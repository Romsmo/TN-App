import 'dart:math' as math;
import 'dart:typed_data';

import '../display/sign_columns.dart';
import 'camera_calibration.dart';
import 'sign_recognizer.dart';
import 'speed_signs.dart';

/// One camera frame, upright, as plain RGB (three bytes per pixel, row after row).
class SignFrame {
  SignFrame(this.width, this.height, this.rgb) : assert(rgb.length >= width * height * 3);
  final int width;
  final int height;
  final Uint8List rgb;
}

/// A region of a frame that may hold a sign, in pixels.
class SignCandidate {
  const SignCandidate(this.left, this.top, this.width, this.height, this.redPixels);
  final int left;
  final int top;
  final int width;
  final int height;
  final int redPixels;

  double get centerX => left + width / 2;
  double get centerY => top + height / 2;
}

/// Tells what a cropped candidate shows. The implementation runs a small neural network on the device (see `tool/signs_model`); the
/// pipeline around it is plain Dart and testable with a fake one.
abstract interface class SignClassifier {
  /// For each crop (a [size] x [size] RGB image, values 0..1, row after row), the probability of each class; the last class
  /// is "not a sign". Each list has [classCount] entries.
  Future<List<List<double>>> classify(List<Float32List> crops);

  int get size;
  int get classCount;
}

/// Finds signs in a frame and says what they are.
abstract interface class SignDetector {
  Future<List<RawDetection>> detect(SignFrame frame);
}

/// Finds the places in a frame that may hold a sign with a red border (warning triangles, prohibition rings, the no-entry disc):
/// red pixels are grouped, and a group is kept when its size, shape and the share of red look like a sign and it sits where a sign
/// can be: not in the lower part of the picture (road, bonnet) and not far below the horizon.
///
/// "Red" is a share of the pixel's own brightness (see [isSignRed]), so a sign in shade or at dusk counts as well as one in the sun;
/// the ring is thickened by a pixel before grouping so that a ring broken by a glare or a branch stays one piece.
///
/// What it does not find: signs without red (the end-of-ban signs are white and grey). Those need a different finder.
class CandidateFinder {
  const CandidateFinder({
    this.analysisWidth = 480,
    this.minSidePx = 7,
    this.minFill = 0.08,
    this.maxFill = 0.92,
    this.minAspect = 0.6,
    this.maxAspect = 1.65,
    this.maxCandidates = 10,
    this.belowHorizonMargin = 0.12,
    this.maxAboveHorizon = 0.55,
    this.maxCentreY = 0.72,
    this.maxSideShare = 0.3,
  });

  /// The frame is looked at in this width (a box average of the pixels); the crops come from the full frame.
  final int analysisWidth;
  final int minSidePx;
  final double minFill;
  final double maxFill;
  final double minAspect;
  final double maxAspect;
  final int maxCandidates;

  /// How far below the horizon (share of the image height) a candidate's centre may be (signs on low posts, in a bend, a horizon that
  /// is not known yet), how far above it, and the lowest the centre may be in the picture at all.
  final double belowHorizonMargin;
  final double maxAboveHorizon;
  final double maxCentreY;

  /// A region wider than this share of the frame is a wall or a car, not a sign.
  final double maxSideShare;

  /// True for a "sign red": the pixel is red against its own brightness, so it does not matter how bright the light is. The red of a
  /// sign ring is rarely the pure red of a sunny day: measured on 2,878 real German circle signs, the ring median is about
  /// (120, 53, 47) and its red over the larger of green and blue about 2.2 times; a fixed bright threshold missed nearly all of them.
  /// Red must lead both other channels by at least 16 % of the pixel's brightness sum, green and blue must be about equal (that keeps
  /// orange out; on the real rings it costs nothing), and the pixel must not be nearly black.
  static bool isSignRed(int r, int g, int b) {
    final lead = math.min(r - g, r - b);
    // green and blue are about equal on a sign (orange, a cone or a lorry side has far less blue; pink far less green)
    return r >= 40 && lead * 25 >= 4 * (r + g + b + 1) && (g - b).abs() * 5 <= 2 * lead + 50;
  }

