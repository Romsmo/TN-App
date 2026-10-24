# TNViewer in Flutter — Projektstand

Stand: 24.10.2026. Dieses Dokument fasst zusammen, was gebaut wurde, was geprüft ist, was auf Ihrem PC und bei GitHub liegt und was noch fehlt.
Die Detaildokumente liegen in `docs/` (`status.md`, `decisions.md`, `ios-install.md`, `privacy-mapping.md`, `wishes-clientlib.md`).

## 1. Auftrag in einem Satz

Die App TNViewer (Meldungen ansehen, melden, Fahrmodus mit Warnungen, **ohne** Navigation) wird in Flutter neu gebaut, mit funktionaler
Parität zur Spezifikation aus dem Export `TNViewer-export-2026-10-22`. Daten kommen ausschließlich über die Trafficnetwork-Client-Bibliothek
(Release `client-lib-v1.2.1`). Keine Analytics, keine Werbung, keine Telemetrie. Installation auf Ihr iPhone (iOS 27) von Windows aus.

## 2. Ampel

| Bereich | Stand |
|---|---|
| App-Code (Karte, Melden, Fahrmodus, Fahrsperre, Warnungen, Tempolimit, Offline, Einstellungen, Server, Notmodus, de/en) | **fertig** im Code |
| Logik-Tests (alle 14 Vektordateien aus `drive-core`, plus eigene Tests) | **271 Tests grün** |
| App-Tests (Widget-Tests) und `flutter analyze` | **6 Tests grün, sauber** |
| CI auf GitHub (`ci`: `core` und `app`) | **grün** |
| iOS-Build in der Cloud (macOS-Runner, unsigniert) | **läuft durch**, `.ipa` 18,1 MB |
| App auf einem Gerät (iPhone oder Android) | **nie gelaufen** |
| Signieren und Installieren auf das iPhone (xtool in WSL) | **offen**: Anmeldung bei Apple scheitert mit `HTTP 503` |
| Hintergrund-Standort, Töne, Sprache, Haptik, Akku, VoiceOver | **ungeprüft** (nur mit Gerät prüfbar) |
| Android-Build | **offen** (Android-SDK ohne cmdline-tools und Lizenzen, nicht angenommen) |
| Store / TestFlight | nicht Teil des Auftrags, nur nach Ihrer schriftlichen Freigabe |

## 3. Was gebaut ist

**Ordner:** `D:\Recent\Projects\TNV\tnviewer` (Git, Branch `flutter`).

- `packages/tn_core/`: reines Dart ohne Flutter. Fahrsperre (ab 10 km/h, frei nach 2 s unter 5 km/h, veraltet nach 60 s), Warn-Engine (zwei Stufen,
  Fahrspur-Korridor, Zonen ohne Entfernung), Fahrt-Sitzung, Simulationsfahrt, Einstellungen, Melden mit eigener Dauer, Tempolimit, Offline-Hilfen,
  die typisierte Schicht über die Bibliothek und die Verbindungslogik (Notmodus, „Nur im WLAN“).
- `lib/`: die Flutter-App. Karte (MapLibre mit Meldungen, Schildern, Blitzer-**Flächen**, Positionspfeil mit Genauigkeitskreis), Filter, Liste, Detailkarte,
  Melden-Blatt, Tempolimit-Modus, Fahrmodus-Bildschirm, Einstellungen, Server verbinden, Offline-Daten, Info, Sperrseite, Startlogo.
- `assets/`: Texte de/en (Deutsch verbindlich, Englisch unfreigegebene Übersetzung), Rechtstexte wörtlich, Töne, Bilder.
- `ios/`, `android/`: Berechtigungen (nur „Beim Verwenden“, nie „Immer“; Hintergrundmodi nur `location` und `audio`), Icons, Startbild.
- `web/`: eine Browser-Vorschau mit Demo-Daten, **nur** zur Entwicklung (kein Produkt).
- `tool/fetch_clientlib.sh`: lädt die Bibliothek 1.2.1 und prüft sie gegen die `checksums.txt` des Releases. Die Bibliothek selbst liegt nicht im Repo.
- `.github/workflows/`: `ci.yml` (Analyse und Tests) und `ios-beta.yml` (baut die unsignierte `.ipa` auf `macos-26`).

**Bibliothek:** 1.2.1 bringt, wie gewünscht, ein SwiftPM-Manifest im Flutter-Plugin und ein dynamisches `TrafficNetworkDart.framework`. Im gebauten
Paket ist es eingebettet (dynamische arm64-Bibliothek mit den `frb_*`-Funktionen).

## 4. Wie es geprüft wurde (und wie nicht)

- Logik: die Testvektoren aus dem Export laufen in Dart durch. Für die Sitzungsszenarien mussten zwei Annahmen getroffen werden (der Export beschreibt nicht, wie
  sie gefahren wurden); damit stimmen alle 16 Szenarien.
