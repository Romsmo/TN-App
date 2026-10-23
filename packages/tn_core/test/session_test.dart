import 'package:test/test.dart';
import 'package:tn_core/tn_core.dart';

import 'vec.dart';

const origin = LatLng(52.5, 13.4);

class RecordingFeedback implements Feedback {
  final List<String> log = [];

  @override
  void warn(WarnLevel level, String text, {required bool sound, required bool voice}) =>
      log.add('warn:${level.name}:"$text":sound=$sound:voice=$voice');

  @override
  void confirm({required bool sound}) => log.add('confirm:sound=$sound');

  @override
  void prompt({required bool sound}) => log.add('prompt:sound=$sound');

  @override
  void silence() => log.add('silence');

  List<String> take() {
    final out = List.of(log);
    log.clear();
    return out;
  }
}

class FakeData implements DriveDataSource {
  FakeData(this.items, this.limitValue, this.covered);
  final List<NearbyItem> items;
  final int? limitValue;
  final bool covered;

  @override
  Future<List<NearbyItem>> nearby(double lat, double lng, double radiusM) async => items;

  @override
  Future<SpeedLimitAnswer?> speedLimit(double lat, double lng, double? heading) async =>
      limitValue == null ? null : SpeedLimitAnswer(value: limitValue!, unit: SpeedUnit.kmh, segmentId: 's');

  @override
  Future<bool> limitCovered(double lat, double lng) async => covered;
}

HazardItem hazardAt(double northM, {String id = 'h1', String type = 'accident', bool pending = false}) {
  final p = destination(origin, 0, northM);
  return HazardItem(
    id: id,
    hazardType: type,
    lat: p.lat,
    lng: p.lng,
    distanceMeters: 0,
    expiresAt: '2030-01-01T00:00:00Z',
    confirmCount: 2,
    denyCount: 0,
    pending: pending,
  );
}

class Harness {
  Harness({List<NearbyItem>? items, int? limitValue = 100, bool covered = true, DriveSettings? settings, bool submitOk = true, Texts? texts}) {
    this.texts = texts ?? makeTexts('en');
    current = settings ?? const DriveSettings();
    feedback = RecordingFeedback();
    session = DriveSession(DriveDeps(
      data: FakeData(items ?? [hazardAt(1500)], limitValue, covered),
      feedback: feedback,
      texts: this.texts,
      getSettings: () => current,
      now: () => now,
      submitReport: (type, pos) async {
        reports.add({'type': type, 'lat': pos.lat, 'lng': pos.lng});
        return submitOk;
      },
      vote: (id, still) async {
        votes.add({'reportId': id, 'stillThere': still});
        return true;
      },
    ));
  }

  late final Texts texts;
  late DriveSettings current;
  late final RecordingFeedback feedback;
  late final DriveSession session;
  int now = 1000000;
  final reports = <Map<String, Object?>>[];
  final votes = <Map<String, Object?>>[];

  Fix at(double northM, double? speedKmh, double? heading) {
    final p = destination(origin, 0, northM);
    return Fix(lat: p.lat, lng: p.lng, speedKmh: speedKmh, heading: heading, t: now);
  }

