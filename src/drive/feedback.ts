/** How the drive mode talks to the driver besides the screen. Native implementation: `feedback-native.ts`; tests use a fake. */
export type WarnFeedback = {
  level: 'first' | 'second';
  /** The sentence to speak. */
  text: string;
};

export interface Feedback {
  /** A warning: a tone and the sentence, each only when allowed. */
  warn(warning: WarnFeedback, allow: { sound: boolean; voice: boolean }): void;
  /** Short confirmation after a one-tap report: haptic and a soft tone. */
  confirm(allow: { sound: boolean }): void;
  /** The "still there?" card appeared. */
  prompt(allow: { sound: boolean }): void;
  /** Silence everything that is being spoken right now (mute). */
  silence(): void;
}
