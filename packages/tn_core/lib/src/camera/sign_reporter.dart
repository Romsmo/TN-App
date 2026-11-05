import '../drive/geo.dart';
import '../tn/types.dart';
import 'sign_recognizer.dart';

/// What the reporter did with a recognised sign.
enum SignAction {
  /// Nothing: switched off, too uncertain, no heading, a sign the camera cannot report, or already handled on this trip.
  skipped,

  /// The database already holds the sign here: the camera confirmed it.
  voted,

  /// The database had nothing here (or something else): the sign was proposed.
  reported,

  /// The database has nothing, but the sign covers a stretch whose end has not been seen yet: waiting for the end sign.
  deferred,
}

/// Signs that stand at one place: they are proposed with one point.
const Set<String> pointSignVz = {'101-11', '102', '131', '151', '267', '280', '281', '282'};

/// Signs that cover a stretch which an end sign closes: proposed with two points once the end was seen.
const Set<String> endedStretchVz = {'276', '277'};

/// The signs that end such a stretch (or replace it).
const Set<String> stretchEndVz = {'276', '277', '280', '281', '282'};

/// Signs that carry a value the camera cannot read (a weight, a height ...) or that open a zone: never proposed.
const Set<String> neverReportedVz = {'253', '262-5', '263-8', '264-2', '265-3', '266-10', '273-70', '270'};

/// The strictness of what leaves the phone. Stricter than what is only shown: a wrong sign on the display lasts a few hundred
/// metres, a wrong proposal reaches everyone's database.
class ReporterConfig {
  const ReporterConfig({
    this.minFrames = 4,
    this.minConfidence = 0.85,
    this.sameSpotM = 80,
    this.dedupeM = 60,
    this.maxPerTrip = 40,
    this.minStretchM = 30,
    this.maxStretchM = 5000,
  });

  final int minFrames;
  final double minConfidence;

  /// A database entry within this many metres (along the road) of the camera's sign is the same sign.
  final double sameSpotM;

  /// The same sign proposed or confirmed within this many metres is not handled twice.
  final double dedupeM;
  final int maxPerTrip;
  final double minStretchM;
  final double maxStretchM;
}

/// Feeds the database from what the camera recognised, automatically but carefully.
///
/// * The database holds the sign here -> the camera confirms it (a vote), once per entry and trip.
/// * The database holds nothing, or something else that conflicts -> the sign is proposed. A proposal is one voice: it only counts
///   as confirmed when other devices agree, so a misreading cannot enter the shown data on its own.
/// * A stretch sign (no overtaking) is proposed only when its end was seen too: the length is never guessed.
/// * Warnings that stand over a stretch the camera cannot measure, signs with a value, and everything the reporter is unsure about
///   are left out.
///
/// The camera cannot read additional plates ("Mo-Fr 7-17 Uhr"): a proposal carries no time window. That is the known weak spot,
/// and why only a sign that several devices agree on counts.
class SignReporter {
  SignReporter({
    required this.readDb,
    required this.report,
    required this.vote,
    required this.enabled,
    this.config = const ReporterConfig(),
  });

  /// The entries at a place, unconfirmed ones included, so that an own proposal can be confirmed too.
  final Future<List<ContextSign>> Function(double lat, double lng, double heading) readDb;

  /// Queues a proposal (the request of `reportContextSign`); resolves true when it was queued.
  final Future<bool> Function(Map<String, Object?> request) report;

  /// Queues a confirmation of an entry; resolves true when it was queued.
  final Future<bool> Function(String id, bool agrees) vote;

  /// The owner's switch for sending anything.
  final bool Function() enabled;

  final ReporterConfig config;

  final List<({String vz, double lat, double lng})> _handled = [];
  final Set<String> _voted = {};
  final Map<String, RecognizedSign> _pending = {};
  final Map<String, RecognizedSign> _ended = {};
  int _count = 0;

  /// Failed attempts are not retried: a write that did not queue is dropped, the next sign gets its own try.
  int get handled => _count;

  void reset() {
    _handled.clear();
    _voted.clear();
    _pending.clear();
    _ended.clear();
    _count = 0;
  }

