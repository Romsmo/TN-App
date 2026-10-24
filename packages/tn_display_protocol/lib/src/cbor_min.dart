/// A deliberately tiny CBOR codec covering exactly what the protocol uses: unsigned and
/// negative integers, booleans, null, text, bytes, arrays and maps. It mirrors the
/// device's own codec (core/codec/cbor.h) and has no dependencies.
///
/// Decoding is tolerant the way the protocol demands: unknown keys and values of any
/// supported type are parsed and can simply be ignored by the caller.
library;

import 'dart:convert';
import 'dart:typed_data';

const int _maxDepth = 8;

/// Encodes a CBOR value. Supported: `int`, `bool`, `null`, `String`, `Uint8List`,
/// `List<Object?>`, `Map<int, Object?>` (entries are written in iteration order).
Uint8List cborEncode(Object? value) {
  final b = BytesBuilder(copy: false);
  _enc(b, value);
  return b.toBytes();
}

void _head(BytesBuilder b, int major, int v) {
  final m = major << 5;
  if (v < 0) throw ArgumentError('negative length/value $v');
  if (v < 24) {
    b.addByte(m | v);
  } else if (v < 0x100) {
    b.addByte(m | 24);
    b.addByte(v);
  } else if (v < 0x10000) {
    b.addByte(m | 25);
    b.addByte(v >> 8);
    b.addByte(v & 0xff);
  } else if (v < 0x100000000) {
    b.addByte(m | 26);
    for (var s = 24; s >= 0; s -= 8) {
      b.addByte((v >> s) & 0xff);
    }
  } else {
    b.addByte(m | 27);
    for (var s = 56; s >= 0; s -= 8) {
      b.addByte((v >> s) & 0xff);
    }
  }
}

void _enc(BytesBuilder b, Object? v) {
  if (v == null) {
    b.addByte(0xf6);
  } else if (v is bool) {
    b.addByte(v ? 0xf5 : 0xf4);
  } else if (v is int) {
    if (v >= 0) {
      _head(b, 0, v);
    } else {
      _head(b, 1, -1 - v);
    }
  } else if (v is String) {
    final u = utf8.encode(v);
    _head(b, 3, u.length);
    b.add(u);
  } else if (v is Uint8List) {
    _head(b, 2, v.length);
    b.add(v);
  } else if (v is List) {
    _head(b, 4, v.length);
    for (final e in v) {
      _enc(b, e);
    }
  } else if (v is Map) {
    _head(b, 5, v.length);
    v.forEach((k, val) {
      if (k is! int) throw ArgumentError('only integer map keys are supported, got $k');
      _enc(b, k);
      _enc(b, val);
    });
  } else {
    throw ArgumentError('unsupported CBOR type ${v.runtimeType}');
  }
}

/// Decodes one CBOR value. Maps come back as `Map<int, Object?>`; entries with a
/// non-integer key are parsed and dropped. Throws [FormatException] on malformed or
/// truncated input, indefinite lengths, or nesting deeper than 8.
Object? cborDecode(Uint8List bytes) {
  final r = _Reader(bytes);
  final v = r.read(0);
  return v;
}

class _Reader {
  _Reader(this.b);
  final Uint8List b;
  int p = 0;

  int _byte() {
    if (p >= b.length) throw const FormatException('CBOR: truncated');
    return b[p++];
  }

  int _arg(int info) {
    if (info < 24) return info;
    int n;
    switch (info) {
      case 24:
        n = 1;
      case 25:
        n = 2;
      case 26:
        n = 4;
      case 27:
        n = 8;
      default:
        throw const FormatException('CBOR: indefinite or reserved length');
    }
    if (p + n > b.length) throw const FormatException('CBOR: truncated');
    var v = 0;
    for (var i = 0; i < n; i++) {
      v = (v << 8) | b[p++];
    }
    return v;
  }

  Object? read(int depth) {
    if (depth > _maxDepth) throw const FormatException('CBOR: nested too deep');
    final ib = _byte();
    final major = ib >> 5;
    final info = ib & 31;
    switch (major) {
      case 0:
        return _arg(info);
      case 1:
        return -1 - _arg(info);
      case 2:
        final n = _arg(info);
        if (p + n > b.length) throw const FormatException('CBOR: truncated');
        final out = Uint8List.sublistView(b, p, p + n);
        p += n;
        return out;
      case 3:
        final n = _arg(info);
        if (p + n > b.length) throw const FormatException('CBOR: truncated');
        final s = utf8.decode(b.sublist(p, p + n), allowMalformed: true);
        p += n;
        return s;
      case 4:
        final n = _arg(info);
        if (n > b.length - p) throw const FormatException('CBOR: truncated');
        return <Object?>[for (var i = 0; i < n; i++) read(depth + 1)];
      case 5:
        final n = _arg(info);
        if (n > b.length - p) throw const FormatException('CBOR: truncated');
        final m = <int, Object?>{};
        for (var i = 0; i < n; i++) {
          final k = read(depth + 1);
          final v = read(depth + 1);
          if (k is int) m[k] = v;
        }
        return m;
      case 6:
        _arg(info); // tag: ignore, read the tagged value
        return read(depth + 1);
      default: // major 7
        if (info == 20) return false;
        if (info == 21) return true;
        if (info == 22 || info == 23) return null;
        if (info == 25) {
          _arg(info);
          return 0.0; // half float: value not needed by this protocol
        }
        if (info == 26) {
          if (p + 4 > b.length) throw const FormatException('CBOR: truncated');
          final v = ByteData.sublistView(b, p, p + 4).getFloat32(0);
          p += 4;
          return v;
        }
        if (info == 27) {
          if (p + 8 > b.length) throw const FormatException('CBOR: truncated');
          final v = ByteData.sublistView(b, p, p + 8).getFloat64(0);
          p += 8;
          return v;
        }
        throw const FormatException('CBOR: unsupported simple value');
    }
  }
}
