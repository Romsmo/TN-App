import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:tn_core/tn_core.dart';

/// The device side of the location updates for the drive mode: "While using the app" permission only (never "Always"),
/// background updates only while the drive mode runs (iOS: the blue status indicator; Android: a foreground service with a
/// notification), accuracy and rate set by the speed (`Sampling`).
class GeolocatorBackend implements LocationBackend {
  GeolocatorBackend({required this.notificationTitle, required this.notificationText});

  final String Function() notificationTitle;
  final String Function() notificationText;

  StreamSubscription<geo.Position>? _sub;
  void Function(Fix fix)? _sink;

  @override
  void setSink(void Function(Fix fix)? sink) => _sink = sink;

  @override
  Future<bool> requestPermission() => requestLocationPermission();

  geo.LocationAccuracy _accuracy(LocationAccuracy a) => switch (a) {
        LocationAccuracy.balanced => geo.LocationAccuracy.medium,
        LocationAccuracy.high => geo.LocationAccuracy.high,
        LocationAccuracy.navigation => geo.LocationAccuracy.bestForNavigation,
      };

  geo.LocationSettings _settings(Sampling s) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return geo.AndroidSettings(
          accuracy: _accuracy(s.accuracy),
          distanceFilter: s.distanceIntervalM,
          intervalDuration: Duration(milliseconds: s.timeIntervalMs),
          foregroundNotificationConfig: geo.ForegroundNotificationConfig(
            notificationTitle: notificationTitle(),
            notificationText: notificationText(),
            enableWakeLock: true,
            setOngoing: true,
          ),
        );
      case TargetPlatform.iOS:
        return geo.AppleSettings(
          accuracy: _accuracy(s.accuracy),
          activityType: geo.ActivityType.automotiveNavigation,
          distanceFilter: s.distanceIntervalM,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
          allowBackgroundLocationUpdates: true,
        );
      default:
        return geo.LocationSettings(accuracy: _accuracy(s.accuracy), distanceFilter: s.distanceIntervalM);
    }
  }

  @override
  Future<void> start(Sampling sampling) async {
    await _sub?.cancel();
    _sub = geo.Geolocator.getPositionStream(locationSettings: _settings(sampling)).listen(
      (p) => _sink?.call(positionToFix(p)),
      onError: (_) {},
    );
  }

  @override
  Future<void> stop() async {
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
  }
}

/// A device position as the drive's [Fix]: m/s to km/h, an invalid speed or heading as null.
Fix positionToFix(geo.Position p) => fixFromPosition(
      latitude: p.latitude,
      longitude: p.longitude,
      speed: p.speed,
      heading: p.heading,
      timestamp: p.timestamp.millisecondsSinceEpoch,
    );

/// Asks for the location permission "While using the app". False if it is refused or the location service is off.
Future<bool> requestLocationPermission() async {
  try {
    if (!await geo.Geolocator.isLocationServiceEnabled()) return false;
    var permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }
    return permission == geo.LocationPermission.whileInUse || permission == geo.LocationPermission.always;
  } catch (_) {
    return false;
  }
}

/// The device position for the map while it is visible: a stream of fixes (speed and heading derived from consecutive
/// positions where the receiver gives none) plus the accuracy of the last one. Starts only with the permission; a refusal
/// is not an error here, the map simply shows no position.
class DevicePosition extends ChangeNotifier {
  Fix? _fix;
  double _accuracyM = 0;
  StreamSubscription<geo.Position>? _sub;
  bool _active = false;

  Fix? get fix => _fix;
  double get accuracyM => _accuracyM;
  bool get hasPermissionAndStream => _active;

  /// Starts (once) reading the position if the permission is there; with [ask] the system dialog may appear.
  Future<bool> start({bool ask = false}) async {
    if (_active) return true;
    try {
      if (!await geo.Geolocator.isLocationServiceEnabled()) return false;
      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied && ask) {
        permission = await geo.Geolocator.requestPermission();
      }
      if (permission != geo.LocationPermission.whileInUse && permission != geo.LocationPermission.always) return false;
      _active = true;
      _sub = geo.Geolocator.getPositionStream(
        locationSettings: const geo.LocationSettings(accuracy: geo.LocationAccuracy.medium, distanceFilter: 5),
      ).listen((p) {
        final next = deriveFix(_fix, positionToFix(p), p.accuracy);
        _fix = next;
        _accuracyM = p.accuracy;
        notifyListeners();
      }, onError: (_) {});
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    _active = false;
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
