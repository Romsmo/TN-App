import 'dart:convert';

import '../drive/units.dart';

/// Local, non-secret settings. They live in an ordinary app file, never in the Keychain: that survives a reinstall on iOS.
class Settings {
  const Settings({
    this.serverAddress,
    this.hiddenHazardTypes = const [],
    this.dataWifiOnly = true,
    this.speedUnit = SpeedUnit.kmh,
    this.driveSound = true,
    this.driveVoice = true,
    this.warnOffCategories = const [],
    this.warnScale = 1,
    this.camerasEnabled = false,
    this.camerasNoticeSeen,
    this.driveNoticeSeen = false,
    this.driveLockEnabled = true,
    this.displayEnabled = false,
    this.displayDeviceId,
    this.displayName,
    this.displaySound = DisplaySoundTarget.auto,
    this.displayVolume = 70,
    this.displayVoice = false,
  });

  /// A server the user entered ("Server verbinden"); null = use discovery from the built-in seeds.
  final String? serverAddress;

  /// Hazard types the user switched off in the map filter. Stored as "hidden", so a new type shows up by default.
  final List<String> hiddenHazardTypes;

  /// Download data packages on Wi-Fi only.
  final bool dataWifiOnly;
  final SpeedUnit speedUnit;

  /// Tones and spoken warnings in the drive mode.
  final bool driveSound;
  final bool driveVoice;

  /// Categories (hazard types, `cameras`) without drive-mode warnings. Stored as "off", so new types warn by default.
  final List<String> warnOffCategories;

  /// Stretches or shrinks the warning distances: 0.75, 1 or 1.5.
  final double warnScale;

  /// The speed-camera category: off at first start.
  final bool camerasEnabled;

  /// Version of the speed-camera notice the user has seen; null = never.
  final String? camerasNoticeSeen;

  /// The legal notice at the first start of the drive mode was shown.
  final bool driveNoticeSeen;

  /// The speed lock. On by default, also on a fresh install (no settings file) and after resetting the device identity.
  final bool driveLockEnabled;

  /// The TN display (Bluetooth): the drive mode feeds it while it is on and a device is chosen.
  final bool displayEnabled;

  /// The Bluetooth id of the display the user chose, and the name it advertised (for the screen only).
  final String? displayDeviceId;
  final String? displayName;

  /// Where announcements play while the display is connected.
  final DisplaySoundTarget displaySound;

  /// 0..100, written to the display's Settings.
  final int displayVolume;
  final bool displayVoice;

  Settings copyWith({
    Object? serverAddress = _unset,
    List<String>? hiddenHazardTypes,
    bool? dataWifiOnly,
    SpeedUnit? speedUnit,
    bool? driveSound,
    bool? driveVoice,
    List<String>? warnOffCategories,
    double? warnScale,
    bool? camerasEnabled,
    Object? camerasNoticeSeen = _unset,
    bool? driveNoticeSeen,
    bool? driveLockEnabled,
    bool? displayEnabled,
    Object? displayDeviceId = _unset,
    Object? displayName = _unset,
    DisplaySoundTarget? displaySound,
    int? displayVolume,
    bool? displayVoice,
  }) =>
      Settings(
        serverAddress: identical(serverAddress, _unset) ? this.serverAddress : serverAddress as String?,
        hiddenHazardTypes: hiddenHazardTypes ?? this.hiddenHazardTypes,
        dataWifiOnly: dataWifiOnly ?? this.dataWifiOnly,
        speedUnit: speedUnit ?? this.speedUnit,
        driveSound: driveSound ?? this.driveSound,
        driveVoice: driveVoice ?? this.driveVoice,
        warnOffCategories: warnOffCategories ?? this.warnOffCategories,
        warnScale: warnScale ?? this.warnScale,
        camerasEnabled: camerasEnabled ?? this.camerasEnabled,
        camerasNoticeSeen: identical(camerasNoticeSeen, _unset) ? this.camerasNoticeSeen : camerasNoticeSeen as String?,
        driveNoticeSeen: driveNoticeSeen ?? this.driveNoticeSeen,
        driveLockEnabled: driveLockEnabled ?? this.driveLockEnabled,
        displayEnabled: displayEnabled ?? this.displayEnabled,
        displayDeviceId: identical(displayDeviceId, _unset) ? this.displayDeviceId : displayDeviceId as String?,
        displayName: identical(displayName, _unset) ? this.displayName : displayName as String?,
        displaySound: displaySound ?? this.displaySound,
        displayVolume: displayVolume ?? this.displayVolume,
        displayVoice: displayVoice ?? this.displayVoice,
      );

