import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:tn_core/tn_core.dart';

import '../app_scope.dart';
import '../services/sign_pipeline.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'common.dart';

/// "Kamera-Ansicht": what the phone's camera sees. The live picture with a frame around every region the recognition looked at:
/// green where it read a sign (with its name), amber where something red looked like a sign but was not read as one. During a drive
/// the signs the recognition follows are marked and listed. Nothing here is stored or sent; nothing has to be set.
class CameraViewScreen extends StatefulWidget {
  const CameraViewScreen({super.key});

  @override
  State<CameraViewScreen> createState() => _CameraViewScreenState();
}

class _CameraViewScreenState extends State<CameraViewScreen> {
  SignPipeline? _pipeline;

  @override
  void initState() {
    super.initState();
    final pipeline = context.app.drive.pipeline;
    _pipeline = pipeline;
    pipeline.attachView();
  }

  @override
  void dispose() {
    _pipeline?.detachView();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pipeline = app.drive.pipeline;
    return ListenableBuilder(
      listenable: Listenable.merge([app.drive, pipeline]),
      builder: (context, _) {
        final c = context.colors;
        final status = pipeline.status;
        final snapshot = app.drive.snapshot;
        final driving = snapshot?.active == true;
        final tracked = driving ? snapshot!.recognizedSigns : const <ContextSign>[];
        final trackedVz = {for (final s in tracked) s.signType.startsWith('DE:') ? s.signType.substring(3) : s.signType};
        final limit = driving && snapshot!.limitFromCamera ? snapshot.limit?.value.round() : null;
        final auto = app.drive.autoCalibration;
        return SubPage(title: context.t('camera.view.title'), children: [
          _Picture(pipeline: pipeline, status: status, trackedVz: trackedVz, trackedSpeed: limit),
          ValueListenableBuilder<CameraViewState>(
            valueListenable: pipeline.view,
            builder: (context, v, _) {
              final read = v.boxes.where((b) => b.read).length;
              final other = v.boxes.length - read;
              return CardSection(children: [
                if (status == CameraStatus.running) ...[
                  Body(v.boxes.isEmpty
                      ? context.t('camera.view.nothing')
                      : context.t('camera.view.found', {'read': read, 'other': other})),
                  Hint(context.t('camera.view.stats', {'ms': v.passMs, 'frames': v.frames})),
                  Hint(context.t(pipeline.usingLocator ? 'camera.view.locator' : 'camera.view.finder')),
                  if (!pipeline.usingLocator && pipeline.locatorError != null) Hint(context.t('camera.view.modelError', {'error': pipeline.locatorError!})),
                ],
                Body(driving
                    ? (tracked.isEmpty && limit == null
                        ? context.t('camera.view.trackedNone')
                        : context.t('camera.view.tracked', {
                            'signs': [
                              if (limit != null) context.t('camera.view.speed', {'value': limit}),
                              for (final s in tracked) signNameOf(s.signType) ?? s.signType,
                            ].join(', '),
                          }))
                    : context.t('camera.view.notDriving')),
                Hint(auto.learned
                    ? context.t('camera.view.aligned', {'n': auto.estimateCount})
                    : context.t('camera.view.aligning')),
              ]);
            },
          ),
          Hint(context.t('camera.view.hint')),
          if (status == CameraStatus.denied || status == CameraStatus.failed || status == CameraStatus.unavailable || status == CameraStatus.noModel)
            Notice(text: context.t('camera.status.${status.name}'), icon: Icons.videocam_off, color: c.danger),
          if (status == CameraStatus.noModel && pipeline.modelError != null) Hint(context.t('camera.view.modelError', {'error': pipeline.modelError!})),
        ]);
      },
    );
  }
}

/// The live picture with the frames drawn over it.
class _Picture extends StatelessWidget {
  const _Picture({required this.pipeline, required this.status, required this.trackedVz, required this.trackedSpeed});
  final SignPipeline pipeline;
  final CameraStatus status;
  final Set<String> trackedVz;
  final int? trackedSpeed;

  @override
  Widget build(BuildContext context) {
    final controller = pipeline.previewController;
    if (status != CameraStatus.running || controller == null) {
      final waiting = status == CameraStatus.starting || status == CameraStatus.off;
      return SizedBox(height: 180, child: Center(child: waiting ? const CircularProgressIndicator() : const Icon(Icons.videocam_off, size: 40)));
    }
    return ValueListenableBuilder<CameraViewState>(
      valueListenable: pipeline.view,
      builder: (context, v, _) {
        final aspect = v.frames > 0 ? v.aspect : _previewAspect(controller);
        return ClipRRect(
          borderRadius: BorderRadius.circular(Radii.md),
          child: AspectRatio(
            aspectRatio: aspect,
            child: Stack(fit: StackFit.expand, children: [
              CameraPreview(controller),
              CustomPaint(
                painter: _BoxesPainter(
                  boxes: v.boxes,
                  trackedVz: trackedVz,
                  trackedSpeed: trackedSpeed,
                  nameOf: (vz) => _nameOf(context, vz),
                  read: const Color(0xFF34C759),
                  unread: const Color(0xFFFFB020),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  /// The preview's shape as the plugin shows it before the first frame: its sensor value is landscape, turned when the phone is
  /// held upright.
  static double _previewAspect(CameraController c) {
    final landscape = c.value.deviceOrientation == DeviceOrientation.landscapeLeft || c.value.deviceOrientation == DeviceOrientation.landscapeRight;
    final a = c.value.aspectRatio;
    return landscape ? a : 1 / a;
  }
}

String _nameOf(BuildContext context, String vz) {
  final speed = speedOfVz(vz);
  if (speed != null) return context.t('camera.view.speed', {'value': speed});
  return signNameOf('DE:$vz') ?? vz;
}

class _BoxesPainter extends CustomPainter {
  _BoxesPainter({
    required this.boxes,
    required this.trackedVz,
    required this.trackedSpeed,
    required this.nameOf,
    required this.read,
    required this.unread,
  });
  final List<SignBox> boxes;
  final Set<String> trackedVz;
  final int? trackedSpeed;
  final String Function(String vz) nameOf;
  final Color read;
  final Color unread;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in boxes) {
      final rect = Rect.fromCenter(center: Offset(b.x * size.width, b.y * size.height), width: b.w * size.width, height: b.h * size.height).inflate(3);
      final vz = b.vz;
      final tracked = vz != null && (trackedVz.contains(vz) || speedOfVz(vz) != null && speedOfVz(vz) == trackedSpeed);
      final color = b.read ? read : unread;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = tracked ? 4 : 2,
      );
      if (vz != null) {
        _label(canvas, size, rect, '${tracked ? '✓ ' : ''}${nameOf(vz)} ${(b.confidence * 100).round()} %', color);
      }
    }
  }

  void _label(Canvas canvas, Size size, Rect rect, String text, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: size.width * 0.6);
    final left = rect.left.clamp(0.0, size.width - tp.width - 8);
    final top = rect.top - tp.height - 6 < 0 ? rect.bottom + 2 : rect.top - tp.height - 6;
    final bg = Rect.fromLTWH(left, top, tp.width + 8, tp.height + 4);
    canvas.drawRRect(RRect.fromRectAndRadius(bg, const Radius.circular(4)), Paint()..color = color);
    tp.paint(canvas, Offset(left + 4, top + 2));
  }

  @override
  bool shouldRepaint(_BoxesPainter old) => true;
}
