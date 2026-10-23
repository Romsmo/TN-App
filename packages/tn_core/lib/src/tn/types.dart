import '../drive/units.dart';

/// Shapes of what the client library returns, as documented in client-lib/docs/api.md (v1.2.x).

T? _opt<T>(Object? v) => v is T ? v : null;
double _d(Object? v) => (v as num).toDouble();
double? _od(Object? v) => v is num ? v.toDouble() : null;
int? _oi(Object? v) => v is num ? v.toInt() : null;

sealed class SpeedLimitOrigin {
  const SpeedLimitOrigin();
  factory SpeedLimitOrigin.fromJson(Object? json) {
    final m = json is Map ? json : const {};
    switch (m['kind']) {
      case 'locallyProposed':
        return LocallyProposed(_oi(m['confirmations']) ?? 0);
      case 'communityCorrected':
        return CommunityCorrected(_oi(m['confirmations']) ?? 0, m['needsReview'] == true);
      default:
        return const ImportedOrigin();
    }
  }
}

class ImportedOrigin extends SpeedLimitOrigin {
  const ImportedOrigin();
}

class LocallyProposed extends SpeedLimitOrigin {
  const LocallyProposed(this.confirmations);
  final int confirmations;
}

class CommunityCorrected extends SpeedLimitOrigin {
  const CommunityCorrected(this.confirmations, this.needsReview);
  final int confirmations;
  final bool needsReview;
}

class SpeedLimitAnswer {
  const SpeedLimitAnswer({
    required this.value,
    required this.unit,
    this.segmentId = '',
    this.segmentKey,
    this.distanceMeters = 0,
    this.origin = const ImportedOrigin(),
    this.importedValue,
  });

  final num value;
  final SpeedUnit unit;
  final String segmentId;
  final String? segmentKey;
  final double distanceMeters;
  final SpeedLimitOrigin origin;
  final num? importedValue;

  factory SpeedLimitAnswer.fromJson(Map<String, Object?> j) => SpeedLimitAnswer(
        value: j['value'] as num,
        unit: SpeedUnit.parse(j['unit']),
        segmentId: _opt<String>(j['segmentId']) ?? '',
        segmentKey: _opt<String>(j['segmentKey']),
        distanceMeters: _od(j['distanceMeters']) ?? 0,
        origin: SpeedLimitOrigin.fromJson(j['origin']),
        importedValue: _opt<num>(j['importedValue']),
      );
}

sealed class NearbyItem {
  const NearbyItem(this.id, this.distanceMeters);
  final String id;
  final double distanceMeters;

  static NearbyItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final j = json.cast<String, Object?>();
    try {
      switch (j['kind']) {
        case 'hazard':
          return HazardItem(
            id: j['id'] as String,
            hazardType: j['hazardType'] as String,
            lat: _d(j['lat']),
            lng: _d(j['lng']),
            distanceMeters: _od(j['distanceMeters']) ?? 0,
            expiresAt: _opt<String>(j['expiresAt']),
            confirmCount: _oi(j['confirmCount']) ?? 0,
            denyCount: _oi(j['denyCount']) ?? 0,
            pending: j['pending'] == true,
          );
        case 'sign':
          return SignItem(
            id: j['id'] as String,
            signType: j['signType'] as String,
            lat: _d(j['lat']),
            lng: _d(j['lng']),
            distanceMeters: _od(j['distanceMeters']) ?? 0,
          );
        case 'camera':
          return CameraItem(
            id: j['id'] as String,
            cameraType: j['cameraType'] as String,
            lat: _d(j['lat']),
            lng: _d(j['lng']),
            distanceMeters: _od(j['distanceMeters']) ?? 0,
          );
        case 'cameraZone':
          return CameraZoneItem(
            id: j['id'] as String,
            cell: _opt<String>(j['cell']) ?? '',
            resolution: _oi(j['resolution']) ?? 0,
            outline: [
              for (final c in (j['outline'] as List)) [_d((c as List)[0]), _d(c[1])],
            ],
            cameraTypes: [for (final t in (_opt<List>(j['cameraTypes']) ?? const [])) t as String],
            distanceMeters: _od(j['distanceMeters']) ?? 0,
          );
      }
    } catch (_) {
      // an unreadable item is skipped, the rest of the list is still good
    }
    return null;
  }
}

class HazardItem extends NearbyItem {
  const HazardItem({
    required String id,
    required this.hazardType,
    required this.lat,
    required this.lng,
    required double distanceMeters,
    required this.expiresAt,
    required this.confirmCount,
    required this.denyCount,
    required this.pending,
  }) : super(id, distanceMeters);
  final String hazardType;
  final double lat;
  final double lng;

