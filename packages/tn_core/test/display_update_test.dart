import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tn_core/tn_core.dart';
import 'package:tn_display_protocol/tn_display_protocol.dart' as d;

String manifestJson({
  String version = '0.2.0',
  String? minFrom = '0.1.0',
  int size = 1000,
  String sha = '',
  int proto = 1,
  int minApp = 1,
  String file = 'tn-display-0.2.0.bin',
  Object? signature,
}) =>
    '{"manifestVersion":1,"firmware":{"version":"$version",${minFrom == null ? '' : '"minFromVersion":"$minFrom",'}"image":{"file":"$file","sizeBytes":$size,"sha256":"${sha.isEmpty ? '0' * 64 : sha}"}},'
    '"protocol":{"version":$proto,"minAppProtocol":$minApp},"changes":{"de":["a"],"en":["b"]},"signature":${signature ?? 'null'}}';

void main() {
  group('manifest', () {
    test('the example manifest of the display project parses', () {
      final text = File('../tn_display_protocol/contract/manifest.example.json').readAsStringSync();
      final m = DisplayManifest.tryParse(text)!;
      expect(m.version, '0.2.0');
      expect(m.imageSize, 1974912);
      expect(m.minFromVersion, '0.1.0');
      expect(m.changesDe, hasLength(2));
      expect(m.signed, isFalse);
    });

    test('anything unexpected is rejected, not guessed', () {
      expect(DisplayManifest.tryParse('not json'), isNull);
      expect(DisplayManifest.tryParse('{"manifestVersion":2}'), isNull);
      expect(DisplayManifest.tryParse(manifestJson(version: 'abc')), isNull);
      expect(DisplayManifest.tryParse(manifestJson(file: '../evil.bin')), isNull);
      expect(DisplayManifest.tryParse(manifestJson(file: 'a/b.bin')), isNull);
      expect(DisplayManifest.tryParse(manifestJson(size: 0)), isNull);
      expect(DisplayManifest.tryParse(manifestJson(sha: 'xyz')), isNull);
    });

    test('a named signature is noted but never counts as verified', () {
      final m = DisplayManifest.tryParse(manifestJson(signature: '{"alg":"ed25519","keyId":"k","file":"manifest.json.sig"}'))!;
      expect(m.signed, isTrue);
    });
  });

  group('versions and verdicts', () {
    test('compareVersions', () {
      expect(compareVersions('0.1.0', '0.2.0'), lessThan(0));
      expect(compareVersions('1.0.0', '0.9.9'), greaterThan(0));
      expect(compareVersions('v1.2.3', '1.2.3'), 0);
      expect(compareVersions('1.2.3-rc.1', '1.2.3'), 0);
      expect(compareVersions('x', '1.0.0'), isNull);
    });

    DisplayManifest m(String version, {String? minFrom = '0.1.0', int size = 1000, int proto = 1, int minApp = 1}) =>
        DisplayManifest.tryParse(manifestJson(version: version, minFrom: minFrom, size: size, proto: proto, minApp: minApp))!;

    test('available, up to date, in steps, app too old, not possible', () {
      expect(judgeUpdate(m('0.2.0'), installed: '0.1.0', hasOta: true), DisplayUpdateVerdict.available);
      expect(judgeUpdate(m('0.2.0'), installed: '0.2.0', hasOta: true), DisplayUpdateVerdict.upToDate);
      expect(judgeUpdate(m('0.2.0'), installed: '0.3.0', hasOta: true), DisplayUpdateVerdict.upToDate);
      expect(judgeUpdate(m('0.3.0', minFrom: '0.2.0'), installed: '0.1.0', hasOta: true), DisplayUpdateVerdict.needsIntermediate);
      expect(judgeUpdate(m('0.2.0', proto: 2), installed: '0.1.0', hasOta: true), DisplayUpdateVerdict.appTooOld);
      expect(judgeUpdate(m('0.2.0', minApp: 2), installed: '0.1.0', hasOta: true), DisplayUpdateVerdict.appTooOld);
      expect(judgeUpdate(m('0.2.0'), installed: '0.1.0', hasOta: false), DisplayUpdateVerdict.notPossible);
      expect(judgeUpdate(m('0.2.0', size: displayImageSlotBytes + 1), installed: '0.1.0', hasOta: true), DisplayUpdateVerdict.notPossible);
      expect(judgeUpdate(m('0.2.0'), installed: '', hasOta: true), DisplayUpdateVerdict.notPossible);
    });
  });

  test('the image is checked for size and SHA-256 before anything is sent', () {
    final image = Uint8List.fromList(List.generate(500, (i) => i % 251));
    final hex = d.sha256Of(image).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final ok = DisplayManifest.tryParse(manifestJson(size: 500, sha: hex))!;
    expect(checkImage(ok, image), ImageCheck.ok);
    expect(checkImage(ok, Uint8List.fromList([...image, 1])), ImageCheck.wrongSize);
    final flipped = Uint8List.fromList(image)..[10] ^= 1;
    expect(checkImage(ok, flipped), ImageCheck.wrongHash);
  });
}
