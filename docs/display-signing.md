# Signing display firmware releases

The display accepts an OTA image from any Bluetooth device in range, so the app is the only place that can check where an update comes
from. Since 2026-10-25 the app verifies a **signature of the manifest**; the manifest names the image's SHA-256, so the signature covers
the image as well.

## The scheme

* **Ed25519** (RFC 8032) over the exact bytes of `manifest.json`.
* The signature is published next to it as **`manifest.json.sig`**, one line: `ed25519:<keyId>:<signature, base64url without padding>`.
  `keyId` = the first 8 hex characters of the SHA-256 of the public key.
* The app trusts the public keys in `displayTrustedKeys` (`packages/tn_core/lib/src/display/manifest_signature.dart`). Today: key id
  **`20043558`**, public key `vogO8GeYeTiSzs7JOlBtw-NbwV_s8UJjPN4hghHp6fk` (created 2026-10-25).
* What the app does with the result: **valid** → installs after the normal confirmation; **no signature file** → the confirmation says the
  release is unsigned (size and SHA-256 are still checked); **invalid, or a key the app does not trust** → the release is refused.

## The private key

It was generated on the owner's PC and lives **outside every repository**: `C:\Users\rsmol\.tnviewer-keys\display-manifest.key` (a
single line, the 32-byte seed). It was never printed, logged or sent anywhere. **Back it up offline and keep it secret.** If it is lost,
a new key is generated, its public key is added to `displayTrustedKeys` and shipped in an app version, and older releases have to be
signed again with the new key. If it leaks, the key is removed from `displayTrustedKeys` in the next app version.

## Signing a release

```bash
cd packages/tn_core
dart run bin/display_manifest_sign.dart sign path/to/manifest.json C:/Users/rsmol/.tnviewer-keys/display-manifest.key
dart run bin/display_manifest_sign.dart verify path/to/manifest.json path/to/manifest.json.sig   # must print "valid"
```

Then upload `manifest.json.sig` as an extra asset of the same GitHub release (`gh release upload fw-vX.Y.Z manifest.json.sig`). The
manifest and the signature have to be uploaded **unchanged** after signing: any change to the manifest invalidates the signature.

`fw-v0.1.0` was signed this way (the file is `D:\Recent\Projects\TNV\signed-out\fw-v0.1.0\manifest.json.sig`); **it is not uploaded yet**.
Until it is, the app treats `fw-v0.1.0` as unsigned.

Other commands: `keygen KEYFILE` (refuses to overwrite a key), `pubkey KEYFILE`.

## Limits

* The display does not check the signature: someone with Bluetooth access can still write an image to it directly. The signature
  protects the download path (a replaced release, a man in the middle), as `update-authenticity.md` of the display project describes
  for option G. A check on the display (option C) is a firmware change.
* The signing key can sign a manifest for any firmware; trust in the key is trust in whoever holds it.
