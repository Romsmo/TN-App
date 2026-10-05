# TNViewer — Regeln für Claude

Expo-App (iOS + Android) für das Trafficnetwork. Diese Regeln gelten vor allem anderen; Ausnahmen nur auf ausdrückliche Anweisung des Auftraggebers.

## Befehle
- `npm run check` = Lint + Typprüfung + Tests. Vor jedem Commit grün.
- Pakete mit **kompatibler SDK-Version** installieren. `npx expo install` braucht `api.expo.dev`/`reactnative.directory`; ist beides gesperrt, die Version aus `node_modules/expo/bundledNativeModules.json` nehmen.
- `src/app/` enthält **nur Routen** (jede Datei ist eine Route, auch Testdateien!). Tests liegen neben dem Code in `src/…`, nicht in `src/app/`.
- `ios/` und `android/` werden erzeugt (Continuous Native Generation), nie von Hand bearbeiten.

## Harte Regeln
- **Daten nur über die Client-Bibliothek** (`@trafficnetwork/react-native`). Kein eigener REST-/WebSocket-Code, der an ihr vorbeigeht.
- **Logik gehört in den Kern.** Was auch andere Hosts brauchen würden (Voraus-Filter, Map-Matching, Entprellen), nicht heimlich in der App bauen: als Wunsch für `client-lib 1.2` melden, hier nur eine austauschbare Übergangslösung hinter einer Schnittstelle.
- **Datenschutz als Bauart:** keine Analyse-, Werbe-, Tracking-Pakete; Absturzberichte nur mit Zustimmung (Standard aus); Schlüssel im Keychain/Keystore; Position verlässt das Gerät nur als Koordinate einer bewusst abgesetzten Meldung (plus die grobe Kachel der Bibliothek).
- **Keine Secrets** im Repo, in Logs oder Tests. Keine echten Server-Namen in Tests. Keine Debug-Ausgaben im Release-Build.
- **Wortlaute** des Blitzer-Hinweises und der Fahrsperren-Warnung sind vorgegeben und werden wörtlich übernommen (de + en).
- **Fahrsperre** ist standardmäßig an, auch nach Neuinstallation und nach „Geräteidentität zurücksetzen".
- **Blitzer:** Filter beim ersten Start aus; Länderpolitik des Servers (`off`/`zones`/`full`) gilt; bei `zones` nie eine Einzelkoordinate.
- Nichts von Blitzer.de oder anderen Marken übernehmen (Name, Gestaltung, Texte, Töne).
- **Nichts einreichen, hochladen oder veröffentlichen** (TestFlight, App Store, Play Store) ohne ausdrückliche Freigabe; Einreichung erst nach schriftlichem „Abnahme". Nicht selbst mergen.
- Was nicht geprüft werden konnte, wird so benannt. Ein offener Punkt ist ein zulässiges Ergebnis, ein behauptetes Häkchen nicht.
