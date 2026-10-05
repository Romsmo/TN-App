# TNViewer

Mobile App (iOS + Android, Expo) für das [Trafficnetwork](https://github.com/Romsmo/Trafficnetwork): Karte ansehen, Gefahren melden und ein Fahrmodus mit Warnungen — ohne Navigation. Apache License 2.0.

**Stand: `0.1.0`, Stufe M2 (Ansehen).** Die Client-Bibliothek ist eingebunden, die Karte zeigt Meldungen mit Filter und Detailkarte, „Server verbinden" und „Datenpakete" gibt es. Der Fahrmodus ist noch ein Platzhalter (M4), Melden folgt in M3. **Nichts davon wurde auf einem Gerät oder Emulator ausgeführt** (siehe unten).

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

## Aufbau

- `src/tn/` — alles rund um die Bibliothek. Nur `native.ts` importiert `@trafficnetwork/react-native`; der Rest spricht mit `RawClient`/`TnService` und lässt sich mit einer Attrappe testen: SecureStore-Adapter, typisierte Aufrufe, Optionen, Adress- und Sync-Regeln.
- `src/state/` — `TnConnection` (Verbindungsablauf als Klasse) und `TnProvider` (bindet sie an React).
- `src/map/`, `src/screens/` — Kartendaten (GeoJSON, Farben, Beschriftung) und Bildschirme.
- `src/settings/` — lokale Einstellungen in einer App-Datei (nicht im Keychain).
- `src/config.ts` — Domain, Seeds und Karten-Schalter an einer Stelle.

Die Bibliothek kommt als vorgebautes Paket aus dem Release `client-lib-v1.1.0` des Trafficnetwork-Repos (URL und Prüfsumme in `package-lock.json`); es liegt nicht im Git (113 MB).

## Was bisher geprüft wurde — und was nicht

Geprüft (Linux-Container, nicht Windows): `npm run check` grün (Lint, Typen, Tests); `expo export` baut die JavaScript-Bundles für Android und iOS (Hermes); `expo prebuild` erzeugt beide Projekte, und das Autolinking findet Trafficnetwork- und MapLibre-Bibliothek für beide Plattformen.
**Nicht** geprüft: native Builds (Gradle/Xcode), die JSI-Schicht der Bibliothek, die Karte auf dem Bildschirm, ein echter Server; App auf einem Gerät oder Emulator (hier gibt es weder Android SDK noch Apple-Toolchain, und ein Android-Gerät fehlt gerade); EAS-Build; `expo-doctor` vollständig (2 von 21 Prüfungen scheitern, weil `api.expo.dev` und `reactnative.directory` vom Netz-Proxy gesperrt sind — 19 bestanden).

## Rahmen

Regeln für die Arbeit an der App stehen in [`CLAUDE.md`](CLAUDE.md), offene Punkte in [`docs/todo.md`](docs/todo.md), Änderungen im [`CHANGELOG.md`](CHANGELOG.md).
