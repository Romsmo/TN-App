import 'dart:math' as math;
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tn_core/tn_core.dart';

const cal = CameraCalibration(vanishingX: 0.5, horizonY: 0.5, hFovDeg: 65, aspect: 16 / 9, calibratedAtMs: 1);

/// A grey road scene, 640 x 360.
SignFrame scene({void Function(void Function(int x, int y, int r, int g, int b) put)? draw}) {
  const w = 640, h = 360;
  final rgb = Uint8List(w * h * 3);
  for (var i = 0; i < w * h; i++) {
    rgb[i * 3] = 120;
    rgb[i * 3 + 1] = 125;
    rgb[i * 3 + 2] = 130;
  }
  draw?.call((x, y, r, g, b) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    final i = (y * w + x) * 3;
    rgb[i] = r;
    rgb[i + 1] = g;
    rgb[i + 2] = b;
  });
  return SignFrame(w, h, rgb);
}

void ring(void Function(int, int, int, int, int) put, int cx, int cy, double radius, double thick) {
  for (var y = cy - radius.ceil() - 1; y <= cy + radius.ceil() + 1; y++) {
    for (var x = cx - radius.ceil() - 1; x <= cx + radius.ceil() + 1; x++) {
      final d = math.sqrt(math.pow(x - cx, 2) + math.pow(y - cy, 2));
      if (d <= radius && d >= radius - thick) {
        put(x, y, 200, 20, 25);
      } else if (d < radius - thick) {
        put(x, y, 245, 245, 245);
      }
    }
  }
}

void triangle(void Function(int, int, int, int, int) put, int cx, int top, int side, int thick) {
  final height = (side * 0.866).round();
  for (var y = top; y < top + height; y++) {
    final half = ((y - top) / height * side / 2);
    for (var x = (cx - half).floor(); x <= (cx + half).ceil(); x++) {
      final edge = math.min(math.min(x - (cx - half), (cx + half) - x), (top + height - 1 - y).toDouble());
      put(x, y, edge < thick ? 200 : 245, edge < thick ? 20 : 245, edge < thick ? 25 : 245);
    }
  }
}

class FakeClassifier implements SignClassifier {
  FakeClassifier(this.answer);
  final int Function(Float32List crop) answer;
  int calls = 0;
  int crops = 0;

  @override
  int get size => 16;

  @override
  int get classCount => 4;

  @override
  Future<List<List<double>>> classify(List<Float32List> c) async {
    calls++;
    crops += c.length;
    return [
      for (final crop in c)
        [for (var k = 0; k < 4; k++) k == answer(crop) ? 0.95 : 0.05 / 3],
    ];
  }
}

