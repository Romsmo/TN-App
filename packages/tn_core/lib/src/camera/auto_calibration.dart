import 'camera_calibration.dart';

/// One frame of a sign's track: where the centre of its box was and how wide the box was (normalised image units).
typedef TrackPoint = ({double x, double y, double w});

/// Learns where the car is heading in the picture (and so where the horizon is) from the signs the camera sees, so nobody has to
/// align the camera.
///
/// A sign stands still at the roadside while the car drives up to it. In the picture it then moves away from one point, the
/// *vanishing point of the direction of travel*: its position is a straight line in its apparent width (a sign twice as near is
/// twice as wide and twice as far from that point). Fitting that line for a sign that was seen in several widths and following it
/// back to width zero gives the vanishing point; the median of many signs is the answer. A car that is driving a bend, a
/// lorry's sticker or anything else that does not fit a line is thrown out by the fit; the median takes care of the rest.
///
/// Until [minTracks] signs have given an answer the image centre counts as straight ahead (a phone in a holder is usually near it).
/// What is learned is kept for the app's run; a new run learns again within a few signs.
class AutoCalibration {
  AutoCalibration({this.base = CameraCalibration.none, this.minTracks = 3, this.keep = 30});

  /// What counts before anything is learned: the lens and the image centre.
  CameraCalibration base;

  /// How many signs must agree before the learned point replaces the image centre, and how many of the latest are kept.
  final int minTracks;
  final int keep;

  /// Width over height of the upright frames the detections come from (a phone held upright gives a narrow frame).
  double aspect = 16 / 9;

  final List<({double x, double y})> _estimates = [];
  double? _vx;
  double? _hy;

  /// The calibration to use now.
  CameraCalibration get current => base.copyWith(vanishingX: _vx ?? base.vanishingX, horizonY: _hy ?? base.horizonY, aspect: aspect);

  /// Whether the vanishing point is known from the road (and not only assumed in the middle).
  bool get learned => _vx != null;

  /// How many signs have given an estimate so far (up to [keep]).
  int get estimateCount => _estimates.length;

  void setAspect(double a) {
    if (a.isFinite && a > 0.3 && a < 3) aspect = a;
  }

  void reset() {
    _estimates.clear();
    _vx = null;
    _hy = null;
  }

  /// Takes a finished track of a recognised sign. Returns whether it gave an estimate.
  bool addTrack(List<TrackPoint> points) {
    final e = estimate(points);
    if (e == null) return false;
    _estimates.add(e);
    if (_estimates.length > keep) _estimates.removeAt(0);
    if (_estimates.length >= minTracks) {
      _vx = _median([for (final p in _estimates) p.x]).clamp(0.3, 0.7).toDouble();
      _hy = _median([for (final p in _estimates) p.y]).clamp(0.25, 0.7).toDouble();
    }
    return true;
  }

  /// The vanishing point one track points to, or null when the track cannot tell: too few frames, too little change of width, or
  /// a path that is not a line in the width.
  static ({double x, double y})? estimate(List<TrackPoint> points) {
    final n = points.length;
    if (n < 5) return null;
    var wMin = double.infinity, wMax = 0.0;
    for (final p in points) {
      if (p.w <= 0) return null;
      if (p.w < wMin) wMin = p.w;
      if (p.w > wMax) wMax = p.w;
    }
    if (wMax < 1.6 * wMin) return null; // it did not come near enough for the lines to meet anywhere
    final x = _intercept(points, (p) => p.x);
    final y = _intercept(points, (p) => p.y);
    if (x == null || y == null) return null;
    return (x: x, y: y);
  }

  /// The value of [pick] extrapolated to width zero by a least-squares line, or null when the line is too uncertain there.
  static double? _intercept(List<TrackPoint> pts, double Function(TrackPoint) pick) {
    final n = pts.length;
    var mw = 0.0, mv = 0.0;
    for (final p in pts) {
      mw += p.w;
      mv += pick(p);
    }
    mw /= n;
    mv /= n;
    var sww = 0.0, swv = 0.0;
    for (final p in pts) {
      sww += (p.w - mw) * (p.w - mw);
      swv += (p.w - mw) * (pick(p) - mv);
    }
    if (sww <= 0) return null;
    final b = swv / sww;
    final a = mv - b * mw;
    var rss = 0.0;
    for (final p in pts) {
      final r = pick(p) - (a + b * p.w);
      rss += r * r;
    }
    final s2 = n > 2 ? rss / (n - 2) : 0.0;
    // the standard error of the intercept: how far the answer may be off
    final seSq = s2 * (1 / n + mw * mw / sww);
    if (seSq > 0.04 * 0.04) return null;
    if (a < -0.25 || a > 1.25) return null;
    return a;
  }

  static double _median(List<double> v) {
    final s = [...v]..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }
}
