import type { LocationBackend } from './location-source';
import type { Sampling } from './sampling';
import type { Fix } from './warning-engine';

/** Kept so `_layout.tsx` and the drive wiring need no platform check; a browser has no background task. */
export const DRIVE_LOCATION_TASK = 'tnviewer-drive-location';
export function defineDriveLocationTask(): void {}

/** A browser position as the drive's `Fix`: m/s to km/h, a missing or invalid speed or heading as null. */
export function fixFromPosition(position: { coords: { latitude: number; longitude: number; speed: number | null; heading: number | null }; timestamp: number }): Fix {
  const { latitude, longitude, speed, heading } = position.coords;
  return {
    lat: latitude,
    lng: longitude,
    speedKmh: speed !== null && Number.isFinite(speed) && speed >= 0 ? speed * 3.6 : null,
    heading: heading !== null && Number.isFinite(heading) && heading >= 0 ? heading : null,
    t: position.timestamp,
  };
}

let sink: ((fix: Fix) => void) | null = null;
let watchId: number | null = null;

/**
 * The browser's position while the drive mode runs, in the foreground only: a hidden tab or a locked screen stops the
 * updates (docs/web-limits.md). The browser decides how often fixes arrive; the sampling regime only chooses accuracy.
 */
export const expoLocationBackend: LocationBackend = {
  setSink(fn) {
    sink = fn;
  },
  requestPermission() {
    return new Promise<boolean>((resolve) => {
      if (!('geolocation' in navigator)) return resolve(false);
      navigator.geolocation.getCurrentPosition(
        () => resolve(true),
        () => resolve(false),
        { maximumAge: 60_000, timeout: 20_000 },
      );
    });
  },
  async start(sampling: Sampling) {
    if (watchId !== null) navigator.geolocation.clearWatch(watchId);
    watchId = navigator.geolocation.watchPosition(
      (position) => sink?.(fixFromPosition(position)),
      () => undefined, // a lost signal is the drive session's business (it notices the silence)
      { enableHighAccuracy: sampling.accuracy !== 'balanced', maximumAge: 0, timeout: 30_000 },
    );
  },
  async stop() {
    if (watchId !== null) navigator.geolocation.clearWatch(watchId);
    watchId = null;
  },
};
