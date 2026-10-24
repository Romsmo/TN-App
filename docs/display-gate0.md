# Display (Bluetooth): gate 0 and state of the work (2026-10-24)

Source of the contract: `Romsmo/TN-DSP`, tag `protocol-v1.0.0` (commit `3e108fc`), read in full: `ble-protocol.md`,
`contract/*`, `app-integration.md`, `release-format.md`, `compatibility.md`, `update-authenticity.md`. **Nothing here has run
against a real display or a real phone.**

## What is built (no hardware needed)

| Part | Where | Tested with |
|---|---|---|
| Protocol package (CBOR, framing, sign rules), vendored unchanged | `packages/tn_display_protocol` (`VENDORED.md`) | its own 85 tests against the golden vectors |
| App logic: category mapping, filter bits, settings set, State stream (`stateSeq` from 1, change-driven, keep-alive, audio cue hold, confirm prompt), event handling with duplicate guard, compatibility check | `packages/tn_core/lib/src/display/display_feed.dart` | `test/display_feed_test.dart` (15 tests) |

Rules enforced there (from the contract): the display never decides; camera categories 0-4 are sent only when the user's camera switch
(including the country rule) is on **and** the firmware has the camera code; a report from the display is accepted only for the
general hazards 5-10 (never a camera category) and a repeated identical report within 3 s is ignored; an unknown app category is not
sent; every packet is checked against the 244-byte limit by the package's encoder.

**Gap (needs your word or the library):** context signs (left/right columns) need a map from the library's `signType` strings to the
VzNr codes of `sign-rules.json`. I found no such table; until there is one the columns stay empty (nothing is guessed).
**Gap:** `hazardSpeedLimit` (limit of a mobile camera) is not available from the warning engine; omitted.

## Built in the app (2026-10-24, after your approval of Bluetooth and `bluetooth-central`)

`DisplayLink` (connect sequence, reconnect, State stream, events; tested with a fake transport), `UniversalBleDisplayTransport`,
`DisplayController` (feeds the display from the drive mode, settings both ways, sound routing), the page *Settings → Display*,
the permissions in `Info.plist` and the Android manifest. **Never run on a phone or against the display.**

## What is not built yet (needs decisions below)

firmware and voice-pack update (questions 3 and 4), the developer area (question 7), sign columns (no mapping).

## Bluetooth plugin

| Plugin | Licence | iOS | Verdict |
|---|---|---|---|
| `universal_ble` 3.1.2 | BSD-3-Clause (Navideck Labs) | SwiftPM manifest (`darwin/universal_ble/Package.swift`) and podspec; state restoration opt-in when the app declares `bluetooth-central`; `requestMtu` (best effort) | **recommended** |
| `flutter_blue_plus` | custom "FlutterBluePlus License": free for non-profit use, a paid commercial licence for for-profit use, mentions build-time licence telemetry ([pub.dev](https://pub.dev/packages/flutter_blue_plus/versions/2.3.10)) | no SwiftPM found | rejected (licence, telemetry) |
| `flutter_reactive_ble` | not confirmed (an index lists "other") | not confirmed; last push April 2024 per an index | not chosen |
| `bluetooth_low_energy` | not looked at | not looked at | not chosen |

(Sources: the plugins' pub.dev pages and README, read 2026-10-24; for `universal_ble` the package itself was downloaded and its `LICENSE`,
`Package.swift` and README read.)

## iOS reality (to be checked on a device)

* Without a background mode CoreBluetooth stops delivering when the app is suspended. The drive mode already keeps the app running
  (`location`, `audio`); whether that is enough for Bluetooth writes is **not verified**. The documented way is `UIBackgroundModes`
  `bluetooth-central` (keeps the connection usable in the background; with state restoration the system can relaunch the app, see Apple's
  [TN3115](https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules); an app the user force-quit is not relaunched).
* Pairing: the display requires none today (open link, decision of 2026-10-24). iOS pairs by itself only when a protected characteristic is
  touched; an app cannot "forget" a device, the user does it in the iOS Bluetooth settings.
* Permission text (draft, `NSBluetoothAlwaysUsageDescription`): "TNViewer nutzt Bluetooth nur, um dein TN-Display zu finden und mit ihm
  Warnungen, Einstellungen und Updates auszutauschen. / TNViewer uses Bluetooth only to find your TN display and to exchange warnings,
  settings and updates with it."
* Android (not built): BLE scan/connect permissions from Android 12 (`BLUETOOTH_SCAN` with `neverForLocation`, `BLUETOOTH_CONNECT`),
  location permission for older versions; a foreground service already exists for the drive.

## Privacy

New permission: Bluetooth. The display exchange stays between phone and display. **New data flow only for the update check:** the manifest
and image come from GitHub; GitHub sees the phone's IP address and the app's name in the `User-Agent`. Proposal: only on a tap ("Nach
Update suchen"), never automatic, no telemetry, one request for `manifest.json` (plus the image only after the user confirms).

## Update source and authenticity (the blocker)

* **`Romsmo/TN-DSP` is a private repository.** An app without a token cannot read its releases. A token inside the app is not acceptable.
  Options: make the repository (or only a separate release repository) public; or serve `manifest.json` and the image from another public
  place. The decision is yours.
* The display accepts an OTA image from **any** BLE central (open link; the SHA-256 only guards against transfer errors). A signature of
  the manifest checked in the app (option G of `update-authenticity.md`) protects only the download, not the device; the contract plans
  it (`manifest.json.sig`) but it does not exist yet. My rule: **no download is pushed to the display without a verified manifest
  signature**; a manual file is allowed only with a clear warning and after you agree.

## Questions for you

1. Add `bluetooth-central` to the background modes (so the display keeps working with the screen locked)? Or try without first?
2. Add the Bluetooth permission (text above)?
3. Update source: make `TN-DSP` (or a release repository) public? Until then the update check cannot be built.
4. Manifest signature: should the app wait for the signed manifest (safe) or allow the unsigned `fw-v0.1.0` for your own display only,
   with a warning?
5. Announcements: on the display, on the phone, or both (a setting; the proposal is "display when connected, else phone")?
6. May the display's own "Melden" tap report while driving (the contract has no lock; the app's lock rules apply to the app only)?
7. Is the developer area (UiConfig switches) hidden behind a long press, or not built?
