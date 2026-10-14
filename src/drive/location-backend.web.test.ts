import { deriveFix, fixFromPosition } from './location-backend.web';
import type { Fix } from './warning-engine';

const at = (lat: number, lng: number, t: number, extra: Partial<Fix> = {}): Fix => ({ lat, lng, speedKmh: null, heading: null, t, ...extra });

describe('fixFromPosition', () => {
  it('converts m/s to km/h and keeps a valid heading', () => {
    const fix = fixFromPosition({ coords: { latitude: 1, longitude: 2, speed: 10, heading: 90 }, timestamp: 5 });
    expect(fix).toEqual({ lat: 1, lng: 2, speedKmh: 36, heading: 90, t: 5 });
  });
  it('reads a missing, negative or NaN speed and heading as unknown', () => {
    expect(fixFromPosition({ coords: { latitude: 1, longitude: 2, speed: null, heading: null }, timestamp: 0 })).toMatchObject({ speedKmh: null, heading: null });
    expect(fixFromPosition({ coords: { latitude: 1, longitude: 2, speed: -1, heading: NaN }, timestamp: 0 })).toMatchObject({ speedKmh: null, heading: null });
  });
});

describe('deriveFix', () => {
  // 0.0002 degrees of latitude are about 22 m
  const first = at(52.0, 13.0, 0);

  it('leaves the first position alone', () => {
    expect(deriveFix(null, first)).toBe(first);
  });

  it('works out speed and heading from the step when the browser gave none (22 m in 2 s north: about 40 km/h)', () => {
    const next = deriveFix(first, at(52.0002, 13.0, 2000));
    expect(next.speedKmh).toBeGreaterThan(38);
    expect(next.speedKmh).toBeLessThan(42);
    expect(next.heading).toBeCloseTo(0, 0);
  });

  it('never replaces values the browser did give', () => {
    const next = deriveFix(first, at(52.0002, 13.0, 2000, { speedKmh: 99, heading: 123 }));
    expect(next).toMatchObject({ speedKmh: 99, heading: 123 });
  });

  it('reads a tiny step as standing still and keeps the previous heading (the arrow must not spin)', () => {
    const moving = at(52.0, 13.0, 0, { heading: 270 });
    expect(deriveFix(moving, at(52.000005, 13.0, 1000))).toMatchObject({ speedKmh: 0, heading: 270 });
  });

  it('reads steps within the uncertainty of the position as standing still (GPS jitter is not walking)', () => {
    // about 7 m in a second would be 25 km/h; with an accuracy of 20 m it is noise
    expect(deriveFix(first, at(52.00006, 13.0, 1000), 20).speedKmh).toBe(0);
    expect(deriveFix(first, at(52.00006, 13.0, 1000), 5).speedKmh).toBeGreaterThan(20);
  });

  it('does not guess over a gap (a step after more than 15 seconds, or less than half a second)', () => {
    expect(deriveFix(first, at(52.01, 13.0, 60_000)).speedKmh).toBeNull();
    expect(deriveFix(first, at(52.0002, 13.0, 100)).speedKmh).toBeNull();
  });
});
