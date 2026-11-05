import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tn_core/tn_core.dart';

import '../app_scope.dart';
import '../services/sign_pipeline.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'camera_calibration_screen.dart';
import 'common.dart';

/// "Schilder per Kamera": the switches of the sign recognition, the alignment of the camera and what the camera is doing.
class CameraSignsScreen extends StatefulWidget {
  const CameraSignsScreen({super.key});

  @override
  State<CameraSignsScreen> createState() => _CameraSignsScreenState();
}

class _CameraSignsScreenState extends State<CameraSignsScreen> {
  bool? _modelOk;

  @override
  void initState() {
    super.initState();
    context.app.drive.pipeline.modelAvailable().then((ok) {
      if (mounted) setState(() => _modelOk = ok);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return ListenableBuilder(
      listenable: Listenable.merge([app.settings, app.drive]),
      builder: (context, _) {
        final s = app.settings.value;
        final cal = s.cameraCalibration;
        final status = app.drive.cameraStatus;
        final c = context.colors;
        return SubPage(title: context.t('camera.title'), children: [
          CardSection(children: [
            SwitchRow(
              title: context.t('camera.switch'),
              hint: context.t('camera.switchHint'),
              value: s.cameraSigns,
              onChanged: (on) => app.settings.update((x) => x.copyWith(cameraSigns: on)),
            ),
            if (_modelOk == false) Notice(text: context.t('camera.modelMissing'), icon: Icons.info_outline),
            Hint(context.t('camera.limits')),
          ]),
          CardSection(title: context.t('camera.calibration'), children: [
            Body(cal.isCalibrated
                ? context.t('camera.calibrated', {'date': DateFormat('dd.MM.yyyy').format(DateTime.fromMillisecondsSinceEpoch(cal.calibratedAtMs!))})
                : context.t('camera.notCalibrated')),
            const SizedBox(height: Space.sm),
            PrimaryButton(
              label: context.t(cal.isCalibrated ? 'camera.recalibrate' : 'camera.calibrate'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CameraCalibrationScreen())),
            ),
          ]),
          CardSection(children: [
            SwitchRow(
              title: context.t('camera.report'),
              hint: context.t('camera.reportHint'),
              value: s.cameraSignsReport && s.cameraSigns,
              enabled: s.cameraSigns,
              onChanged: (on) => app.settings.update((x) => x.copyWith(cameraSignsReport: on)),
            ),
            if (!s.cameraSigns) Hint(context.t('camera.reportNeedsCamera')),
          ]),
          if (status != CameraStatus.off)
            Notice(
              text: context.t('camera.status.${status.name}'),
              icon: status == CameraStatus.running || status == CameraStatus.starting ? Icons.videocam : Icons.videocam_off,
              color: status == CameraStatus.running ? c.tint : null,
            ),
        ]);
      },
    );
  }
}

/// The one-line summary of the sign camera for the settings list.
String cameraSummary(BuildContext context, Settings s, bool? modelOk) {
  if (!s.cameraSigns) return context.t('camera.summary.off');
  if (modelOk == false) return context.t('camera.summary.noModel');
  if (!s.cameraCalibration.isCalibrated) return context.t('camera.summary.notCalibrated');
  return context.t('camera.summary.ready');
}
