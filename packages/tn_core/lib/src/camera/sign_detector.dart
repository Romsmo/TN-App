import 'dart:math' as math;
import 'dart:typed_data';

import '../display/sign_columns.dart';
import 'camera_calibration.dart';
import 'sign_recognizer.dart';

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
/// can be, above the horizon (a sign hangs higher than the camera, so its centre is above the horizon at every distance).
///
/// What it does not find: signs without red (the end-of-ban signs are white and grey). Those need a different finder.
class CandidateFinder {
  const CandidateFinder({
    this.analysisWidth = 480,
    this.minSidePx = 9,
    this.minFill = 0.10,
    this.maxFill = 0.80,
    this.minAspect = 0.7,
    this.maxAspect = 1.45,
    this.maxCandidates = 6,
    this.aboveHorizonMargin = 0.02,
    this.maxAboveHorizon = 0.45,
  });

  /// The frame is looked at in this width (a box average of the pixels); the crops come from the full frame.
  final int analysisWidth;
  final int minSidePx;
  final double minFill;
  final double maxFill;
  final double minAspect;
  final double maxAspect;
  final int maxCandidates;

  /// How far below the horizon (share of the image height) a candidate's centre may be, and how far above it.
  final double aboveHorizonMargin;
  final double maxAboveHorizon;

  /// True for a "sign red": clearly red, not orange or brown, not dark, not washed out.
  static bool isSignRed(int r, int g, int b) => r >= 110 && r * 10 >= g * 28 && r * 10 >= b * 28 && (r - math.min(g, b)) >= 60;

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
      final aspect = bw / bh;
      if (aspect < minAspect || aspect > maxAspect) continue;
      final fill = count / (bw * bh);
      if (fill < minFill || fill > maxFill) continue;
      // where the candidate sits: above the horizon (see the class comment)
      final cy = (minY + bh / 2) / h;
      if (cy > cal.horizonY + aboveHorizonMargin || cy < cal.horizonY - maxAboveHorizon) continue;
      out.add(SignCandidate(minX * step, minY * step, bw * step, bh * step, count));
    }
    out.sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
    return out.length > maxCandidates ? out.sublist(0, maxCandidates) : out;
  }
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
/// display can draw leaves as a detection.
class FinderSignDetector implements SignDetector {
  FinderSignDetector({
    required this.classifier,
    required this.labels,
    required this.calibration,
    this.finder = const CandidateFinder(),
    this.minProbability = 0.6,
  }) : assert(labels.length == classifier.classCount - 1);

  final SignClassifier classifier;

  /// The catalogue number of each class (`276`, `142-10`), or null for a class the app does not use (a speed limit, a direction
  /// sign). One entry per class except the last, which is "not a sign".
  final List<String?> labels;
  final CameraCalibration Function() calibration;
  final CandidateFinder finder;
  final double minProbability;

  @override
  Future<List<RawDetection>> detect(SignFrame frame) async {
    final cal = calibration();
    final candidates = finder.find(frame, cal);
    if (candidates.isEmpty) return const [];
    final crops = [for (final c in candidates) cropForClassifier(frame, c, classifier.size)];
    final probs = await classifier.classify(crops);
    final out = <RawDetection>[];
    for (var i = 0; i < candidates.length && i < probs.length; i++) {
      final p = probs[i];
      if (p.length != classifier.classCount) continue;
      var best = 0;
      for (var k = 1; k < p.length; k++) {
        if (p[k] > p[best]) best = k;
      }
      if (best >= labels.length || p[best] < minProbability) continue; // "not a sign" or unsure
      final vz = labels[best];
      if (vz == null || vzNrOf('DE:$vz') == null) continue;
      final c = candidates[i];
      out.add(RawDetection(
        vz: vz,
        confidence: p[best],
        x: c.centerX / frame.width,
        y: c.centerY / frame.height,
        w: c.width / frame.width,
        h: c.height / frame.height,
      ));
    }
    return out;
  }
}
