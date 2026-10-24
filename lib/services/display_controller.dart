import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tn_core/tn_core.dart';
import 'package:tn_display_protocol/tn_display_protocol.dart' as d;

import 'display_ble.dart';
import 'drive_controller.dart';
import 'stores.dart';
import 'tn_controller.dart';

/// The TN display (Bluetooth) as the app sees it: choosing a device, the connection, and feeding it from the drive mode. Lives
/// outside the widget tree. The display is optional: whatever happens here (no permission, Bluetooth off, link lost, a failing
/// write) never changes anything in the drive mode.
class DisplayController extends ChangeNotifier {
  DisplayController({
    required this.settings,
    required this.tn,
    required this.drive,
    DisplayTransport? transport,
    int Function()? nowMs,
  })  : _transport = transport,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch) {
    settings.addListener(_onSettings);
    tn.addListener(_onSettings);
    drive.phoneSoundAllowed = () => !_displayPlaysSound;
  }

  final SettingsStore settings;
  final TnController tn;
  final DriveController drive;
  final DisplayTransport? _transport;
  final int Function() _nowMs;

  DisplayLink? _link;
  Timer? _timer;
  String? _linkedId;
  String _settingsKey = '';

  /// Displays found by the last scan.
  final List<DisplayFound> found = [];
  bool scanning = false;

  /// Why the Bluetooth part cannot work right now: `unavailable` (this platform), `off` (Bluetooth switched off or no permission).
  String? problem;
  StreamSubscription<DisplayFound>? _scanSub;

  bool get supported => _transport != null;
  DisplayLinkState get state => _link?.state ?? DisplayLinkState.off;
  bool get connected => state == DisplayLinkState.ready;
  d.DeviceInfo? get info => _link?.info;
  DisplayCaps get caps => _link?.caps ?? const DisplayCaps();
  DisplayCompat? get compat => _link?.compat;
  d.DeviceSettings? get deviceSettings => _link?.deviceSettings;
  d.UiConfig? get uiConfig => _link?.uiConfig;
  int get mtu => _link?.mtu ?? 0;
  int get sentCount => _link?.sentCount ?? 0;
  DateTime? get lastSent => _link?.lastSentMs == null ? null : DateTime.fromMillisecondsSinceEpoch(_link!.lastSentMs!);
  bool get deviceBusyWithError => _link?.lastError != null;

  /// Announcements play on the display (and not on the phone) as the user chose and as the connection allows.
  bool get _displayPlaysSound => connected && switch (settings.value.displaySound) {
        DisplaySoundTarget.auto || DisplaySoundTarget.display => true,
        DisplaySoundTarget.phone || DisplaySoundTarget.both => false,
      };

  bool get _soundOnDisplay => switch (settings.value.displaySound) {
        DisplaySoundTarget.auto || DisplaySoundTarget.display || DisplaySoundTarget.both => true,
        DisplaySoundTarget.phone => false,
      };

  /// Starts the link when a display was chosen earlier (called once at app start).
  void start() => _sync();

  // ---------------------------------------------------------------------------------------------------- choosing a device

  Future<void> scan() async {
    final t = _transport;
    if (t == null || scanning) return;
    problem = null;
    found.clear();
    scanning = true;
    notifyListeners();
    try {
      if (t is UniversalBleDisplayTransport && !await t.ensureReady()) {
        problem = 'off';
        return;
      }
      _scanSub = t.scan().listen((f) {
        if (found.indexWhere((x) => x.id == f.id) < 0) {
          found.add(f);
          notifyListeners();
        }
      }, onError: (Object _) {
        problem = 'off';
        notifyListeners();
      });
      await Future<void>.delayed(const Duration(seconds: 10));
    } finally {
      await stopScan();
    }
  }

  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await _transport?.stopScan();
    } catch (_) {}
    scanning = false;
    notifyListeners();
  }

  Future<void> choose(DisplayFound f) async {
    await stopScan();
    await settings.update((s) => s.copyWith(displayEnabled: true, displayDeviceId: f.id, displayName: f.name));
  }

  /// Stops using the display and forgets the device (the pairing record of the phone, if any, stays; see the iOS Bluetooth settings).
  Future<void> forget() async {
    await settings.update((s) => s.copyWith(displayEnabled: false, displayDeviceId: null, displayName: null));
  }

  Future<void> setEnabled(bool on) => settings.update((s) => s.copyWith(displayEnabled: on));

  // ------------------------------------------------------------------------------------------------------------- the link

  void _onSettings() {
    _sync();
    notifyListeners();
  }

  void _sync() {
    final t = _transport;
    final s = settings.value;
    final want = t != null && s.displayEnabled && s.displayDeviceId != null;
    if (!want) {
      if (_link != null) unawaited(_stopLink());
      return;
    }
    if (_link == null || _linkedId != s.displayDeviceId) {
      unawaited(_startLink(s.displayDeviceId!));
      return;
    }
    final key = _keyOfSettings();
    if (key != _settingsKey) {
      _settingsKey = key;
      unawaited(_link!.pushSettings());
    }
  }

  String _keyOfSettings() {
    final s = settings.value;
    return [s.speedUnit.name, s.displaySound.name, s.displayVolume, s.displayVoice, s.warnOffCategories.join(','), s.camerasEnabled, _camerasAllowed].join('|');
  }

  bool get _camerasAllowed {
    final p = tn.policy;
    return settings.value.camerasEnabled && p != null && p.active && p.maxLevel == CameraLevel.full;
  }

  Future<void> _startLink(String id) async {
    await _stopLink();
    final t = _transport!;
    _linkedId = id;
    _settingsKey = _keyOfSettings();
    final link = DisplayLink(
      transport: t,
      input: _input,
      settings: _deviceSettings,
      nowMs: _nowMs,
      epochS: () => DateTime.now().millisecondsSinceEpoch ~/ 1000,
      tzOffsetMin: () => DateTime.now().timeZoneOffset.inMinutes,
      onAction: _onAction,
      onChange: notifyListeners,
    );
    _link = link;
    link.start(id);
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => unawaited(link.tick()));
    notifyListeners();
  }

  Future<void> _stopLink() async {
    _timer?.cancel();
    _timer = null;
    final link = _link;
    _link = null;
    _linkedId = null;
    if (link != null) await link.stop();
    notifyListeners();
  }

  d.DeviceSettings _deviceSettings(DisplayCaps caps) {
    final s = settings.value;
    return displaySettingsFor(
      soundOnDisplay: _soundOnDisplay && s.driveSound,
      voice: s.displayVoice,
      volume: s.displayVolume,
      unit: s.speedUnit,
      warnOff: s.warnOffCategories,
      camerasEnabled: _camerasAllowed,
      caps: caps,
    );
  }

  DisplayInput _input() {
    final s = settings.value;
    final snap = drive.snapshot ?? const DriveSnapshot();
    final hour = DateTime.now().hour;
    final conn = tn.snapshot.sync?.connection;
    return DisplayInput(
      snapshot: snap,
      caps: _link?.caps ?? const DisplayCaps(),
      online: conn == Connection.online,
      peers: tn.snapshot.network?.onlineNetwork ?? 0,
      nightMode: hour >= 20 || hour < 6,
      camerasEnabled: _camerasAllowed,
      soundOnDisplay: _soundOnDisplay && s.driveSound,
      voice: s.displayVoice,
      directionArrows: snap.active && snap.warnings.isEmpty,
    );
  }

  // ---------------------------------------------------------------------------------------------- what the display asks for

  void _onAction(DisplayAction a) {
    switch (a) {
      case DisplayReport(:final reportType):
        // only while a drive runs and has a recent position (the session checks that); the answer is not shown on the display
        unawaited(drive.session?.report(reportType) ?? Future<bool>.value(false));
      case DisplayConfirm(:final seen):
        unawaited(drive.session?.answerPrompt(seen) ?? Future<void>.value());
      case DisplaySettingsChanged(:final soundOn, :final useMph, :final filterBits):
        unawaited(_takeFromDevice(soundOn: soundOn, useMph: useMph, filterBits: filterBits));
      case DisplayHeartbeat():
        break;
    }
  }

  /// A change made on the display itself: the app keeps the settings, so it follows (both directions stay equal).
  Future<void> _takeFromDevice({bool? soundOn, bool? useMph, int? filterBits}) async {
    await settings.update((s) {
      var next = s;
      if (soundOn != null) next = next.copyWith(displaySound: soundOn ? DisplaySoundTarget.auto : DisplaySoundTarget.phone);
      if (useMph != null) next = next.copyWith(speedUnit: useMph ? SpeedUnit.mph : SpeedUnit.kmh);
      if (filterBits != null) {
        // only the general hazards can be taken over; the camera switch stays with the app's own rules
        final off = {...next.warnOffCategories};
        for (final category in const ['traffic', 'ice', 'accident', 'construction', 'breakdown', 'obstacle']) {
          final id = displayHazardId(category)!;
          if (filterBits & (1 << id) == 0) {
            off.add(category);
          } else {
            off.remove(category);
          }
        }
        next = next.copyWith(warnOffCategories: off.toList());
      }
      return next;
    });
  }

  @override
  void dispose() {
    settings.removeListener(_onSettings);
    tn.removeListener(_onSettings);
    _timer?.cancel();
    unawaited(_link?.stop());
    super.dispose();
  }
}
