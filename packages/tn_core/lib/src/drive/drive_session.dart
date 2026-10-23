import 'dart:async';
import 'dart:math' as math;

import '../texts.dart';
import '../tn/types.dart';
import 'data_source.dart';
import 'feedback.dart';
import 'fix.dart';
import 'geo.dart';
import 'lock.dart';
import 'units.dart';
import 'warning_engine.dart';

/// The settings the session reads, fresh at every use (they can change while driving, e.g. mute).
class DriveSettings {
  const DriveSettings({
    this.unit = SpeedUnit.kmh,
    this.sound = true,
    this.voice = true,
    this.warnOff = const [],
    this.scale = 1,
    this.lockEnabled = true,
  });
  final SpeedUnit unit;
  final bool sound;
  final bool voice;

  /// Categories (hazard types, `cameras`) the user does not want warnings for.
  final List<String> warnOff;

  /// Stretches or shrinks the warning distances.
  final double scale;
  final bool lockEnabled;
}

class ActiveWarning {
  const ActiveWarning({
    required this.id,
    required this.level,
    required this.kind,
    required this.category,
    required this.label,
    required this.distanceM,
    required this.since,
  });
  final String id;
  final WarnLevel level;
  final WarnKind kind;
  final String category;

  /// What the screen shows ("Unfall", "Gefahrenbereich").
  final String label;

  /// Metres to a point object; always null for a zone: an area has no distance to a spot.
  final int? distanceM;
  final int since;
}

class DrivePrompt {
  const DrivePrompt({required this.id, required this.hazardType, required this.since});
  final String id;
  final String hazardType;
  final int since;
}

typedef Limit = ({num value, SpeedUnit unit});

const Object _unset = Object();

class DriveSnapshot {
  const DriveSnapshot({
    this.active = false,
    this.simulated = false,
    this.speedKmh,
    this.heading,
    this.limit,
    this.limitUnavailable = false,
    this.speedState = SpeedState.ok,
    this.warnings = const [],
    this.prompt,
    this.muted = false,
    this.locked = false,
    this.speedLocked = false,
    this.gpsLost = false,
  });

  final bool active;
  final bool simulated;
  final double? speedKmh;

  /// The direction of travel in degrees from north (0..360), or null while it is not known.
  final double? heading;
  final Limit? limit;

  /// There is no limit shown because the offline data does not cover this spot (not because none is on record).
  final bool limitUnavailable;
  final SpeedState speedState;
  final List<ActiveWarning> warnings;
  final DrivePrompt? prompt;
  final bool muted;

  /// The speed lock is in force (driving above the threshold, lock switched on).
  final bool locked;

  /// Driving above the threshold, whatever the user's lock setting says.
  final bool speedLocked;

  /// No position for a while.
  final bool gpsLost;

  DriveSnapshot copyWith({
    bool? active,
    bool? simulated,
    Object? speedKmh = _unset,
    Object? heading = _unset,
    Object? limit = _unset,
    bool? limitUnavailable,
    SpeedState? speedState,
    List<ActiveWarning>? warnings,
    Object? prompt = _unset,
    bool? muted,
    bool? locked,
    bool? speedLocked,
    bool? gpsLost,
  }) =>
      DriveSnapshot(
        active: active ?? this.active,
        simulated: simulated ?? this.simulated,
        speedKmh: identical(speedKmh, _unset) ? this.speedKmh : speedKmh as double?,
        heading: identical(heading, _unset) ? this.heading : heading as double?,
        limit: identical(limit, _unset) ? this.limit : limit as Limit?,
        limitUnavailable: limitUnavailable ?? this.limitUnavailable,
        speedState: speedState ?? this.speedState,
        warnings: warnings ?? this.warnings,
        prompt: identical(prompt, _unset) ? this.prompt : prompt as DrivePrompt?,
        muted: muted ?? this.muted,
        locked: locked ?? this.locked,
        speedLocked: speedLocked ?? this.speedLocked,
        gpsLost: gpsLost ?? this.gpsLost,
      );
}

