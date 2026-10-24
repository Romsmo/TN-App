**Beta of the Flutter rebuild of TNViewer. Read this before installing.**

* The `.ipa` is **unsigned**. It is for sideloading on your own iPhone with your own Apple ID (for example with
  [xtool](https://github.com/xtool-org/xtool), see `docs/ios-install.md`); with a free Apple account the profile lasts 7 days.
  It is not on TestFlight or the App Store. Minimum iOS 13.1.
* **New in beta 2:** the **TN display** over Bluetooth (Settings → Display): live speed limit and warnings from the drive mode,
  announcements on the display, reports and answers from the display, settings both ways. New permission: Bluetooth, and the
  background mode `bluetooth-central`. Firmware updates for the display are **not** included.
* **Connecting to a server:** Settings → Connect to server → *Scan code* / *Paste code* (join code from your server's "App verbinden"
  page, or a `trafficnetwork://join?…` link). Without a server the app runs in emergency mode.
* **Map:** background map from OpenStreetMap tiles (the same source as the server's web map), credit "© OpenStreetMap contributors".
* **Checked so far:** the logic with the shared test vectors (join code, display protocol), the screens in a browser preview and widget
  tests, the cloud build, the install on one iPhone (iOS 26.4.1) of beta 1 and that it starts. **Not checked:** the display against real
  hardware, Bluetooth and drive mode in the background, the join flow against a real server, scanning and opening a code as a link,
  drive mode and sounds on the road, battery use, VoiceOver, Android.
* The legal texts and the English wording are drafts and not approved. No analytics, no telemetry.

Checksum: `SHA256SUMS.txt` next to the file.
