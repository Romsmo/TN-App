import { TnError, type TnService } from '@/tn/service';

export type Position = { lat: number; lng: number };

export type SubmitOutcome = { ok: true; localId: string } | { ok: false; reason: 'invalidPosition' | 'invalidType' | 'storageFull' | 'failed' };

/** A position the server's plausibility check would accept: finite, in range, not the null island. */
export function isPlausiblePosition({ lat, lng }: Position): boolean {
  return Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 && !(lat === 0 && lng === 0);
}

function outcomeFromError(error: unknown): Extract<SubmitOutcome, { ok: false }> {
  if (error instanceof TnError) {
    if (error.code === 'invalidArgument') return { ok: false, reason: 'invalidType' };
    if (error.code === 'storageFull') return { ok: false, reason: 'storageFull' };
  }
  return { ok: false, reason: 'failed' };
}

/** Queues a hazard report. It is stored on the device first; nothing leaves the phone until the next sync. Only type and position are sent. */
export async function submitHazard(service: TnService, type: string, position: Position): Promise<SubmitOutcome> {
  if (!isPlausiblePosition(position)) return { ok: false, reason: 'invalidPosition' };
  try {
    return { ok: true, localId: await service.submitReport(type, position.lat, position.lng) };
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
