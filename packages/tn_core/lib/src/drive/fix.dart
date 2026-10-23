import 'geo.dart';

/// A position as the drive mode uses it. [speedKmh] and [heading] are null while the receiver gives none.
class Fix {
  const Fix({required this.lat, required this.lng, this.speedKmh, this.heading, required this.t});
  final double lat;
  final double lng;
  final double? speedKmh;
  final double? heading;

  /// Milliseconds since the epoch.
  final int t;

  LatLng get point => LatLng(lat, lng);

  Fix copyWith({double? Function()? speedKmh, double? Function()? heading, int? t}) => Fix(
        lat: lat,
        lng: lng,
        speedKmh: speedKmh != null ? speedKmh() : this.speedKmh,
        heading: heading != null ? heading() : this.heading,
        t: t ?? this.t,
      );
}

/// A device position (m/s, degrees; null or invalid = unknown) as the drive's [Fix]: m/s to km/h, a missing or invalid
/// speed or heading as null.
Fix fixFromPosition({
  required double latitude,
  required double longitude,
  required double? speed,
  required double? heading,
  required int timestamp,
}) {
  return Fix(
    lat: latitude,
    lng: longitude,
    speedKmh: speed != null && speed.isFinite && speed >= 0 ? speed * 3.6 : null,
    heading: heading != null && heading.isFinite && heading >= 0 ? heading : null,
    t: timestamp,
  );
}

/// Where speed or heading are missing, they are worked out from the step to the previous position: speed from distance
/// over time (only for steps of 0.5 to 15 seconds), heading from the direction (only for a step of 3 m or more, so
/// standing still does not turn the arrow; steps within the position's own uncertainty count as standing). Values the
/// receiver did give are never replaced.
Fix deriveFix(Fix? previous, Fix fix, [double accuracyM = 0]) {
  if (previous == null) return fix;
  final seconds = (fix.t - previous.t) / 1000;
  if (seconds < 0.5 || seconds > 15) return fix;
  final meters = distanceMeters(previous.point, fix.point);
  // a step smaller than half the position's own uncertainty is noise, not movement
  final noise = accuracyM / 2 > 2 ? accuracyM / 2 : 2.0;
  final speed = fix.speedKmh ?? (meters < noise ? 0.0 : (meters / seconds) * 3.6);
  final heading = fix.heading ?? (meters >= 3 ? bearingDegrees(previous.point, fix.point) : previous.heading);
  return Fix(lat: fix.lat, lng: fix.lng, speedKmh: speed, heading: heading, t: fix.t);
}
