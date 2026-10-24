import 'package:flutter/material.dart';
import 'package:tn_core/tn_core.dart';

import '../app_scope.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'common.dart';

/// "Display": choose the TN display, see its state, set where announcements play. Reached from the settings (and so locked while
/// driving, like every settings page).
class DisplayScreen extends StatelessWidget {
  const DisplayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final c = context.colors;
    return ListenableBuilder(
      listenable: Listenable.merge([app.settings, app.display]),
      builder: (context, _) {
        final s = app.settings.value;
        final d = app.display;
        final name = s.displayName ?? 'TN-Display';
        final chosen = s.displayDeviceId != null;
        final status = !chosen
            ? context.t('display.status.off')
            : !s.displayEnabled
                ? context.t('display.status.disabled', {'name': name})
                : switch (d.state) {
                    DisplayLinkState.ready => context.t('display.status.ready', {'name': name}),
                    DisplayLinkState.incompatible => context.t('display.status.incompatible', {'name': name}),
                    _ => context.t('display.status.connecting', {'name': name}),
                  };
        final info = d.info;
        return SubPage(
          title: context.t('display.title'),
          children: [
            if (!d.supported) Notice(text: context.t('display.unsupported'), icon: Icons.bluetooth_disabled),
            CardSection(children: [
              Semantics(liveRegion: true, child: Body(status)),
              if (d.problem != null) Notice(text: context.t('display.problem.off'), icon: Icons.bluetooth_disabled, color: c.warn),
              if (chosen)
                SwitchRow(
                  title: context.t('display.use'),
                  hint: context.t('display.useHint'),
                  value: s.displayEnabled,
                  onChanged: d.setEnabled,
                ),
              if (d.compat == DisplayCompat.appTooOld) Notice(text: context.t('display.compat.appTooOld'), icon: Icons.system_update, color: c.warn),
              if (d.compat == DisplayCompat.displayTooOld) Notice(text: context.t('display.compat.displayTooOld'), icon: Icons.system_update, color: c.warn),
            ]),
            CardSection(title: context.t('display.scan'), children: [
              PrimaryButton(
                icon: Icons.bluetooth_searching,
                label: d.scanning ? context.t('display.scanning') : context.t('display.scan'),
                onPressed: d.supported && !d.scanning ? d.scan : null,
              ),
              if (!d.scanning && d.found.isEmpty && d.supported) Hint(context.t('display.noneFound')),
              for (final f in d.found)
                Semantics(
                  container: true,
                  label: f.name,
                  child: Row(children: [
                    Expanded(child: Body(f.name)),
                    SoftButton(label: context.t('display.connect'), expand: false, onPressed: () => d.choose(f)),
                  ]),
                ),
              if (chosen) SoftButton(icon: Icons.link_off, label: context.t('display.forget'), danger: true, onPressed: d.forget),
              if (chosen) Hint(context.t('display.forgetHint')),
            ]),
            if (info != null)
              CardSection(title: context.t('display.device'), children: [
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
              ]),
            CardSection(title: context.t('display.sound'), children: [
              Segments<DisplaySoundTarget>(
                value: s.displaySound,
                options: {
                  DisplaySoundTarget.auto: context.t('display.sound.auto'),
                  DisplaySoundTarget.display: context.t('display.sound.display'),
                  DisplaySoundTarget.phone: context.t('display.sound.phone'),
                  DisplaySoundTarget.both: context.t('display.sound.both'),
                },
                onChanged: (v) => app.settings.update((x) => x.copyWith(displaySound: v)),
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
            ]),
            CardSection(title: context.t('display.updates'), children: [Hint(context.t('display.updatesHint'))]),
            Notice(text: context.t('display.security'), icon: Icons.info_outline),
            const SizedBox(height: Space.md),
          ],
        );
      },
    );
  }
}