void main() {
  group('CandidateFinder', () {
    const finder = CandidateFinder();

    test('finds a ring and a triangle above the horizon, with their boxes', () {
      final frame = scene(draw: (put) {
        ring(put, 400, 120, 24, 5);
        triangle(put, 150, 90, 56, 6);
      });
      final found = finder.find(frame, cal);
      expect(found, hasLength(2));
      final r = found.firstWhere((c) => c.centerX > 300);
      expect(r.centerX, closeTo(400, 4));
      expect(r.centerY, closeTo(120, 4));
      expect(r.width, closeTo(49, 6));
      final t = found.firstWhere((c) => c.centerX < 300);
      expect(t.centerX, closeTo(150, 5));
    });

    test('ignores red below the horizon, too small a spot and a plain red rectangle', () {
      final frame = scene(draw: (put) {
        ring(put, 300, 280, 24, 5); // a ring on the road (a tail light, a bonnet ornament), below the horizon
        ring(put, 100, 100, 3, 1); // far too small
        for (var y = 80; y < 110; y++) {
          for (var x = 500; x < 580; x++) {
            put(x, y, 200, 20, 25); // a red banner: filled, not a ring, aspect off
          }
        }
      });
      expect(finder.find(frame, cal), isEmpty);
    });

    test('a calibrated horizon moves where signs are looked for', () {
      final frame = scene(draw: (put) => ring(put, 300, 280, 24, 5));
      expect(finder.find(frame, cal.copyWith(horizonY: 0.8)), hasLength(1));
    });

    test('orange, brown and dark red are not sign red', () {
      expect(CandidateFinder.isSignRed(200, 20, 25), isTrue);
      expect(CandidateFinder.isSignRed(230, 120, 30), isFalse); // orange
      expect(CandidateFinder.isSignRed(110, 70, 50), isFalse); // brown
      expect(CandidateFinder.isSignRed(60, 5, 5), isFalse); // too dark
      expect(CandidateFinder.isSignRed(180, 170, 170), isFalse); // washed out
    });

    test('a full-size frame is looked at in a smaller one', () {
      const w = 1280, h = 720;
      final rgb = Uint8List(w * h * 3);
      for (var i = 0; i < w * h; i++) {
        rgb[i * 3] = rgb[i * 3 + 1] = rgb[i * 3 + 2] = 125;
      }
      void put(int x, int y) {
        final i = (y * w + x) * 3;
        rgb[i] = 200;
        rgb[i + 1] = 20;
        rgb[i + 2] = 25;
      }

      for (var y = 150; y < 250; y++) {
        for (var x = 700; x < 800; x++) {
          final d = math.sqrt(math.pow(x - 750, 2) + math.pow(y - 200, 2));
          if (d <= 50 && d >= 40) put(x, y);
        }
      }
      final found = const CandidateFinder().find(SignFrame(w, h, rgb), cal);
      expect(found, hasLength(1));
      expect(found.single.centerX, closeTo(750, 8));
      expect(found.single.width, closeTo(100, 12));
    });
  });

  group('FinderSignDetector', () {
    // classes: 0 = 276, 1 = a speed limit the app does not use, 2 = 123, 3 = not a sign
    const labels = <String?>['276', null, '123'];

    SignFrame twoSigns() => scene(draw: (put) {
          ring(put, 400, 120, 24, 5);
          triangle(put, 150, 90, 56, 6);
        });

    test('reads the candidates and returns detections with normalised boxes', () async {
      // the ring is mostly white inside, the triangle too: tell them apart by the position of the crop's centre pixel row sums
      final classifier = FakeClassifier((crop) => 0);
      final detector = FinderSignDetector(classifier: classifier, labels: labels, calibration: () => cal);
      final out = await detector.detect(twoSigns());
      expect(classifier.calls, 1);
      expect(classifier.crops, 2);
      expect(out, hasLength(2));
      expect(out.every((d) => d.vz == '276' && d.confidence == 0.95), isTrue);
      final d = out.firstWhere((d) => d.x > 0.5);
      expect(d.x, closeTo(400 / 640, 0.01));
      expect(d.y, closeTo(120 / 360, 0.02));
      expect(d.w, closeTo(49 / 640, 0.012));
    });

    test('"not a sign", an unused class and a doubtful reading give nothing', () async {
      for (final cls in [1, 3]) {
        final detector = FinderSignDetector(classifier: FakeClassifier((_) => cls), labels: labels, calibration: () => cal);
        expect(await detector.detect(twoSigns()), isEmpty);
      }
      final unsure = FinderSignDetector(classifier: FakeClassifier((_) => 0), labels: labels, calibration: () => cal, minProbability: 0.99);
      expect(await unsure.detect(twoSigns()), isEmpty);
    });

    test('a frame without candidates does not call the classifier', () async {
      final classifier = FakeClassifier((_) => 0);
      final detector = FinderSignDetector(classifier: classifier, labels: labels, calibration: () => cal);
      expect(await detector.detect(scene()), isEmpty);
      expect(classifier.calls, 0);
    });

    test('a class that is not in the display catalogue is dropped', () async {
      final detector = FinderSignDetector(classifier: FakeClassifier((_) => 0), labels: const ['274', null, '123'], calibration: () => cal);
      expect(await detector.detect(twoSigns()), isEmpty);
    });
  });

  test('a crop is the candidate with a margin, scaled to the classifier size', () {
    final frame = scene(draw: (put) => ring(put, 320, 100, 20, 4));
    final c = const CandidateFinder().find(frame, cal).single;
    final crop = cropForClassifier(frame, c, 16);
    expect(crop, hasLength(16 * 16 * 3));
    // the middle of the crop is the white inside of the ring, the corner is the grey road
    expect(crop[(8 * 16 + 8) * 3], greaterThan(0.9));
    expect(crop[0], closeTo(120 / 255, 0.01));
  });
}
