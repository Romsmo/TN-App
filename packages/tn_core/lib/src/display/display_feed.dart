import 'package:tn_display_protocol/tn_display_protocol.dart' as d;

import '../drive/drive_session.dart';
import '../drive/units.dart';
import '../drive/warning_engine.dart';

/// The app's side of the display contract (`docs/contract/responsibilities.md` of the display project): the app decides what the
/// display shows, whether and when; the display only draws. Pure logic: no Bluetooth, no clock of its own, tested without hardware.

/// The display's hazard id for an app category (`accident`, `fixedSpeedCamera`, ...), or null when it has none: such a category is
/// not sent ("no guessing").
int? displayHazardId(String category) => switch (category) {
      'fixedSpeedCamera' => d.HazardType.fixedSpeedCamera,
      'mobileSpeedCamera' => d.HazardType.mobileSpeedCamera,
      'trailerCamera' => d.HazardType.trailerCamera,
      'redLightCamera' => d.HazardType.redLightCamera,
      'distanceControl' => d.HazardType.distanceControl,
      'traffic' => d.HazardType.traffic,
      'ice' => d.HazardType.ice,
      'accident' => d.HazardType.accident,
      'construction' => d.HazardType.construction,
      'breakdown' => d.HazardType.breakdown,
      'obstacle' => d.HazardType.obstacle,
      _ => null,
    };

/// The report type of the app for a display hazard id (the general hazards 5-10 only; camera ids never become a report here).
String? appReportTypeFor(int hazardId) => switch (hazardId) {
      d.HazardType.traffic => 'traffic',
      d.HazardType.ice => 'ice',
      d.HazardType.accident => 'accident',
      d.HazardType.construction => 'construction',
      d.HazardType.breakdown => 'breakdown',
      d.HazardType.obstacle => 'obstacle',
      _ => null,
    };

/// What the connected display can do (from `DeviceInfo`).
class DisplayCaps {
  const DisplayCaps({this.audio = false, this.sd = false, this.speedcamBuild = false, this.ota = false, this.rtc = false});
  factory DisplayCaps.fromInfo(d.DeviceInfo i) => DisplayCaps(
        audio: i.has(d.Caps.audio),
        sd: i.has(d.Caps.sd),
        speedcamBuild: i.has(d.Caps.speedcamBuild),
        ota: i.has(d.Caps.ota),
        rtc: i.has(d.Caps.rtc),
      );
  final bool audio;
  final bool sd;
  final bool speedcamBuild;
  final bool ota;
  final bool rtc;
}

/// Whether the app's protocol version can drive this display (`docs/compatibility.md`).
enum DisplayCompat { ok, appTooOld, displayTooOld }

DisplayCompat displayCompat(d.DeviceInfo info, {int minProtocol = d.protocolVersion, int maxProtocol = d.protocolVersion}) {
  if (info.protoVersion > maxProtocol) return DisplayCompat.appTooOld;
  if (info.protoVersion < minProtocol) return DisplayCompat.displayTooOld;
  return DisplayCompat.ok;
}

/// The hazard filter as the display stores it: bit n = category n is warned about. Speed-camera categories (0-4) are on only when the
/// user switched cameras on **and** the country rule allows them (the Blitzer rule of the app; there is no way around it through
/// the display), and when the firmware has the speed-camera code at all.
int displayFilterBits({required Iterable<String> warnOff, required bool camerasEnabled, required DisplayCaps caps}) {
  var bits = 0;
  for (var id = 0; id <= d.HazardType.maxKnown; id++) {
    if (d.HazardType.isSpeedCamera(id) && !(camerasEnabled && caps.speedcamBuild)) continue;
    bits |= 1 << id;
  }
  for (final category in warnOff) {
    if (category == 'cameras') {
      for (var id = 0; id <= 4; id++) {
        bits &= ~(1 << id);
      }
      continue;
    }
    final id = displayHazardId(category);
    if (id != null) bits &= ~(1 << id);
  }
  return bits & 0xffff;
}

/// The complete Settings set the app writes after a connect (a write replaces all fields).
d.DeviceSettings displaySettingsFor({
  required bool soundOnDisplay,
  required bool voice,
  required int volume,
  required SpeedUnit unit,
  required Iterable<String> warnOff,
  required bool camerasEnabled,
  required DisplayCaps caps,
  int nightStartHour = 20,
  int nightEndHour = 6,
  int cacheStaleMinutes = 10,
}) =>
    d.DeviceSettings(
      soundEnabled: soundOnDisplay && caps.audio,
      soundMode: voice && caps.sd ? d.AudioMode.voice : d.AudioMode.tones,
      soundVolume: volume.clamp(0, 100),
      useMph: unit == SpeedUnit.mph,
      filterBits: displayFilterBits(warnOff: warnOff, camerasEnabled: camerasEnabled, caps: caps),
      nightStartHour: nightStartHour,
      nightEndHour: nightEndHour,
      cacheStaleMinutes: cacheStaleMinutes,
    );

