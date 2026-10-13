import * as Location from 'expo-location';
import { useEffect, useState } from 'react';

import { deriveFix, fixFromPosition } from '@/drive/derive-fix';
import type { Fix } from '@/drive/warning-engine';

export type DevicePosition = { lat: number; lng: number; heading: number | null; accuracy: number | null; speedKmh: number | null; t: number };

/**
 * The device's position while the map is shown, as often as it changes by a few metres: the arrow and the "follows me"
 * mode need it. Runs only while `enabled` (permission was given, the map is on screen); with no permission it never asks.
 * The heading is the receiver's course; where the receiver gives none, it comes from the step to the previous position.
 */
export function useDevicePosition(enabled: boolean): DevicePosition | null {
  const [position, setPosition] = useState<DevicePosition | null>(null);
  useEffect(() => {
    if (!enabled) return;
    let cancelled = false;
    let subscription: Location.LocationSubscription | null = null;
    let last: Fix | null = null;
    void (async () => {
      try {
        if (!(await Location.getForegroundPermissionsAsync()).granted || cancelled) return;
        subscription = await Location.watchPositionAsync({ accuracy: Location.Accuracy.Balanced, distanceInterval: 5, timeInterval: 2000 }, (location) => {
          const fix = deriveFix(last, fixFromPosition(location), location.coords.accuracy ?? 0);
          last = { ...fix, heading: fix.heading ?? last?.heading ?? null };
          setPosition({ lat: fix.lat, lng: fix.lng, heading: last.heading, accuracy: location.coords.accuracy ?? null, speedKmh: fix.speedKmh, t: fix.t });
        });
        if (cancelled) subscription.remove();
      } catch {
        // no position: the arrow stays where it was, nothing else depends on it
      }
    })();
    return () => {
      cancelled = true;
      subscription?.remove();
    };
  }, [enabled]);
  return enabled ? position : null;
}
