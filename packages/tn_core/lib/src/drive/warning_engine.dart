import 'dart:math' as math;

import 'fix.dart';
import 'geo.dart';

/// A thing the driver may be warned about. A zone is an area: it has no point and is never announced with a distance to a spot.
sealed class WarnCandidate {
  const WarnCandidate(this.id, this.category);
  final String id;
  final String category;
}

class PointCandidate extends WarnCandidate {
  const PointCandidate({
    required String id,
    required String category,
    required this.source,
    required this.lat,
    required this.lng,
  }) : super(id, category);

  /// `hazard` or `camera`.
  final String source;
  final double lat;
  final double lng;
}

class ZoneCandidate extends WarnCandidate {
  const ZoneCandidate({required String id, required String category, required this.ring}) : super(id, category);

  /// `[lng, lat]` corners.
  final List<List<double>> ring;
}

class WarnConfig {
  const WarnConfig({
    this.leadFirstS = 25,
    this.leadSecondS = 8,
    this.minFirstM = 300,
    this.maxFirstM = 2000,
    this.minSecondM = 80,
    this.scale = 1,
    this.minSpeedKmh = 10,
    this.lateralMinM = 25,
    this.lateralMaxM = 100,
    this.lateralFactor = 0.1,
    this.passedM = 30,
  });

  /// Seconds of driving time before the object for the first and the second warning.
  final double leadFirstS;
  final double leadSecondS;

  /// Bounds for the warning distances (metres), before [scale].
  final double minFirstM;
  final double maxFirstM;
  final double minSecondM;

  /// User setting: stretches or shrinks all warning distances.
  final double scale;

  /// No warnings below this speed (km/h): standing in a queue is not driving towards a hazard.
  final double minSpeedKmh;

  /// Side tolerance of "on my carriageway": grows with distance (curves), within these bounds (metres).
  final double lateralMinM;
  final double lateralMaxM;
  final double lateralFactor;

  /// How far behind (metres) an object must be to count as passed.
  final double passedM;

  WarnConfig withScale(double scale) => WarnConfig(
        leadFirstS: leadFirstS,
        leadSecondS: leadSecondS,
        minFirstM: minFirstM,
        maxFirstM: maxFirstM,
        minSecondM: minSecondM,
        scale: scale,
        minSpeedKmh: minSpeedKmh,
        lateralMinM: lateralMinM,
        lateralMaxM: lateralMaxM,
        lateralFactor: lateralFactor,
        passedM: passedM,
      );
}

const defaultWarnConfig = WarnConfig();

enum WarnLevel { first, second }

enum WarnKind { point, zone }

/// What a [WarnEvent] concerns: a reported hazard, a permanently installed camera, or a camera zone.
enum WarnSource { hazard, camera, zone }

sealed class WarnEvent {
  const WarnEvent({required this.id, required this.kind, required this.category, required this.source});
  final String id;
  final WarnKind kind;
  final String category;
  final WarnSource source;
}

class WarnNow extends WarnEvent {
  const WarnNow({
    required this.level,
    required super.id,
    required super.kind,
    required super.category,
    required super.source,
    required this.distanceM,
  });
  final WarnLevel level;

  /// Null for a zone.
  final int? distanceM;
}

class Passed extends WarnEvent {
  const Passed({
    required super.id,
    required super.kind,
    required super.category,
    required super.source,
    required this.reachedSecond,
  });
  final bool reachedSecond;
}

/// The two warning distances for a speed.
({double first, double second}) thresholds(double speedKmh, WarnConfig config) {
  final v = math.max(0.0, speedKmh) / 3.6;
  final first = math.min(config.maxFirstM, math.max(config.minFirstM, v * config.leadFirstS)) * config.scale;
  final second = math.min(first * 0.6, math.max(config.minSecondM, v * config.leadSecondS) * config.scale);
  return (first: first, second: second);
}

class _State {
  int stage = 0;
  bool seenAhead = false;
}

/// Decides when to warn: only for objects in the direction of travel and on the own track, a first warning early
/// enough for the speed, a second one shortly before, never twice. Pure state machine: no clock, no I/O.
///
/// Interim solution: the library has no road geometry for items, so "own carriageway" is a narrow corridor along the
/// heading. It cannot tell a hazard on the opposite lane from one on the own lane at long range. The proper filter
/// belongs into the client library; this class is the one place to replace (wish to the library).
class WarningEngine {
  WarningEngine([this.config = defaultWarnConfig]);
  final WarnConfig config;
  final Map<String, _State> _stages = {};

  void reset() => _stages.clear();

  List<WarnEvent> update(Fix fix, List<WarnCandidate> candidates) {
    final speed = fix.speedKmh;
    final heading = fix.heading;
    if (speed == null || heading == null) return const [];
    final here = LatLng(fix.lat, fix.lng);
    final t = thresholds(speed, config);
    final first = t.first;
    final second = t.second;
    final moving = speed >= config.minSpeedKmh;
    final events = <({double along, WarnEvent event})>[];
    final present = <String>{};

    for (final c in candidates) {
      present.add(c.id);
      double? along; // metres to the object along the heading; null = not on the track
      var behind = false;
      if (c is PointCandidate) {
        final rel = alongCross(here, heading, LatLng(c.lat, c.lng));
        final lateral = math.min(config.lateralMaxM, math.max(config.lateralMinM, rel.along.abs() * config.lateralFactor));
        along = rel.cross <= lateral ? rel.along : null;
        behind = rel.along < -config.passedM && rel.cross <= lateral;
      } else {
        along = rayEntryDistance(here, heading, (c as ZoneCandidate).ring);
      }

      final isZone = c is ZoneCandidate;
      final kind = isZone ? WarnKind.zone : WarnKind.point;
      final state = _stages[c.id] ?? _State();
      final source = isZone
          ? WarnSource.zone
          : ((c as PointCandidate).source == 'camera' ? WarnSource.camera : WarnSource.hazard);

      if (along != null && along >= 0 && along <= first) {
        if (moving) {
          if (along <= second && state.stage < 2) {
            state.stage = 2;
            events.add((
              along: along,
              event: WarnNow(
                level: WarnLevel.second,
                id: c.id,
                kind: kind,
                category: c.category,
                source: source,
                distanceM: isZone ? null : jsRound(along),
              ),
            ));
          } else if (along > second && state.stage < 1) {
            state.stage = 1;
            events.add((
              along: along,
              event: WarnNow(
                level: WarnLevel.first,
                id: c.id,
                kind: kind,
                category: c.category,
                source: source,
                distanceM: isZone ? null : jsRound(along),
              ),
            ));
          }
        }
        state.seenAhead = true;
        _stages[c.id] = state;
      } else if (state.seenAhead && (behind || (isZone && along == null))) {
        // it was ahead of us and now it is behind us (or the zone is left)
        events.add((
          along: -1,
          event: Passed(id: c.id, kind: kind, category: c.category, source: source, reachedSecond: state.stage >= 2),
        ));
        _stages.remove(c.id);
      } else if (along == null || along > first * 1.6 || along < -2000) {
        // far away or off the track again: forget, so it can warn anew on a later approach
        if (!state.seenAhead || along == null || along > first * 1.6) _stages.remove(c.id);
      }
    }

    _stages.removeWhere((id, _) => !present.contains(id));
    // stable sort by distance, like Array.prototype.sort
    final indexed = [for (var i = 0; i < events.length; i++) (i, events[i])];
    indexed.sort((a, b) {
      final c = a.$2.along.compareTo(b.$2.along);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2.event];
  }
}
