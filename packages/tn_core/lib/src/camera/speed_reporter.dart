import '../drive/geo.dart';
import '../drive/units.dart';
import 'sign_recognizer.dart';

/// What the speed reporter did with a speed sign.
enum SpeedAction {
  /// Nothing: switched off, too uncertain, no heading, the car turned off, no data, or already handled on this trip.
  skipped,

  /// The database holds the same limit for the road after the sign: nothing to correct.
  agreed,

  /// The database holds another limit after the sign: "that limit is wrong" was proposed with the camera's value.
  corrected,

  /// The database holds no limit there: waiting for the end of the stretch (the next limit sign) to propose the stretch.
  deferred,

  /// A stretch without a limit on record was proposed.
  reported,
}

/// The limit the database holds for a road.
typedef DatabaseLimit = ({num value, SpeedUnit unit});

class SpeedReporterConfig {
  const SpeedReporterConfig({
    this.minFrames = 4,
    this.minConfidence = 0.85,
    this.checkAfterM = 60,
    this.giveUpAfterM = 400,
    this.maxTurnDeg = 25,
    this.dedupeM = 60,
    this.maxPerTrip = 20,
    this.minStretchM = 30,
    this.maxStretchM = 5000,
  });

  /// As strict as the other signs: a wrong proposal reaches everyone's database.
  final int minFrames;
  final double minConfidence;

  /// The database is asked this far after the sign: a speed sign stands where the road's limit changes, so right at the sign the
  /// database may still hold the old limit (the positions are rough). The car's own position then is on the right road.
  final double checkAfterM;

  /// A sign whose check did not happen within this distance is dropped (the car must have left the road).
  final double giveUpAfterM;

  /// The car must still drive in about the direction it had at the sign (it did not turn off at a junction).
  final double maxTurnDeg;
  final double dedupeM;
  final int maxPerTrip;
  final double minStretchM;
  final double maxStretchM;
}

/// Feeds the database's speed limits from what the camera read, automatically but carefully. The same switch as for the other signs.
///
/// * Some way after the sign, the database is asked for the road's limit at the car's position:
///   * the same value -> nothing to do;
///   * another value -> "that limit is wrong" is proposed with the camera's value, at the car's position;
///   * none, and the offline data covers the spot -> the stretch from this sign to the next limit sign is proposed once that sign is
///     read (the length is never guessed).
/// * A proposal is one voice: it only counts when other devices agree.
///
/// The camera cannot read additional plates ("bei Nässe", "Mo-Fr 7-17 Uhr", "Schule"): a limit that holds only at certain times is
/// proposed as if it held always. That is the known weak spot, and why only what several devices agree on counts.
class SpeedLimitReporter {
  SpeedLimitReporter({
    required this.readLimit,
    required this.covered,
    required this.reportWrong,
    required this.reportInterval,
    required this.enabled,
    this.config = const SpeedReporterConfig(),
  });

  /// The limit the database holds for the road at a position in a direction of travel; null = none on record.
  final Future<DatabaseLimit?> Function(double lat, double lng, double heading) readLimit;

  /// Whether the offline data answers for the spot (so that "none" means none on record and not "unknown").
  final Future<bool> Function(double lat, double lng) covered;

  /// "That limit is wrong": queues a proposal; resolves true when it was queued.
  final Future<bool> Function(double lat, double lng, int kmh) reportWrong;

  /// "No limit on record": queues a proposal for the stretch between two points; resolves true when it was queued.
  final Future<bool> Function(({double lat, double lng}) from, ({double lat, double lng}) to, int kmh) reportInterval;

  /// The owner's switch for sending anything.
  final bool Function() enabled;

  final SpeedReporterConfig config;

  final List<RecognizedSign> _waiting = [];
  final Map<String, RecognizedSign> _open = {};
  final Map<String, RecognizedSign> _ended = {}; // the id of the sign that ended a stretch -> the stretch's start
  final List<({int kmh, double lat, double lng})> _handled = [];
  int _count = 0;

  int get handled => _count;

  void reset() {
    _waiting.clear();
    _open.clear();
    _ended.clear();
    _handled.clear();
    _count = 0;
  }

  bool _nearHandled(int kmh, double lat, double lng) {
    for (final h in _handled) {
      if (h.kmh == kmh && distanceMeters(LatLng(h.lat, h.lng), LatLng(lat, lng)) <= config.dedupeM) return true;
    }
    return false;
  }

