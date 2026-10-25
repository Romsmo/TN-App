/// The CBOR messages of protocol v1. Field names match the decoded form in
/// docs/contract/vectors/*.json; encoding order matches core/codec/protocol.cpp so the
/// bytes are identical to what the firmware's own encoder emits (canonical form).
library;

import 'dart:typed_data';

import 'cbor_min.dart';
import 'constants.dart';

Map<int, Object?> _decodeMap(Uint8List bytes) {
  final v = cborDecode(bytes);
  if (v is! Map<int, Object?>) throw const FormatException('payload is not a CBOR map');
  return v;
}

int? _uint(Object? v) => v is int && v >= 0 ? v : null;

int _intOr(Map<int, Object?> m, int key, int dflt) => _uint(m[key]) ?? dflt;

bool _flag(int flags, int bit) => (flags & (1 << bit)) != 0;

List<int> _signs(Object? v) {
  if (v is! List) return const [];
  final out = <int>[];
  for (final e in v) {
    final u = _uint(e);
    if (u != null && out.length < signListMax) out.add(u & 0xffff);
  }
  return out;
}

// ─────────────────────────────── AudioCue ────────────────────────────────────

/// A request to play an announcement. The app decides WHEN; the device decides how it
/// sounds. The device plays a cue only when [seq] changes (0 = never).
class AudioCue {
  const AudioCue({
    required this.seq,
    this.mode = AudioMode.tones,
    this.event = AudioEvent.info,
    this.hazardType,
    this.distanceM,
    this.speedValue,
    this.speedUnit = SpeedUnit.kmh,
  });

  final int seq;
  final int mode; // AudioMode
  final int event; // AudioEvent
  final int? hazardType;
  final int? distanceM;
  final int? speedValue;
  final int speedUnit;

  Map<int, Object?> toMap() => {
        0: seq,
        1: mode,
        2: event,
        if (hazardType != null) 3: hazardType,
        if (distanceM != null) 4: distanceM,
        if (speedValue != null) 5: speedValue,
        6: speedUnit,
      };

  static AudioCue _fromMap(Map<int, Object?> m) => AudioCue(
        seq: _intOr(m, 0, 0),
        mode: _intOr(m, 1, AudioMode.tones),
        event: _intOr(m, 2, AudioEvent.info),
        hazardType: _uint(m[3]),
        distanceM: _uint(m[4]),
        speedValue: _uint(m[5]),
        speedUnit: _intOr(m, 6, SpeedUnit.kmh),
      );

  Map<String, Object?> toJson() => {
        'seq': seq,
        'mode': mode,
        'event': event,
        'hazardType': hazardType,
        'distanceM': distanceM,
        'speedValue': speedValue,
        'speedUnit': speedUnit,
      };
}

// ─────────────────────────────── DisplayState ────────────────────────────────

/// Everything the app tells the display to show (State characteristic, `0001`).
class DisplayState {
  const DisplayState({
    this.internetConnected = false,
    this.driveActive = true,
    this.networkPeers = 0,
    this.speedLimit,
    this.speedLimitUnit = SpeedUnit.kmh,
    this.directionArrows = false,
    this.leftSigns = const [],
    this.rightSigns = const [],
    this.hazardActive = false,
    this.hazardType,
    this.hazardDistanceM,
    this.hazardSpeedLimit,
    this.confirmPromptActive = false,
    this.confirmPromptTimeoutS = 15,
    this.nightMode = false,
    this.useMph = false,
    this.stateSeq = 0,
    this.epochS = 0,
    this.audioCue,
  });

  final bool internetConnected;

  /// Is a trip (Fahrt) running? `false` = the app is connected but idle: the display shows its
  /// logo and offers only Settings. Encoded as key 14 only when false; absent means true.
  final bool driveActive;
  final int networkPeers;
  final int? speedLimit;
  final int speedLimitUnit;
  final bool directionArrows;
  final List<int> leftSigns;
  final List<int> rightSigns;
  final bool hazardActive;
  final int? hazardType;
  final int? hazardDistanceM;
  final int? hazardSpeedLimit;
  final bool confirmPromptActive;
  final int confirmPromptTimeoutS;
  final bool nightMode;
  final bool useMph;
  final int stateSeq;
  final int epochS;
  final AudioCue? audioCue;

