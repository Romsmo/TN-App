import 'dart:typed_data';

import 'package:tn_core/tn_core.dart';

/// One plane of a camera image as the platform hands it over.
class RawPlane {
  const RawPlane(this.bytes, this.bytesPerRow, this.bytesPerPixel);
  final Uint8List bytes;
  final int bytesPerRow;

  /// Distance in bytes between two pixels of the row (4 for BGRA, 1 or 2 for the colour planes of YUV); null where not given.
  final int? bytesPerPixel;
}

enum RawFormat { bgra8888, yuv420 }

/// Turns a camera image into an upright RGB [SignFrame], at most [maxWidth] wide.
///
/// [quarterTurns] is how often the image must be turned clockwise to stand upright (the sensor of a phone is built sideways).
/// The picture is thinned out by taking every n-th pixel: the finder and the classifier need a sign several pixels wide, not a
/// smooth picture, and a full frame of 1280 x 720 would cost too much on every pass.
SignFrame frameFromRaw({
  required int width,
  required int height,
  required RawFormat format,
  required List<RawPlane> planes,
  required int quarterTurns,
  int maxWidth = 960,
}) {
  final turns = quarterTurns % 4;
  final rw = turns.isOdd ? height : width;
  final rh = turns.isOdd ? width : height;
  final step = (rw / maxWidth).ceil().clamp(1, 16);
  final ow = rw ~/ step;
  final oh = rh ~/ step;
  final out = Uint8List(ow * oh * 3);

  final p0 = planes[0];
  final p1 = format == RawFormat.yuv420 ? planes[1] : null;
  final p2 = format == RawFormat.yuv420 ? planes[2] : null;

  var o = 0;
  for (var oy = 0; oy < oh; oy++) {
    final fy = oy * step;
    for (var ox = 0; ox < ow; ox++) {
      final fx = ox * step;
      final int sx, sy;
      switch (turns) {
        case 1:
          sx = fy;
          sy = height - 1 - fx;
        case 2:
          sx = width - 1 - fx;
          sy = height - 1 - fy;
        case 3:
          sx = width - 1 - fy;
          sy = fx;
        default:
          sx = fx;
          sy = fy;
      }
      if (format == RawFormat.bgra8888) {
        final i = sy * p0.bytesPerRow + sx * 4;
        out[o++] = p0.bytes[i + 2];
        out[o++] = p0.bytes[i + 1];
        out[o++] = p0.bytes[i];
      } else {
        final y = p0.bytes[sy * p0.bytesPerRow + sx];
        final ui = (sy >> 1) * p1!.bytesPerRow + (sx >> 1) * (p1.bytesPerPixel ?? 1);
        final vi = (sy >> 1) * p2!.bytesPerRow + (sx >> 1) * (p2.bytesPerPixel ?? 1);
        final u = p1.bytes[ui] - 128;
        final v = p2.bytes[vi] - 128;
        out[o++] = _clamp(y + ((1436 * v) >> 10));
        out[o++] = _clamp(y - ((352 * u + 731 * v) >> 10));
        out[o++] = _clamp(y + ((1815 * u) >> 10));
      }
    }
  }
  return SignFrame(ow, oh, out);
}

int _clamp(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);

/// How often a camera image must be turned clockwise to stand upright, from the sensor's built-in orientation and the way the
/// phone is held (both in degrees, as the camera plugin reports them: portrait up 0, landscape left 90, portrait down 180,
/// landscape right 270).
int quarterTurnsFor({required int sensorOrientation, required int deviceOrientationDegrees}) =>
    ((sensorOrientation - deviceOrientationDegrees + 360) % 360) ~/ 90;
