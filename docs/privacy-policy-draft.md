# Datenschutzerklärung — ENTWURF

> **Entwurf, keine Rechtsberatung.** Aus den tatsächlichen Datenflüssen der App abgeleitet (siehe `privacy-mapping.md`). Angaben in `[eckigen Klammern]` fehlen und kommen vom Betreiber. Apple verlangt eine erreichbare URL (App Store Connect und in der App erreichbar); die Domain `trafficnetwork.info` ist noch nicht eingerichtet. Die Erklärung des Betreibers im Trafficnetwork-Repo (`docs/privacy.md`) ist noch nicht fertig und muss zusammenpassen.

## 1. Wer ist verantwortlich?
[Name und Anschrift des Anbieters], E-Mail: r.smolenski@icloud.com (Roman Smolenski).
Die App ruft Server des **Trafficnetworks** ab. Diese Server werden von verschiedenen Betreibern betrieben; für sie gelten deren Erklärungen. [Betreiber des Standardnetzes, Link]

## 2. Was die App verarbeitet
- **Gerätezugang:** beim ersten Start meldet sich das Gerät beim Server an und erhält eine zufällige Kennung; es erzeugt ein Schlüsselpaar und teilt den öffentlichen Schlüssel mit. Es gibt kein Konto, keinen Namen, keine E-Mail-Adresse. Die geheimen Schlüssel bleiben im Schlüsselspeicher des Geräts.
- **Grober Standort:** Um Daten für deine Umgebung zu laden, sendet die App Kennungen von Kartenzellen (etwa 2,4 km groß), nicht deine Koordinaten. Im **Fahrmodus** geschieht das laufend, solange er läuft.
- **Meldungen:** Wenn du eine Gefahr meldest oder eine Meldung bestätigst bzw. widerlegst, sendet die App die Art der Meldung und die **genaue Koordinate** der Meldung, signiert mit dem Geräteschlüssel. Das passiert nur auf deine Handlung. Meldungen sind für alle sichtbar.
- **IP-Adresse:** Jede Verbindung zu einem Server übermittelt technisch deine IP-Adresse.
- **Nur auf dem Gerät:** Tempo, Fahrtrichtung und der Abstand zu Meldungen werden im Fahrmodus lokal berechnet und nicht gesendet. Einstellungen bleiben auf dem Gerät.
- **Nicht verarbeitet:** keine Werbe-ID, keine Analyse, keine Nutzerprofile, keine Absturzberichte, keine Weitergabe an Werbenetzwerke.

## 3. Standort im Hintergrund
Nur im **Fahrmodus** und nur nach deinem Start nutzt die App den Standort auch bei ausgeschaltetem Bildschirm, um dich vor Meldungen voraus zu warnen. Das System zeigt das an (iOS: Statusanzeige; Android: Benachrichtigung). Mit „Beenden" hört es auf. Du erlaubst den Standort „Beim Verwenden der App".

## 4. Rechtsgrundlagen
Standortnutzung: Einwilligung (Art. 6 Abs. 1 lit. a DSGVO) über die Systemabfrage; Meldungen: Einwilligung durch dein bewusstes Absenden und Vertragserfüllung/Funktion der App (Art. 6 Abs. 1 lit. b); technische Verbindungsdaten: berechtigtes Interesse (lit. f). [vom Betreiber/Rechtsprüfung zu bestätigen]

## 5. Empfänger
Server des Netzwerks, die Meldungen untereinander austauschen (föderiert). Betreiber können Dritte in verschiedenen Ländern sein. [Liste/Verzeichnis der Standardserver, Standort der Server]

## 6. Speicherdauer
Meldungen verfallen nach ihrer Gültigkeitsdauer (je Art); [Aufbewahrung von Protokollen mit IP-Adressen: ___ Tage]. Die App speichert Daten lokal, bis du sie löschst („Lokale Daten löschen") oder die App entfernst.

## 7. Deine Rechte
Auskunft, Berichtigung, Löschung, Einschränkung, Widerspruch, Datenübertragbarkeit, Widerruf der Einwilligung (Standort jederzeit in den Systemeinstellungen), Beschwerde bei einer Aufsichtsbehörde. Da Meldungen pseudonym sind, kann der Server sie nur mit deinem Geräteschlüssel dir zuordnen. [Kontakt für Anfragen]

## 8. Kinder
Die App richtet sich nicht an Kinder unter 16.

## 9. Sicherheit
Verbindungen sind verschlüsselt (HTTPS/WSS), Meldungen werden mit einem Geräteschlüssel signiert, Schlüssel liegen im Keychain/Keystore.

## 10. Hinweis zur Nutzung im Straßenverkehr
Die Bedienung eines Smartphones während der Fahrt lenkt ab und ist in vielen Ländern verboten. Blitzer-Warnungen während der Fahrt sind in Deutschland verboten (auch für Beifahrer), in der Schweiz generell unzulässig und in Frankreich nur als allgemeine Gefahrenzonen. Bitte informiere dich über die Regeln in deinem Land.

*Stand: [Datum]*
