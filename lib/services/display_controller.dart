import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tn_core/tn_core.dart';
import 'package:tn_display_protocol/tn_display_protocol.dart' as d;
import 'package:wakelock_plus/wakelock_plus.dart';

import 'display_ble.dart';
import 'display_update_source.dart';
import 'drive_controller.dart';
import 'stores.dart';
import 'tn_controller.dart';

/// Where the firmware update stands (for the Display page).
enum DisplayUpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  needsIntermediate,
  appTooOld,
  notPossible,

  /// The release source cannot be read (not published, or the repository is private).
  sourceUnavailable,

  /// No connection to the release source.
  offline,
  badRelease,

  /// The signature of the release is wrong or from a key the app does not trust: nothing is installed.
  badSignature,
  downloading,
  installing,
  verifying,
  success,
  failed,
}

/// State of copying the sounds to the display's card.
enum DisplayPackPhase { idle, uploading, done, failed, cancelled }

/// The TN display (Bluetooth) as the app sees it: choosing a device, the connection, feeding it from the drive mode and updating
/// its firmware. Lives outside the widget tree. **The whole feature is off until the user switches it on in the settings**
/// (`displayFeature`): until then nothing of it is visible and Bluetooth is not touched. The display is optional: whatever happens
/// here (no permission, Bluetooth off, link lost, a failing write, a failed update) never changes anything in the drive mode.
class DisplayController extends ChangeNotifier {
  DisplayController({
    required this.settings,
    required this.tn,
    required this.drive,
    DisplayTransport? transport,
    DisplayUpdateSource? updates,
    int Function()? nowMs,
  })  : _transport = transport,
        _updates = updates,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch) {
    settings.addListener(_onSettings);
    tn.addListener(_onSettings);
    drive.phoneSoundAllowed = () => !_displayPlaysSound;
  }

  final SettingsStore settings;
  final TnController tn;
  final DriveController drive;
  final DisplayTransport? _transport;
  final DisplayUpdateSource? _updates;
  final int Function() _nowMs;

  DisplayLink? _link;
  Timer? _timer;
  String? _linkedId;
  String _settingsKey = '';
  DisplayLinkState _lastState = DisplayLinkState.off;

  /// Displays found by the last scan.
  final List<DisplayFound> found = [];
  bool scanning = false;

  /// Why the Bluetooth part cannot work right now: `off` (Bluetooth switched off or not allowed).
  String? problem;
  StreamSubscription<DisplayFound>? _scanSub;

  // ---------------------------------------------------------------------------------------------------------- the update

  DisplayUpdatePhase updatePhase = DisplayUpdatePhase.idle;
  DisplayManifest? manifest;

  /// What the signature of the shown release says (valid, missing = unsigned, ...).
  SignatureStatus signature = SignatureStatus.missing;

  /// 0..1 while downloading and installing.
  double updateProgress = 0;

  /// The OTA error code of the display (1..5) when an update failed on the display's side.
  int? updateErrorCode;
  bool _cancelUpdate = false;

  // ------------------------------------------------------------------------------------------- sounds for the card

  DisplayPackPhase packPhase = DisplayPackPhase.idle;
  double packProgress = 0;
  String? packFailedPath;

  /// Which clips of [displayAudioFiles] this app carries (loaded on demand; the voice clips only when they were added to the build).
  List<DisplayFile>? _pack;
  int get packFiles => _pack?.length ?? 0;
  int get packVoiceFiles => _pack?.where((f) => f.path.startsWith('audio/voice/')).length ?? 0;
  bool _cancelPack = false;

  /// Whether the whole display feature is switched on in the settings.
  bool get featureOn => settings.value.displayFeature;
  bool get supported => _transport != null;
  bool get canUpdate => _updates != null;
  DisplayLinkState get state => _link?.state ?? DisplayLinkState.off;
  bool get connected => state == DisplayLinkState.ready;
  d.DeviceInfo? get info => _link?.info;
  DisplayCaps get caps => _link?.caps ?? const DisplayCaps();
  DisplayCompat? get compat => _link?.compat;
  d.DeviceSettings? get deviceSettings => _link?.deviceSettings;
  int get mtu => _link?.mtu ?? 0;

  /// Connect attempts in a row that failed while the display is meant to be connected.
  int get failedAttempts => _link?.failedAttempts ?? 0;
  int get sentCount => _link?.sentCount ?? 0;
  DateTime? get lastSent => _link?.lastSentMs == null ? null : DateTime.fromMillisecondsSinceEpoch(_link!.lastSentMs!);

  /// A one-word summary for the settings row and the drive screen: `off`, `connecting`, `ready`, `incompatible`, or `none` when no
  /// display was chosen yet.
  String get summary {
    final s = settings.value;
    if (!s.displayFeature) return 'off';
    if (s.displayDeviceId == null) return 'none';
    if (!s.displayEnabled) return 'paused';
    return switch (state) {
      DisplayLinkState.ready => 'ready',
      DisplayLinkState.incompatible => 'incompatible',
      _ => 'connecting',
    };
  }

  /// An update is known and can be installed (the badge on the Display row).
  bool get updateAvailable => updatePhase == DisplayUpdatePhase.available;

  /// Announcements play on the display (and not on the phone) as the user chose and as the connection allows.
  bool get _displayPlaysSound =>
      settings.value.displayFeature &&
      connected &&
      switch (settings.value.displaySound) {
        DisplaySoundTarget.auto || DisplaySoundTarget.display => true,
        DisplaySoundTarget.phone || DisplaySoundTarget.both => false,
      };

  bool get _soundOnDisplay => switch (settings.value.displaySound) {
        DisplaySoundTarget.auto || DisplaySoundTarget.display || DisplaySoundTarget.both => true,
        DisplaySoundTarget.phone => false,
      };

  /// Starts the link when the feature is on and a display was chosen earlier (called once at app start).
  void start() => _sync();

  // ---------------------------------------------------------------------------------------------------- choosing a device

  Future<void> scan() async {
    final t = _transport;
    if (t == null || scanning || !featureOn) return;
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

  /// Stops using the display and forgets the device (the pairing record of the phone, if any, stays; see the Bluetooth settings).
  Future<void> forget() async {
    updatePhase = DisplayUpdatePhase.idle;
    manifest = null;
    await settings.update((s) => s.copyWith(displayEnabled: false, displayDeviceId: null, displayName: null));
  }

  Future<void> setEnabled(bool on) => settings.update((s) => s.copyWith(displayEnabled: on));

  /// Reads the bundled sound files (once). A file that is missing or not in the display's WAV format is left out.
  Future<void> loadPack() async {
    if (_pack != null) return;
    final files = <DisplayFile>[];
    for (final path in displayAudioFiles) {
      try {
        final data = await rootBundle.load('assets/display_audio/$path');
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        if (isDisplayWav(bytes)) files.add(DisplayFile(path, bytes));
      } catch (_) {}
    }
    _pack = files;
    notifyListeners();
  }

  /// Why the sounds cannot be copied right now, or null.
  String? get packBlocker {
    if (!connected) return 'notConnected';
    if (!caps.sd) return 'noCard';
    if (drive.isActive) return 'driving';
    if (packFiles == 0) return 'empty';
    return null;
  }

  void cancelPack() => _cancelPack = true;

  /// Copies the tones and voice clips to the card (a few minutes at most). Only on a tap, not while driving.
  Future<void> uploadPack() async {
    final link = _link;
    final files = _pack;
    if (link == null || files == null || packBlocker != null || packPhase == DisplayPackPhase.uploading) return;
    _cancelPack = false;
    packFailedPath = null;
    packProgress = 0;
    packPhase = DisplayPackPhase.uploading;
    notifyListeners();
    _wake(true);
    try {
      final total = files.fold<int>(0, (a, f) => a + f.bytes.length);
      final before = List<int>.generate(files.length, (i) => files.take(i).fold<int>(0, (a, f) => a + f.bytes.length));
      final r = await link.runAssetUpload(files, isCancelled: () => _cancelPack || drive.isActive, onProgress: (i, sent, _) {
        packProgress = total > 0 ? (before[i] + sent) / total : 0;
        notifyListeners();
      });
      if (r.ok) {
        packProgress = 1;
        packPhase = DisplayPackPhase.done;
      } else {
        packFailedPath = r.failedPath;
        packPhase = r.outcome == OtaOutcome.cancelled ? DisplayPackPhase.cancelled : DisplayPackPhase.failed;
      }
    } catch (_) {
      packPhase = DisplayPackPhase.failed;
    } finally {
      _wake(false);
      notifyListeners();
    }
  }

  /// Sends the time again.
  Future<void> syncTime() async => _link?.syncTime();

  /// A short information cue on the display, to check the volume.
  Future<void> testSound() async => _link?.feed.queueTestCue(_nowMs());

  // ------------------------------------------------------------------------------------------------------------- the link

  void _onSettings() {
    _sync();
    notifyListeners();
  }

  void _sync() {
    final t = _transport;
    final s = settings.value;
    final want = t != null && s.displayFeature && s.displayEnabled && s.displayDeviceId != null;
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
    return [
      s.speedUnit.name,
      s.displaySound.name,
      s.displayVolume,
      s.displayVoice,
      s.warnOffCategories.join(','),
      s.camerasEnabled,
      _camerasAllowed,
      s.displayNightStart,
      s.displayNightEnd,
      s.displayCacheMinutes,
    ].join('|');
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
      onChange: _onLinkChange,
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
    _lastState = DisplayLinkState.off;
    if (link != null) await link.stop();
    notifyListeners();
  }

  void _onLinkChange() {
    final now = state;
    if (now == DisplayLinkState.ready && _lastState != DisplayLinkState.ready) _onConnected();
    _lastState = now;
    notifyListeners();
  }

  /// Once per connection: look for an update by itself if the user allowed it (at most once a day).
  void _onConnected() {
    final s = settings.value;
    if (!s.displayAutoUpdateCheck || !caps.ota || _updates == null) return;
    final last = s.displayLastUpdateCheck;
    if (last != null && _nowMs() - last < const Duration(hours: 24).inMilliseconds) return;
    unawaited(checkForUpdate(automatic: true));
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
      nightStartHour: s.displayNightStart,
      nightEndHour: s.displayNightEnd,
      cacheStaleMinutes: s.displayCacheMinutes,
    );
  }

  DisplayInput _input() {
    final s = settings.value;
    final snap = drive.snapshot ?? const DriveSnapshot();
    final hour = DateTime.now().hour;
    final night = s.displayNightStart <= s.displayNightEnd
        ? hour >= s.displayNightStart && hour < s.displayNightEnd
        : hour >= s.displayNightStart || hour < s.displayNightEnd;
    final conn = tn.snapshot.sync?.connection;
    return DisplayInput(
      snapshot: snap,
      caps: _link?.caps ?? const DisplayCaps(),
      online: conn == Connection.online,
      peers: tn.snapshot.network?.onlineNetwork ?? 0,
      nightMode: night,
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

  // ------------------------------------------------------------------------------------------------------------- updating

  bool get _busyUpdating =>
      updatePhase == DisplayUpdatePhase.downloading || updatePhase == DisplayUpdatePhase.installing || updatePhase == DisplayUpdatePhase.verifying;

  /// Asks the release source for the newest firmware and judges it against what the display reports. Only on a tap or, if the
  /// user allowed it, once a day while the display is connected.
  Future<void> checkForUpdate({bool automatic = false}) async {
    final src = _updates;
    if (src == null || _busyUpdating || updatePhase == DisplayUpdatePhase.checking) return;
    updatePhase = DisplayUpdatePhase.checking;
    updateErrorCode = null;
    notifyListeners();
    try {
      final fetched = await src.manifest();
      final m = fetched.manifest;
      await settings.update((s) => s.copyWith(displayLastUpdateCheck: _nowMs()));
      manifest = m;
      signature = fetched.signature;
      if (signature == SignatureStatus.invalid || signature == SignatureStatus.unknownKey) {
        // a bad signature is never offered for installing, whatever the version says
        updatePhase = automatic ? DisplayUpdatePhase.idle : DisplayUpdatePhase.badSignature;
        notifyListeners();
        return;
      }
      final installed = info?.fwVersion ?? '';
      updatePhase = switch (judgeUpdate(m, installed: installed, hasOta: caps.ota)) {
        DisplayUpdateVerdict.available => DisplayUpdatePhase.available,
        DisplayUpdateVerdict.upToDate => DisplayUpdatePhase.upToDate,
        DisplayUpdateVerdict.needsIntermediate => DisplayUpdatePhase.needsIntermediate,
        DisplayUpdateVerdict.appTooOld => DisplayUpdatePhase.appTooOld,
        DisplayUpdateVerdict.notPossible => DisplayUpdatePhase.notPossible,
      };
    } on UpdateFetchException catch (e) {
      updatePhase = switch (e.problem) {
        UpdateFetchProblem.notFound => DisplayUpdatePhase.sourceUnavailable,
        UpdateFetchProblem.offline => DisplayUpdatePhase.offline,
        _ => DisplayUpdatePhase.badRelease,
      };
      if (automatic) updatePhase = DisplayUpdatePhase.idle; // a quiet failure: the user did not ask
    } catch (_) {
      updatePhase = automatic ? DisplayUpdatePhase.idle : DisplayUpdatePhase.failed;
    }
    notifyListeners();
  }

  /// Why the update cannot start right now, or null: not connected, no OTA support, a drive is running.
  String? get updateBlocker {
    if (!connected) return 'notConnected';
    if (!caps.ota) return 'noOta';
    if (drive.isActive) return 'driving';
    return null;
  }

  void cancelUpdate() => _cancelUpdate = true;

  /// Downloads the image, checks size and SHA-256 against the manifest, pushes it to the display and checks the version after the
  /// reboot. Only after the user's tap (the page asks first). The manifest is not signed (no scheme is defined yet), which the page
  /// says before this runs.
  Future<void> installUpdate() async {
    final src = _updates;
    final m = manifest;
    final link = _link;
    if (src == null || m == null || link == null || updatePhase != DisplayUpdatePhase.available || updateBlocker != null) return;
    _cancelUpdate = false;
    updateErrorCode = null;
    updateProgress = 0;
    updatePhase = DisplayUpdatePhase.downloading;
    notifyListeners();
    _wake(true);
    try {
      final image = await src.image(m, onProgress: (got, total) {
        updateProgress = total > 0 ? got / total * 0.2 : 0;
        notifyListeners();
      });
      if (_cancelUpdate) return _end(DisplayUpdatePhase.available);
      if (checkImage(m, image) != ImageCheck.ok) return _end(DisplayUpdatePhase.badRelease);
      if (updateBlocker != null) return _end(DisplayUpdatePhase.failed);

      updatePhase = DisplayUpdatePhase.installing;
      notifyListeners();
      final result = await link.runOta(image, isCancelled: () => _cancelUpdate || drive.isActive, onProgress: (sent, total) {
        updateProgress = 0.2 + (total > 0 ? sent / total * 0.75 : 0);
        notifyListeners();
      });
      if (result.outcome == OtaOutcome.cancelled) return _end(DisplayUpdatePhase.available);
      if (!result.ok) {
        updateErrorCode = result.errorCode;
        return _end(DisplayUpdatePhase.failed);
      }

      // The display reboots and the link comes back by itself; the new version is read again and compared.
      updatePhase = DisplayUpdatePhase.verifying;
      updateProgress = 0.97;
      notifyListeners();
      final deadline = _nowMs() + const Duration(seconds: 120).inMilliseconds;
      while (_nowMs() < deadline) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final v = info?.fwVersion;
        if (connected && v != null && compareVersions(v, m.version) == 0) {
          updateProgress = 1;
          return _end(DisplayUpdatePhase.success);
        }
      }
      // Nothing changed or the display did not come back: do not claim success (the display rolls back an image that fails).
      _end(DisplayUpdatePhase.failed);
    } on UpdateFetchException catch (e) {
      _end(e.problem == UpdateFetchProblem.offline ? DisplayUpdatePhase.offline : DisplayUpdatePhase.badRelease);
    } catch (_) {
      _end(DisplayUpdatePhase.failed);
    }
  }

  /// Keeps the screen on while a firmware transfer runs; a failing plugin is ignored (the update does not depend on it).
  void _wake(bool on) {
    try {
      unawaited((on ? WakelockPlus.enable() : WakelockPlus.disable()).catchError((Object _) {}));
    } catch (_) {}
  }

  void _end(DisplayUpdatePhase phase) {
    updatePhase = phase;
    _wake(false);
    notifyListeners();
  }

  bool _disposed = false;

  /// Work that finishes after the controller was disposed (a late scan result, a link callback) must not notify.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    settings.removeListener(_onSettings);
    tn.removeListener(_onSettings);
    _timer?.cancel();
    unawaited(_link?.stop());
    super.dispose();
  }
}