  /// Null for this device's own report that has not been delivered yet.
  final String? expiresAt;
  final int confirmCount;
  final int denyCount;
  final bool pending;

  HazardItem withDistance(double meters) => HazardItem(
        id: id,
        hazardType: hazardType,
        lat: lat,
        lng: lng,
        distanceMeters: meters,
        expiresAt: expiresAt,
        confirmCount: confirmCount,
        denyCount: denyCount,
        pending: pending,
      );
}

class SignItem extends NearbyItem {
  const SignItem({required String id, required this.signType, required this.lat, required this.lng, required double distanceMeters})
      : super(id, distanceMeters);
  final String signType;
  final double lat;
  final double lng;
}

class CameraItem extends NearbyItem {
  const CameraItem({required String id, required this.cameraType, required this.lat, required this.lng, required double distanceMeters})
      : super(id, distanceMeters);
  final String cameraType;
  final double lat;
  final double lng;
}

/// An area, not a point: never draw it as a pin.
class CameraZoneItem extends NearbyItem {
  const CameraZoneItem({
    required String id,
    required this.cell,
    required this.resolution,
    required this.outline,
    required this.cameraTypes,
    required double distanceMeters,
  }) : super(id, distanceMeters);
  final String cell;
  final int resolution;

  /// `[lng, lat]` corners.
  final List<List<double>> outline;
  final List<String> cameraTypes;
}

class SyncReport {
  const SyncReport({
    this.skipped = false,
    this.ok = true,
    this.staticDataError,
    this.dynamicDataError,
    this.submitted = 0,
    this.rejected = 0,
    this.pendingWrites = 0,
    this.needsLocation = false,
  });
  final bool skipped;
  final bool ok;
  final String? staticDataError;
  final String? dynamicDataError;
  final int submitted;
  final int rejected;
  final int pendingWrites;

  /// Automatic offline area and neither a position nor a home is known: nothing was selected.
  final bool needsLocation;

  factory SyncReport.fromJson(Map<String, Object?> j) => SyncReport(
        skipped: j['skipped'] == true,
        ok: j['ok'] != false,
        staticDataError: _opt<String>(j['staticDataError']),
        dynamicDataError: _opt<String>(j['dynamicDataError']),
        submitted: _oi(j['submitted']) ?? 0,
        rejected: _oi(j['rejected']) ?? 0,
        pendingWrites: _oi(j['pendingWrites']) ?? 0,
        needsLocation: j['needsLocation'] == true,
      );
}

class TickResult {
  const TickResult({required this.synced, this.report});
  final bool synced;
  final SyncReport? report;

  factory TickResult.fromJson(Map<String, Object?> j) => TickResult(
        synced: j['synced'] == true,
        report: j['report'] is Map ? SyncReport.fromJson((j['report'] as Map).cast()) : null,
      );
}

enum Connection { never, online, offline }

class SyncStatus {
  const SyncStatus({
    required this.connection,
    this.lastSyncedAtUnixMs,
    this.pendingWrites = 0,
    this.subscribedTiles = const [],
    this.staticDataVersion,
    this.lastErrorCode,
    this.lastErrorMessage,
    this.storageBytes,
  });
  final Connection connection;

  /// The time of the last *attempt*, not of the last success.
  final int? lastSyncedAtUnixMs;
  final int pendingWrites;
  final List<String> subscribedTiles;
  final int? staticDataVersion;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final int? storageBytes;

  factory SyncStatus.fromJson(Map<String, Object?> j) => SyncStatus(
        connection: switch (j['connection']) {
          'online' => Connection.online,
          'offline' => Connection.offline,
          _ => Connection.never,
        },
        lastSyncedAtUnixMs: _oi(j['lastSyncedAtUnixMs']),
        pendingWrites: _oi(j['pendingWrites']) ?? 0,
        subscribedTiles: [for (final t in (_opt<List>(j['subscribedTiles']) ?? const [])) '$t'],
        staticDataVersion: _oi(j['staticDataVersion']),
        lastErrorCode: _opt<String>(j['lastErrorCode']),
        lastErrorMessage: _opt<String>(j['lastErrorMessage']),
        storageBytes: _oi(j['storageBytes']),
      );
}

enum NodeTier { probation, active, trusted }