  /// Canonical encoding (identical bytes to the firmware's `encode_state`).
  Uint8List encode() {
    var flags = 0;
    if (internetConnected) flags |= 1 << 0;
    if (directionArrows) flags |= 1 << 1;
    if (hazardActive) flags |= 1 << 2;
    if (confirmPromptActive) flags |= 1 << 3;
    if (nightMode) flags |= 1 << 4;
    if (useMph) flags |= 1 << 5;
    final m = <int, Object?>{
      0: protocolVersion,
      1: flags,
      if (speedLimit != null) 2: speedLimit,
      3: speedLimitUnit,
      if (hazardActive && hazardType != null) 4: hazardType,
      if (hazardDistanceM != null) 5: hazardDistanceM,
      if (hazardSpeedLimit != null) 6: hazardSpeedLimit,
      7: confirmPromptTimeoutS,
      8: stateSeq,
      if (epochS != 0) 9: epochS,
      if (networkPeers != 0) 10: networkPeers,
      if (leftSigns.isNotEmpty) 11: leftSigns.take(signListMax).toList(),
      if (rightSigns.isNotEmpty) 12: rightSigns.take(signListMax).toList(),
      if (audioCue != null) 13: audioCue!.toMap(),
      if (!driveActive) 14: false,
    };
    final out = cborEncode(m);
    if (out.length > maxPayloadBytes) {
      throw StateError('DisplayState encodes to ${out.length} B, over the $maxPayloadBytes B limit');
    }
    return out;
  }

  /// Decodes like the firmware does; throws [FormatException] if it is not a valid map.
  static DisplayState decode(Uint8List bytes) {
    final m = _decodeMap(bytes);
    final f = _intOr(m, 1, 0);
    final cue = m[13];
    return DisplayState(
      internetConnected: _flag(f, 0),
      driveActive: m[14] != false,
      directionArrows: _flag(f, 1),
      hazardActive: _flag(f, 2),
      confirmPromptActive: _flag(f, 3),
      nightMode: _flag(f, 4),
      useMph: _flag(f, 5),
      speedLimit: _uint(m[2]),
      speedLimitUnit: _intOr(m, 3, SpeedUnit.kmh),
      hazardType: _uint(m[4]),
      hazardDistanceM: _uint(m[5]),
      hazardSpeedLimit: _uint(m[6]),
      confirmPromptTimeoutS: _intOr(m, 7, 15),
      stateSeq: _intOr(m, 8, 0),
      epochS: _intOr(m, 9, 0),
      networkPeers: _intOr(m, 10, 0),
      leftSigns: _signs(m[11]),
      rightSigns: _signs(m[12]),
      audioCue: cue is Map<int, Object?> ? AudioCue._fromMap(cue) : null,
    );
  }

  static DisplayState? tryDecode(Uint8List bytes) {
    try {
      return decode(bytes);
    } on FormatException {
      return null;
    }
  }

  Map<String, Object?> toJson() => {
        'internetConnected': internetConnected,
        'driveActive': driveActive,
        'networkPeers': networkPeers,
        'speedLimit': speedLimit,
        'speedLimitUnit': speedLimitUnit,
        'directionArrows': directionArrows,
        'leftSigns': leftSigns,
        'rightSigns': rightSigns,
        'hazardActive': hazardActive,
        'hazardType': hazardType,
        'hazardDistanceM': hazardDistanceM,
        'hazardSpeedLimit': hazardSpeedLimit,
        'confirmPromptActive': confirmPromptActive,
        'confirmPromptTimeoutS': confirmPromptTimeoutS,
        'nightMode': nightMode,
        'useMph': useMph,
        'stateSeq': stateSeq,
        'epochS': epochS,
        'audioCue': audioCue?.toJson(),
      };
}

// ─────────────────────────────── Settings ────────────────────────────────────

/// Persisted device settings (Settings characteristic, `0004`), synced both ways.
class DeviceSettings {
  const DeviceSettings({
    this.soundEnabled = false,
    this.soundMode = AudioMode.tones,
    this.soundVolume = 70,
    this.theme = 0,
    this.useMph = false,
    this.filterBits = 0xffff,
    this.nightStartHour = 20,
    this.nightEndHour = 6,
    this.cacheStaleMinutes = 10,
  });

