import 'dart:async';

import 'package:test/test.dart';
import 'package:tn_core/tn_core.dart';

import 'vec.dart';

typedef Handler = Object? Function(String method, Map<String, Object?> args);

class FakeBackend implements TnBackend {
  FakeBackend(this.handler);
  Handler handler;
  final calls = <(String, Map<String, Object?>)>[];
  final _events = StreamController<Map<String, Object?>>.broadcast();
  bool realtime = false;
  bool closed = false;

  void emit(Map<String, Object?> e) => _events.add(e);

  @override
  Future<Object?> call(String method, Map<String, Object?> args) async {
    calls.add((method, args));
    return handler(method, args);
  }

  @override
  Future<void> close() async => closed = true;

  @override
  Stream<Map<String, Object?>> get events => _events.stream;

  @override
  Future<void> startRealtime() async => realtime = true;

  @override
  Future<void> stopRealtime() async => realtime = false;
}

Map<String, Object?> status({String connection = 'online', int? version = 1, int pending = 0}) => {
      'connection': connection,
      'lastSyncedAtUnixMs': 1,
      'pendingWrites': pending,
      'subscribedTiles': <String>[],
      'staticDataVersion': version,
    };

Object? happy(String method, Map<String, Object?> args) => switch (method) {
      'planBootstrap' => {'partitionsTotal': 1, 'partitionsPending': 0, 'bytesTotal': 10, 'bytesPending': 0},
      'tick' => {'synced': true, 'report': {'skipped': false, 'ok': true, 'submitted': 0, 'rejected': 0, 'pendingWrites': 0}},
      'sync' => {'skipped': false, 'ok': true, 'submitted': 1, 'rejected': 2, 'pendingWrites': 0},
      'getSyncStatus' => status(),
      'getNetworkStatus' => {'knownNodes': [], 'activeNodes': [], 'currentNodes': [], 'cameraNamespaceEnabled': false},
      _ => null,
    };

Texts texts(String lang) => Texts(de: textTable('de'), en: textTable('en'), language: lang);

