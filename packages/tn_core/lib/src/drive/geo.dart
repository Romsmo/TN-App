import 'dart:math' as math;

/// Small geodesy helpers in a local flat projection: exact enough for the few kilometres a warning looks ahead.
class LatLng {
  const LatLng(this.lat, this.lng);
  final double lat;
  final double lng;

  @override
  bool operator ==(Object other) => other is LatLng && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'LatLng($lat, $lng)';
}

/// Mean earth radius in metres (sphere).
const double earthRadiusM = 6371000;

double _rad(double d) => d * math.pi / 180;
double _deg(double r) => r * 180 / math.pi;

/// JavaScript's `Math.round`: halves go up (towards +infinity), unlike Dart's `round()`.
int jsRound(num x) => (x + 0.5).floor();

double distanceMeters(LatLng a, LatLng b) {
  final dLat = _rad(b.lat - a.lat);
  final dLng = _rad(b.lng - a.lng);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * earthRadiusM * math.asin(math.min(1.0, math.sqrt(h)));
}

/// Initial bearing from [a] to [b] in degrees, 0 = north, clockwise, [0, 360).
double bearingDegrees(LatLng a, LatLng b) {
  final y = math.sin(_rad(b.lng - a.lng)) * math.cos(_rad(b.lat));
  final x = math.cos(_rad(a.lat)) * math.sin(_rad(b.lat)) -
      math.sin(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.cos(_rad(b.lng - a.lng));
  return (_deg(math.atan2(y, x)) + 360) % 360;
}

/// Smallest absolute difference between two bearings, [0, 180].
double angleDiff(double a, double b) {
  final d = (((a - b) % 360) + 360) % 360;
  return d > 180 ? 360 - d : d;
}

/// Point [meters] away from [from] along [bearing].
LatLng destination(LatLng from, double bearing, double meters) {
  final d = meters / earthRadiusM;
  final b = _rad(bearing);
  final lat1 = _rad(from.lat);
  final lng1 = _rad(from.lng);
  final lat2 = math.asin(math.sin(lat1) * math.cos(d) + math.cos(lat1) * math.sin(d) * math.cos(b));
  final lng2 = lng1 +
      math.atan2(math.sin(b) * math.sin(d) * math.cos(lat1), math.cos(d) - math.sin(lat1) * math.sin(lat2));
  return LatLng(_deg(lat2), ((_deg(lng2) + 540) % 360) - 180);
}

/// East/north offset in metres of [p] from [origin] (equirectangular, fine for a few km).
({double x, double y}) toLocal(LatLng origin, LatLng p) => (
      x: _rad(p.lng - origin.lng) * earthRadiusM * math.cos(_rad(origin.lat)),
      y: _rad(p.lat - origin.lat) * earthRadiusM,
    );

/// Where a point lies relative to a vehicle: `along` metres in front of it (negative = behind) and `cross` metres to the side.
({double along, double cross}) alongCross(LatLng vehicle, double heading, LatLng p) {
  final l = toLocal(vehicle, p);
  final h = _rad(heading);
  final fx = math.sin(h);
  final fy = math.cos(h);
  return (along: l.x * fx + l.y * fy, cross: (l.x * fy - l.y * fx).abs());
}

/// Ray from the vehicle along [heading] against a polygon ring ([lng, lat] corners): metres to the first edge crossed,
/// 0 if inside, null if missed.
double? rayEntryDistance(LatLng vehicle, double heading, List<List<double>> ring) {
  if (ring.length < 3) return null;
  final pts = [for (final c in ring) toLocal(vehicle, LatLng(c[1], c[0]))];
  var inside = false;
  for (var i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    final a = pts[i];
    final b = pts[j];
    if ((a.y > 0) != (b.y > 0) && 0 < ((b.x - a.x) * (0 - a.y)) / (b.y - a.y) + a.x) inside = !inside;
  }
  if (inside) return 0;
  final h = _rad(heading);
  final dx = math.sin(h);
  final dy = math.cos(h);
  double? best;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % pts.length];
    final ex = b.x - a.x;
    final ey = b.y - a.y;
    final denom = dx * ey - dy * ex;
    if (denom.abs() < 1e-9) continue;
    final t = (a.x * ey - a.y * ex) / denom; // along the ray
    final u = (a.x * dy - a.y * dx) / denom; // along the edge
    if (t >= 0 && u >= 0 && u <= 1 && (best == null || t < best)) best = t;
  }
  return best;
}
