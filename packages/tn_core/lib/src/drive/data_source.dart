import '../tn/service.dart';
import '../tn/types.dart';

/// What the drive session reads. The library backs it on a real drive, `sim/sim_data.dart` in the simulation.
abstract interface class DriveDataSource {
  Future<List<NearbyItem>> nearby(double lat, double lng, double radiusM);

  Future<SpeedLimitAnswer?> speedLimit(double lat, double lng, double? heading);

  /// Whether the offline data answers for this spot. "No limit shown" is only a calm "no limit on record" where this is
  /// true; where it is false the drive mode says the limit is not available here instead of staying silent.
  Future<bool> limitCovered(double lat, double lng);
}

/// Local reads only: the library answers both from its store without touching the network. The service is looked up at
/// every call: it is rebuilt when server, access or camera settings change, and a drive that is on must not keep talking
/// to a closed one.
class LibraryDataSource implements DriveDataSource {
  LibraryDataSource(this._getService);
  final TnService? Function() _getService;

  @override
  Future<List<NearbyItem>> nearby(double lat, double lng, double radiusM) async =>
      await _getService()?.getNearby(lat, lng, radiusM) ?? const [];

  @override
  Future<SpeedLimitAnswer?> speedLimit(double lat, double lng, double? heading) async =>
      _getService()?.getSpeedLimitAt(lat, lng, heading: heading);

  @override
  Future<bool> limitCovered(double lat, double lng) async {
    final service = _getService();
    if (service == null) throw StateError('no client');
    return (await service.getCoverage(lat, lng)).covered;
  }
}
