import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:tn_core/tn_core.dart';

/// Signs a display firmware manifest, for the owner's release process (the private key never goes into a repository).
///
/// ```
/// dart run bin/display_manifest_sign.dart keygen KEYFILE            make a key pair; writes the private seed to KEYFILE
/// dart run bin/display_manifest_sign.dart pubkey KEYFILE            print the public key (for the app) and its key id
/// dart run bin/display_manifest_sign.dart sign MANIFEST KEYFILE [OUT]   write MANIFEST.sig (or OUT)
/// dart run bin/display_manifest_sign.dart verify MANIFEST SIGFILE   check against the keys built into the app
/// ```
void main(List<String> args) {
  if (args.isEmpty) return _usage();
  switch (args[0]) {
    case 'keygen':
      if (args.length != 2) return _usage();
      final file = File(args[1]);
      if (file.existsSync()) {
        stderr.writeln('${args[1]} exists already; refusing to overwrite a key.');
        exit(2);
      }
      final rng = Random.secure();
      final seed = Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
      file.createSync(recursive: true);
      file.writeAsStringSync('${base64Url.encode(seed).replaceAll('=', '')}\n');
      stdout.writeln('Private key written to ${args[1]} (not shown). Keep it offline and out of every repository.');
      _printPublic(seed);
    case 'pubkey':
      if (args.length != 2) return _usage();
      _printPublic(_readSeed(args[1]));
    case 'sign':
      if (args.length < 3) return _usage();
      final manifest = File(args[1]).readAsBytesSync();
      final text = signManifest(manifest, _readSeed(args[2]));
      final out = args.length > 3 ? args[3] : '${args[1]}.sig';
      File(out).writeAsStringSync('$text\n');
      stdout.writeln('Wrote $out');
    case 'verify':
      if (args.length != 3) return _usage();
      final status = verifyManifestSignature(
        File(args[1]).readAsBytesSync(),
        File(args[2]).readAsStringSync(),
        displayTrustedKeys.map((k) => parsePublicKey(k)!).toList(),
      );
      stdout.writeln(status.name);
      exit(status == SignatureStatus.valid ? 0 : 1);
    default:
      _usage();
  }
}

Uint8List _readSeed(String path) {
  final key = parsePublicKey(File(path).readAsStringSync());
  if (key == null) {
    stderr.writeln('$path does not hold a 32-byte key.');
    exit(2);
  }
  return key;
}

void _printPublic(Uint8List seed) {
  final pub = publicKeyOf(seed);
  stdout.writeln('public key: ${encodePublicKey(pub)}');
  stdout.writeln('key id:     ${keyIdOf(pub)}');
}

void _usage() {
  stderr.writeln('usage: keygen <key-file> | pubkey <key-file> | sign <manifest.json> <key-file> [out] | verify <manifest.json> <sig>');
  exit(64);
}
