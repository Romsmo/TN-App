import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:tn_core/tn_core.dart';

import 'sign_camera.dart';
import 'sign_model.dart';

/// What the sign camera is doing.
enum CameraStatus { off, starting, running, noModel, denied, unavailable, failed }

/// The camera with the detector behind it: while a drive runs, frames are read about four times a second, the finder proposes
/// regions, the classifier reads them, and the detections go to the drive session. Frames that arrive while a pass is still running
/// are dropped, so a slow phone reads fewer frames instead of falling behind.
class SignPipeline extends ChangeNotifier {
  SignPipeline({required this.calibration});

  final CameraCalibration Function() calibration;

  CameraStatus _status = CameraStatus.off;
  CameraStatus get status => _status;

  final SignCamera _camera = SignCamera();
  SignModel? _model;
  SignDetector? _detector;
  bool _busy = false;
  int _lastMs = 0;
  int _failures = 0;
  int _generation = 0;
  void Function(int frameMs, List<RawDetection> detections)? _sink;

  /// The minimum time between two passes.
  static const int minGapMs = 250;

  /// After this many passes in a row that threw, the camera is switched off for the drive.
  static const int maxFailures = 8;

  void _set(CameraStatus s) {
    if (_status == s) return;
    _status = s;
    notifyListeners();
  }

  bool _modelAsked = false;

  /// Whether the app has a classifier, as far as known: null until it was asked for once.
  bool? get modelKnown => _modelAsked ? _model != null : null;

  /// Whether the app has a classifier at all (loaded once; false when it was built without a model).
  Future<bool> modelAvailable() async {
    _model ??= await SignModel.load();
    _modelAsked = true;
    return _model != null;
  }

  /// Starts reading signs for the running drive; [onDetections] gets what each pass found.
  Future<void> start(void Function(int frameMs, List<RawDetection> detections) onDetections) async {
    if (_status == CameraStatus.starting || _status == CameraStatus.running) return;
    final gen = ++_generation;
    _set(CameraStatus.starting);
    _failures = 0;
    _sink = onDetections;
    if (!await modelAvailable()) {
      _set(CameraStatus.noModel);
      return;
    }
    final model = _model!;
    _detector = FinderSignDetector(classifier: model.classifier, labels: model.labels, calibration: calibration);
    try {
      await _camera.start(_onImage);
    } on SignCameraException catch (e) {
      if (gen != _generation) return;
      _set(switch (e.error) {
        SignCameraError.denied => CameraStatus.denied,
        SignCameraError.none => CameraStatus.unavailable,
        SignCameraError.failed => CameraStatus.failed,
      });
      return;
    }
    if (gen != _generation) {
      await _camera.stop(); // the drive ended while the camera was starting
      return;
    }
    _set(CameraStatus.running);
  }

  Future<void> stop() async {
    _generation++;
    _sink = null;
    _detector = null;
    await _camera.stop();
    _busy = false;
    _set(CameraStatus.off);
  }

  void _onImage(CameraImage image, int quarterTurns) {
    final sink = _sink;
    final detector = _detector;
    if (sink == null || detector == null || _busy) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastMs < minGapMs) return;
    _lastMs = now;
    final frame = signFrameFrom(image, quarterTurns);
    if (frame == null) return;
    _busy = true;
    unawaited(_pass(detector, frame, now, sink));
  }

  Future<void> _pass(SignDetector detector, SignFrame frame, int ms, void Function(int, List<RawDetection>) sink) async {
    try {
      final found = await detector.detect(frame);
      if (_sink == null) return;
      _failures = 0;
      sink(ms, found);
    } catch (_) {
      if (++_failures >= maxFailures) {
        _set(CameraStatus.failed);
        unawaited(stop().then((_) => _set(CameraStatus.failed)));
      }
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    unawaited(_camera.stop());
    _model?.close();
    super.dispose();
  }
}
