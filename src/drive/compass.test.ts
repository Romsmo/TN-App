import { cardinalIndex } from './compass';

describe('cardinalIndex', () => {
  it.each([
    [0, 0], [22, 0], [23, 1], [45, 1], [90, 2], [135, 3], [180, 4], [225, 5], [270, 6], [315, 7], [337, 7], [338, 0], [359.9, 0], [360, 0], [-45, 7], [720 + 90, 2],
  ])('heading %d is point %d', (heading, index) => {
    expect(cardinalIndex(heading)).toBe(index);
  });
});
