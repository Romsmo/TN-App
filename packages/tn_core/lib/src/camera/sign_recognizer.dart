import 'dart:math' as math;

import 'package:tn_display_protocol/tn_display_protocol.dart' as d;

import '../display/sign_columns.dart';
import '../drive/fix.dart';
import '../drive/geo.dart';
import '../tn/types.dart';
import 'camera_calibration.dart';
import 'speed_signs.dart';

/// One sign the detector found in one camera frame. [vz] is the catalogue number (`276`, `142-10`), the box is normalised to the
/// upright frame: centre ([x], [y]) and size ([w], [h]).
class RawDetection {
  const RawDetection({required this.vz, required this.confidence, required this.x, required this.y, required this.w, required this.h});
  final String vz;
  final double confidence;
  final double x;
  final double y;
  final double w;
  final double h;
}

/// A sign the camera has recognised on the road, placed on it.
class RecognizedSign {
  RecognizedSign({
    required this.id,
    required this.vz,
    required this.signOdoM,
    required this.lat,
    required this.lng,
    required this.heading,
    required this.firstSeenMs,
    required this.lastSeenMs,
    required this.frames,
    required this.confidence,
  });

  final String id;

  /// Catalogue number without the country: `276`.
  final String vz;

  /// Where the sign stands, as metres driven on the trip's odometer (so "ahead" and "behind" stay right as the car moves).
  double signOdoM;

  /// The point on the road abreast of the sign (the car's line, no lateral offset): where a speed limit starts. Equal to the
  /// car's position when no heading is known.
  double roadLat = 0;
  double roadLng = 0;

  /// The sign's position and the direction the car drove in when it saw it. [heading] is null when the receiver gave none: then
  /// [lat]/[lng] are only the car's position and the sign must not be reported.
  double lat;
  double lng;
  double? heading;
  int firstSeenMs;
  int lastSeenMs;

  /// In how many frames it was seen, and the mean confidence of those frames.
  int frames;
  double confidence;

  /// The track has ended: the sign is out of sight (passed).
  bool finished = false;

  String get signType => 'DE:$vz';

  /// The limit in km/h when this is a speed-limit sign.
  int? get speedKmh => speedOfVz(vz);
}

/// The limit the camera read and that is in force now.
class RecognizedSpeed {
  const RecognizedSpeed({required this.id, required this.kmh, required this.startsInM});
  final String id;
  final int kmh;

  /// Where the sign stands relative to the car (negative = behind).
  final double startsInM;
}

/// How the recognition decides. The values are meant to be strict: a missing sign is better than an invented one.
class RecognizerConfig {
  const RecognizerConfig({
    this.minDetectionConfidence = 0.5,
    this.minFrames = 3,
    this.minMeanConfidence = 0.75,
    this.minShare = 0.7,
    this.maxGapMs = 1200,
    this.matchDistance = 0.12,
    this.maxBearingOffsetDeg = 35,
    this.minBoxWidth = 0.008,
    this.fixMaxAgeMs = 5000,
    this.warningShownM = 400,
    this.otherShownM = 2000,
    this.speedShownM = 1500,
    this.speedLeadM = 20,
    this.speedMinSpanM = 8,
    this.speedMaxSignWidthM = 1.5,
    this.speedMinSlopeShare = 0.6,
    this.speedKeepAfterDbChangeM = 50,
  });

  final double minDetectionConfidence;

  /// A sign is shown once the same reading was made in this many frames, with this mean confidence, and this share of all the
  /// track's frames agreeing.
  final int minFrames;
  final double minMeanConfidence;
  final double minShare;

  /// The sign is out of sight when it was not seen for this long.
  final int maxGapMs;

  /// How far apart (normalised image units) two boxes of the same sign in consecutive frames may be.
  final double matchDistance;

  /// A sign further off the direction of travel than this stands at a side road, not at ours.
  final double maxBearingOffsetDeg;
  final double minBoxWidth;

  /// A position older than this is not used to place a sign.
  final int fixMaxAgeMs;

  /// How long a recognised sign stays in the list when nothing replaces it: warnings are about the next stretch, a prohibition
  /// holds until its end sign (here: at most this far).
  final double warningShownM;
  final double otherShownM;