void main() {
  group('TnService', () {
    test('drops null arguments and decodes nearby items, skipping unreadable ones', () async {
      final b = FakeBackend((m, a) => {
            'items': [
              {'kind': 'hazard', 'id': 'h', 'hazardType': 'ice', 'lat': 1.0, 'lng': 2.0, 'distanceMeters': 5, 'expiresAt': null, 'confirmCount': 1, 'denyCount': 0, 'pending': true},
              {'kind': 'mystery'},
              {'kind': 'cameraZone', 'id': 'z', 'outline': [[1, 2], [3, 4], [5, 6]], 'cameraTypes': ['mobileSpeedCamera']},
            ]
          });
      final s = TnService(b);
      final items = await s.getNearby(1, 2, 3);
      expect(items.length, 2);
      expect((items.first as HazardItem).pending, true);
      expect(b.calls.single.$2.containsKey('categories'), false);
    });

    test('setStorageLimits sends a JSON null for "no limit" and nothing when unchanged', () async {
      final b = FakeBackend((m, a) => {'mode': 'auto', 'regions': [], 'maxBytes': null, 'wifiOnly': true});
      final s = TnService(b);
      await s.setStorageLimits(clearMaxBytes: true);
      expect(b.calls.last.$2, {'maxBytes': null});
      await s.setStorageLimits(wifiOnly: false);
      expect(b.calls.last.$2, {'wifiOnly': false});
      await s.setStorageLimits(maxBytes: 500);
      expect(b.calls.last.$2, {'maxBytes': 500});
    });

    test('reportSpeedLimitInterval sends the two ends and the reason', () async {
      final b = FakeBackend((m, a) => {'value': 50, 'unit': 'kmh', 'confirmations': 0});
      await TnService(b).reportSpeedLimitInterval(from: (lat: 1, lng: 2), to: (lat: 3, lng: 4), value: 50, unit: SpeedUnit.kmh);
      expect(b.calls.single.$1, 'reportSpeedLimitInterval');
      expect(b.calls.single.$2, {
        'from': {'lat': 1.0, 'lng': 2.0},
        'to': {'lat': 3.0, 'lng': 4.0},
        'value': 50,
        'unit': 'kmh',
        'reason': 'missing',
      });
    });

    test('lookupSpeedLimit: found, not recorded and outside the offline area', () async {
      final answers = [
        {'status': 'found', 'source': 'online', 'value': 50, 'unit': 'kmh', 'segmentId': 's', 'origin': {'kind': 'locallyProposed', 'confirmations': 2}},
        {'status': 'notRecorded', 'source': 'offline'},
        {'status': 'outsideOfflineArea'},
      ];
      final b = FakeBackend((m, a) => answers.removeAt(0));
      final s = TnService(b);
      final found = await s.lookupSpeedLimit(1, 2) as LimitFound;
      expect(found.online, true);
      expect(found.answer.origin, isA<LocallyProposed>());
      expect(await s.lookupSpeedLimit(1, 2), isA<LimitNotRecorded>());
      expect(await s.lookupSpeedLimit(1, 2), isA<LimitOutsideOfflineArea>());
    });
  });

  group('submitHazard', () {
    test('rejects an implausible position without calling the library', () async {
      final b = FakeBackend((m, a) => null);
      final r = await submitHazard(TnService(b), 'ice', (lat: 0, lng: 0));
      expect(r.ok, false);
      expect(r.reason, SubmitProblem.invalidPosition);
      expect(b.calls, isEmpty);
    });

    test('a default duration sends type and position only', () async {
      final b = FakeBackend((m, a) => {'localId': 'L1'});
      final r = await submitHazard(TnService(b), 'ice', (lat: 52.5, lng: 13.4));
      expect(r.ok, true);
      expect(r.localId, 'L1');
      expect(b.calls.single.$2, {'type': 'ice', 'lat': 52.5, 'lng': 13.4});
    });

    test('a custom duration is checked against the limits first', () async {
      final b = FakeBackend((m, a) => switch (m) {
            'getReportLimits' => {'supported': true, 'defaultSeconds': 7200, 'minSeconds': 600, 'maxSeconds': 3600},
            'submitReport' => {'localId': 'L2', 'durationHonoured': true},
            _ => null,
          });
      final s = TnService(b);
      final tooLong = await submitHazard(s, 'ice', (lat: 52.5, lng: 13.4), const CustomDuration(7200));
      expect(tooLong.reason, SubmitProblem.ttlOutOfRange);
      expect(tooLong.maxSeconds, 3600);
      expect(b.calls.where((c) => c.$1 == 'submitReport'), isEmpty);
      final ok = await submitHazard(s, 'ice', (lat: 52.5, lng: 13.4), const CustomDuration(1800));
      expect(ok.ok, true);
      expect(ok.durationHonoured, true);
      expect(b.calls.last.$2['ttlSeconds'], 1800);
    });

    test('limits not yet known (before the first sync) are never guessed', () async {
      final b = FakeBackend((m, a) => {'supported': false});
      final r = await submitHazard(TnService(b), 'ice', (lat: 52.5, lng: 13.4), const CustomDuration(1800));
      expect(r.reason, SubmitProblem.ttlUnsupported);
    });

    test('library errors become the matching problem', () async {
      Future<SubmitProblem?> with_(String code) async {
        final b = FakeBackend((m, a) => throw TnError(code, 'x'));
        return (await submitHazard(TnService(b), 'ice', (lat: 52.5, lng: 13.4))).reason;
      }

      expect(await with_('storageFull'), SubmitProblem.storageFull);
      expect(await with_('invalidArgument'), SubmitProblem.invalidType);
      expect(await with_('network'), SubmitProblem.failed);
    });

    test('error text names the allowed range', () {
      const f = SubmitOutcome.fail(SubmitProblem.ttlOutOfRange, minSeconds: 600, maxSeconds: 3600);
      expect(submitErrorText(texts('en'), f), contains('10 min'));
      expect(submitErrorText(texts('en'), f), contains('1 h'));
    });
  });

  group('speed limit proposals', () {
    test('roadAlreadyHasLimit and invalid values are told apart', () async {
      Future<ProposalProblem?> run(String code) async {
        final b = FakeBackend((m, a) => throw TnError(code, 'x'));
        final r = await proposeMissing(TnService(b), (lat: 1, lng: 1), (lat: 1.001, lng: 1), 50, SpeedUnit.kmh);
        return r.reason;
      }

      expect(await run('roadAlreadyHasLimit'), ProposalProblem.roadAlreadyHasLimit);
      expect(await run('invalidArgument'), ProposalProblem.invalidValue);
      expect(await run('network'), ProposalProblem.network);
      expect(await run('internal'), ProposalProblem.failed);
    });
  });

  group('TnConnection', () {
    test('an unreachable server ends in emergency noServer and recovers with the first successful sync', () async {
      var offline = true;
      final b = FakeBackend((m, a) {
        if (offline && (m == 'planBootstrap' || m == 'tick' || m == 'sync')) throw const TnError('network', 'down');
        if (m == 'getSyncStatus') return status(connection: offline ? 'offline' : 'online', version: offline ? null : 1);
        return happy(m, a);
      });
      final c = TnConnection(
        createService: () async => TnService(b),
        isOnWifi: () async => true,
        tickInterval: const Duration(hours: 1),
      );
      await c.start();
      await c.syncNow();
      expect(c.snapshot.phase, Phase.ready);
      expect(c.snapshot.emergency, Emergency.noServer);
      offline = false;
      await c.syncNow();
      expect(c.snapshot.emergency, isNull);
      await c.stop();
      expect(b.closed, true);
    });

    test('notConfigured means no credentials and emergency noAccess', () async {
      final b = FakeBackend((m, a) => throw const TnError('notConfigured', 'no access'));
      final c = TnConnection(createService: () async => TnService(b), isOnWifi: () async => true, tickInterval: const Duration(hours: 1));
      await c.start();
      await c.syncNow();
      expect(c.snapshot.phase, Phase.noCredentials);
      expect(c.snapshot.emergency, Emergency.noAccess);
      await c.stop();
    });

    test('Wi-Fi only holds the download back while there is data to load, and an explicit tap overrides it', () async {
      final b = FakeBackend((m, a) {
        if (m == 'planBootstrap') return {'partitionsTotal': 2, 'partitionsPending': 2, 'bytesTotal': 100, 'bytesPending': 100};
        return happy(m, a);
      });
      final c = TnConnection(createService: () async => TnService(b), isOnWifi: () async => false, tickInterval: const Duration(hours: 1));
      await c.start();
      await c.syncNow();
      expect(c.snapshot.waitingForWifi, true);
      expect(b.calls.where((x) => x.$1 == 'sync' || x.$1 == 'tick'), isEmpty);
      await c.syncNow(ignoreWifi: true);
      expect(c.snapshot.waitingForWifi, false);
      expect(b.calls.where((x) => x.$1 == 'sync'), isNotEmpty);
      await c.stop();
    });

    test('rejected writes are counted until the user dismisses the notice; events bump the data version', () async {
      final b = FakeBackend(happy);
      final c = TnConnection(createService: () async => TnService(b), isOnWifi: () async => true, tickInterval: const Duration(hours: 1));
      await c.start();
      await c.syncNow();
      expect(c.snapshot.rejectedWrites, 2);
      c.dismissRejected();
      expect(c.snapshot.rejectedWrites, 0);
      final before = c.snapshot.dataVersion;
      b.emit({'type': 'dataChanged', 'entityType': 'hazard', 'entityId': 'x', 'eventType': 'created'});
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(c.snapshot.dataVersion, greaterThan(before));
      await c.stop();
    });

    test('stop during creation closes the new client', () async {
      final b = FakeBackend(happy);
      final gate = Completer<TnService>();
      final c = TnConnection(createService: () => gate.future, isOnWifi: () async => true, tickInterval: const Duration(hours: 1));
      final started = c.start();
      await c.stop();
      gate.complete(TnService(b));
      await started;
      expect(b.closed, true);
    });
  });

  group('DriveHost', () {
    DriveSession session(Texts t, {bool simulated = false}) => DriveSession(DriveDeps(
          data: _EmptyData(),
          feedback: _NoFeedback(),
          texts: t,
          getSettings: () => const DriveSettings(),
          now: () => DateTime.now().millisecondsSinceEpoch,
          submitReport: (a, b) async => true,
          vote: (a, b) async => true,
          simulated: simulated,
        ));

    test('start feeds fixes to the session, stop ends everything', () async {
      final src = _FakeSource();
      final host = DriveHost(
        createSession: (sim) => session(texts('en'), simulated: sim),
        realSource: () => src,
        simSource: (n) => src,
        heartbeat: const Duration(milliseconds: 10),
      );
      await host.start(DriveMode.real);
      expect(host.isActive, true);
      src.push(const Fix(lat: 52.5, lng: 13.4, speedKmh: 50, heading: 0, t: 1));
      expect(host.snapshot!.speedKmh, 50);
      host.stop();
      expect(host.isActive, false);
      expect(src.stopped, true);
    });

    test('a start that is overtaken by a stop leaves nothing running', () async {
      final gate = Completer<void>();
      final src = _FakeSource(gate: gate);
      final host = DriveHost(
        createSession: (sim) => session(texts('en')),
        realSource: () => src,
        simSource: (n) => src,
      );
      final started = host.start(DriveMode.real);
      host.stop();
      gate.complete();
      await started;
      expect(src.stopped, true);
      expect(host.isActive, false);
    });

    test('a failed start (no permission) stops the drive and rethrows', () async {
      final src = _FakeSource(fail: true);
      final host = DriveHost(createSession: (sim) => session(texts('en')), realSource: () => src, simSource: (n) => src);
      await expectLater(host.start(DriveMode.real), throwsA(isA<LocationPermissionDenied>()));
      expect(host.isActive, false);
    });
  });

  group('location source', () {
    test('asks for permission, starts at the slow rate and speeds up with the speed, never while stopped', () async {
      final backend = _FakeLocation();
      final source = createLocationSource(backend);
      final fixes = <Fix>[];
      await source.start(fixes.add);
      expect(backend.started.single.regime, Regime.crawl);
      backend.sink!(const Fix(lat: 1, lng: 1, speedKmh: 100, heading: 0, t: 1));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(backend.started.last.regime, Regime.fast);
      source.stop();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(backend.running, false);
      expect(backend.sink, isNull);
    });

    test('permission denied throws', () async {
      final backend = _FakeLocation(allowed: false);
      await expectLater(createLocationSource(backend).start((_) {}), throwsA(isA<LocationPermissionDenied>()));
    });
  });
}

