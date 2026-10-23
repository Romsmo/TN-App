import 'dart:async';

import 'drive_session.dart';
import 'fix.dart';
import 'sampling.dart';

/// A stream of position fixes: the device's location updates, or the simulated route.
abstract interface class PositionSource {
  Future<void> start(void Function(Fix fix) onFix);
  void stop();
}

enum DriveMode { real, simulation }

/// Owns one drive: the session, the position source and the heartbeat. Lives outside the widget tree so that the drive
/// (and its lock) survives screen changes. Start errors (no permission) are thrown to the caller.
class DriveHost {
  DriveHost({
    required this.createSession,
    required this.realSource,
    required this.simSource,
    this.heartbeat = const Duration(seconds: 1),
  });

  final DriveSession Function(bool simulated) createSession;
  final PositionSource Function() realSource;
  final PositionSource Function(int speedup) simSource;
  final Duration heartbeat;

  DriveSession? _session;
  PositionSource? _source;
  Timer? _timer;

  /// Counts starts: an old start that finishes after a stop or a newer start must not touch the current drive.
  int _token = 0;
  void Function()? _unsubscribe;
  DriveSnapshot? _snap;
  final Set<void Function()> _listeners = {};

  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  DriveSnapshot? get snapshot => _snap;

  bool get isActive => _snap?.active == true;

  DriveSession? get current => _session;

  void _emit() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  Future<void> start(DriveMode mode, {int speedup = 1}) async {
    if (_session != null) stop();
    final token = ++_token;
    final session = createSession(mode == DriveMode.simulation);
    final source = mode == DriveMode.simulation ? simSource(speedup) : realSource();
    _session = session;
    _source = source;
    _unsubscribe = session.subscribe(() {
      _snap = session.snapshot;
      _emit();
    });
    session.start();
    try {
      await source.start((fix) {
        if (token == _token) session.onFix(fix);
      });
    } catch (_) {
      if (token == _token) {
        stop();
      } else {
        source.stop(); // an outdated start that failed: only its own source needs cleaning up
      }
      rethrow;
    }
    if (token != _token) {
      // stopped or replaced while the source was starting (e.g. during the permission dialog)
      source.stop();
      return;
    }
    _timer = Timer.periodic(heartbeat, (_) => session.tick());
  }

  void stop() {
    _token++; // invalidates a start that is still waiting
    _timer?.cancel();
    _timer = null;
    _source?.stop();
    _source = null;
    _session?.stop();
    _unsubscribe?.call();
    _unsubscribe = null;
    _session = null;
    _snap = null;
    _emit();
  }
}

/// The device side of the location updates; native in the app, a fake in tests.
abstract interface class LocationBackend {
  /// Where the fixes go while a drive is on; null when none is.
  void setSink(void Function(Fix fix)? sink);

  Future<bool> requestPermission();

  Future<void> start(Sampling sampling);

  /// Stops the updates; does nothing when none are running.
  Future<void> stop();
}

class LocationPermissionDenied implements Exception {
  const LocationPermissionDenied();
  @override
  String toString() => 'location-permission-denied';
}

/// The device's location while the drive mode runs, with accuracy and rate adapted to the speed.
/// Nothing runs outside the drive mode: `stop` ends the updates, also when a change of the rate is just under way.
PositionSource createLocationSource(LocationBackend backend) => _LocationSource(backend);

class _LocationSource implements PositionSource {
  _LocationSource(this._backend);
  final LocationBackend _backend;
  Regime _regime = Regime.crawl;
  bool _stopped = true;
  Future<void>? _restarting;

  Future<void> _restart(Regime next) {
    final previous = _regime;
    return () async {
      try {
        await _backend.stop();
        if (_stopped) return;
        await _backend.start(samplingFor(representativeSpeed[next]));
        _regime = next;
        if (_stopped) await _backend.stop(); // the drive ended while the new rate was starting
      } catch (_) {
        // The new rate did not start: go back to the old one once, so the drive does not go quiet.
        if (!_stopped) {
          try {
            await _backend.start(samplingFor(representativeSpeed[previous]));
          } catch (_) {}
        }
      } finally {
        _restarting = null;
      }
    }();
  }

  @override
  Future<void> start(void Function(Fix fix) onFix) async {
    if (!await _backend.requestPermission()) throw const LocationPermissionDenied();
    _stopped = false;
    _regime = Regime.crawl;
    _backend.setSink((fix) {
      if (_stopped) return;
      onFix(fix);
      final next = nextRegime(_regime, fix.speedKmh);
      if (next != _regime && _restarting == null) _restarting = _restart(next);
    });
    await _backend.start(samplingFor(null));
  }

  @override
  void stop() {
    _stopped = true;
    _backend.setSink(null);
    // wait for a restart that is under way, then make sure nothing is left running
    unawaited((_restarting ?? Future<void>.value()).whenComplete(_backend.stop).catchError((_) {}));
  }
}
