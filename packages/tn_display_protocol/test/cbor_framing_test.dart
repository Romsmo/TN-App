import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tn_display_protocol/tn_display_protocol.dart';

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List unhex(String h) => Uint8List.fromList([
      for (var i = 0; i + 1 < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16),
    ]);

void main() {
  group('CBOR encoder', () {
    final cases = <Object?, String>{
      0: '00',
      23: '17',
      24: '1818',
      255: '18ff',
      256: '190100',
      65535: '19ffff',
      65536: '1a00010000',
      4294967295: '1affffffff',
      4294967296: '1b0000000100000000',
      -1: '20',
      -24: '37',
      -25: '3818',
      -210: '38d1',
      true: 'f5',
      false: 'f4',
      null: 'f6',
      'a': '6161',
    };
    cases.forEach((v, h) => test('$v -> $h', () => expect(hex(cborEncode(v)), h)));

    test('a nested map keeps insertion order', () {
      expect(hex(cborEncode(<int, Object?>{0: 1, 2: <Object?>[1, 2], 1: <int, Object?>{0: true}})),
          'a3000102820102 01a100f5'.replaceAll(' ', ''));
    });
    test('rejects text keys', () {
      expect(() => cborEncode(<Object?, Object?>{'a': 1}), throwsArgumentError);
    });
  });

  group('CBOR decoder', () {
    test('round trips what it encodes', () {
      final m = <int, Object?>{0: 1, 1: -5, 2: 'hi', 3: <Object?>[1, 2, 3], 4: <int, Object?>{9: false}};
      expect(cborDecode(cborEncode(m)), equals(m));
    });
    test('skips entries with a text key and unknown simple values stay parseable', () {
      // {0:1, "x": 5, 2: 7}
      final m = cborDecode(unhex('a3000161780502' '07')) as Map<int, Object?>;
      expect(m, equals(<int, Object?>{0: 1, 2: 7}));
    });
    test('truncated input throws', () {
      expect(() => cborDecode(unhex('a50001')), throwsFormatException);
      expect(() => cborDecode(unhex('1a0000')), throwsFormatException);
      expect(() => cborDecode(Uint8List(0)), throwsFormatException);
    });
    test('indefinite lengths are rejected', () {
      expect(() => cborDecode(unhex('9f0102ff')), throwsFormatException);
    });
    test('a huge claimed array does not allocate', () {
      expect(() => cborDecode(unhex('9affffffff')), throwsFormatException);
    });
    test('nesting deeper than 8 is rejected', () {
      expect(() => cborDecode(unhex('81818181818181818181818100')), throwsFormatException);
    });
    test('payload that is not a map is not a message', () {
      expect(DisplayState.tryDecode(unhex('01')), isNull);
      expect(() => DeviceSettings.decode(unhex('01')), throwsFormatException);
    });
  });

  group('OTA framing', () {
    test('SHA-256 of "abc" (FIPS 180-2 test vector)', () {
      expect(hex(sha256Of('abc'.codeUnits)),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    test('begin frame = op, uint32 LE length, 32-byte digest', () {
      final image = Uint8List.fromList(List<int>.generate(1000, (i) => i & 0xff));
      final f = OtaFrames.beginForImage(image);
      expect(f.length, 37);
      expect(f[0], 0x01);
      expect(f.sublist(1, 5), [0xe8, 0x03, 0x00, 0x00]); // 1000 little endian
      expect(f.sublist(5), sha256Of(image));
    });

    test('data frames: 230-byte chunks, op 0x02, in order, nothing lost', () {
      final image = Uint8List.fromList(List<int>.generate(461, (i) => i & 0xff));
      final frames = OtaFrames.dataFrames(image).toList();
      expect(frames.map((f) => f.length), [231, 231, 2]);
      expect(frames.every((f) => f[0] == 0x02), isTrue);
      expect(frames.expand((f) => f.skip(1)).toList(), image);
    });

    test('end and abort', () {
      expect(OtaFrames.end(), [0x03]);
      expect(OtaFrames.abort(), [0x04]);
    });

    test('notifications', () {
      final p = OtaNotify.parse([0x10, 0x00, 0x80, 0x00, 0x00]);
      expect(p, isA<OtaProgress>());
      expect((p! as OtaProgress).receivedBytes, 0x8000);
      expect(OtaNotify.parse([0x11]), isA<OtaAccepted>());
      expect((OtaNotify.parse([0x12, 4])! as OtaError).code, 4);
      expect((OtaNotify.parse([0x12])! as OtaError).code, 0); // older firmware sent no code
      expect(OtaNotify.parse([0x99]), isNull);
      expect(OtaNotify.parse([]), isNull);
    });
  });

  group('Asset framing', () {
    test('begin frame = op, path length, path', () {
      final f = AssetFrames.begin('audio/tones/warn.wav');
      expect(f[0], 0x01);
      expect(f[1], 20);
      expect(String.fromCharCodes(f.sublist(2)), 'audio/tones/warn.wav');
    });
    test('path limits', () {
      expect(() => AssetFrames.begin(''), throwsArgumentError);
      expect(() => AssetFrames.begin('x' * 256), throwsArgumentError);
      expect(AssetFrames.begin('x' * 255).length, 257);
    });
    test('notifications', () {
      expect(parseAssetNotify([0x11]), AssetResult.ok);
      expect(parseAssetNotify([0x12]), AssetResult.error);
      expect(parseAssetNotify([0x10]), isNull);
    });
  });

  group('UUIDs', () {
    test('slot -> UUID', () {
      expect(uuidForSlot(Slot.state), '079a0001-d673-469c-98a0-12c0c5eb43b3');
      expect(uuidForSlot(Slot.asset), '079a0008-d673-469c-98a0-12c0c5eb43b3');
    });
  });

  group('encode limits', () {
    test('a State over the payload limit is refused', () {
      // 4 + 4 signs fit; a hazard + cue + everything still fits; force overflow with a long list
      final s = DisplayState(
        leftSigns: List<int>.filled(4, 65535),
        rightSigns: List<int>.filled(4, 65535),
        audioCue: const AudioCue(seq: 4294967295, hazardType: 10, distanceM: 4294967295, speedValue: 4294967295),
        epochS: 4294967295,
        networkPeers: 4294967295,
        stateSeq: 4294967295,
      );
      expect(s.encode().length, lessThanOrEqualTo(maxPayloadBytes));
    });
  });
}
