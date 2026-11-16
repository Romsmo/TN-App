import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tn_core/tn_core.dart';

import 'camera_detector_test.dart' show FakeClassifier, ring, scene;

/// A locator that answers with peaks at the given frame boxes (in its own input pixels) and nothing elsewhere.
class FakeLocator implements SignLocator {
  FakeLocator(this.peaks, {this.inputSize = 160, this.stride = 4});
  final List<LocatedBox> peaks;
  Float32List? lastInput;

  @override
  final int inputSize;
  @override
  final int stride;

  @override
  Future<Float32List> locate(Float32List rgb) async {
    lastInput = rgb;
    final g = inputSize ~/ stride;
    final out = Float32List(g * g * 5);
    for (final p in peaks) {
      final ix = (p.cx / stride).floor().clamp(0, g - 1);
      final iy = (p.cy / stride).floor().clamp(0, g - 1);
      final i = (iy * g + ix) * 5;
      out[i] = p.score;
      out[i + 1] = p.w / stride;
      out[i + 2] = p.h / stride;
      out[i + 3] = p.cx / stride - ix;
      out[i + 4] = p.cy / stride - iy;
      // a weaker neighbour, as a real heatmap has around a peak
      if (ix + 1 < g) out[(iy * g + ix + 1) * 5] = p.score * 0.6;
    }
    return out;
  }
}

