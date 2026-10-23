import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tn_core/tn_core.dart';

import '../app_scope.dart';
import '../services/drive_controller.dart';
import '../services/legal.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

Color _hex(String hex) => Color(int.parse('FF${hex.substring(1)}', radix: 16));

Color hazardColorOf(String type) => _hex(hazardColor(type));

/// The "Fahrmodus" tab: the start page, or the running drive.
class DriveScreen extends StatefulWidget {
  const DriveScreen({super.key});

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> {
  bool _starting = false;
  String? _error;

  Future<void> _begin(DriveMode mode, int speedup) async {
    final app = context.app;
    setState(() {
      _error = null;
      _starting = true;
    });
    try {
      await app.drive.start(mode, speedup: speedup);
    } catch (_) {
      if (mounted) setState(() => _error = context.t('drive.noPermission'));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _request(DriveMode mode, [int speedup = 1]) async {
    final app = context.app;
    if (!app.settings.value.driveNoticeSeen) {
      final language = app.texts.language;
      await infoDialog(
        context,
        title: context.t('driveNotice.title'),
        body: noticeText(
          app.legal.driveNotice(language),
          TnText.body.copyWith(color: context.colors.text),
        ),
        okLabel: context.t('driveNotice.ok'),
      );
      await app.settings.update((s) => s.copyWith(driveNoticeSeen: true));
      if (!mounted) return;
    }
    await _begin(mode, speedup);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return ListenableBuilder(
      listenable: Listenable.merge([app.drive, app.settings, app.tn]),
      builder: (context, _) {
        if (app.drive.snapshot?.active == true) return const RunningDrive();
        final c = context.colors;
        return SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                20,
                20,
                20,
                tabBarClearance + 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ScreenTitle(context.t('tabs.drive')),
                  const SizedBox(height: Space.md),
                  Text(
                    context.t('drive.startHint'),
                    style: TnText.body.copyWith(color: c.textSecondary),
                  ),
                  if (app.tn.snapshot.emergency != null) ...[
                    const SizedBox(height: Space.md),
                    Text(
                      context.t('emergency.driveHint'),
                      style: TnText.body.copyWith(color: c.textSecondary),
                    ),
                  ],
                  const SizedBox(height: Space.md),
                  PrimaryButton(
                    icon: Icons.play_circle,
                    label: _starting
                        ? context.t('drive.starting')
                        : context.t('drive.start'),
                    onPressed: _starting || !canDriveForReal
                        ? null
                        : () => _request(DriveMode.real),
                  ),
                  const SizedBox(height: Space.lg),
                  Text(
                    context.t('drive.simulateHint'),
                    style: TnText.body.copyWith(color: c.textSecondary),
                  ),
                  const SizedBox(height: Space.md),
                  SoftButton(
                    icon: Icons.science,
                    label: context.t('drive.simulate'),
                    onPressed: _starting
                        ? null
                        : () => _request(DriveMode.simulation),
                  ),
                  const SizedBox(height: Space.sm),
                  SoftButton(
                    icon: Icons.bolt,
                    label: context.t('drive.simulateFast'),
                    onPressed: _starting
                        ? null
                        : () => _request(DriveMode.simulation, 4),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: Space.md),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyle(fontSize: 16, color: c.danger),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The running drive: reads the session snapshot and offers the actions.
class RunningDrive extends StatefulWidget {
  const RunningDrive({super.key});

  @override
  State<RunningDrive> createState() => _RunningDriveState();
}

class _RunningDriveState extends State<RunningDrive> {
  String? _toast;
  Timer? _toastTimer;

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  void _showToast(String text) {
    setState(() => _toast = text);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return ListenableBuilder(
      listenable: Listenable.merge([app.drive, app.settings, app.tn]),
      builder: (context, _) {
        final snapshot = app.drive.snapshot;
        if (snapshot == null) return const SizedBox.shrink();
        final s = app.settings.value;
        final policy = app.tn.policy;
        final session = app.drive.session;
        return DriveView(
          snapshot: snapshot,
          unit: s.speedUnit,
          lockEnabled: s.driveLockEnabled,
          emergency: app.tn.snapshot.emergency != null,
          reportTypes: driveReportTypes(
            s.camerasEnabled && policy?.active == true,
            policy?.maxLevel,
          ),
          toast: _toast,
          onReport: (type) async {
            final reported = context.t('drive.reported');
            final failed = context.t('drive.reportFailed');
            final ok = await session?.report(type) ?? false;
            if (mounted) _showToast(ok ? reported : failed);
          },
          onAnswer: (still) => session?.answerPrompt(still),
          onMute: () => session?.setMuted(!snapshot.muted),
          onStop: app.drive.stop,
          onEnableLock: () =>
              app.settings.update((x) => x.copyWith(driveLockEnabled: true)),
        );
      },
    );
  }
}

/// The drive-mode screen: only what is needed. Speed and limit, warnings ahead, one-tap reports, the "still there?"
/// card. Everything is large and high-contrast; there is no menu and no text input.
class DriveView extends StatefulWidget {
  const DriveView({
    super.key,
    required this.snapshot,
    required this.unit,
    required this.lockEnabled,
    this.emergency = false,
    this.screenMayDim = false,
    required this.reportTypes,
    this.toast,
    required this.onReport,
    required this.onAnswer,
    required this.onMute,
    required this.onStop,
    required this.onEnableLock,
  });

  final DriveSnapshot snapshot;
  final SpeedUnit unit;
  final bool lockEnabled;

  /// No data has ever been loaded, so there is no limit and no warning, only the speed.
  final bool emergency;

  /// The screen could not be kept on: say so, the drive needs the screen.
  final bool screenMayDim;
  final List<String> reportTypes;
  final String? toast;
  final void Function(String type) onReport;
  final void Function(bool stillThere) onAnswer;
  final VoidCallback onMute;
  final VoidCallback onStop;
  final VoidCallback onEnableLock;

  @override
  State<DriveView> createState() => _DriveViewState();
}

class _DriveViewState extends State<DriveView> {
  // The camera kinds sit behind one "Blitzer" tile, so the first screen keeps its few, large buttons.
  bool _cameraPanel = false;

  Widget _chip(
    IconData icon,
    String text, {
    Color? color,
    VoidCallback? onTap,
    String? hint,
  }) {
    final fg = color == DrivePalette.tint
        ? DrivePalette.onTint
        : DrivePalette.text;
    final child = Container(
      constraints: BoxConstraints(minHeight: onTap != null ? minTouch - 8 : 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color ?? DrivePalette.badge,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      liveRegion: true,
      button: onTap != null,
      label: text,
      hint: hint,
      child: onTap == null
          ? child
          : GestureDetector(onTap: onTap, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.snapshot;
    final unit = widget.unit;
    final speed = displaySpeed(s.speedKmh, unit);
    final limit = s.limit != null
        ? displayLimit(s.limit!.value, s.limit!.unit, unit)
        : null;
    final over = s.speedState == SpeedState.over;
    final cameras = widget.reportTypes.where(isCameraType).toList();
    final plain = widget.reportTypes.where((t) => !isCameraType(t)).toList();

    void report(String type) {
      setState(() => _cameraPanel = false);
      widget.onReport(type);
    }

    return ColoredBox(
      color: DrivePalette.background,
      child: SafeArea(
        bottom: false,
        // On a small screen the content scrolls instead of overflowing; the warnings area is the flexible spacer.
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    14,
                    12,
                    14,
                    tabBarClearance,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (s.simulated)
                            _chip(
                              Icons.science,
                              context.t('drive.simulated'),
                              color: DrivePalette.tint,
                            ),
                          if (widget.screenMayDim)
                            _chip(
                              Icons.wb_sunny,
                              context.t('drive.screenMayDim'),
                            ),
                          if (widget.emergency)
                            _chip(
                              Icons.cloud_off,
                              context.t('emergency.driveChip'),
                            ),
                          if (s.limitUnavailable && !widget.emergency)
                            _chip(
                              Icons.cloud_off,
                              context.t('drive.limitUnavailable'),
                            ),
                          if (s.gpsLost)
                            _chip(
                              Icons.signal_cellular_alt,
                              context.t('drive.noGps'),
                            ),
                          if (!widget.lockEnabled)
                            _chip(
                              Icons.lock_open,
                              context.t('drive.lockOff'),
                              onTap: widget.onEnableLock,
                              hint: context.t('drive.lockOffHint'),
                            ),
                        ],
                      ),
                      if (s.heading != null) ...[
                        const SizedBox(height: 8),
                        _Compass(heading: s.heading!),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Semantics(
                              container: true,
                              label:
                                  '${speed ?? '—'} ${unitLabel(unit)}${over ? ', ${context.t('drive.overLimit')}' : ''}',
                              child: ExcludeSemantics(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        '${speed ?? '—'}',
                                        style: TextStyle(
                                          fontSize: 112,
                                          fontWeight: FontWeight.w800,
                                          height: 1.05,
                                          letterSpacing: -4,
                                          color: over
                                              ? DrivePalette.over
                                              : DrivePalette.ok,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 18,
                                        ),
                                        child: Text(
                                          unitLabel(unit),
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w600,
                                            color: DrivePalette.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (limit != null)
                            Semantics(
                              container: true,
                              label: context.t('drive.limit', {'value': limit}),
                              child: ExcludeSemantics(
                                child: Container(
                                  width: 96,
                                  height: 96,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: DrivePalette.sign,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: DrivePalette.signRing,
                                      width: 9,
                                    ),
                                  ),
                                  child: Text(
                                    '$limit',
                                    style: const TextStyle(
                                      fontSize: 38,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -1,
                                      color: DrivePalette.signInk,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: s.warnings.isEmpty
                                ? [
                                    Icon(
                                      s.speedKmh == null
                                          ? Icons.my_location
                                          : widget.emergency
                                          ? Icons.cloud_off
                                          : Icons.radio,
                                      size: 28,
                                      color: DrivePalette.textSecondary,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      s.speedKmh == null
                                          ? context.t('drive.waiting')
                                          : widget.emergency
                                          ? context.t('emergency.driveCalm')
                                          : context.t('drive.watching'),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        color: DrivePalette.textSecondary,
                                      ),
                                    ),
                                  ]
                                : [
                                    for (final w in s.warnings)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: _WarningCard(w: w),
                                      ),
                                  ],
                          ),
                        ),
                      ),
                      if (s.prompt != null) ...[
                        _PromptCard(
                          prompt: s.prompt!,
                          onAnswer: widget.onAnswer,
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (widget.toast != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Semantics(
                            liveRegion: true,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: DrivePalette.surface,
                                borderRadius: BorderRadius.circular(Radii.md),
                              ),
                              child: Text(
                                widget.toast!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: DrivePalette.text,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_cameraPanel)
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: Text(
                                context.t('drive.report.cameraTitle'),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: DrivePalette.text,
                                ),
                              ),
                            ),
                            for (final t in cameras)
                              _ReportTile(
                                type: t,
                                short: true,
                                onPressed: () => report(t),
                              ),
                            _BackTile(
                              onPressed: () =>
                                  setState(() => _cameraPanel = false),
                            ),
                          ],
                        )
                      else
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final t in plain)
                              _ReportTile(type: t, onPressed: () => report(t)),
                            if (cameras.isNotEmpty)
                              _CamerasTile(
                                onPressed: () =>
                                    setState(() => _cameraPanel = true),
                              ),
                          ],
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _BigButton(
                              label: s.muted
                                  ? context.t('drive.unmute')
                                  : context.t('drive.mute'),
                              icon: s.muted
                                  ? Icons.volume_up
                                  : Icons.volume_off,
                              onPressed: widget.onMute,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _BigButton(
                              label: context.t('drive.stop'),
                              icon: Icons.stop_circle,
                              onPressed: widget.onStop,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Compass extends StatelessWidget {
  const _Compass({required this.heading});
  final double heading;

  @override
  Widget build(BuildContext context) {
    final point = context.t('compass.${cardinalIndex(heading)}');
    return Semantics(
      container: true,
      label: context.t('drive.heading', {'point': point}),
      child: ExcludeSemantics(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: DrivePalette.tile,
                shape: BoxShape.circle,
              ),
              child: Transform.rotate(
                angle: heading * math.pi / 180,
                child: const Icon(
                  Icons.arrow_circle_up,
                  size: 30,
                  color: DrivePalette.tint,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              point,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: DrivePalette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.w});
  final ActiveWarning w;

  @override
  Widget build(BuildContext context) {
    final second = w.level == WarnLevel.second;
    final bg = second ? DrivePalette.warnSecond : DrivePalette.warnFirst;
    final zone = w.kind == WarnKind.zone;
    return Semantics(
      container: true,
      label: zone
          ? context.t('drive.warnZone')
          : context.t('drive.warnPoint', {
              'what': w.label,
              'distance': w.distanceM ?? 0,
            }),
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(Radii.lg),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: DrivePalette.onWarn,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  iconFor(hazardIconKey(zone ? 'zone' : w.category)),
                  size: 30,
                  color: bg,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      w.label,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: DrivePalette.onWarn,
                      ),
                    ),
                    Text(
                      zone
                          ? context.t('drive.zoneHint')
                          : context.t('drive.inMeters', {
                              'distance': w.distanceM ?? 0,
                            }),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: DrivePalette.onWarn,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.prompt, required this.onAnswer});
  final DrivePrompt prompt;
  final void Function(bool) onAnswer;

  @override
  Widget build(BuildContext context) {
    final label = context.app.texts.hazardLabel(prompt.hazardType);
    return Semantics(
      liveRegion: true,
      scopesRoute: false,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: DrivePalette.surface,
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.t('drive.stillThere', {'what': label}),
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: DrivePalette.text,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _BigButton(
                    label: context.t('vote.still'),
                    icon: Icons.check_circle,
                    primary: true,
                    onPressed: () => onAnswer(true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _BigButton(
                    label: context.t('vote.gone'),
                    icon: Icons.cancel,
                    onPressed: () => onAnswer(false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.type,
    required this.onPressed,
    this.short = false,
  });
  final String type;
  final VoidCallback onPressed;
  final bool short;

  @override
  Widget build(BuildContext context) {
    final texts = context.app.texts;
    final label = short
        ? context.t('drive.camera.$type')
        : texts.hazardLabel(type);
    final width = (MediaQuery.sizeOf(context).width - 28 - 10) / 2;
    return Semantics(
      button: true,
      label: context.t('report.type', {'type': texts.hazardLabel(type)}),
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: width,
          constraints: const BoxConstraints(minHeight: driveTile),
          padding: EdgeInsets.symmetric(horizontal: short ? 12 : 14),
          decoration: BoxDecoration(
            color: DrivePalette.tile,
            borderRadius: BorderRadius.circular(Radii.lg),
          ),
          child: Row(
            children: [
              Container(
                width: short ? 36 : 48,
                height: short ? 36 : 48,
                decoration: BoxDecoration(
                  color: hazardColorOf(type),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  iconFor(hazardIconKey(type)),
                  size: short ? 20 : 26,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: short ? 10 : 12),
              Flexible(
                child: Text(
                  label,
                  maxLines: short ? 1 : null,
                  overflow: short ? TextOverflow.ellipsis : null,
                  style: TextStyle(
                    fontSize: short ? 19 : 20,
                    fontWeight: FontWeight.w800,
                    color: DrivePalette.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CamerasTile extends StatelessWidget {
  const _CamerasTile({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 28 - 10) / 2;
    return Semantics(
      button: true,
      label: context.t('drive.report.cameras'),
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: width,
          constraints: const BoxConstraints(minHeight: driveTile),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: DrivePalette.tile,
            borderRadius: BorderRadius.circular(Radii.lg),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: hazardColorOf('cameras'),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  iconFor(hazardIconKey('cameras')),
                  size: 26,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  context.t('drive.report.cameras'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: DrivePalette.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackTile extends StatelessWidget {
  const _BackTile({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 28 - 10) / 2;
    return Semantics(
      button: true,
      label: context.t('common.back'),
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: width,
          constraints: const BoxConstraints(minHeight: driveTile),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: DrivePalette.tile,
            borderRadius: BorderRadius.circular(Radii.lg),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.chevron_left,
                size: 26,
                color: DrivePalette.text,
              ),
              const SizedBox(width: 10),
              Text(
                context.t('common.back'),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: DrivePalette.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? DrivePalette.onTint : DrivePalette.text;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: driveTile - 16),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: primary ? DrivePalette.tint : DrivePalette.tile,
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 26, color: fg),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
