import 'package:test/test.dart';
import 'package:tn_core/tn_core.dart';

import 'vec.dart';

Fix fixOf(dynamic m) => Fix(
      lat: (m['lat'] as num).toDouble(),
      lng: (m['lng'] as num).toDouble(),
      speedKmh: (m['speedKmh'] as num?)?.toDouble(),
      heading: (m['heading'] as num?)?.toDouble(),
      t: (m['t'] as num).toInt(),
    );

WarnCandidate candidateOf(dynamic m) {
  if (m['kind'] == 'zone') {
    return ZoneCandidate(
      id: m['id'],
      category: m['category'],
      ring: [
        for (final p in m['ring']) [(p[0] as num).toDouble(), (p[1] as num).toDouble()]
      ],
    );
  }
  return PointCandidate(
    id: m['id'],
    category: m['category'],
    source: m['source'],
    lat: (m['lat'] as num).toDouble(),
    lng: (m['lng'] as num).toDouble(),
  );
}

Map<String, Object?> eventJson(WarnEvent e) {
  final base = <String, Object?>{
    'id': e.id,
    'kind': e.kind.name,
    'category': e.category,
    'source': e.source.name,
  };
  if (e is WarnNow) {
    return {'type': 'warn', 'level': e.level.name, ...base, 'distanceM': e.distanceM};
  }
  return {'type': 'passed', ...base, 'reachedSecond': (e as Passed).reachedSecond};
}

WarnConfig configOf(dynamic c) => WarnConfig(
      leadFirstS: (c['leadFirstS'] as num).toDouble(),
      leadSecondS: (c['leadSecondS'] as num).toDouble(),
      minFirstM: (c['minFirstM'] as num).toDouble(),
      maxFirstM: (c['maxFirstM'] as num).toDouble(),
      minSecondM: (c['minSecondM'] as num).toDouble(),
      scale: (c['scale'] as num).toDouble(),
      minSpeedKmh: (c['minSpeedKmh'] as num).toDouble(),
      lateralMinM: (c['lateralMinM'] as num).toDouble(),
      lateralMaxM: (c['lateralMaxM'] as num).toDouble(),
      lateralFactor: (c['lateralFactor'] as num).toDouble(),
      passedM: (c['passedM'] as num).toDouble(),
    );

void main() {
  final th = vec('warning-thresholds');
  group('warning thresholds', () {
    test('default config equals the vector config', () {
      final c = configOf(th['config']);
      expect(c.leadFirstS, defaultWarnConfig.leadFirstS);
      expect(c.leadSecondS, defaultWarnConfig.leadSecondS);
      expect(c.minFirstM, defaultWarnConfig.minFirstM);
      expect(c.maxFirstM, defaultWarnConfig.maxFirstM);
      expect(c.minSecondM, defaultWarnConfig.minSecondM);
      expect(c.minSpeedKmh, defaultWarnConfig.minSpeedKmh);
      expect(c.lateralMinM, defaultWarnConfig.lateralMinM);
      expect(c.lateralMaxM, defaultWarnConfig.lateralMaxM);
      expect(c.lateralFactor, defaultWarnConfig.lateralFactor);
      expect(c.passedM, defaultWarnConfig.passedM);
    });
    for (final c in th['table']) {
      test('speed ${c['speedKmh']} scale ${c['scale']}', () {
        final r = thresholds((c['speedKmh'] as num).toDouble(), defaultWarnConfig.withScale((c['scale'] as num).toDouble()));
        expect(r.first, closeTo(c['first'], 0.5));
        expect(r.second, closeTo(c['second'], 0.5));
      });
    }
  });

  final eng = vec('warning-engine');
  group('warning engine', () {
    for (final s in eng['scenarios']) {
      test(s['name'], () {
        final engine = WarningEngine(defaultWarnConfig.withScale((s['scale'] as num).toDouble()));
        final candidates = [for (final c in s['candidates']) candidateOf(c)];
        final expected = <int, List<dynamic>>{
          for (final e in s['expectedEventsByStep']) (e['step'] as num).toInt(): e['events'],
        };
        final fixes = s['fixes'] as List;
        for (var i = 0; i < fixes.length; i++) {
          final events = engine.update(fixOf(fixes[i]), candidates).map(eventJson).toList();
          expect(events, expected[i] ?? <dynamic>[], reason: 'step $i');
        }
      });
    }
  });

  final forget = vec('warning-forget');
  test('warning-forget: a candidate missing from one update is forgotten', () {
    final engine = WarningEngine();
    var i = 0;
    for (final st in forget['steps']) {
      final events = engine
          .update(fixOf(st['fix']), [for (final c in st['candidates']) candidateOf(c)])
          .map(eventJson)
          .toList();
      expect(events, st['events'], reason: 'step $i');
      i++;
    }
  });
}
