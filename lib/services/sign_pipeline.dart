import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:tn_core/tn_core.dart';

import 'sign_camera.dart';
import 'sign_model.dart';

/// What the sign camera is doing.
enum CameraStatus { off, starting, running, noModel, denied, unavailable, failed }

/// What the camera view shows: the regions of the latest frame the finder proposed (and what each was read as), the shape of the
/// frame, and how fast the passes run.
class CameraViewState {
  const CameraViewState({this.boxes = const [], this.aspect = 16 / 9, this.passMs = 0, this.frames = 0});
  final List<SignBox> boxes;

  /// Width over height of the upright frame the boxes are normalised to.
  final double aspect;

  /// How long the latest pass took (frame to detections), in milliseconds, and how many passes have run since the camera started.
  final int passMs;
  final int frames;
}

/// The camera with the detector behind it: while a drive runs (or the camera view is open), frames are read several times a second,
/// the finder proposes regions, the classifier reads them, and the detections go to the drive session. Frames that arrive while a
/// pass is still running are dropped, so a slow phone reads fewer frames instead of falling behind.
///
/// The camera runs as long as the drive or a camera view wants it. Nothing about the alignment is asked of the owner: the
/// recognition learns it from the signs (see `AutoCalibration`).
class SignPipeline extends ChangeNotifier {
  SignPipeline({required this.calibration});

  final CameraCalibration Function() calibration;

  CameraStatus _status = CameraStatus.off;
  CameraStatus get status => _status;

  /// For the camera view; updated once per pass while a view is open, and not at all otherwise.
  final ValueNotifier<CameraViewState> view = ValueNotifier(const CameraViewState());

  final SignCamera _camera = SignCamera();
  SignModel? _model;
  SignDetector? _detector;
  bool _usingLocator = false;
  bool _busy = false;
  int _lastMs = 0;
  int _failures = 0;
  int _generation = 0;
  int _frames = 0;
  int _viewers = 0;
  void Function(int frameMs, List<RawDetection> detections)? _sink;

  /// The minimum time between two passes (about seven a second on a phone that is fast enough).
  static const int minGapMs = 140;

  /// After this many passes in a row that threw, the camera is switched off.
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

  /// Why there is no model, when the camera says so (the runtime failed to start it, or the files are missing); null otherwise.
  String? get modelError => _model == null && _modelAsked ? SignModel.lastError : null;

  /// Whether the signs are found by the locator network (whole frame) or, without it, by the colour-based candidate finder.
  bool get usingLocator => _usingLocator;

  /// Why the locator is not in use although the classifier is, or null.
  String? get locatorError => _modelAsked && _model != null && _model!.locator == null ? SignModel.locatorError : null;

  /// The running camera, for a preview widget; null while it is not running.
  CameraController? get previewController => _status == CameraStatus.running ? _camera.controller : null;

  /// Starts reading signs for the running drive; [onDetections] gets what each pass found.
  Future<void> start(void Function(int frameMs, List<RawDetection> detections) onDetections) async {
    _sink = onDetections;
    await _ensureCamera();
  }

  /// The drive ended. The camera stays on only while a camera view is open.
  Future<void> stop() async {
    _sink = null;
    await _stopIfUnused();
  }

  /// A camera view opened: the camera runs (also outside a drive) and the view gets the boxes of every pass.
  Future<void> attachView() async {
    _viewers++;
    await _ensureCamera();
  }

  Future<void> detachView() async {
    if (_viewers > 0) _viewers--;
    await _stopIfUnused();
  }

  Future<void> _ensureCamera() async {
    if (_status == CameraStatus.starting || _status == CameraStatus.running) return;
    final gen = ++_generation;
    _set(CameraStatus.starting);
    _failures = 0;
    if (!await modelAvailable()) {
      _set(CameraStatus.noModel);
      return;
    }
    final model = _model!;
    final locator = model.locator;
    _usingLocator = locator != null;
    _detector = locator != null
        ? HeatmapSignDetector(locator: locator, classifier: model.classifier, labels: model.labels)
        : FinderSignDetector(classifier: model.classifier, labels: model.labels, calibration: calibration);
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
    if (gen != _generation || (_sink == null && _viewers == 0)) {
      await _camera.stop(); // the drive ended (or the view closed) while the camera was starting
      if (gen == _generation) _set(CameraStatus.off);
      return;
    }
    _frames = 0;
    _set(CameraStatus.running);
  }

  Future<void> _stopIfUnused() async {
    if (_sink != null || _viewers > 0) return;
    _generation++;
    _detector = null;
    await _camera.stop();
    _busy = false;
    view.value = const CameraViewState();
    _set(CameraStatus.off);
  }

  void _onImage(CameraImage image, int quarterTurns) {
    final detector = _detector;
    if (detector == null || _busy || (_sink == null && _viewers == 0)) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastMs < minGapMs) return;
    _lastMs = now;
    final frame = signFrameFrom(image, quarterTurns);
    if (frame == null) return;
    _busy = true;
    unawaited(_pass(detector, frame, now));
  }

  Future<void> _pass(SignDetector detector, SignFrame frame, int ms) async {
    try {
      final found = await detector.detect(frame);
      if (_detector == null) return;
      _failures = 0;
      _frames++;
      _sink?.call(ms, found);
      if (_viewers > 0) {
        view.value = CameraViewState(
          boxes: detector.lastBoxes,
          aspect: frame.width / frame.height,
          passMs: DateTime.now().millisecondsSinceEpoch - ms,
          frames: _frames,
        );
      }
    } catch (_) {
      if (++_failures >= maxFailures) {
        _sink = null;
        _viewers = 0;
        unawaited(_stopIfUnused().then((_) => _set(CameraStatus.failed)));
      }
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    unawaited(_camera.stop());
    _model?.close();
    view.dispose();
    super.dispose();
  }
}