- UI: im Browser mit Demo-Daten gesehen (Karte, Detailkarte, Melden-Blatt, Tempolimit-Modus, Einstellungen, Simulationsfahrt mit Warnung „Unfall in 661 m“
  und „Noch da?“). Dabei sind zwei echte Fehler aufgefallen und behoben (Datumsformat, `clamp` im Web) und eine Überlauf-Stelle im Fahrmodus.
- Cloud-Build: `flutter build ios --release --no-codesign` mit echter Bibliothek und allen Plugins besteht (Lauf `40027344526`, rund 7 Minuten).
  Inhalt der `.ipa` geprüft: Bundle `info.trafficnetwork.tnviewer`, 0.1.0 (1), Mindest-iOS 13.0, arm64, nur Standort-Beschreibung „Beim Verwenden“, keine Signatur.
- **Nicht geprüft:** alles, was ein Gerät braucht (echter Standort, Hintergrund, Töne, Sprache, Haptik, Keychain, Zusammenspiel mit dem echten Server,
  Akkuverbrauch, VoiceOver/TalkBack).

## 5. Entscheidungen, die ich mit Standardwerten getroffen habe (bitte bestätigen oder ändern)

| # | Frage | Entscheidung |
|---|---|---|
| D-N1 | Soll der Fahrmodus `updatePosition` füttern? | Ja, höchstens einmal pro Minute oder je 500 m; nur die grobe Kachel (≈ 2,4 km) geht an den Server. Abschaltbar mit `DRIVE_FEEDS_TILES=false`. |
| D-N2 | `reportMissingSpeedLimit` gibt es in 1.2.1 nicht mehr | „Nachreichen“ läuft jetzt über zwei Punkte (Straßenabschnitt, `reportSpeedLimitInterval`). Die 11 neuen Texte dazu stammen von mir. |
| D-N4 | Karten-Plugin | `maplibre_gl` 0.27.1 (passt zu Ihrem Flutter 3.38.7). |
| D-N5 | Kartenhintergrund | keiner (nur die Daten des Netzwerks auf einer Fläche, „© OpenStreetMap contributors“ immer sichtbar). |
| D-N6 | Web-Test-PWA | nicht weitergeführt. |
| D-N7 | Repo | `Romsmo/TN-App`, neuer Branch `flutter`, mit Ihrer Freigabe gepusht. |
| D-N8 | Lizenz, englische Rechtstexte | Apache 2.0 als Entwurf, Englisch als unfreigegebene Übersetzung. |

Datenschutz: Was das Gerät verlässt, steht in `docs/privacy-mapping.md` (Entwurf für einen Anwalt). Neu gegenüber dem Expo-Stand: grobe Kacheln im Fahrmodus
und die beiden Endpunkte eines Straßenabschnitts beim Tempolimit-Vorschlag.

## 6. Der Weg aufs iPhone (Gate 0)

Gewählt: **Weg (b)**. Ein macOS-Runner baut die unsignierte `.ipa`, **xtool** in WSL signiert und installiert sie mit Ihrer Apple-ID
(Anmeldemodus „Password“, kein bezahltes Entwicklerkonto nötig, dafür 7-Tage-Profile).

| Schritt | Stand |
|---|---|
| Cloud-Build der `.ipa` | **erledigt** (Artefakt `TNViewer-unsigned-ipa`, 18.023.116 Bytes, SHA-256 `f44d81b6…8237d33f`, abrufbar bis 30.10.2026; lokal in `ipa-check/`) |
| Ubuntu 24.04 in WSL2 | **installiert** auf `D:\wsl\ubuntu-24.04`, Benutzer `rsmol` |
| `usbipd-win` 5.3.0 | **installiert** (Administrator-Abfrage von Ihnen bestätigt), Dienst läuft |
| `usbmuxd` 1.1.1 in Ubuntu | **installiert** |
| xtool 1.23.0 als `/usr/local/bin/xtool` | **installiert**, SHA-256 geprüft, braucht weder Swift noch Xcode |
| `xtool auth` (Apple-Anmeldung) | **scheitert** mit `HTTP 503` von `gsa.apple.com` (zweimal); Sie versuchen es später erneut |
| iPhone vorbereiten (Entwicklermodus, USB, `usbipd bind` und `attach`) | **offen** |
| `xtool install TNViewer-unsigned.ipa` | **offen** |

Wichtige Klärungen unterwegs: xtool kann Flutter nicht bauen, aber `xtool install` braucht weder die Xcode-Datei noch die Swift-Toolchain (Quelltext
`InstallCommand.swift` gelesen). Ein früherer Ansatz mit **xcross** war ein Missverständnis und wurde vollständig zurückgebaut.

Offene Risiken: die Apple-Anmeldung (private Schnittstellen, 503), die USB-Durchreichung per `usbipd` (Ausweich: iTunes-Weg aus der xtool-Doku),
ob xtool das eingebettete dynamische Framework richtig mitsigniert, 7-Tage-Profil (wöchentlich neu installieren), eine mit dem iOS-26-SDK gebaute App auf iOS 27.

