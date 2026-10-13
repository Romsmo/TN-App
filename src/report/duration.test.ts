import { setLanguage } from '@/i18n';

import { checkDuration, formatDuration, parseDuration, remainingSeconds } from './duration';

describe('parseDuration', () => {
  it.each([
    ['90', 'min', 5400],
    ['1,5', 'h', 5400],
    ['1.5', 'h', 5400],
    [' 2 ', 'd', 172800],
  ] as const)('%s %s -> %d s', (amount, unit, seconds) => {
    expect(parseDuration(amount, unit)).toBe(seconds);
  });

  it.each(['', 'abc', '0', '-3', 'Infinity', '1e999'])('rejects %j', (amount) => {
    expect(parseDuration(amount, 'h')).toBeNull();
  });
});

describe('checkDuration', () => {
  const limits = { supported: true, defaultSeconds: 7200, minSeconds: 600, maxSeconds: 1_209_600 }; // 14 days, e.g. a trailer
  it('accepts the bounds themselves', () => {
    expect(checkDuration(600, limits)).toEqual({ ok: true });
    expect(checkDuration(1_209_600, limits)).toEqual({ ok: true });
  });
  it('names too short and too long, with the bounds', () => {
    expect(checkDuration(599, limits)).toEqual({ ok: false, reason: 'tooShort', minSeconds: 600, maxSeconds: 1_209_600 });
    expect(checkDuration(1_209_601, limits)).toEqual({ ok: false, reason: 'tooLong', minSeconds: 600, maxSeconds: 1_209_600 });
  });
  it('does not guess without limits', () => {
    expect(checkDuration(3600, { supported: false, defaultSeconds: null, minSeconds: null, maxSeconds: null })).toMatchObject({ ok: false, reason: 'unsupported' });
  });
});

describe('formatDuration / remainingSeconds', () => {
  beforeEach(() => setLanguage('de'));
  it('shows the two largest units', () => {
    expect(formatDuration(900)).toBe('15 Min.');
    expect(formatDuration(3 * 3600)).toBe('3 Std.');
    expect(formatDuration(3 * 3600 + 10 * 60)).toBe('3 Std. 10 Min.');
    expect(formatDuration(14 * 86400)).toBe('14 d');
    expect(formatDuration(86400 + 2 * 3600 + 30 * 60)).toBe('1 d 2 Std.');
  });
  it('takes the remaining time from the server expiry, not from a built-in lifetime', () => {
    const now = Date.parse('2026-10-13T12:00:00Z');
    expect(remainingSeconds('2026-10-13T15:00:00Z', now)).toBe(10800); // a mobile camera: 3 h
    expect(remainingSeconds('2026-10-27T12:00:00Z', now)).toBe(14 * 86400); // a trailer: 14 d
    expect(remainingSeconds('2026-10-13T11:59:59Z', now)).toBeNull();
    expect(remainingSeconds(null, now)).toBeNull();
    expect(remainingSeconds('nonsense', now)).toBeNull();
  });
});
