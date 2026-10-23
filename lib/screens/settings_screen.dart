import 'package:flutter/material.dart';
import 'package:tn_core/tn_core.dart';

import '../app_scope.dart';
import '../services/app_config.dart';
import '../services/legal.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'common.dart';
import 'data_screen.dart';
import 'info_screen.dart';
import 'server_screen.dart';

/// The "Einstellungen" tab.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _done = false;
  bool _failed = false;

  Future<void> _set(Settings Function(Settings) change) => context.app.settings.update(change);

  Future<void> _reset({required bool identity}) async {
    final ok = await confirmDialog(
      context,
      title: context.t(identity ? 'settings.resetIdentity' : 'settings.deleteLocal'),
      message: context.t(identity ? 'settings.resetIdentityHint' : 'settings.deleteLocalHint'),
      confirmLabel: context.t(identity ? 'settings.resetIdentityConfirm' : 'settings.deleteLocalConfirm'),
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _done = false;
      _failed = false;
    });
    try {
      await context.app.tn.resetLocal(identity: identity);
      if (mounted) setState(() => _done = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _open(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final c = context.colors;
    return ListenableBuilder(
      listenable: Listenable.merge([app.settings, app.tn]),
      builder: (context, _) {
        final s = app.settings.value;
        final policy = app.tn.policy;
        final warnTypes = [...interimCatalog.types(), if (s.camerasEnabled) 'cameras'];
        void toggleWarn(String category, bool on) {
          final off = {...s.warnOffCategories};
          on ? off.remove(category) : off.add(category);
          _set((x) => x.copyWith(warnOffCategories: off.toList()));
        }

        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, tabBarClearance + 16),
            children: [
              ScreenTitle(context.t('tabs.settings')),
              SectionLabel(context.t('settings.section.drive')),
              Group(children: [
                Padding(
                  padding: const EdgeInsets.all(Space.lg),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Body(context.t('settings.units')),
                    const SizedBox(height: Space.sm),
                    Segments<SpeedUnit>(
                      value: s.speedUnit,
                      options: const {SpeedUnit.kmh: 'km/h', SpeedUnit.mph: 'mph'},
                      onChanged: (u) => _set((x) => x.copyWith(speedUnit: u)),
                    ),
                  ]),
                ),
                SwitchRow(
                  leading: const IconTile(icon: Icons.volume_up, color: Color(0xFFFF9500)),
                  title: context.t('settings.sound'),
                  value: s.driveSound,
                  onChanged: (v) => _set((x) => x.copyWith(driveSound: v)),
                ),
                SwitchRow(
                  leading: const IconTile(icon: Icons.chat_bubble, color: Color(0xFF34C759)),
                  title: context.t('settings.voice'),
                  value: s.driveVoice,
                  onChanged: (v) => _set((x) => x.copyWith(driveVoice: v)),
                ),
                Padding(
                  padding: const EdgeInsets.all(Space.lg),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Body(context.t('settings.scale')),
                    const SizedBox(height: Space.sm),
                    Segments<double>(
                      value: s.warnScale,
                      options: {
                        0.75: context.t('settings.scale.near'),
                        1.0: context.t('settings.scale.normal'),
                        1.5: context.t('settings.scale.far'),
                      },
                      onChanged: (v) => _set((x) => x.copyWith(warnScale: v)),
                    ),
                  ]),
                ),
              ]),
              SectionLabel(context.t('settings.warnCategories')),
              Group(children: [
                for (final category in warnTypes)
                  SwitchRow(
                    leading: IconTile(icon: iconFor(hazardIconKey(category)), color: _color(category)),
                    title: context.t('settings.warnCategory', {'type': category == 'cameras' ? context.t('settings.section.cameras') : app.texts.hazardLabel(category)}),
                    value: !s.warnOffCategories.contains(category),
                    onChanged: (on) => toggleWarn(category, on),
                  ),
              ]),
              SectionLabel(context.t('settings.section.cameras')),
              Group(children: [
                _CamerasSwitch(
                  enabled: s.camerasEnabled,
                  maxLevel: policy?.maxLevel,
                  noticeSeen: s.camerasNoticeSeen,
                  serverNoticeVersion: policy?.noticeVersion,
                  onChange: (on) => _set((x) => x.copyWith(camerasEnabled: on)),
                  onNoticeSeen: (key) => _set((x) => x.copyWith(camerasNoticeSeen: key)),
                ),
              ]),
              SectionLabel(context.t('settings.section.safety')),
              Group(children: [
                if (buildConfig.allowDisableDriveLock)
                  _LockSwitch(enabled: s.driveLockEnabled, onChange: (on) => _set((x) => x.copyWith(driveLockEnabled: on)))
                else
                  Padding(padding: const EdgeInsets.all(Space.lg), child: Hint(context.t('lockSwitch.always'))),
              ]),
              SectionLabel(context.t('settings.section.more')),
              Group(children: [
                for (final e in [
                  (context.t('settings.server'), context.t('settings.serverHint'), Icons.dns, const Color(0xFF5856D6), () => _open(const LockGuard(child: ServerScreen()))),
                  (context.t('settings.data'), context.t('settings.dataHint'), Icons.cloud_download, const Color(0xFF30B0C7), () => _open(const LockGuard(child: DataScreen()))),
                  (context.t('settings.info'), context.t('settings.infoHint'), Icons.info, const Color(0xFF007AFF), () => _open(const LockGuard(child: InfoScreen()))),
                ])
                  Semantics(
                    link: true,
                    label: '${e.$1}, ${e.$2}',
                    excludeSemantics: true,
                    child: Row3(
                      leading: IconTile(icon: e.$3, color: e.$4),
                      title: e.$1,
                      hint: e.$2,
                      trailing: Icon(Icons.chevron_right, size: 20, color: c.textSecondary),
                      onTap: e.$5,
                    ),
                  ),
              ]),
              SectionLabel(context.t('settings.section.data')),
              Group(children: [
                Row3(title: context.t('settings.deleteLocal'), danger: true, onTap: () => _reset(identity: false)),
                Row3(title: context.t('settings.resetIdentity'), danger: true, onTap: () => _reset(identity: true)),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
                child: Hint('${context.t('settings.deleteLocalHint')}\n\n${context.t('settings.resetIdentityHint')}'),
              ),
              if (_done) Padding(padding: const EdgeInsets.all(Space.lg), child: Hint(context.t('settings.done'))),
              if (_failed) Padding(padding: const EdgeInsets.all(Space.lg), child: Hint(context.t('settings.failed'))),
              const SizedBox(height: Space.xl),
              Center(child: Hint(context.t('settings.version', {'version': appVersion}))),
            ],
          ),
        );
      },
    );
  }

  Color _color(String category) => category == 'cameras' ? hazardColorHex('fixedSpeedCamera') : hazardColorHex(category);
}