/// Everything besides the drive snapshot that goes into a State.
class DisplayInput {
  const DisplayInput({
    required this.snapshot,
    required this.caps,
    required this.online,
    this.peers = 0,
    this.nightMode = false,
    this.camerasEnabled = false,
    this.soundOnDisplay = false,
    this.voice = false,
    this.confirmTimeoutS = 15,
    this.directionArrows = false,
    this.leftSigns = const [],
    this.rightSigns = const [],
  });
  final DriveSnapshot snapshot;
  final DisplayCaps caps;
  final bool online;
  final int peers;
  final bool nightMode;

  /// The user's camera switch (already including the country rule).
  final bool camerasEnabled;

  /// The user chose that announcements play on the display.
  final bool soundOnDisplay;
  final bool voice;
  final int confirmTimeoutS;
  final bool directionArrows;

  /// Computed with `addSign` of the protocol package from the signs the library reports; empty until that mapping exists.
  final List<int> leftSigns;
  final List<int> rightSigns;
}

/// Builds the stream of State packets for one connection: `stateSeq` from 1, a packet on every change (at most 2 per second), a
/// keep-alive at least every 5 seconds, an audio cue held for a second so a superseded packet cannot lose it.
class DisplayFeed {
  DisplayFeed({this.minIntervalMs = 500, this.keepAliveMs = 4000, this.cueHoldMs = 1500});

  final int minIntervalMs;
  final int keepAliveMs;
  final int cueHoldMs;

  int _seq = 0;
  int _cueSeq = 0;
  int? _lastSentMs;
  String? _lastContent;
  d.AudioCue? _cue;
  int _cueSinceMs = 0;
  final Map<String, WarnLevel> _announced = {};
  bool _promptAnnounced = false;

  /// A new connection: `stateSeq` starts again at 1 and everything is sent afresh.
  void reset() {
    _seq = 0;
    _cueSeq = 0;
    _lastSentMs = null;
    _lastContent = null;
    _cue = null;
    _announced.clear();
    _promptAnnounced = false;
  }

  /// The packet to send now, or null when nothing is due.
  d.DisplayState? next(DisplayInput input, int nowMs, {required int epochS}) {
    final s = input.snapshot;
    final warning = _pickWarning(s.warnings, input);
    final hazardId = warning == null ? null : displayHazardId(warning.category);
    _updateCue(input, warning, hazardId, nowMs);

    final limit = s.limit;
    final mph = limit?.unit == SpeedUnit.mph;
    final prompt = s.prompt != null && !input.snapshot.muted;
    final content = d.DisplayState(
      internetConnected: input.online,
      networkPeers: input.peers,
      speedLimit: limit?.value.round(),
      speedLimitUnit: mph ? d.SpeedUnit.mph : d.SpeedUnit.kmh,
      useMph: mph,
      directionArrows: input.directionArrows,
      leftSigns: input.leftSigns,
      rightSigns: input.rightSigns,
      hazardActive: hazardId != null,
      hazardType: hazardId,
      hazardDistanceM: warning?.distanceM,
      confirmPromptActive: prompt,
      confirmPromptTimeoutS: input.confirmTimeoutS,
      nightMode: input.nightMode,
      audioCue: _cue,
    );
    final key = _key(content);
    final last = _lastSentMs;
    final changed = key != _lastContent;
    final due = last == null ||
        (changed && nowMs - last >= minIntervalMs) ||
        (!changed && nowMs - last >= keepAliveMs);
    if (!due) return null;
    _seq += 1;
    _lastSentMs = nowMs;
    _lastContent = key;
    return d.DisplayState(
      internetConnected: content.internetConnected,
      networkPeers: content.networkPeers,
      speedLimit: content.speedLimit,
      speedLimitUnit: content.speedLimitUnit,
      useMph: content.useMph,
      directionArrows: content.directionArrows,
      leftSigns: content.leftSigns,
      rightSigns: content.rightSigns,
      hazardActive: content.hazardActive,
      hazardType: content.hazardType,
      hazardDistanceM: content.hazardDistanceM,
      confirmPromptActive: content.confirmPromptActive,
      confirmPromptTimeoutS: content.confirmPromptTimeoutS,
      nightMode: content.nightMode,
      stateSeq: _seq,
      epochS: epochS,
      audioCue: content.audioCue,
    );
  }

  // The content without sequence and clock, so a keep-alive can be told from a change.
  String _key(d.DisplayState s) {
    final j = s.toJson()
      ..remove('stateSeq')
      ..remove('epochS');
    return j.toString();
  }

