import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:tn_core/tn_core.dart';

import 'app_config.dart';
import 'display_update_source.dart';

/// Where the display firmware releases come from: the display project's GitHub releases. Only https, only on a tap or on the
/// user's automatic-check setting; the request carries the app's name in the User-Agent and nothing else (no identifier).
class DisplayUpdateHttp implements DisplayUpdateSource {
  DisplayUpdateHttp({String? base}) : base = base ?? displayUpdateBase;

  final String base;

  Uri get _manifestUri => Uri.parse('$base/releases/latest/download/manifest.json');

  Uri _imageUri(DisplayManifest m) => Uri.parse('$base/releases/download/fw-v${m.version}/${m.imageFile}');

  Uri get _signatureUri => Uri.parse('$base/releases/latest/download/manifest.json.sig');

  @override
  Future<FetchedManifest> manifest() async {
    final bytes = await _get(_manifestUri, maxBytes: 64 * 1024);
    final m = DisplayManifest.tryParse(utf8.decode(bytes, allowMalformed: true));
    if (m == null) throw const UpdateFetchException(UpdateFetchProblem.badAnswer);
    // No signature file (404) is an unsigned release; any other failure is a failure.
    String? sig;
    try {
      sig = utf8.decode(await _get(_signatureUri, maxBytes: 4 * 1024), allowMalformed: true);
    } on UpdateFetchException catch (e) {
      if (e.problem != UpdateFetchProblem.notFound) rethrow;
    }
    final trusted = [for (final k in displayTrustedKeys) ?parsePublicKey(k)];
    return FetchedManifest(m, verifyManifestSignature(bytes, sig, trusted));
  }

  @override
  Future<Uint8List> image(DisplayManifest m, {void Function(int received, int total)? onProgress}) =>
      _get(_imageUri(m), maxBytes: displayImageSlotBytes, expected: m.imageSize, onProgress: onProgress);

  Future<Uint8List> _get(Uri uri, {required int maxBytes, int? expected, void Function(int, int)? onProgress}) async {
    if (uri.scheme != 'https') throw const UpdateFetchException(UpdateFetchProblem.badAnswer);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = 'TNViewer/$appVersion (+$sourceRepoUrl)';
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode == 404) throw const UpdateFetchException(UpdateFetchProblem.notFound);
      if (response.statusCode != 200) throw const UpdateFetchException(UpdateFetchProblem.badAnswer);
      if (response.contentLength > maxBytes) throw const UpdateFetchException(UpdateFetchProblem.tooLarge);
      final out = BytesBuilder(copy: false);
      var got = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        got += chunk.length;
        if (got > maxBytes) throw const UpdateFetchException(UpdateFetchProblem.tooLarge);
        out.add(chunk);
        onProgress?.call(got, expected ?? response.contentLength);
      }
      return out.takeBytes();
    } on UpdateFetchException {
      rethrow;
    } on SocketException {
      throw const UpdateFetchException(UpdateFetchProblem.offline);
    } on TimeoutException {
      throw const UpdateFetchException(UpdateFetchProblem.offline);
    } on HandshakeException {
      throw const UpdateFetchException(UpdateFetchProblem.offline);
    } on HttpException {
      throw const UpdateFetchException(UpdateFetchProblem.badAnswer);
    } finally {
      client.close(force: true);
    }
  }
}
