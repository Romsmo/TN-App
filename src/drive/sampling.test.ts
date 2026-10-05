import { nextRegime, samplingFor } from './sampling';

describe('samplingFor', () => {
  it.each([
    [null, 'crawl'],
    [0, 'crawl'],
    [14, 'crawl'],
    [15, 'city'],
    [79, 'city'],
    [80, 'fast'],
    [160, 'fast'],
  ])('%s km/h -> %s', (speed, regime) => {
    expect(samplingFor(speed).regime).toBe(regime);
  });

  it('asks more often and more precisely the faster it goes', () => {
    expect(samplingFor(120).timeIntervalMs).toBeLessThan(samplingFor(40).timeIntervalMs);
    expect(samplingFor(40).timeIntervalMs).toBeLessThan(samplingFor(3).timeIntervalMs);
    expect(samplingFor(3).accuracy).toBe('balanced');
    expect(samplingFor(120).accuracy).toBe('navigation');
  });
});

describe('nextRegime', () => {
  it('does not flip at the boundary', () => {
    expect(nextRegime('city', 79)).toBe('city');
    expect(nextRegime('city', 81)).toBe('fast'); // crossed the speed for good
    expect(nextRegime('fast', 78)).toBe('fast'); // not yet back
    expect(nextRegime('fast', 60)).toBe('city');
    expect(nextRegime('crawl', 16)).toBe('crawl');
    expect(nextRegime('crawl', 25)).toBe('city');
  });
});