  Future<void> flush() async {
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// A fix (the first reading of the nearby data is asynchronous, so the same fix is delivered a second time once it has
  /// arrived: the recorded vectors show warnings at the first fix), then the clock advances and the session ticks.
  Future<void> fix(double northM, double? speedKmh, double? heading, {int advanceMs = 1000, bool deliverTwice = true}) async {
    session.onFix(at(northM, speedKmh, heading));
    await flush();
    if (deliverTwice) session.onFix(at(northM, speedKmh, heading));
    now += advanceMs;
    session.tick();
  }

  Future<void> drive(double from, double to, {double speed = 100, double step = 25}) async {
    for (var m = from; m <= to; m += step) {
      await fix(m, speed, 0);
    }
  }
}

Texts makeTexts(String lang) => Texts(de: textTable('de'), en: textTable('en'), language: lang);

Map<String, Object?> snapJson(DriveSnapshot s) => {
      'active': s.active,
      'speedKmh': s.speedKmh,
      'heading': s.heading,
      'limit': s.limit == null ? null : {'value': s.limit!.value, 'unit': s.limit!.unit.name},
      'limitUnavailable': s.limitUnavailable,
      'speedState': s.speedState.name,
      'warnings': [
        for (final w in s.warnings)
          {'id': w.id, 'level': w.level.name, 'kind': w.kind.name, 'category': w.category, 'label': w.label, 'distanceM': w.distanceM},
      ],
      'prompt': s.prompt == null ? null : {'id': s.prompt!.id, 'hazardType': s.prompt!.hazardType},
      'muted': s.muted,
      'locked': s.locked,
      'speedLocked': s.speedLocked,
      'gpsLost': s.gpsLost,
    };

void main() {
  final v = vec('drive-session');

  test('constants match the vector constants', () {
    final c = v['constants'];
    expect(warningShownMs, c['warningShownMs']);
    expect(promptShownMs, c['promptShownMs']);
    expect(promptMinGapMs, c['promptMinGapMs']);
    expect(speechMinGapMs, c['speechMinGapMs']);
    expect(gpsLostAfterMs, c['gpsLostAfterMs']);
    expect(maxReportFixAgeMs, c['maxReportFixAgeMs']);
    expect(refreshMovedM, c['refreshMovedM']);
    expect(refreshAfterMs, c['refreshAfterMs']);
    expect(limitRefreshMovedM, c['limitRefreshMovedM']);
    expect(limitRefreshAfterMs, c['limitRefreshAfterMs']);
  });

  final scenarios = v['scenarios'] as List;
  for (var idx = 0; idx < scenarios.length; idx++) {
    final s = scenarios[idx] as Map;
    test('scenario $idx: ${(s['name'] as String).substring(0, ((s['name'] as String).length).clamp(0, 70))}', () async {
      final name = s['name'] as String;
      final sj = s['settings'] as Map?;
      final settings = DriveSettings(
        unit: SpeedUnit.parse(sj?['unit']),
        sound: sj?['sound'] ?? true,
        voice: sj?['voice'] ?? true,
        warnOff: [
          for (final w in (sj?['warnOff'] ?? s['warnOff'] ?? const []) as List) w as String,
        ],
        scale: ((sj?['scale'] ?? 1) as num).toDouble(),
        lockEnabled: sj?['lockEnabled'] ?? true,
      );
      List<NearbyItem>? items;
      if (s['items'] != null) {
        items = [
          for (final i in s['items'] as List)
            i['northM'] != null
                ? hazardAt((i['northM'] as num).toDouble(), id: i['id'], type: i['type'], pending: i['pending'] == true)
                : HazardItem(
                    id: i['id'],
                    hazardType: i['type'],
                    lat: (i['lat'] as num).toDouble(),
                    lng: (i['lng'] as num).toDouble(),
                    distanceMeters: 0,
                    expiresAt: '2030-01-01T00:00:00Z',
                    confirmCount: 2,
                    denyCount: 0,
                    pending: i['pending'] == true,
                  ),
        ];
      }
      int? limitValue = s.containsKey('limit') ? (s['limit'] as num).toInt() : 100;
      var covered = true;
      if (name.startsWith('no limit and the offline data does not cover')) {
        limitValue = null;
        covered = false;
      } else if (name.startsWith('no limit but the spot is covered')) {
        limitValue = null;
      }
      final h = Harness(
        items: items,
        limitValue: limitValue,
        covered: covered,
        settings: settings,
        submitOk: !name.startsWith('storing the report failed'),
      );

      final steps = (s['steps'] as List?) ?? const [];

      if (steps.isEmpty) {
        // anyWarning / anyPrompt scenarios: drive past the hazard and watch
        h.session.start();
        var anyWarning = false;
        var anyPrompt = false;
        for (var m = 0.0; m <= 1800; m += 25) {
          await h.fix(m, 100, 0);
          final snap = h.session.snapshot;
          if (snap.warnings.isNotEmpty) anyWarning = true;
          if (snap.prompt != null) anyPrompt = true;
        }
        expect(anyWarning, s['anyWarning']);
        expect(anyPrompt, s['anyPrompt']);
        return;
      }

      // Setup the vector does not record: scenarios that begin after the drive has started.
      if ((steps.first['action'] as Map)['type'] != 'start') {
        h.session.start();
        if (idx == 3) {
          for (final m in [850.0, 1300.0, 1550.0]) {
            await h.fix(m, 100, 0);
          }
        } else if (name.startsWith('storing the report failed')) {
          await h.fix(0, 50, 0);
        }
        h.feedback.take();
      }

      var i = 0;
      for (final st in steps) {
        final a = st['action'] as Map;
        switch (a['type']) {
          case 'start':
            h.session.start();
          case 'stop':
            h.session.stop();
            await h.flush();
          case 'fix':
            await h.fix((a['northM'] as num).toDouble(), (a['speedKmh'] as num?)?.toDouble(), (a['heading'] as num?)?.toDouble(),
                advanceMs: name.startsWith('GPS lost') ? 0 : 1000);
          case 'tick':
            h.now += (a['afterMs'] as num).toInt();
            h.session.tick();
          case 'setMuted':
            h.session.setMuted(a['muted'] as bool);
          case 'answerPrompt':
            await h.session.answerPrompt(a['stillThere'] as bool);
            await h.flush();
          case 'report':
            if (a['afterMs'] != null) h.now += (a['afterMs'] as num).toInt();
            final r = await h.session.report((a['type_'] as String?) ?? 'traffic');
            expect(r, a['result'], reason: 'report result at step $i');
          default:
            fail('unknown action ${a['type']}');
        }
        expect(h.feedback.take(), st['feedback'], reason: 'feedback at step $i');
        expect(snapJson(h.session.snapshot), st['snapshot'], reason: 'snapshot at step $i');
        i++;
      }

      if (s['votes'] != null) expect(h.votes, s['votes']);
      if (s['reports'] != null) {
        expect(h.reports.length, (s['reports'] as List).length);
        for (var k = 0; k < h.reports.length; k++) {
          final e = (s['reports'] as List)[k];
          expect(h.reports[k]['type'], e['type']);
          expect(h.reports[k]['lat'] as double, closeTo(e['lat'], 1e-6));
          expect(h.reports[k]['lng'] as double, closeTo(e['lng'], 1e-6));
        }
      }
      if (s.containsKey('reportAfterStop')) {
        expect(await h.session.report('traffic'), s['reportAfterStop']);
      }
    });
  }

  group('spoken text', () {
    for (final c in v['spokenText']) {
      test('${c['language']} ${c['level']} ${c['kind']} ${c['distanceM']}', () {
        final texts = makeTexts(c['language']);
        final kind = c['kind'] == 'zone' ? WarnKind.zone : WarnKind.point;
        final level = c['level'] == 'first' ? WarnLevel.first : WarnLevel.second;
        expect(spokenText(texts, c['label'], level, kind, c['distanceM']), c['text']);
      });
    }
  });
}
