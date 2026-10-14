# TNViewer Web — was ein Browser kann und was nicht

TNViewer Web ist der schnelle Probelauf von TNViewer im Handy-Browser (installierbare Web-App, „PWA“). Sie benutzt dieselbe Oberfläche und Logik wie die native App und die Client-Bibliothek 1.2.0 als WebAssembly. Sie ersetzt weder die native App noch die Weboberfläche des Servers. **Testversion.**

Stand: V1–V4 gebaut; **Gerätetest auf echtem Android und iPhone steht aus** (macht der Betreiber, Protokoll: `docs/web-geraetetest.md`). Spalte „Beleg“: **gemessen** = in dieser Entwicklung im Browser geprüft, **Quelle** = aus Dokumentation oder Fehlerberichten (Sekundärquellen, siehe `docs/web/v0-machbarkeit.md`, Abschnitt 4), **offen** = nur der Gerätetest klärt es.

## Grenzen

| Thema | Verhalten | Beleg |
|---|---|---|
| **Hintergrund** | Kein Hintergrundbetrieb. Sperrt der Bildschirm oder wechselt man die App, stoppen Standort, Warnungen, Ton und der Abgleich. Der Fahrmodus läuft nur bei **aktivem Bildschirm im Vordergrund**. Die Bibliothek hat im Browser keinen Service-Worker-Modus. | Quelle (Bibliotheksdoku) |
| **Bildschirm an** | Die Wake-Lock-API hält den Bildschirm an. Auf dem iPhone ging sie in installierten Home-Bildschirm-Apps bis iOS 18.4 nicht (WebKit-Fehler 254545, laut Berichten behoben); ob sie nach dem Wechsel in eine andere App wieder greift, ist offen (WebKit 255363). Fällt sie aus, sagt die App das nicht von selbst: der Bildschirm kann dunkel werden. | Quelle, **offen** |
| **Vollbild** | Android-Chrome: installiert, `display_override: fullscreen` mit Rückfall `standalone`. **iPhone:** im Safari-Tab gibt es kein Vollbild für Web-Seiten; nur über „Zum Home-Bildschirm“ (Standalone, ohne Browserleiste). Die App erkennt, ob sie so läuft, und zeigt sonst einen kurzen Hinweis mit den Schritten je System (einmal wegklickbar). | Quelle, **offen** (iOS-Vollbild unbelegt) |
| **Standort** | Nur über HTTPS. Auf dem iPhone liefert die Standortfreigabe Geschwindigkeit und Richtung nur in Bewegung. Fehlen sie (manche Browser), rechnet der Fahrmodus beides aus aufeinanderfolgenden Positionen aus. | gemessen (Ausrechnen, mit gesetzten Positionen), **offen** (echte Geräte) |
| **Ton und Sprache** | Browser spielen Ton und sprechen erst nach einer Handlung des Nutzers. Der erste Fingertipp (spätestens „Fahrt starten“) schaltet beides frei. Stimmen und Lautstärke hängen vom Gerät ab. Ton und Sprache laufen nicht bei gesperrtem Bildschirm. | Quelle, **offen** |
| **Vibration** | Nur Android. Auf dem iPhone wirkt `navigator.vibrate` nicht; dort tragen Bildschirm und Töne die Warnung. | Quelle |
| **Richtung/Kompass** | Der Pfeil folgt der Fahrtrichtung aus den Positionen (in Bewegung). Die Geräteausrichtung im Stand braucht auf dem iPhone eine eigene Freigabe; sie wird nicht verlangt, solange die App ohne sie auskommt. | Quelle, **offen** |
| **Speicher** | Der Browser darf Daten bei Platzmangel oder nach längerer Nichtnutzung löschen (Safari: 7 Tage ohne Besuch für Tabs; Home-Bildschirm-Apps haben laut WebKit einen eigenen Zähler, ein Fehlerbericht sagt anderes). Die App erkennt einen leeren Speicher und lädt neu; dann ist auch die Geräte-Identität neu (neue Registrierung). | Quelle, **offen** |
| **Datenmenge** | Die Bibliothek hält ihren Speicher im Arbeitsspeicher und spiegelt ihn nach IndexedDB. Das taugt für kleine Regionen. Der automatische Offline-Bereich (Umgebung der Position) begrenzt das; „alles laden“ ist im Browser nicht vorgesehen. | Quelle (Bibliotheksdoku) |
| **Ein Tab** | Zwei Tabs würden sich die Datenbank überschreiben. Der zweite Tab sieht „Schon geöffnet“ und startet die App nicht (Web Locks). Ohne Web-Locks-Unterstützung läuft die App ungeschützt. | gemessen |
| **Geheimnisse** | Der Browser hat keinen Schlüsselspeicher. Geräte-Zugang und Signaturschlüssel liegen in `localStorage`, lesbar für jedes Skript dieser Herkunft. Schutz: strenge Content-Security-Policy (nur eigene Skripte), keine Dritt-Skripte. **Die Forderung „nicht exportierbar über WebCrypto“ lässt sich mit der Bibliothek nicht erfüllen** (ihr Speicher muss synchron sein). | Quelle (Bibliotheksdoku) |
| **WLAN-Erkennung** | Ein Browser kennt die Verbindungsart nur auf manchen Systemen (Android-Chrome). Sonst gilt „unbekannt“ als nicht getaktet; „Nur im WLAN“ hält dann nichts zurück. | gemessen (Code), **offen** |
| **Kartenhintergrund** | Wie in der nativen App: keine Quelle voreingestellt, solange keine mit nachgewiesenen Bedingungen da ist (`docs/map-sources.md`). | — |