class DriveDeps {
  DriveDeps({
    required this.data,
    required this.feedback,
    required this.texts,
    required this.getSettings,
    required this.now,
    required this.submitReport,
    required this.vote,
    this.simulated = false,
  });
  final DriveDataSource data;
  final Feedback feedback;
  final Texts texts;
  final DriveSettings Function() getSettings;
  final int Function() now;

  /// One-tap report at a position; resolves true when the report was stored. No speed is sent: the server refuses it
  /// for most types, and it is data nobody needs.
  final Future<bool> Function(String type, ({double lat, double lng}) position) submitReport;

  /// Vote on a report; resolves true when stored.
  final Future<bool> Function(String reportId, bool stillThere) vote;
  final bool simulated;
}

const int warningShownMs = 12000;
const int promptShownMs = 8000;
const int promptMinGapMs = 30000;
const int speechMinGapMs = 2500;
const int gpsLostAfterMs = 10000;
const int maxReportFixAgeMs = 15000;
const double refreshMovedM = 200;
const int refreshAfterMs = 10000;
const double limitRefreshMovedM = 30;
const int limitRefreshAfterMs = 3000;

String? _categoryOf(NearbyItem item) => switch (item) {
      HazardItem() => item.hazardType,
      CameraItem() || CameraZoneItem() => 'cameras',
      _ => null,
    };

/// The text for a warning event: a point gets a distance, an area never does.
String warningLabel(Texts texts, String category, WarnKind kind, WarnSource source, String? rawType) {
  if (kind == WarnKind.zone) return texts.t('drive.zone');
  return texts.hazardLabel(source == WarnSource.camera && rawType != null ? rawType : category);
}

/// The sentence spoken for a warning. A zone is "Gefahrenbereich", never a distance to a spot.
String spokenText(Texts texts, String label, WarnLevel level, WarnKind kind, int? distanceM) {
  if (kind == WarnKind.zone) {
    return level == WarnLevel.first ? texts.t('drive.say.zoneAhead') : texts.t('drive.say.zoneInside');
  }
  if (level == WarnLevel.second || distanceM == null) return texts.t('drive.say.second', {'what': label});
  return texts.t('drive.say.first', {'what': label, 'distance': jsRound(distanceM / 50) * 50});
}

/// The drive mode's brain. Position fixes go in; speed, limit, warnings, "still there?" prompts and the lock come out as a
/// snapshot. Everything outside (clock, data, speech, haptics, storage of reports) is injected, so the whole flow runs in tests.
class DriveSession {
  DriveSession(this.deps);
  final DriveDeps deps;

  DriveSnapshot _snap = const DriveSnapshot();
  final Set<void Function()> _listeners = {};
  final WarningEngine _engine = WarningEngine();
  final LockTracker _lock = LockTracker();
  List<NearbyItem> _items = const [];
  ({double lat, double lng, int at})? _queriedAt;
  bool _querying = false;
  Fix? _lastFix;
  int _lastFixAtMs = 0;
  Fix? _previous;
  int _lastSpeechAt = -4503599627370496;
  int _lastPromptAt = -4503599627370496;
  ({double lat, double lng, int at})? _limitAt;
  Map<String, String> _rawTypes = {};

  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  DriveSnapshot get snapshot => _snap;