  Map<String, Object?> toJson() => {
        'serverAddress': serverAddress,
        'hiddenHazardTypes': hiddenHazardTypes,
        'dataWifiOnly': dataWifiOnly,
        'speedUnit': speedUnit.wire,
        'driveSound': driveSound,
        'driveVoice': driveVoice,
        'warnOffCategories': warnOffCategories,
        'warnScale': warnScale,
        'camerasEnabled': camerasEnabled,
        'camerasNoticeSeen': camerasNoticeSeen,
        'driveNoticeSeen': driveNoticeSeen,
        'driveLockEnabled': driveLockEnabled,
      };

  /// What is written to the settings file: [toJson] (the fields the shared test vectors pin) plus the display fields added later.
  Map<String, Object?> toStorageJson() => {
        ...toJson(),
        'displayEnabled': displayEnabled,
        'displayDeviceId': displayDeviceId,
        'displayName': displayName,
        'displaySound': displaySound.name,
        'displayVolume': displayVolume,
        'displayVoice': displayVoice,
      };
}

/// Where announcements play while a display is connected: `auto` = on the display, and on the phone when it is not connected.
enum DisplaySoundTarget { auto, display, phone, both }

const Object _unset = Object();

const Settings defaultSettings = Settings();

List<String> _stringList(Object? v, List<String> fallback) =>
    v is List ? [for (final e in v) if (e is String) e] : fallback;

bool _bool(Object? v, bool fallback) => v is bool ? v : fallback;

/// Reads stored JSON tolerantly: anything missing or of the wrong type falls back to the default.
/// Only an explicit `false` switches the lock off, and only if the build allows it.
Settings parseSettings(String? raw, {bool allowDisableDriveLock = true}) {
  Object? data;
  try {
    data = raw != null && raw.isNotEmpty ? jsonDecode(raw) : <String, Object?>{};
  } catch (_) {
    data = <String, Object?>{};
  }
  final o = data is Map ? data.cast<String, Object?>() : const <String, Object?>{};
  const d = defaultSettings;
  final scale = o['warnScale'];
  return Settings(
    serverAddress: o['serverAddress'] is String && (o['serverAddress'] as String).isNotEmpty ? o['serverAddress'] as String : d.serverAddress,
    hiddenHazardTypes: _stringList(o['hiddenHazardTypes'], d.hiddenHazardTypes),
    dataWifiOnly: _bool(o['dataWifiOnly'], d.dataWifiOnly),
    speedUnit: o['speedUnit'] == 'mph' ? SpeedUnit.mph : SpeedUnit.kmh,
    driveSound: _bool(o['driveSound'], d.driveSound),
    driveVoice: _bool(o['driveVoice'], d.driveVoice),
    warnOffCategories: _stringList(o['warnOffCategories'], d.warnOffCategories),
    warnScale: scale is num && (scale == 0.75 || scale == 1.5) ? scale.toDouble() : 1,
    camerasEnabled: _bool(o['camerasEnabled'], d.camerasEnabled),
    camerasNoticeSeen: o['camerasNoticeSeen'] is String && (o['camerasNoticeSeen'] as String).isNotEmpty ? o['camerasNoticeSeen'] as String : null,
    driveNoticeSeen: _bool(o['driveNoticeSeen'], d.driveNoticeSeen),
    driveLockEnabled: allowDisableDriveLock && o['driveLockEnabled'] == false ? false : true,
    displayEnabled: _bool(o['displayEnabled'], d.displayEnabled),
    displayDeviceId: o['displayDeviceId'] is String && (o['displayDeviceId'] as String).isNotEmpty ? o['displayDeviceId'] as String : null,
    displayName: o['displayName'] is String && (o['displayName'] as String).isNotEmpty ? o['displayName'] as String : null,
    displaySound: DisplaySoundTarget.values.firstWhere((t) => t.name == o['displaySound'], orElse: () => d.displaySound),
    displayVolume: o['displayVolume'] is int ? (o['displayVolume'] as int).clamp(0, 100) : d.displayVolume,
    displayVoice: _bool(o['displayVoice'], d.displayVoice),
  );
}

String encodeSettings(Settings s) => jsonEncode(s.toStorageJson());
