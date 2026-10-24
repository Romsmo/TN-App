import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Join code v1: the text an app scans or pastes to learn a node's address, an app key and, optionally, the network's public
/// root key. Specification: the server's `docs/join-code.md` (branch `feat/join-code` of Romsmo/Trafficnetwork), checked against
/// its implementation `src/modules/join/code.ts` and the shared vectors `test/vectors/join-code-vectors.json`.
///
/// Pure functions: no I/O, no logging. Nothing here puts a seed, a secret or a whole code into an exception or a string
/// representation: errors carry a [JoinCodeProblem], never the input.
const String joinScheme = 'trafficnetwork';
const int joinVersion = 1;
const int joinMaxLength = 512;

const String _hkdfSalt = 'trafficnetwork-join-v1';
const String _checkDomain = 'tn-join-v1/check';
const int _keyLength = 43;

/// Why a code was rejected (the interface shows a text per category; none of them names the code).
enum JoinCodeProblem {
  tooLong,
  notAJoinCode,
  duplicateParameter,
  missingParameter,
  newerVersion,
  badVersion,
  badNode,
  badSeed,
  badRoot,
  badCheck,
}

class JoinCodeException implements Exception {
  const JoinCodeException(this.problem);
  final JoinCodeProblem problem;

  @override
  String toString() => 'invalid join code: ${problem.name}';
}

/// The id and secret of the app key derived from a seed (scope `device-registration`). [clientSecret] is secret material.
class JoinCredentials {
  const JoinCredentials(this.clientId, this.clientSecret);
  final String clientId;
  final String clientSecret;

  @override
  String toString() => 'JoinCredentials($clientId, secret hidden)';
}

class JoinCode {
  JoinCode({required this.node, required Uint8List seed, Uint8List? root})
      : seed = Uint8List.fromList(seed),
        root = root == null ? null : Uint8List.fromList(root);

  /// Host in lower case, optional `:port`; always reached over HTTPS.
  final String node;

  /// 32 bytes. Secret material: not stored by the app, never logged.
  final Uint8List seed;

  /// 32 bytes, the public Ed25519 root key, or null when the code carries none.
  final Uint8List? root;

  /// The server address for the library (`https://` + [node]).
  String get address => 'https://$node';

  JoinCredentials get credentials => deriveJoinCredentials(seed);

  /// The root key as the library takes it (base64url, no padding), or null.
  String? get rootKeyText => root == null ? null : _b64url(root!);

  /// The key's fingerprint for display (null without a root key).
  String? get rootFingerprint => root == null ? null : joinRootFingerprint(root!);

  /// The shared string (QR content and text form), parameters in the order of the specification.
  String toUri() {
    final parts = ['v=$joinVersion', 'n=$node', 'k=${_b64url(seed)}'];
    if (root != null) parts.add('r=${_b64url(root!)}');
    parts.add('c=${joinCheck(node, seed)}');
    return '$joinScheme://join?${parts.join('&')}';
  }

  /// Never prints the seed or the code.
  @override
  String toString() => 'JoinCode($node)';

  /// Strict parsing. Throws only a [JoinCodeException]; whitespace around the text is ignored (pasted text often has a line
  /// break at its end), whitespace inside is an error.
  static JoinCode parse(String input) => parseJoinUri(input.trim());

  /// Like [parse] but returns the problem instead of throwing.
  static ({JoinCode? code, JoinCodeProblem? problem}) tryParse(String input) {
    try {
      return (code: parse(input), problem: null);
    } on JoinCodeException catch (e) {
      return (code: null, problem: e.problem);
    } catch (_) {
      return (code: null, problem: JoinCodeProblem.notAJoinCode);
    }
  }
}

String _b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

final RegExp _base64urlAlphabet = RegExp(r'^[A-Za-z0-9_-]+$');
final RegExp _labelPattern = RegExp(r'^[a-z0-9-]{1,63}$');
final RegExp _checkPattern = RegExp(r'^[A-Z2-7]{8}$');
final RegExp _portPattern = RegExp(r'^[0-9]{1,5}$');
final RegExp _versionPattern = RegExp(r'^[0-9]{1,6}$');

/// A 43-character canonical base64url string as 32 bytes, or null when it is not exactly that.
Uint8List? _decodeKey(String text) {
  if (text.length != _keyLength || !_base64urlAlphabet.hasMatch(text)) return null;
  try {
    final bytes = Uint8List.fromList(base64Url.decode('$text='));
    if (bytes.length != 32 || _b64url(bytes) != text) return null;
    return bytes;
  } catch (_) {
    return null;
  }
}

bool _isIPv4(String host) {
  final parts = host.split('.');
  if (parts.length != 4) return false;
  for (final p in parts) {
    if (!RegExp(r'^[0-9]{1,3}$').hasMatch(p)) return false;
    if (p.length > 1 && p.startsWith('0')) return false;
    if (int.parse(p) > 255) return false;
  }
  return true;
}