  void _set(DriveSnapshot next) {
    _snap = next;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  void start() {
    _engine.reset();
    _lock.reset();
    _items = const [];
    _queriedAt = null;
    _lastFix = null;
    _previous = null;
    _limitAt = null;
    _lastFixAtMs = deps.now();
    _set(DriveSnapshot(active: true, simulated: deps.simulated));
  }

  void stop() {
    deps.feedback.silence();
    _engine.reset();
    _lock.reset();
    _lastFix = null;
    _previous = null;
    _items = const [];
    _set(const DriveSnapshot());
  }

  void setMuted(bool muted) {
    if (muted) deps.feedback.silence();
    _set(_snap.copyWith(muted: muted));
  }

  /// The heading of the fix; when the receiver gives none (standing, slow) it comes from the last clear movement.
  double? _headingOf(Fix fix) {
    if (fix.heading != null && (fix.speedKmh ?? 0) >= 4) return fix.heading;
    final prev = _previous;
    if (prev == null) return fix.heading;
    if (distanceMeters(prev.point, fix.point) < 10) return prev.heading;
    return bearingDegrees(prev.point, fix.point);
  }

  void onFix(Fix raw) {
    if (!_snap.active) return;
    final now = deps.now();
    final settings = deps.getSettings();
    final fix = raw.copyWith(heading: () => _headingOf(raw));
    if (fix.heading != null) _previous = fix;
    _lastFix = fix;
    _lastFixAtMs = now;

    final speedLocked = _lock.update(fix.speedKmh, now);
    final locked = speedLocked && settings.lockEnabled;
    unawaited(_refreshData(fix, now));

    final events = _engine.update(fix, _candidates(settings));
    final warnings = _applyEvents(events, now, settings);
    _handlePassed(events, now, settings);

    _set(_snap.copyWith(
      speedKmh: fix.speedKmh,
      heading: fix.heading,
      speedState: speedState(fix.speedKmh, _snap.limit),
      warnings: warnings,
      locked: locked,
      speedLocked: speedLocked,
      gpsLost: false,
    ));
  }

  /// Regular heartbeat (about once a second): lets warnings and the prompt expire, releases a stale lock.
  void tick() {
    if (!_snap.active) return;
    final now = deps.now();
    final warnings = _snap.warnings.where((w) => now - w.since < warningShownMs).toList();
    final prompt = _snap.prompt != null && now - _snap.prompt!.since < promptShownMs ? _snap.prompt : null;
    final speedLocked = _lock.tick(now);
    final stillLocked = speedLocked && deps.getSettings().lockEnabled;
    final gpsLost = now - _lastFixAtMs > gpsLostAfterMs;
    if (warnings.length != _snap.warnings.length ||
        prompt != _snap.prompt ||
        stillLocked != _snap.locked ||
        speedLocked != _snap.speedLocked ||
        gpsLost != _snap.gpsLost) {
      _set(_snap.copyWith(warnings: warnings, prompt: prompt, locked: stillLocked, speedLocked: speedLocked, gpsLost: gpsLost));
    }
  }

  List<WarnCandidate> _candidates(DriveSettings settings) {
    final out = <WarnCandidate>[];
    for (final item in _items) {
      final category = _categoryOf(item);
      if (category == null || settings.warnOff.contains(category)) continue;
      switch (item) {
        case HazardItem() when !item.pending:
          out.add(PointCandidate(id: item.id, category: category, source: 'hazard', lat: item.lat, lng: item.lng));
        case CameraItem():
          out.add(PointCandidate(id: item.id, category: category, source: 'camera', lat: item.lat, lng: item.lng));
        case CameraZoneItem():
          out.add(ZoneCandidate(id: item.id, category: category, ring: item.outline));
        default:
      }
    }
    return out;
  }

  Future<void> _refreshData(Fix fix, int now) async {
    final queried = _queriedAt;
    final moved = queried != null ? distanceMeters(LatLng(queried.lat, queried.lng), fix.point) : double.infinity;
    if (!_querying && (moved > refreshMovedM || queried == null || now - queried.at > refreshAfterMs)) {
      _querying = true;
      _queriedAt = (lat: fix.lat, lng: fix.lng, at: now);
      try {
        final scale = deps.getSettings().scale;
        final radius = math.max(2500.0, thresholds(fix.speedKmh ?? 0, defaultWarnConfig.withScale(scale)).first * 1.6);
        _items = await deps.data.nearby(fix.lat, fix.lng, radius);
        _rawTypes = {
          for (final i in _items)
            if (i is CameraItem) i.id: i.cameraType,
        };
      } catch (_) {
        // keep what we had: an empty read must not silence warnings that were already known
      } finally {
        _querying = false;
      }
    }
    final limitAt = _limitAt;
    final limitMoved = limitAt != null ? distanceMeters(LatLng(limitAt.lat, limitAt.lng), fix.point) : double.infinity;
    if (limitMoved > limitRefreshMovedM || limitAt == null || now - limitAt.at > limitRefreshAfterMs) {
      _limitAt = (lat: fix.lat, lng: fix.lng, at: now);
      try {
        final answer = await deps.data.speedLimit(fix.lat, fix.lng, fix.heading);
        if (!_snap.active) return; // the drive ended while the answer was on its way
        final Limit? limit = answer == null ? null : (value: answer.value, unit: answer.unit);
        final unavailable = limit == null ? !(await deps.data.limitCovered(fix.lat, fix.lng)) : false;
        if (!_snap.active) return;
        _set(_snap.copyWith(limit: limit, limitUnavailable: unavailable, speedState: speedState(_snap.speedKmh, limit)));
      } catch (_) {
        // no limit shown rather than a wrong one, and no claim about coverage that could not be read
      }
    }
  }

  List<ActiveWarning> _applyEvents(List<WarnEvent> events, int now, DriveSettings settings) {
    var warnings = _snap.warnings.where((w) => now - w.since < warningShownMs).toList();
    for (final e in events) {
      if (e is Passed) {
        warnings = warnings.where((w) => w.id != e.id).toList();
        continue;
      }
      e as WarnNow;
      final label = warningLabel(deps.texts, e.category, e.kind, e.source, _rawTypes[e.id]);
      warnings = [
        ...warnings.where((w) => w.id != e.id),
        ActiveWarning(
          id: e.id,
          level: e.level,
          kind: e.kind,
          category: e.category,
          label: label,
          distanceM: e.kind == WarnKind.zone ? null : e.distanceM,
          since: now,
        ),
      ];
      final muted = _snap.muted;
      final speak = settings.voice && !muted && (e.level == WarnLevel.second || now - _lastSpeechAt >= speechMinGapMs);
      if (speak) _lastSpeechAt = now;
      deps.feedback.warn(
        e.level,
        spokenText(deps.texts, label, e.level, e.kind, e.distanceM),
        sound: settings.sound && !muted,
        voice: speak,
      );
    }
    // second level first, newer first within a level; stable like Array.prototype.sort
    final indexed = [for (var i = 0; i < warnings.length; i++) (i, warnings[i])];
    indexed.sort((a, b) {
      final wa = a.$2;
      final wb = b.$2;
      final c = wa.level == wb.level ? wb.since.compareTo(wa.since) : (wa.level == WarnLevel.second ? -1 : 1);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    return [for (final w in indexed.take(3)) w.$2];
  }

  void _handlePassed(List<WarnEvent> events, int now, DriveSettings settings) {
    for (final e in events) {
      if (e is! Passed || e.source != WarnSource.hazard || _snap.prompt != null || now - _lastPromptAt < promptMinGapMs) continue;
      _lastPromptAt = now;
      _set(_snap.copyWith(prompt: DrivePrompt(id: e.id, hazardType: e.category, since: now)));
      deps.feedback.prompt(sound: settings.sound && !_snap.muted);
    }
  }

  /// The answer to the "still there?" card; it counts as a confirmation or a denial.
  Future<void> answerPrompt(bool stillThere) async {
    final prompt = _snap.prompt;
    if (prompt == null) return;
    _set(_snap.copyWith(prompt: null));
    final ok = await deps.vote(prompt.id, stillThere);
    if (ok) deps.feedback.confirm(sound: deps.getSettings().sound && !_snap.muted);
  }

  void dismissPrompt() {
    if (_snap.prompt != null) _set(_snap.copyWith(prompt: null));
  }

  /// One-tap report at the current position. Returns false when there is no position yet or storing failed.
  Future<bool> report(String type) async {
    final fix = _lastFix;
    // No report at an old position: not before the first fix, not after the drive, not with the GPS lost.
    if (!_snap.active || fix == null || deps.now() - _lastFixAtMs > maxReportFixAgeMs) return false;
    final ok = await deps.submitReport(type, (lat: fix.lat, lng: fix.lng));
    if (ok) deps.feedback.confirm(sound: deps.getSettings().sound && !_snap.muted);
    return ok;
  }
}
