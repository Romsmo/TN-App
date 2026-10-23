import 'dart:convert';

import 'package:test/test.dart';
import 'package:tn_core/tn_core.dart';

import 'vec.dart';

/// `misc.json` was written with some German texts double-encoded (UTF-8 read as Latin-1, e.g. "Ã¼ber" for "über").
/// The mistake is in the vector file, not in the app text; undo it before comparing.
String? unmoji(String? text) {
  if (text == null || !text.contains('Ã')) return text;
  return utf8.decode(latin1.encode(text), allowMalformed: true);
}

double _n(dynamic v) => v is String ? double.parse(v) : (v as num).toDouble();

Texts texts(String lang) => Texts(de: textTable('de'), en: textTable('en'), language: lang);

void main() {
  final m = vec('misc');

  test('isPlausiblePosition', () {
    for (final c in m['isPlausiblePosition']) {
      expect(isPlausiblePosition((lat: _n(c['lat']), lng: _n(c['lng']))), c['plausible'], reason: '$c');
    }
  });

  group('duration', () {
    test('parseDuration', () {
      for (final c in m['parseDuration']) {
        expect(parseDuration(c['amount'], DurationUnit.values.byName(c['unit'])), c['seconds'], reason: '$c');
      }
    });
    test('checkDuration', () {
      final l = m['checkDuration']['limits'];
      final limits = ReportLimits(
        supported: l['supported'],
        defaultSeconds: l['defaultSeconds'],
        minSeconds: l['minSeconds'],
        maxSeconds: l['maxSeconds'],
      );
      for (final c in m['checkDuration']['cases']) {
        final r = checkDuration(c['seconds'], limits);
        final e = c['result'];
        expect(r.ok, e['ok'], reason: '$c');
        if (!r.ok) {
          expect(r.reason!.name, e['reason']);
          expect(r.minSeconds, e['minSeconds']);
          expect(r.maxSeconds, e['maxSeconds']);
        }
      }
    });
    test('checkDuration: unsupported limits never guess', () {
      final r = checkDuration(3600, const ReportLimits(supported: false));
      expect(r.ok, false);
      expect(r.reason, DurationProblem.unsupported);
    });
    for (final lang in ['de', 'en']) {
      test('formatDuration $lang', () {
        for (final c in m['formatDuration'][lang]) {
          expect(formatDuration(texts(lang), c['seconds']), c['text'], reason: '$c');
        }
      });
    }
    test('remainingSeconds', () {
      final now = DateTime.parse(m['remainingSeconds']['now']).millisecondsSinceEpoch;
      for (final c in m['remainingSeconds']['cases']) {
        expect(remainingSeconds(c['expiresAt'], now), c['seconds'], reason: '$c');
      }
    });
    test('quick choices', () => expect(quickSeconds, m['quickDurationSeconds']));
  });

  group('speed limit entry', () {
    test('parseLimitValue', () {
      for (final c in m['parseLimitValue']) {
        expect(parseLimitValue(c['text'], SpeedUnit.parse(c['unit'])), c['value'], reason: '$c');
      }
    });
    test('entryLocked', () {
      for (final c in m['entryLocked']) {
        expect(
          entryLocked(lockActive: c['lockActive'], lockEnabled: c['lockEnabled'], deviceSpeedKmh: (c['deviceSpeedKmh'] as num?)?.toDouble()),
          c['locked'],
          reason: '$c',
        );
      }
    });
  });

  group('offline helpers', () {
    test('toggleRegion', () {
      for (final c in m['toggleRegion']) {
        expect(toggleRegion([for (final s in c['selected']) s as String], c['id']), c['result']);
      }
    });
    test('isLeaving', () {
      for (final c in m['isLeaving']) {
        final st = c['settings'];
        final settings = OfflineSettings(
          mode: OfflineMode.parse(st['mode']),
          regions: [for (final r in st['regions']) r as String],
          wifiOnly: true,
        );
        final region = OfflineRegion(id: c['regionId'], storedTiles: c['storedTiles']);
        expect(isLeaving(region, settings), c['leaving'], reason: '$c');
      }
    });
    test('usedBytes', () {
      for (final c in m['usedBytes']) {
        final u = c['usage'];
        expect(usedBytes(StorageUsage(storeBytes: u['storeBytes'], estimatedDeviceBytes: u['estimatedDeviceBytes'])), c['bytes']);
      }
    });
    test('regionName', () {
      for (final c in m['regionName']['de']) {
        final region = OfflineRegion(id: 'x-1', country: c['country']);
        expect(regionName(region, c['language'], builtInCountryName), c['name'], reason: '$c');
      }
    });
  });

  group('filters and catalogs', () {
    test('isTypeHidden', () {
      for (final c in m['isTypeHidden']) {
        expect(isTypeHidden(c['type'], {for (final h in c['hidden']) h as String}), c['isHidden'], reason: '$c');
      }
    });
    test('isCameraType', () {
      for (final c in m['isCameraType']) {
        expect(isCameraType(c['type']), c['camera'], reason: '$c');
      }
    });
    test('mapReportTypes and driveReportTypes', () {
      for (final c in m['mapReportTypes']) {
        expect(mapReportTypes(c['camerasActive'], c['maxLevel'] == null ? null : CameraLevel.parse(c['maxLevel'])), c['types'], reason: '$c');
      }
      for (final c in m['driveReportTypes']) {
        expect(driveReportTypes(c['camerasActive'], c['maxLevel'] == null ? null : CameraLevel.parse(c['maxLevel'])), c['types'], reason: '$c');
      }
    });
  });

  test('normalizeServerAddress', () {
    for (final c in m['normalizeServerAddress']) {
      final r = normalizeServerAddress(c['input'], allowInsecure: c['allowInsecure']);
      final e = c['result'];
      if (e['ok'] == true) {
        expect(r, isA<AddressOk>(), reason: '$c');
        expect((r as AddressOk).url, e['url'], reason: '$c');
      } else {
        expect(r, isA<AddressError>(), reason: '$c');
        expect((r as AddressError).reason.name, e['reason'], reason: '$c');
      }
    }
  });

  test('shouldSync', () {
    for (final c in m['shouldSync']) {
      expect(shouldSync(wifiOnly: c['wifiOnly'], onWifi: c['onWifi'], bytesPending: c['bytesPending']), c['sync'], reason: '$c');
    }
  });

  test('emergencyOf', () {
    for (final c in m['emergencyOf']) {
      final s = c['sync'];
      final sync = s == null
          ? null
          : SyncStatus(connection: Connection.values.byName(s['connection']), staticDataVersion: s['staticDataVersion']);
      final r = emergencyOf(phase: Phase.values.byName(c['phase']), sync: sync, waitingForWifi: c['waitingForWifi']);
      expect(r?.name, c['emergency'], reason: '$c');
    }
  });

  group('settings', () {
    Map<String, Object?> j(Settings s) => s.toJson();
    test('defaults', () => expect(j(defaultSettings), m['settings']['defaults']));
    test('parse', () {
      for (final c in m['settings']['parse']) {
        expect(j(parseSettings(c['raw'])), c['settings'], reason: '${c['raw']}');
      }
    });
    test('a build without the option to switch the lock off keeps it on', () {
      expect(parseSettings('{"driveLockEnabled":false}', allowDisableDriveLock: false).driveLockEnabled, true);
    });
    test('encode/parse round trip', () {
      final s = defaultSettings.copyWith(serverAddress: 'https://x.org', speedUnit: SpeedUnit.mph, warnScale: 1.5, camerasEnabled: true);
      expect(j(parseSettings(encodeSettings(s))), j(s));
    });
  });

  group('texts for the waiting state', () {
    test('pendingText', () {
      for (final c in m['pendingText']) {
        expect(
          pendingText(texts('de'), pending: c['pending'], waitingForWifi: c['waitingForWifi'], offline: c['offline']),
          unmoji(c['text']),
          reason: '$c',
        );
      }
    });
    test('rejectedText', () {
      for (final c in m['rejectedText']) {
        expect(rejectedText(texts('de'), c['count']), unmoji(c['text']), reason: '$c');
      }
    });
  });
}
