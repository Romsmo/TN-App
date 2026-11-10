import 'dart:math' as math;

/// How the phone's camera sits in the car, as the sign recognition needs it. Nobody sets this: [AutoCalibration] learns it while
/// driving from the signs the camera has seen (see there); until it has, the image centre is straight ahead.
///
/// All image coordinates are normalised (0..1) in the upright frame the preview shows, x to the right, y downwards.
///
/// * [vanishingX] is the direction of travel in the image; a sign's horizontal angle off it says whether it stands beside our
///   lane or on a side road;
/// * [horizonY] is the height of the horizon in the image (the vanishing point of a flat road lies on it);
/// * [rollDeg] is how far the image is turned (a mounted phone is upright: 0).
///
/// The field of view of the lens is not readable from the camera plugin, so [hFovDeg] is a typical value for a phone's main
/// camera; distances from it are estimates (see [distanceToSignM]).
class CameraCalibration {
  const CameraCalibration({
    this.vanishingX = 0.5,
    this.horizonY = 0.5,
    this.rollDeg = 0,
    this.hFovDeg = defaultHFovDeg,
    this.aspect = 16 / 9,
  });

  /// A typical field of view of a phone's main camera along the long side of its 16:9 picture.
  static const double defaultHFovDeg = 65;

  /// The image centre is straight ahead, a typical lens.
  static const CameraCalibration none = CameraCalibration();

  final double vanishingX;
  final double horizonY;
  final double rollDeg;

  /// The field of view along the long side of the picture. A phone held upright (portrait) shows the short side across: [aspect]
  /// (width over height of the upright frame the detections come from) turns this into the field of view across the frame.
  final double hFovDeg;
  final double aspect;

  /// The field of view across the upright frame, in degrees.
  double get acrossFovDeg {
    if (aspect >= 1) return hFovDeg;
    return 2 * math.atan(math.tan(hFovDeg * math.pi / 360) * aspect) * 180 / math.pi;
  }

  /// Focal length in units of the image width.
  double get _f => 0.5 / math.tan(acrossFovDeg * math.pi / 360);

  /// The focal length in units of the image width: a thing of width W metres at a distance of D metres fills W * this / D of the image.
  double get focalInImageWidths => _f;

  /// The point (x, y) with the roll taken out, as offsets from the vanishing point in units of the image width.
  ({double dx, double dy}) _level(double x, double y) {
    final p = _unrolled(x, y);
    final vp = _unrolled(vanishingX, horizonY);
    return (dx: p.dx - vp.dx, dy: p.dy - vp.dy);
  }

  /// The offset of an image point from the image centre, in units of the image width, turned back by the roll.
  ({double dx, double dy}) _unrolled(double x, double y) {
    final r = rollDeg * math.pi / 180;
    final dx = x - 0.5;
    final dy = (y - 0.5) / aspect;
    return (dx: dx * math.cos(r) + dy * math.sin(r), dy: -dx * math.sin(r) + dy * math.cos(r));
  }

  /// The angle of the image point to the right of the direction of travel, in degrees (negative = left).
  double bearingOffsetDeg(double x, double y) => math.atan(_level(x, y).dx / _f) * 180 / math.pi;

  /// The angle of the image point above the horizon, in degrees (negative = below).
  double elevationDeg(double x, double y) => -math.atan(_level(x, y).dy / _f) * 180 / math.pi;

  /// The estimated distance to a sign of [signWidthM] that fills [boxWidth] of the image width (pinhole model, sign facing us).
  /// A rough value: real signs come in several sizes (a motorway sign is twice a village one), so it is only used to place a
  /// sign within a few tens of metres and is clamped to what a camera can still read.
  double distanceToSignM(double boxWidth, {double signWidthM = defaultSignWidthM}) {
    if (boxWidth <= 0) return maxSignDistanceM;
    return (signWidthM * _f / boxWidth).clamp(minSignDistanceM, maxSignDistanceM).toDouble();
  }

  static const double defaultSignWidthM = 0.6;
  static const double minSignDistanceM = 5;
  static const double maxSignDistanceM = 120;

  CameraCalibration copyWith({double? vanishingX, double? horizonY, double? rollDeg, double? hFovDeg, double? aspect}) => CameraCalibration(
        vanishingX: vanishingX ?? this.vanishingX,
        horizonY: horizonY ?? this.horizonY,
        rollDeg: rollDeg ?? this.rollDeg,
        hFovDeg: hFovDeg ?? this.hFovDeg,
        aspect: aspect ?? this.aspect,
      );
}