/// `n`: lower-case host with at least one dot, optional port 1-65535, no IP address, no localhost.
bool isValidJoinNode(String node) {
  if (node.isEmpty || node.length > 253 + 6) return false;
  final colon = node.lastIndexOf(':');
  var host = node;
  if (colon != -1) {
    host = node.substring(0, colon);
    final port = node.substring(colon + 1);
    if (!_portPattern.hasMatch(port)) return false;
    final n = int.parse(port);
    if (n < 1 || n > 65535) return false;
  }
  if (host.isEmpty || host.length > 253) return false;
  if (_isIPv4(host)) return false;
  final labels = host.split('.');
  if (labels.length < 2) return false;
  if (host == 'localhost' || host.endsWith('.localhost')) return false;
  return labels.every(_labelPattern.hasMatch);
}

const String _b32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// RFC 4648 base32, upper case, no padding.
String base32NoPad(List<int> bytes) {
  var bits = 0;
  var acc = 0;
  final out = StringBuffer();
  for (final b in bytes) {
    acc = (acc << 8) | b;
    bits += 8;
    while (bits >= 5) {
      out.write(_b32[(acc >> (bits - 5)) & 31]);
      bits -= 5;
    }
    acc &= (1 << bits) - 1;
  }
  if (bits > 0) out.write(_b32[(acc << (5 - bits)) & 31]);
  return out.toString();
}

/// The check value against typos and damage; it binds address and seed and is not a security feature.
String joinCheck(String node, List<int> seed) {
  final digest = sha256.convert([...ascii.encode(_checkDomain), 0, ...ascii.encode(node), 0, ...seed]);
  return base32NoPad(digest.bytes.sublist(0, 5));
}

/// The fingerprint of the root key for display and comparison: five groups of four characters.
String joinRootFingerprint(List<int> root) {
  final text = base32NoPad(sha256.convert(root).bytes).substring(0, 20);
  return [for (var i = 0; i < 20; i += 4) text.substring(i, i + 4)].join('-');
}

/// HKDF-SHA256 (RFC 5869) with a given salt, input key material, info and output length.
Uint8List hkdfSha256({required List<int> ikm, required List<int> salt, required List<int> info, required int length}) {
  final prk = Hmac(sha256, salt).convert(ikm).bytes;
  final okm = BytesBuilder();
  var t = <int>[];
  for (var i = 1; okm.length < length; i++) {
    t = Hmac(sha256, prk).convert([...t, ...info, i]).bytes;
    okm.add(t);
  }
  return Uint8List.fromList(okm.toBytes().sublist(0, length));
}

/// The app key behind a seed: `id = "join-" + hex(HKDF(info "id", 8))`, `secret = base64url(HKDF(info "secret", 32))`.
JoinCredentials deriveJoinCredentials(List<int> seed) {
  Uint8List expand(String info, int length) =>
      hkdfSha256(ikm: seed, salt: ascii.encode(_hkdfSalt), info: ascii.encode(info), length: length);
  final id = expand('id', 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return JoinCredentials('join-$id', _b64url(expand('secret', 32)));
}

const Set<String> _known = {'v', 'n', 'k', 'r', 'c'};

/// Strict parser (specification, "Parser rules"). Query values are taken literally; a percent sign makes a value fail its own
/// alphabet check. Throws only a [JoinCodeException] and never echoes the input.
JoinCode parseJoinUri(String input) {
  if (input.length > joinMaxLength) throw const JoinCodeException(JoinCodeProblem.tooLong);
  final prefix = RegExp(r'^([A-Za-z][A-Za-z0-9+.-]*)://join\?').firstMatch(input);
  if (prefix == null || prefix.group(1)!.toLowerCase() != joinScheme) {
    throw const JoinCodeException(JoinCodeProblem.notAJoinCode);
  }
  final query = input.substring(prefix.end);

  final values = <String, String>{};
  for (final pair in query.split('&')) {
    final eq = pair.indexOf('=');
    final name = eq == -1 ? pair : pair.substring(0, eq);
    final value = eq == -1 ? '' : pair.substring(eq + 1);
    if (!_known.contains(name)) continue; // forward compatibility: unknown parameters are ignored
    if (values.containsKey(name)) throw const JoinCodeException(JoinCodeProblem.duplicateParameter);
    values[name] = value;
  }

  final v = values['v'];
  final n = values['n'];
  final k = values['k'];
  final c = values['c'];
  if (v == null || n == null || k == null || c == null) throw const JoinCodeException(JoinCodeProblem.missingParameter);
  if (!_versionPattern.hasMatch(v)) throw const JoinCodeException(JoinCodeProblem.badVersion);
  // The specification says "exactly 1"; the server also accepts "01". Stricter here (reported in docs/status.md).
  if (int.parse(v) > joinVersion) throw const JoinCodeException(JoinCodeProblem.newerVersion);
  if (v != '$joinVersion') throw const JoinCodeException(JoinCodeProblem.badVersion);
  if (!isValidJoinNode(n)) throw const JoinCodeException(JoinCodeProblem.badNode);
  final seed = _decodeKey(k);
  if (seed == null) throw const JoinCodeException(JoinCodeProblem.badSeed);
  Uint8List? root;
  final r = values['r'];
  if (r != null) {
    root = _decodeKey(r);
    if (root == null) throw const JoinCodeException(JoinCodeProblem.badRoot);
  }
  if (!_checkPattern.hasMatch(c) || c != joinCheck(n, seed)) throw const JoinCodeException(JoinCodeProblem.badCheck);
  return JoinCode(node: n, seed: seed, root: root);
}
