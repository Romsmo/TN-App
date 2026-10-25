import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tn_core/tn_core.dart';

import '../app_scope.dart';
import '../services/display_controller.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'common.dart';

/// "Display": choose the TN display, see its state, set what it shows and where announcements play, update its firmware. Reached
/// from the settings once the feature is switched on there (and so locked while driving, like every settings page).
class DisplayScreen extends StatelessWidget {
  const DisplayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return ListenableBuilder(
      listenable: Listenable.merge([app.settings, app.display]),
      builder: (context, _) {
        final s = app.settings.value;
        final d = app.display;
        final chosen = s.displayDeviceId != null;
        return SubPage(
          title: context.t('display.title'),
          children: [
            _Hero(controller: d, chosen: chosen),
            if (chosen) ...[
              Group(children: [
                SwitchRow(
                  leading: const IconTile(icon: Icons.bluetooth_connected, color: Color(0xFF0A84FF)),
                  title: context.t('display.use'),
                  hint: context.t('display.useHint'),
                  value: s.displayEnabled,
                  onChanged: d.setEnabled,
                ),
              ]),
            ],
            if (d.info != null) _DeviceCard(controller: d),
            SectionLabel(context.t('display.scan')),
            _ScanCard(controller: d, chosen: chosen),
            if (chosen) ...[
              SectionLabel(context.t('display.sound')),
              _SoundCard(controller: d),
              SectionLabel(context.t('display.section.show')),
              _ShowCard(controller: d),
              SectionLabel(context.t('display.section.update')),
              _UpdateCard(controller: d),
              SectionLabel(context.t('display.advanced')),
              _AdvancedCard(controller: d),
            ],
            const SizedBox(height: Space.lg),
            Notice(text: context.t('display.security'), icon: Icons.info_outline),
            const SizedBox(height: Space.md),
          ],
        );
      },
    );
  }
}