  final bool soundEnabled;
  final int soundMode;
  final int soundVolume; // 0..100
  final int theme; // 0 auto / 1 day / 2 night — the device has one dark theme and ignores it
  final bool useMph;
  final int filterBits; // bit n = HazardType n is warned about
  final int nightStartHour;
  final int nightEndHour;
  final int cacheStaleMinutes;

  DeviceSettings copyWith({
    bool? soundEnabled,
    int? soundMode,
    int? soundVolume,
    int? theme,
    bool? useMph,
    int? filterBits,
    int? nightStartHour,
    int? nightEndHour,
    int? cacheStaleMinutes,
  }) =>
      DeviceSettings(
        soundEnabled: soundEnabled ?? this.soundEnabled,
        soundMode: soundMode ?? this.soundMode,
        soundVolume: soundVolume ?? this.soundVolume,
        theme: theme ?? this.theme,
        useMph: useMph ?? this.useMph,
        filterBits: filterBits ?? this.filterBits,
        nightStartHour: nightStartHour ?? this.nightStartHour,
        nightEndHour: nightEndHour ?? this.nightEndHour,
        cacheStaleMinutes: cacheStaleMinutes ?? this.cacheStaleMinutes,
      );

  Uint8List encode() => cborEncode(<int, Object?>{
        0: protocolVersion,
        1: soundEnabled,
        2: soundMode,
        9: soundVolume.clamp(0, 100),
        3: theme,
        4: useMph,
        5: filterBits & 0xffff,
        6: nightStartHour,
        7: nightEndHour,
        8: cacheStaleMinutes,
      });

  static DeviceSettings decode(Uint8List bytes) {
    final m = _decodeMap(bytes);
    return DeviceSettings(
      soundEnabled: m[1] == true,
      soundMode: _intOr(m, 2, AudioMode.tones),
      soundVolume: _intOr(m, 9, 70).clamp(0, 100),
      theme: _intOr(m, 3, 0),
      useMph: m[4] == true,
      filterBits: _intOr(m, 5, 0xffff) & 0xffff,
      nightStartHour: _intOr(m, 6, 20),
      nightEndHour: _intOr(m, 7, 6),
      cacheStaleMinutes: _intOr(m, 8, 10),
    );
  }

  /// Is a hazard category switched on? Unknown (future) types are always shown.
  bool warnsAbout(int hazardType) =>
      hazardType >= 16 || (filterBits & (1 << hazardType)) != 0;

  Map<String, Object?> toJson() => {
        'soundEnabled': soundEnabled,
        'soundMode': soundMode,
        'soundVolume': soundVolume,
        'theme': theme,
        'useMph': useMph,
        'filterBits': filterBits,
        'nightStartHour': nightStartHour,
        'nightEndHour': nightEndHour,
        'cacheStaleMinutes': cacheStaleMinutes,
      };
}

// ─────────────────────────────── UiConfig ────────────────────────────────────

/// Persistent feature switches (UiConfig characteristic, `0006`). Bit set = feature on.
class UiConfig {
  const UiConfig([this.bits = (1 << UiBit.count) - 1]);
  final int bits;

  bool isOn(int bit) => (bits & (1 << bit)) != 0;
  UiConfig withBit(int bit, bool on) => UiConfig(on ? bits | (1 << bit) : bits & ~(1 << bit));

  Uint8List encode() => cborEncode(<int, Object?>{0: protocolVersion, 1: bits & 0xffffffff});

  static UiConfig decode(Uint8List bytes) {
    final m = _decodeMap(bytes);
    return UiConfig(_intOr(m, 1, (1 << UiBit.count) - 1));
  }

  Map<String, Object?> toJson() => {'bits': bits};
}

// ─────────────────────────────── Time ────────────────────────────────────────

/// Wall-clock sync (Time characteristic, `0005`): epoch seconds + UTC offset in minutes.
class TimeSync {
  const TimeSync(this.epochS, this.tzOffsetMin);
  final int epochS;
  final int tzOffsetMin;

  Uint8List encode() =>
      cborEncode(<int, Object?>{0: protocolVersion, 1: epochS, 2: tzOffsetMin});

  static TimeSync decode(Uint8List bytes) {
    final m = _decodeMap(bytes);
    final tz = m[2];
    return TimeSync(_intOr(m, 1, 0), tz is int ? tz : 0);
  }

  Map<String, Object?> toJson() => {'epochS': epochS, 'tzOffsetMin': tzOffsetMin};
}