  /// A speed limit the camera read stays in force this far, unless another limit, the end of all limits, or a change of what the
  /// database holds for the road replaces it. (The camera does not see the end-of-limit signs, which have no red.)
  final double speedShownM;

  /// A limit counts from this far before its sign: the sign's position is an estimate, and the driver takes the limit at the sign.
  final double speedLeadM;

  /// A speed sign is accepted only when the track shows that it is a thing at the roadside the car drives up to, and not something
  /// that moves with the car (a speed sticker on the back of a lorry): over at least [speedMinSpanM] driven, the sign's apparent size
  /// must have grown at least [speedMinSlopeShare] of the rate a sign of [speedMaxSignWidthM] (the biggest real one) gives.
  final double speedMinSpanM;
  final double speedMaxSignWidthM;
  final double speedMinSlopeShare;

  /// A newer value of the database for the road gives way to a camera limit only for signs passed more than this far ago (the sign
  /// stands where the road's limit changes, and both positions are rough).
  final double speedKeepAfterDbChangeM;
}

class _Car {
  const _Car(this.pos, this.heading, this.odoM);
  final LatLng pos;
  final double? heading;
  final double odoM;
}

class _Track {
  _Track(this.id, this.firstMs);
  final int id;
  final int firstMs;
  int lastMs = 0;
  int frames = 0;
  final Map<String, double> score = {};
  final Map<String, int> count = {};
  double lastX = 0, lastY = 0, lastW = 0;
  double bestW = 0;
  _Car? bestCar;
  double bestBearingOffset = 0;
  double bestDistance = 0;
  bool bestChanged = false;
  RecognizedSign? sign;

  /// (odometer, apparent width) of every frame, for the check that a speed sign is approached.
  final List<({double odo, double w})> samples = [];

  String get leader => (score.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
}

/// Turns detections of single frames into signs on the road.
///
/// A detection alone proves nothing: the same sign must be seen in several frames and be read the same way. A sign is
/// placed from the frame in which it was biggest (the nearest), using the calibration for the angle and a typical sign size for
/// the distance. Position fixes come in separately; they give the odometer that keeps "where is the sign now" right.
class SignRecognizer {
  SignRecognizer({
    this.calibration = CameraCalibration.none,
    this.config = const RecognizerConfig(),
    this.onFinished,
    this.onStretchEnded,
  });

  CameraCalibration calibration;
  final RecognizerConfig config;

  /// A sign went out of sight: its position is as good as it gets.
  void Function(RecognizedSign sign)? onFinished;

  /// A sign that was in force is ended by another one that conflicts with it (the end of the overtaking ban, a different ban).
  void Function(RecognizedSign start, RecognizedSign end)? onStretchEnded;

  final List<_Track> _tracks = [];
  final List<RecognizedSign> _active = [];
  Fix? _fix;
  double _odoM = 0;
  int _nextId = 1;

  double get odometerM => _odoM;

  /// The recognised signs that are in force or just ahead, as entries like the library's (for the display's columns).
  List<ContextSign> get signs => [
        for (final s in _active)
          if (s.speedKmh == null)
            ContextSign(
              id: s.id,
              signType: s.signType,
              startsInM: s.signOdoM - _odoM,
              confirmed: true,
              confirmations: 1,
              fromCamera: true,
            ),
      ];

  /// The speed limit the camera read that applies now: the latest speed sign that is at the car or less than
  /// [RecognizerConfig.speedLeadM] ahead. Null when the camera has read none (or it ended).
  RecognizedSpeed? get speedLimit {
    RecognizedSign? best;
    for (final s in _active) {
      if (s.speedKmh == null || s.signOdoM - _odoM > config.speedLeadM) continue;
      if (best == null || s.signOdoM > best.signOdoM) best = s;
    }
    return best == null ? null : RecognizedSpeed(id: best.id, kmh: best.speedKmh!, startsInM: best.signOdoM - _odoM);
  }

