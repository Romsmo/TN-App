import 'dart:async';

import '../drive/fix.dart';
import '../tn/types.dart';
import 'camera_calibration.dart';
import 'sign_recognizer.dart';
import 'sign_reporter.dart';

/// The camera side of a drive: the recogniser, which places signs on the road from the detections, and the reporter, which feeds the
/// database from them. The drive session owns one while the camera is switched on; the app feeds it frames.
class SignVision {
  SignVision({required this.recognizer, required this.reporter}) {
    recognizer.onFinished = _finished;
    recognizer.onStretchEnded = (start, end) => unawaited(reporter.onStretchEnded(start, end));
  }

  final SignRecognizer recognizer;
  final SignReporter reporter;
  Fix? _fix;

  /// The signs the camera read that are in force or just ahead (entries like the database's, marked `fromCamera`).
  List<ContextSign> get signs => recognizer.signs;

  CameraCalibration get calibration => recognizer.calibration;
  set calibration(CameraCalibration c) => recognizer.calibration = c;

  void start() {
    recognizer.reset();
    reporter.reset();
    _fix = null;
  }

  void onFix(Fix fix) {
    _fix = fix;
    recognizer.onFix(fix);
  }

  void onFrame(int frameMs, List<RawDetection> detections) => recognizer.onDetections(frameMs, detections);

  void _finished(RecognizedSign s) {
    final fix = _fix;
    if (fix == null) return;
    unawaited(reporter.onFinished(s, carLat: fix.lat, carLng: fix.lng, startsInM: s.signOdoM - recognizer.odometerM));
  }
}
