import { t, type TextKey } from '@/i18n';
import { de } from '@/i18n/de';

/** The display name of a hazard type. Unknown types (a newer server) show their raw id instead of failing. */
export function hazardLabel(type: string): string {
  const key = `hazard.${type}`;
  return key in de ? t(key as TextKey) : type;
}