class NodeView {
  const NodeView({required this.nodeId, required this.address, required this.tier, required this.backedOff});
  final String nodeId;
  final String address;
  final NodeTier tier;
  final bool backedOff;

  factory NodeView.fromJson(Map<String, Object?> j) => NodeView(
        nodeId: '${j['nodeId']}',
        address: '${j['address']}',
        tier: switch (j['tier']) {
          'trusted' => NodeTier.trusted,
          'active' => NodeTier.active,
          _ => NodeTier.probation,
        },
        backedOff: j['backedOff'] == true,
      );
}

class NetworkStatus {
  const NetworkStatus({
    this.knownNodes = const [],
    this.activeNodes = const [],
    this.currentNodes = const [],
    this.configVersion,
    this.cameraNamespaceEnabled = false,
    this.onlineNetwork,
    this.onlineEstimated,
  });
  final List<NodeView> knownNodes;
  final List<String> activeNodes;
  final List<String> currentNodes;
  final int? configVersion;
  final bool cameraNamespaceEnabled;
  final int? onlineNetwork;
  final bool? onlineEstimated;

  factory NetworkStatus.fromJson(Map<String, Object?> j) => NetworkStatus(
        knownNodes: [
          for (final n in (_opt<List>(j['knownNodes']) ?? const [])) NodeView.fromJson((n as Map).cast()),
        ],
        activeNodes: [for (final n in (_opt<List>(j['activeNodes']) ?? const [])) '$n'],
        currentNodes: [for (final n in (_opt<List>(j['currentNodes']) ?? const [])) '$n'],
        configVersion: _oi(j['configVersion']),
        cameraNamespaceEnabled: j['cameraNamespaceEnabled'] == true,
        onlineNetwork: _oi(j['onlineNetwork']),
        onlineEstimated: _opt<bool>(j['onlineEstimated']),
      );
}

class BootstrapPlan {
  const BootstrapPlan({required this.partitionsTotal, required this.partitionsPending, required this.bytesTotal, required this.bytesPending});
  final int partitionsTotal;
  final int partitionsPending;
  final int bytesTotal;
  final int bytesPending;

  factory BootstrapPlan.fromJson(Map<String, Object?> j) => BootstrapPlan(
        partitionsTotal: _oi(j['partitionsTotal']) ?? 0,
        partitionsPending: _oi(j['partitionsPending']) ?? 0,
        bytesTotal: _oi(j['bytesTotal']) ?? 0,
        bytesPending: _oi(j['bytesPending']) ?? 0,
      );
}

enum CameraLevel {
  off,
  zones,
  full;

  static CameraLevel parse(Object? v) => switch (v) {
        'full' => CameraLevel.full,
        'zones' => CameraLevel.zones,
        _ => CameraLevel.off,
      };
}

class CameraPolicy {
  const CameraPolicy({
    required this.hostEnabled,
    required this.active,
    required this.enabled,
    required this.maxLevel,
    required this.defaultLevel,
    this.zoneResolution,
    this.version,
    this.noticeVersion = '',
    this.noticeText = const {},
  });
  final bool hostEnabled;
  final bool active;
  final bool enabled;
  final CameraLevel maxLevel;
  final CameraLevel defaultLevel;
  final int? zoneResolution;
  final String? version;
  final String noticeVersion;
  final Map<String, String> noticeText;

  factory CameraPolicy.fromJson(Map<String, Object?> j) {
    final notice = j['notice'] is Map ? (j['notice'] as Map).cast<String, Object?>() : const <String, Object?>{};
    final text = notice['text'] is Map ? (notice['text'] as Map).cast<String, Object?>() : const <String, Object?>{};
    return CameraPolicy(
      hostEnabled: j['hostEnabled'] == true,
      active: j['active'] == true,
      enabled: j['enabled'] == true,
      maxLevel: CameraLevel.parse(j['maxLevel']),
      defaultLevel: CameraLevel.parse(j['defaultLevel']),
      zoneResolution: _oi(j['zoneResolution']),
      version: _opt<String>(j['version']),
      noticeVersion: '${notice['version'] ?? ''}',
      noticeText: {for (final e in text.entries) e.key: '${e.value}'},
    );
  }
}

/// Events the library emits (only the kinds the app uses are decoded).
sealed class TnEvent {
  const TnEvent();
  static TnEvent? fromJson(Map<String, Object?> j) => switch (j['type']) {
        'dataChanged' => const DataChanged(),
        'bootstrapProgress' => BootstrapProgress(_oi(j['partitionsDone']) ?? 0, _oi(j['partitionsTotal']) ?? 0),
        'syncCompleted' => const OtherEvent(),
        'syncFailed' => const OtherEvent(),
        'storageFull' => const OtherEvent(),
        _ => null,
      };
}

