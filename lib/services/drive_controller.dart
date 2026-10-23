import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tn_core/tn_core.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../platform/platform.dart';
import 'feedback.dart';
import 'location.dart';
import 'stores.dart';
import 'tn_controller.dart';

/// The app's drive mode: wires [DriveHost] to the library, the device location, tones, speech and the settings. Lives
/// outside the widget tree, so the drive (and its lock) survives screen changes.
class DriveController extends ChangeNotifier {
  DriveController({required this.tn, required this.settings, required this.texts}) {
    _feedback = DeviceFeedback(language: () => texts.language);
    _backend = GeolocatorBackend(
      notificationTitle: () => texts.t('drive.notification.title'),
      notificationText: () => texts.t('drive.notification.body'),
    );
    _host = DriveHost(
      createSession: _createSession,
      realSource: () => _TileFeed(createLocationSource(_backend), () => tn.service),
      simSource: (speedup) => createSimSource(speedup, onFinished: () => _finished = true),
    );
    _host.subscribe(_onHost);
    settings.addListener(_onSettings);
  }

  final TnController tn;
  final SettingsStore settings;
  final Texts texts;

  late final DeviceFeedback _feedback;
  late final GeolocatorBackend _backend;
  late final DriveHost _host;
  bool _finished = false;
  bool _wake = false;

  DriveSnapshot? get snapshot => _host.snapshot;

  bool get isActive => _host.isActive;

  DriveSession? get session => _host.current;

  /// The simulated route has been driven to its end.
  bool get simulationFinished => _finished;

  /// Whether settings, text input and server pages are locked right now: a drive is on, the lock setting is on, and the
  /// car is moving. The setting is read live, so switching the lock on again takes effect at once.
  bool get lockActive => isLockActive(
        driving: snapshot?.active == true,
        lockEnabled: settings.value.driveLockEnabled,
        locked: snapshot?.speedLocked == true,
      );

  DriveSettings _driveSettings() {
    final s = settings.value;
    return DriveSettings(
      unit: s.speedUnit,
      sound: s.driveSound,
      voice: s.driveVoice,
      warnOff: s.warnOffCategories,
      scale: s.warnScale,
      lockEnabled: s.driveLockEnabled,
    );
  }

  DriveSession _createSession(bool simulated) {
    final DriveDataSource data = simulated
        ? createSimDataSource(demoRoute, camerasEnabled: settings.value.camerasEnabled)
        : LibraryDataSource(() => tn.service);
    return DriveSession(DriveDeps(
      data: data,
      feedback: _feedback,
      texts: texts,
      getSettings: _driveSettings,
      now: () => DateTime.now().millisecondsSinceEpoch,
      simulated: simulated,
      // A simulated drive must never put invented reports or votes into the real queue.
      submitReport: (type, position) async {
        if (simulated) return true;
        final s = tn.service;
        return s != null && (await submitHazard(s, type, position)).ok;
      },
      vote: (reportId, stillThere) async {
        if (simulated) return true;
        final s = tn.service;
        return s != null && (await voteOnReport(s, reportId, stillThere)).ok;
      },
    ));
  }

  void _onHost() {
    _syncWakeLock();
    notifyListeners();
  }

  void _onSettings() => notifyListeners(); // the lock setting is read live

  /// Keeps the screen on while the drive mode runs.
  void _syncWakeLock() {
    final want = isActive;
    if (want == _wake) return;
    _wake = want;
    try {
      want ? WakelockPlus.enable() : WakelockPlus.disable();
    } catch (_) {}
  }

  /// Starts a drive. A refused location permission throws [LocationPermissionDenied] (nothing is left running).
  Future<void> start(DriveMode mode, {int speedup = 1}) async {
    _finished = false;
    await _host.start(mode, speedup: speedup);
  }

  void stop() => _host.stop();

  @override
  void dispose() {
    settings.removeListener(_onSettings);
    _host.stop();
    _feedback.dispose();
    super.dispose();
  }
}

/// Whether the platform can run a real drive with the location updates (iOS and Android).
bool get canDriveForReal => isMobile;


/// Decision (docs/decisions.md, D-N1): a real drive hands its position to the library's `updatePosition`, so the library
/// keeps the tiles around the drive subscribed and the automatic offline area follows a long trip. What leaves the device
/// is the coarse tile (H3 resolution 7, about 2.4 km), not a coordinate. Switch off with `--dart-define=DRIVE_FEEDS_TILES=false`.
const bool driveFeedsTiles = bool.fromEnvironment('DRIVE_FEEDS_TILES', defaultValue: true);

class _TileFeed implements PositionSource {
  _TileFeed(this._inner, this._service);
  final PositionSource _inner;
  final TnService? Function() _service;
  ({double lat, double lng, int at})? _last;

  @override
  Future<void> start(void Function(Fix fix) onFix) => _inner.start((fix) {
        onFix(fix);
        if (!driveFeedsTiles) return;
        final service = _service();
        if (service == null) return;
        final last = _last;
        // at most once a minute, or after 500 m: the library only needs to follow the drive, not every fix
        if (last != null && fix.t - last.at < 60000 && distanceMeters(LatLng(last.lat, last.lng), fix.point) < 500) return;
        _last = (lat: fix.lat, lng: fix.lng, at: fix.t);
        service.updatePosition(fix.lat, fix.lng, speedKmh: fix.speedKmh).then<void>((_) {}, onError: (Object _) {});
      });

  @override
  void stop() {
    _last = null;
    _inner.stop();
  }
}
