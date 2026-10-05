# Offene Punkte — Mobile

Nur, was wirklich offen ist.

## Beim Auftraggeber

- [ ] Expo-Konto: `eas login` und `eas init` (setzt `extra.eas.projectId`), `EXPO_TOKEN` als Secret für die Umgebung dieser Instanz (nie im Chat/Repo)
- [ ] Apple-Developer-Konto (Team-ID vorhanden): Apple-ID und App-Store-Connect-App-ID bereitstellen, wenn es soweit ist
- [x] Client-Bibliothek: Release `client-lib-v1.1.0` ist da; die App bindet `trafficnetwork-react-native-1.1.0.tgz` per Release-URL ein (Prüfsumme in `package-lock.json`, sha256 gegen `checksums.txt` geprüft)
- [ ] **Gerätezugang (Entscheidung nötig, betrifft Server/Bibliothek):** Ein Gerät registriert sich nur mit einem **App-Schlüssel** des jeweiligen Servers (`device-registration`, 50 Registrierungen pro Tag und Schlüssel, `server/docs/api.md`). Ein in die App eingebauter Schlüssel wäre auslesbar, und 50 pro Tag trägt keine öffentliche App. Heute kann die App daher nur Zugangsdaten verwenden, die der Nutzer unter „Server verbinden" selbst einträgt (im Schlüsselspeicher abgelegt). Für eine öffentliche Einreichung braucht es serverseitig eine andere Registrierung (z. B. Geräteprüfung mit App Attest / Play Integrity) — Wunsch an `server/`, nicht in der App lösbar
- [ ] Netzfreigabe für die Karten-Anbieter, falls eine Übergangsquelle geprüft werden soll (siehe `docs/map-sources.md`)
- [ ] Netzfreigaben für diese Instanz: `api.expo.dev`, `reactnative.directory`, `docs.expo.dev` (Expo-Tooling/Doku) und für M5 Apple-Entwicklerdokumentation (App-Store-Richtlinien); `operations.osmfoundation.org` (Kachel-Richtlinie)
- [x] Karten-Quelle: eigene PMTiles als Ziel, Übergangsquelle nur mit belegten App-Bedingungen (`docs/map-sources.md`)
- [ ] Datenschutzerklärungs-URL, öffentlicher befüllter Server, Support-URL/Marketing-URL vor der Einreichung
- [ ] Lizenz der App bestätigen (derzeit Apache 2.0 wie das Monorepo)
- [ ] Android-Testgerät oder Emulator (derzeit keins)

## Entscheidungen / Risiken aus M0

- **Karte:** siehe `docs/map-sources.md`. Ohne eingerichtete Quelle zeigt die App nur die eigenen Daten auf einfachem Hintergrund.
- **React-Native-Anbindung der Bibliothek wurde nie ausgeführt** (nur gebaut, JSI-Schicht ungetestet) — **auch von dieser App noch nicht:** hier gibt es kein Gerät und keinen Emulator. Geprüft ist nur, dass die Typen passen, die JavaScript-Bundles bauen und das Autolinking beide nativen Bibliotheken (Trafficnetwork, MapLibre) für Android und iOS findet. Ob die JSI-Schicht mit Expo SDK 57 und der neuen Architektur läuft, ob MapLibre die Layer zeichnet und ob der Android-/iOS-Build durchläuft: **offen bis zum ersten EAS-Build und Lauf auf einem Gerät (iPhone vorhanden)**.
- **SecureStore der Bibliothek muss synchron antworten.** Umgesetzt mit `SecureStore.getItem/setItem` (synchron). `expo-secure-store` hat **kein synchrones Löschen**: ein Eintrag wird mit einer Markierung überschrieben und liest sich als „nicht da"; „Geräteidentität zurücksetzen" (M5) löscht die Einträge mit `deleteItemAsync` (`wipeLibrarySecrets`, vorbereitet). Ob der Aufruf aus einem Bibliotheks-Thread in der Praxis funktioniert, ist ungeprüft.
- **Keychain überlebt unter iOS eine Neuinstallation.** Darum liegen Einstellungen (und später die Fahrsperre) in einer App-Datei, nicht im Schlüsselspeicher. Geräteschlüssel und Zugang bleiben dagegen im Keychain; wie sich die Bibliothek nach einer Neuinstallation mit altem Schlüssel verhält, ist offen.
- **http:** Die Bibliothek nutzt ihren eigenen Netzwerkstack und umgeht damit iOS-ATS und Android-Cleartext-Regeln. Die App erlaubt `http://` deshalb nur in Development-Builds (`__DEV__`, für das lokale Testnetz) und verlangt sonst `https://`.
- **Berechtigungen (Prebuild geprüft):** iOS enthält nur `NSLocationWhenInUseUsageDescription` (keine „Always"-Texte); Android blockiert Lese-/Schreibzugriff auf externen Speicher. `SYSTEM_ALERT_WINDOW` kommt vom Dev Client und ist im Release-APK in M6 zu prüfen.
- **TLS:** die Bibliothek vertraut nur den eingebauten Mozilla-Wurzeln; ein echter Handshake ist nirgends getestet; Seeds `seed1./seed2.trafficnetwork.info` sind noch nicht im DNS.
- **Standortabfluss:** `updatePosition` sendet grobe H3-Kacheln (~2,4 km, bei >100 km/h zwei Ringe) an den Server; im Fahrmodus laufend. Gehört in `docs/privacy-mapping.md` (M5); die App ruft `updatePosition` nur auf, wenn nötig.
- **Wünsche für `client-lib 1.2`** (nicht in der App bauen): richtungsbewusstes `getSpeedLimitAt` (`heading` wird heute ignoriert), Voraus-Filter entlang der Fahrtrichtung/eigenen Fahrbahn, Entprellen von Warnungen, Map-Matching über mehrere Positionen. Bis dahin: Übergangslösung hinter einer Schnittstelle (M4). Dazu aus M2: eine Methode für die **Liste der Meldungsarten** (heute nur die elf Typen aus `server/docs/api.md`; die App leitet die Filter aus den vorhandenen Daten ab und braucht für „Melden" in M3 eine Liste), das **Alter einer Meldung** (`NearbyItem` hat nur `expiresAt`, die Detailkarte zeigt „Gültig bis" statt „Alter") und **Regionen einzeln laden** (heute lädt `sync` alles, was der Server anbietet).
- **Live-Meldungen nur rund um den Standort:** Die Bibliothek abonniert nur die Kacheln um die zuletzt gemeldete Position (`updatePosition`). Schiebt der Nutzer die Karte weit weg, erscheinen dort nur Daten, die schon lokal sind.
- `expo-doctor` und `expo install` laufen in dieser Umgebung wegen der Netzsperre nur eingeschränkt; Versionen kommen aus `bundledNativeModules.json`.

## Entwicklung

- [x] M2 Bibliothek eingebunden, Karte, Ansehen, „Server verbinden", Datenpakete — **nur Typen, Tests und Bundles geprüft, nicht auf einem Gerät**
- [ ] Aus M2 offen: **Blitzer-Kategorie, Blitzer-Filter und Rechtshinweis (M4)** — die Karte zeigt Kameras/Zonen nur, wenn die Bibliothek sie liefert (`cameraNamespaceEnabled` bleibt aus)
- [ ] „Lokale Daten löschen" und „Geräteidentität zurücksetzen" (Einstellungen, M5)
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
