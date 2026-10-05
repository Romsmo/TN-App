import { createAudioPlayer, setAudioModeAsync, type AudioPlayer } from 'expo-audio';
import * as Haptics from 'expo-haptics';
import * as Speech from 'expo-speech';

import { getLanguage } from '@/i18n';

import type { Feedback } from './feedback';

type Tone = 'first' | 'second' | 'confirm' | 'prompt';

const SOURCES: Record<Tone, number> = {
  first: require('../../assets/sounds/warn-first.wav') as number,
  second: require('../../assets/sounds/warn-second.wav') as number,
  confirm: require('../../assets/sounds/confirm.wav') as number,
  prompt: require('../../assets/sounds/prompt.wav') as number,
};

/** Tones, speech and haptics of the drive mode. Own short tones (generated for this app), the system voice. */
export function createNativeFeedback(): Feedback {
  const players = new Map<Tone, AudioPlayer>();
  let modeSet = false;

  const play = (tone: Tone) => {
    try {
      if (!modeSet) {
        modeSet = true;
        // Warnings play over music (ducking it), also with the silent switch on and while the app is in the background.
        void setAudioModeAsync({ playsInSilentMode: true, interruptionMode: 'duckOthers', shouldPlayInBackground: true, allowsRecording: false });
      }
      let player = players.get(tone);
      if (!player) {
        player = createAudioPlayer(SOURCES[tone]);
        players.set(tone, player);
      }
      void player.seekTo(0);
      player.play();
    } catch {
      // a missing tone must never break a warning
    }
  };
  const haptic = (kind: 'warn' | 'light' | 'ok') => {
    const run =
      kind === 'warn'
        ? Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning)
        : kind === 'ok'
          ? Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success)
          : Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    run.catch(() => undefined);
  };

  return {
    warn({ level, text }, allow) {
      haptic(level === 'second' ? 'warn' : 'light');
      if (allow.sound) play(level);
      if (allow.voice) Speech.speak(text, { language: getLanguage() === 'de' ? 'de-DE' : 'en-US', rate: 1.0 });
    },
    confirm(allow) {
      haptic('ok');
      if (allow.sound) play('confirm');
    },
    prompt(allow) {
      haptic('light');
      if (allow.sound) play('prompt');
    },
    silence() {
      void Speech.stop();
    },
  };
}
