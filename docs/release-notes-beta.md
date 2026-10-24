**Beta of the Flutter rebuild of TNViewer. Read this before installing.**

* The `.ipa` is **unsigned**. It is for sideloading on your own iPhone with your own Apple ID (for example with
  [xtool](https://github.com/xtool-org/xtool), see `docs/ios-install.md`); with a free Apple account the profile lasts 7 days.
  It is not on TestFlight or the App Store.
* **Connecting to a server:** Settings → Connect to server → *Scan code* / *Paste code*. The code comes from your server's web page
  ("App verbinden"). Without a server the app runs in emergency mode.
* **Map:** background map from OpenStreetMap tiles (the same source as the server's web map), credit "© OpenStreetMap contributors".
* **Checked so far:** the logic with the shared test vectors, the screens in a browser preview, the cloud build, the install on one
  iPhone (iOS 26.4.1) and that the app starts. **Not checked:** drive mode and sounds on the road, battery use, the join flow against a
  real server, opening a code as a link, VoiceOver, Android.
* The legal texts and the English wording are drafts and not approved. No analytics, no telemetry.

Checksum: `SHA256SUMS.txt` next to the file.
