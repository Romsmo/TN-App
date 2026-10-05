import { isLockActive, LOCK_OFF_KMH, LOCK_ON_KMH, LOCK_RELEASE_AFTER_MS, LOCK_STALE_AFTER_MS, LockTracker } from './lock';

describe('LockTracker', () => {
  it('starts open (standing still, not yet driving)', () => {
    expect(new LockTracker().isLocked).toBe(false);
  });

  it.each([
    [0, false],
    [9.9, false],
    [LOCK_ON_KMH, true],
    [50, true],
  ])('at %s km/h from standstill the lock is %s', (speed, expected) => {
    expect(new LockTracker().update(speed, 0)).toBe(expected);
  });

  it('stays locked when the speed drops only briefly or only a little', () => {
    const t = new LockTracker();
    t.update(50, 0);
    expect(t.update(LOCK_OFF_KMH, 1000)).toBe(true); // low, but not for long enough
    expect(t.update(7, 5000)).toBe(true); // between the thresholds: unchanged
    expect(t.update(LOCK_OFF_KMH, 6000)).toBe(true); // the dwell restarted
  });

  it('releases after the speed stayed low long enough', () => {
    const t = new LockTracker();
    t.update(50, 0);
    t.update(2, 1000);
    expect(t.update(0, 1000 + LOCK_RELEASE_AFTER_MS - 1)).toBe(true);
    expect(t.update(0, 1000 + LOCK_RELEASE_AFTER_MS)).toBe(false);
  });

  it('locks again as soon as the car moves on', () => {
    const t = new LockTracker();
    t.update(50, 0);
    t.update(0, 1000);
    t.update(0, 4000);
    expect(t.isLocked).toBe(false);
    expect(t.update(30, 5000)).toBe(true);
  });

  it('keeps the state without a speed reading', () => {
    const t = new LockTracker();
    t.update(60, 0);
    expect(t.update(null, 1000)).toBe(true);
  });

  it('releases a stale lock when no position arrives for a minute', () => {
    const t = new LockTracker();
    t.update(60, 0);
    expect(t.tick(LOCK_STALE_AFTER_MS - 1)).toBe(true);
    expect(t.tick(LOCK_STALE_AFTER_MS)).toBe(false);
  });

  it('reset opens the lock', () => {
    const t = new LockTracker();
    t.update(60, 0);
    t.reset();
    expect(t.isLocked).toBe(false);
  });
});

describe('isLockActive', () => {
  it.each([
    // driving, lockEnabled, locked, expected
    [true, true, true, true],
    [true, true, false, false],
    [true, false, true, false], // the user switched the lock off
    [false, true, true, false], // no drive session: nothing is locked
    [false, false, false, false],
  ])('driving=%s lockEnabled=%s locked=%s -> %s', (driving, lockEnabled, locked, expected) => {
    expect(isLockActive({ driving, lockEnabled, locked })).toBe(expected);
  });
});
