import type { Language } from '@/i18n';

/** A piece of a notice; `strong` pieces are shown bold. */
export type Segment = { text: string; strong?: boolean };

/**
 * The speed-camera notice. The German wording is fixed by the client and must not be edited; the English text is its
 * translation (to be approved). Shown once when the user switches speed cameras on, in the info area for good, and
 * at the first start of the drive mode.
 */
export const CAMERA_NOTICE: Record<Language, readonly Segment[]> = {
  de: [
    { text: 'Hinweis: Das Nutzen von Blitzer-Warnungen ' },
    { text: 'während der Fahrt', strong: true },
    {
      text: ' ist in Deutschland verboten — auch, wenn ein Beifahrer sie bedient. In der Schweiz sind solche Hinweise generell unzulässig, in Frankreich nur als allgemeine Gefahrenzonen. Bitte informiere dich über die Regeln in deinem Land.',
    },
  ],
  en: [
    { text: 'Notice: Using speed-camera warnings ' },
    { text: 'while driving', strong: true },
    {
      text: ' is prohibited in Germany — even if a passenger operates them. In Switzerland such notices are generally not permitted, in France only as general danger zones. Please find out about the rules in your country.',
    },
  ],
};

/** Added to the camera notice at the first start of the drive mode. */
export const DRIVE_NOTICE_EXTRA: Record<Language, string> = {
  de: 'Bediene die App nur als Beifahrer oder im Stand.',
  en: 'Operate the app only as a passenger or when stationary.',
};

/** Warning shown, and to be confirmed, every time the speed lock is switched off. German wording fixed by the client. */
export const LOCK_WARNING: Record<Language, string> = {
  de: 'Warnung: Die Bedienung eines Smartphones während der Fahrt lenkt ab und ist in vielen Ländern verboten, in Deutschland unter anderem als Handynutzung am Steuer. Wenn du die Fahrsperre abschaltest, bist du allein dafür verantwortlich. Bediene die App nur im Stand oder als Beifahrer.',
  en: 'Warning: Operating a smartphone while driving is distracting and prohibited in many countries, in Germany among other things as using a mobile phone at the wheel. If you switch off the driving lock, you are solely responsible. Operate the app only when stationary or as a passenger.',
};

export function plain(segments: readonly Segment[]): string {
  return segments.map((s) => s.text).join('');
}

/** Bumped when the wording of the camera notice changes: users then see it once more. */
export const CAMERA_NOTICE_VERSION = 'app-1';
