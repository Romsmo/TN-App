import { LOCK_ON_KMH } from '@/drive/lock';
import { TnError, type TnService } from '@/tn/service';
import type { CorrectionReasonCode, SpeedLimitLookup, SpeedUnit } from '@/tn/types';

export type Spot = { lat: number; lng: number };

/** The values offered as one tap; anything else is typed. Only a convenience, the library decides what it accepts. */
export const QUICK_LIMITS: Record<SpeedUnit, readonly number[]> = {
  kmh: [30, 50, 70, 100, 120],
  mph: [20, 30, 40, 55, 70],
};

/** The reasons a person can give for "that limit is wrong". */
export type WrongReason = Exclude<CorrectionReasonCode, 'missing'>;
export const WRONG_REASONS: readonly WrongReason[] = ['wrongValue', 'limitLifted', 'signMissingOrNew', 'other'];

const MAX_VALUE: Record<SpeedUnit, number> = { kmh: 200, mph: 125 };

/** A whole number from 5 up to a plausible maximum; null for everything else (the library still has the last word). */
export function parseLimitValue(text: string, unit: SpeedUnit): number | null {
  const trimmed = text.trim();
  if (!/^\d{1,3}$/.test(trimmed)) return null;
  const value = Number(trimmed);
  return value >= 5 && value <= MAX_VALUE[unit] ? value : null;
}

/**
 * Proposing a limit is a text input and happens while looking at a screen, so it follows the speed lock: not while the
 * drive session's lock is in force, and — with the lock switched on — not while the device itself moves at driving speed
 * (map open without a drive started).
 */
export function entryLocked(input: { lockActive: boolean; lockEnabled: boolean; deviceSpeedKmh: number | null }): boolean {
  if (input.lockActive) return true;
  return input.lockEnabled && input.deviceSpeedKmh !== null && input.deviceSpeedKmh >= LOCK_ON_KMH;
}

/** What the card shows for a tapped spot; `error` is a failed lookup (e.g. no connection while outside the offline area). */
export type LookupState = { phase: 'loading' } | { phase: 'done'; result: SpeedLimitLookup } | { phase: 'error' };

export async function lookupSpot(service: TnService, spot: Spot): Promise<LookupState> {
  try {
    return { phase: 'done', result: await service.lookupSpeedLimit(spot.lat, spot.lng) };
  } catch {
    return { phase: 'error' };
  }
}

export type ProposalOutcome = { ok: true } | { ok: false; reason: 'roadAlreadyHasLimit' | 'invalidValue' | 'storageFull' | 'network' | 'failed' };

function failure(error: unknown): ProposalOutcome {
  if (error instanceof TnError) {
    if (error.code === 'roadAlreadyHasLimit') return { ok: false, reason: 'roadAlreadyHasLimit' };
    if (error.code === 'invalidArgument') return { ok: false, reason: 'invalidValue' };
    if (error.code === 'storageFull') return { ok: false, reason: 'storageFull' };
    if (error.code === 'network' || error.code === 'unavailable') return { ok: false, reason: 'network' };
  }
  return { ok: false, reason: 'failed' };
}

/** "No limit on record": proposes a value. Stored on the device first and sent with the next sync, like every write. */
export async function proposeMissing(service: TnService, spot: Spot, value: number, unit: SpeedUnit): Promise<ProposalOutcome> {
  try {
    await service.reportMissingSpeedLimit({ lat: spot.lat, lng: spot.lng, value, unit, reason: 'missing' });
    return { ok: true };
  } catch (error) {
    return failure(error);
  }
}

/** "That limit is wrong": proposes another value for a road that has one. */
export async function proposeCorrection(service: TnService, spot: Spot, value: number, unit: SpeedUnit, reason: CorrectionReasonCode): Promise<ProposalOutcome> {
  try {
    await service.reportWrongSpeedLimit({ lat: spot.lat, lng: spot.lng, proposedValue: value, unit, reason });
    return { ok: true };
  } catch (error) {
    return failure(error);
  }
}
