import type { SpeedUnit } from '@/tn/types';

const KMH_PER_MPH = 1.609344;

export function toKmh(value: number, unit: SpeedUnit): number {
  return unit === 'kmh' ? value : value * KMH_PER_MPH;
}

export function fromKmh(kmh: number, unit: SpeedUnit): number {
  return unit === 'kmh' ? kmh : kmh / KMH_PER_MPH;
}

/** Speed in the user's unit as a whole number. */
export function displaySpeed(kmh: number | null, unit: SpeedUnit): number | null {
  return kmh === null ? null : Math.round(fromKmh(Math.max(0, kmh), unit));
}

/** A limit as the library stores it (never converted there), shown in the user's unit; mph limits are 5-steps. */
export function displayLimit(value: number, from: SpeedUnit, to: SpeedUnit): number {
  if (from === to) return Math.round(value);
  const converted = fromKmh(toKmh(value, from), to);
  return Math.round(converted / 5) * 5;
}

export type SpeedState = 'ok' | 'over';

/** Over the limit by more than `toleranceKmh` (default 3 km/h of GPS and speedometer slack). */
export function speedState(speedKmh: number | null, limit: { value: number; unit: SpeedUnit } | null, toleranceKmh = 3): SpeedState {
  if (speedKmh === null || !limit) return 'ok';
  return speedKmh > toKmh(limit.value, limit.unit) + toleranceKmh ? 'over' : 'ok';
}

export function unitLabel(unit: SpeedUnit): string {
  return unit === 'kmh' ? 'km/h' : 'mph';
}