class _EmptyData implements DriveDataSource {
  @override
  Future<List<NearbyItem>> nearby(double lat, double lng, double radiusM) async => [];
  @override
  Future<SpeedLimitAnswer?> speedLimit(double lat, double lng, double? heading) async => null;
  @override
  Future<bool> limitCovered(double lat, double lng) async => true;
}

class _NoFeedback implements Feedback {
  @override
  void warn(WarnLevel level, String text, {required bool sound, required bool voice}) {}
  @override
  void confirm({required bool sound}) {}
  @override
  void prompt({required bool sound}) {}
  @override
  void silence() {}
}

class _FakeSource implements PositionSource {
  _FakeSource({this.gate, this.fail = false});
  final Completer<void>? gate;
  final bool fail;
  bool stopped = false;
  void Function(Fix)? _on;

  void push(Fix f) => _on?.call(f);

  @override
  Future<void> start(void Function(Fix fix) onFix) async {
    _on = onFix;
    if (fail) throw const LocationPermissionDenied();
    await gate?.future;
  }

  @override
  void stop() => stopped = true;
}

class _FakeLocation implements LocationBackend {
  _FakeLocation({this.allowed = true});
  final bool allowed;
  final started = <Sampling>[];
  bool running = false;
  void Function(Fix)? sink;

  @override
  Future<bool> requestPermission() async => allowed;

  @override
  void setSink(void Function(Fix fix)? s) => sink = s;

  @override
  Future<void> start(Sampling sampling) async {
    started.add(sampling);
    running = true;
  }

  @override
  Future<void> stop() async => running = false;
}
