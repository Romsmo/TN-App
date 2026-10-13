# V0 — Machbarkeit der Web-Testapp (TNViewer Web) und Plan für Nachtrag E

Stand 2026-10-13. **Kein Code, keine Veröffentlichung, keine Einrichtung.** Dieses Dokument legt Fakten, Varianten, Risiken und offene Fragen vor, wie der Auftrag es für V0 verlangt. Was nicht belegt werden konnte, ist als solches markiert.

## 1. Repo-Lage

- **TN-App** (`Romsmo/TN-App`) ist das Arbeitsrepo, **öffentlich** (GitHub-API: `private: false`). Es hat **keinen Branch `main`**: der Standard-Branch ist der Arbeitsbranch `claude/tnviewer-mobile-setup-gcv37k`, es gibt keinen Pull Request.
- **Trafficnetwork** ist Lieferant: ich habe dort **nichts angelegt und nichts geändert** (lokale Kopie, `git status` sauber; gelesen wurden `server/docs/api.md`, `client-lib/docs/*`, `CHANGELOG.md`, `server/src/app.ts`). Es gibt dort keinen `mobile/`-Ordner und keine Einträge von mir; ein Umzug ist nicht nötig.
- Das Trafficnetwork-Repo ist **öffentlich**, die Release-Dateien sind ohne Token abrufbar (geprüft: `client-lib-v1.2.0/trafficnetwork-client-web-1.2.0.tgz`, `…-react-native-1.2.0.tgz` und `checksums.txt` antworten mit 200). Die CI von TN-App braucht daher **kein** Lese-Token. Wird das Repo später privat, ist ein auf Lesen beschränktes Token als CI-Secret der einfachste sichere Weg; das lege ich dann nicht selbst an.

## 2. Abhängigkeiten und Reihenfolge

| | Stand |
|---|---|
| `client-lib 1.2.0` | **vorhanden** (Tag `client-lib-v1.2.0`, 2026-10-11), rein additiv auf der Aufrufseite, `apiVersion` bleibt 1 |
| `server 1.1.0` | **vorhanden** (Tag `server-v1.1.0`) |
| native App heute | auf `client-lib 1.1.0` |

M3 (Melden) und M4 (Fahrmodus) sind in der nativen App schon gebaut, **sie verschieben sich nicht**. Teil 1 und die Web-App setzen aber den Umstieg auf 1.2.0 voraus; vorgeschlagene Reihenfolge:

1. **P0 — Umstieg der nativen App auf 1.2.0** (kleiner eigener PR: Paket-URL und Prüfsumme, Tests, `SyncReport`-Felder, `ErrorCode`-Werte).
2. **Teil 1** in drei PRs: (a) Pfeil + Zentrieren, (b) Ablaufzeit beim Melden + neue Verfallszeiten, (c) Tempolimit nachreichen + Offline-Bereich + Datenschutz-Doku.
3. **Web-Testapp V1–V5**, je ein PR.

**Verhaltensänderung in 1.2.0, die ich vor dem Umstieg ernst nehme:** *ein Client, der nie eine Position nennt, lädt keine Statikdaten mehr.* Die App nennt die Position erst nach der Standortfreigabe. Ohne Freigabe bliebe die Karte leer, obwohl der Server erreichbar ist. Das gehört in P0 gelöst (Offline-Modus bewusst setzen oder Region wählen lassen) und ist ein Grund, Teil 1 Punkt 4 früh zu bauen.

## 3. Was die Bibliothek im Browser kann (Quelle: `client-lib/docs/integration-web.md`, Version 1.2.0)

