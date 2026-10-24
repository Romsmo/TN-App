# Decisions made while building (2026-10-23)

The operator's binding decisions (D1–D13 of the export: data only through the library, privacy by design, wordings verbatim,
speed lock default on, cameras default off, nothing from Blitzer.de, no store upload without approval, drive mode never
asks online, ...) are unchanged. The following were **open** and were decided here with a sensible default, so the work could
go on. Each is easy to reverse; please confirm or change.

| # | Question | Decision | Why / how to change |
|---|---|---|---|
| D-N1 | Does the drive mode feed `updatePosition`? (the Expo drive mode never did, the privacy documents claimed it did) | **Yes**, a real drive hands its position to the library at most once a minute or per 500 m (`DriveController`, `_TileFeed`). A coarse H3 tile (≈ 2.4 km) leaves the device, no coordinate. The simulation never does. | Without it the library follows no long trip and the automatic offline area stays where the map once put it. `--dart-define=DRIVE_FEEDS_TILES=false` switches it off; `privacy-mapping.md` says what it sends. |
| D-N2 | `reportMissingSpeedLimit` is gone from the library (1.2.1) | "Add" now proposes a limit for a **stretch of road between two points** (`reportSpeedLimitInterval`): tap the road, choose "Nachreichen", tap the other end, optional preview (`resolveRoadInterval`, needs the network), choose the value. "That limit is wrong" still corrects at one tapped spot (`reportWrongSpeedLimit`). | the API has no single-point "missing" any more. The 11 new texts of this flow (`limit.interval.*`, `limit.error.noRoad*` …) are **mine** and need a read-through. The lock rules are unchanged: no proposals while driving or above 10 km/h. |
| D-N3 | Client library version | **1.2.1** (SwiftPM manifest + dynamic framework in the Flutter plugin). | 1.2.0 was podspec-only; see `ios-install.md`. |
| D-N4 | Map plugin | `maplibre_gl` 0.27.1 (has a SwiftPM manifest on iOS; works with the installed Flutter 3.38.7). `maplibre` 0.3.x needs Flutter ≥ 3.47. | revisit when the Flutter SDK is upgraded. |
| D-N5 | Map background source | **none** (plain surface, only the network's data; "© OpenStreetMap contributors" always shown), as before. `MAP_STYLE_URL(_DARK)` takes a style as soon as one with usable terms exists (own PMTiles are the goal; whether MapLibre native reads `pmtiles://` is untested). | `tile.openstreetmap.org` does not allow app use. |
| D-N6 | Web test PWA | not continued. The browser build in this repository is a development preview with a demo backend only. | |
| D-N7 | Repo | `Romsmo/TN-App`, branch `flutter` (an orphan branch; no other branch touched), pushed with the owner's approval on 2026-10-23. A local clone lives in `D:/Recent/Projects/TNV/tnviewer`. | pushes only after the owner's word |
| D-N8 | Licence and English legal texts | Apache 2.0 kept as a draft (not confirmed); English wordings are carried over as an unapproved translation. | |
| D-N9 | Where `Package.swift` lives | it is the library's (`client-lib-v1.2.1`, requested in wish 1 and delivered). The app contains none. | |

## Interim solutions that stay behind an interface

`WarningEngine` (own-carriageway filter), `ReportCatalog` (report types) — as in the Expo version; both are wishes to the
library (`wishes-clientlib.md`).

## Added 2026-10-24

| # | Question | Decision | Why / how to change |
|---|---|---|---|
| D-N5 (revised) | Map background | **OpenStreetMap raster tiles** (`tile.openstreetmap.org`), as the operator's web map; dimmed in dark mode; credit shown. The app names itself in the `User-Agent` (`TNViewer/<version> (+repo)`). | The tile usage policy (operations.osmfoundation.org/policies/tiles, read 2026-10-24) allows apps that identify themselves, show the credit and honour the cache; it forbids bulk download, prefetching and offline use, and gives no guarantee (access can be blocked). Known gap: the native map library may prefetch some low-zoom tiles around the view; it has no switch in `maplibre_gl` 0.27.1. `MAP_STYLE_URL(_DARK)` still overrides. Own tiles stay the goal. |
| D-N10 | Simulated drive in a release | **Removed from the UI** of every release build. `--dart-define=TN_DEV_TOOLS=true` (or the demo/browser preview) shows it again. The code and its tests stay. | The owner: everything that only serves testing, such as the simulated drive, leaves the beta. |
| D-N11 | Join code (server 1.3.0, branch `feat/join-code`) | Implemented as `JoinCode` in `tn_core` against `server/docs/join-code.md` and the shared vectors; 300 random codes made by the server's `code.ts` were also parsed and re-derived identically. **One deviation:** `v=01` is rejected (the text says "exactly 1", the server also accepts `01`). | Report to the server chat. The seed is never stored; address, app key and root key are (Keychain, this device only, after first unlock). A saved code beats the build variables. |
| D-N12 | QR scanner | `mobile_scanner` 7.4.2 (BSD-3-Clause, verified publisher steenbakker.dev; Apple Vision on iOS, has a SwiftPM manifest; Android uses ML Kit). New permission: camera (`NSCameraUsageDescription`, Android `CAMERA`), approved by the owner on 2026-10-24. | A link `trafficnetwork://join?…` needs no permission (URL scheme in Info.plist, intent filter). |