## 7. Was auf Ihrem PC liegt

| Ort | Inhalt |
|---|---|
| `D:\Recent\Projects\TNV\tnviewer` | das Flutter-Projekt (Git-Klon von `Romsmo/TN-App`, Branch `flutter`) |
| `D:\Recent\Projects\TNV\export-2026-10-22` | der entpackte Export (Prüfsummen geprüft) |
| `D:\Recent\Projects\TNV\clientlib-1.2.1` | die heruntergeladene Bibliothek 1.2.1 (geprüft) |
| `D:\Recent\Projects\TNV\ipa-check` | `TNViewer-unsigned.ipa` und der Artefakt-Zip, entpackt zur Prüfung |
| `D:\Recent\Projects\TNV\usbipd-dl` | das MSI von `usbipd-win` und das Installationsprotokoll |
| `D:\wsl\ubuntu-24.04` | die WSL-Festplatte von Ubuntu (≈ 1,4 GB) |
| Windows | `usbipd-win` 5.3.0 (Dienst), WSL-Distribution `Ubuntu-24.04` |

Zurückgebaut: Swift, LLVM, Python 3.10, `pymobiledevice3` samt pip-Paketen, xcross, ein zweites Flutter 3.44.9, alle PATH-Einträge.
Ihr Flutter 3.38.7 ist unverändert. Hinweis: `C:` hat nur noch ≈ 12 GB frei, `D:` ≈ 67 GB. Norton prüft TLS (pip brauchte einmalig `--cert …\wscert.pem`).

## 8. GitHub

- Repo: `Romsmo/TN-App`, Branch **`flutter`** (ohne gemeinsame Historie mit dem Expo-Stand; alle anderen Branches unberührt).
- Gepusht bis Commit `9eaf193`. **Lokal noch nicht gepusht:** `ebd96ca` (Doku zum xtool-Weg und Ergebnis des Cloud-Builds) und diese Datei `PROJEKTSTAND.md`.
- Der macOS-Workflow läuft von Hand (`gh workflow run ios-beta.yml --ref flutter`) oder wenn die Workflow-Datei auf `flutter` geändert wird.
  Server-Variablen (`TN_DEFAULT_NODE`, `TN_APP_CLIENT_ID`, `TN_NETWORK_ROOT_KEY`, `MAP_STYLE_URL`, Secret `TN_APP_CLIENT_SECRET`) sind **nicht gesetzt**:
  Der Build läuft im Notmodus. Die Werte tragen Sie selbst ein.

## 9. Wünsche und Funde für die Bibliothek / den Export

- Pubspec des Flutter-Plugins verweist auf `path: ../dart`, die Tarballs entpacken aber zu anderen Ordnernamen (ich entpacke nach `packages/dart` und `packages/flutter`).
- `lookupSpeedLimit` und Vorschläge senden genaue Koordinaten; „Network & privacy“ nennt das nicht.
- Voraus-Filter, Report-Typen-Liste und „letzter Erfolg“ statt „letzter Versuch“ gehören in die Bibliothek.
- Export: doppelt kodierte deutsche Texte in `misc.json`; die Sitzungsvektoren beschreiben nicht, wie sie gefahren wurden; ein veralteter Textschlüssel `data.regionNote`.

## 10. Was als Nächstes dran ist

1. **Sie:** `xtool auth` später einmal erneut versuchen (Hinweis: nicht mehrfach hintereinander; ggf. Wegwerf-Apple-ID, anderes Netz).
2. **Sie:** iPhone vorbereiten (Entwicklermodus, USB, `usbipd bind` und `attach`), dann `xtool devices` und gemeinsam `xtool install`.
3. **Dann:** erster Lauf auf dem Gerät. Danach gehen die Funktionen der Reihe nach auf dem Gerät durch (Karte, Melden, Fahrmodus, Standort im Hintergrund, Töne,
   Sprache), und die offenen Fragen aus Abschnitt 5 werden abgehakt.
4. **Sie:** Server-Adresse, App-Schlüssel und optional Kartenstil in den Repository-Variablen eintragen, damit die App nicht im Notmodus startet.
5. **Später:** Android-Build (cmdline-tools und Lizenzen nötig), VoiceOver/TalkBack-Test, Akkumessung, Rechtstexte prüfen lassen.

## 11. Regeln, die gelten

Keine Geheimnisse im Repo, in Logs oder im Chat (Apple-ID, Passwort, 2FA, Schlüssel tippen Sie selbst). Kein Merge, Tag, Release, Store- oder TestFlight-Upload
ohne Ihre ausdrückliche Freigabe. Pushen nur nach Ihrem Ja. Rechtstexte sind Entwürfe für einen Anwalt, keine Rechtsberatung. Nichts von Blitzer.de übernommen.
