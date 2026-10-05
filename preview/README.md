# UI-Vorschau (Web, mit Attrappen)

Rendert die **echten Bildschirme** der App im Browser (react-native-web), damit man das Interface ohne iPhone-Build sehen kann.

```bash
npm run preview:web        # baut nach dist-preview/ (TN_PREVIEW=1)
cd dist-preview && python3 -m http.server 8100
```

Ersetzt wird nur Natives (`preview/mocks`, aktiv nur mit `TN_PREVIEW=1`, siehe `metro.config.js`): die Trafficnetwork-Bibliothek liefert Demodaten, die **Karte ist eine flache Zeichnung** (MapLibre läuft nicht im Browser), Töne, Sprache, Haptik und Standort sind Attrappen. Die Fahrmodus-Simulation und alle Regeln (Warnungen, Fahrsperre, Rechtshinweise) laufen mit dem echten Code.

**Nicht gezeigt:** die echte Karte, die Bibliothek, Standort im Hintergrund, Töne/Sprache, Keychain. Das prüft erst ein Build auf dem Gerät.
