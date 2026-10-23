import '../fix.dart';
import '../geo.dart';

/// Track points of a GPX document (`<trkpt lat=".." lon="..">`), in file order. Anything unreadable is skipped.
List<LatLng> parseGpx(String xml) {
  final points = <LatLng>[];
  final tag = RegExp(r'<trkpt\b([^>]*)>');
  for (final m in tag.allMatches(xml)) {
    final attrs = m.group(1) ?? '';
    final lat = RegExp(r'\blat\s*=\s*"([^"]+)"').firstMatch(attrs)?.group(1);
    final lng = RegExp(r'\blon\s*=\s*"([^"]+)"').firstMatch(attrs)?.group(1);
    if (lat == null || lng == null) continue;
    final la = double.tryParse(lat);
    final lo = double.tryParse(lng);
    if (la != null && lo != null && la.isFinite && lo.isFinite && la.abs() <= 90 && lo.abs() <= 180) {
      points.add(LatLng(la, lo));
    }
  }
  return points;
}

class Route {
  Route(this.points, this.cumulative, this.lengthM);
  final List<LatLng> points;

  /// Cumulative distance of each point from the start, metres.
  final List<double> cumulative;
  final double lengthM;
}

Route buildRoute(List<LatLng> points) {
  final cumulative = <double>[0];
  for (var i = 1; i < points.length; i++) {
    cumulative.add(cumulative[i - 1] + distanceMeters(points[i - 1], points[i]));
  }
  return Route(points, cumulative, cumulative.isEmpty ? 0 : cumulative.last);
}

/// Position and heading at [distanceM] along the route (clamped to its ends).
({double lat, double lng, double heading}) pointAt(Route route, double distanceM) {
  final d = distanceM < 0 ? 0.0 : (distanceM > route.lengthM ? route.lengthM : distanceM);
  var i = 1;
  while (i < route.points.length - 1 && route.cumulative[i] < d) {
    i++;
  }
  final a = route.points[i - 1];
  final b = route.points[i];
  final segLen = route.cumulative[i] - route.cumulative[i - 1];
  final heading = bearingDegrees(a, b);
  final into = d - route.cumulative[i - 1];
  final p = segLen > 0 ? destination(a, heading, into) : a;
  return (lat: p.lat, lng: p.lng, heading: heading);
}

/// Plays a route as GPS fixes, one per [stepMs], at the speed the profile gives for the distance driven so far.
/// No real movement, no real sensor: the simulated drive feeds the same pipeline as a real one.
class RoutePlayer {
  RoutePlayer(this.route, this.speedKmhAt, int startMs, {this.stepMs = 1000}) : _t = startMs;
  final Route route;
  final double Function(double distanceM) speedKmhAt;
  final int stepMs;
  double _distance = 0;
  int _t;

  bool get finished => _distance >= route.lengthM;

  double get progress => route.lengthM == 0 ? 1 : (_distance / route.lengthM).clamp(0.0, 1.0);

  /// The next fix, or null when the end of the route is reached.
  Fix? next() {
    if (finished) return null;
    final speed = speedKmhAt(_distance);
    final p = pointAt(route, _distance);
    final fix = Fix(lat: p.lat, lng: p.lng, speedKmh: speed, heading: p.heading, t: _t);
    _distance += (speed / 3.6) * (stepMs / 1000);
    _t += stepMs;
    return fix;
  }
}
