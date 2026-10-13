# Datenschutz-Zuordnung (App-Datenschutz-Angaben, „Privacy Nutrition Label")

Abgeleitet aus dem, was die App **tatsächlich** sendet (Stand `0.1.0`, Bibliothek 1.2.0; Nachtrag E ergänzt unten die Zeilen „Meldedauer“, „Tempolimit-Vorschlag“ und „Online-Abfrage“). Quellen: `client-lib/docs/api.md` („Network & privacy"), `server/docs/api.md`, der Code dieser App. Der Server-Betrieb (Protokolle, Aufbewahrung) liegt beim Betreiber; seine Angaben stehen in `docs/privacy.md` des Trafficnetwork-Repos und sind hier **nicht** geprüft. Dies ist keine Rechtsberatung.

## Was das Gerät verlässt

| Was | Wann | Wohin | Genauigkeit | Zweck |
|---|---|---|---|---|
| Gerätezugang anlegen (`POST /v1/devices/register`), öffentlicher Signaturschlüssel binden (`bind-key`) | beim ersten Abgleich | Server des Netzwerks | pseudonyme Kennung (Client-ID, öffentlicher Schlüssel), kein Name, keine E-Mail | Funktion (Meldungen zuordnen, Missbrauch begrenzen) |
| **Kachel-IDs** (H3, Auflösung 7, etwa 2,4 km Kantenlänge, bei über 100 km/h zwei Ringe) | bei jedem Abgleich, solange die Kartenansicht oder der Fahrmodus den Standort meldet (`updatePosition`) | Server | **grober Standort** (Zelle, keine Koordinate) | Funktion (nur Daten rund um den Standort laden) |
| **Meldung** (Art + genaue Koordinate, Zeitpunkt über den Server), Bestätigung/Widerlegung | nur, wenn der Nutzer sie bewusst absetzt (Taste im Melden-Blatt, Ein-Tipp im Fahrmodus, „Noch da?") | ein Server, signiert mit dem Geräteschlüssel | **genaue Koordinate** der Meldung; **keine Geschwindigkeit** | Funktion (Gefahr teilen) |
| **Gewählte Meldedauer** (`ttlSeconds`, nur wenn der Nutzer „Eigene Dauer“ wählt; sonst nichts) | zusammen mit der Meldung, auf Handlung des Nutzers | ein Server, wie die Meldung | eine Zahl (Sekunden), kein Ort | Funktion (wie lange die Meldung gilt) |
| **Tempolimit-Vorschlag** (`reportMissingSpeedLimit` / `reportWrongSpeedLimit`: Wert, Einheit, Grund, **genaue Koordinate** der angetippten Straße) | nur nach „Senden“ im Tempolimit-Dialog, nie im Fahrmodus und nie bei Fahrsperre | ein Server, signiert mit dem Geräteschlüssel | **genaue Koordinate** der Straße | Funktion (Karte verbessern) |
| **Online-Abfrage eines Tempolimits** (`lookupSpeedLimit`, `GET /v1/speed-limit?lat&lng`) | nur wenn der Nutzer auf eine Straße **außerhalb des Offline-Bereichs** tippt; der Fahrmodus fragt nie online (nur lokale Lesezugriffe) | ein Server, mit Bearer-Zugang | **genaue Koordinate** der angetippten Stelle (aus dem Quellcode der Bibliothek, `core/src/api/client.rs`; die Bibliotheksdoku nennt es nicht, siehe `wishes-trafficnetwork.md` Nr. 4); die App speichert die Antwort nicht | Funktion (Tempolimit anzeigen) |
| Offline-Auswahl (`setOfflineRegions`, `setStorageLimits`) | bei Auswahl | nichts: Auswahl bleibt auf dem Gerät; der Abgleich holt danach nur die gewählten Kacheln/Regionen (Kachel-IDs wie oben, bzw. Region-IDs) | Region/Kachel, keine Koordinate | Funktion |
| IP-Adresse | bei jeder Anfrage | Server (technisch bedingt) | — | Verbindung |

Nicht gesendet: Name, E-Mail, Telefon, Kontakte, Fotos, Gesundheitsdaten, Käufe, Suchverlauf, Werbe-ID, Nutzungsstatistik, Absturzberichte (es gibt **keine** Analyse-, Werbe- oder Absturz-Bibliothek in der App). Die Position des Fahrmodus wird **nur lokal** für Warnungen ausgewertet (Tempo, Richtung, Abstand zu Meldungen); nach außen gehen nur die Kachel-IDs. Die Karte lädt von **keinem** Drittanbieter Kacheln (derzeit ohne Hintergrundkarte, `docs/map-sources.md`).

**Wo genaue Koordinaten abfließen — und nur dort:** (1) eine Meldung oder Bestätigung, (2) ein Tempolimit-Vorschlag, (3) die Online-Abfrage beim Antippen einer Straße außerhalb des Offline-Bereichs. Alle drei geschehen auf eine bewusste Handlung; (3) ist keine „Meldung“ im engeren Sinn, ist aber eine genaue Koordinate und steht deshalb hier ausdrücklich. Wer das nicht möchte, tippt außerhalb des Offline-Bereichs nicht auf Straßen oder wählt den Offline-Bereich so, dass er den Ort abdeckt („Offline-Daten“).

**Wo trotzdem grobe Standortinformation abfließt:** die Kachel-IDs (laufend im Fahrmodus, also eine grobe Spur der Fahrt auf dem Server, der sie beantwortet) und die IP-Adresse. Das Netzwerk verteilt Anfragen auf mehrere Server, damit kein einzelner Server das vollständige Profil sieht (`docs/federation.md`); ob das im Betrieb so greift, ist nicht von der App prüfbar.

**Dritte:** Server des föderierten Netzwerks werden von Dritten betrieben; Meldungen (Art, Koordinate, Signatur) werden zwischen Servern geteilt. Das gehört in die Datenschutzerklärung („Daten werden über Server Dritter verteilt") und in die Angabe „mit Dritten geteilt".

## Vorschlag für App Store Connect → App-Datenschutz

| Datentyp (Apple) | Erhoben? | Mit Identität verknüpft? | Zum Tracking? | Zweck |
|---|---|---|---|---|
| Standort → **Genauer Standort** | Ja (die Koordinate einer abgesetzten Meldung, eines Tempolimit-Vorschlags und die Koordinate einer angetippten Straße bei der Online-Abfrage außerhalb des Offline-Bereichs) | Ja (pseudonyme Geräte-ID) | Nein | App-Funktionalität |
| Standort → **Ungefährer Standort** | Ja (Kachel-IDs, ~2,4 km) | Ja (Anfragen sind mit der Geräte-ID authentifiziert) | Nein | App-Funktionalität |
| Kennungen → **Geräte-ID** | Ja (Client-ID / öffentlicher Schlüssel, vom Server vergeben) | Ja | Nein | App-Funktionalität |
| Nutzerinhalte → **Sonstige Nutzerinhalte** | Ja (Meldungen und Bestätigungen: Art, Ort, Zeit, gewählte Dauer; Tempolimit-Vorschläge: Wert, Grund, Ort) | Ja | Nein | App-Funktionalität |
| Alles andere (Kontaktdaten, Gesundheit, Finanzen, Browserverlauf, Nutzungsdaten, Diagnose, …) | Nein | — | — | — |

„Tracking" (Verknüpfung mit Daten Dritter für Werbung) findet nicht statt. **Offen:** ob der Betreiber Protokolle mit IP-Adressen führt (dann „Ungefährer Standort"/„Geräte-ID" ebenso, bereits oben genannt) und wie lange; das ist vor der Einreichung mit der Datenschutzerklärung des Betreibers abzugleichen.

## Berechtigungen und Hintergrund

- **Standort „Beim Verwenden der App"** (`NSLocationWhenInUseUsageDescription`). Es gibt **kein** „Immer". Hintergrund-Aktualisierung (`UIBackgroundModes: location`) läuft nur, solange der Fahrmodus gestartet ist (iOS zeigt die blaue Statusanzeige; Android einen Vordergrunddienst mit Benachrichtigung) und endet mit „Beenden". Außerhalb des Fahrmodus wird kein Standort im Hintergrund erfasst.
- **`UIBackgroundModes: audio`:** nur, damit gesprochene Warnungen und Töne bei ausgeschaltetem Bildschirm laufen.
- Kein Zugriff auf Mikrofon, Kamera, Fotos, Kontakte, Bluetooth.
- Schlüssel und Zugang liegen im Keychain/Keystore; Einstellungen in einer App-Datei.

## Löschen

„Lokale Daten löschen" und „Geräteidentität zurücksetzen" (Einstellungen) entfernen alles auf dem Gerät. **Auf dem Server** bereits abgesetzte Meldungen bleiben (pseudonym) bestehen; eine Löschung dort ist Sache des Betreibers (in der Datenschutzerklärung zu regeln).
