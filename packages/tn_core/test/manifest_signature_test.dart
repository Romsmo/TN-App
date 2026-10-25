import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tn_core/tn_core.dart';

Uint8List hex(String s) => Uint8List.fromList([for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
String toHex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  // RFC 8032, section 7.1, test 1 (empty message) and test 2 (one byte): the key derivation and the signature are the standard ones.
  test('RFC 8032 test vectors: public key from seed, and the signature', () {
    final seed1 = hex('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60');
    expect(toHex(publicKeyOf(seed1)), 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a');
    final seed2 = hex('4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb');
    expect(toHex(publicKeyOf(seed2)), '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c');
  });

  final seed = Uint8List.fromList(List.generate(32, (i) => i + 1));
  final pub = publicKeyOf(seed);
  final manifest = Uint8List.fromList(utf8.encode('{"manifestVersion":1}'));

  test('sign and verify round trip; the file is one line "ed25519:<keyId>:<signature>"', () {
    final text = signManifest(manifest, seed);
    expect(text.split(':'), hasLength(3));
    expect(text.startsWith('ed25519:${keyIdOf(pub)}:'), isTrue);
    expect(verifyManifestSignature(manifest, text, [pub]), SignatureStatus.valid);
    expect(verifyManifestSignature(manifest, '$text\n', [pub]), SignatureStatus.valid);
  });

  test('a changed manifest, a changed signature or a wrong key never verify', () {
    final text = signManifest(manifest, seed);
    final changed = Uint8List.fromList(manifest)..[3] ^= 1;
    expect(verifyManifestSignature(changed, text, [pub]), SignatureStatus.invalid);
    final parts = text.split(':');
    final sig = base64Url.decode(base64Url.normalize(parts[2]));
    sig[5] ^= 1;
    expect(verifyManifestSignature(manifest, 'ed25519:${parts[1]}:${base64Url.encode(sig).replaceAll('=', '')}', [pub]), SignatureStatus.invalid);
    // a key with another id: unknown, not invalid
    final other = publicKeyOf(Uint8List.fromList(List.generate(32, (i) => 100 + i)));
    expect(verifyManifestSignature(manifest, text, [other]), SignatureStatus.unknownKey);
    expect(verifyManifestSignature(manifest, text, const []), SignatureStatus.unknownKey);
  });

  test('missing and malformed signature files', () {
    expect(verifyManifestSignature(manifest, null, [pub]), SignatureStatus.missing);
    expect(verifyManifestSignature(manifest, '  \n', [pub]), SignatureStatus.missing);
    for (final bad in ['garbage', 'ed25519:abc', 'rsa:${keyIdOf(pub)}:AAAA', 'ed25519:${keyIdOf(pub)}:@@@@', 'ed25519:${keyIdOf(pub)}:AAAA', 'a:b:c:d']) {
      expect(verifyManifestSignature(manifest, bad, [pub]), SignatureStatus.invalid, reason: bad);
    }
  });

  test('the real manifest of fw-v0.1.0 verifies against the key built into the app, and a changed one does not', () {
    final bytes = File('test/vectors/fw-v0.1.0-manifest.json').readAsBytesSync();
    final sig = File('test/vectors/fw-v0.1.0-manifest.json.sig').readAsStringSync();
    final trusted = [for (final k in displayTrustedKeys) parsePublicKey(k)!];
    expect(trusted, isNotEmpty);
    expect(verifyManifestSignature(bytes, sig, trusted), SignatureStatus.valid);
    final tampered = Uint8List.fromList(bytes)..[100] ^= 1;
    expect(verifyManifestSignature(tampered, sig, trusted), SignatureStatus.invalid);
    // and the manifest itself is one the app understands
    expect(DisplayManifest.tryParse(utf8.decode(bytes))!.version, '0.1.0');
  });

  test('public keys parse only at 32 bytes', () {
    expect(parsePublicKey(encodePublicKey(pub)), pub);
    expect(parsePublicKey('AAAA'), isNull);
    expect(parsePublicKey('!!!'), isNull);
  });
}
