/** Speed from which the app counts as "being driven": settings, text input and server pages are locked. Not configurable. */
export const LOCK_ON_KMH = 10;
/** Back below this speed the lock is released (hysteresis, so crawling traffic does not flicker the lock). */
export const LOCK_OFF_KMH = 5;
/** The speed must stay low this long before the lock is released. */
export const LOCK_RELEASE_AFTER_MS = 2_000;
/** Without any position for this long a locked app releases the lock (tunnel, GPS lost, phone parked). */
export const LOCK_STALE_AFTER_MS = 60_000;

/** Whether the lock is currently in force, given the drive session and the user's lock setting. */
export function isLockActive(input: { driving: boolean; lockEnabled: boolean; locked: boolean }): boolean {
  return input.driving && input.lockEnabled && input.locked;
}

/**
 * Speed-based lock with hysteresis. Pure state machine: feed it speeds with timestamps, ask it whether the app is locked.
 * It does not know about the user's "lock enabled" setting; `isLockActive` combines the two.
 */
export class LockTracker {
  private locked = false;
  private lowSince: number | null = null;
  private lastFixAt: number | null = null;

  update(speedKmh: number | null, now: number): boolean {
    this.lastFixAt = now;
    if (speedKmh === null) return this.locked; // no speed reading: keep the state, staleness handles the rest
    if (speedKmh >= LOCK_ON_KMH) {
      this.locked = true;
      this.lowSince = null;
    } else if (this.locked && speedKmh <= LOCK_OFF_KMH) {
      this.lowSince ??= now;
      if (now - this.lowSince >= LOCK_RELEASE_AFTER_MS) {
        this.locked = false;
        this.lowSince = null;
      }
    } else {
      this.lowSince = null; // between the two thresholds: no change, restart the dwell
    }
    return this.locked;
  }

  /** Call regularly (the session ticks): releases a lock that has gone stale. */
  tick(now: number): boolean {
    if (this.locked && this.lastFixAt !== null && now - this.lastFixAt >= LOCK_STALE_AFTER_MS) {
      this.locked = false;
      this.lowSince = null;
    }
    return this.locked;
  }

  reset(): void {
    this.locked = false;
    this.lowSince = null;
    this.lastFixAt = null;
  }

  get isLocked(): boolean {
    return this.locked;
  }
}