  /// Drops the speed limits the car passed more than [passedM] ago: the database has a new value for the road, which is newer
  /// than the sign. Returns whether one was dropped.
  bool forgetSpeedPassedBeyond(double passedM) {
    final n = _active.length;
    _active.removeWhere((s) => s.speedKmh != null && _odoM - s.signOdoM > passedM);
    return _active.length != n;
  }

  List<RecognizedSign> get active => List.unmodifiable(_active);

  void reset() {
    _tracks.clear();
    _active.clear();
    _fix = null;
    _odoM = 0;
  }

  void onFix(Fix fix) {
    final prev = _fix;
    if (prev != null) {
      final m = distanceMeters(prev.point, fix.point);
      // a step within the receiver's noise is standing, not driving
      if (m >= 2) _odoM += m;
    }
    _fix = fix;
    _finishOld(fix.t);
    _expire();
  }

  /// The car's position, heading and odometer at [ms], from the last fix moved on with its speed; null without a recent fix.
  _Car? _carAt(int ms) {
    final fix = _fix;
    if (fix == null || (ms - fix.t).abs() > config.fixMaxAgeMs) return null;
    final dt = ((ms - fix.t) / 1000).clamp(0.0, 3.0);
    final mps = (fix.speedKmh ?? 0) / 3.6;
    final moved = mps * dt;
    final h = fix.heading;
    final pos = h != null && moved > 0 ? destination(fix.point, h, moved) : fix.point;
    return _Car(pos, h, _odoM + moved);
  }

  void onDetections(int frameMs, List<RawDetection> detections) {
    final car = _carAt(frameMs);
    if (car == null) return;
    for (final det in detections) {
      if (det.confidence < config.minDetectionConfidence || det.w < config.minBoxWidth) continue;
      if (vzNrOf('DE:${det.vz}') == null && !isSpeedVz(det.vz)) continue;
      final off = calibration.bearingOffsetDeg(det.x, det.y);
      if (off.abs() > config.maxBearingOffsetDeg) continue;
      final track = _match(det, frameMs) ?? _open(frameMs);
      _add(track, det, frameMs, car, off);
    }
    _promote(frameMs);
    _finishOld(frameMs);
    _expire();
  }

  _Track _open(int ms) {
    final t = _Track(_nextId++, ms);
    _tracks.add(t);
    return t;
  }

  /// The track a detection belongs to: the nearest box in the image, one detection per track and frame (two signs on one post are
  /// two tracks). A track whose reading is the same as the detection's counts as nearer. A detection that reads differently still
  /// joins a track at the same place: it is a vote against the reading, not a new sign.
  _Track? _match(RawDetection det, int ms) {
    _Track? best;
    var bestDist = config.matchDistance;
    for (final t in _tracks) {
      if (ms - t.lastMs > config.maxGapMs || t.lastMs == ms) continue;
      final ratio = t.lastW > 0 ? det.w / t.lastW : 1.0;
      if (ratio < 0.5 || ratio > 2) continue;
      final dist = math.sqrt(math.pow(det.x - t.lastX, 2) + math.pow(det.y - t.lastY, 2)) * (t.leader == det.vz ? 0.5 : 1);
      if (dist < bestDist) {
        bestDist = dist;
        best = t;
      }
    }
    return best;
  }

  void _add(_Track t, RawDetection det, int ms, _Car car, double bearingOffset) {
    t.lastMs = ms;
    t.frames++;
    t.score[det.vz] = (t.score[det.vz] ?? 0) + det.confidence;
    t.count[det.vz] = (t.count[det.vz] ?? 0) + 1;
    t.lastX = det.x;
    t.lastY = det.y;
    t.lastW = det.w;
    t.samples.add((odo: car.odoM, w: det.w));
    if (det.w > t.bestW) {
      t.bestW = det.w;
      t.bestCar = car;
      t.bestBearingOffset = bearingOffset;
      t.bestDistance = calibration.distanceToSignM(det.w);
      t.bestChanged = true;
    }
  }

