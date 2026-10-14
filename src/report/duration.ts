import { t } from '@/i18n';
import type { ReportLimits } from '@/tn/types';

/** What the reporter picked in the report sheet: the server's default for the type, or a duration of their own. */
export type DurationChoice = { kind: 'default' } | { kind: 'custom'; seconds: number };

export const DEFAULT_CHOICE: DurationChoice = { kind: 'default' };

/** Quick choices in the sheet. They are only offers; what is allowed is decided per type by `getReportLimits` when a type is picked. */
export const QUICK_SECONDS = [15 * 60, 60 * 60, 3 * 3600, 24 * 3600] as const;

export type DurationUnit = 'min' | 'h' | 'd';

const UNIT_SECONDS: Record<DurationUnit, number> = { min: 60, h: 3600, d: 86400 };

/** "1,5" + "h" -> 5400. Null for anything that is not a positive, finite number. */
export function parseDuration(amount: string, unit: DurationUnit): number | null {
  const value = Number(amount.trim().replace(',', '.'));
  if (!Number.isFinite(value) || value <= 0) return null;
  const seconds = Math.round(value * UNIT_SECONDS[unit]);
  return seconds > 0 ? seconds : null;
}

export type DurationCheck = { ok: true } | { ok: false; reason: 'unsupported' | 'tooShort' | 'tooLong'; minSeconds: number | null; maxSeconds: number | null };

/** Is `seconds` inside the bounds the server announced for this type? Unknown bounds (before the first sync) mean: do not guess. */
export function checkDuration(seconds: number, limits: ReportLimits): DurationCheck {
  const { minSeconds, maxSeconds } = limits;
  if (!limits.supported || minSeconds === null || maxSeconds === null) return { ok: false, reason: 'unsupported', minSeconds, maxSeconds };
  if (seconds < minSeconds) return { ok: false, reason: 'tooShort', minSeconds, maxSeconds };
  if (seconds > maxSeconds) return { ok: false, reason: 'tooLong', minSeconds, maxSeconds };
  return { ok: true };
}

/** "3 h", "1 d 2 h", "45 min" – the two largest non-zero units, rounded to minutes. */
export function formatDuration(totalSeconds: number): string {
  const minutes = Math.max(1, Math.round(totalSeconds / 60));
  const days = Math.floor(minutes / 1440);
  const hours = Math.floor((minutes % 1440) / 60);
  const mins = minutes % 60;
  const parts: string[] = [];
  if (days > 0) parts.push(t('duration.d', { n: days }));
  if (hours > 0) parts.push(t('duration.h', { n: hours }));
  if (mins > 0 && days === 0) parts.push(t('duration.min', { n: mins }));
  return parts.slice(0, 2).join(' ');
}

/** Time left until `expiresAt`, from the server's own expiry; null when unknown or already past. */
export function remainingSeconds(expiresAt: string | null, now: number): number | null {
  if (!expiresAt) return null;
  const end = new Date(expiresAt).getTime();
  if (Number.isNaN(end)) return null;
  const left = Math.floor((end - now) / 1000);
  return left > 0 ? left : null;
}