// ─────────────────────────────── DeviceInfo ──────────────────────────────────

/// What a device reports about itself (DeviceInfo characteristic, `0003`, read).
class DeviceInfo {
  const DeviceInfo({
    required this.protoVersion,
    required this.fwVersion,
    required this.caps,
    required this.width,
    required this.height,
  });

  final int protoVersion;
  final String fwVersion;
  final int caps;
  final int width;
  final int height;

  bool has(int capBit) => (caps & capBit) != 0;

  Uint8List encode() => cborEncode(<int, Object?>{
        0: protoVersion,
        1: fwVersion,
        2: caps,
        3: width,
        4: height,
      });

  static DeviceInfo decode(Uint8List bytes) {
    final m = _decodeMap(bytes);
    final fw = m[1];
    return DeviceInfo(
      protoVersion: _intOr(m, 0, 0),
      fwVersion: fw is String ? fw : '',
      caps: _intOr(m, 2, 0),
      width: _intOr(m, 3, 0),
      height: _intOr(m, 4, 0),
    );
  }

  Map<String, Object?> toJson() => {
        'protoVersion': protoVersion,
        'fwVersion': fwVersion,
        'caps': caps,
        'width': width,
        'height': height,
      };
}

// ─────────────────────────────── DeviceEvent ─────────────────────────────────

/// A raw interaction fact from the device (Event characteristic, `0002`, notify).
class DeviceEvent {
  const DeviceEvent(
    this.tag, {
    this.hazardType,
    this.speedKmh,
    this.seen,
    this.on,
    this.mode,
    this.useMph,
    this.filterBits,
    this.uptimeS,
  });

  final int tag; // EventTag
  final int? hazardType; // ReportSubmitted
  final int? speedKmh; // ReportSubmitted (present only for categories that need a speed)
  final bool? seen; // ConfirmResponse
  final bool? on; // SettingsSoundToggle
  final int? mode; // SettingsThemeChanged
  final bool? useMph; // SettingsUnitChanged
  final int? filterBits; // SettingsFilterChanged
  final int? uptimeS; // Heartbeat

  /// Returns null for an unknown tag (the protocol says: drop it) and throws
  /// [FormatException] for malformed bytes.
  static DeviceEvent? decode(Uint8List bytes) {
    final m = _decodeMap(bytes);
    final tag = _uint(m[1]);
    switch (tag) {
      case EventTag.reportPressed:
      case EventTag.settingsPhoneConnect:
        return DeviceEvent(tag!);
      case EventTag.reportSubmitted:
        return DeviceEvent(tag!, hazardType: _intOr(m, 2, 0), speedKmh: _uint(m[3]));
      case EventTag.confirmResponse:
        return DeviceEvent(tag!, seen: m[4] == true);
      case EventTag.settingsSoundToggle:
        return DeviceEvent(tag!, on: m[5] == true);
      case EventTag.settingsThemeChanged:
        return DeviceEvent(tag!, mode: _intOr(m, 6, 0));
      case EventTag.settingsUnitChanged:
        return DeviceEvent(tag!, useMph: m[7] == true);
      case EventTag.settingsFilterChanged:
        return DeviceEvent(tag!, filterBits: _intOr(m, 8, 0xffff) & 0xffff);
      case EventTag.heartbeat:
        return DeviceEvent(tag!, uptimeS: _intOr(m, 9, 0));
      default:
        return null;
    }
  }

  static DeviceEvent? tryDecode(Uint8List bytes) {
    try {
      return decode(bytes);
    } on FormatException {
      return null;
    }
  }

  Map<String, Object?> toJson() {
    final o = <String, Object?>{'tag': tag};
    switch (tag) {
      case EventTag.reportSubmitted:
        o['hazardType'] = hazardType;
        o['speedKmh'] = speedKmh;
      case EventTag.confirmResponse:
        o['seen'] = seen;
      case EventTag.settingsSoundToggle:
        o['on'] = on;
      case EventTag.settingsThemeChanged:
        o['mode'] = mode;
      case EventTag.settingsUnitChanged:
        o['useMph'] = useMph;
      case EventTag.settingsFilterChanged:
        o['filterBits'] = filterBits;
      case EventTag.heartbeat:
        o['uptimeS'] = uptimeS;
    }
    return o;
  }
}
