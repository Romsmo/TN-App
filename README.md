# TNViewer (Flutter)

View, report and get warned about traffic events from the open *Trafficnetwork*: a map of reports, one-tap reporting, a drive
mode with speed, speed limit and warnings ahead, speed-limit proposals and offline data. **No navigation, no analytics, no
advertising SDK, no telemetry.** All data comes through the Trafficnetwork client library (Dart/Flutter package, release
`client-lib-v1.2.1`); the app has no REST or WebSocket code of its own.

This is the Flutter rebuild of the Expo/React Native app (`Romsmo/TN-App`, commit `069040f`). The functional specification
is the export `TNViewer-export-2026-10-22` (`spec/`, `texts/`, `drive-core/`).

> **Honest status:** the logic is tested (all test vectors of `drive-core` pass in Dart, plus own tests of the service and device layers) and the UI was
> looked at in a browser with demo data. **Nothing has run on an iPhone or an Android device yet.** See
> [docs/status.md](docs/status.md) and [docs/ios-install.md](docs/ios-install.md).

## Layout

| Path | What |
|---|---|
| `packages/tn_core/` | UI-free Dart: drive mode (lock, warnings, session, simulation), settings, report/limit/offline logic, the typed service layer over the library, the connection state. Tested with the vectors from the export. |
| `lib/` | The Flutter app: screens (`screens/`), device services (`services/`), design (`ui/`), the platform switch (`platform/`). |
| `assets/texts/` | All app texts, German (binding) and English (unapproved translation), plus the legal wordings. |
| `packages/dart`, `packages/flutter` | The client library, **fetched** by `tool/fetch_clientlib.sh` (not committed). |
| `docs/` | status, decisions, privacy mapping, iOS install paths, wishes to the library. |

## Build

```bash
tool/fetch_clientlib.sh          # fetches client-lib 1.2.1 and checks it against the release's checksums.txt
flutter pub get
flutter analyze
(cd packages/tn_core && dart test)
flutter test --dart-define=TN_DEMO=true
flutter build apk --release      # Android (needs the Android SDK)
flutter build ios --release --no-codesign   # on macOS (the workflow ios-unsigned.yml does it in the cloud); see docs/ios-install.md
```

### Configuration (`--dart-define`, nothing in the code)

| Name | Meaning |
|---|---|
| `TN_DEFAULT_NODE` | server the app tries first; the user can enter another under *Server verbinden* |
| `TN_APP_CLIENT_ID`, `TN_APP_CLIENT_SECRET` | a *public* app key (scope `device-registration`) so a fresh install can register itself |
| `TN_NETWORK_ROOT_KEY` | the network's public root key (base64url) |
| `MAP_STYLE_URL`, `MAP_STYLE_URL_DARK` | MapLibre style URL; **no default** (see `docs/decisions.md`, D-N5) |
| `ALLOW_DISABLE_DRIVE_LOCK` | `false` removes the option to switch the speed lock off (cautious review build) |
| `DRIVE_FEEDS_TILES` | `false` stops the drive mode from handing its position to the library (see D-N1) |
| `TN_DEMO` | **development only:** answer from an invented data set instead of the library |

Without a server address and access data the app runs in the *Notmodus*. The real values are entered by the operator;
this repository contains placeholders only.

## Development preview in a browser

`flutter build web --release` builds a browser preview that uses the demo backend (invented data around Munich). It exists to
look at the screens without a device; it is not a product and has no part of the real library.
