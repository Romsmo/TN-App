import 'package:test/test.dart';
import 'package:tn_core/tn_core.dart';

import 'session_test.dart' show Harness, origin;

const cal = CameraCalibration(vanishingX: 0.5, horizonY: 0.5, rollDeg: 0, hFovDeg: 65, aspect: 16 / 9, calibratedAtMs: 1);

Fix fixAt(double northM, {double speedKmh = 36, double? heading = 0, int t = 0}) {
  final p = destination(origin, 0, northM);
  return Fix(lat: p.lat, lng: p.lng, speedKmh: speedKmh, heading: heading, t: t);
}

RawDetection det(String vz, {double x = 0.62, double y = 0.45, double w = 0.02, double conf = 0.9}) =>
    RawDetection(vz: vz, confidence: conf, x: x, y: y, w: w, h: w);

/// A sign seen in [n] frames, 250 ms apart from [t0], growing as the car comes nearer.
void see(SignRecognizer r, String vz, {int n = 4, int t0 = 0, double x = 0.62, double w0 = 0.012, double conf = 0.9}) {
  for (var i = 0; i < n; i++) {
    r.onDetections(t0 + i * 250, [det(vz, x: x, w: w0 + i * 0.003, conf: conf)]);
  }
}

ContextSign sign(String type, double starts, {bool camera = false, bool confirmed = true}) =>
    ContextSign(id: '${camera ? 'cam' : 'db'}:$type:$starts', signType: type, startsInM: starts, confirmed: confirmed, fromCamera: camera);

