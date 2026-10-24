import 'dart:typed_data';

import 'package:tn_core/tn_core.dart';

/// Why fetching a release failed (never the response itself).
enum UpdateFetchProblem { notFound, offline, badAnswer, tooLarge }

class UpdateFetchException implements Exception {
  const UpdateFetchException(this.problem);
  final UpdateFetchProblem problem;
  @override
  String toString() => 'update fetch failed: ${problem.name}';
}

/// Where display firmware releases come from. The device implementation reads the display project's GitHub releases.
abstract interface class DisplayUpdateSource {
  Future<DisplayManifest> manifest();
  Future<Uint8List> image(DisplayManifest m, {void Function(int received, int total)? onProgress});
}
