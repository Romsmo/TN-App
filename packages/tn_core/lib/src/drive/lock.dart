/// Speed from which the app counts as "being driven": settings, text input and server pages are locked. Not configurable.
const double lockOnKmh = 10;

/// Back below this speed the lock is released (hysteresis, so crawling traffic does not flicker the lock).
const double lockOffKmh = 5;

/// The speed must stay low this long before the lock is released.
const int lockReleaseAfterMs = 2000;

/// Without any position for this long a locked app releases the lock (tunnel, GPS lost, phone parked).
const int lockStaleAfterMs = 60000;

/// Whether the lock is currently in force, given the drive session and the user's lock setting.
bool isLockActive({required bool driving, required bool lockEnabled, required bool locked}) =>
    driving && lockEnabled && locked;

/// Speed-based lock with hysteresis. Pure state machine: feed it speeds with timestamps, ask it whether the app is locked.
/// It does not know about the user's "lock enabled" setting; [isLockActive] combines the two.
class LockTracker {
  bool _locked = false;
  int? _lowSince;
  int? _lastFixAt;

  bool update(double? speedKmh, int now) {
    _lastFixAt = now;
    if (speedKmh == null) return _locked; // no speed reading: keep the state, staleness handles the rest
    if (speedKmh >= lockOnKmh) {
      _locked = true;
      _lowSince = null;
    } else if (_locked && speedKmh <= lockOffKmh) {
      _lowSince ??= now;
      if (now - _lowSince! >= lockReleaseAfterMs) {
        _locked = false;
        _lowSince = null;
      }
    } else {
      _lowSince = null; // between the two thresholds: no change, restart the dwell
    }
    return _locked;
  }

  /// Call regularly (the session ticks): releases a lock that has gone stale.
  bool tick(int now) {
    if (_locked && _lastFixAt != null && now - _lastFixAt! >= lockStaleAfterMs) {
      _locked = false;
      _lowSince = null;
    }
    return _locked;
  }

  void reset() {
    _locked = false;
    _lowSince = null;
    _lastFixAt = null;
  }

  bool get isLocked => _locked;
}