void main() {
  group('letterbox', () {
    test('a wide frame fills the top of the square, the rest stays black; the scale maps back', () {
      final frame = scene(draw: (put) {
        for (var y = 0; y < 360; y++) {
          for (var x = 0; x < 640; x++) {
            put(x, y, x < 320 ? 255 : 0, 0, 0); // left half red, right half black
          }
        }
      });
      final lb = letterbox(frame, 160);
      expect(lb.scale, closeTo(0.25, 1e-9));
      expect(lb.contentWidth, 160);
      expect(lb.contentHeight, 90);
      expect(lb.pixels[(10 * 160 + 20) * 3], closeTo(1, 0.01)); // red on the left
      expect(lb.pixels[(10 * 160 + 140) * 3], closeTo(0, 0.01)); // black on the right
      expect(lb.pixels[(120 * 160 + 20) * 3 + 1], 0); // below the content: black
    });

    test('a tall frame fills the left side', () {
      final frame = SignFrame(90, 160, Uint8List(90 * 160 * 3)..fillRange(0, 90 * 160 * 3, 200));
      final lb = letterbox(frame, 64);
      expect(lb.contentWidth, 36);
      expect(lb.contentHeight, 64);
      expect(lb.pixels[(30 * 64 + 10) * 3], closeTo(200 / 255, 0.01));
      expect(lb.pixels[(30 * 64 + 50) * 3], 0);
    });

    test('a thin line survives the scaling as an average, not as luck of the sample point', () {
      final frame = scene(draw: (put) {
        for (var x = 0; x < 640; x++) {
          put(x, 100, 255, 255, 255);
        }
      });
      final lb = letterbox(frame, 160); // four source rows per target row: the white row lifts its target row by a quarter
      final row = (100 / 4).floor();
      expect(lb.pixels[(row * 160 + 50) * 3], closeTo((3 * 120 + 255) / 4 / 255, 0.02));
    });
  });

  group('decodeHeatmap', () {
    test('local maxima above the threshold become boxes in input pixels; neighbours and weak cells do not', () async {
      final loc = FakeLocator([
        const LocatedBox(score: 0.9, cx: 50, cy: 30, w: 20, h: 20),
        const LocatedBox(score: 0.2, cx: 100, cy: 60, w: 12, h: 12),
      ]);
      final out = await loc.locate(Float32List(160 * 160 * 3));
      final boxes = decodeHeatmap(out, grid: 40, stride: 4, threshold: 0.3);
      expect(boxes, hasLength(1));
      expect(boxes.single.cx, closeTo(50, 0.01));
      expect(boxes.single.cy, closeTo(30, 0.01));
      expect(boxes.single.w, closeTo(20, 0.01));
      expect(decodeHeatmap(out, grid: 40, stride: 4, threshold: 0.1), hasLength(2));
    });

    test('two boxes that mostly cover each other leave the stronger one', () {
      final g = 10;
      final out = Float32List(g * g * 5);
      void peak(int ix, int iy, double s) {
        final i = (iy * g + ix) * 5;
        out[i] = s;
        out[i + 1] = 6;
        out[i + 2] = 6;
        out[i + 3] = 0.5;
        out[i + 4] = 0.5;
      }

      peak(4, 4, 0.8);
      peak(6, 4, 0.5); // 8 px to the right of a 24 px box: IoU about 0.5
      peak(9, 9, 0.6); // far away
      final boxes = decodeHeatmap(out, grid: g, stride: 4, threshold: 0.3, nmsIou: 0.4);
      expect(boxes.map((b) => (b.score * 10).round()), [8, 6]);
    });

    test('an empty heatmap gives nothing, and so does the wrong length', () {
      expect(decodeHeatmap(Float32List(100 * 5), grid: 10, stride: 4), isEmpty);
    });
  });

  group('HeatmapSignDetector', () {
    const labels = <String?>['276', null, '123'];

    test('a located sign is cut from the full frame and read; the boxes are kept for the camera view', () async {
      final frame = scene(draw: (put) => ring(put, 400, 120, 24, 5)); // 640 x 360, a ring 48 px wide at (400, 120)
      // the locator's square is 160: scale 0.25, so the ring sits at (100, 30), 12 px wide
      final loc = FakeLocator([const LocatedBox(score: 0.9, cx: 100, cy: 30, w: 12, h: 12)]);
      final classifier = FakeClassifier((_) => 0);
      final d = HeatmapSignDetector(locator: loc, classifier: classifier, labels: labels);
      final out = await d.detect(frame);
      expect(loc.lastInput, hasLength(160 * 160 * 3));
      expect(out, hasLength(1));
      expect(out.single.vz, '276');
      expect(out.single.x, closeTo(400 / 640, 0.02));
      expect(out.single.y, closeTo(120 / 360, 0.02));
      expect(out.single.w, closeTo(48 / 640, 0.02));
      expect(out.single.frameAspect, closeTo(640 / 360, 1e-9));
      expect(d.lastBoxes.single.read, isTrue);
      expect(d.lastCandidates.single.width, 48);
      expect(classifier.crops, 1);
    });

    test('a peak in the black band, a tiny box and a weak score are dropped before the classifier', () async {
      final frame = scene();
      final loc = FakeLocator([
        const LocatedBox(score: 0.9, cx: 80, cy: 140, w: 12, h: 12), // below the 90 px of content
        const LocatedBox(score: 0.9, cx: 40, cy: 40, w: 1, h: 1), // 4 px in the frame
        const LocatedBox(score: 0.1, cx: 120, cy: 40, w: 12, h: 12),
      ]);
      final classifier = FakeClassifier((_) => 0);
      final d = HeatmapSignDetector(locator: loc, classifier: classifier, labels: labels);
      expect(await d.detect(frame), isEmpty);
      expect(classifier.calls, 0);
      expect(d.lastBoxes, isEmpty);
    });

    test('"not a sign" from the classifier leaves an unread box', () async {
      final frame = scene(draw: (put) => ring(put, 400, 120, 24, 5));
      final loc = FakeLocator([const LocatedBox(score: 0.9, cx: 100, cy: 30, w: 12, h: 12)]);
      final d = HeatmapSignDetector(locator: loc, classifier: FakeClassifier((_) => 3), labels: labels);
      expect(await d.detect(frame), isEmpty);
      expect(d.lastBoxes.single.read, isFalse);
    });

    test('a locator that answers with the wrong size gives nothing instead of garbage', () async {
      final loc = FakeLocator([], inputSize: 160, stride: 8); // 20 x 20 cells, but the detector expects 40 x 40 for stride 4?
      final d = HeatmapSignDetector(locator: _WrongLength(loc), classifier: FakeClassifier((_) => 0), labels: labels);
      expect(await d.detect(scene()), isEmpty);
    });
  });
}

class _WrongLength implements SignLocator {
  _WrongLength(this.inner);
  final FakeLocator inner;
  @override
  int get inputSize => inner.inputSize;
  @override
  int get stride => 4;
  @override
  Future<Float32List> locate(Float32List rgb) async => Float32List(7);
}
