import { deriveFix, fixFromPosition } from './derive-fix';
import type { LocationBackend } from './location-source';
import type { Sampling } from './sampling';
import type { Fix } from './warning-engine';

export { deriveFix, fixFromPosition };

/** Kept so `_layout.tsx` and the drive wiring need no platform check; a browser has no background task. */
export const DRIVE_LOCATION_TASK = 'tnviewer-drive-location';
export function defineDriveLocationTask(): void {}

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
