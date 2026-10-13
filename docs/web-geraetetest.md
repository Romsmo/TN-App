# TNViewer Web — Gerätetest (Protokoll) und Messwerte

Die Web-App ist mit Playwright in einem Handy-großen Chromium gegen den Mock-Server der Client-Bibliothek getestet (`e2e/`, CI-Job `web-e2e`). **Das ersetzt keinen Test auf echten Geräten:** Safari/WebKit, Wake Lock auf dem iPhone, Töne und Sprache, Standortgenauigkeit, Vollbild und Akku kann nur ein Gerät zeigen. Diese Seite ist das Formular dafür.

## So öffnest du die App

1. Die Adresse ist `https://romsmo.github.io/TN-App/` — sie gibt es erst, wenn GitHub Pages eingeschaltet ist und die Pull Requests in `main` gemergt sind (Reihenfolge: siehe die Beschreibung von PR #1).
2. **Android (Chrome):** Adresse öffnen → Browser-Menü → „App installieren“ (oder die Schaltfläche „Installieren“ im Hinweis der App). Die App startet danach vom Startbildschirm im Vollbild.
3. **iPhone (Safari):** Adresse öffnen → „Teilen“ → „Zum Home-Bildschirm“. Nur so läuft sie ohne Browserleiste. Teste **beides**: im Safari-Tab und installiert.
4. Standort erlauben („Beim Verwenden der App“ bzw. „Nur dieses Mal/Beim Verwenden“).

## Protokoll (bitte ausfüllen)

Gerät: ____________ Betriebssystem/Version: ____________ Browser/Version: ____________ Datum: ____________

| # | Prüfung | Android Chrome | iPhone Safari (Tab) | iPhone installiert |
|---|---|---|---|---|
| 1 | Adresse öffnen: Logo, dann Karte; „Testversion“ sichtbar | | | |
| 2 | Hinweis „Als App installieren“ erscheint (nicht installiert) und ist wegklickbar | | | — |
| 3 | Installiert: **kein** Browserleiste, Vollbild (Android: ganz ohne Leiste) | — | — | |
| 4 | Standort freigeben: Pfeil/Punkt erscheint, „Auf mich zentrieren“ springt hin | | | |
| 5 | Verbindung: kein „Notmodus“-Kasten, Daten laden (Server `trafficnetwork.link`) | | | |
| 6 | Meldung absetzen („Melden → Stau“): erscheint als Punkt, „Gespeichert“ | | | |
| 7 | Meldung bestätigen/widerlegen in der Detailkarte | | | |
| 8 | Fahrmodus → „Fahrt simulieren (4× schneller)“: Rechtshinweis, Warnung mit Entfernung, **Ton** und **Sprache** nach „Fahrt starten“ | | | |
| 9 | Während der Simulation „Einstellungen“ öffnen: **gesperrt** | | | |
| 10 | Echte Fahrt (Beifahrer!) oder Gehen: Geschwindigkeit und Richtung ändern sich | | | |
| 11 | Bildschirm bleibt im Fahrmodus an (5 Minuten nichts berühren) | | | |
| 12 | Bildschirm sperren und wieder entsperren im Fahrmodus: Standort/Warnungen laufen weiter oder die App sagt es | | | |
| 13 | Flugmodus an, App neu starten: sie startet (Karte leer, Meldungen werden vorgemerkt) | | | |
| 14 | Flugmodus aus: vorgemerkte Meldung wird gesendet | | | |
| 15 | Dunkelmodus (Systemeinstellung): beide Erscheinungsbilder lesbar | | | |
| 16 | Eine zweite Instanz in einem anderen Tab zeigt „Schon geöffnet“ | | — | — |

Ergebnis je Zeile: ✓ bestanden · ✗ gescheitert (kurz warum) · — nicht möglich. Screenshots zu den Zeilen 1, 3, 4, 8 und jeder ✗ bitte anhängen.

## Messwerte (selbst gemessen, Desktop-Chromium mit Handy-Fenster, nicht auf einem Gerät)

Messung mit `node scripts/web-measure.mjs` (komprimierte Übertragung wie bei GitHub Pages, Mock-Server der Bibliothek, Stand 2026-10-13):

| Verbindung | Übertragen beim ersten Laden (komprimiert, bis die Karte steht + 4 s) | App-Rahmen sichtbar | Karte steht | Speicher des Browsers danach |
|---|---|---|---|---|
| schnelles Netz (kein Limit) | 1833 kB | 0,4 s | 0,7 s | 10 186 kB (IndexedDB, Cache, Local Storage) |
| langsames Mobilfunknetz (1,6 Mbit/s, 150 ms) | 1830 kB | 2,7 s | 7,2 s | 10 184 kB |

Der Service Worker legt die App-Dateien einmalig in den Cache (der größte Teil der 10 MB) und wird erst drei Sekunden nach dem Laden angemeldet, damit er den ersten Start nicht bremst. Nicht messbar ohne Gerät: **Akkuverbrauch** einer halben Stunde Fahrmodus.

## Was ich nicht geprüft habe
Alles in der Spalte „iPhone“, jedes Verhalten von Safari/WebKit (die „iPhone-Größe“ in den Tests ist Chromium), Wake Lock, Töne und Sprache auf Geräten, die Qualität der Standortangaben, den echten Server `trafficnetwork.link` (aus der Entwicklungsumgebung nicht erreichbar).
