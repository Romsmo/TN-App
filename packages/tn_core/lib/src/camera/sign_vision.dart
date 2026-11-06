import 'dart:async';

import '../drive/fix.dart';
import '../tn/types.dart';
import 'camera_calibration.dart';
import 'sign_recognizer.dart';
import 'sign_reporter.dart';
import 'speed_reporter.dart';

/// The camera side of a drive: the recogniser, which places signs on the road from the detections, and the reporters, which feed the
/// database from them (the signs, and the speed limits). The drive session owns one while the camera is switched on; the app feeds
/// it frames.
class SignVision {
  SignVision({required this.recognizer, required this.reporter, this.speedReporter}) {
    recognizer.onFinished = _finished;
    recognizer.onStretchEnded = (start, end) {
      if (start.speedKmh != null) {
        unawaited(speedReporter?.onStretchEnded(start, end));
      } else {
        unawaited(reporter.onStretchEnded(start, end));
      }
    };
  }

  final SignRecognizer recognizer;
  final SignReporter reporter;

  /// Feeds the database's speed limits; null = the speed limits are only shown.
  final SpeedLimitReporter? speedReporter;
  Fix? _fix;

  /// The signs the camera read that are in force or just ahead (entries like the database's, marked `fromCamera`). Speed limits are
  /// not among them: the display draws the limit from a number, see [speedLimit].
  List<ContextSign> get signs => recognizer.signs;

  /// The speed limit the camera read that applies now, or null.
  RecognizedSpeed? get speedLimit => recognizer.speedLimit;

  /// The database has a newer value for the road than the sign the car passed more than [passedM] ago: that sign is dropped.
  bool forgetSpeedPassedBeyond(double passedM) => recognizer.forgetSpeedPassedBeyond(passedM);

  CameraCalibration get calibration => recognizer.calibration;
  set calibration(CameraCalibration c) => recognizer.calibration = c;

  void start() {
    recognizer.reset();
    reporter.reset();
    speedReporter?.reset();
    _fix = null;
  }

  void onFix(Fix fix) {
    _fix = fix;
    recognizer.onFix(fix);
    final speed = speedReporter;
    if (speed != null) {
      unawaited(speed.onFix(lat: fix.lat, lng: fix.lng, heading: fix.heading, odoM: recognizer.odometerM));
    }
  }

  void onFrame(int frameMs, List<RawDetection> detections) => recognizer.onDetections(frameMs, detections);

  void _finished(RecognizedSign s) {
    final fix = _fix;
    if (s.speedKmh != null || speedReporter != null && s.vz == '282') {
      unawaited(speedReporter?.onFinished(s));
    }
    if (s.speedKmh != null) return; // a speed sign is not a sign of the display's catalogue
    if (fix == null) return;
    unawaited(reporter.onFinished(s, carLat: fix.lat, carLng: fix.lng, startsInM: s.signOdoM - recognizer.odometerM));
  }
}
