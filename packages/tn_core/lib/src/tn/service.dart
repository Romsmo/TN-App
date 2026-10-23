import 'dart:async';

import '../drive/units.dart';
import 'types.dart';

/// The part of the library's client the app uses. The native client implements it (see the app's `LibraryBackend`);
/// tests use a fake.
abstract interface class TnBackend {
  /// Runs an API method by name. The result is the decoded `ok` payload; a library error is thrown as [TnError].
  Future<Object?> call(String method, Map<String, Object?> args);

  Future<void> startRealtime();
  Future<void> stopRealtime();

  /// Events as the library emits them (decoded JSON objects).
  Stream<Map<String, Object?>> get events;

  Future<void> close();
}

/// A failure answered by the library or an unusable answer. [code] is one of the API's error codes
/// (`invalidArgument, notConfigured, notOffered, unknownSegment, storageFull, storage, network, auth, rejected,
/// unavailable, ttlOutOfRange, roadAlreadyHasLimit, closed, internal`) or `badResponse`.
class TnError implements Exception {
  const TnError(this.code, this.message);
  final String code;
  final String message;

  bool get isOffline => code == 'network' || code == 'unavailable';

  @override
  String toString() => 'TnError($code): $message';
}

Map<String, Object?> _obj(Object? v) {
  if (v is Map) return v.cast<String, Object?>();
  throw const TnError('badResponse', 'The library answered with something unexpected.');
}

/// Typed access to the library. Knows method names and argument shapes (api.md), nothing about the UI.
class TnService {
  TnService(this._backend);
  final TnBackend _backend;
  StreamSubscription<Map<String, Object?>>? _eventSub;

  Future<Object?> _call(String method, [Map<String, Object?> args = const {}]) {
    // keys with null values are left out: the library treats a missing key as "not given"
    final clean = {for (final e in args.entries) if (e.value != null) e.key: e.value};
    return _backend.call(method, clean);
  }

  Future<List<NearbyItem>> getNearby(double lat, double lng, double radiusMeters, {List<String>? categories}) async {
    final r = _obj(await _call('getNearby', {'lat': lat, 'lng': lng, 'radiusMeters': radiusMeters, 'categories': categories}));
    return [
      for (final i in (r['items'] as List? ?? const [])) ...[
        if (NearbyItem.fromJson(i) case final item?) item,
      ],
    ];
  }

  Future<SpeedLimitAnswer?> getSpeedLimitAt(double lat, double lng, {double? heading}) async {
    final r = await _call('getSpeedLimitAt', {'lat': lat, 'lng': lng, 'heading': heading});
    return r == null ? null : SpeedLimitAnswer.fromJson(_obj(r));
  }

  Future<({List<String> tiles, bool changed})> updatePosition(double lat, double lng, {double? speedKmh}) async {
    final r = _obj(await _call('updatePosition', {'lat': lat, 'lng': lng, 'speedKmh': speedKmh}));
    return (tiles: [for (final t in (r['tiles'] as List? ?? const [])) '$t'], changed: r['changed'] == true);
  }

  Future<SyncReport> sync() async => SyncReport.fromJson(_obj(await _call('sync')));

  Future<TickResult> tick() async => TickResult.fromJson(_obj(await _call('tick')));

  Future<BootstrapPlan> planBootstrap() async => BootstrapPlan.fromJson(_obj(await _call('planBootstrap')));

  Future<SyncStatus> getSyncStatus() async => SyncStatus.fromJson(_obj(await _call('getSyncStatus')));

  Future<NetworkStatus> getNetworkStatus() async => NetworkStatus.fromJson(_obj(await _call('getNetworkStatus')));

  Future<CameraPolicy> getCameraPolicy() async => CameraPolicy.fromJson(_obj(await _call('getCameraPolicy')));

  /// Stores a report locally (queue) and returns its local id; it is sent with the next sync.
  Future<String> submitReport(String type, double lat, double lng) async =>
      (await submitReportFor(type, lat, lng)).localId;

  /// The same with a duration the reporter chose ([ttlSeconds], within [getReportLimits]). Out of range is
  /// `ttlOutOfRange` and nothing is queued. `durationHonoured: false` means the server ignored the request.
  Future<SubmittedReport> submitReportFor(String type, double lat, double lng, {int? ttlSeconds}) async =>
      SubmittedReport.fromJson(_obj(await _call('submitReport', {'type': type, 'lat': lat, 'lng': lng, 'ttlSeconds': ttlSeconds})));

  /// Default, shortest and longest duration for a type (needs one successful sync).
  Future<ReportLimits> getReportLimits(String type) async =>
      ReportLimits.fromJson(_obj(await _call('getReportLimits', {'type': type})));

  /// The limit at a spot, with the honest third answer "outside the offline area" instead of a silent "none".
  Future<SpeedLimitLookup> lookupSpeedLimit(double lat, double lng, {double? heading}) async =>
      SpeedLimitLookup.fromJson(_obj(await _call('lookupSpeedLimit', {'lat': lat, 'lng': lng, 'heading': heading})));

