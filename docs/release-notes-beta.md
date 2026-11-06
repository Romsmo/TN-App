**Beta of the Flutter rebuild of TNViewer. Read this before installing.**

* The `.ipa` is **unsigned**. It is for sideloading on your own iPhone with your own Apple ID (for example with
  [xtool](https://github.com/xtool-org/xtool), see `docs/ios-install.md`); with a free Apple account the profile lasts 7 days.
  It is not on TestFlight or the App Store. Minimum iOS 13.1.
* **New in beta 7:** the camera also reads **speed-limit signs** (20 to 130 km/h). The limit it reads is shown as the drive's limit (with a
  small camera badge), takes the place of the database's limit, and counts for the over-the-limit warning and the display. It ends at the
  next limit sign, after 1.5 km, or when the database later holds another value for the road; the signs that end a limit have no red and are
  not read. With the report switch on, the app proposes the limit to the database when the database holds another value or none. **Not
  tested on a road:** the limits 40, 90, 110 and 130 were trained on repainted pictures only, never tested on real signs; a lorry's speed
  sticker is kept out by a check that is tested with made-up data only. Additional plates ("bei Nässe", "7-17 Uhr") are not read.
* **Since beta 6:** **traffic signs by camera** (*Settings -> Signs by camera*, off until you switch it on): during a drive the phone's
  camera reads signs with a red border (warning and prohibition signs the display can draw); what it sees is shown on the display before
  the database's signs. Needs the **calibration** first (drag a cross onto the vanishing point of the road). A second switch lets the
  camera feed the database (confirm known signs, propose new ones; sign type, place and direction only, never an image). **Not tested
  on a phone or in a car; the recognition model was trained on benchmark crops, not road footage.** Start with the report switch off.
  See `docs/camera-signs.md` for what it cannot do (signs without red such as end-of-ban signs, additional plates, dark, far signs).
* **Since beta 5:** the display's sign columns are filled with the traffic signs that apply on the road (no overtaking, no stopping,
  wild animals, roadworks ...), from the Trafficnetwork's new context signs (client library 1.3.0, node with server 1.4.0). Only signs
  several devices have confirmed are shown; the switch is *Settings → Display → Show traffic signs*. A node that has no entries shows
  nothing. Entering and confirming signs is not in the app yet (it is on the website).
* **Since beta 4:** a speed camera on the display now carries the limit of its road; display firmware updates are checked against a
  **signature** (Ed25519; a good one is shown, an unsigned release asks for an extra confirmation, a bad one is refused; the release
  `fw-v0.1.0` of the display project counts as unsigned until its `.sig` is uploaded); *Settings → Display → Sounds and voice files*
  copies five tones and 18 German voice clips (synthetic voice: Piper with the CC0 Thorsten data) to the display's memory card. The
  display's developer switches were removed from the app.
* **Since beta 3:** the display contract 1.1.0 (needs display firmware 0.2 for the trip mode): without a trip the display shows its logo,
  with a trip the driving screen; a "cleared" tone; a hint when the display cannot be reached. The small grey sign dots on the map
  appear only when zoomed in to street level.
* **Since beta 2:** the **TN display** over Bluetooth. It is **off until you switch it on** (Settings → Extensions → "TN-Display unterstützen");
  then Settings → Display: live speed limit and warnings from the drive mode, announcements on the display, reports and answers from
  the display, settings both ways (sound, volume, night dimming, picture cache, time) and **firmware updates** (check on a tap or once a day if
  you allow it; installing always needs a tap and is not offered while driving; the release is not signed, the app says so). New permission:
  Bluetooth, and the background mode `bluetooth-central`. The update source (the display project's GitHub releases) is private today, so the
  check says so until it is public.
* **Smoother interface:** iOS-style transitions and scrolling, press feedback and light haptics, a calmer settings page and drive start page.
* **Connecting to a server:** Settings → Connect to server → *Scan code* / *Paste code* (join code from your server's "App verbinden"
  page, or a `trafficnetwork://join?…` link). Without a server the app runs in emergency mode.
* **Map:** background map from OpenStreetMap tiles (the same source as the server's web map), credit "© OpenStreetMap contributors".
* **Checked so far:** the logic with the shared test vectors (join code, display protocol), the screens in a browser preview and widget
  tests, the cloud build, the install on one iPhone (iOS 26.4.1) of beta 1 and that it starts. **Not checked:** the display against real
  hardware, Bluetooth and drive mode in the background, the join flow against a real server, scanning and opening a code as a link,
  drive mode and sounds on the road, battery use, VoiceOver, Android.
* The legal texts and the English wording are drafts and not approved. No analytics, no telemetry.

Checksum: `SHA256SUMS.txt` next to the file.
