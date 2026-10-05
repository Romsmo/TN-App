# TNViewer auf dem iPhone testen

**Warum nicht Expo Go?** Expo Go enthält nur Expos eigene Module. TNViewer braucht zusätzlich die Trafficnetwork-Bibliothek und MapLibre (native Code). Deshalb baut EAS (Expos Cloud) eine eigene App; du installierst sie per **QR-Code / Link** auf dem iPhone. Dafür braucht es dein **Apple-Developer-Konto**: Apple lässt eigene Apps nur auf Geräten laufen, die in einem Profil eingetragen sind (Ad-hoc).

Du brauchst: Windows-Rechner mit Node.js 22, Git, dein Expo-Konto (Mitglied von `reamcrbss-team`), dein Apple-Developer-Konto, das iPhone. Mach die Schritte **in dieser Reihenfolge in PowerShell**; Passwörter tippst du dort selbst (nie in einen Chat).

## 1. Projekt holen
```powershell
git clone https://github.com/Romsmo/TN-App
cd TN-App
git checkout claude/tnviewer-mobile-setup-gcv37k
npm ci
```

## 2. Bei Expo anmelden
```powershell
npx eas-cli@latest login
npx eas-cli@latest whoami        # soll dein Konto zeigen
```
Das Projekt liegt im Konto `reamcrbss-team` (`app.json`: `owner`, `projectId`). Fehlt dir der Zugriff, bitte dich dort als Mitglied einladen oder `eas init` für dein Konto neu laufen lassen und `owner` anpassen.

## 3. Das iPhone registrieren
```powershell
npx eas-cli@latest device:create
```
Das Programm fragt nach deiner **Apple-ID** (Passwort, Zwei-Faktor-Code) und zeigt dann einen **QR-Code/Link**. Öffne ihn mit der Kamera/Safari **auf dem iPhone** und installiere das angezeigte Profil (Einstellungen → „Profil geladen" → Installieren). Damit steht die Gerätekennung im Apple-Konto.

## 4. App bauen (Preview: Release-Version, braucht keinen Entwicklungsserver)
```powershell
npx eas-cli@latest build -p ios --profile preview
```
- Beim ersten Mal fragt EAS nach der Apple-ID und legt Zertifikat und Profil an (auf „ja" antworten, das iPhone aus Schritt 3 auswählen).
- Der Build dauert in der Warteschlange der kostenlosen Stufe oft 20–40 Minuten. Am Ende zeigt das Terminal einen **QR-Code und einen Link** zur Installation (auch auf <https://expo.dev/accounts/reamcrbss-team/projects/tnviewer/builds>).

## 5. Installieren und starten
1. Auf dem iPhone den QR-Code scannen oder den Link in **Safari** öffnen → „Installieren".
2. Beim ersten Start ggf. **Entwicklermodus** einschalten: Einstellungen → Datenschutz & Sicherheit → Entwicklermodus (neu starten). Bei „Nicht vertrauenswürdiger Entwickler": Einstellungen → Allgemein → VPN & Geräteverwaltung → deine Apple-ID vertrauen.
3. App öffnen. Standort erlauben: **„Beim Verwenden der App"**.

## Was du ohne Server testen kannst
- **Fahrmodus → „Fahrt simulieren"** (oder „4× schneller"): Rechtshinweis, Tempo und Tempolimit, Warnungen voraus (Unfall, Baustelle, Glätte), Ton und Sprache, Melden mit einem Tipp, „Noch da?", Stumm. Einstellungen sind währenddessen **gesperrt**.
- **Einstellungen:** Einheit, Töne, Warnabstand, Fahrsperre (Abschalten zeigt den Warnhinweis), Blitzer-Option (Rechtshinweis), „Quellen und Lizenzen".
- Die **Karte** hat noch keinen Hintergrund (keine freigegebene Kartenquelle, `docs/map-sources.md`); du siehst nur die eigenen Daten auf einfachem Grund.

Mit **echten Daten** (Karte, Melden, Echtfahrt) brauchst du einen Server und einen Zugang: Einstellungen → Server verbinden. Ein öffentlicher Server mit Daten und ein Registrierungsweg fehlen noch (`docs/todo.md`).

## Wenn etwas nicht klappt
Bitte genau notieren oder fotografieren: **welcher Schritt**, **die Fehlermeldung wörtlich**, bei Abstürzen die Uhrzeit. Der erste Start auf dem Gerät ist die erste echte Probe der Bibliothek (React-Native-Anbindung, MapLibre, Schlüsselspeicher); Fehler dort sind möglich.
