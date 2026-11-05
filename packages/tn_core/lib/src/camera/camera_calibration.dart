import 'dart:math' as math;

/// How the phone's camera sits in the car, as the sign recognition needs it.
///
/// All image coordinates are normalised (0..1) in the upright frame the preview shows, x to the right, y downwards.
/// Calibration is done once with the car standing on a straight road: the owner drags a marker onto the point where the road
/// disappears ahead (the vanishing point) and the phone's own tilt sensor gives the roll. From that:
///
/// * [vanishingX] is the direction of travel in the image; a sign's horizontal angle off it says whether it stands beside our
///   lane or on a side road;
/// * [horizonY] is the height of the horizon in the image (the vanishing point of a flat road lies on it);
/// * [rollDeg] is how far the image is turned.
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
    this.calibratedAtMs,
  });

  /// A typical horizontal field of view of a phone's main camera in landscape.
  static const double defaultHFovDeg = 65;

  /// Not calibrated yet: the image centre is straight ahead.
  static const CameraCalibration none = CameraCalibration();

  final double vanishingX;
  final double horizonY;
  final double rollDeg;
  final double hFovDeg;

  /// Width over height of the frame the detections come from.
  final double aspect;

  /// When the owner finished the calibration; null = never.
  final int? calibratedAtMs;

  bool get isCalibrated => calibratedAtMs != null;

  /// Focal length in units of the image width.
  double get _f => 0.5 / math.tan(hFovDeg * math.pi / 360);

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

  CameraCalibration copyWith({double? vanishingX, double? horizonY, double? rollDeg, double? hFovDeg, double? aspect, int? calibratedAtMs}) =>
      CameraCalibration(
        vanishingX: vanishingX ?? this.vanishingX,
        horizonY: horizonY ?? this.horizonY,
        rollDeg: rollDeg ?? this.rollDeg,
        hFovDeg: hFovDeg ?? this.hFovDeg,
        aspect: aspect ?? this.aspect,
        calibratedAtMs: calibratedAtMs ?? this.calibratedAtMs,
      );

  Map<String, Object?> toJson() => {
        'vanishingX': vanishingX,
        'horizonY': horizonY,
        'rollDeg': rollDeg,
        'hFovDeg': hFovDeg,
        'aspect': aspect,
        'calibratedAtMs': calibratedAtMs,
      };

  /// Reads stored values; anything unusable gives [none] (a calibration that cannot be trusted is no calibration).
  static CameraCalibration fromJson(Object? j) {
    if (j is! Map) return none;
    double? num_(String k, double lo, double hi) {
      final v = j[k];
      return v is num && v.isFinite && v >= lo && v <= hi ? v.toDouble() : null;
    }

    final x = num_('vanishingX', 0, 1);
    final y = num_('horizonY', 0, 1);
    final roll = num_('rollDeg', -45, 45);
    final fov = num_('hFovDeg', 30, 120);
    final aspect = num_('aspect', 0.4, 3);
    final at = j['calibratedAtMs'];
    if (x == null || y == null || roll == null || fov == null || aspect == null || at is! int) return none;
    return CameraCalibration(vanishingX: x, horizonY: y, rollDeg: roll, hFovDeg: fov, aspect: aspect, calibratedAtMs: at);
  }

  /// A reason the placement is not good enough to read signs, or null when it is fine: the horizon must lie in the middle band
  /// of the image (a camera that looks at the bonnet or at the sky sees no signs), the image must not be turned much, and the
  /// direction of travel must be near the middle.
  CalibrationProblem? get problem {
    if (rollDeg.abs() > 8) return CalibrationProblem.rolled;
    if (horizonY < 0.25) return CalibrationProblem.lookingDown;
    if (horizonY > 0.65) return CalibrationProblem.lookingUp;
    if ((vanishingX - 0.5).abs() > 0.2) return CalibrationProblem.turned;
    return null;
  }
}

/// Why a camera placement is not good enough.
enum CalibrationProblem {
  /// The horizon is high in the image: the camera looks too far down.
  lookingDown,

  /// The horizon is low in the image: the camera looks too far up.
  lookingUp,

  /// The image is turned around the viewing axis.
  rolled,

  /// The camera does not look along the road.
  turned,
}
