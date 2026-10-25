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

/// A manifest together with what the signature next to it says (checked against the keys the app trusts).
class FetchedManifest {
  const FetchedManifest(this.manifest, this.signature);
  final DisplayManifest manifest;
  final SignatureStatus signature;
}

/// Where display firmware releases come from. The device implementation reads the display project's GitHub releases.
abstract interface class DisplayUpdateSource {
  Future<FetchedManifest> manifest();
  Future<Uint8List> image(DisplayManifest m, {void Function(int received, int total)? onProgress});
}
