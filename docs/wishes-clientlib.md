# Wishes and findings for the Trafficnetwork client library (supplier; nothing is changed there from here)

State 2026-10-23, against `client-lib-v1.2.1`.

## Delivered

1. **SwiftPM manifest in the Flutter plugin** (asked 2026-10-23, delivered the same day in 1.2.1, PR #35): `Package.swift`
   (product `trafficnetwork-flutter`) and a dynamic `TrafficNetworkDart.framework`. Not run on a device by anyone
   (the library's CI builds, and runs the example in the iOS simulator in debug mode).
2. `reportMissingSpeedLimit` → replaced by the typed `reportSpeedLimitInterval` (two points).

## Open

3. **`trafficnetwork_flutter/pubspec.yaml` depends on `trafficnetwork` with `path: ../dart`**, but the two tarballs unpack to
   `trafficnetwork-dart-1.2.1/` and `trafficnetwork-flutter-1.2.1/`; side by side the path does not resolve. This app unpacks them
   to `packages/dart` and `packages/flutter` (`tool/fetch_clientlib.sh`). A note in `integration-flutter.md`, or `dependency_overrides`
   advice, would help.
4. `lookupSpeedLimit` sends the exact coordinate outside the offline area; `api.md` ("Network & privacy") says no raw coordinate
   leaves the device. A tile variant would be better. (Carried over from the Expo findings.)
5. Speed-limit proposals (`reportWrongSpeedLimit`, `reportSpeedLimitInterval`) and `resolveRoadInterval` carry exact coordinates;
   please say so in "Network & privacy".
6. The own-carriageway filter for warnings (heading corridor today) belongs into the library; the app keeps it behind
   `WarningEngine`.
7. A list of report types instead of the interim catalogue (`ReportCatalog`).
8. `lastSyncedAtUnixMs` is the last *attempt*; a field for the last success would be better (carried over).
9. Whether the error codes `noRoadFound`, `noRoadBetweenPoints`, `intervalTooLong`, `intervalTooShort`, `noRoadData`,
   `notOffered` arrive as `error.code` of the envelope is read from `api.md`, not tried; the app maps them by name.

## For the author of the export (`TNViewer-export-2026-10-22`)

- `drive-core/vectors/misc.json`: `pendingText` / `rejectedText` contain double-encoded German ("Ã¼ber").
- `drive-core/vectors/drive-session.json` does not say how the scenarios were driven: the first fix of a scenario warns
  immediately, which needs the nearby data to be loaded already; the "GPS lost" scenario needs a clock advance of 0 after the fix.
  Two sentences in `drive-core/README.md` would make the vectors self-contained.
- `texts/de.json` has a stale key (`data.regionNote`: "Regionen einzeln auszuwählen unterstützt die Bibliothek noch nicht").
