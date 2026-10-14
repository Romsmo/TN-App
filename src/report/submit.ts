import { TnError, type TnService } from '@/tn/service';

import { checkDuration, DEFAULT_CHOICE, type DurationChoice } from './duration';

export type Position = { lat: number; lng: number };

export type SubmitFailure =
  | { ok: false; reason: 'invalidPosition' | 'invalidType' | 'storageFull' | 'failed' | 'ttlUnsupported' }
  | { ok: false; reason: 'ttlOutOfRange'; minSeconds: number | null; maxSeconds: number | null };

/** `durationHonoured: false`: the server will use its own duration instead of the requested one. */
export type SubmitOutcome = { ok: true; localId: string; durationHonoured?: boolean } | SubmitFailure;

/** A position the server's plausibility check would accept: finite, in range, not the null island. */
export function isPlausiblePosition({ lat, lng }: Position): boolean {
  return Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 && !(lat === 0 && lng === 0);
}

function outcomeFromError(error: unknown): SubmitFailure {
  if (error instanceof TnError) {
    if (error.code === 'ttlOutOfRange') return { ok: false, reason: 'ttlOutOfRange', minSeconds: null, maxSeconds: null };
    if (error.code === 'invalidArgument') return { ok: false, reason: 'invalidType' };
    if (error.code === 'storageFull') return { ok: false, reason: 'storageFull' };
  }
  return { ok: false, reason: 'failed' };
}

/**
 * Queues a hazard report. It is stored on the device first; nothing leaves the phone until the next sync. Only type and position
 * (and, if the reporter chose one, the duration) are sent. A chosen duration is checked against `getReportLimits` of the type first:
 * unknown limits (before the first sync) or a value outside them queue nothing.
 */
export async function submitHazard(service: TnService, type: string, position: Position, choice: DurationChoice = DEFAULT_CHOICE): Promise<SubmitOutcome> {
  if (!isPlausiblePosition(position)) return { ok: false, reason: 'invalidPosition' };
  try {
    if (choice.kind === 'default') return { ok: true, localId: await service.submitReport(type, position.lat, position.lng) };
    const limits = await service.getReportLimits(type).catch(() => null);
    if (!limits) return { ok: false, reason: 'ttlUnsupported' };
    const check = checkDuration(choice.seconds, limits);
    if (!check.ok) return check.reason === 'unsupported' ? { ok: false, reason: 'ttlUnsupported' } : { ok: false, reason: 'ttlOutOfRange', minSeconds: check.minSeconds, maxSeconds: check.maxSeconds };
    const submitted = await service.submitReportFor(type, position.lat, position.lng, { ttlSeconds: choice.seconds });
    return { ok: true, localId: submitted.localId, durationHonoured: submitted.durationHonoured };
  } catch (error) {
    return outcomeFromError(error);
  }
}

/** Queues the vote "this permanently installed camera is gone". */
export async function reportCameraGone(service: TnService, cameraId: string): Promise<SubmitOutcome> {
  try {
    return { ok: true, localId: await service.reportCameraRemoved(cameraId) };
  } catch (error) {
    return outcomeFromError(error);
  }
}

/** Queues a vote on someone's report. */
export async function voteOnReport(service: TnService, reportId: string, stillThere: boolean): Promise<SubmitOutcome> {
  try {
    return { ok: true, localId: await service.confirmReport(reportId, stillThere) };
  } catch (error) {
    return outcomeFromError(error);
  }
}