class DataChanged extends TnEvent {
  const DataChanged();
}

class BootstrapProgress extends TnEvent {
  const BootstrapProgress(this.partitionsDone, this.partitionsTotal);
  final int partitionsDone;
  final int partitionsTotal;
}

class OtherEvent extends TnEvent {
  const OtherEvent();
}

/// What a report may ask for as its duration, per type (`getReportLimits`; needs one successful sync).
class ReportLimits {
  const ReportLimits({required this.supported, this.defaultSeconds, this.minSeconds, this.maxSeconds});
  final bool supported;
  final int? defaultSeconds;
  final int? minSeconds;
  final int? maxSeconds;

  factory ReportLimits.fromJson(Map<String, Object?> j) => ReportLimits(
        supported: j['supported'] == true,
        defaultSeconds: _oi(j['defaultSeconds']),
        minSeconds: _oi(j['minSeconds']),
        maxSeconds: _oi(j['maxSeconds']),
      );
}

/// What `submitReport` answers.
class SubmittedReport {
  const SubmittedReport({required this.localId, this.expiresInSeconds, this.durationHonoured, this.defaultSeconds});
  final String localId;
  final int? expiresInSeconds;
  final bool? durationHonoured;
  final int? defaultSeconds;

  factory SubmittedReport.fromJson(Map<String, Object?> j) => SubmittedReport(
        localId: '${j['localId']}',
        expiresInSeconds: _oi(j['expiresInSeconds']),
        durationHonoured: _opt<bool>(j['durationHonoured']),
        defaultSeconds: _oi(j['defaultSeconds']),
      );
}

/// `lookupSpeedLimit`: always an answer, never a bare "nothing".
sealed class SpeedLimitLookup {
  const SpeedLimitLookup();
  factory SpeedLimitLookup.fromJson(Map<String, Object?> j) {
    switch (j['status']) {
      case 'found':
        return LimitFound(SpeedLimitAnswer.fromJson(j), online: j['source'] == 'online');
      case 'notRecorded':
        return const LimitNotRecorded();
      default:
        return const LimitOutsideOfflineArea();
    }
  }
}

class LimitFound extends SpeedLimitLookup {
  const LimitFound(this.answer, {required this.online});
  final SpeedLimitAnswer answer;
  final bool online;
}

class LimitNotRecorded extends SpeedLimitLookup {
  const LimitNotRecorded();
}

class LimitOutsideOfflineArea extends SpeedLimitLookup {
  const LimitOutsideOfflineArea();
}

enum CorrectionReason {
  wrongValue,
  limitLifted,
  signMissingOrNew,
  other,
  missing,
}

class Proposal {
  const Proposal({required this.value, required this.unit, required this.confirmations});
  final num value;
  final SpeedUnit unit;
  final int confirmations;

  factory Proposal.fromJson(Map<String, Object?> j) =>
      Proposal(value: (j['value'] as num?) ?? 0, unit: SpeedUnit.parse(j['unit']), confirmations: _oi(j['confirmations']) ?? 0);
}

enum OfflineMode {
  auto,
  regions,
  all;

  static OfflineMode parse(Object? v) => switch (v) {
        'regions' => OfflineMode.regions,
        'all' => OfflineMode.all,
        _ => OfflineMode.auto,
      };
}

class OfflineSettings {
  const OfflineSettings({required this.mode, required this.regions, this.home, this.maxBytes, required this.wifiOnly});
  final OfflineMode mode;
  final List<String> regions;
  final List<double>? home;
  final int? maxBytes;
  final bool wifiOnly;

  factory OfflineSettings.fromJson(Map<String, Object?> j) => OfflineSettings(
        mode: OfflineMode.parse(j['mode']),
        regions: [for (final r in (_opt<List>(j['regions']) ?? const [])) '$r'],
        home: j['home'] is List ? [for (final v in (j['home'] as List)) _d(v)] : null,
        maxBytes: _oi(j['maxBytes']),
        wifiOnly: j['wifiOnly'] == true,
      );
}

enum RegionState { none, partial, complete }

class OfflineRegion {
  const OfflineRegion({
    required this.id,
    this.country,
    this.tileCount = 0,
    this.downloadBytes = 0,
    this.sizeBytes = 0,
    this.estimatedDeviceBytes = 0,
    this.complete = true,
    this.selected = false,
    this.storedTiles = 0,
    this.state = RegionState.none,
  });
  final String id;

