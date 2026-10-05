import { HAZARD_COLORS } from './colors';
import { hazardIcon } from './hazard-icons';

describe('hazardIcon', () => {
  it.each([
    ['traffic', 'car'],
    ['accident', 'warning'],
    ['construction', 'construct'],
    ['ice', 'snow'],
    ['breakdown', 'build'],
    ['obstacle', 'alert-circle'],
    ['mobileSpeedCamera', 'camera'],
    ['cameras', 'camera'],
  ])('%s -> %s', (type, icon) => {
    expect(hazardIcon(type)).toBe(icon);
  });

  it('has a symbol for every type that has a colour, the camera types sharing one', () => {
    for (const type of Object.keys(HAZARD_COLORS)) expect(typeof hazardIcon(type)).toBe('string');
    expect(new Set(['fixedSpeedCamera', 'mobileSpeedCamera', 'trailerCamera', 'redLightCamera', 'distanceControl'].map(hazardIcon)).size).toBe(1);
  });

  it('shows an unknown type with a neutral symbol', () => {
    expect(hazardIcon('somethingNew')).toBe('alert-circle');
  });
});
