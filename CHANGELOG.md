# Changelog

Eigene Versionierung: `0.x` während der Entwicklung, `1.0.0` mit der Einreichung im App Store.

## 0.1.0 — in Arbeit (M1, M2)

- M2: Client-Bibliothek 1.1.0 eingebunden (Schlüssel im Keychain/Keystore, typisierter Zugriff, Tests mit Attrappe); Karte mit MapLibre (Meldungen, Zonen nur als Fläche, Filter, Detailkarte, Namensnennung); „Server verbinden" (Adresse, Zugang, Status, Knotenliste; https erzwungen außer in Development-Builds); „Datenpakete" mit „Nur im WLAN"; „Quellen und Lizenzen". Keine Kartenquelle voreingestellt (`docs/map-sources.md`).

- Expo-SDK-57-Gerüst mit Expo Router, TypeScript strikt, Jest, ESLint, Dev Client.
- Texte zentral in `src/i18n` (Deutsch/Englisch).
- Platzhalter-Tabs Karte / Fahrmodus / Einstellungen.
- EAS-Profile und CI-Workflow `mobile-ci`.
- Noch keine Client-Bibliothek, keine Karte, keine Funktionen (kommen in M2–M4).
