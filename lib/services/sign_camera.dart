import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:tn_core/tn_core.dart';

import 'camera_frame.dart';

/// Why the camera could not be started.
enum SignCameraError { denied, none, failed }

class SignCameraException implements Exception {
  const SignCameraException(this.error);
  final SignCameraError error;
}

/// The phone's back camera as a source of frames for the sign recognition (the `camera` plugin). The picture is never stored or
/// sent: a frame is turned into a small RGB image in memory, read, and dropped.
class SignCamera {
  CameraController? _controller;
  CameraDescription? _description;

  /// For a preview widget; null while the camera is not running.
  CameraController? get controller => _controller;

  bool get isRunning => _controller?.value.isInitialized == true;

  /// Starts the camera. [onImage] is called for every frame the plugin delivers, with the number of clockwise quarter turns that make
  /// it upright; throttling is the caller's, a frame it does not take costs nothing. Throws [SignCameraException].
  Future<void> start(void Function(CameraImage image, int quarterTurns) onImage) async {
    if (kIsWeb) throw const SignCameraException(SignCameraError.none);
    final List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on CameraException catch (e) {
      throw SignCameraException(_isDenied(e) ? SignCameraError.denied : SignCameraError.failed);
    }
    final back = cameras.where((c) => c.lensDirection == CameraLensDirection.back);
    if (back.isEmpty) throw const SignCameraException(SignCameraError.none);
    final description = back.first;
    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
    );
    try {
      await controller.initialize();
      await controller.startImageStream((image) {
        final turns = quarterTurnsFor(
          sensorOrientation: description.sensorOrientation,
          deviceOrientationDegrees: _degrees(controller.value.deviceOrientation),
        );
        onImage(image, turns);
      });
    } on CameraException catch (e) {
      await controller.dispose();
      throw SignCameraException(_isDenied(e) ? SignCameraError.denied : SignCameraError.failed);
    }
    _controller = controller;
    _description = description;
  }

  Future<void> stop() async {
    final c = _controller;
    _controller = null;
    _description = null;
    if (c == null) return;
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    try {
      await c.dispose();
    } catch (_) {}
  }

  /// The camera's sensor orientation, for tests and diagnostics.
  int? get sensorOrientation => _description?.sensorOrientation;
}

bool _isDenied(CameraException e) => e.code.contains('AccessDenied') || e.code.contains('Restricted');

int _degrees(DeviceOrientation o) => switch (o) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };

/// A camera image as an upright [SignFrame], or null where the format is not one the app reads.
SignFrame? signFrameFrom(CameraImage image, int quarterTurns, {int maxWidth = 960}) {
  final planes = [for (final p in image.planes) RawPlane(p.bytes, p.bytesPerRow, p.bytesPerPixel)];
  switch (image.format.group) {
    case ImageFormatGroup.bgra8888:
      return frameFromRaw(width: image.width, height: image.height, format: RawFormat.bgra8888, planes: planes, quarterTurns: quarterTurns, maxWidth: maxWidth);
    case ImageFormatGroup.yuv420:
      if (planes.length < 3) return null;
      return frameFromRaw(width: image.width, height: image.height, format: RawFormat.yuv420, planes: planes, quarterTurns: quarterTurns, maxWidth: maxWidth);
    default:
      return null;
  }
}