/// The big status picture at the top: what is connected, or what is missing.
class _Hero extends StatelessWidget {
  const _Hero({required this.controller, required this.chosen});
  final DisplayController controller;
  final bool chosen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = controller;
    final s = context.app.settings.value;
    final name = s.displayName ?? 'TN-Display';
    final summary = d.summary;
    final (icon, tint) = switch (summary) {
      'ready' => (Icons.bluetooth_connected, c.success),
      'incompatible' => (Icons.warning_amber_rounded, c.warn),
      'connecting' => (Icons.bluetooth_searching, c.tint),
      _ => (Icons.bluetooth, c.textSecondary),
    };
    final text = !chosen
        ? context.t('display.status.off')
        : !s.displayEnabled
            ? context.t('display.status.disabled', {'name': name})
            : switch (d.state) {
                DisplayLinkState.ready => context.t('display.status.ready', {'name': name}),
                DisplayLinkState.incompatible => context.t('display.status.incompatible', {'name': name}),
                _ => context.t('display.status.connecting', {'name': name}),
              };
    return Column(children: [
      const SizedBox(height: Space.md),
      AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 84,
        height: 84,
        decoration: BoxDecoration(color: tint.withValues(alpha: 0.14), shape: BoxShape.circle),
        child: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: Icon(icon, key: ValueKey(icon), size: 42, color: tint)),
      ),
      const SizedBox(height: Space.md),
      Semantics(liveRegion: true, child: Text(text, textAlign: TextAlign.center, style: TnText.body.copyWith(color: c.text, fontWeight: FontWeight.w600, fontSize: 18))),
      const SizedBox(height: Space.md),
      if (!d.supported) Notice(text: context.t('display.unsupported'), icon: Icons.bluetooth_disabled),
      if (d.problem != null) Notice(text: context.t('display.problem.off'), icon: Icons.bluetooth_disabled, color: c.warn),
      if (d.connected && !context.app.drive.isActive) Padding(padding: const EdgeInsets.only(bottom: Space.sm), child: Hint(context.t('display.idleHint'))),
      if (chosen && s.displayEnabled && !d.connected && d.failedAttempts >= 2) Notice(text: context.t('display.connectFailing'), icon: Icons.bluetooth_disabled, color: c.warn),
      if (d.compat == DisplayCompat.appTooOld) Notice(text: context.t('display.compat.appTooOld'), icon: Icons.system_update, color: c.warn),
      if (d.compat == DisplayCompat.displayTooOld) Notice(text: context.t('display.compat.displayTooOld'), icon: Icons.system_update, color: c.warn),
      const SizedBox(height: Space.sm),
    ]);
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.controller});
  final DisplayController controller;

  @override
  Widget build(BuildContext context) {
    final d = controller;
    final info = d.info!;
    return CardSection(title: context.t('display.device'), children: [
      Body(context.t('display.fw', {'version': info.fwVersion})),
      Hint(context.t('display.proto', {'version': info.protoVersion})),
      Hint(context.t('display.size', {'w': info.width, 'h': info.height})),
      Hint(context.t('display.caps', {
        'list': [
          if (d.caps.audio) context.t('display.cap.audio'),
          if (d.caps.sd) context.t('display.cap.sd'),
          if (d.caps.ota) context.t('display.cap.ota'),
          if (d.caps.speedcamBuild) context.t('display.cap.camera'),
          if (d.caps.rtc) context.t('display.cap.rtc'),
        ].join(', '),
      })),
      Hint(context.t('display.link', {'mtu': d.mtu, 'count': d.sentCount})),
    ]);
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.controller, required this.chosen});
  final DisplayController controller;
  final bool chosen;

  @override
  Widget build(BuildContext context) {
    final d = controller;
    return CardSection(children: [
      PrimaryButton(
        icon: d.scanning ? null : Icons.bluetooth_searching,
        label: d.scanning ? context.t('display.scanning') : context.t('display.scan'),
        onPressed: d.supported && !d.scanning ? d.scan : null,
      ),
      if (d.scanning) const LinearProgressIndicator(minHeight: 3),
      if (!d.scanning && d.found.isEmpty && d.supported) Hint(context.t('display.noneFound')),
      for (final f in d.found)
        Semantics(
          container: true,
          label: f.name,
          child: Row(children: [
            const Icon(Icons.memory, size: 22),
            const SizedBox(width: Space.sm),
            Expanded(child: Body(f.name)),
            SoftButton(label: context.t('display.connect'), expand: false, onPressed: () => d.choose(f)),
          ]),
        ),
      if (chosen) SoftButton(icon: Icons.link_off, label: context.t('display.forget'), danger: true, onPressed: d.forget),
      if (chosen) Hint(context.t('display.forgetHint')),
    ]);
  }
}

class _SoundCard extends StatelessWidget {
  const _SoundCard({required this.controller});
  final DisplayController controller;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.settings.value;
    final d = controller;
    return CardSection(children: [
      Segments<DisplaySoundTarget>(
        value: s.displaySound,
        options: {
          DisplaySoundTarget.auto: context.t('display.sound.auto'),
          DisplaySoundTarget.display: context.t('display.sound.display'),
          DisplaySoundTarget.phone: context.t('display.sound.phone'),
          DisplaySoundTarget.both: context.t('display.sound.both'),
        },
        onChanged: (v) {
          HapticFeedback.selectionClick();
          app.settings.update((x) => x.copyWith(displaySound: v));
        },
      ),
      Hint(context.t('display.sound.hint')),
      Semantics(
        label: context.t('display.volume', {'value': s.displayVolume}),
        child: Slider(
          value: s.displayVolume.toDouble(),
          min: 0,
          max: 100,
          divisions: 20,
          label: '${s.displayVolume} %',
          onChanged: (v) => app.settings.update((x) => x.copyWith(displayVolume: v.round())),
        ),
      ),
      Hint(context.t('display.volume', {'value': s.displayVolume})),
      SwitchRow(
        title: context.t('display.voice'),
        hint: context.t('display.voiceHint'),
        value: s.displayVoice,
        enabled: d.connected ? d.caps.sd : true,
        onChanged: (on) => app.settings.update((x) => x.copyWith(displayVoice: on)),
      ),
      SoftButton(icon: Icons.volume_up, label: context.t('display.testSound'), onPressed: d.connected && d.caps.audio ? d.testSound : null),
      if (!d.connected) Hint(context.t('display.connectedOnly')),
    ]);
  }
}

