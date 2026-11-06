import 'package:test/test.dart';
import 'package:tn_core/tn_core.dart';

import 'session_test.dart' show Harness, origin;

const cal = CameraCalibration(vanishingX: 0.5, horizonY: 0.5, rollDeg: 0, hFovDeg: 65, aspect: 16 / 9, calibratedAtMs: 1);

Fix fixAt(double northM, {double speedKmh = 36, double? heading = 0, int t = 0}) {
  final p = destination(origin, 0, northM);
  return Fix(lat: p.lat, lng: p.lng, speedKmh: speedKmh, heading: heading, t: t);
}

/// A 0.6 m sign at [d] metres fills this share of the image width (65 degrees field of view).
double widthAt(double d) => 0.6 * cal.focalInImageWidths / d;

/// The car drives up to a sign that stands [d0] metres ahead of [startOdo]: one frame every 250 ms, [stepM] metres further each.
void approach(SignRecognizer r, String vz,
    {double x = 0.62, double d0 = 50, int n = 6, double stepM = 2.5, int t0 = 0, double startOdo = 0, double conf = 0.9}) {
  for (var i = 0; i < n; i++) {
    final t = t0 + i * 250;
    r.onFix(fixAt(startOdo + i * stepM, t: t));
    r.onDetections(t, [RawDetection(vz: vz, confidence: conf, x: x, y: 0.45, w: widthAt(d0 - i * stepM), h: widthAt(d0 - i * stepM))]);
  }
}

RecognizedSign speedSign(int kmh, {int frames = 5, double conf = 0.9, double? heading = 90, double odo = 100, double lat = 50, double lng = 10}) =>
    RecognizedSign(
      id: 'cam:$kmh:$lat:$lng',
      vz: '274-$kmh',
      signOdoM: odo,
      lat: lat,
      lng: lng,
      heading: heading,
      firstSeenMs: 0,
      lastSeenMs: 1,
      frames: frames,
      confidence: conf,
    )
      ..roadLat = lat
      ..roadLng = lng;

