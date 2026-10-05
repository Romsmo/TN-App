import { displayLimit, displaySpeed, fromKmh, speedState, toKmh, unitLabel } from './units';

describe('units', () => {
  it('converts between km/h and mph', () => {
    expect(toKmh(60, 'mph')).toBeCloseTo(96.56, 2);
    expect(fromKmh(100, 'mph')).toBeCloseTo(62.14, 2);
    expect(toKmh(50, 'kmh')).toBe(50);
  });

  it('rounds the displayed speed and never shows a negative one', () => {
    expect(displaySpeed(99.6, 'kmh')).toBe(100);
    expect(displaySpeed(100, 'mph')).toBe(62);
    expect(displaySpeed(-3, 'kmh')).toBe(0);
    expect(displaySpeed(null, 'kmh')).toBeNull();
  });

  it('shows a limit in the user unit in 5-steps when converted, unchanged otherwise', () => {
    expect(displayLimit(50, 'kmh', 'kmh')).toBe(50);
    expect(displayLimit(50, 'kmh', 'mph')).toBe(30);
    expect(displayLimit(30, 'mph', 'kmh')).toBe(50);
  });

  it('labels the units', () => {
    expect(unitLabel('kmh')).toBe('km/h');
    expect(unitLabel('mph')).toBe('mph');
  });
});

describe('speedState', () => {
  it.each([
    [50, { value: 50, unit: 'kmh' as const }, 'ok'],
    [53, { value: 50, unit: 'kmh' as const }, 'ok'], // within the tolerance
    [54, { value: 50, unit: 'kmh' as const }, 'over'],
    [100, { value: 60, unit: 'mph' as const }, 'over'], // 60 mph = 96.6 km/h
    [95, { value: 60, unit: 'mph' as const }, 'ok'],
    [200, null, 'ok'], // no limit known: never red
    [null, { value: 50, unit: 'kmh' as const }, 'ok'],
  ])('%s km/h against %j is %s', (speed, limit, expected) => {
    expect(speedState(speed, limit)).toBe(expected);
  });
});
