import '../../tn/types.dart';
import '../../drive/units.dart';
import '../data_source.dart';
import '../geo.dart';
import 'demo_route.dart';
import 'route.dart';

/// Speed limits along the demo route: [from metres, limit km/h].
const List<(int, int)> simLimits = [(0, 50), (1500, 100), (4500, 70)];

int simLimitAt(double distanceM) {
  var limit = simLimits.first.$2;
  for (final (from, value) in simLimits) {
    if (distanceM >= from) limit = value;
  }
  return limit;
}

/// The speed of the simulated car: just under the limit, with one stretch a little over it to show the colour change.
double simSpeedAt(double distanceM) {
  final limit = simLimitAt(distanceM);
  if (distanceM >= 2600 && distanceM < 3200) return (limit + 12).toDouble();
  return (limit - 3).toDouble();
}

/// The bundled demo route, parsed once.
final Route demoRoute = buildRoute(parseGpx(demoRouteGpx));

class _SimHazard {
  const _SimHazard(this.id, this.hazardType, this.atM);
  final String id;
  final String hazardType;
  final double atM;
}

const _simHazards = [
  _SimHazard('sim-accident', 'accident', 2300),
  _SimHazard('sim-construction', 'construction', 3900),
  _SimHazard('sim-ice', 'ice', 5600),
];

/// A camera zone across the route, only offered when the user switched cameras on (default: off, like in the real app).
const _simZone = (id: 'sim-zone', fromM: 4800.0, toM: 5200.0, halfWidthM: 250.0);

/// Synthetic, clearly marked data for the simulated drive. The route and everything on it are invented.
DriveDataSource createSimDataSource(Route route, {required bool camerasEnabled, DateTime Function()? clock}) {
  final now = (clock ?? DateTime.now)();
  final items = <NearbyItem>[
    for (final h in _simHazards)
      () {
        final p = pointAt(route, h.atM);
        return HazardItem(
          id: h.id,
          hazardType: h.hazardType,
          lat: p.lat,
          lng: p.lng,
          distanceMeters: 0,
          expiresAt: now.add(const Duration(hours: 1)).toUtc().toIso8601String(),
          confirmCount: 3,
          denyCount: 0,
          pending: false,
        );
      }(),
  ];
  if (camerasEnabled) {
    final a = pointAt(route, _simZone.fromM);
    final b = pointAt(route, _simZone.toM);
    List<double> corner(({double lat, double lng, double heading}) p, int side) {
      final q = destination(LatLng(p.lat, p.lng), (p.heading + (side > 0 ? 90 : 270)) % 360, _simZone.halfWidthM);
      return [q.lng, q.lat];
    }

    items.add(CameraZoneItem(
      id: _simZone.id,
      cell: 'sim',
      resolution: 7,
      cameraTypes: const ['mobileSpeedCamera'],
      distanceMeters: 0,
      outline: [corner(a, -1), corner(a, 1), corner(b, 1), corner(b, -1)],
    ));
  }

  double distanceAlong(double lat, double lng) {
    var best = 0.0;
    var bestD = double.infinity;
    for (var i = 0; i < route.points.length; i++) {
      final d = distanceMeters(LatLng(lat, lng), route.points[i]);
      if (d < bestD) {
        bestD = d;
        best = route.cumulative[i];
      }
    }
    return best;
  }

  return _SimDataSource(items, distanceAlong);
}

class _SimDataSource implements DriveDataSource {
  _SimDataSource(this._items, this._distanceAlong);
  final List<NearbyItem> _items;
  final double Function(double lat, double lng) _distanceAlong;

  @override
  Future<List<NearbyItem>> nearby(double lat, double lng, double radiusM) async => [
        for (final item in _items)
          if (item is HazardItem)
            if (distanceMeters(LatLng(lat, lng), LatLng(item.lat, item.lng)) <= radiusM)
              item.withDistance(distanceMeters(LatLng(lat, lng), LatLng(item.lat, item.lng)))
            else
              ...const <NearbyItem>[]
          else
            item,
      ];

  @override
  Future<bool> limitCovered(double lat, double lng) async => true;

  @override
  Future<SpeedLimitAnswer?> speedLimit(double lat, double lng, double? heading) async =>
      SpeedLimitAnswer(value: simLimitAt(_distanceAlong(lat, lng)), unit: SpeedUnit.kmh, segmentId: 'sim-segment');
}
