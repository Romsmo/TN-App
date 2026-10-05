# Kartenquelle (Hintergrundkarte)

**Entscheidung (Auftraggeber, M2):** Ziel sind **eigene PMTiles** (Vektor-Kacheln) auf eigenem Server oder Speicher. Eine Übergangsquelle ist nur zulässig, wenn ihre Bedingungen die Nutzung in einer App **ausdrücklich** erlauben — mit Beleg (Link und Datum der Prüfung) in diesem Dokument. **Ein Store-Build darf keine Übergangsquelle enthalten, deren Bedingungen das nicht abdecken.**

## Stand

- Es ist **keine** Quelle eingebaut. `MAP_STYLE_URL` (`src/config.ts`, aus `EXPO_PUBLIC_MAP_STYLE_URL`) hat keinen Standardwert. Ohne Wert zeigt die Karte die Daten des Trafficnetworks auf einfachem Hintergrund und sagt das auf dem Bildschirm.
- Die Namensnennung „© OpenStreetMap contributors" steht immer sichtbar auf der Karte und im Bereich „Quellen und Lizenzen".

## Geprüfte Kandidaten

| Quelle | App-Nutzung ausdrücklich erlaubt? | Beleg | Ergebnis |
|---|---|---|---|
| `tile.openstreetmap.org` | nein: laut Repo-Doku des Servers (`server/docs/web-ui.md`, Stand 2026-09-23) kein Bulk/Prefetch/Offline, nur Best-Effort | Richtlinientext selbst nicht gelesen (Host vom Netz-Proxy gesperrt, 2026-10-05) | **nicht verwenden** |
| `demotiles.maplibre.org` (Beispiel der MapLibre-README) | nein, Demo | — | **nicht verwenden** |
| OpenFreeMap, kommerzielle Anbieter | **nicht geprüft** | Hosts vom Netz-Proxy gesperrt (2026-10-05), Bedingungen daher nicht gelesen | **offen**, keine Aussage |

Ein Eintrag wandert erst in „zulässig", wenn hier stehen: Link zu den Bedingungen, das Datum der Prüfung, der Satz, der App-Nutzung erlaubt, und die geforderte Namensnennung. Ein im App-Paket eingebetteter API-Schlüssel ist auslesbar und gilt nicht als Geheimnis.

## Zielzustand: eigene PMTiles

- Eine OSM-Ausschnittsdatei (z. B. Europa) als PMTiles auf eigenem Server oder Objektspeicher; die App bekommt nur die Style-URL.
- Vorteil für den Datenschutz: kein Dritter sieht IP-Adresse und betrachteten Ausschnitt. Offline-Nutzung wäre möglich.
- Noch zu klären: Hosting und Größe; ob `@maplibre/maplibre-react-native` 11.5 `pmtiles://` direkt liest oder ein Tile-Endpunkt davor nötig ist (nicht geprüft).