  /// The warning to show: a camera category only when cameras are on and the firmware has the code; the nearest one, the second
  /// stage before the first, a zone (no distance) last.
  ActiveWarning? _pickWarning(List<ActiveWarning> all, DisplayInput input) {
    ActiveWarning? best;
    for (final w in all) {
      final id = displayHazardId(w.category);
      if (id == null) continue;
      if (d.HazardType.isSpeedCamera(id) && !(input.camerasEnabled && input.caps.speedcamBuild)) continue;
      if (best == null || _rank(w) < _rank(best)) best = w;
    }
    return best;
  }

  int _rank(ActiveWarning w) => (w.level == WarnLevel.second ? 0 : 1) * 10000000 + (w.distanceM ?? 9999999);

  void _updateCue(DisplayInput input, ActiveWarning? warning, int? hazardId, int nowMs) {
    final cueOk = input.soundOnDisplay && input.caps.audio && !input.snapshot.muted;
    final mode = input.voice && input.caps.sd ? d.AudioMode.voice : d.AudioMode.tones;
    final unit = input.snapshot.limit?.unit == SpeedUnit.mph ? d.SpeedUnit.mph : d.SpeedUnit.kmh;
    d.AudioCue? fresh;
    if (warning != null && hazardId != null) {
      final before = _announced[warning.id];
      if (before == null || (before == WarnLevel.first && warning.level == WarnLevel.second)) {
        _announced[warning.id] = warning.level;
        fresh = d.AudioCue(
          seq: 0,
          mode: mode,
          event: warning.level == WarnLevel.second ? d.AudioEvent.hazardImminent : d.AudioEvent.hazardApproach,
          hazardType: hazardId,
          distanceM: warning.distanceM,
          speedUnit: unit,
        );
      }
    }
    final ids = input.snapshot.warnings.map((w) => w.id).toSet();
    _announced.removeWhere((id, _) => !ids.contains(id));
    final prompt = input.snapshot.prompt != null;
    if (prompt && !_promptAnnounced) {
      _promptAnnounced = true;
      fresh ??= d.AudioCue(seq: 0, mode: mode, event: d.AudioEvent.confirmPrompt, speedUnit: unit);
    }
    if (!prompt) _promptAnnounced = false;
    if (fresh != null && cueOk) {
      _cueSeq += 1;
      _cue = d.AudioCue(
        seq: _cueSeq,
        mode: fresh.mode,
        event: fresh.event,
        hazardType: fresh.hazardType,
        distanceM: fresh.distanceM,
        speedUnit: fresh.speedUnit,
      );
      _cueSinceMs = nowMs;
    } else if (_cue != null && nowMs - _cueSinceMs >= cueHoldMs) {
      _cue = null;
    }
  }
}

/// What a device event asks the app to do.
sealed class DisplayAction {
  const DisplayAction();
}

class DisplayReport extends DisplayAction {
  const DisplayReport(this.reportType, {this.speedKmh});
  final String reportType;
  final int? speedKmh;
}

class DisplayConfirm extends DisplayAction {
  const DisplayConfirm({required this.seen});
  final bool seen;
}

class DisplaySettingsChanged extends DisplayAction {
  const DisplaySettingsChanged({this.soundOn, this.useMph, this.filterBits});
  final bool? soundOn;
  final bool? useMph;
  final int? filterBits;
}

class DisplayHeartbeat extends DisplayAction {
  const DisplayHeartbeat(this.uptimeS);
  final int uptimeS;
}

/// Turns device events into actions. A report from the display is accepted only for the general hazards (never a camera category:
/// the Blitzer rule of the app holds for the display too), and an identical report within [dedupeMs] is ignored (a repeated or
/// doubled notification must never make two reports).
class DisplayEventHandler {
  DisplayEventHandler({this.dedupeMs = 3000});
  final int dedupeMs;
  int? _lastReportMs;
  int? _lastReportType;

  void reset() {
    _lastReportMs = null;
    _lastReportType = null;
  }

  DisplayAction? handle(d.DeviceEvent e, int nowMs) {
    switch (e.tag) {
      case d.EventTag.reportSubmitted:
        final id = e.hazardType;
        final type = id == null ? null : appReportTypeFor(id);
        if (type == null) return null;
        final lastMs = _lastReportMs;
        if (lastMs != null && _lastReportType == id && nowMs - lastMs < dedupeMs) return null;
        _lastReportMs = nowMs;
        _lastReportType = id;
        return DisplayReport(type, speedKmh: e.speedKmh);
      case d.EventTag.confirmResponse:
        return DisplayConfirm(seen: e.seen ?? false);
      case d.EventTag.settingsSoundToggle:
        return DisplaySettingsChanged(soundOn: e.on);
      case d.EventTag.settingsUnitChanged:
        return DisplaySettingsChanged(useMph: e.useMph);
      case d.EventTag.settingsFilterChanged:
        return DisplaySettingsChanged(filterBits: e.filterBits);
      case d.EventTag.heartbeat:
        return DisplayHeartbeat(e.uptimeS ?? 0);
      default:
        return null; // ReportPressed (the page opened), legacy tags
    }
  }
}
