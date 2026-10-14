import { t } from '@/i18n';

import { formatDuration } from './duration';
import type { SubmitFailure } from './submit';

/** The sentence for a failed report; for a duration outside the server's bounds it names the bounds when they are known. */
export function submitErrorText(failure: SubmitFailure): string {
  if (failure.reason === 'ttlOutOfRange' && failure.minSeconds !== null && failure.maxSeconds !== null) {
    return t('report.error.ttlRange', { min: formatDuration(failure.minSeconds), max: formatDuration(failure.maxSeconds) });
  }
  return t(`report.error.${failure.reason}`);
}
