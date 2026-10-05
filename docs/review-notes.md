# Texte für die Einreichung: Standort-Begründung und Review-Hinweise

Entwürfe. Nichts davon ist eingereicht. Die Server-Angaben und der Zugang fehlen (siehe „Offen").

## Berechtigungstexte (in `app.json`, Plugin `expo-location`)

`NSLocationWhenInUseUsageDescription` (de/en in einem Text):

> TNViewer nutzt deinen Standort, um Meldungen in deiner Nähe anzuzeigen und Meldungen an deiner Position abzusetzen. Im Fahrmodus wird er auch bei ausgeschaltetem Bildschirm genutzt, solange der Fahrmodus läuft, um dich vor Meldungen voraus zu warnen. / TNViewer uses your location to show reports near you and to place reports at your position. In the drive mode it is also used with the screen off, only while the drive mode is running, to warn you about reports ahead.

Es gibt **keine** „Always"-Texte, weil „Immer" nicht angefragt wird. `NSLocationAlways…` ist bewusst nicht gesetzt (per Prebuild geprüft).

Android: `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`; Benachrichtigung „TNViewer Fahrmodus — Dein Standort wird für Warnungen genutzt, solange der Fahrmodus läuft." Android wird nicht im Play Store veröffentlicht.

## Begründung Hintergrund-Standort (für das Review-Formular / die Hinweise)

> The app's drive mode warns the driver about reports ahead (hazards, roadworks, congestion, and, if the user switched it on and the country policy allows it, speed-camera danger areas) and shows the current speed and speed limit. This only works while the phone is locked or the app is in the background, because the phone is in a holder during the drive. Therefore the app uses location updates in the background **only while the user has started the drive mode** and until the user ends it. The system shows the location indicator (iOS) during that time. The app requests "While Using the App" only, never "Always". Outside the drive mode, no location is collected in the background. The position is evaluated on the device; only coarse map-cell IDs (about 2.4 km) are sent to the server to load nearby data, and exact coordinates only for a report the user submits.
>
> UIBackgroundModes: `location` (the drive mode above) and `audio` (spoken warnings with the screen off). No other background modes.

## Hinweise für den Prüfer (Notes for Review) — Entwurf

> **What the app is:** TNViewer shows traffic reports (hazards, roadworks, congestion, speed limits) from the open Trafficnetwork and lets users report them. It is not a navigation app and gives no route guidance.
>
> **How to see the drive mode without driving:** open the tab "Drive mode" → "Simulate a drive" (clearly labelled "SIMULATION – not a real drive"). It plays an invented demo route with invented hazards. No location and no server are needed. "Simulate a drive (4× faster)" shortens it. In the simulation, reports and votes are not sent anywhere.
>
> **Real data:** server address and access: [Server-Adresse und Zugang fehlen: öffentlicher, befüllter Server nötig, siehe docs/todo.md]. Settings → Connect to server.
>
> **Speed-camera display** is off by default (Settings → Speed cameras) and follows a per-country policy of the server; a legal notice is shown when it is switched on and at the first start of the drive mode.
>
> **Driving lock:** settings, server pages and text input are locked above about 10 km/h while the drive mode runs. [Je nach Entscheidung (docs/store-risks.md): „The lock cannot be switched off in this version." / „The user can switch it off only with an explicit warning; it is on by default."]
>
> **User-generated content:** reports consist of a predefined type and a coordinate (no text, no images, no profiles). Wrong reports can be marked "Gone" by other users. Contact: r.smolenski@icloud.com.
>
> **Encryption:** [offen, siehe docs/store-risks.md Punkt 9]

## Offen
- Öffentlicher befüllter Server und ein Weg für den Prüfer, sich zu registrieren (App-Schlüssel-Problem, `docs/todo.md`).
- URL der Datenschutzerklärung, Support- und Marketing-URL.
- Entscheidung zur Fahrsperre-Option im Review-Build und zur Verschlüsselungsangabe.
