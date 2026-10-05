import { useEffect, useState } from 'react';

import type { TnService } from '@/tn/service';
import type { NearbyItem } from '@/tn/types';

export type Viewport = { lat: number; lng: number; radiusMeters: number };

/**
 * Reads the items around the viewport from the local store. It re-reads when the viewport or the stored data changes
 * and keeps showing the previous result meanwhile (no flicker). Without a service or viewport the answer is empty.
 */
export function useNearby(service: TnService | null, viewport: Viewport | null, dataVersion: number): NearbyItem[] {
  const [result, setResult] = useState<{ service: TnService; items: NearbyItem[] } | null>(null);
  const lat = viewport?.lat;
  const lng = viewport?.lng;
  const radius = viewport?.radiusMeters;

  useEffect(() => {
    if (!service || lat === undefined || lng === undefined || radius === undefined) return;
    let cancelled = false;
    service
      .getNearby(lat, lng, radius)
      .then((items) => !cancelled && setResult({ service, items }))
      .catch(() => !cancelled && setResult({ service, items: [] })); // e.g. before the first sync: an empty map is the honest answer
    return () => {
      cancelled = true;
    };
  }, [service, lat, lng, radius, dataVersion]);

  return service && viewport && result?.service === service ? result.items : [];
}

/** Radius that covers the visible map: the distance from the centre to a corner, kept inside what the library allows. */
export function radiusFor(center: { lat: number; lng: number }, corner: { lat: number; lng: number }): number {
  const R = 6_371_000;
  const rad = (d: number) => (d * Math.PI) / 180;
  const dLat = rad(corner.lat - center.lat);
  const dLng = rad(corner.lng - center.lng);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(center.lat)) * Math.cos(rad(corner.lat)) * Math.sin(dLng / 2) ** 2;
  const meters = 2 * R * Math.asin(Math.min(1, Math.sqrt(a)));
  return Math.min(50_000, Math.max(500, Math.round(meters)));
}
