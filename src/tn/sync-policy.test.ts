import { shouldSync } from './sync-policy';

describe('shouldSync', () => {
  it.each([
    // wifiOnly, onWifi, bytesPending, expected
    [true, true, 5_000_000, true],
    [true, false, 5_000_000, false],
    [true, false, null, false],
    [true, false, 0, true],
    [false, false, 5_000_000, true],
    [false, true, null, true],
  ])('wifiOnly=%s onWifi=%s pending=%s -> %s', (wifiOnly, onWifi, bytesPending, expected) => {
    expect(shouldSync({ wifiOnly, onWifi, bytesPending })).toBe(expected);
  });
});
