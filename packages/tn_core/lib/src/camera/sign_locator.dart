import 'dart:math' as math;
import 'dart:typed_data';

import 'sign_detector.dart';
import 'sign_recognizer.dart';

/// A network that looks at a whole picture and marks where traffic signs are (`tool/signs_model/detect_train.py`): the input is an
/// [inputSize] x [inputSize] RGB picture (0..1), the output one record of five numbers per cell of a grid with [stride] pixels per
/// cell: score (0..1), width, height (in cells), and the sign centre's offset inside the cell (0..1 each).
abstract interface class SignLocator {
  int get inputSize;
  int get stride;

  /// [rgb] has inputSize * inputSize * 3 values; the result (inputSize / stride)^2 * 5 values, cell after cell, row after row.
  Future<Float32List> locate(Float32List rgb);
}

/// The frame scaled so that its longer side is [size] and put at the top left of a black [size] x [size] square (the shape the
/// locator takes); [scale] maps frame pixels to square pixels.
class Letterbox {
  const Letterbox({required this.pixels, required this.scale, required this.contentWidth, required this.contentHeight});
  final Float32List pixels;
  final double scale;
  final int contentWidth;
  final int contentHeight;
}

/// Scales [frame] into the square (a box average over the source pixels of every target pixel, so that a thin ring of a far sign
/// does not vanish between sample points).
Letterbox letterbox(SignFrame frame, int size) {
  final scale = size / math.max(frame.width, frame.height);
  final cw = math.max(1, (frame.width * scale).round());
  final ch = math.max(1, (frame.height * scale).round());
  final out = Float32List(size * size * 3);
  final rgb = frame.rgb;
  final fw = frame.width;
  for (var y = 0; y < ch; y++) {
    final sy0 = (y * frame.height / ch).floor();
    final sy1 = math.max(sy0 + 1, ((y + 1) * frame.height / ch).floor());
    for (var x = 0; x < cw; x++) {
      final sx0 = (x * fw / cw).floor();
      final sx1 = math.max(sx0 + 1, ((x + 1) * fw / cw).floor());
      var r = 0, g = 0, b = 0, n = 0;
      for (var sy = sy0; sy < sy1; sy++) {
        var i = (sy * fw + sx0) * 3;
        for (var sx = sx0; sx < sx1; sx++) {
          r += rgb[i];
          g += rgb[i + 1];
          b += rgb[i + 2];
          i += 3;
          n++;
        }
      }
      final o = (y * size + x) * 3;
      out[o] = r / (255 * n);
      out[o + 1] = g / (255 * n);
      out[o + 2] = b / (255 * n);
    }
  }
  return Letterbox(pixels: out, scale: scale, contentWidth: cw, contentHeight: ch);
}

/// A sign the locator found, in pixels of its input square: centre, size, score.
class LocatedBox {
  const LocatedBox({required this.score, required this.cx, required this.cy, required this.w, required this.h});
  final double score;
  final double cx;
  final double cy;
  final double w;
  final double h;

  double get left => cx - w / 2;
  double get top => cy - h / 2;
  double get right => cx + w / 2;
  double get bottom => cy + h / 2;
}

double boxIou(LocatedBox a, LocatedBox b) {
  final iw = math.max(0.0, math.min(a.right, b.right) - math.max(a.left, b.left));
  final ih = math.max(0.0, math.min(a.bottom, b.bottom) - math.max(a.top, b.top));
  final inter = iw * ih;
  return inter / math.max(1e-6, a.w * a.h + b.w * b.h - inter);
}

/// The signs in a locator output: every cell whose score is at least [threshold] and the largest among its eight neighbours, the
/// best [topK] of them, without boxes that mostly cover one another (IoU over [nmsIou]). The same rules as `decode` in
/// `detect_train.py`, so that the numbers measured there hold here.
List<LocatedBox> decodeHeatmap(Float32List out, {required int grid, required int stride, double threshold = 0.3, int topK = 20, double nmsIou = 0.5}) {
  const ch = 5;
  final found = <LocatedBox>[];
  for (var y = 0; y < grid; y++) {
    for (var x = 0; x < grid; x++) {
      final s = out[(y * grid + x) * ch];
      if (s < threshold) continue;
      var isMax = true;
      for (var dy = -1; dy <= 1 && isMax; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= grid || ny >= grid) continue;
          if (out[(ny * grid + nx) * ch] > s) {
            isMax = false;
            break;
          }
        }
      }
      if (!isMax) continue;
      final i = (y * grid + x) * ch;
      found.add(LocatedBox(
        score: s,
        cx: (x + out[i + 3]) * stride,
        cy: (y + out[i + 4]) * stride,
        w: out[i + 1] * stride,
        h: out[i + 2] * stride,
      ));
    }
  }
  found.sort((a, b) => b.score.compareTo(a.score));
  final keep = <LocatedBox>[];
  for (final f in found) {
    if (keep.length >= topK) break;
    if (keep.every((k) => boxIou(f, k) < nmsIou)) keep.add(f);
  }
  return keep;
}

/// The detector the app runs when it has the locator model: the locator marks the signs in the whole frame, the classifier reads
/// each one from a crop of the full-resolution frame. Signs without red (the end of a limit, the end of all bans) are found too.
class HeatmapSignDetector implements SignDetector {
  HeatmapSignDetector({
    required this.locator,
    required this.classifier,
    required this.labels,
    this.minScore = 0.3,
    this.minProbability = 0.6,
    this.minSidePx = 6,
    this.topK = 20,
  }) : assert(labels.length == classifier.classCount - 1);

  final SignLocator locator;
  final SignClassifier classifier;
  final List<String?> labels;

  /// The locator's score a region needs, and the classifier's probability a reading needs.
  final double minScore;
  final double minProbability;

  /// A region smaller than this in the frame is not read (the classifier cannot tell anything from a few pixels).
  final int minSidePx;
  final int topK;

  @override
  List<SignBox> lastBoxes = const [];

  /// What the locator found in the latest frame, in frame pixels (before the classifier), for tests and the camera view.
  List<SignCandidate> lastCandidates = const [];

  @override
  Future<List<RawDetection>> detect(SignFrame frame) async {
    final size = locator.inputSize;
    final lb = letterbox(frame, size);
    final out = await locator.locate(lb.pixels);
    final grid = size ~/ locator.stride;
    if (out.length != grid * grid * 5) {
      lastBoxes = const [];
      lastCandidates = const [];
      return const [];
    }
    final boxes = decodeHeatmap(out, grid: grid, stride: locator.stride, threshold: minScore, topK: topK);
    final candidates = <SignCandidate>[];
    for (final b in boxes) {
      if (b.cx > lb.contentWidth || b.cy > lb.contentHeight) continue; // in the black band, not in the picture
      final w = (b.w / lb.scale).round();
      final h = (b.h / lb.scale).round();
      if (w < minSidePx || h < minSidePx) continue;
      final left = (b.cx / lb.scale - w / 2).round().clamp(0, math.max(0, frame.width - w)).toInt();
      final top = (b.cy / lb.scale - h / 2).round().clamp(0, math.max(0, frame.height - h)).toInt();
      candidates.add(SignCandidate(left, top, w, h, (b.score * 1000).round()));
    }
    lastCandidates = candidates;
    if (candidates.isEmpty) {
      lastBoxes = const [];
      return const [];
    }
    final read = await classifyCandidates(frame, candidates, classifier, labels, minProbability);
    lastBoxes = read.boxes;
    return read.detections;
  }
}
