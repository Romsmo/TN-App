# Status per function (as of 2026-10-23)

Legend — **Code**: done / partial / open. **Test**: what exists. **Device**: always *never run on a device or simulator*
(Windows, no Mac; Gate 0 — the way to get the app onto the iPhone — is not finished: macOS runner builds, xtool in WSL installs, see `ios-install.md`).
"Browser" = Flutter web preview with the demo backend, looked at by hand.

| Function | Code | Test | Notes |
|---|---|---|---|
| Start logo, three tabs, sub pages | done | widget tests, browser | |
| Map: reports (colours per type), signs, camera **zones as areas only**, filter chips, list view, detail card | done | unit (`map_data`), widget, browser | no background map (decision D-N5) |
| Position arrow + accuracy circle (in metres), "centre on me" (3 states) | done | unit (`follow-mode`), browser (arrow not seen: no position in a browser) | native location unverified |
| Report (types, place by tap, **own duration** checked against `getReportLimits`) | done | unit, widget | |
| Confirm / deny, "doesn't exist any more" for fixed cameras | done | unit, browser | |
| Drive mode (speed, limit, compass, chips) | done | unit (session vectors), widget, browser (simulation) | |
| **Speed lock** (10 km/h on, 5 km/h for 2 s off, stale 60 s), switch-off warning | done | unit (`lock.json`), widget | default on, also after reset |
| Warnings ahead (two stages, lane, zones without distance) | done (interim solution, wish to the library) | unit (`warning-*.json`, `drive-session.json`) | |
| "Still there?" after passing, one-tap reporting | done | unit, browser | |
| Simulated drive (invented route) | done | unit, browser | never writes to the real queue |
| Background location only while the drive runs; sampling by speed | done (code) | unit (sampling, location source) | **iOS/Android behaviour and battery unverified** |
| Tones (own WAV), speech, haptics | done (code) | fakes only | **never heard or felt** |
| Speed limit: look up, **add as a stretch between two points**, correct | done | unit, widget | the "add" flow changed (D-N2) |
| Offline data: auto / own regions, storage, limit, Wi-Fi only | done | unit | mode *all* still not selectable |
| Settings, server connection, access data, reset local data / device identity | done | unit | Keychain/Keystore unverified |
| Emergency mode ("Notmodus") | done | unit | |
| Blitzer filter default off, notice wording, country policy | done | unit | German wording verbatim; English unapproved |
| Languages de/en | done | — | 6 new texts for the stretch flow are mine (see decisions) |
| Accessibility | partial | semantics labels | **no VoiceOver/TalkBack test**, font scaling unchecked |
| Web test PWA | not part of this job | — | |
| iOS build (cloud, unsigned `.ipa`) | done | workflow `ios-beta.yml`; run on 2026-10-23; a tag `v<version>-beta.<n>` publishes a pre-release | |
| Signing and install with xtool (WSL) | done | installed on one iPhone (iOS 26.4.1), the app starts | Part B of `ios-install.md` |
| Join code: parse, derive, confirm, store, scan, link | done (code) | unit (shared vectors + 300 server-made codes), widget | **never run against a real server**; scan and link never run on a device (`join-device-test.md`) |
| Display (Bluetooth): connect, live State from the drive mode, events, settings both ways, time, "Display" page | done (code) | 85 contract tests, 15 feed tests, 7 link tests (fake transport), 3 widget tests | **never run against the real display or on a phone**; `universal_ble` calls untested; iOS background behaviour unverified (`display-device-test.md`) |
| Display: firmware / voice-pack update, developer area, sign columns | **open** | — | update source is a private repository and no signed manifest exists (`display-gate0.md`) |
| Map background (OpenStreetMap tiles) | done | style unit-free; analysis only | **not looked at on a device yet** |
| Android build | **open** | — | Android SDK on this PC lacks cmdline-tools and accepted licences |
| Store submission | **open** | — | only after written approval |

## Test results

- `packages/tn_core`: 271 tests, all pass (`dart test`): all 14 vector files of `drive-core/` (geo, units, sampling, compass,
  follow mode, fix, lock, warning thresholds/engine/forget, drive session 16 scenarios, sim, misc) plus own tests of the
  service layer, connection, drive host, location source, report/limit logic.
- `flutter test` (app): 6 widget tests pass. `flutter analyze`: clean.
- Not run: anything that needs a device.

## Known gaps

- The vector files do not record how the session scenarios were driven; the test harness reproduces them with two
  assumptions (the first fix is delivered a second time once the asynchronous data read has finished; the "GPS lost" scenario
  advances the clock by 0 after the fix). With these all 16 scenarios match. A report to the export's author is in `wishes-clientlib.md`.
- `misc.json` contains double-encoded German texts (`pendingText`, `rejectedText`: "Ã¼ber" for "über"); the test decodes them.
