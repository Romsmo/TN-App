import type { PositionSource } from './drive-host';
import { nextRegime, samplingFor, type Sampling } from './sampling';
import type { Fix } from './warning-engine';

/** The device side of the location updates; native in the app (`location-backend.ts`), a fake in tests. */
export interface LocationBackend {
  /** Where the fixes go while a drive is on; null when none is. */
  setSink(sink: ((fix: Fix) => void) | null): void;
  requestPermission(): Promise<boolean>;
  start(sampling: Sampling): Promise<void>;
  /** Stops the updates; does nothing when none are running. */
  stop(): Promise<void>;
}

const REPRESENTATIVE_SPEED: Record<Sampling['regime'], number> = { crawl: 0, city: 40, fast: 100 };

/**
 * The device's location while the drive mode runs, with accuracy and rate adapted to the speed.
 * Nothing runs outside the drive mode: `stop` ends the updates, also when a change of the rate is just under way.
 */
export function createLocationSource(backend: LocationBackend): PositionSource {
  let regime: Sampling['regime'] = 'crawl';
  let stopped = true;
  let restarting: Promise<void> | null = null;

  const restart = (next: Sampling['regime']): Promise<void> => {
    const previous = regime;
    return (async () => {
      try {
        await backend.stop();
        if (stopped) return;
        await backend.start(samplingFor(REPRESENTATIVE_SPEED[next]));
        regime = next;
        if (stopped) await backend.stop(); // the drive ended while the new rate was starting
      } catch {
        // The new rate did not start: go back to the old one once, so the drive does not go quiet.
        if (!stopped) await backend.start(samplingFor(REPRESENTATIVE_SPEED[previous])).catch(() => undefined);
      } finally {
        restarting = null;
      }
    })();
  };

  return {
    async start(onFix) {
      if (!(await backend.requestPermission())) throw new Error('location-permission-denied');
      stopped = false;
      regime = 'crawl';
      backend.setSink((fix) => {
        if (stopped) return;
        onFix(fix);
        const next = nextRegime(regime, fix.speedKmh);
        if (next !== regime && !restarting) restarting = restart(next);
      });
      await backend.start(samplingFor(null));
    },
    stop() {
      stopped = true;
      backend.setSink(null);
      // wait for a restart that is under way, then make sure nothing is left running
      void (restarting ?? Promise.resolve()).finally(() => backend.stop()).catch(() => undefined);
    },
  };
}