class _ShowCard extends StatelessWidget {
  const _ShowCard({required this.controller});
  final DisplayController controller;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.settings.value;
    final d = controller;
    return CardSection(children: [
      Body(context.t('display.night')),
      _Stepper(
        label: context.t('display.nightFrom', {'hour': s.displayNightStart}),
        onMinus: () => app.settings.update((x) => x.copyWith(displayNightStart: (x.displayNightStart + 23) % 24)),
        onPlus: () => app.settings.update((x) => x.copyWith(displayNightStart: (x.displayNightStart + 1) % 24)),
      ),
      _Stepper(
        label: context.t('display.nightTo', {'hour': s.displayNightEnd}),
        onMinus: () => app.settings.update((x) => x.copyWith(displayNightEnd: (x.displayNightEnd + 23) % 24)),
        onPlus: () => app.settings.update((x) => x.copyWith(displayNightEnd: (x.displayNightEnd + 1) % 24)),
      ),
      Hint(context.t('display.nightHint')),
      const Divider(height: Space.xl),
      Body(context.t('display.cache')),
      Segments<int>(
        value: s.displayCacheMinutes,
        options: {for (final m in const [5, 10, 30, 60]) m: context.t('display.cacheValue', {'minutes': m})},
        onChanged: (v) {
          HapticFeedback.selectionClick();
          app.settings.update((x) => x.copyWith(displayCacheMinutes: v));
        },
      ),
      Hint(context.t('display.cacheHint')),
      SoftButton(icon: Icons.schedule, label: context.t('display.time'), onPressed: d.connected ? d.syncTime : null),
    ]);
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.label, required this.onMinus, required this.onPlus});
  final String label;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Body(label)),
        IconButton(onPressed: onMinus, icon: const Icon(Icons.remove_circle_outline), tooltip: '−'),
        IconButton(onPressed: onPlus, icon: const Icon(Icons.add_circle_outline), tooltip: '+'),
      ]);
}

/// The firmware: what is installed, what is known, check, install (after a confirmation), progress, result.
class _UpdateCard extends StatelessWidget {
  const _UpdateCard({required this.controller});
  final DisplayController controller;

