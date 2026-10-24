import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tn_core/tn_core.dart';

import 'vec.dart';

// The vectors are the server's `docs/join-code-vectors.json` (branch feat/join-code of Romsmo/Trafficnetwork), unchanged.
Uint8List hex(String s) => Uint8List.fromList([for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
String toHex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

const reasons = {
  'bad_check': JoinCodeProblem.badCheck,
  'newer_version': JoinCodeProblem.newerVersion,
  'bad_node': JoinCodeProblem.badNode,
  'bad_seed': JoinCodeProblem.badSeed,
  'bad_root': JoinCodeProblem.badRoot,
  'duplicate_parameter': JoinCodeProblem.duplicateParameter,
  'missing_parameter': JoinCodeProblem.missingParameter,
  'bad_version': JoinCodeProblem.badVersion,
};

void main() {
  final v = vec('join-code-vectors') as Map;

  test('HKDF-SHA256 matches RFC 5869 test case 1', () {
    final t = v['rfc5869TestCase1'] as Map;
    final okm = hkdfSha256(
      ikm: hex(t['ikm'] as String),
      salt: hex(t['salt'] as String),
      info: hex(t['info'] as String),
      length: t['length'] as int,
    );
    expect(toHex(okm), t['okm']);
  });

  group('valid vectors', () {
    for (final raw in v['valid'] as List) {
      final e = raw as Map;
      test(e['name'] as String, () {
        final code = JoinCode.parse(e['uri'] as String);
        expect(code.node, e['node']);
        expect(toHex(code.seed), e['seedHex']);
        expect(code.root == null ? null : toHex(code.root!), e['rootHex']);
        expect(code.credentials.clientId, e['id']);
        expect(code.credentials.clientSecret, e['secret']);
        expect(code.rootFingerprint, e['fingerprint']);
        expect(joinCheck(code.node, code.seed), e['c']);
        expect(code.toUri(), e['uri']);
        expect(code.address, 'https://${e['node']}');
        // building a code from the parts gives the same text
        expect(JoinCode(node: e['node'] as String, seed: hex(e['seedHex'] as String), root: e['rootHex'] == null ? null : hex(e['rootHex'] as String)).toUri(), e['uri']);
      });
    }
  });

  group('invalid vectors', () {
    for (final raw in v['invalid'] as List) {
      final e = raw as Map;
      test(e['name'] as String, () {
        final r = JoinCode.tryParse(e['uri'] as String);
        expect(r.code, isNull);
        expect(r.problem, reasons[e['reason']]);
      });
    }
  });

  group('edge cases never throw anything but a JoinCodeException', () {
    final v1 = ((v['valid'] as List).first as Map)['uri'] as String;
    final cases = <String, String>{
      'empty': '',
      'spaces': '   ',
      'only scheme': 'trafficnetwork://',
      'wrong scheme': 'https://join?v=1',
      'wrong host': v1.replaceFirst('://join?', '://other?'),
      '10000 characters': 'a' * 10000,
      'too long by one': '$v1&x=${'a' * 512}',
      'unicode': 'trafficnetwork://join?v=1&n=tn.exämple.org&k=ä&c=ä',
      'percent encoding': v1.replaceFirst('n=tn.example.org', 'n=tn%2Eexample%2Eorg'),
      'inner whitespace': v1.replaceFirst('&k=', '& k='),
      'newline inside': v1.replaceFirst('&k=', '\n&k='),
      'v without number': v1.replaceFirst('v=1', 'v=x'),
      'v with leading zero': v1.replaceFirst('v=1', 'v=01'),
      'v huge': v1.replaceFirst('v=1', 'v=9999999'),
      'duplicate unknown ok? no - unknown are ignored but k duplicated': '$v1&k=$v1',
      'port 0': v1.replaceFirst('tn.example.org', 'tn.example.org:0'),
      'port 65536': v1.replaceFirst('tn.example.org', 'tn.example.org:65536'),
      'no dot': v1.replaceFirst('tn.example.org', 'localhost'),
      'dot-localhost': v1.replaceFirst('tn.example.org', 'a.localhost'),
      'path in node': v1.replaceFirst('tn.example.org', 'tn.example.org/x'),
      'credentials in node': v1.replaceFirst('tn.example.org', 'user@tn.example.org'),
      'padded seed': v1.replaceFirst('&k=', '&k=='),
      'r too short': v1.replaceFirst('vr8', 'v'),
      'c lower case': v1.replaceFirst('3477B6GZ', '3477b6gz'),
    };
    cases.forEach((name, text) {
      test(name, () {
        final r = JoinCode.tryParse(text);
        expect(r.code, isNull, reason: name);
        expect(r.problem, isNotNull);
        expect(() => JoinCode.parse(text), throwsA(isA<JoinCodeException>()));
      });
    });

    test('surrounding whitespace and a trailing line break are ignored', () {
      expect(JoinCode.parse('  $v1\r\n').node, 'tn.example.org');
    });

    test('scheme is case-insensitive, unknown parameters are ignored, order does not matter', () {
      final code = JoinCode.parse('${v1.replaceFirst('trafficnetwork', 'TrafficNetwork')}&future=1&future=2');
      expect(code.node, 'tn.example.org');
      final parts = Uri.parse(v1).query.split('&').reversed.join('&');
      expect(JoinCode.parse('trafficnetwork://join?$parts').toUri(), v1);
    });

    test('a damaged root key is not caught by the check value (the fingerprint is), but a malformed one is rejected', () {
      final bad = v1.replaceFirst('oKGio6SlpqeoqaqrrK2ur7CxsrO0tba3uLm6u7y9vr8', 'oKGio6SlpqeoqaqrrK2ur7CxsrO0tba3uLm6u7y9vr9');
      expect(JoinCode.tryParse(bad).problem, JoinCodeProblem.badRoot); // non-canonical last character
      final other = v1.replaceFirst('oKGio6SlpqeoqaqrrK2ur7CxsrO0tba3uLm6u7y9vr8', 'oKGio6SlpqeoqaqrrK2ur7CxsrO0tba3uLm6u7y9vq8');
      expect(JoinCode.tryParse(other).code!.rootFingerprint, isNot('ADUY-QZ36-5T4U-YC5Z-EMZX'));
    });
  });

  group('no secret ends up in a text', () {
    final v1 = ((v['valid'] as List).first as Map)['uri'] as String;
    test('toString of code, credentials and exceptions', () {
      final code = JoinCode.parse(v1);
      final seed = base64Url.encode(code.seed).replaceAll('=', '');
      final all = [code.toString(), code.credentials.toString(), const JoinCodeException(JoinCodeProblem.badCheck).toString()];
      for (final s in all) {
        expect(s.contains(seed), isFalse);
        expect(s.contains(code.credentials.clientSecret), isFalse);
      }
      final failure = JoinCode.tryParse(v1.replaceFirst('3477B6GZ', 'AAAAAAAA'));
      expect(failure.problem, JoinCodeProblem.badCheck);
    });
  });

  test('base32 and fingerprint basics (RFC 4648 vectors)', () {
    expect(base32NoPad(utf8.encode('f')), 'MY');
    expect(base32NoPad(utf8.encode('fo')), 'MZXQ');
    expect(base32NoPad(utf8.encode('foobar')), 'MZXW6YTBOI');
  });
}
