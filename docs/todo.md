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
- **Senden gekoppelt an das Laden der Kartendaten:** `sync` erledigt Kartendaten, Live-Meldungen und das Senden wartender Meldungen in einem Zug. Steht „Nur im WLAN" an und sind die Kartendaten noch nicht geladen, wartet deshalb auch das Senden einer Meldung auf WLAN (die App sagt das an). Wunsch an `client-lib 1.2`: das Senden der Warteschlange getrennt auslösen können (`flushWrites`).
- **Mehrknoten-Verhalten** (Serverwechsel, Ausfall mitten im Sync, Offline-Meldung an anderem Server) liegt in der Bibliothek; ihre Tests decken es ab. Die App hat dazu **keinen eigenen Test gegen ein Testnetz** (kein Docker/Gerät hier): offen.
- **Fahrmodus-Näherungen (Übergangslösung hinter `WarningEngine`):** „eigene Fahrbahn" ist ein schmaler Korridor entlang der Fahrtrichtung (25–100 m seitlich). Die Bibliothek liefert keine Straßengeometrie zu Meldungen; auf Autobahnen mit Mittelstreifen oder bei Kurven kann eine Meldung der Gegenrichtung auf großer Entfernung fälschlich warnen oder eine eigene verpasst werden. Gehört als Voraus-Filter in `client-lib 1.2`. Vorwarnzeiten (25 s / 8 s) und Mindestabstände sind Annahmen, nicht an echten Fahrten abgestimmt.
- **Hintergrund-Standort (Quelltext von `expo-location` gelesen):** `startLocationUpdatesAsync` verlangt unter iOS für einen vom Nutzer gestarteten Dienst nur die Vordergrund-Berechtigung („Beim Verwenden"). Ob der Dienst auf einem echten Gerät mit gesperrtem Bildschirm zuverlässig weiterläuft und die Aufgabe das JavaScript wach hält, ist **ungeprüft**.
- **Simulation:** Meldungen und Stimmen in der Simulation werden nicht gesendet. Die Strecke und alles darauf sind erfunden.
- **„Nur im WLAN" und neue Kartendaten:** Die App prüft den Download-Plan alle 10 Minuten neu. Veröffentlicht der Server neue Pakete, kann der **erste** Abgleich danach (die Bibliothek holt Konfiguration und Pakete in einem Zug) sie trotzdem über Mobilfunk laden. Sauber lösbar nur mit einer getrennten Funktion in `client-lib 1.2` (Plan abfragen und Pakete getrennt anstoßen).
- **Live-Meldungen nur rund um den Standort:** Die Bibliothek abonniert nur die Kacheln um die zuletzt gemeldete Position (`updatePosition`). Schiebt der Nutzer die Karte weit weg, erscheinen dort nur Daten, die schon lokal sind.
- `expo-doctor` und `expo install` laufen in dieser Umgebung wegen der Netzsperre nur eingeschränkt; Versionen kommen aus `bundledNativeModules.json`.

## Entwicklung

- [x] M2 Bibliothek eingebunden, Karte, Ansehen, „Server verbinden", Datenpakete — **nur Typen, Tests und Bundles geprüft, nicht auf einem Gerät**
- [x] Aus M2: Blitzer-Option (aus, Länderpolitik, Rechtshinweis) erledigt in M4; die Karte zeigt Kameras/Zonen nur, wenn die Option an ist (`cameraNamespaceEnabled`) **und** die Bibliothek sie liefert — nie gegen einen echten Server mit Blitzer-Daten geprüft
- [ ] „Lokale Daten löschen" und „Geräteidentität zurücksetzen" (Einstellungen, M5)
- [x] M3 Melden, Bestätigen, Offline-Puffer, Hinweise zu Wartezustand und Begrenzungen — **nur Typen, Tests und Bundles geprüft, nicht auf einem Gerät**
- [x] Melden einer Blitzer-Art: im Fahrmodus (Ein-Tipp) und auf der Karte nur „Blitzer (mobil)", nur bei Option an und Länderpolitik `full`; Arten und Wertebereich des Servers für feste Blitzer, Anhänger, Rotlicht und Abstand nicht geklärt (nur `mobileSpeedCamera` ist angeschlossen) — **offen**
- [ ] Aus M3 offen: Maestro-Abläufe ausführen (M5/M6)
- [x] M4 Fahrmodus, Simulationsfahrt, Blitzer-Option und Hinweise, Fahrsperre — **nur Tests und Bundles, nicht auf einem Gerät**
- [x] M5 Politur: Icon/Splash, Lizenzen, Listenansicht, Kontrast, Datenschutz-Zuordnung und -Entwurf, Store-Texte, Review-Hinweise, Risiken
- [ ] Aus M5 offen: VoiceOver/TalkBack **nicht mit einem Screenreader geprüft** (nur Beschriftungen und Tests); Schriftskalierung nicht auf dem Gerät geprüft; Screenshots; Datenschutz-URL in der App erreichbar machen (kommt mit der URL); `ITSAppUsesNonExemptEncryption` (siehe `docs/store-risks.md` #9); Entscheidung zur Fahrsperre-Option im Review-Build; **Akkuverbrauch einer Stunde Fahrmodus nicht gemessen**; Übersetzungen: die englischen Rechtstexte sind meine Übersetzung der deutschen Vorgaben und brauchen Freigabe
- [ ] M6 Abnahmefassung; M7 Einreichung erst nach schriftlichem „Abnahme"

## Bewusst nicht in 1.0

- Navigation und Routenführung
- CarPlay und Android Auto (eigene Berechtigungen/Entitlements)
- Widgets
- Apple Watch
- Play-Store-Upload (Android wird gebaut und getestet, nicht hochgeladen)
