// Runs every golden vector of docs/contract/vectors/ against this package.
// The vectors are produced by the firmware's real codec (test/gen_vectors.cpp):
//  * every vector must decode to exactly "decoded" (or fail, if decodeOk is false);
//  * "canonical" vectors of app->device / both-way characteristics must re-encode to
//    the same bytes.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tn_display_protocol/tn_display_protocol.dart';

const _dir = 'contract/vectors';

Uint8List unhex(String h) => Uint8List.fromList([
      for (var i = 0; i + 1 < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16),
    ]);

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Map<String, Object?> _load(String file) =>
    jsonDecode(File('$_dir/$file').readAsStringSync()) as Map<String, Object?>;

List<Map<String, Object?>> vectors(String file) =>
    (_load(file)['vectors']! as List<Object?>).cast<Map<String, Object?>>();

void main() {
  group('State (0001)', () {
    for (final v in vectors('state.json')) {
      test(v['name']! as String, () {
        final bytes = unhex(v['hex']! as String);
        final s = DisplayState.tryDecode(bytes);
        if (v['decodeOk'] == false) {
          expect(s, isNull);
          return;
        }
        expect(s, isNotNull);
        expect(s!.toJson(), equals(v['decoded']));
        if (v['canonical'] == true) expect(hex(s.encode()), v['hex']);
      });
    }
  });

  group('Event (0002)', () {
    for (final v in vectors('event.json')) {
      test(v['name']! as String, () {
        final e = DeviceEvent.tryDecode(unhex(v['hex']! as String));
        expect(e, isNotNull);
        expect(e!.toJson(), equals(v['decoded']));
      });
    }
    test('unknown tag is dropped, not an error', () {
      expect(DeviceEvent.decode(cborEncode(<int, Object?>{0: 1, 1: 99})), isNull);
    });
  });

  group('DeviceInfo (0003)', () {
    for (final v in vectors('device-info.json')) {
      test(v['name']! as String, () {
        final bytes = unhex(v['hex']! as String);
        final d = DeviceInfo.decode(bytes);
        expect(d.toJson(), equals(v['decoded']));
        expect(hex(d.encode()), v['hex']);
        expect(d.has(Caps.ota), isTrue);
        expect(d.has(Caps.imu), isFalse);
      });
    }
  });

  group('Settings (0004)', () {
    for (final v in vectors('settings.json')) {
      test(v['name']! as String, () {
        final bytes = unhex(v['hex']! as String);
        final s = DeviceSettings.decode(bytes);
        expect(s.toJson(), equals(v['decoded']));
        if (v['canonical'] == true) expect(hex(s.encode()), v['hex']);
      });
    }
    test('filter helper: unknown types are always shown', () {
      const s = DeviceSettings(filterBits: 0x0000);
      expect(s.warnsAbout(7), isFalse);
      expect(s.warnsAbout(11), isFalse); // 11 < 16: covered by the bitmask
      expect(s.warnsAbout(16), isTrue);
    });
  });

  group('Time (0005)', () {
    for (final v in vectors('time.json')) {
      test(v['name']! as String, () {
        final bytes = unhex(v['hex']! as String);
        final t = TimeSync.decode(bytes);
        expect(t.toJson(), equals(v['decoded']));
        expect(hex(t.encode()), v['hex']);
      });
    }
  });

  group('UiConfig (0006)', () {
    for (final v in vectors('ui-config.json')) {
      test(v['name']! as String, () {
        final bytes = unhex(v['hex']! as String);
        final c = UiConfig.decode(bytes);
        expect(c.toJson(), equals(v['decoded']));
        expect(hex(c.encode()), v['hex']);
      });
    }
    test('bit helpers', () {
      final c = const UiConfig().withBit(UiBit.meldenPage, false);
      expect(c.isOn(UiBit.meldenPage), isFalse);
      expect(c.isOn(UiBit.hazardOverlay), isTrue);
    });
  });

  group('constants.json', () {
    test('match the Dart constants', () {
      final c = _load('constants.json');
      expect(c['protocolVersion'], protocolVersion);
      expect(c['maxPayloadBytes'], maxPayloadBytes);
      expect(c['uiConfigBitCount'], UiBit.count);
      expect(c['hazardTypeMaxKnown'], HazardType.maxKnown);
      expect(c['signListMax'], signListMax);
    });
  });

  group('categories.json', () {
    test('ids and keys match HazardType', () {
      const byKey = {
        'FixedSpeedCamera': HazardType.fixedSpeedCamera,
        'MobileSpeedCamera': HazardType.mobileSpeedCamera,
        'TrailerCamera': HazardType.trailerCamera,
        'RedLightCamera': HazardType.redLightCamera,
        'DistanceControl': HazardType.distanceControl,
        'Traffic': HazardType.traffic,
        'Ice': HazardType.ice,
        'Accident': HazardType.accident,
        'Construction': HazardType.construction,
        'Breakdown': HazardType.breakdown,
        'Obstacle': HazardType.obstacle,
      };
      final cats = (_load('categories.json')['categories']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(cats, hasLength(byKey.length));
      for (final c in cats) {
        expect(byKey[c['key']], c['id'], reason: '${c['key']}');
        expect(c['filterBit'], c['id']);
        expect(HazardType.isSpeedCamera(c['id']! as int), c['group'] == 'speedCamera');
      }
    });
  });
}
