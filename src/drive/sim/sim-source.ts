import type { PositionSource } from '../drive-host';
import { DEMO_ROUTE_GPX } from './demo-route.gpx';
import { buildRoute, parseGpx } from './gpx';
import { RoutePlayer } from './player';
import { simSpeedAt } from './sim-data';

export const demoRoute = buildRoute(parseGpx(DEMO_ROUTE_GPX));

/** The demo route as a position source: one fix per second of simulated time, `speedup` times faster than real time. */
export function createSimSource(speedup: number, hooks: { onFinished?: () => void } = {}): PositionSource {
  let timer: ReturnType<typeof setInterval> | null = null;
  return {
    start(onFix) {
      const player = new RoutePlayer(demoRoute, simSpeedAt, Date.now());
      timer = setInterval(() => {
        const fix = player.next();
        if (!fix) {
          if (timer) clearInterval(timer);
          timer = null;
          hooks.onFinished?.();
          return;
        }
        onFix({ ...fix, t: Date.now() });
      }, 1000 / Math.max(1, speedup));
    },
    stop() {
      if (timer) clearInterval(timer);
      timer = null;
    },
  };
}
