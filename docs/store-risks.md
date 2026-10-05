# App-Store-Risiken (vor der Einreichung zu entscheiden)

Recherche am 2026-10-05. Die Richtlinientexte stammen aus einem Abruf von <https://developer.apple.com/app-store/review/guidelines/> über ein zusammenfassendes Werkzeug (Auszüge, kein Wortlaut-Beleg): **vor der Einreichung die Originalseite lesen.** Die Seite zur Exportkontrolle (`Complying with Encryption Export Regulations`) war nicht abrufbar (JavaScript-Seite); dazu gibt es unten keine belegte Aussage. Nichts wurde eingereicht.

## Übersicht

| # | Thema | Richtlinie | Risiko | Empfehlung |
|---|---|---|---|---|
| 1 | Blitzer-Warnungen | 1.4.4 (nur DUI-Kontrollen eingeschränkt) | niedrig–mittel | Es gibt Vorbilder im deutschen Store (Blitzer.de, SpeedCam, CamerAlert; Suchtreffer 2026-10-05). Keine Meldeart „Polizeikontrolle"/„Alkoholkontrolle" anbieten (gibt es nicht); angeboten werden nur die fünf Kameraarten des Servers (fest, mobil, Anhänger, Rotlicht, Abstand). Länderpolitik und Rechtshinweis sind eingebaut. |
| 2 | Bedienung beim Fahren / abschaltbare Fahrsperre | 1.4.5 („Geräte so nutzen, dass Schaden droht") | **mittel** | siehe unten |
| 3 | Hintergrund-Standort | 2.5.4, 5.1.5 | mittel | „Beim Verwenden" statt „Immer", nur im laufenden Fahrmodus, sichtbare Anzeige; ehrliche Begründung (`docs/review-notes.md`). `UIBackgroundModes` nur `location` und `audio`. |
| 4 | Nutzergenerierte Inhalte | 1.2 | niedrig–mittel | Meldungen sind vorgegebene Arten mit Koordinate: kein Text, kein Bild, kein Profil. Apple verlangt bei UGC Filter, Meldeweg, Sperrmöglichkeit und Kontaktangabe. Hier: Widerlegen („Nicht mehr da") ist der Weg gegen falsche Meldungen; Support-E-Mail öffentlich angeben. Einen Weg, **Nutzer zu blockieren,** gibt es nicht (Nutzer sind nicht sichtbar). Ob Apple das genügt, ist offen; Antwort bereithalten. |
| 5 | Leerer Server im Review | 2.1(a) („turn on your back-end service") | **hoch, wenn nicht gelöst** | Öffentlicher, befüllter Server nötig. Die Simulationsfahrt zeigt den Fahrmodus auch ohne Server. |
| 6 | Zugang des Prüfers | 2.1(a) | **hoch** | Ein Gerät kann sich nur mit einem App-Schlüssel des Servers registrieren (50/Tag/Schlüssel, `docs/todo.md`). Ohne öffentlichen Registrierungsweg kann der Prüfer keine echten Daten laden. |
| 7 | Datenschutzerklärung-URL | 5.1.1(i) | **hoch, wenn nicht gelöst** | `docs/privacy-policy-draft.md`; Domain fehlt. Auch in der App erreichbar machen (noch nicht eingebaut, kommt mit der URL). |
| 8 | Datenminimierung | 5.1.1(iii) | niedrig | Standort nur für die Funktion; Geschwindigkeit wird nicht gesendet. |
| 9 | Exportkontrolle (Verschlüsselung) | App Store Connect | offen | Die Bibliothek bringt eigenes TLS (HTTPS/WSS) und Ed25519-Signaturen mit. `ITSAppUsesNonExemptEncryption` ist bewusst **nicht** gesetzt, bis das geklärt ist (Apple fragt dann je Build). Entscheidung braucht eine belegte Einschätzung des Betreibers (US-Exportregeln, ggf. Selbstklassifizierung; EU-/französische Regeln). |
| 10 | Kategorie | 2.3 | niedrig | Vorschlag **Navigation** (Verkehrsinfos, wie die Vorbilder); Alternative **Reisen**. Die App navigiert nicht — das im Beschreibungstext klar sagen. |
| 11 | Mindestfunktion / Download | 4.2, 4.2.3(ii) | niedrig | Die Kartendaten werden nach dem Start geladen; Größe wird angezeigt, „Nur im WLAN" ist Standard. |
| 12 | Verborgene Funktionen | 2.3.1(a) | niedrig | Simulationsfahrt und Fahrsperre-Option in den Review-Hinweisen **nennen**. |
| 13 | Rechtslage Blitzer | Landesrecht | Betreiber | Der Nutzer wird gewarnt; `off`/`zones` je Land entscheidet der Betreiber (signierte Politik). Rechtliche Einschätzung je Land steht beim Betreiber (`docs/todo.md` des Trafficnetwork-Repos). |

## Zur abschaltbaren Fahrsperre — meine Einschätzung

Die Sperre ist standardmäßig **an**, das Abschalten braucht einen deutlichen Warnhinweis, den man jedes Mal bestätigen muss, und der Fahrmodus selbst hat keine Menüs und keine Texteingabe. Trotzdem ist „der Nutzer kann die Sperre abschalten" für einen Prüfer ein Anhaltspunkt für Richtlinie 1.4.5 und für die allgemeine Verkehrssicherheitslinie.

**Empfehlung:** Für die **erste Einreichung** den Review-Build **ohne** die Option bauen (`EXPO_PUBLIC_ALLOW_DISABLE_DRIVE_LOCK=false`: Sperre immer an, keine Option, Einstellungsseite sagt das). Das nimmt dem Prüfer die Angriffsfläche; die Option kann in einem späteren Update mit eigener Begründung folgen. Wenn du die Option von Anfang an im Store haben willst: sie bleibt in den Review-Hinweisen genannt (Standard an, Warnhinweis, jedes Mal bestätigen), mit dem Rückfall, bei einer Ablehnung den Schalter sofort abzuschalten. Die Entscheidung liegt bei dir; ich habe den Schalter gebaut und getestet.

## Was ich nicht belegen kann
- Ob Apple Blitzer-Apps **heute** unverändert zulässt (Hinweis nur: Vorbilder sind im Store).
- Ob die Meldewege für nutzergenerierte Inhalte für diese Art Meldungen genügen.
- Die Exportkontroll-Einstufung (siehe 9).
- Apples Haltung zur abschaltbaren Fahrsperre (Einschätzung oben ist meine, kein Beleg).
