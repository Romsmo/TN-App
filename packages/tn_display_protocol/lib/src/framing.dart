/// Raw (non-CBOR) frames of the OTA (`0007`) and Asset (`0008`) characteristics, plus the
/// image checksum. These carry file bytes, so every byte counts: the first byte is an
/// opcode, the rest is payload. Writes are "write without response"; the device notifies
/// progress / result on the same characteristic.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// Payload bytes per data frame the tools use (opcode + 230 = 231 B, inside a 247-byte MTU).
const int defaultChunkBytes = 230;

/// SHA-256 of an image, as the OTA `begin` frame needs it.
Uint8List sha256Of(List<int> data) => Uint8List.fromList(crypto.sha256.convert(data).bytes);

abstract final class _Op {
  static const int begin = 0x01;
  static const int data = 0x02;
  static const int end = 0x03;
  static const int abort = 0x04;
  static const int progress = 0x10;
  static const int ok = 0x11;
  static const int error = 0x12;
}

Iterable<Uint8List> _chunks(Uint8List bytes, int chunk) sync* {
  if (chunk <= 0) throw ArgumentError.value(chunk, 'chunk');
  for (var off = 0; off < bytes.length; off += chunk) {
    final end = off + chunk < bytes.length ? off + chunk : bytes.length;
    final f = Uint8List(1 + end - off);
    f[0] = _Op.data;
    f.setRange(1, f.length, bytes, off);
    yield f;
  }
}

/// Firmware update frames. Order: [begin] → wait for the first [OtaNotify] progress (0 bytes —
/// the device sends it once it has erased the target slot, which takes seconds) → all
/// [dataFrames] in order, pacing the writes → [end]. A disconnect aborts the update.
abstract final class OtaFrames {
  /// `[0x01][len u32 LE][sha256 x32]`.
  static Uint8List begin(int totalBytes, Uint8List sha256) {
    if (sha256.length != 32) throw ArgumentError('sha256 must be 32 bytes');
    final f = Uint8List(1 + 4 + 32);
    f[0] = _Op.begin;
    ByteData.sublistView(f).setUint32(1, totalBytes, Endian.little);
    f.setRange(5, 37, sha256);
    return f;
  }

  static Uint8List beginForImage(Uint8List image) => begin(image.length, sha256Of(image));

  static Iterable<Uint8List> dataFrames(Uint8List image, {int chunk = defaultChunkBytes}) =>
      _chunks(image, chunk);

  static Uint8List end() => Uint8List.fromList([_Op.end]);
  static Uint8List abort() => Uint8List.fromList([_Op.abort]);
}

sealed class OtaNotify {
  const OtaNotify();

  /// Parses a notification; returns null for an unknown opcode.
  static OtaNotify? parse(List<int> b) {
    if (b.isEmpty) return null;
    switch (b[0]) {
      case _Op.progress:
        if (b.length < 5) return null;
        return OtaProgress(b[1] | (b[2] << 8) | (b[3] << 16) | (b[4] << 24));
      case _Op.ok:
        return const OtaAccepted();
      case _Op.error:
        return OtaError(b.length > 1 ? b[1] : 0);
      default:
        return null;
    }
  }
}

/// Bytes received so far (sent every ~32 KB; the first one, with 0, means "slot erased, go").
class OtaProgress extends OtaNotify {
  const OtaProgress(this.receivedBytes);
  final int receivedBytes;
}

/// Image verified and installed; the device reboots about 0.6 s later.
class OtaAccepted extends OtaNotify {
  const OtaAccepted();
}

/// Aborted. Codes: 1 no OTA slot · 2 begin failed · 3 flash write failed · 4 SHA-256
/// mismatch · 5 finalise failed; 0 = the device did not send a code.
class OtaError extends OtaNotify {
  const OtaError(this.code);
  final int code;
}

/// File upload to the SD card. Same shape as OTA; the path is relative to the card root
/// and parent directories are created.
abstract final class AssetFrames {
  /// `[0x01][path length u8][path bytes]` — the path must be 1..255 UTF-8 bytes.
  static Uint8List begin(String path) {
    final p = utf8.encode(path);
    if (p.isEmpty || p.length > 255) throw ArgumentError.value(path, 'path', 'must be 1..255 bytes');
    final f = Uint8List(2 + p.length);
    f[0] = _Op.begin;
    f[1] = p.length;
    f.setRange(2, f.length, p);
    return f;
  }

  static Iterable<Uint8List> dataFrames(Uint8List file, {int chunk = defaultChunkBytes}) =>
      _chunks(file, chunk);

  static Uint8List end() => Uint8List.fromList([_Op.end]);
  static Uint8List abort() => Uint8List.fromList([_Op.abort]);
}

/// Asset notifications: `0x11` ok, `0x12` error.
enum AssetResult { ok, error }

AssetResult? parseAssetNotify(List<int> b) {
  if (b.isEmpty) return null;
  if (b[0] == _Op.ok) return AssetResult.ok;
  if (b[0] == _Op.error) return AssetResult.error;
  return null;
}
