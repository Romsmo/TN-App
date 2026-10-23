import 'package:test/test.dart';
import 'package:tn_core/tn_core.dart';

import 'vec.dart';

void main() {
  final sim = vec('sim');

  test('limits table', () {
    expect([for (final l in simLimits) [l.$1, l.$2]], sim['limits']);
  });

  test('limit and speed along the route', () {
    for (final c in sim['table']) {
      final d = (c['distanceM'] as num).toDouble();
      expect(simLimitAt(d), c['limitKmh'], reason: '$c');
      expect(simSpeedAt(d), c['speedKmh'], reason: '$c');
    }
  });

  test('the demo route has 71 points and is about 7 km long', () {
    expect(demoRoute.points.length, 71);
    expect(demoRoute.lengthM, closeTo(7000, 400));
  });

  test('route player produces fixes until the end, at the profile speed', () {
    final player = RoutePlayer(demoRoute, simSpeedAt, 0);
    var n = 0;
    Fix? last;
    while (true) {
      final f = player.next();
      if (f == null) break;
      last = f;
      n++;
      if (n > 3000) fail('route never ends');
    }
    expect(n, greaterThan(300));
    expect(last, isNotNull);
    expect(player.finished, true);
  });

  test('simulated data: three hazards on the route, a zone only with cameras on', () async {
    final without = createSimDataSource(demoRoute, camerasEnabled: false);
    final start = demoRoute.points.first;
    final a = await without.nearby(start.lat, start.lng, 20000);
    expect(a.whereType<HazardItem>().length, 3);
    expect(a.whereType<CameraZoneItem>(), isEmpty);
    final withCams = createSimDataSource(demoRoute, camerasEnabled: true);
    final b = await withCams.nearby(start.lat, start.lng, 20000);
    expect(b.whereType<CameraZoneItem>().length, 1);
    final limit = await without.speedLimit(start.lat, start.lng, null);
    expect(limit!.value, 50);
    expect(await without.limitCovered(start.lat, start.lng), true);
  });

  test('a simulated drive through the session raises warnings and the lock', () async {
    var now = 5000000;
    final fb = <String>[];
    final session = DriveSession(DriveDeps(
      data: createSimDataSource(demoRoute, camerasEnabled: true),
      feedback: _Silent(fb),
      texts: Texts(de: textTable('de'), en: textTable('en'), language: 'en'),
      getSettings: () => const DriveSettings(),
      now: () => now,
      submitReport: (t, p) async => true,
      vote: (id, s) async => true,
      simulated: true,
    ));
    session.start();
    final player = RoutePlayer(demoRoute, simSpeedAt, now);
    var warned = <String>{};
    var sawZone = false;
    var sawLock = false;
    var sawOver = false;
    while (true) {
      final f = player.next();
      if (f == null) break;
      session.onFix(f);
      await Future<void>.delayed(Duration.zero);
      now += 1000;
      session.tick();
      final s = session.snapshot;
      for (final w in s.warnings) {
        warned.add(w.id);
        if (w.kind == WarnKind.zone) sawZone = true;
      }
      if (s.locked) sawLock = true;
      if (s.speedState == SpeedState.over) sawOver = true;
    }
    expect(warned, containsAll(['sim-accident', 'sim-construction', 'sim-ice']));
    expect(sawZone, true);
    expect(sawLock, true);
    expect(sawOver, true, reason: 'the stretch 2600..3200 m is driven over the limit');
  });
}

class _Silent implements Feedback {
  _Silent(this.log);
  final List<String> log;
  @override
  void warn(WarnLevel level, String text, {required bool sound, required bool voice}) => log.add(text);
  @override
  void confirm({required bool sound}) {}
  @override
  void prompt({required bool sound}) {}
  @override
  void silence() {}
}
