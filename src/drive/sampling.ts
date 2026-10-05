/** How often and how precisely the device is asked for its position. */
export type Sampling = { regime: 'crawl' | 'city' | 'fast'; accuracy: 'balanced' | 'high' | 'navigation'; distanceIntervalM: number; timeIntervalMs: number };

/**
 * Accuracy and rate only as high as the warnings need: standing or crawling needs little, fast driving needs
 * a fix every second or so because a warning distance is only a few hundred metres.
 */
export function samplingFor(speedKmh: number | null): Sampling {
  if (speedKmh === null || speedKmh < 15) return { regime: 'crawl', accuracy: 'balanced', distanceIntervalM: 20, timeIntervalMs: 5000 };
  if (speedKmh < 80) return { regime: 'city', accuracy: 'high', distanceIntervalM: 10, timeIntervalMs: 2000 };
  return { regime: 'fast', accuracy: 'navigation', distanceIntervalM: 15, timeIntervalMs: 1000 };
}

/** The regime to use now, staying in the old one near the boundaries so the location updates are not restarted all the time. */
export function nextRegime(current: Sampling['regime'], speedKmh: number | null): Sampling['regime'] {
  const wanted = samplingFor(speedKmh).regime;
  if (wanted === current) return current;
  const v = speedKmh ?? 0;
  if (current === 'crawl' && v < 20) return 'crawl';
  if (current === 'city' && v >= 12 && v < 90 && wanted !== 'fast') return 'city';
  if (current === 'city' && v >= 70 && v < 80) return 'city';
  if (current === 'fast' && v >= 70) return 'fast';
  return wanted;
}