- Paket `@trafficnetwork/client-web` (WebAssembly), **`.wasm` 2,04 MB, gzip 0,76 MB** (selbst gemessen am heruntergeladenen Release, Prüfsumme gegen `checksums.txt` geprüft).
- Speicher: komplette Datenbank **im Arbeitsspeicher**, in IndexedDB gespiegelt (Schreibvorgänge innerhalb von 250 ms teilen sich einen Schnappschuss). Taugt für **kleine Regionen**, nicht für „ganz Europa auf dem Gerät“.
- **Ein Tab pro Datenbank** (zwei Tabs überschreiben sich). Die App muss das selbst absichern (Sperre/`BroadcastChannel`).
- **Geheimnisse standardmäßig in `localStorage`** (von jedem Skript derselben Herkunft lesbar). Ein eigener `secureStore` muss synchron sein, WebCrypto-Speicher scheidet damit aus. Die Anforderung „nicht exportierbar, WebCrypto“ aus dem Auftrag lässt sich mit der Bibliothek **nicht erfüllen**; die Grenze steht dann in `web-limits.md`.
- **Keine Hintergrundarbeit**, kein Service-Worker-Modus: Sync nur im sichtbaren Tab, `tick()` per Timer.
- Server müssen per `https://`/`wss://` erreichbar sein (Mischinhalte); der **Referenzserver beantwortet Cross-Origin-Anfragen** (`@fastify/cors` mit `origin: true`, `server/src/app.ts`). **CORS ist deshalb kein Wunsch an das Trafficnetwork-Repo**, solange mein Server dieses Verhalten behält.
- Die Browser-Anbindung hat die generische Methode **`call(method, args)`**. Unser `TnService` spricht schon heute nur diese Form (`callAsync(method, argsJson)`): ein Adapter von etwa 30 Zeilen genügt, `TnService` und alles darüber bleiben unverändert (Grundlage für Variante A).
- 1.2.0 liefert im Browser die neuen Methoden `getReportLimits`, `lookupSpeedLimit`, `reportMissingSpeedLimit`, `setOfflineRegions`, `listOfflineRegions`, `setStorageLimits` (typisiert).

### Zugang (Registrierung)

Ein Gerät registriert sich nur mit einem **App-Schlüssel** des Servers (`credentials: {type:"app"}`) oder bekommt ein fertiges Client-Zugangspaar. **Ein Schlüssel im Code einer öffentlichen Web-App wäre für jeden lesbar** (und CLAUDE.md verbietet Secrets im Repo). Konsequenz: Der Zugang wird **je Tester in der App eingetragen** („Server verbinden“, wie in der nativen App), nie eingebaut. Der Server begrenzt auf 50 Registrierungen pro Tag und Schlüssel.

## 4. Browser-Grenzen mit Quellen

**Wichtig zur Belegqualität:** Aus dieser Umgebung waren MDN, caniuse, webkit.org und docs.github.com **nicht erreichbar** (DNS-Fehler). Die Angaben stammen aus einer Websuche (Sekundärquellen, jeweils verlinkt) und sind mit „vermutlich“ markiert, wo sie veraltet sein können. **Der Gerätetest (V5) ist die eigentliche Prüfung.**

