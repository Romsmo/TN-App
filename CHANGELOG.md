# Changelog

Eigene Versionierung: `0.x` während der Entwicklung, `1.0.0` mit der Einreichung im App Store.

## 0.1.0 — in Arbeit (M1–M5)

- M4: Fahrmodus (Tempo, Tempolimit, Warnungen voraus in Fahrtrichtung mit zeitbasierter Vorwarnung und Entprellen, Ein-Tipp-Melden, „Noch da?", Stumm, Nachtfarben, Bildschirm bleibt an); Hintergrund-Standort nur im laufenden Fahrmodus; Fahrsperre ab 10 km/h (Standard an, Abschalten nur mit bestätigtem Warnhinweis); Blitzer-Option (aus, Länderpolitik, Rechtshinweis einmalig und dauerhaft im Info-Bereich); Simulationsfahrt auf erfundener Strecke; Einstellungen inkl. „Lokale Daten löschen" und „Geräteidentität zurücksetzen".
- M5: eigenes Icon und Splash; Listenansicht der Karte für Screenreader; Kontrasttests; Lizenzliste; Build-Schalter für die Fahrsperre; Datenschutz-Zuordnung, Datenschutzerklärung (Entwurf), Store-Risiken, Review-Hinweise, Store-Texte, Maestro-Abläufe (nicht ausgeführt).
- Behoben: Meldungen senden keine Geschwindigkeit mehr.

- M3: Melden (am Standort oder per Tipp auf die Karte, große Tasten je Art), Bestätigen/Widerlegen in der Detailkarte, Wartezustand für gespeicherte, noch nicht gesendete Meldungen (ohne Alarm: WLAN-Wartezeit, offline, wird gesendet), ruhiger Hinweis bei vom Server nicht angenommenen Meldungen. Meldungen werden zuerst auf dem Gerät gespeichert und erscheinen sofort. Keine Blitzer-Arten (kommen mit M4).

- M2: Client-Bibliothek 1.1.0 eingebunden (Schlüssel im Keychain/Keystore, typisierter Zugriff, Tests mit Attrappe); Karte mit MapLibre (Meldungen, Zonen nur als Fläche, Filter, Detailkarte, Namensnennung); „Server verbinden" (Adresse, Zugang, Status, Knotenliste; https erzwungen außer in Development-Builds); „Datenpakete" mit „Nur im WLAN"; „Quellen und Lizenzen". Keine Kartenquelle voreingestellt (`docs/map-sources.md`).

- Expo-SDK-57-Gerüst mit Expo Router, TypeScript strikt, Jest, ESLint, Dev Client.
- Texte zentral in `src/i18n` (Deutsch/Englisch).
- Platzhalter-Tabs Karte / Fahrmodus / Einstellungen.
- EAS-Profile und CI-Workflow `mobile-ci`.
- Noch keine Client-Bibliothek, keine Karte, keine Funktionen (kommen in M2–M4).
