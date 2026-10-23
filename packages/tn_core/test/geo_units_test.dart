import 'package:test/test.dart';
import 'package:tn_core/tn_core.dart';

import 'vec.dart';

LatLng ll(dynamic m) => LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());

void main() {
  final geo = vec('geo');
  group('geo (0.5 m / 0.05 deg tolerance)', () {
    for (final c in geo['distance']) {
      test('distance: ${c['name']}', () {
        expect(distanceMeters(ll(c['a']), ll(c['b'])), closeTo(c['meters'], 0.5));
        expect(bearingDegrees(ll(c['a']), ll(c['b'])), closeTo(c['bearing'], 0.05));
      });
    }
    for (final c in geo['angleDiff']) {
      test('angleDiff ${c['a']} ${c['b']}',
          () => expect(angleDiff((c['a'] as num).toDouble(), (c['b'] as num).toDouble()), closeTo(c['diff'], 0.05)));
    }
    for (final c in geo['destination']) {
      test('destination ${c['bearing']} ${c['meters']}', () {
        final to = destination(ll(c['from']), (c['bearing'] as num).toDouble(), (c['meters'] as num).toDouble());
        expect(distanceMeters(to, ll(c['to'])), lessThan(0.5));
      });
    }
    for (final c in geo['alongCross']) {
      test('alongCross: ${c['name']}', () {
        final r = alongCross(ll(c['vehicle']), (c['heading'] as num).toDouble(), ll(c['point']));
        expect(r.along, closeTo(c['along'], 0.5));
        expect(r.cross, closeTo(c['cross'], 0.5));
      });
    }
    for (final c in geo['rayEntry']) {
      test('rayEntry: ${c['name']}', () {
        final ring = [
          for (final p in c['ring']) [(p[0] as num).toDouble(), (p[1] as num).toDouble()]
        ];
        final r = rayEntryDistance(ll(c['vehicle']), (c['heading'] as num).toDouble(), ring);
        if (c['entryMeters'] == null) {
          expect(r, isNull);
        } else {
          expect(r, isNotNull);
          expect(r!, closeTo(c['entryMeters'], 0.5));
        }
      });
    }
  });

  final units = vec('units');
  SpeedUnit u(dynamic s) => SpeedUnit.parse(s);
  group('units', () {
    test('mph factor', () => expect(kmhPerMph, units['kmPerMph']));
    for (final c in units['toKmh']) {
      test('toKmh ${c['value']} ${c['unit']}', () => expect(toKmh(c['value'], u(c['unit'])), closeTo(c['kmh'], 1e-9)));
    }
    for (final c in units['fromKmh']) {
      test('fromKmh ${c['kmh']} ${c['unit']}', () => expect(fromKmh(c['kmh'], u(c['unit'])), closeTo(c['value'], 1e-9)));
    }
    for (final c in units['displaySpeed']) {
      test('displaySpeed ${c['kmh']} ${c['unit']}',
          () => expect(displaySpeed((c['kmh'] as num?)?.toDouble(), u(c['unit'])), c['shown']));
    }
    for (final c in units['displayLimit']) {
      test('displayLimit ${c['value']} ${c['from']}->${c['to']}',
          () => expect(displayLimit(c['value'], u(c['from']), u(c['to'])), c['shown']));
    }
    for (final c in units['speedState']) {
      test('speedState ${c['speedKmh']} ${c['limit']}', () {
        final l = c['limit'];
        final limit = l == null ? null : (value: l['value'] as num, unit: u(l['unit']));
        expect(
            speedState((c['speedKmh'] as num?)?.toDouble(), limit, toleranceKmh: (units['toleranceKmh'] as num).toDouble()).name,
            c['state']);
      });
    }
  });

  final sampling = vec('sampling');
  group('sampling', () {
    for (final c in sampling['samplingFor']) {
      test('samplingFor ${c['speedKmh']}', () {
        final s = samplingFor((c['speedKmh'] as num?)?.toDouble());
        expect(s.regime.name, c['regime']);
        expect(s.accuracy.name, c['accuracy']);
        expect(s.distanceIntervalM, c['distanceIntervalM']);
        expect(s.timeIntervalMs, c['timeIntervalMs']);
      });
    }
    for (final c in sampling['nextRegime']) {
      test('nextRegime ${c['current']} ${c['speedKmh']}', () {
        final cur = Regime.values.byName(c['current']);
        expect(nextRegime(cur, (c['speedKmh'] as num?)?.toDouble()).name, c['next']);
      });
    }
    test('representative speeds', () {
      for (final e in (sampling['representativeSpeed'] as Map).entries) {
        expect(representativeSpeed[Regime.values.byName(e.key)], (e.value as num).toDouble());
      }
    });
  });

  final compass = vec('compass');
  group('compass and follow mode', () {
    for (final c in compass['cardinalIndex']) {
      test('cardinalIndex ${c['heading']}', () => expect(cardinalIndex((c['heading'] as num).toDouble()), c['index']));
    }
    test('points', () => expect(cardinalPoints, compass['points']));
    final follow = vec('follow-mode');
    for (final c in follow['next']) {
      test('follow ${c['mode']}', () {
        final m = FollowMode.values.byName(c['mode']);
        expect(nextFollowMode(m).name, c['next']);
        expect(afterUserMove(m).name, c['afterUserMove']);
        expect(shouldMoveWithPosition(m), c['movesWithPosition']);
      });
    }
    test('centre zoom', () => expect(centerZoom, follow['centerZoom']));
  });
}