void main() {
  group('speed values', () {
    test('a limit is a 274 number with a value a sign can show', () {
      expect(speedOfVz('274-50'), 50);
      expect(speedOfVz('274-130'), 130);
      expect(speedOfVz('274-55'), isNull);
      expect(speedOfVz('276'), isNull);
      expect(speedOfVz('274'), isNull);
      expect(isSpeedVz('274-30'), isTrue);
      expect(speedVzOf(40), '274-40');
    });

    test('the small limits of pedestrian zones and car parks are limits too', () {
      for (final v in [5, 10, 15, 25]) {
        expect(speedOfVz('274-$v'), v);
        expect(isSpeedVz(speedVzOf(v)), isTrue);
      }
      expect(speedOfVz('274-0'), isNull);
      expect(speedOfVz('274-35'), isNull); // not read
    });
  });

  group('SignRecognizer: speed limits', () {
    late SignRecognizer r;
    setUp(() {
      r = SignRecognizer(calibration: cal);
      r.onFix(fixAt(0));
    });

    test('a speed sign the car drives up to is read, and is not a sign of the display', () {
      approach(r, '274-50');
      expect(r.signs, isEmpty); // the display draws the limit from a number
      expect(r.active.single.speedKmh, 50);
      expect(r.speedLimit, isNull); // still more than 20 m ahead
      r.onFix(fixAt(35, t: 6000));
      expect(r.speedLimit?.kmh, 50);
      expect(r.speedLimit!.startsInM, closeTo(14, 8));
    });

    test('a sticker that keeps its distance to the car (a lorry ahead) is no sign', () {
      for (var i = 0; i < 10; i++) {
        r.onFix(fixAt(i * 2.5, t: i * 250));
        r.onDetections(i * 250, [RawDetection(vz: '274-80', confidence: 0.95, x: 0.52, y: 0.46, w: 0.02, h: 0.02)]);
      }
      expect(r.active, isEmpty);
      r.onFix(fixAt(300, t: 20000));
      expect(r.speedLimit, isNull);
    });

    test('a sticker whose size only flickers is no sign either', () {
      for (var i = 0; i < 10; i++) {
        r.onFix(fixAt(i * 2.5, t: i * 250));
        final w = 0.02 + (i.isEven ? 0.0015 : -0.0015);
        r.onDetections(i * 250, [RawDetection(vz: '274-80', confidence: 0.95, x: 0.52, y: 0.46, w: w, h: w)]);
      }
      expect(r.active, isEmpty);
    });

    test('a standing car cannot show that a sign is approached', () {
      r.onFix(fixAt(0, speedKmh: 0));
      for (var i = 0; i < 6; i++) {
        r.onDetections(i * 250, [RawDetection(vz: '274-50', confidence: 0.9, x: 0.62, y: 0.45, w: 0.012 + i * 0.003, h: 0.01)]);
      }
      expect(r.active, isEmpty);
    });

    test('other signs are not held to that check', () {
      for (var i = 0; i < 4; i++) {
        r.onDetections(i * 250, [RawDetection(vz: '276', confidence: 0.9, x: 0.62, y: 0.45, w: 0.012 + i * 0.003, h: 0.01)]);
      }
      expect(r.signs.map((s) => s.signType), ['DE:276']);
    });

    test('a limit counts from the sign on: the next one replaces it and ends its stretch', () {
      final ended = <(String, String)>[];
      r.onStretchEnded = (a, b) => ended.add((a.vz, b.vz));
      approach(r, '274-50');
      r.onFix(fixAt(100, t: 10000));
      approach(r, '274-30', t0: 10000, startOdo: 100);
      r.onFix(fixAt(160, t: 16000));
      expect(ended, [('274-50', '274-30')]);
      expect(r.speedLimit?.kmh, 30);
      expect(r.active.where((s) => s.speedKmh != null), hasLength(1));
    });

    test('the same limit seen again is not a new one', () {
      final ended = <(String, String)>[];
      r.onStretchEnded = (a, b) => ended.add((a.vz, b.vz));
      approach(r, '274-70');
      r.onFix(fixAt(100, t: 10000));
      approach(r, '274-70', t0: 10000, startOdo: 100);
      expect(ended, isEmpty);
      expect(r.active.where((s) => s.speedKmh != null), hasLength(1));
    });

    test('the end of all limits ends a limit', () {
      approach(r, '274-50');
      r.onFix(fixAt(100, t: 10000));
      expect(r.speedLimit?.kmh, 50);
      approach(r, '282', t0: 10000, startOdo: 100);
      r.onFix(fixAt(160, t: 16000));
      expect(r.speedLimit, isNull);
    });

    test('a limit holds for 1.5 km when nothing replaces it', () {
      approach(r, '274-50');
      r.onFix(fixAt(1000, t: 100000));
      expect(r.speedLimit?.kmh, 50);
      r.onFix(fixAt(1700, t: 200000));
      expect(r.speedLimit, isNull);
    });

    test('a newer value of the database ends a limit the car passed a while ago, not one at the car', () {
      approach(r, '274-50');
      r.onFix(fixAt(30, t: 6000));
      expect(r.forgetSpeedPassedBeyond(50), isFalse);
      expect(r.speedLimit?.kmh, 50);
      r.onFix(fixAt(200, t: 20000));
      expect(r.forgetSpeedPassedBeyond(50), isTrue);
      expect(r.speedLimit, isNull);
    });

    test('a speed sign gets a road point abreast of it, without the sideways offset', () {
      approach(r, '274-50');
      final s = r.active.single;
      expect(s.heading, 0);
      expect(s.roadLng, closeTo(origin.lng, 1e-6)); // driving north: the road point is straight ahead of the car
      expect(s.lng, greaterThan(origin.lng)); // the sign itself is to the right
    });
  });

  group('SpeedLimitReporter', () {
    late DatabaseLimit? db;
    late bool covered;
    late bool enabled;
    late List<(double, double, int)> wrong;
    late List<(double, double, double, double, int)> intervals;
    late SpeedLimitReporter rep;

    setUp(() {
      db = (value: 50, unit: SpeedUnit.kmh);
      covered = true;
      enabled = true;
      wrong = [];
      intervals = [];
      rep = SpeedLimitReporter(
        readLimit: (a, b, c) async => db,
        covered: (a, b) async => covered,
        reportWrong: (lat, lng, kmh) async {
          wrong.add((lat, lng, kmh));
          return true;
        },
        reportInterval: (from, to, kmh) async {
          intervals.add((from.lat, from.lng, to.lat, to.lng, kmh));
          return true;
        },
        enabled: () => enabled,
      );
    });

    Future<List<SpeedAction>> carAt(double odo, {double heading = 90}) => rep.onFix(lat: 50, lng: 10.001, heading: heading, odoM: odo);

    test('the database holds the same limit after the sign: nothing to correct', () async {
      await rep.onFinished(speedSign(50));
      expect(await carAt(130), isEmpty); // not far enough past the sign yet
      expect(await carAt(170), [SpeedAction.agreed]);
      expect(wrong, isEmpty);
      expect(intervals, isEmpty);
    });

    test('another limit in the database: "that limit is wrong" with the camera value, at the car', () async {
      db = (value: 30, unit: SpeedUnit.kmh);
      await rep.onFinished(speedSign(50));
      expect(await carAt(170), [SpeedAction.corrected]);
      expect(wrong, [(50.0, 10.001, 50)]);
    });

    test('no limit on record: the stretch is proposed once the next limit sign is read', () async {
      db = null;
      final start = speedSign(50, odo: 100);
      await rep.onFinished(start);
      expect(await carAt(170), [SpeedAction.deferred]);
      expect(intervals, isEmpty);
      final end = speedSign(30, odo: 700, lat: 50.004);
      expect(await rep.onStretchEnded(start, end), SpeedAction.deferred);
      expect(intervals, isEmpty); // the end sign is final only when it is out of sight
      expect(await rep.onFinished(end), SpeedAction.reported);
      expect(intervals, [(50.0, 10.0, 50.004, 10.0, 50)]);
    });

    test('no limit and no data for the place: nothing is proposed', () async {
      db = null;
      covered = false;
      await rep.onFinished(speedSign(50));
      expect(await carAt(170), [SpeedAction.skipped]);
    });

    test('a stretch that is too long, or an uncertain end, is not proposed', () async {
      db = null;
      final start = speedSign(50, odo: 100);
      await rep.onFinished(start);
      await carAt(170);
      final far = speedSign(30, odo: 9000, lat: 50.2);
      await rep.onStretchEnded(start, far);
      expect(await rep.onFinished(far), SpeedAction.skipped);

      final s2 = speedSign(70, odo: 100, lat: 51, lng: 11);
      await rep.onFinished(s2);
      await rep.onFix(lat: 51, lng: 11.001, heading: 90, odoM: 170);
      final weak = speedSign(30, odo: 700, lat: 51.004, lng: 11, frames: 3);
      await rep.onStretchEnded(s2, weak);
      expect(await rep.onFinished(weak), SpeedAction.skipped);
      expect(intervals, isEmpty);
    });

    test('a limit that is replaced before the car is far enough past it is dropped', () async {
      final start = speedSign(50, odo: 100);
      await rep.onFinished(start);
      await rep.onStretchEnded(start, speedSign(30, odo: 130));
      expect(await carAt(170), isEmpty);
    });

    test('a car that turned off at a junction says nothing about the road of the sign', () async {
      await rep.onFinished(speedSign(50));
      expect(await carAt(170, heading: 180), [SpeedAction.skipped]);
      expect(wrong, isEmpty);
    });

    test('a sign that was never checked within 400 m is dropped', () async {
      await rep.onFinished(speedSign(50));
      expect(await carAt(900), [SpeedAction.skipped]);
    });

    test('nothing is sent when it is switched off, uncertain or without a heading', () async {
      db = (value: 30, unit: SpeedUnit.kmh);
      enabled = false;
      await rep.onFinished(speedSign(50));
      expect(await carAt(170), isEmpty);
      enabled = true;
      await rep.onFinished(speedSign(50, frames: 3));
      await rep.onFinished(speedSign(50, conf: 0.8));
      await rep.onFinished(speedSign(50, heading: null));
      expect(await carAt(170), isEmpty);
      expect(wrong, isEmpty);
    });

    test('a limit in miles is left alone, and so is an unreadable database', () async {
      db = (value: 30, unit: SpeedUnit.mph);
      await rep.onFinished(speedSign(50));
      expect(await carAt(170), [SpeedAction.skipped]);
      final broken = SpeedLimitReporter(
        readLimit: (a, b, c) async => throw StateError('no data'),
        covered: (a, b) async => true,
        reportWrong: (a, b, c) async => true,
        reportInterval: (a, b, c) async => true,
        enabled: () => true,
      );
      await broken.onFinished(speedSign(50));
      expect(await broken.onFix(lat: 50, lng: 10, heading: 90, odoM: 170), [SpeedAction.skipped]);
    });

    test('the same limit at the same place is handled once, and a trip has a cap', () async {
      db = (value: 30, unit: SpeedUnit.kmh);
      await rep.onFinished(speedSign(50));
      await carAt(170);
      expect(await rep.onFinished(speedSign(50)), SpeedAction.skipped);
      final capped = SpeedLimitReporter(
        readLimit: (a, b, c) async => (value: 30, unit: SpeedUnit.kmh),
        covered: (a, b) async => true,
        reportWrong: (a, b, c) async => true,
        reportInterval: (a, b, c) async => true,
        enabled: () => true,
        config: const SpeedReporterConfig(maxPerTrip: 2),
      );
      for (var i = 0; i < 4; i++) {
        await capped.onFinished(speedSign(50, lat: 50 + i * 0.1, odo: 100 + i * 1000.0));
        await capped.onFix(lat: 50, lng: 10, heading: 90, odoM: 170 + i * 1000.0);
      }
      expect(capped.handled, 2);
    });

    test('a write that fails is not retried', () async {
      db = (value: 30, unit: SpeedUnit.kmh);
      final flaky = SpeedLimitReporter(
        readLimit: (a, b, c) async => db,
        covered: (a, b) async => true,
        reportWrong: (a, b, c) async => throw StateError('queue full'),
        reportInterval: (a, b, c) async => true,
        enabled: () => true,
      );
      await flaky.onFinished(speedSign(50));
      expect(await flaky.onFix(lat: 50, lng: 10, heading: 90, odoM: 170), [SpeedAction.skipped]);
      expect(flaky.handled, 0);
    });
  });

  group('drive session: the limit shown', () {
    SignVision vision() => SignVision(
          recognizer: SignRecognizer(calibration: cal),
          reporter: SignReporter(readDb: (a, b, c) async => const [], report: (r) async => true, vote: (a, b) async => true, enabled: () => false),
        );

    /// The car drives up to the sign: fixes and frames together, every 250 ms.
    Future<void> approachSign(Harness h, String vz, {double d0 = 50, int n = 6, double startM = 0}) async {
      for (var i = 0; i < n; i++) {
        final m = startM + i * 2.5;
        h.session.onFix(h.at(m, 36, 0));
        final w = widthAt(d0 - i * 2.5);
        h.session.onFrame(h.now, [RawDetection(vz: vz, confidence: 0.9, x: 0.62, y: 0.45, w: w, h: w)]);
        await h.flush();
        h.now += 250;
      }
    }

    test('without a camera the database limit is shown, as before', () async {
      final h = Harness(limitValue: 100);
      h.session.start();
      await h.fix(0, 36, 0);
      expect(h.session.snapshot.limit?.value, 100);
      expect(h.session.snapshot.limitFromCamera, isFalse);
      h.session.stop();
    });

    test('a limit the camera read is shown instead of the database limit and the speed state follows it', () async {
      final h = Harness(limitValue: 100, vision: vision());
      h.session.start();
      await h.fix(0, 36, 0);
      expect(h.session.snapshot.limit?.value, 100);
      await approachSign(h, '274-30');
      h.session.onFix(h.at(40, 60, 0));
      await h.flush();
      final s = h.session.snapshot;
      expect(s.limitFromCamera, isTrue);
      expect(s.limit?.value, 30);
      expect(s.limit?.unit, SpeedUnit.kmh);
      expect(s.databaseLimit?.value, 100);
      expect(s.speedState, isNot(SpeedState.ok)); // 60 km/h in a 30 zone
      expect(s.recognizedSigns, isEmpty); // not a sign of the display
      h.session.stop();
    });

    test('a limit that is still far ahead is not applied yet', () async {
      final h = Harness(limitValue: 100, vision: vision());
      h.session.start();
      await h.fix(0, 36, 0);
      await approachSign(h, '274-30', d0: 80, n: 4);
      expect(h.session.snapshot.limitFromCamera, isFalse);
      expect(h.session.snapshot.limit?.value, 100);
      h.session.stop();
    });

    test('a different value in the database, long after the sign, gives way to the newer data', () async {
      final h = Harness(limitValue: 100, vision: vision());
      h.session.start();
      await h.fix(0, 36, 0);
      await approachSign(h, '274-30');
      h.session.onFix(h.at(40, 36, 0));
      await h.flush();
      expect(h.session.snapshot.limit?.value, 30);
      h.data.limitValue = 70; // the road has a new limit in the database
      h.now += 5000; // the next limit read is due
      h.session.onFix(h.at(150, 36, 0));
      await h.flush();
      h.session.onFix(h.at(155, 36, 0));
      await h.flush();
      expect(h.session.snapshot.limitFromCamera, isFalse);
      expect(h.session.snapshot.limit?.value, 70);
      h.session.stop();
    });

    test('the same value as the camera in the database changes nothing', () async {
      final h = Harness(limitValue: 100, vision: vision());
      h.session.start();
      await h.fix(0, 36, 0);
      await approachSign(h, '274-30');
      h.session.onFix(h.at(40, 36, 0));
      await h.flush();
      h.data.limitValue = 30;
      h.now += 5000;
      h.session.onFix(h.at(150, 36, 0));
      await h.flush();
      h.session.onFix(h.at(155, 36, 0));
      await h.flush();
      expect(h.session.snapshot.limit?.value, 30);
      h.session.stop();
    });

    test('a new drive starts without the last drive\'s limit', () async {
      final h = Harness(limitValue: 100, vision: vision());
      h.session.start();
      await h.fix(0, 36, 0);
      await approachSign(h, '274-30');
      h.session.onFix(h.at(40, 36, 0));
      h.session.stop();
      h.session.start();
      expect(h.session.snapshot.limit, isNull);
      expect(h.session.snapshot.limitFromCamera, isFalse);
      h.session.stop();
    });
  });
}
