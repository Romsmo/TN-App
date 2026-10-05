import { getLocales } from 'expo-localization';

import { de, type TextKey } from './de';
import { en } from './en';

export type { TextKey };
export type Language = 'de' | 'en';

const tables: Record<Language, Record<TextKey, string>> = { de, en };

/** German for German-language devices, English for everything else. */
export function pickLanguage(languageCode: string | null | undefined): Language {
  return languageCode === 'de' ? 'de' : 'en';
}

let current: Language = pickLanguage(getLocales()[0]?.languageCode);

export function getLanguage(): Language {
  return current;
}

/** For tests and a future language setting. */
export function setLanguage(language: Language): void {
  current = language;
}

/** The text for `key` in the current language; `{name}` placeholders are filled from `vars`. */
export function t(key: TextKey, vars: Record<string, string | number> = {}): string {
  const text = tables[current][key];
  return text.replace(/\{(\w+)\}/g, (whole, name: string) => {
    const value = vars[name];
    return value === undefined ? whole : String(value);
  });
}
