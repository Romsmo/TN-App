import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:tn_core/tn_core.dart';

import '../app_scope.dart';
import '../services/sign_camera.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'common.dart';

/// Aligns the phone's camera for the sign recognition. The owner stands the car on a straight road and drags a cross onto the
/// point where the road disappears (it gives the direction of travel and the height of the horizon in the image) and turns a line
/// with a slider until it lies on the horizon (it gives the roll). A small picture shows what the recognition itself sees, so a
/// wrongly turned image shows up here and not on the road.
class CameraCalibrationScreen extends StatefulWidget {
  const CameraCalibrationScreen({super.key});

  @override
  State<CameraCalibrationScreen> createState() => _CameraCalibrationScreenState();
}

class _CameraCalibrationScreenState extends State<CameraCalibrationScreen> {
  final SignCamera _camera = SignCamera();
  double _vx = 0.5;
  double _vy = 0.5;
  double _roll = 0;
  double _aspect = 16 / 9;
  bool _ready = false;
  bool _failed = false;
  ui.Image? _thumb;
  int _lastThumbMs = 0;
  bool _thumbBusy = false;

  @override
  void initState() {
    super.initState();
    final saved = context.app.settings.value.cameraCalibration;
    if (saved.isCalibrated) {
      _vx = saved.vanishingX;
      _vy = saved.horizonY;
      _roll = saved.rollDeg;
      _aspect = saved.aspect;
    }
    if (!context.app.drive.isActive) _start();
  }

  Future<void> _start() async {
    try {
      await _camera.start(_onImage);
      if (mounted) setState(() => _ready = true);
    } on SignCameraException {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onImage(CameraImage image, int turns) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_thumbBusy || now - _lastThumbMs < 500) return;
    _lastThumbMs = now;
    final frame = signFrameFrom(image, turns, maxWidth: 240);
    if (frame == null) return;
    _thumbBusy = true;
    final rgba = Uint8List(frame.width * frame.height * 4);
    for (var i = 0, j = 0, k = 0; i < frame.width * frame.height; i++) {
      rgba[k++] = frame.rgb[j++];
      rgba[k++] = frame.rgb[j++];
      rgba[k++] = frame.rgb[j++];
      rgba[k++] = 255;
    }
    ui.decodeImageFromPixels(rgba, frame.width, frame.height, ui.PixelFormat.rgba8888, (img) {
      _thumbBusy = false;
      if (!mounted) return;
      final old = _thumb;
      setState(() {
        _thumb = img;
        _aspect = frame.width / frame.height;
      });
      old?.dispose();
    });
  }

  @override
  void dispose() {
    unawaited(_camera.stop());
    _thumb?.dispose();
    super.dispose();
  }

  CameraCalibration get _current => CameraCalibration(
        vanishingX: _vx,
        horizonY: _vy,
        rollDeg: _roll,
        aspect: _aspect,
        calibratedAtMs: DateTime.now().millisecondsSinceEpoch,
      );

  Future<void> _save() async {
    await context.app.settings.update((x) => x.copyWith(cameraCalibration: _current));
    if (mounted) Navigator.of(context).pop();
  }

  String? _problemText(BuildContext context) {
    final p = _current.problem;
    return p == null ? null : context.t('camera.cal.problem.${p.name}');
  }

  @override
  Widget build(BuildContext context) {
    if (context.app.drive.isActive) {
      return SubPage(title: context.t('camera.cal.title'), children: [Hint(context.t('camera.cal.driveRunning'))]);
    }
    final c = context.colors;
    final controller = _camera.controller;
    final problem = _problemText(context);
    return SubPage(title: context.t('camera.cal.title'), children: [
      if (_failed) Notice(text: context.t('camera.cal.error'), icon: Icons.error_outline, color: c.danger),
      if (_ready && controller != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.md),
          child: AspectRatio(
            aspectRatio: _previewAspect(controller),
            child: Stack(fit: StackFit.expand, children: [
              CameraPreview(controller),
              LayoutBuilder(builder: (context, box) {
                void move(Offset p) => setState(() {
                      _vx = (p.dx / box.maxWidth).clamp(0.0, 1.0);
                      _vy = (p.dy / box.maxHeight).clamp(0.0, 1.0);
                    });
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) => move(d.localPosition),
                  onPanUpdate: (d) => move(d.localPosition),
                  onTapDown: (d) => move(d.localPosition),
                  child: CustomPaint(painter: _MarkerPainter(_vx, _vy, _roll, c.tint)),
                );
              }),
            ]),
          ),
        )
      else if (!_failed)
        const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
      CardSection(children: [
        Body(context.t('camera.cal.roll', {'deg': _roll.toStringAsFixed(1)})),
        Slider(
          value: _roll,
          min: -15,
          max: 15,
          divisions: 60,
          onChanged: (v) => setState(() => _roll = v),
        ),
        Hint(context.t('camera.cal.steps')),
        if (problem != null) Notice(text: problem, icon: Icons.warning_amber, color: c.danger),
      ]),
      if (_thumb != null)
        CardSection(children: [
          Hint(context.t('camera.cal.thumb')),
          Center(child: SizedBox(width: 200, child: AspectRatio(aspectRatio: _aspect, child: RawImage(image: _thumb, fit: BoxFit.fill)))),
        ]),
      PrimaryButton(label: context.t('camera.cal.save'), onPressed: _ready ? _save : null),
    ]);
  }

  /// The preview's shape as the plugin shows it: its sensor value is landscape, turned when the phone is held upright.
  double _previewAspect(CameraController c) {
    final landscape = c.value.deviceOrientation == DeviceOrientation.landscapeLeft || c.value.deviceOrientation == DeviceOrientation.landscapeRight;
    final a = c.value.aspectRatio;
    return landscape ? a : 1 / a;
  }
}

class _MarkerPainter extends CustomPainter {
  _MarkerPainter(this.vx, this.vy, this.rollDeg, this.color);
  final double vx;
  final double vy;
  final double rollDeg;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Offset(vx * size.width, vy * size.height);
    final line = Paint()
      ..color = color
      ..strokeWidth = 2;
    final shadow = Paint()
      ..color = const Color(0x99000000)
      ..strokeWidth = 4;
    final r = rollDeg * math.pi / 180;
    final dir = Offset(math.cos(r), math.sin(r)) * (size.width * 1.5);
    canvas.drawLine(p - dir, p + dir, shadow);
    canvas.drawLine(p - dir, p + dir, line);
    // the cross: the direction of travel
    canvas.drawLine(Offset(p.dx, p.dy - 22), Offset(p.dx, p.dy + 22), shadow);
    canvas.drawLine(Offset(p.dx, p.dy - 22), Offset(p.dx, p.dy + 22), line);
    canvas.drawCircle(p, 8, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_MarkerPainter old) => old.vx != vx || old.vy != vy || old.rollDeg != rollDeg || old.color != color;
}