Color hazardColorHex(String type) => Color(int.parse('FF${hazardColor(type).substring(1)}', radix: 16));

/// The speed lock option. Switching it on needs nothing; switching it off shows the warning and needs an explicit
/// confirmation, every single time. Where the option is reachable at all is decided by the screen's [LockGuard].
class _LockSwitch extends StatelessWidget {
  const _LockSwitch({required this.enabled, required this.onChange});
  final bool enabled;
  final ValueChanged<bool> onChange;

  @override
  Widget build(BuildContext context) {
    Future<void> change(bool value) async {
      if (value) {
        onChange(true);
        return;
      }
      final ok = await confirmDialog(
        context,
        title: context.t('lockSwitch.confirmTitle'),
        message: context.app.legal.lockWarning(context.app.texts.language),
        confirmLabel: context.t('lockSwitch.confirm'),
        cancelLabel: context.t('lockSwitch.cancel'),
        danger: true,
      );
      if (ok) onChange(false);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SwitchRow(
        leading: const IconTile(icon: Icons.lock, color: Color(0xFF8E8E93)),
        title: context.t('lockSwitch.label'),
        value: enabled,
        onChanged: change,
      ),
      Padding(padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md), child: Hint(context.t('lockSwitch.hint'))),
    ]);
  }
}

/// What the user has to have seen: our wording's version and, when the server's notice changes, that version too.
String noticeKey(LegalTexts legal, String? serverNoticeVersion) =>
    serverNoticeVersion != null && serverNoticeVersion.isNotEmpty ? '${legal.cameraNoticeVersion}|$serverNoticeVersion' : legal.cameraNoticeVersion;

/// The speed-camera option, off at the first start. Ticking it shows the legal notice once (plainly informing, not a consent
/// dialog) and again only when the wording or the server's notice version changed. When the network's policy allows nothing
/// (`off`) the option is unavailable and says why.
class _CamerasSwitch extends StatelessWidget {
  const _CamerasSwitch({
    required this.enabled,
    required this.maxLevel,
    required this.noticeSeen,
    required this.serverNoticeVersion,
    required this.onChange,
    required this.onNoticeSeen,
  });
  final bool enabled;
  final CameraLevel? maxLevel;
  final String? noticeSeen;
  final String? serverNoticeVersion;
  final ValueChanged<bool> onChange;
  final ValueChanged<String> onNoticeSeen;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final blocked = maxLevel == CameraLevel.off;
    final key = noticeKey(app.legal, serverNoticeVersion);

    Future<void> toggle(bool value) async {
      onChange(value);
      if (value && noticeSeen != key) {
        await infoDialog(
          context,
          title: context.t('cameras.noticeTitle'),
          body: noticeText(app.legal.cameraNotice(app.texts.language), TnText.body.copyWith(color: context.colors.text)),
          okLabel: context.t('cameras.noticeOk'),
        );
        onNoticeSeen(key);
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SwitchRow(
        leading: IconTile(icon: iconFor('camera'), color: hazardColorHex('fixedSpeedCamera')),
        title: context.t('cameras.label'),
        value: enabled && !blocked,
        enabled: !blocked,
        onChanged: toggle,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Hint(context.t('cameras.hint')),
          if (blocked) Hint(context.t('cameras.policyOff')),
          if (maxLevel == CameraLevel.zones) Hint(context.t('cameras.policyZones')),
        ]),
      ),
    ]);
  }
}