  /// A sign went out of sight, its reading is final now. A speed sign is checked once the car is [SpeedReporterConfig.checkAfterM] past
  /// it; a sign that ended a stretch which waited for its end completes that stretch (only now are its frames and confidence known).
  Future<SpeedAction> onFinished(RecognizedSign s) async {
    final ended = _ended.remove(s.id);
    if (ended != null) return _complete(ended, s);
    final kmh = s.speedKmh;
    if (kmh == null || !enabled() || s.heading == null) return SpeedAction.skipped;
    if (s.frames < config.minFrames || s.confidence < config.minConfidence) return SpeedAction.skipped;
    if (_count >= config.maxPerTrip || _nearHandled(kmh, s.roadLat, s.roadLng)) return SpeedAction.skipped;
    _waiting.add(s);
    return SpeedAction.deferred;
  }

  /// A position of the car; [odoM] is the trip's odometer. Signs that are far enough behind are checked now.
  Future<List<SpeedAction>> onFix({required double lat, required double lng, required double? heading, required double odoM}) async {
    final out = <SpeedAction>[];
    for (final s in List.of(_waiting)) {
      final passed = odoM - s.signOdoM;
      if (passed < config.checkAfterM) continue;
      _waiting.remove(s);
      if (passed > config.giveUpAfterM || !enabled()) {
        out.add(SpeedAction.skipped);
        continue;
      }
      out.add(await _check(s, lat, lng, heading ?? s.heading!));
    }
    return out;
  }

  Future<SpeedAction> _check(RecognizedSign s, double lat, double lng, double heading) async {
    final kmh = s.speedKmh!;
    if (_angleBetween(heading, s.heading!) > config.maxTurnDeg) return SpeedAction.skipped; // turned off: another road
    if (_count >= config.maxPerTrip || _nearHandled(kmh, s.roadLat, s.roadLng)) return SpeedAction.skipped;
    final DatabaseLimit? db;
    try {
      db = await readLimit(lat, lng, heading);
    } catch (_) {
      return SpeedAction.skipped; // without the database's view nothing is sent: it could contradict it
    }
    if (db == null) {
      final bool known;
      try {
        known = await covered(lat, lng);
      } catch (_) {
        return SpeedAction.skipped;
      }
      if (!known) return SpeedAction.skipped; // "no limit" may only mean "no data here"
      _open[s.id] = s;
      return SpeedAction.deferred;
    }
    if (db.unit != SpeedUnit.kmh) return SpeedAction.skipped;
    _handled.add((kmh: kmh, lat: s.roadLat, lng: s.roadLng));
    if (db.value.round() == kmh) return SpeedAction.agreed;
    final ok = await _safe(() => reportWrong(lat, lng, kmh));
    if (ok) _count++;
    return ok ? SpeedAction.corrected : SpeedAction.skipped;
  }

  /// [start] was replaced by [end] (another limit, or the end of all limits). A stretch that waited for this is proposed as soon as
  /// [end] has gone out of sight and its reading is final.
  Future<SpeedAction> onStretchEnded(RecognizedSign start, RecognizedSign end) async {
    if (start.speedKmh == null) return SpeedAction.skipped;
    _waiting.remove(start); // it ended before the check: too short to say anything about
    if (_open.remove(start.id) == null || !enabled()) return SpeedAction.skipped;
    if (end.speedKmh == null && end.vz != '282') return SpeedAction.skipped;
    _ended[end.id] = start;
    return SpeedAction.deferred;
  }

  Future<SpeedAction> _complete(RecognizedSign start, RecognizedSign end) async {
    final kmh = start.speedKmh!;
    if (!enabled() || _count >= config.maxPerTrip) return SpeedAction.skipped;
    if (end.heading == null || end.frames < config.minFrames || end.confidence < config.minConfidence) return SpeedAction.skipped;
    final length = end.signOdoM - start.signOdoM;
    if (length < config.minStretchM || length > config.maxStretchM) return SpeedAction.skipped;
    _handled.add((kmh: kmh, lat: start.roadLat, lng: start.roadLng));
    final ok = await _safe(() => reportInterval((lat: start.roadLat, lng: start.roadLng), (lat: end.roadLat, lng: end.roadLng), kmh));
    if (ok) _count++;
    return ok ? SpeedAction.reported : SpeedAction.skipped;
  }

  Future<bool> _safe(Future<bool> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return false;
    }
  }
}

double _angleBetween(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}