void main() {
  group('CameraCalibration', () {
    test('the vanishing point is straight ahead; points left of it are negative angles', () {
      expect(cal.bearingOffsetDeg(0.5, 0.5), closeTo(0, 1e-9));
      expect(cal.bearingOffsetDeg(0.62, 0.5), greaterThan(0));
      expect(cal.bearingOffsetDeg(0.3, 0.5), lessThan(0));
      final shifted = cal.copyWith(vanishingX: 0.6);
      expect(shifted.bearingOffsetDeg(0.6, 0.5), closeTo(0, 1e-9));
      expect(cal.bearingOffsetDeg(1.0, 0.5), closeTo(32.5, 0.01)); // the image edge is half the field of view
    });

    test('a point above the horizon has a positive elevation', () {
      expect(cal.elevationDeg(0.5, 0.3), greaterThan(0));
      expect(cal.elevationDeg(0.5, 0.7), lessThan(0));
    });

    test('a bigger sign is nearer, the distance is clamped to what can be read', () {
      expect(cal.distanceToSignM(0.02), greaterThan(cal.distanceToSignM(0.04)));
      expect(cal.distanceToSignM(0.0001), CameraCalibration.maxSignDistanceM);
      expect(cal.distanceToSignM(0.9), CameraCalibration.minSignDistanceM);
      expect(cal.distanceToSignM(0), CameraCalibration.maxSignDistanceM);
    });

    test('the roll is taken out before the angles are read', () {
      final rolled = cal.copyWith(rollDeg: 10);
      // a point on the rolled horizon (right of the centre, lower by dx * tan(roll) in image widths) is at elevation 0
      expect(rolled.elevationDeg(0.9, 0.5 + (16 / 9) * 0.4 * 0.17633), closeTo(0, 0.01));
      expect(cal.elevationDeg(0.9, 0.5 + (16 / 9) * 0.4 * 0.17633), lessThan(-5));
    });

    test('it is stored and read back; anything unusable is "not calibrated"', () {
      expect(CameraCalibration.fromJson(cal.toJson()).vanishingX, 0.5);
      expect(CameraCalibration.fromJson(cal.toJson()).isCalibrated, isTrue);
      expect(CameraCalibration.fromJson(null).isCalibrated, isFalse);
      expect(CameraCalibration.fromJson({...cal.toJson(), 'hFovDeg': 500}).isCalibrated, isFalse);
      expect(CameraCalibration.fromJson({...cal.toJson(), 'calibratedAtMs': null}).isCalibrated, isFalse);
      expect(CameraCalibration.none.isCalibrated, isFalse);
    });

    test('a bad placement is named', () {
      expect(cal.problem, isNull);
      expect(cal.copyWith(horizonY: 0.1).problem, CalibrationProblem.lookingDown);
      expect(cal.copyWith(horizonY: 0.8).problem, CalibrationProblem.lookingUp);
      expect(cal.copyWith(rollDeg: 12).problem, CalibrationProblem.rolled);
      expect(cal.copyWith(vanishingX: 0.9).problem, CalibrationProblem.turned);
    });

    test('settings keep the switches and the calibration', () {
      final s = const Settings().copyWith(cameraSigns: true, cameraSignsReport: true, cameraCalibration: cal);
      final back = parseSettings(encodeSettings(s));
      expect(back.cameraSigns, isTrue);
      expect(back.cameraSignsReport, isTrue);
      expect(back.cameraCalibration.isCalibrated, isTrue);
      final fresh = parseSettings(null);
      expect(fresh.cameraSigns, isFalse);
      expect(fresh.cameraSignsReport, isFalse);
      expect(fresh.cameraCalibration.isCalibrated, isFalse);
    });
  });

  group('SignRecognizer', () {
    late SignRecognizer r;
    setUp(() {
      r = SignRecognizer(calibration: cal);
      r.onFix(fixAt(0));
    });

    test('a sign seen in three frames is placed ahead; a sign seen in two is not', () {
      see(r, '276', n: 2);
      expect(r.signs, isEmpty);
      see(r, '276', n: 3);
      expect(r.signs.map((s) => s.signType), ['DE:276']);
      final s = r.signs.single;
      expect(s.fromCamera, isTrue);
      expect(s.confirmed, isTrue);
      expect(s.startsInM, closeTo(33, 6));
    });

    test('driving past moves the sign behind the car', () {
      see(r, '276');
      final ahead = r.signs.single.startsInM;
      r.onFix(fixAt(50, t: 5000));
      expect(r.signs.single.startsInM, closeTo(ahead - 50, 0.5));
      expect(r.signs.single.startsInM, lessThan(0));
    });

    test('a low-confidence reading and a sign the display cannot draw are ignored', () {
      see(r, '276', conf: 0.6);
      see(r, '274', t0: 4000);
      see(r, '999', t0: 6000);
      expect(r.signs, isEmpty);
    });

    test('a sign far off the direction of travel stands at a side road and is ignored', () {
      final skewed = SignRecognizer(calibration: cal.copyWith(vanishingX: 0.3));
      skewed.onFix(fixAt(0));
      see(skewed, '276', x: 0.95); // about 40 degrees to the right of the road
      expect(skewed.signs, isEmpty);
      see(skewed, '276', x: 0.45, t0: 3000); // 11 degrees to the right
      expect(skewed.signs, hasLength(1));
    });

    test('a track that cannot make up its mind between two signs shows neither', () {
      for (var i = 0; i < 6; i++) {
        r.onDetections(i * 250, [det(i.isEven ? '276' : '277', w: 0.012 + i * 0.002, conf: 0.8)]);
      }
      expect(r.signs, isEmpty);
    });

    test('nothing is placed without a recent position', () {
      final lost = SignRecognizer(calibration: cal);
      see(lost, '276');
      expect(lost.signs, isEmpty);
      r.onFix(fixAt(0, t: 0));
      see(r, '276', t0: 60000); // the position is a minute old
      expect(r.signs, isEmpty);
    });

    test('a later sign of the same family replaces the earlier one and ends its stretch', () {
      final ended = <(String, String)>[];
      r.onStretchEnded = (a, b) => ended.add((a.vz, b.vz));
      see(r, '276');
      r.onFix(fixAt(300, t: 30000));
      see(r, '280', t0: 30000);
      expect(r.signs.map((s) => s.signType), ['DE:280']);
      expect(ended, [('276', '280')]);
    });

    test('the same sign seen again is not shown twice and does not end itself', () {
      final ended = <(String, String)>[];
      r.onStretchEnded = (a, b) => ended.add((a.vz, b.vz));
      see(r, '276');
      r.onFix(fixAt(300, t: 30000));
      see(r, '276', t0: 30000);
      expect(r.signs, hasLength(1));
      expect(ended, isEmpty);
    });

    test('a sign out of sight is reported as finished once, with its best place', () {
      final done = <RecognizedSign>[];
      r.onFinished = done.add;
      see(r, '131');
      expect(done, isEmpty);
      r.onFix(fixAt(100, t: 4000));
      expect(done.map((s) => s.vz), ['131']);
      expect(done.single.finished, isTrue);
      expect(done.single.heading, 0);
      expect(done.single.frames, 4);
    });

    test('a warning stays for a short stretch, a prohibition until something replaces it', () {
      see(r, '123');
      see(r, '276', t0: 2000);
      r.onFix(fixAt(300, t: 30000));
      expect(r.signs.map((s) => s.signType).toSet(), {'DE:123', 'DE:276'});
      r.onFix(fixAt(500, t: 50000));
      expect(r.signs.map((s) => s.signType), ['DE:276']);
      r.onFix(fixAt(6000, t: 600000));
      expect(r.signs, isEmpty);
    });

    test('without a heading a sign is shown but has no place on the map', () {
      final noHeading = SignRecognizer(calibration: cal);
      noHeading.onFix(fixAt(0, heading: null));
      see(noHeading, '131');
      expect(noHeading.signs, hasLength(1));
      expect(noHeading.active.single.heading, isNull);
    });
  });

  group('camera and database together', () {
    test('what the camera reads wins against an older database sign that conflicts', () {
      final c = signColumnsFor([sign('DE:276', -300), sign('DE:277', -20, camera: true)]);
      expect(c.left, [27700]);
    });

    test('a database sign that clearly began after the camera sign still applies', () {
      final c = signColumnsFor([sign('DE:276', -300, camera: true), sign('DE:280', -40)]);
      expect(c.left, [28000]);
    });

    test('within the position tolerance the camera wins', () {
      final c = signColumnsFor([sign('DE:276', -60, camera: true), sign('DE:280', -40)]);
      expect(c.left, [27600]);
    });

    test('the camera shows a sign the database does not have, and the database one the camera did not see', () {
      final c = signColumnsFor([sign('DE:123', -20, camera: true), sign('DE:142-10', -50), sign('DE:276', -80, confirmed: false)]);
      expect(c.right, [14210, 12300]);
      expect(c.left, isEmpty);
    });

    test('the same sign in both is shown once', () {
      final c = signColumnsFor([sign('DE:276', -100), sign('DE:276', -90, camera: true)]);
      expect(c.left, [27600]);
    });
  });

  group('SignReporter', () {
    late List<Map<String, Object?>> reports;
    late List<(String, bool)> votes;
    late List<ContextSign> db;
    var enabled = true;
    var throwOnRead = false;
    late SignReporter rep;

    setUp(() {
      reports = [];
      votes = [];
      db = [];
      enabled = true;
      throwOnRead = false;
      rep = SignReporter(
        readDb: (lat, lng, h) async {
          if (throwOnRead) throw StateError('no data');
          return db;
        },
        report: (r) async {
          reports.add(r);
          return true;
        },
        vote: (id, agrees) async {
          votes.add((id, agrees));
          return true;
        },
        enabled: () => enabled,
      );
    });

    RecognizedSign seen(String vz, {int frames = 5, double conf = 0.9, double? heading = 90, double lat = 50, double lng = 10, double odo = 100}) =>
        RecognizedSign(id: 'cam:$vz$lat$lng', vz: vz, signOdoM: odo, lat: lat, lng: lng, heading: heading, firstSeenMs: 0, lastSeenMs: 1, frames: frames, confidence: conf);

    Future<SignAction> finish(RecognizedSign s, {double startsInM = -20}) => rep.onFinished(s, carLat: 50, carLng: 10.0003, startsInM: startsInM);

    test('a sign the database holds is confirmed, once', () async {
      db = [ContextSign(id: 'e1', signType: 'DE:131', startsInM: -25, confirmed: false)];
      expect(await finish(seen('131')), SignAction.voted);
      expect(votes, [('e1', true)]);
      expect(reports, isEmpty);
      expect(await finish(seen('131', lng: 10.1)), SignAction.skipped);
      expect(votes, hasLength(1));
    });

    test('a repeated sign inside a stretch the database holds confirms that stretch', () async {
      db = [ContextSign(id: 'e2', signType: 'DE:276', startsInM: -700, endsInM: 400, confirmed: true)];
      expect(await finish(seen('276')), SignAction.voted);
      expect(votes.single.$1, 'e2');
    });

    test('a point sign the database lacks is proposed with its place and direction', () async {
      expect(await finish(seen('131')), SignAction.reported);
      expect(reports.single, {
        'signType': 'DE:131',
        'from': {'lat': 50.0, 'lng': 10.0},
        'direction': 'along',
        'heading': 90.0,
      });
    });

    test('a different sign of the same family in the database does not stop the proposal', () async {
      db = [ContextSign(id: 'e3', signType: 'DE:102', startsInM: -20, confirmed: true)];
      expect(await finish(seen('101-11')), SignAction.reported);
    });

    test('a stretch sign waits for its end sign and is then proposed with both ends', () async {
      final start = seen('276', lat: 50, lng: 10, odo: 100);
      expect(await finish(start), SignAction.deferred);
      expect(reports, isEmpty);
      final end = seen('280', lat: 50.004, lng: 10, odo: 600);
      expect(await rep.onStretchEnded(start, end), SignAction.reported);
      expect(reports.single['signType'], 'DE:276');
      expect(reports.single['from'], {'lat': 50.0, 'lng': 10.0});
      expect(reports.single['to'], {'lat': 50.004, 'lng': 10.0});
    });

    test('an end that is seen before the start sign has finished is not lost', () async {
      final start = seen('276', odo: 100);
      final end = seen('280', lat: 50.004, odo: 600);
      expect(await rep.onStretchEnded(start, end), SignAction.skipped);
      expect(await finish(start), SignAction.reported);
      expect(reports, hasLength(1));
    });

    test('a stretch that is too short or too long is not proposed', () async {
      final s1 = seen('276', odo: 100);
      await finish(s1);
      expect(await rep.onStretchEnded(s1, seen('280', lat: 50.0002, odo: 110)), SignAction.skipped);
      final s2 = seen('277', lat: 51, odo: 100);
      await finish(s2);
      expect(await rep.onStretchEnded(s2, seen('280', lat: 51.1, odo: 9000)), SignAction.skipped);
      expect(reports, isEmpty);
    });

    test('nothing is sent when it is switched off, uncertain, without a heading or for a sign with a value', () async {
      enabled = false;
      expect(await finish(seen('131')), SignAction.skipped);
      enabled = true;
      expect(await finish(seen('131', frames: 3)), SignAction.skipped);
      expect(await finish(seen('131', conf: 0.8)), SignAction.skipped);
      expect(await finish(seen('131', heading: null)), SignAction.skipped);
      expect(await finish(seen('253')), SignAction.skipped);
      expect(await finish(seen('123')), SignAction.skipped); // a warning over a stretch the camera cannot measure
      expect(reports, isEmpty);
      expect(votes, isEmpty);
    });

    test('nothing is sent when the database cannot be read', () async {
      throwOnRead = true;
      expect(await finish(seen('131')), SignAction.skipped);
      expect(reports, isEmpty);
    });

    test('the same sign at the same place is handled once, and a trip has a cap', () async {
      expect(await finish(seen('131')), SignAction.reported);
      expect(await finish(seen('131')), SignAction.skipped);
      final capped = SignReporter(
        readDb: (a, b, c) async => const [],
        report: (r) async => true,
        vote: (a, b) async => true,
        enabled: () => true,
        config: const ReporterConfig(maxPerTrip: 2),
      );
      for (var i = 0; i < 4; i++) {
        await capped.onFinished(seen('131', lat: 50 + i * 0.1), carLat: 50, carLng: 10, startsInM: -20);
      }
      expect(capped.handled, 2);
    });

    test('a write that fails is not retried and does not break the next one', () async {
      var n = 0;
      final flaky = SignReporter(
        readDb: (a, b, c) async => const [],
        report: (r) async {
          n++;
          if (n == 1) throw StateError('queue full');
          return true;
        },
        vote: (a, b) async => true,
        enabled: () => true,
      );
      expect(await flaky.onFinished(seen('131'), carLat: 50, carLng: 10, startsInM: -20), SignAction.skipped);
      expect(await flaky.onFinished(seen('151', lat: 51), carLat: 51, carLng: 10, startsInM: -20), SignAction.reported);
    });
  });

  group('drive session', () {
    SignVision vision(List<Map<String, Object?>> out) => SignVision(
          recognizer: SignRecognizer(calibration: cal),
          reporter: SignReporter(
            readDb: (a, b, c) async => const [],
            report: (r) async {
              out.add(r);
              return true;
            },
            vote: (a, b) async => true,
            enabled: () => true,
          ),
        );

    test('frames put recognised signs into the snapshot, and the drive ending clears them', () async {
      final h = Harness(vision: vision([]));
      h.session.start();
      await h.fix(0, 36, 0);
      for (var i = 0; i < 4; i++) {
        h.session.onFrame(h.now - 1000 + i * 250, [det('276', w: 0.012 + i * 0.003)]);
      }
      expect(h.session.snapshot.recognizedSigns.map((s) => s.signType), ['DE:276']);
      h.session.stop();
      expect(h.session.snapshot.recognizedSigns, isEmpty);
    });

    test('a sign the camera read goes into the display columns before the database', () async {
      final h = Harness(vision: vision([]), signs: [sign('DE:276', -300)]);
      h.session.start();
      await h.fix(0, 36, 0);
      for (var i = 0; i < 4; i++) {
        h.session.onFrame(h.now - 1000 + i * 250, [det('277', w: 0.012 + i * 0.003)]);
      }
      final snap = h.session.snapshot;
      final cols = signColumnsFor([...snap.contextSigns, ...snap.recognizedSigns]);
      expect(cols.left, [27700]);
      h.session.stop();
    });

    test('a session without a camera ignores frames', () async {
      final h = Harness();
      h.session.start();
      await h.fix(0, 36, 0);
      h.session.onFrame(h.now, [det('276')]);
      expect(h.session.snapshot.recognizedSigns, isEmpty);
      h.session.stop();
    });
  });
}
