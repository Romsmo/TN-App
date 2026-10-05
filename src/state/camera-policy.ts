import { useEffect, useState } from 'react';

import type { TnService } from '@/tn/service';
import type { CameraPolicy } from '@/tn/types';

/**
 * The country policy for speed cameras as the library reports it (local, no network). Null until known.
 * Re-read when the stored data changes, because a stricter policy arrives with a sync.
 */
export function useCameraPolicy(service: TnService | null, version: number): CameraPolicy | null {
  const [result, setResult] = useState<{ service: TnService; policy: CameraPolicy | null } | null>(null);
  useEffect(() => {
    if (!service) return;
    let cancelled = false;
    service
      .getCameraPolicy()
      .then((policy) => !cancelled && setResult({ service, policy }))
      .catch(() => !cancelled && setResult({ service, policy: null }));
    return () => {
      cancelled = true;
    };
  }, [service, version]);
  return service && result?.service === service ? result.policy : null;
}