  /// "That limit is wrong": proposes another value for a road that has one.
  Future<Proposal> reportWrongSpeedLimit({
    required double lat,
    required double lng,
    required int proposedValue,
    required SpeedUnit unit,
    CorrectionReason reason = CorrectionReason.wrongValue,
  }) async =>
      Proposal.fromJson(_obj(await _call('reportWrongSpeedLimit', {
        'lat': lat,
        'lng': lng,
        'proposedValue': proposedValue,
        'unit': unit.wire,
        'reason': reason.name,
      })));

  /// "No limit on record here": proposes a value for the stretch of road between two points. The library's successor of
  /// `reportMissingSpeedLimit` (`roadAlreadyHasLimit` if the stretch has a limit already).
  Future<Proposal> reportSpeedLimitInterval({
    required ({double lat, double lng}) from,
    required ({double lat, double lng}) to,
    required int value,
    required SpeedUnit unit,
    CorrectionReason reason = CorrectionReason.missing,
  }) async =>
      Proposal.fromJson(_obj(await _call('reportSpeedLimitInterval', {
        'from': {'lat': from.lat, 'lng': from.lng},
        'to': {'lat': to.lat, 'lng': to.lng},
        'value': value,
        'unit': unit.wire,
        'reason': reason.name,
      })));

  /// A preview of the stretch of road between two points (needs the network).
  Future<Map<String, Object?>> resolveRoadInterval(({double lat, double lng}) from, ({double lat, double lng}) to) async =>
      _obj(await _call('resolveRoadInterval', {
        'from': {'lat': from.lat, 'lng': from.lng},
        'to': {'lat': to.lat, 'lng': to.lng},
      }));

  Future<OfflineSettings> getOfflineSettings() async => OfflineSettings.fromJson(_obj(await _call('getOfflineSettings')));

  /// Chooses what is kept of the static data; applied with the next sync. [regions] without a mode switches to `regions`.
  Future<OfflineSettings> setOfflineRegions({OfflineMode? mode, List<String>? regions}) async =>
      OfflineSettings.fromJson(_obj(await _call('setOfflineRegions', {'mode': mode?.name, 'regions': regions})));

  /// [maxBytes] null removes the limit when [clearMaxBytes] is set, leaving it out keeps the limit as it is.
  Future<OfflineSettings> setStorageLimits({int? maxBytes, bool clearMaxBytes = false, bool? wifiOnly}) async {
    final args = <String, Object?>{if (wifiOnly != null) 'wifiOnly': wifiOnly};
    if (clearMaxBytes) {
      args['maxBytes'] = null;
    } else if (maxBytes != null) {
      args['maxBytes'] = maxBytes;
    }
    // a JSON null must reach the library here (it means "no limit"), so this call does not drop null values
    return OfflineSettings.fromJson(_obj(await _backend.call('setStorageLimits', args)));
  }

  Future<List<OfflineRegion>> listOfflineRegions() async {
    final r = _obj(await _call('listOfflineRegions'));
    return [for (final x in (r['regions'] as List? ?? const [])) OfflineRegion.fromJson((x as Map).cast())];
  }

  Future<StoragePlan> getStoragePlan() async => StoragePlan.fromJson(_obj(await _call('getStoragePlan')));

  Future<StorageUsage> getStorageUsage() async => StorageUsage.fromJson(_obj(await _call('getStorageUsage')));

  Future<Coverage> getCoverage(double lat, double lng) async =>
      Coverage.fromJson(_obj(await _call('getCoverage', {'lat': lat, 'lng': lng})));

  /// Votes on a report: still there ([stillThere] true) or gone. Queued like every write.
  Future<String> confirmReport(String reportId, bool stillThere) async =>
      '${_obj(await _call('confirmReport', {'reportId': reportId, 'stillThere': stillThere}))['localId']}';

  /// "This device is gone": the one vote that exists for permanently installed cameras. Queued like every write.
  Future<String> reportCameraRemoved(String cameraId) async =>
      '${_obj(await _call('reportCameraRemoved', {'cameraId': cameraId}))['localId']}';

  /// The version of the client library (for the info page), or null where the library does not say.
  Future<String?> libraryVersion() async {
    final r = _obj(await _call('version'));
    final v = r['libraryVersion'];
    return v is String ? v : null;
  }

  Future<void> startRealtime() => _backend.startRealtime();

  /// Calls [onEvent] for every event; an unreadable event is ignored, the next sync catches up.
  void onEvents(void Function(TnEvent event) onEvent) {
    _eventSub?.cancel();
    _eventSub = _backend.events.listen((json) {
      try {
        final e = TnEvent.fromJson(json);
        if (e != null) onEvent(e);
      } catch (_) {
        // ignored
      }
    }, onError: (_) {});
  }

  Future<void> close() async {
    await _eventSub?.cancel();
    _eventSub = null;
    try {
      await _backend.stopRealtime();
    } catch (_) {
      // closing must not fail
    }
    await _backend.close();
  }
}
