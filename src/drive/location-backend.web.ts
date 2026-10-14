import { bearingDegrees, distanceMeters } from './geo';
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

/**
 * Browsers differ in what a position carries: phones usually give speed and heading, many desktop browsers and some
 * phones give neither. Where they are missing, they are worked out from the step to the previous position: speed from
 * distance over time (only for steps of 0.5 to 15 seconds), heading from the direction (only for a step of 3 m or more,
 * so standing still does not turn the arrow; steps within the position's own uncertainty count as standing). Values the
 * browser did give are never replaced.
 */
export function deriveFix(previous: Fix | null, fix: Fix, accuracyM = 0): Fix {
  if (!previous) return fix;
  const seconds = (fix.t - previous.t) / 1000;
  if (seconds < 0.5 || seconds > 15) return fix;
  const meters = distanceMeters(previous, fix);
  // a step smaller than half the position's own uncertainty is noise, not movement (standing still must not read as walking)
  const noise = Math.max(2, accuracyM / 2);
  return {
    ...fix,
    speedKmh: fix.speedKmh ?? (meters < noise ? 0 : (meters / seconds) * 3.6),
    heading: fix.heading ?? (meters >= 3 ? bearingDegrees(previous, fix) : previous.heading),
  };
}

let sink: ((fix: Fix) => void) | null = null;
let watchId: number | null = null;
let watchHigh: boolean | null = null;
// The previous position, kept across the restarts the location source does when the speed regime changes (it restarts the
// updates to change their rate; a browser has no rate to change). Only the end of the drive forgets it.
let last: Fix | null = null;

/**
 * The browser's position while the drive mode runs, in the foreground only: a hidden tab or a locked screen stops the
 * updates (docs/web-limits.md). The browser decides how often fixes arrive; the sampling regime only chooses accuracy.
 */
export const expoLocationBackend: LocationBackend = {
  setSink(fn) {
    sink = fn;
    if (!fn) last = null;
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
    const high = sampling.accuracy !== 'balanced';
    if (watchId !== null && watchHigh === high) return; // a browser has no rate to change: the watch that runs is the right one
    if (watchId !== null) navigator.geolocation.clearWatch(watchId);
    watchHigh = high;
    watchId = navigator.geolocation.watchPosition(
      (position) => {
        // A new watch is first told the position the browser already had; passing that on again would read as a fix
        // without a step (no speed) and make the speed regime flip back and forth.
        if (last && position.timestamp <= last.t) return;
        const fix = deriveFix(last, fixFromPosition(position), position.coords.accuracy);
        last = fix;
        sink?.(fix);
      },
      () => undefined, // a lost signal is the drive session's business (it notices the silence)
      { enableHighAccuracy: high, maximumAge: 0, timeout: 30_000 },
    );
  },
  async stop() {
    if (watchId !== null) navigator.geolocation.clearWatch(watchId);
    watchId = null;
    watchHigh = null;
  },
};
