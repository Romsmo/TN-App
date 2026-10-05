import { hazardColor, hazardColorExpression, HAZARD_COLORS, UNKNOWN_HAZARD_COLOR } from './colors';

describe('hazard colours', () => {
  it('has a colour for every type the server documents, all distinct from the fallback', () => {
    for (const type of ['traffic', 'ice', 'accident', 'construction', 'breakdown', 'obstacle', 'fixedSpeedCamera', 'mobileSpeedCamera', 'trailerCamera', 'redLightCamera', 'distanceControl']) {
      expect(hazardColor(type)).not.toBe(UNKNOWN_HAZARD_COLOR);
    }
  });

  it('falls back to grey for an unknown type', () => {
    expect(hazardColor('somethingNew')).toBe(UNKNOWN_HAZARD_COLOR);
  });

  it('builds a match expression with the fallback last', () => {
    const expression = hazardColorExpression() as unknown[];
    expect(expression[0]).toBe('match');
    expect(expression[expression.length - 1]).toBe(UNKNOWN_HAZARD_COLOR);
    expect(expression.length).toBe(2 + Object.keys(HAZARD_COLORS).length * 2 + 1);
  });
});
