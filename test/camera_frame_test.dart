import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tnviewer/services/camera_frame.dart';

/// A 4 x 2 BGRA image whose pixels carry their own number in the red channel (0..7), row after row.
List<RawPlane> numbered({int rowPad = 0}) {
  const w = 4, h = 2;
  final stride = w * 4 + rowPad;
  final bytes = Uint8List(stride * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * stride + x * 4;
      bytes[i] = 0; // blue
      bytes[i + 1] = 0; // green
      bytes[i + 2] = y * w + x; // red
      bytes[i + 3] = 255;
    }
  }
  return [RawPlane(bytes, stride, 4)];
}

List<int> reds(SignFrameLike f) => [for (var i = 0; i < f.width * f.height; i++) f.rgb[i * 3]];

typedef SignFrameLike = ({int width, int height, Uint8List rgb});

SignFrameLike frame(int turns, {int rowPad = 0}) {
  final f = frameFromRaw(width: 4, height: 2, format: RawFormat.bgra8888, planes: numbered(rowPad: rowPad), quarterTurns: turns);
  return (width: f.width, height: f.height, rgb: f.rgb);
}

void main() {
  group('frameFromRaw, BGRA', () {
    test('no turn keeps the picture, and a padded row is read by its stride', () {
      final f = frame(0);
      expect((f.width, f.height), (4, 2));
      expect(reds(f), [0, 1, 2, 3, 4, 5, 6, 7]);
      expect(reds(frame(0, rowPad: 8)), [0, 1, 2, 3, 4, 5, 6, 7]);
    });

    test('one clockwise turn: the left column becomes the top row, read bottom to top', () {
      // src:  0 1 2 3      out (2 wide, 4 high):  4 0
      //       4 5 6 7                             5 1
      //                                           6 2
      //                                           7 3
      final f = frame(1);
      expect((f.width, f.height), (2, 4));
      expect(reds(f), [4, 0, 5, 1, 6, 2, 7, 3]);
    });

    test('two turns turn the picture upside down', () {
      expect(reds(frame(2)), [7, 6, 5, 4, 3, 2, 1, 0]);
    });

    test('three turns (one counter-clockwise)', () {
      final f = frame(3);
      expect((f.width, f.height), (2, 4));
      expect(reds(f), [3, 7, 2, 6, 1, 5, 0, 4]);
    });

    test('a wide picture is thinned out to the maximum width', () {
      const w = 2000, h = 400;
      final bytes = Uint8List(w * h * 4);
      final f = frameFromRaw(width: w, height: h, format: RawFormat.bgra8888, planes: [RawPlane(bytes, w * 4, 4)], quarterTurns: 0, maxWidth: 960);
      expect(f.width, lessThanOrEqualTo(960));
      expect(f.width, 666); // every third pixel: the smallest whole step that fits
      expect(f.height, 133);
    });
  });

  group('frameFromRaw, YUV420', () {
    test('grey (neutral colour planes) stays grey, red stays red', () {
      const w = 4, h = 4;
      Uint8List plane(int value, int len) => Uint8List(len)..fillRange(0, len, value);
      final grey = frameFromRaw(
        width: w,
        height: h,
        format: RawFormat.yuv420,
        planes: [RawPlane(plane(100, w * h), w, 1), RawPlane(plane(128, 4), 2, 1), RawPlane(plane(128, 4), 2, 1)],
        quarterTurns: 0,
      );
      expect(grey.rgb.sublist(0, 3), [100, 100, 100]);
      // BT.601 red: Y 76, U 85, V 255
      final red = frameFromRaw(
        width: w,
        height: h,
        format: RawFormat.yuv420,
        planes: [RawPlane(plane(76, w * h), w, 1), RawPlane(plane(85, 4), 2, 1), RawPlane(plane(255, 4), 2, 1)],
        quarterTurns: 0,
      );
      expect(red.rgb[0], greaterThan(240));
      expect(red.rgb[1], lessThan(15));
      expect(red.rgb[2], lessThan(15));
    });

    test('colour planes with interleaved samples (pixel stride 2) are read right', () {
      const w = 2, h = 2;
      // one chroma sample per 2 x 2 block, stored every second byte
      final y = RawPlane(Uint8List.fromList([76, 76, 76, 76]), w, 1);
      final u = RawPlane(Uint8List.fromList([85, 0]), 2, 2);
      final v = RawPlane(Uint8List.fromList([255, 0]), 2, 2);
      final f = frameFromRaw(width: w, height: h, format: RawFormat.yuv420, planes: [y, u, v], quarterTurns: 0);
      expect(f.rgb[0], greaterThan(240));
    });
  });

  test('how often the image must be turned from the sensor and the way the phone is held', () {
    expect(quarterTurnsFor(sensorOrientation: 90, deviceOrientationDegrees: 0), 1); // portrait: turn the landscape sensor image
    expect(quarterTurnsFor(sensorOrientation: 90, deviceOrientationDegrees: 90), 0);
    expect(quarterTurnsFor(sensorOrientation: 90, deviceOrientationDegrees: 180), 3);
    expect(quarterTurnsFor(sensorOrientation: 90, deviceOrientationDegrees: 270), 2);
  });
}
