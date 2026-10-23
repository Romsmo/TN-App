import 'dart:async';

import 'tn/basics.dart';
import 'tn/service.dart';
import 'tn/types.dart';

enum Phase { starting, ready, noCredentials, error }

/// The emergency mode: this install has never loaded any data from a server, and right now it cannot.
/// `noServer`: nothing was reachable; `noAccess`: no credentials were given. Reads answer from an empty store, writes are
/// queued on the device (the library stores every write locally first) and go out when a server answers.
/// `lastSyncedAtUnixMs` is the time of the last *attempt*, so "never loaded anything" is told by `staticDataVersion` being null.
enum Emergency { noServer, noAccess }

class ConnectionSnapshot {
  const ConnectionSnapshot({
    this.phase = Phase.starting,
    this.error,
    this.service,
    this.sync,
    this.network,
    this.waitingForWifi = false,
    this.rejectedWrites = 0,
    this.dataVersion = 0,
    this.emergency,
    this.needsLocation = false,
  });
  final Phase phase;
  final String? error;
  final TnService? service;
  final SyncStatus? sync;
  final NetworkStatus? network;

  /// The static data is still waiting for Wi-Fi (the "Wi-Fi only" setting).
  final bool waitingForWifi;

  /// Queued writes the server refused for good since the app started and the user has not yet acknowledged.
  final int rejectedWrites;

  /// Bumps whenever data in the local store changed; screens re-read when it moves.
  final int dataVersion;

  /// The emergency mode, or null. It ends by itself with the first successful sync.
  final Emergency? emergency;

  /// The offline area is automatic and no position or home is known, so nothing is selected to load.
  final bool needsLocation;

  ConnectionSnapshot copyWith({
    Phase? phase,
    Object? error = _unset,
    TnService? service,
    SyncStatus? sync,
    NetworkStatus? network,
    bool? waitingForWifi,
    int? rejectedWrites,
    int? dataVersion,
    bool? needsLocation,
  }) =>
      ConnectionSnapshot(
        phase: phase ?? this.phase,
        error: identical(error, _unset) ? this.error : error as String?,
        service: service ?? this.service,
        sync: sync ?? this.sync,
        network: network ?? this.network,
        waitingForWifi: waitingForWifi ?? this.waitingForWifi,
        rejectedWrites: rejectedWrites ?? this.rejectedWrites,
        dataVersion: dataVersion ?? this.dataVersion,
        needsLocation: needsLocation ?? this.needsLocation,
      );
}

const Object _unset = Object();

/// Derived from the rest of the snapshot, so it can never disagree with it.
Emergency? emergencyOf({required Phase phase, required SyncStatus? sync, required bool waitingForWifi}) {
  if (phase == Phase.starting) return null; // the first attempt is still running
  if (waitingForWifi) return null; // not "no server": the user's own Wi-Fi-only choice is holding the download back
  if (phase == Phase.noCredentials) return Emergency.noAccess;
  if (phase != Phase.ready || sync == null) return null; // an error of the app itself has its own message
  if (sync.staticDataVersion != null) return null; // data from an earlier sync is on the device: plain offline
  return sync.connection == Connection.online ? null : Emergency.noServer;
}

/// How often an "all static data loaded" is verified again.
const Duration _staticRecheck = Duration(minutes: 10);

