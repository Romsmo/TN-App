import { getLanguage } from '@/i18n';

import type { Feedback } from './feedback';

type Tone = 'first' | 'second' | 'confirm' | 'prompt';

const SOURCES: Record<Tone, string> = {
  first: 'warn-first.wav',
  second: 'warn-second.wav',
  confirm: 'confirm.wav',
  prompt: 'prompt.wav',
};

/** Folder of the tones next to the app (copied by `scripts/web-postbuild.mjs`). */
function soundsBase(): string {
  const base = (globalThis as { __tnBase?: string }).__tnBase ?? new URL('./', globalThis.location?.href ?? 'http://localhost/').href;
  return `${base.replace(/\/?$/, '/')}sounds/`;
}

/**
 * Tones, speech and vibration of the drive mode in the browser. Browsers play audio and speak only after the user did
 * something on the page; the first tap anywhere (the "start drive" button is one) unlocks both. Vibration exists on
 * Android only (docs/web-limits.md); everywhere else the screen and the tones carry the warning.
 */
export function createNativeFeedback(): Feedback {
  const players = new Map<Tone, HTMLAudioElement>();
  let unlocked = false;

  const unlock = () => {
    if (unlocked) return;
    unlocked = true;
    try {
      // a silent utterance and a silent tone make the browser treat later ones as user-initiated
      window.speechSynthesis?.speak(new SpeechSynthesisUtterance(''));
      const tone = new Audio(`${soundsBase()}${SOURCES.confirm}`);
      tone.volume = 0;
      void tone.play().catch(() => undefined);
    } catch {
      // nothing to unlock
    }
  };
  if (typeof document !== 'undefined') document.addEventListener('pointerdown', unlock, { once: true, capture: true });

  const play = (tone: Tone) => {
    try {
      let player = players.get(tone);
      if (!player) {
        player = new Audio(`${soundsBase()}${SOURCES[tone]}`);
        players.set(tone, player);
      }
      player.currentTime = 0;
      void player.play().catch(() => undefined);
    } catch {
      // a missing tone must never break a warning
    }
  };
  const vibrate = (pattern: number | number[]) => {
    try {
      navigator.vibrate?.(pattern);
    } catch {
      // not supported here
    }
  };

  return {
    warn({ level, text }, allow) {
      vibrate(level === 'second' ? [200, 100, 200] : 80);
      if (allow.sound) play(level);
      if (allow.voice) {
        try {
          const utterance = new SpeechSynthesisUtterance(text);
          utterance.lang = getLanguage() === 'de' ? 'de-DE' : 'en-US';
          window.speechSynthesis?.speak(utterance);
        } catch {
          // no voice on this device
        }
      }
    },
    confirm(allow) {
      vibrate(40);
      if (allow.sound) play('confirm');
    },
    prompt(allow) {
      vibrate(40);
      if (allow.sound) play('prompt');
    },
    silence() {
      try {
        window.speechSynthesis?.cancel();
      } catch {
        // see warn
      }
    },
  };
}
