# TestFlight (und später App Store): was ich von dir brauche

Stand 2026-10-05. Nichts davon wurde ausgeführt: **kein Upload, keine Einreichung.** TestFlight-Upload nur nach deinem „ja", App Store erst nach deinem schriftlichen „Abnahme".

Passwörter und Apple-Codes tippst du **selbst** im Terminal, nie in den Chat. Schlüssel kommen nur als Umgebungs-Secret (EXPO_TOKEN-Art), nie ins Repo.

## A. Für den ersten TestFlight-Build (interne Tester) — das blockiert mich

| # | Was | Wer | Warum / Hinweis |
|---|---|---|---|
| 1 | **Apple Developer Program** aktiv, Lizenzvereinbarungen angenommen | du (Account Holder) | Ohne angenommene Vereinbarung scheitert der Upload; Neubauen hilft dann nicht. |
| 2 | **Bundle-ID bestätigen:** `info.trafficnetwork.tnviewer` | du | Lässt sich nach dem ersten Upload nicht mehr ändern. Passt sie zu deiner Domain/Marke? |
| 3 | **App-Eintrag in App Store Connect** (Name, Primärsprache, Bundle-ID, SKU) | du, oder EAS legt ihn beim ersten `eas submit` mit deinem Apple-Login an | Ist der Name „TNViewer" frei? Sonst Wunschname nennen. |
| 4 | **Apple-Login im Terminal** (Apple-ID, Passwort, 2FA-Code) für Zertifikate/Profile — **oder** ein **App-Store-Connect-API-Schlüssel** (Rolle „App Manager") als Umgebungs-Secret | du | Der Login ist interaktiv; ich kann ihn nicht für dich tippen. Mit API-Schlüssel kann ich Builds und Upload ohne dich anstoßen. |
| 5 | **Verschlüsselungs-Erklärung entscheiden** (`ITSAppUsesNonExemptEncryption`) | du | Die App nutzt nur Standard-HTTPS/TLS und Ed25519-Signaturen. Üblich ist „ausgenommen" (`false`), aber das ist eine Erklärung **von dir** gegenüber Apple/US-Exportrecht. Ich setze sie erst, wenn du sie freigibst; ich habe dazu keinen belegten Wortlaut (Apple-Seite war nicht abrufbar). Für Frankreich ggf. eigene Erklärung. |
| 6 | **Interne Tester:** Apple-IDs der Personen, als Nutzer in App Store Connect angelegt (bis 100) | du | Interne Tester brauchen keine Beta-Prüfung und keine Geräteregistrierung (anders als Ad-hoc). |
| 7 | **Dein „ja" zum Upload** | du | Sobald 1–5 stehen: Build mit `eas build -p ios --profile production`, danach `eas submit` mit der Build-ID. |

## B. Damit die App für Tester **sinnvoll** ist (sonst sehen sie nur den Notmodus)

| # | Was | Stand |
|---|---|---|
| 8 | **Ein erreichbarer, befüllter Server** mit öffentlichem Weg zum Zugang | **offen.** Ein Gerät registriert sich nur mit einem App-Schlüssel des Servers (50 Registrierungen/Tag/Schlüssel). Wie bekommt ein Tester seinen Zugang? Möglichkeiten: Schlüssel pro Tester von dir, oder eine Server-Änderung für offene Registrierung (liegt in `server/`, das ich nicht ändere). **Frage an dich.** |
| 9 | **Seed-Server:** `seed1/seed2.trafficnetwork.info` | existieren noch nicht in DNS; ohne sie findet eine frische Installation keinen Server und zeigt den **Notmodus**. Entweder die Hosts anlegen oder eine feste Server-Adresse für den Build nennen. |
| 10 | **Kartenhintergrund** (eigene PMTiles + Stil, hell und dunkel) | **offen.** Ohne Stil zeigt die Karte nur Meldungen auf grauer Fläche. Hosting und Nutzungsbedingungen der Quelle müssen geklärt sein (`docs/map-sources.md`). |
| 11 | **Netzwerk-Wurzelschlüssel** (`EXPO_PUBLIC_TN_NETWORK_ROOT_KEY`) | Ohne ihn ignoriert die Bibliothek die signierte Netzwerk-Konfiguration (und damit die Länderpolitik für Blitzer). Öffentlicher Schlüssel, darf ins Build. |

## C. Zusätzlich für **externe** Tester und für den App Store

| # | Was |
|---|---|
| 12 | **Datenschutz-URL** (Entwurf: `docs/privacy-policy-draft.md`) auf einer Domain, die dir gehört; dazu **Support-URL** und **Support-E-Mail** |
| 13 | **Test-Informationen:** Beta-Beschreibung, Kontakt für Rückfragen (Name, Telefon, E-Mail), Review-Hinweise (`docs/review-notes.md`: Hintergrund-Standort, Simulationsfahrt, Fahrsperre) und **Zugangsdaten bzw. Server für den Prüfer** |
| 14 | **App-Datenschutz-Angaben** („Nutrition Label"): Antworten stehen in `docs/privacy-mapping.md` — du bestätigst sie |
| 15 | **Screenshots** iPhone (6,9" und 6,5"), Beschreibung, Stichwörter, Kategorie (Vorschlag Navigation), Altersfreigabe-Fragebogen, Copyright, Preis, Länder (Blitzer-Rechtslage je Land: Schweiz/Frankreich — **Verfügbarkeit entscheidest du**) |
| 16 | **Entscheidung Fahrsperre:** Review-Build ohne Abschaltoption (`EXPO_PUBLIC_ALLOW_DISABLE_DRIVE_LOCK=false`, meine Empfehlung, `docs/store-risks.md`) oder mit Option |
| 17 | **Freigabe der englischen Rechtstexte** (`src/legal/texts.ts`; deutsche Texte sind wörtlich, die englischen sind meine Übersetzung) |
| 18 | **Blitzer-Rechtsbewertung** je Land (Betreiber) und deine Antwort auf die Review-Frage zu nutzergenerierten Inhalten (Richtlinie 1.2) |
| 19 | **„Abnahme"** schriftlich, erst dann Einreichung zur App-Prüfung |

## Was ich vorbereitet habe
- Build-Profile in `eas.json` (`production` mit automatischer Build-Nummer), EAS-Projekt verknüpft, Anmeldedaten bei EAS (entfernt verwaltet).
- Icon (hell/dunkel/getönt), Splash, Hintergrund-Modi nur `location` und `audio`, Standort-Texte de/en, App-Datenschutz-Zuordnung, Review-Hinweise, Store-Texte (Entwurf), Risikoliste.
- `npm run check` grün (Lint, Typen, 373 Tests). **Auf einem Gerät lief die App noch nie.** Das ist der erste Test, den TestFlight ermöglicht.

## Ablauf, sobald A steht
1. Du: „ja, bauen und hochladen" (und gibst 4 frei).
2. Ich: `eas build -p ios --profile production`, prüfe den Build, dann `eas submit` mit genau dieser Build-ID.
3. Apple verarbeitet den Build (Minuten bis Stunden); Export-Erklärung ggf. in App Store Connect beantworten.
4. Du fügst den Build einer internen Testgruppe hinzu; die Tester installieren über die TestFlight-App.
