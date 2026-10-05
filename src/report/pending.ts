import { t } from '@/i18n';

/**
 * What to tell the user about reports that are stored on the device but not yet sent. Waiting is a normal state
 * of an offline-first app, not an error, so the wording explains instead of alarming.
 */
export function pendingText(input: { pending: number; waitingForWifi: boolean; offline: boolean }): string | null {
  if (input.pending <= 0) return null;
  if (input.waitingForWifi) return t('pending.wifi', { count: input.pending });
  if (input.offline) return t('pending.offline', { count: input.pending });
  return t('pending.sending', { count: input.pending });
}

/** A soft notice for writes a server refused for good (rate limit, plausibility, …). Not shown as a failure. */
export function rejectedText(rejected: number): string | null {
  return rejected > 0 ? t('rejected.notice', { count: rejected }) : null;
}
