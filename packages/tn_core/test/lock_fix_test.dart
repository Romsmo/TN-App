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

/// The vectors write NaN as the string "NaN".
double? _num(dynamic v) => v == null ? null : (v is String ? double.parse(v) : (v as num).toDouble());

void main() {
  final lock = vec('lock');
  group('lock', () {
    test('constants', () {
      expect(lockOnKmh, lock['constants']['lockOnKmh']);
      expect(lockOffKmh, lock['constants']['lockOffKmh']);
      expect(lockReleaseAfterMs, lock['constants']['releaseAfterMs']);
      expect(lockStaleAfterMs, lock['constants']['staleAfterMs']);
    });
    for (final s in lock['scenarios']) {
      test(s['name'], () {
        final tracker = LockTracker();
        var i = 0;
        for (final st in s['steps']) {
          final bool locked;
          if (st.containsKey('tick')) {
            locked = tracker.tick((st['tick'] as num).toInt());
          } else {
            locked = tracker.update((st['speed'] as num?)?.toDouble(), (st['t'] as num).toInt());
          }
          expect(locked, st['locked'], reason: 'step $i');
          i++;
        }
      });
    }
    for (final c in lock['isLockActive']) {
      test('isLockActive $c',
          () => expect(isLockActive(driving: c['driving'], lockEnabled: c['lockEnabled'], locked: c['locked']), c['active']));
    }
  });

  final fix = vec('fix');
  group('fix', () {
    for (final c in fix['fixFromPosition']) {
      test('fixFromPosition ${c['position']}', () {
        final co = c['position']['coords'];
        final r = fixFromPosition(
          latitude: (co['latitude'] as num).toDouble(),
          longitude: (co['longitude'] as num).toDouble(),
          speed: _num(co['speed']),
          heading: _num(co['heading']),
          timestamp: (c['position']['timestamp'] as num).toInt(),
        );
        final e = c['fix'];
        expect(r.lat, e['lat']);
        expect(r.lng, e['lng']);
        expect(r.speedKmh, e['speedKmh'] == null ? isNull : closeTo(e['speedKmh'], 1e-9));
        expect(r.heading, e['heading']);
        expect(r.t, e['t']);
      });
    }
    for (final c in fix['deriveFix']) {
      test('deriveFix: ${c['name']}', () {
        final prev = c['previous'] == null ? null : fixOf(c['previous']);
        final r = deriveFix(prev, fixOf(c['fix']), (c['accuracyM'] as num).toDouble());
        final e = c['derived'];
        expect(r.lat, closeTo(e['lat'], 1e-9));
        expect(r.speedKmh, e['speedKmh'] == null ? isNull : closeTo(e['speedKmh'], 0.01));
        expect(r.heading, e['heading'] == null ? isNull : closeTo(e['heading'], 0.05));
      });
    }
  });
}