/// One library client for one set of options: starts it, keeps it ticking, tells subscribers what changed.
/// A plain class (not a widget) so the flow is testable without Flutter and so the UI only has to subscribe.
class TnConnection {
  TnConnection({
    required this.createService,
    required this.isOnWifi,
    this.tickInterval = const Duration(milliseconds: tickIntervalMs),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Builds the library client (asynchronous: the native library is loaded and the client created).
  final Future<TnService> Function() createService;
  final Future<bool> Function() isOnWifi;
  final Duration tickInterval;
  final DateTime Function() _clock;

  ConnectionSnapshot _snap = const ConnectionSnapshot();
  final Set<void Function()> _listeners = {};
  TnService? _client;
  Timer? _timer;
  Timer? _bumpTimer;
  bool _staticComplete = false;
  DateTime _staticCheckedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _current;
  bool _busy = false;
  bool _stopped = false;
  bool _wifiOnly = true;

  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  ConnectionSnapshot get snapshot => _snap;

  void setWifiOnly(bool value) => _wifiOnly = value;

  /// The user has read the notice about refused writes.
  void dismissRejected() => _set(rejectedWrites: 0);

  /// Sync now. [ignoreWifi] is for an explicit tap on "load anyway". Waits for a pass that is already running, then
  /// runs: an explicit tap must not be dropped.
  Future<void> syncNow({bool ignoreWifi = false}) async {
    while (_busy && _current != null) {
      await _current!.catchError((_) {});
    }
    await _run(true, ignoreWifi);
  }

  Future<void> start() async {
    _stopped = false;
    final TnService client;
    try {
      client = await createService();
    } catch (e) {
      _set(phase: Phase.error, error: '$e');
      return;
    }
    if (_stopped) {
      // stopped while the client was being created
      await client.close();
      return;
    }
    _client = client;
    client.onEvents((event) {
      if (event is DataChanged) {
        _bump();
      } else if (event is BootstrapProgress && event.partitionsDone >= event.partitionsTotal) {
        _bump();
      }
    });
    _set(service: client);
    unawaited(client.startRealtime().catchError((_) {}));
    unawaited(_run(false, false));
    _timer = Timer.periodic(tickInterval, (_) => unawaited(_run(false, false)));
  }

  Future<void> stop() async {
    _stopped = true;
    _timer?.cancel();
    _bumpTimer?.cancel();
    final client = _client;
    _client = null;
    await client?.close();
  }

  void _set({
    Phase? phase,
    Object? error = _unset,
    TnService? service,
    SyncStatus? sync,
    NetworkStatus? network,
    bool? waitingForWifi,
    int? rejectedWrites,
    int? dataVersion,
    bool? needsLocation,
  }) {
    if (_stopped) return;
    final next = _snap.copyWith(
      phase: phase,
      error: error,
      service: service,
      sync: sync,
      network: network,
      waitingForWifi: waitingForWifi,
      rejectedWrites: rejectedWrites,
      dataVersion: dataVersion,
      needsLocation: needsLocation,
    );
    _snap = ConnectionSnapshot(
      phase: next.phase,
      error: next.error,
      service: next.service,
      sync: next.sync,
      network: next.network,
      waitingForWifi: next.waitingForWifi,
      rejectedWrites: next.rejectedWrites,
      dataVersion: next.dataVersion,
      needsLocation: next.needsLocation,
      emergency: emergencyOf(phase: next.phase, sync: next.sync, waitingForWifi: next.waitingForWifi),
    );
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  void _bump() {
    _bumpTimer?.cancel();
    _bumpTimer = Timer(const Duration(milliseconds: 400), () => _set(dataVersion: _snap.dataVersion + 1));
  }

  Future<void> _run(bool force, bool ignoreWifi) {
    if (_busy) return _current ?? Future.value();
    final pass = _pass(force, ignoreWifi);
    _current = pass;
    return pass;
  }

  /// One sync or tick. The library *throws* `network` when no server answers: that is the offline state, not an error of
  /// the app, so it is turned into "nothing synced" and the pass goes on to read the status.
  Future<SyncReport?> _syncPass(TnService client, bool force) async {
    try {
      return force ? await client.sync() : (await client.tick()).report;
    } on TnError catch (e) {
      if (e.isOffline) return null;
      rethrow;
    }
  }

  Future<void> _pass(bool force, bool ignoreWifi) async {
    final client = _client;
    if (client == null || _busy || _stopped) return;
    _busy = true;
    try {
      // "Complete" is not forever: the server publishes new static data, so look again now and then.
      if (_staticComplete && _clock().difference(_staticCheckedAt) > _staticRecheck) _staticComplete = false;
      int? bytesPending = _staticComplete ? 0 : null;
      if (!_staticComplete) {
        try {
          bytesPending = (await client.planBootstrap()).bytesPending;
          _staticComplete = bytesPending == 0;
          _staticCheckedAt = _clock();
        } catch (_) {
          bytesPending = null; // offline or no access: the sync below reports it
        }
      }
      final allowed = ignoreWifi || shouldSync(wifiOnly: _wifiOnly, onWifi: await isOnWifi(), bytesPending: bytesPending);
      if (_stopped) return;
      _set(waitingForWifi: !allowed);
      if (allowed) {
        final report = await _syncPass(client, force);
        if (report != null && report.rejected > 0) _set(rejectedWrites: _snap.rejectedWrites + report.rejected);
        if (report != null) _set(needsLocation: report.needsLocation);
        // Screens re-read only when something changed: the library tells (dataChanged), or this pass sent something.
        if (report != null && report.submitted > 0) _bump();
      }
      final status = await (client.getSyncStatus(), client.getNetworkStatus()).wait;
      final firstReady = _snap.phase != Phase.ready;
      _set(sync: status.$1, network: status.$2, phase: Phase.ready, error: null);
      if (firstReady) _bump(); // the first successful pass: whatever it loaded is new to the screens
    } catch (e) {
      if (e is TnError && e.code == 'notConfigured') {
        _set(phase: Phase.noCredentials, error: null);
      } else {
        _set(phase: Phase.error, error: '$e');
      }
    } finally {
      _busy = false;
    }
  }
}