  List<SignCandidate> find(SignFrame frame, CameraCalibration cal) {
    final step = math.max(1, frame.width ~/ analysisWidth);
    final w = frame.width ~/ step;
    final h = frame.height ~/ step;
    if (w < 8 || h < 8) return const [];
    final mask = Uint8List(w * h);
    final rgb = frame.rgb;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        // the pixel in the middle of the step x step block stands for it: cheap, and enough for a border several pixels thick
        final sx = x * step + step ~/ 2;
        final sy = y * step + step ~/ 2;
        final i = (sy * frame.width + sx) * 3;
        if (isSignRed(rgb[i], rgb[i + 1], rgb[i + 2])) mask[y * w + x] = 1;
      }
    }
    _thicken(mask, w, h);
    final seen = Uint8List(w * h);
    final stack = Int32List(w * h);
    final out = <SignCandidate>[];
    for (var start = 0; start < w * h; start++) {
      if (mask[start] == 0 || seen[start] == 1) continue;
      var sp = 0;
      stack[sp++] = start;
      seen[start] = 1;
      var minX = w, maxX = 0, minY = h, maxY = 0, count = 0;
      while (sp > 0) {
        final p = stack[--sp];
        final px = p % w;
        final py = p ~/ w;
        count++;
        if (px < minX) minX = px;
        if (px > maxX) maxX = px;
        if (py < minY) minY = py;
        if (py > maxY) maxY = py;
        // eight neighbours: the thin ring of a far sign breaks into diagonal steps
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nx = px + dx;
            final ny = py + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            final n = ny * w + nx;
            if (mask[n] == 1 && seen[n] == 0) {
              seen[n] = 1;
              stack[sp++] = n;
            }
          }
        }
      }
      final bw = maxX - minX + 1;
      final bh = maxY - minY + 1;
      if (bw < minSidePx || bh < minSidePx) continue;
      if (bw > maxSideShare * w || bh > maxSideShare * w) continue;
      final aspect = bw / bh;
      if (aspect < minAspect || aspect > maxAspect) continue;
      final fill = count / (bw * bh);
      if (fill < minFill || fill > maxFill) continue;
      // where the candidate sits: above the horizon (see the class comment)
      final cy = (minY + bh / 2) / h;
      if (cy > cal.horizonY + belowHorizonMargin || cy < cal.horizonY - maxAboveHorizon || cy > maxCentreY) continue;
      out.add(SignCandidate(minX * step, minY * step, bw * step, bh * step, count));
    }
    out.sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
    return out.length > maxCandidates ? out.sublist(0, maxCandidates) : out;
  }

  /// Every red pixel also marks its eight neighbours (in place).
  static void _thicken(Uint8List mask, int w, int h) {
    final src = Uint8List.fromList(mask);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (src[y * w + x] == 0) continue;
        for (var dy = -1; dy <= 1; dy++) {
          final ny = y + dy;
          if (ny < 0 || ny >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx;
            if (nx >= 0 && nx < w) mask[ny * w + nx] = 1;
          }
        }
      }
    }
  }
}

/// A box of the latest frame, for the camera view: a region the finder proposed and what the classifier made of it.
class SignBox {
  const SignBox({required this.x, required this.y, required this.w, required this.h, required this.confidence, this.vz});

  /// Centre and size, normalised to the upright frame.
  final double x;
  final double y;
  final double w;
  final double h;

  /// The class's catalogue number when the classifier took it for a sign the app uses (above the confidence it needs), else null.
  final String? vz;
  final double confidence;

  bool get read => vz != null;
}

/// A crop of [frame] around [c] (with a margin for the sign's white background), scaled to [size] x [size], RGB 0..1.
Float32List cropForClassifier(SignFrame frame, SignCandidate c, int size, {double margin = 0.15}) {
  final side = math.max(c.width, c.height) * (1 + 2 * margin);
  final left = c.centerX - side / 2;
  final top = c.centerY - side / 2;
  final out = Float32List(size * size * 3);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final sx = (left + (x + 0.5) * side / size).floor().clamp(0, frame.width - 1);
      final sy = (top + (y + 0.5) * side / size).floor().clamp(0, frame.height - 1);
      final i = (sy * frame.width + sx) * 3;
      final o = (y * size + x) * 3;
      out[o] = frame.rgb[i] / 255;
      out[o + 1] = frame.rgb[i + 1] / 255;
      out[o + 2] = frame.rgb[i + 2] / 255;
    }
  }
  return out;
}

/// The detector the app runs: the candidate finder proposes regions, the classifier reads them, and what it reads as a sign the
/// display can draw, or as a speed limit, leaves as a detection.
class FinderSignDetector implements SignDetector {
  FinderSignDetector({
    required this.classifier,
    required this.labels,
    required this.calibration,
    this.finder = const CandidateFinder(),
    this.minProbability = 0.6,
  }) : assert(labels.length == classifier.classCount - 1);

  final SignClassifier classifier;

  /// The catalogue number of each class (`276`, `142-10`; a speed limit is `274-<km/h>`), or null for a class the app does not use (a
  /// direction sign). One entry per class except the last, which is "not a sign".
  final List<String?> labels;
  final CameraCalibration Function() calibration;
  final CandidateFinder finder;
  final double minProbability;

  /// Every region of the latest frame the finder proposed, with what it was read as (for the camera view).
  List<SignBox> lastBoxes = const [];

  @override
  Future<List<RawDetection>> detect(SignFrame frame) async {
    final cal = calibration();
    final candidates = finder.find(frame, cal);
    if (candidates.isEmpty) {
      lastBoxes = const [];
      return const [];
    }
    final crops = [for (final c in candidates) cropForClassifier(frame, c, classifier.size)];
    final probs = await classifier.classify(crops);
    final out = <RawDetection>[];
    final boxes = <SignBox>[];
    final aspect = frame.width / frame.height;
    for (var i = 0; i < candidates.length && i < probs.length; i++) {
      final p = probs[i];
      if (p.length != classifier.classCount) continue;
      var best = 0;
      for (var k = 1; k < p.length; k++) {
        if (p[k] > p[best]) best = k;
      }
      final c = candidates[i];
      final cx = c.centerX / frame.width, cy = c.centerY / frame.height, cw = c.width / frame.width, ch = c.height / frame.height;
      final vz = best >= labels.length || p[best] < minProbability ? null : labels[best]; // "not a sign" or unsure
      if (vz == null || (vzNrOf('DE:$vz') == null && !isSpeedVz(vz))) {
        boxes.add(SignBox(x: cx, y: cy, w: cw, h: ch, confidence: p[best]));
        continue;
      }
      boxes.add(SignBox(x: cx, y: cy, w: cw, h: ch, confidence: p[best], vz: vz));
      out.add(RawDetection(vz: vz, confidence: p[best], x: cx, y: cy, w: cw, h: ch, frameAspect: aspect));
    }
    lastBoxes = boxes;
    return out;
  }
}