## Zugang: offen für alle Tester

Jedes Gerät braucht einen Server-Zugang. Die Web-App ist **für alle offen**: Sie trägt einen **öffentlichen App-Schlüssel** des Servers (Bereich `device-registration`), mit dem sich jedes Gerät selbst registriert. Dieser Schlüssel steht zwangsläufig im Quelltext der Seite und ist für jeden lesbar. Deshalb:

- Er ist ein **eigener** Schlüssel nur für die Web-Testapp (nie ein persönlicher Zugang) und lässt sich am Server widerrufen.
- Der Server begrenzt die Registrierungen **pro Schlüssel auf 50 am Tag** und pro IP-Adresse auf 10 in der Minute (`server/docs/api.md`). Mehr als 50 neue Geräte pro Tag sind so nicht möglich; das ist auch der Schutz gegen Missbrauch.
- Er kommt aus den **Repository-Variablen** des Builds (`TN_WEB_APP_CLIENT_ID`, `TN_WEB_APP_CLIENT_SECRET`), nicht aus dem Code.
- Ohne Schlüssel startet die App im **Notmodus** („kein Zugang“); wer einen eigenen Zugang hat, trägt ihn unter „Server verbinden“ ein.

## Speicherinventur (was die Seite im Browser ablegt)

| Ort | Name | Inhalt |
|---|---|---|
| `localStorage` | `tnviewer.settings` | Einstellungen (Einheit, Töne, Filter, Fahrsperre, …) |
| `localStorage` | `tnviewer.installHintDismissed` | Der Installationshinweis wurde weggeklickt |
| `localStorage` | `tn.*` | Geräte-Zugang und Signaturschlüssel der Bibliothek; `tn.app_access` = Zugang, den der Nutzer selbst eingetragen hat |
| IndexedDB | `tnviewer` | der Speicher der Bibliothek (Karten- und Meldungsdaten, Warteschlange der Meldungen) |
| Cache Storage | `tnviewer-<Build>` | die Dateien der App (für den Start ohne Netz) |
| Service Worker | `<Pfad>/sw.js` | liefert die App-Dateien aus dem Cache; fasst Anfragen an andere Herkunft nicht an |

Keine Cookies, kein Tracking, keine Analyse-Pakete. „Lokale Daten löschen“ in den Einstellungen leert IndexedDB; „Geräteidentität zurücksetzen“ entfernt Zugang und Schlüssel.

## Verbindungen nach außen

Erlaubt sind (Content-Security-Policy `connect-src`) die eigene Herkunft und **`https:`/`wss:`**, weil der Server des Nutzers frei wählbar ist. Ohne Eingabe spricht die App nur mit dem Server des Builds (`https://trafficnetwork.link/`). Es gibt keine weiteren festen Hosts. `style-src` erlaubt Inline-Stile (React Native Web schreibt sie zur Laufzeit); Skripte sind auf die eigene Herkunft und WebAssembly beschränkt.

## Messwerte

Siehe Abschnitt „Messwerte“ am Ende von `docs/web-geraetetest.md` (Größe, Startzeit, Speicher). Nicht messbar ohne Gerät: Akkuverbrauch einer halben Stunde Fahrt.
