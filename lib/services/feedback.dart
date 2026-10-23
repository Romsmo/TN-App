import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:tn_core/tn_core.dart' hide Feedback;
import 'package:tn_core/tn_core.dart' as core show Feedback;

enum _Tone { first, second, confirm, prompt }

const _toneAssets = {
  _Tone.first: 'sounds/warn-first.wav',
  _Tone.second: 'sounds/warn-second.wav',
  _Tone.confirm: 'sounds/confirm.wav',
  _Tone.prompt: 'sounds/prompt.wav',
};

/// Tones, speech and haptics of the drive mode: our own short tones (generated for this app), the system voice.
/// Warnings play over music (ducking it), also with the silent switch on and while the app is in the background.
class DeviceFeedback implements core.Feedback {
  DeviceFeedback({required this.language});

  /// `de` or `en`; read at every warning, so a language change takes effect at once.
  final String Function() language;

  final Map<_Tone, AudioPlayer> _players = {};
  FlutterTts? _tts;
  bool _audioConfigured = false;

  Future<void> _configureAudio() async {
    if (_audioConfigured) return;
    _audioConfigured = true;
    try {
      await AudioPlayer.global.setAudioContext(AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {AVAudioSessionOptions.duckOthers},
        ),
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceNavigationGuidance,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
      ));
    } catch (_) {}
  }

  Future<void> _play(_Tone tone) async {
    try {
      await _configureAudio();
      final player = _players.putIfAbsent(tone, () => AudioPlayer()..setReleaseMode(ReleaseMode.stop));
      await player.stop();
      await player.play(AssetSource(_toneAssets[tone]!));
    } catch (_) {
      // a missing tone must never break a warning
    }
  }

  void _haptic(String kind) {
    try {
      switch (kind) {
        case 'warn':
          HapticFeedback.heavyImpact();
        case 'ok':
          HapticFeedback.mediumImpact();
        default:
          HapticFeedback.lightImpact();
      }
    } catch (_) {}
  }

  Future<void> _speak(String text) async {
    try {
      var tts = _tts;
      if (tts == null) {
        tts = _tts = FlutterTts();
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          // speech ducks music and keeps going with the screen off
          await tts.setSharedInstance(true);
          await tts.setIosAudioCategory(
            IosTextToSpeechAudioCategory.playback,
            [IosTextToSpeechAudioCategoryOptions.duckOthers],
            IosTextToSpeechAudioMode.voicePrompt,
          );
        }
      }
      await tts.setLanguage(language() == 'de' ? 'de-DE' : 'en-US');
      await tts.setSpeechRate(0.5);
      await tts.speak(text);
    } catch (_) {}
  }

  @override
  void warn(WarnLevel level, String text, {required bool sound, required bool voice}) {
    _haptic(level == WarnLevel.second ? 'warn' : 'light');
    if (sound) _play(level == WarnLevel.second ? _Tone.second : _Tone.first);
    if (voice) _speak(text);
  }

  @override
  void confirm({required bool sound}) {
    _haptic('ok');
    if (sound) _play(_Tone.confirm);
  }

  @override
  void prompt({required bool sound}) {
    _haptic('light');
    if (sound) _play(_Tone.prompt);
  }

  @override
  void silence() {
    try {
      _tts?.stop();
    } catch (_) {}
  }

  void dispose() {
    for (final p in _players.values) {
      p.dispose();
    }
    _players.clear();
    if (kDebugMode) debugPrint('feedback disposed');
  }
}