  /// The sign's place from the track's best frame: along the road by the cosine of its angle, on the map by bearing and distance.
  void _place(_Track t, RecognizedSign s) {
    final car = t.bestCar!;
    final rad = t.bestBearingOffset * math.pi / 180;
    s.signOdoM = car.odoM + t.bestDistance * math.cos(rad);
    final h = car.heading;
    final pos = h != null ? destination(car.pos, (h + t.bestBearingOffset) % 360, t.bestDistance) : car.pos;
    s.lat = pos.lat;
    s.lng = pos.lng;
    s.heading = h;
    final road = h != null ? destination(car.pos, h, t.bestDistance * math.cos(rad)) : car.pos;
    s.roadLat = road.lat;
    s.roadLng = road.lng;
  }

  void _promote(int ms) {
    for (final t in _tracks) {
      final lead = t.leader;
      final n = t.count[lead] ?? 0;
      final mean = n == 0 ? 0.0 : (t.score[lead] ?? 0) / n;
      final share = t.frames == 0 ? 0.0 : n / t.frames;
      final known = t.sign;
      if (known == null) {
        if (n < config.minFrames || mean < config.minMeanConfidence || share < config.minShare || t.bestCar == null) continue;
        if (isSpeedVz(lead) && !_approached(t)) continue;
        final s = RecognizedSign(
          id: 'cam:${t.id}',
          vz: lead,
          signOdoM: 0,
          lat: 0,
          lng: 0,
          heading: null,
          firstSeenMs: t.firstMs,
          lastSeenMs: t.lastMs,
          frames: t.frames,
          confidence: mean,
        );
        _place(t, s);
        t.sign = s;
        t.bestChanged = false;
        _addActive(s);
      } else {
        known.frames = t.frames;
        known.lastSeenMs = t.lastMs;
        known.confidence = mean;
        if (t.bestChanged && t.bestCar != null) {
          _place(t, known);
          t.bestChanged = false;
        }
      }
    }
  }

  /// Whether the track's size grew as a fixed thing at the roadside does when the car drives up to it. 1 / width falls linearly with
  /// the distance driven, at a rate of 1 / (focal length x sign width); this fits that line and asks for a slope of at least a share of
  /// the one the biggest real sign gives. Something that keeps its distance to the car (the sticker on a lorry ahead) has a slope
  /// near zero.
  bool _approached(_Track t) {
    final pts = t.samples;
    if (pts.length < 3) return false;
    if (pts.last.odo - pts.first.odo < config.speedMinSpanM) return false;
    var mo = 0.0, mu = 0.0;
    for (final p in pts) {
      mo += p.odo;
      mu += 1 / p.w;
    }
    mo /= pts.length;
    mu /= pts.length;
    var cov = 0.0, vr = 0.0;
    for (final p in pts) {
      cov += (p.odo - mo) * (1 / p.w - mu);
      vr += (p.odo - mo) * (p.odo - mo);
    }
    if (vr <= 0) return false;
    final slope = -cov / vr; // 1 / width falls as the odometer rises
    final weakest = 1 / (config.speedMaxSignWidthM * calibration.focalInImageWidths);
    return slope >= config.speedMinSlopeShare * weakest;
  }

  /// A new sign takes the place of the ones it conflicts with (by the display's rules). The same sign seen again is the same
  /// sign, not the end of itself.
  void _addActive(RecognizedSign s) {
    for (final a in List.of(_active)) {
      if (a.vz == s.vz) {
        // a repetition or a track that broke: the sign that is in force stays, and this one is not shown twice
        return;
      }
    }
    for (final a in List.of(_active)) {
      if (d.signConflicts(s.vz, a.vz)) {
        _active.remove(a);
        onStretchEnded?.call(a, s);
      }
    }
    _active.add(s);
  }

  void _finishOld(int ms) {
    for (final t in List.of(_tracks)) {
      if (ms - t.lastMs <= config.maxGapMs) continue;
      _tracks.remove(t);
      final s = t.sign;
      if (s != null) {
        s.finished = true;
        onFinished?.call(s);
      }
    }
  }

  void _expire() {
    _active.removeWhere((s) {
      final major = d.signMajorOf(s.vz);
      final limit = s.speedKmh != null ? config.speedShownM : (major < 200 ? config.warningShownM : config.otherShownM);
      return _odoM - s.signOdoM > limit;
    });
  }
}