  /// ISO 3166-1 alpha-2, or null for a coarse area.
  final String? country;
  final int tileCount;
  final int downloadBytes;
  final int sizeBytes;
  final int estimatedDeviceBytes;

  /// false: the byte counts are lower bounds.
  final bool complete;
  final bool selected;
  final int storedTiles;
  final RegionState state;

  factory OfflineRegion.fromJson(Map<String, Object?> j) => OfflineRegion(
        id: '${j['id']}',
        country: _opt<String>(j['country']),
        tileCount: _oi(j['tileCount']) ?? 0,
        downloadBytes: _oi(j['downloadBytes']) ?? 0,
        sizeBytes: _oi(j['sizeBytes']) ?? 0,
        estimatedDeviceBytes: _oi(j['estimatedDeviceBytes']) ?? 0,
        complete: j['complete'] != false,
        selected: j['selected'] == true,
        storedTiles: _oi(j['storedTiles']) ?? 0,
        state: switch (j['state']) {
          'complete' => RegionState.complete,
          'partial' => RegionState.partial,
          _ => RegionState.none,
        },
      );
}

class StoragePlan {
  const StoragePlan({
    required this.mode,
    this.needsLocation = false,
    this.toFetchTiles = 0,
    this.toFetchBytes = 0,
    this.toRemoveTiles = 0,
    this.deferredTiles = 0,
    this.maxBytes,
    this.fits = true,
    this.storedTiles = 0,
    this.storedDeviceBytes,
  });
  final OfflineMode mode;
  final bool needsLocation;
  final int toFetchTiles;
  final int toFetchBytes;
  final int toRemoveTiles;
  final int deferredTiles;
  final int? maxBytes;
  final bool fits;
  final int storedTiles;
  final int? storedDeviceBytes;

  factory StoragePlan.fromJson(Map<String, Object?> j) => StoragePlan(
        mode: OfflineMode.parse(j['mode']),
        needsLocation: j['needsLocation'] == true,
        toFetchTiles: _oi(j['toFetchTiles']) ?? 0,
        toFetchBytes: _oi(j['toFetchBytes']) ?? 0,
        toRemoveTiles: _oi(j['toRemoveTiles']) ?? 0,
        deferredTiles: _oi(j['deferredTiles']) ?? 0,
        maxBytes: _oi(j['maxBytes']),
        fits: j['fits'] != false,
        storedTiles: _oi(j['storedTiles']) ?? 0,
        storedDeviceBytes: _oi(j['storedDeviceBytes']),
      );
}

class StorageUsage {
  const StorageUsage({this.storedTiles = 0, this.storeBytes, this.storedJsonBytes = 0, this.estimatedDeviceBytes = 0, this.maxBytes});
  final int storedTiles;
  final int? storeBytes;
  final int storedJsonBytes;
  final int estimatedDeviceBytes;
  final int? maxBytes;

  factory StorageUsage.fromJson(Map<String, Object?> j) => StorageUsage(
        storedTiles: _oi(j['storedTiles']) ?? 0,
        storeBytes: _oi(j['storeBytes']),
        storedJsonBytes: _oi(j['storedJsonBytes']) ?? 0,
        estimatedDeviceBytes: _oi(j['estimatedDeviceBytes']) ?? 0,
        maxBytes: _oi(j['maxBytes']),
      );
}

class Coverage {
  const Coverage({required this.covered, this.tile, this.usesNetwork = false});
  final bool covered;
  final String? tile;
  final bool usesNetwork;

  factory Coverage.fromJson(Map<String, Object?> j) =>
      Coverage(covered: j['covered'] == true, tile: _opt<String>(j['tile']), usesNetwork: j['usesNetwork'] == true);
}

/// Credentials the user (or the build) provides.
sealed class Credentials {
  const Credentials();
  Map<String, Object?> toJson();
}

class ClientCredentials extends Credentials {
  const ClientCredentials(this.clientId, this.clientSecret);
  final String clientId;
  final String clientSecret;
  @override
  Map<String, Object?> toJson() => {'type': 'client', 'clientId': clientId, 'clientSecret': clientSecret};
}

class AppCredentials extends Credentials {
  const AppCredentials(this.appClientId, this.appClientSecret);
  final String appClientId;
  final String appClientSecret;
  @override
  Map<String, Object?> toJson() => {'type': 'app', 'appClientId': appClientId, 'appClientSecret': appClientSecret};
}
