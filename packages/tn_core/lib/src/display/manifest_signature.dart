import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

/// Signature of a display firmware manifest.
///
/// Scheme (decided here, the display project's contract only reserves the field): an **Ed25519** signature (RFC 8032) over the exact
/// bytes of `manifest.json`, published next to it as `manifest.json.sig`, one line:
///
///     ed25519:<keyId>:<signature, base64url without padding>
///
/// `keyId` is the first 8 hex characters of the SHA-256 of the public key, so the app can hold several trusted keys (rotation). The
/// private key stays offline with the owner; the app contains only public keys. The manifest names the image's SHA-256, so the
/// signature covers the image too.
enum SignatureStatus {
  /// A good signature of a trusted key.
  valid,

  /// There is no signature file (an unsigned release).
  missing,

  /// The file is malformed or the signature does not match: the release must not be installed.
  invalid,

  /// A well-formed signature, but of a key this app does not trust.
  unknownKey,
}

/// The key id of a public key: 8 lower-case hex characters.
String keyIdOf(List<int> publicKey) => sha256.convert(publicKey).bytes.take(4).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

String _b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List? _unb64url(String s) {
  try {
    return Uint8List.fromList(base64Url.decode(s + '=' * ((4 - s.length % 4) % 4)));
  } catch (_) {
    return null;
  }
}

/// The text of a signature file for [manifest] signed with the 32-byte [seed] (the private key).
String signManifest(Uint8List manifest, Uint8List seed) {
  final key = ed.newKeyFromSeed(seed);
  final pub = ed.public(key).bytes;
  return 'ed25519:${keyIdOf(pub)}:${_b64url(ed.sign(key, manifest))}';
}

/// The 32-byte public key for a seed.
Uint8List publicKeyOf(Uint8List seed) => Uint8List.fromList(ed.public(ed.newKeyFromSeed(seed)).bytes);

/// Checks [signatureText] (the content of `manifest.json.sig`, or null when there is none) against the trusted public keys.
SignatureStatus verifyManifestSignature(Uint8List manifest, String? signatureText, List<Uint8List> trusted) {
  if (signatureText == null || signatureText.trim().isEmpty) return SignatureStatus.missing;
  try {
    final parts = signatureText.trim().split(':');
    if (parts.length != 3 || parts[0] != 'ed25519') return SignatureStatus.invalid;
    final sig = _unb64url(parts[2]);
    if (sig == null || sig.length != 64) return SignatureStatus.invalid;
    final keyId = parts[1];
    final candidates = trusted.where((k) => k.length == 32 && keyIdOf(k) == keyId).toList();
    if (candidates.isEmpty) return SignatureStatus.unknownKey;
    for (final k in candidates) {
      if (ed.verify(ed.PublicKey(k), manifest, sig)) return SignatureStatus.valid;
    }
    return SignatureStatus.invalid;
  } catch (_) {
    return SignatureStatus.invalid;
  }
}

/// Reads a base64url public key (as kept in the app's configuration); null when it is not 32 bytes.
Uint8List? parsePublicKey(String text) {
  final b = _unb64url(text.trim());
  return b != null && b.length == 32 ? b : null;
}

String encodePublicKey(Uint8List key) => _b64url(key);

/// The public keys whose signatures the app accepts for display firmware (base64url, 32 bytes each). Public by nature: the private
/// key is kept offline by the owner. A new key is added here before the first release signed with it.
const List<String> displayTrustedKeys = [
  'vogO8GeYeTiSzs7JOlBtw-NbwV_s8UJjPN4hghHp6fk', // key id 20043558, created 2026-10-25; the private key is kept offline by the owner
];