| Thema | Befund | Quelle / Sicherheit |
|---|---|---|
| Wake Lock (Bildschirm bleibt an) | Safari kennt die API; in **installierten** Home-Bildschirm-Apps ging sie nach WebKit-Fehler 254545 (iOS 16.4) nicht. Laut Suchtreffern in **iOS 18.4 behoben**; ein Folgefehler (Sperre nach Rückkehr vom Home-Bildschirm erneut anfordern, Fehler 255363) ist ungeklärt. MDNs Tabelle nennt „16.4–18.4: nicht in Standalone“. | [WebKit 254545](https://bugs.webkit.org/show_bug.cgi?id=254545), [WebKit 255363](https://bugs.webkit.org/show_bug.cgi?id=255363), [Progressier](https://progressier.com/pwa-capabilities/screen-wake-lock) — **mittel**, nur Gerätetest entscheidet |
| Vollbild | `display: fullscreen` bzw. `display_override` mit Rückfallkette fullscreen → standalone → minimal-ui → browser; auf iOS vermutlich nur `standalone`/`browser` (aus dem Gedächtnis, **nicht belegt**) | [Chrome-Doku zu display-override](https://developer.chrome.com/docs/capabilities/display-override) — Android **hoch**, iOS **unbelegt** |
| Speicher-Löschung | Safari löscht seit 13.4/13.1 skriptbeschreibbaren Speicher (IndexedDB, `localStorage`) nach 7 Tagen ohne Nutzung; Home-Bildschirm-Apps haben laut WebKit einen eigenen Zähler. Ein Fehlerbericht (237350, iOS 15.3) meldet trotzdem Abmeldung nach 7 Tagen. | [Search Engine Land](https://searchengineland.com/what-safaris-7-day-cap-on-script-writeable-storage-means-for-pwa-developers-332519), [WebKit 237350](https://bugs.webkit.org/show_bug.cgi?id=237350) — **mittel**; die App muss Verlust erkennen und neu laden |
| Vibration | `navigator.vibrate` wirkt auf iOS-Safari nicht (je nach Quelle fehlt die Funktion oder liefert `false`) | [bugnet.io](https://bugnet.io/blog/fix-web-game-vibrate-api-not-available-ios-safari) u. a. — **mittel**; Rückmeldung dort optisch/akustisch |
| Geräteausrichtung (Kompass) | iOS braucht eine ausdrückliche Freigabe per Tippen (`DeviceOrientationEvent.requestPermission`); die Richtung der Standortfreigabe (`heading`) ist in Ruhe `null` | Suche lieferte dazu keinen Treffer — **aus Gedächtnis, unbelegt**, im Gerätetest prüfen |
| Ton/Sprache | Start erst nach Nutzerhandlung (Autoplay-Regeln) | Standardverhalten, im Gerätetest prüfen |
| Standort | nur über HTTPS | Standard, in der Bibliotheksdoku für Mischinhalte bestätigt |
| GitHub Pages | Seite ≤ 1 GB, weiche Grenze 100 GB Datenverkehr/Monat, Zeitlimit 10 Min je Veröffentlichung; **öffentliche Repos mit Free-Tarif**, private nur mit bezahltem Tarif; 10-Builds-pro-Stunde-Grenze gilt nicht für eigene Actions-Workflows | [GitHub-Doku zu Pages-Grenzen](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits) (über Suche bestätigt, Seite selbst nicht abrufbar) — **hoch** |

## 5. Variante A oder B (Entscheidung offen, Empfehlung A)

### A — Expo-Web-Export derselben Oberfläche, Adapter für Bibliothek und Karte

**Belegt:** `expo export --platform web` rendert schon heute **alle echten Bildschirme** der App im Browser (die Vorschau, die ich dir gezeigt habe; Gesamtgröße der Seite 1,9 MB einschließlich Symbolschrift, Mocks statt nativer Module). Alles Reine ist geteilt: `src/drive/*` (Warn-Engine, Fahrsperre, Einheiten, Geometrie), `src/tn/*`, `src/state/*`, `src/i18n`, `src/legal`, `src/settings`, alle Bildschirme und deren ~370 Tests.

**Zu bauen (Adapter, keine Neuschreibung):**
| Native Baustein | Web-Ersatz |
|---|---|
| `@trafficnetwork/react-native` | `@trafficnetwork/client-web` über den `call()`-Adapter (siehe 3) |
| `@maplibre/maplibre-react-native` | `maplibre-gl` hinter derselben `MapView`-Schnittstelle (Layer, Pfeil, Tippen, `flyTo`) — **auch Variante B braucht das** |
| `expo-secure-store` | synchroner `localStorage`-Speicher (Grenze siehe 3) |
| `expo-location` | Web-Implementierung nutzt `navigator.geolocation` (Vordergrund) |
| `expo-keep-awake`, `expo-audio`, `expo-speech` | haben Web-Fassungen; Wake-Lock/Ton-Freischaltung im Gerätetest prüfen |
| `expo-task-manager`, Hintergrund-Standort, `expo-haptics` | entfallen bzw. ohne Wirkung (ehrlich ausweisen) |
| Löschen der lokalen Daten | `indexedDB.deleteDatabase` |

PWA-Teile (Manifest, Service Worker, Symbole, Unterpfad `/TN-App/` über `experiments.baseUrl`) kommen als eigener Schritt nach dem Export; ein Nachbearbeitungs-Skript erzeugt Manifest und Dateiliste für den Service Worker.

**Aufwand:** mittel (Adapter, Karte, PWA-Hülle, Tests). **Risiken:** (1) React-Native-Web-Eigenheiten bei Vollbild/Berührung/Sicherheitsabstand; (2) Größe: JS-Bündel der Vorschau ~1,9 MB unkomprimiert (gzip deutlich kleiner, nicht gemessen) plus 0,76 MB WASM gzip; (3) die Bibliotheksgrenze „ein Tab pro Datenbank“ muss gelöst werden; (4) Expo-Web-Ausgabe ist ein Single-Page-Bündel ohne Server (genügt hier).

### B — eigene schlanke Oberfläche (Vite + TypeScript + `maplibre-gl`) auf einem gemeinsamen Kern

Der Kern (`packages/drive-core/`) enthielte Warn-Engine, Fahrsperre, Einheiten, Geometrie, Filterregeln — heute reine TS-Dateien in `src/drive` und `src/map`, die sich ohne große Mühe verschieben lassen. **Zu bauen:** alle Bildschirme neu (Karte, Meldesheet, Detailkarte, Fahrmodus, Einstellungen, Server, Info, Notmodus, Rechtstexte, Hell/Dunkel, Barrierefreiheit) und deren Tests.

**Aufwand:** hoch (rund doppelt so viel Oberfläche, zwei Stellen für jede künftige Änderung). **Vorteil:** kleiner, volle Kontrolle über Vollbild/PWA-Verhalten, kein React-Native-Web. **Risiko:** zwei Oberflächen laufen auseinander; Teil 1 müsste doppelt gebaut werden.

### Empfehlung

**A.** Die gleiche Oberfläche und Logik in beiden Apps ist der Kern des Auftrags („dieselben Regeln wie die native App“), A ist bereits zu großen Teilen im Browser belegt, und die Adapter sind klein. B nur, wenn der Gerätetest zeigt, dass React-Native-Web im Handy-Browser nicht gut genug ist; das lässt sich früh in V1/V2 prüfen (ein Satz Messungen: Start, Berührung, Vollbild), bevor viel gebaut ist.

Ein `packages/drive-core/` brauche ich bei A **nicht**: der gemeinsame Kern ist `src/` selbst.

## 6. Hosting (GitHub Pages)

- TN-App ist **öffentlich**, Pages im Free-Tarif möglich. Adresse: `https://romsmo.github.io/TN-App/` (Unterpfad `/TN-App/` ist für Manifest, Service Worker und Assets zu beachten).
- Veröffentlicht wird per Actions-Workflow (`.github/workflows/web-pages.yml`), Quelle in den Repo-Einstellungen: **Pages → Build and deployment → Source: GitHub Actions** (das schaltest **du** ein; ich kann Repo-Einstellungen nicht ändern).
- Der Workflow soll nach Merge nach `main` veröffentlichen — **es gibt noch kein `main`** (siehe 1). Ohne `main` weder PR-Ziel noch Veröffentlichung.
- **Folge der Öffentlichkeit:** Quellcode und Web-App sind für alle sichtbar. Die Seite trägt „Testversion“; sie enthält keine Schlüssel.
- **Das erste Deployment erfolgt erst nach deiner ausdrücklichen Freigabe.**

## 7. HTTPS-Weg zu deinem Server (Vorschlag, noch nichts eingerichtet)

Die Seite ist HTTPS, also muss auch der Server `https://`/`wss://` sprechen. Reihenfolge von einfach nach dauerhaft:

1. **Temporärer Tunnel** mit `cloudflared tunnel --url http://localhost:3000` (Quick Tunnel: kein Konto, wechselnde `https://…trycloudflare.com`-Adresse, nur für Tests; erfordert `cloudflared` auf dem Rechner, der den Server hostet). Drei Sätze: Server lokal starten, Tunnel starten, die angezeigte Adresse in der Web-App unter „Server verbinden“ eintragen.
2. **Eigener Host mit Domain** (z. B. ein Server mit Caddy/Let's-Encrypt-Zertifikat). Dauerhaft, kostet einen Host und eine Domain; `trafficnetwork.info` ist noch nicht im DNS.
3. Tunnel-Dienste mit Konto (z. B. ngrok) — nur, wenn du ein Konto willst.

Ich richte nichts davon ein, bevor du freigibst; ich brauche zuerst: **Wo läuft dein Server, mit welcher Adresse?**

## 8. Plan der Stufen

| # | Inhalt | Ergebnis |
|---|---|---|
| P0 | native App auf client-lib 1.2.0 (+ Lösung „Position noch unbekannt“) | PR |
| T1a | Pfeil in Fahrtrichtung, Genauigkeitskreis, Zentrieren (aus/zentriert/folgt) | PR |
| T1b | Ablaufzeit beim Melden (`getReportLimits`), neue Verfallszeiten aus dem Server | PR |
| T1c | Tempolimit nachreichen/korrigieren, Offline-Bereich verwalten, Datenschutz-Zuordnung | PR |
| V1 | Gerüst: PWA (Manifest, Service Worker, Symbole), Workflow (Deployment erst nach OK) | PR |
| V2 | Bibliothek (WASM) eingebunden: Registrierung, Bootstrap, Abfrage, Meldung, Push, Puffer | PR |
| V3 | Karte, Ansehen, Melden, Pfeil, Filter, „Server verbinden“ | PR |
| V4 | Fahrmodus (Vordergrund), Fahrsperre, Simulationsfahrt, Blitzer-Regeln | PR |
| V5 | Tests, Gerätetest Android + iPhone, `web-limits.md`, Abnahmeanfrage | PR + Meldung |

Jede Stufe ein eigener, grüner PR; **nicht von mir gemergt**.

## 9. Gerätetest — was ich nicht kann

Ich habe keinen Zugriff auf ein Android-Handy oder ein iPhone. Die Bestätigung am Ende von V5 („auf echten Geräten geprüft“) kann ich **nicht** abgeben; ich liefere die Playwright-Läufe mit Handy-Emulation und ein **Testprotokoll-Formular**, und **du** führst den Gerätetest aus (oder beschreibst, was scheiterte). Im Bericht steht dann „auf Geräten geprüft von dir“ bzw. „nicht geprüft“.

## 10. Offene Fragen an dich

1. **Variante A oder B?** (Empfehlung A, mit früher Messung in V1/V2.)
2. **`main` anlegen?** Aus dem heutigen Stand, damit PRs und Pages möglich sind. Ich lege es erst nach deinem OK an.
3. **Pages einschalten** (Repo-Einstellung, durch dich) und die **öffentliche Sichtbarkeit** akzeptieren (Repo bleibt öffentlich).
4. **Wo läuft dein Server, und wie erreichst du ihn per HTTPS?** (Tunnel für den Test, oder fester Host.)
5. **Zugang für die Web-App:** je Tester ein Zugang, den du ausgibst und der in der App eingetragen wird — einverstanden? (Ein Schlüssel im Code scheidet aus.)
6. **Reihenfolge** wie in 2 (P0, Teil 1, Web) oder Web zuerst?
7. **Gerätetest:** übernimmst du ihn mit meinem Protokoll?