  Future<void> _install(BuildContext context) async {
    final d = controller;
    final m = d.manifest;
    if (m == null) return;
    final ok = await confirmDialog(
      context,
      title: context.t('display.update.confirmTitle'),
      message: '${context.t('display.update.confirmBody', {'version': m.version})}\n\n${context.t('display.update.unsigned')}',
      confirmLabel: context.t('display.update.confirm'),
    );
    if (ok) {
      HapticFeedback.mediumImpact();
      await d.installUpdate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final c = context.colors;
    final s = app.settings.value;
    final d = controller;
    final m = d.manifest;
    final phase = d.updatePhase;
    final busy = phase == DisplayUpdatePhase.downloading || phase == DisplayUpdatePhase.installing || phase == DisplayUpdatePhase.verifying;
    final lang = app.texts.language;
    final changes = m == null ? const <String>[] : (lang == 'de' ? m.changesDe : m.changesEn);
    final blocker = d.updateBlocker;

    Widget status() => switch (phase) {
          DisplayUpdatePhase.idle => const SizedBox.shrink(),
          DisplayUpdatePhase.checking => Row(children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: Space.sm),
              Body(context.t('display.update.checking')),
            ]),
          DisplayUpdatePhase.upToDate => _Line(Icons.check_circle, c.success, context.t('display.update.upToDate')),
          DisplayUpdatePhase.available => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Line(Icons.system_update, c.tint, context.t('display.update.available', {'version': m?.version ?? ''})),
              if (changes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: Space.xs), child: Hint(context.t('display.update.changes', {'list': changes.join(' · ')}))),
            ]),
          DisplayUpdatePhase.downloading => _Line(Icons.download, c.tint, context.t('display.update.downloading')),
          DisplayUpdatePhase.installing => _Line(Icons.bluetooth_connected, c.tint, context.t('display.update.installing')),
          DisplayUpdatePhase.verifying => _Line(Icons.restart_alt, c.tint, context.t('display.update.verifying')),
          DisplayUpdatePhase.success => _Line(Icons.check_circle, c.success, context.t('display.update.success', {'version': m?.version ?? ''})),
          DisplayUpdatePhase.failed => _Line(
              Icons.error_outline,
              c.danger,
              d.updateErrorCode != null ? context.t('display.update.failedCode', {'code': d.updateErrorCode!}) : context.t('display.update.failed'),
            ),
          DisplayUpdatePhase.sourceUnavailable => _Line(Icons.cloud_off, c.warn, context.t('display.update.sourceUnavailable')),
          DisplayUpdatePhase.offline => _Line(Icons.wifi_off, c.warn, context.t('display.update.offline')),
          DisplayUpdatePhase.badRelease => _Line(Icons.error_outline, c.danger, context.t('display.update.badRelease')),
          DisplayUpdatePhase.needsIntermediate => _Line(Icons.info_outline, c.warn, context.t('display.update.needsIntermediate')),
          DisplayUpdatePhase.appTooOld => _Line(Icons.info_outline, c.warn, context.t('display.update.appTooOld')),
          DisplayUpdatePhase.notPossible => _Line(Icons.info_outline, c.warn, context.t('display.update.notPossible')),
        };

    return CardSection(children: [
      if (d.info != null) Body(context.t('display.update.installed', {'version': d.info!.fwVersion})),
      AnimatedSize(duration: const Duration(milliseconds: 250), alignment: Alignment.topCenter, child: Semantics(liveRegion: true, child: status())),
      if (busy) LinearProgressIndicator(value: phase == DisplayUpdatePhase.verifying ? null : d.updateProgress, minHeight: 6, borderRadius: BorderRadius.circular(3)),
      if (phase == DisplayUpdatePhase.available) ...[
        PrimaryButton(icon: Icons.system_update, label: context.t('display.update.install'), onPressed: blocker == null ? () => _install(context) : null),
        if (blocker != null) Hint(context.t('display.update.blocker.$blocker')),
      ] else if (phase == DisplayUpdatePhase.downloading || phase == DisplayUpdatePhase.installing)
        SoftButton(label: context.t('display.update.cancel'), onPressed: d.cancelUpdate)
      else if (!busy)
        SoftButton(
          icon: Icons.refresh,
          label: phase == DisplayUpdatePhase.checking ? context.t('display.update.checking') : context.t('display.update.check'),
          onPressed: d.canUpdate && phase != DisplayUpdatePhase.checking ? () => d.checkForUpdate() : null,
        ),
      if (s.displayLastUpdateCheck != null) Hint(context.t('display.update.last', {'time': formatDateTime(context, s.displayLastUpdateCheck!)})),
      SwitchRow(
        title: context.t('display.update.auto'),
        hint: context.t('display.update.autoHint'),
        value: s.displayAutoUpdateCheck,
        onChanged: (on) => app.settings.update((x) => x.copyWith(displayAutoUpdateCheck: on)),
      ),
    ]);
  }
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.color, this.text);
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: Space.sm),
        Expanded(child: Body(text)),
      ]);
}


/// The developer switches of the display (UiConfig, ten persistent bits), hidden until asked for. Only while connected.
class _AdvancedCard extends StatefulWidget {
  const _AdvancedCard({required this.controller});
  final DisplayController controller;

  @override
  State<_AdvancedCard> createState() => _AdvancedCardState();
}

class _AdvancedCardState extends State<_AdvancedCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.controller;
    final config = d.uiConfig;
    return CardSection(children: [
      SoftButton(
        icon: _open ? Icons.expand_less : Icons.tune,
        label: _open ? context.t('display.advancedHide') : context.t('display.advancedShow'),
        onPressed: () => setState(() => _open = !_open),
      ),
      if (_open) ...[
        Hint(context.t('display.advancedHint')),
        if (!d.connected || config == null)
          Hint(context.t('display.connectedOnly'))
        else
          for (var bit = 0; bit < 10; bit++)
            SwitchRow(
              title: context.t('display.ui.$bit'),
              value: config.isOn(bit),
              onChanged: (on) => d.setUiBit(bit, on),
            ),
        Hint(context.t('display.resetHint')),
      ],
    ]);
  }
}
