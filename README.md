# TNViewer

Mobile App (iOS + Android, Expo) für das [Trafficnetwork](https://github.com/Romsmo/Trafficnetwork): Karte ansehen, Gefahren melden und ein Fahrmodus mit Warnungen — ohne Navigation. Apache License 2.0.

**Stand: `0.1.0`, Stufe M1 (Gerüst).** Die Bereiche Karte, Fahrmodus und Einstellungen sind Platzhalter, die das auch sagen. Noch **nicht** eingebunden: die Client-Bibliothek (M2).

## Entwickeln

```bash
npm ci
npm run check        # Lint + Typprüfung + Tests
npm start            # Metro für einen Development Build (kein Expo Go: natives Modul folgt in M2)
```

- Expo SDK 57, Expo Router (`src/app/` nur Routen), TypeScript strikt, Jest (`jest-expo`) + Testing Library.
- Alle sichtbaren Texte an einer Stelle: `src/i18n/` (Deutsch `de.ts`, Englisch `en.ts`; ein Test stellt gleiche Schlüssel und Platzhalter sicher). Sprache: Deutsch auf deutschen Geräten, sonst Englisch.
- CI: `.github/workflows/mobile-ci.yml` (Lint, Typen, Tests, Bundle-Bau für beide Plattformen) auf Pull Requests.

## Builds (EAS)

`eas.json` kennt vier Profile: `development` (Dev Client, intern, Android als APK), `development-simulator` (iOS-Simulator), `preview` (intern, APK) und `production` (Buildnummer zählt EAS hoch, `appVersionSource: remote`). iOS-Builds laufen in der EAS-Cloud, Tests auf einem echten iPhone über TestFlight. Dafür sind ein Expo-Konto, `eas init` (setzt `extra.eas.projectId`) und ein Apple-Developer-Zugang nötig; Zugangsdaten gehören **nur** in EAS-Secrets oder lokal, nie ins Repo. Es wurde bisher **kein** Build gestartet und **nichts** hochgeladen.

Bundle-ID und Android-Paketname: `info.trafficnetwork.tnviewer`.

## Was in M1 geprüft wurde — und was nicht

Geprüft (Linux-Container, nicht Windows): `npm run check` grün; `expo export` baut die JavaScript-Bundles für Android und iOS (Hermes).
**Nicht** geprüft: App auf einem Gerät oder Emulator (hier gibt es weder Android SDK noch Apple-Toolchain, und ein Android-Gerät fehlt gerade); EAS-Build; `expo-doctor` vollständig (2 von 21 Prüfungen scheitern, weil `api.expo.dev` und `reactnative.directory` vom Netz-Proxy gesperrt sind — 19 bestanden).

## Rahmen

Regeln für die Arbeit an der App stehen in [`CLAUDE.md`](CLAUDE.md), offene Punkte in [`docs/todo.md`](docs/todo.md), Änderungen im [`CHANGELOG.md`](CHANGELOG.md).
