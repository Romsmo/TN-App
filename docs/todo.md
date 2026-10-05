# Offene Punkte — Mobile

Nur, was wirklich offen ist.

## Beim Auftraggeber

- [ ] Expo-Konto: `eas login` und `eas init` (setzt `extra.eas.projectId`), `EXPO_TOKEN` als Secret für die Umgebung dieser Instanz (nie im Chat/Repo)
- [ ] Apple-Developer-Konto (Team-ID vorhanden): Apple-ID und App-Store-Connect-App-ID bereitstellen, wenn es soweit ist
- [ ] **Client-Bibliothek `@trafficnetwork/react-native`:** im Trafficnetwork-Repo existiert kein Tag `client-lib-v*` und damit kein Release mit vorgebautem `.tgz` (nur `server-v1.0.0`, `ingestion-v0.2.0`). Ohne dieses Artefakt bräuchten die EAS-Builder Rust, Android-NDK und `cargo-ndk`. Entscheidung: Tag `client-lib-v1.1.0` setzen (löst `release.yml` aus — bewusst deine Entscheidung) oder das CI-Artefakt `trafficnetwork-release-files` bereitstellen
- [ ] Netzfreigaben für diese Instanz: `api.expo.dev`, `reactnative.directory`, `docs.expo.dev` (Expo-Tooling/Doku) und für M5 Apple-Entwicklerdokumentation (App-Store-Richtlinien); `operations.osmfoundation.org` (Kachel-Richtlinie)
- [ ] Karten-Quelle entscheiden (siehe unten); Datenschutzerklärungs-URL, öffentlicher befüllter Server, Support-URL/Marketing-URL vor der Einreichung
- [ ] Lizenz der App bestätigen (derzeit Apache 2.0 wie das Monorepo)
- [ ] Android-Testgerät oder Emulator (derzeit keins)

## Entscheidungen / Risiken aus M0

- **Karte:** `tile.openstreetmap.org` wird nicht eingebaut (laut Repo-Doku kein Bulk/Prefetch/Offline, nur Best-Effort; Richtlinientext selbst nicht geprüft, Host gesperrt). Ziel: eigene Vektor-Kacheln (PMTiles) auf eigenem Server. Übergang: kommerzieller Anbieter oder OpenFreeMap — Nutzungsbedingungen und Eignung für App-Betrieb noch zu prüfen; ein API-Schlüssel in der App ist auslesbar. Namensnennung „© OpenStreetMap contributors" auf der Karte und im Info-Bereich.
- **React-Native-Anbindung der Bibliothek wurde nie ausgeführt** (nur gebaut, JSI-Schicht ungetestet). Erster Lauf in M2; ob sie mit Expo SDK 57 und der neuen Architektur läuft, ist offen.
- **SecureStore der Bibliothek muss synchron antworten.** `expo-secure-store` bietet synchrone Aufrufe — in M2 zu prüfen; Rückfall: verschlüsselter MMKV oder Dateispeicher.
- **TLS:** die Bibliothek vertraut nur den eingebauten Mozilla-Wurzeln; ein echter Handshake ist nirgends getestet; Seeds `seed1./seed2.trafficnetwork.info` sind noch nicht im DNS.
- **Standortabfluss:** `updatePosition` sendet grobe H3-Kacheln (~2,4 km, bei >100 km/h zwei Ringe) an den Server; im Fahrmodus laufend. Gehört in `docs/privacy-mapping.md` (M5); die App ruft `updatePosition` nur auf, wenn nötig.
- **Wünsche für `client-lib 1.2`** (nicht in der App bauen): richtungsbewusstes `getSpeedLimitAt` (`heading` wird heute ignoriert), Voraus-Filter entlang der Fahrtrichtung/eigenen Fahrbahn, Entprellen von Warnungen, Map-Matching über mehrere Positionen. Bis dahin: Übergangslösung hinter einer Schnittstelle (M4).
- `expo-doctor` und `expo install` laufen in dieser Umgebung wegen der Netzsperre nur eingeschränkt; Versionen kommen aus `bundledNativeModules.json`.

## Entwicklung

- [ ] M2 Bibliothek einbinden, Karte, Ansehen, „Server verbinden"
- [ ] M3 Melden, Bestätigen, Offline-Puffer
- [ ] M4 Fahrmodus, Simulationsfahrt, Blitzer-Filter und Hinweise, Fahrsperre
- [ ] M5 Politur, Barrierefreiheit, eigenes Icon und Splash (derzeit Expo-Platzhalter), Store-Texte, Datenschutz-Zuordnung, `ITSAppUsesNonExemptEncryption` begründet setzen
- [ ] M6 Abnahmefassung; M7 Einreichung erst nach schriftlichem „Abnahme"

## Bewusst nicht in 1.0

- Navigation und Routenführung
- CarPlay und Android Auto (eigene Berechtigungen/Entitlements)
- Widgets
- Apple Watch
- Play-Store-Upload (Android wird gebaut und getestet, nicht hochgeladen)