  bool _nearHandled(String vz, double lat, double lng) {
    for (final h in _handled) {
      if (h.vz == vz && _metres(h.lat, h.lng, lat, lng) <= config.dedupeM) return true;
    }
    return false;
  }

  /// A sign went out of sight. [carLat]/[carLng] is where the car is now, [startsInM] where the sign is relative to it (negative =
  /// behind).
  Future<SignAction> onFinished(RecognizedSign s, {required double carLat, required double carLng, required double startsInM}) async {
    final heading = s.heading;
    if (!enabled() || heading == null) return SignAction.skipped;
    if (s.frames < config.minFrames || s.confidence < config.minConfidence) return SignAction.skipped;
    if (neverReportedVz.contains(s.vz) || _count >= config.maxPerTrip) return SignAction.skipped;
    if (_nearHandled(s.vz, s.lat, s.lng)) return SignAction.skipped;

    final List<ContextSign> db;
    try {
      db = await readDb(carLat, carLng, heading);
    } catch (_) {
      return SignAction.skipped; // without the database's view nothing is sent: it could duplicate or contradict it
    }
    final type = s.signType;
    // The same sign in the database: the same type at the same spot, or one that is in force here (a repeated sign).
    ContextSign? same;
    for (final e in db) {
      final near = (e.startsInM - startsInM).abs() <= config.sameSpotM;
      final inForce = e.startsInM <= 0 && (e.endsInM == null || e.endsInM! > 0);
      if (e.signType == type && (near || inForce)) {
        same ??= e;
        break;
      }
    }
    _handled.add((vz: s.vz, lat: s.lat, lng: s.lng));

    if (same != null) {
      if (!_voted.add(same.id)) return SignAction.skipped;
      final ok = await _safe(() => vote(same!.id, true));
      if (ok) _count++;
      return ok ? SignAction.voted : SignAction.skipped;
    }
    // Here the database has nothing of this sign: either nothing at all, or something else (a different sign of the same family).
    // In both cases the camera's reading is proposed; the node merges it with what it holds, and it counts only when others agree.
    if (pointSignVz.contains(s.vz)) {
      final ok = await _safe(() => report({
            'signType': type,
            'from': {'lat': s.lat, 'lng': s.lng},
            'direction': 'along',
            'heading': heading,
          }));
      if (ok) _count++;
      return ok ? SignAction.reported : SignAction.skipped;
    }
    if (endedStretchVz.contains(s.vz)) {
      _pending[s.id] = s;
      return _maybeReportStretch(s.id);
    }
    return SignAction.skipped;
  }

  /// [start] was ended by [end] (another sign that conflicts with it). A pending stretch is proposed now.
  Future<SignAction> onStretchEnded(RecognizedSign start, RecognizedSign end) async {
    if (!enabled() || !endedStretchVz.contains(start.vz) || !stretchEndVz.contains(end.vz)) return SignAction.skipped;
    _ended[start.id] = end;
    return _maybeReportStretch(start.id);
  }

  Future<SignAction> _maybeReportStretch(String id) async {
    final start = _pending[id];
    final end = _ended[id];
    if (start == null || end == null) return start != null ? SignAction.deferred : SignAction.skipped;
    _pending.remove(id);
    _ended.remove(id);
    final heading = start.heading;
    if (heading == null || end.heading == null || _count >= config.maxPerTrip) return SignAction.skipped;
    final length = end.signOdoM - start.signOdoM;
    if (length < config.minStretchM || length > config.maxStretchM) return SignAction.skipped;
    final ok = await _safe(() => report({
          'signType': start.signType,
          'from': {'lat': start.lat, 'lng': start.lng},
          'to': {'lat': end.lat, 'lng': end.lng},
          'direction': 'along',
          'heading': heading,
        }));
    if (ok) _count++;
    return ok ? SignAction.reported : SignAction.skipped;
  }

  Future<bool> _safe(Future<bool> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return false;
    }
  }
}

double _metres(double lat1, double lng1, double lat2, double lng2) => distanceMeters(LatLng(lat1, lng1), LatLng(lat2, lng2));
