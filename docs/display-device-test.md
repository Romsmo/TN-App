# Display: test with the real display (the owner runs it; nothing here has been run yet)

Needs the TN display with firmware `0.1.0` (or newer) and the phone with this app (build `0.1.0-beta.2` or later, not yet released).

1. Settings → Display → *Search for display*. Allow Bluetooth. The display appears; *Connect*. Expect: "Verbunden mit …", firmware,
   protocol 1, capabilities (sound, update; card only if inserted).
2. Switch the display off and on: the app reconnects by itself within about a minute; the display shows its home screen again.
3. Start the simulated drive (a development build with `TN_DEV_TOOLS=true`) or a real drive: the speed limit and warnings appear on the
   display; the "no app" badge does not appear; the display keeps its last picture when the app is closed.
4. Warnings: first stage, second stage (with sound on the display, silent on the phone in *Automatic*); "Gesehen?" appears and the
   answer on the display is counted (check the report on the map).
5. *Melden* on the display while a drive runs with a position: one report appears in the app, not two. Without a drive: nothing happens.
6. Change sound, volume and unit on the display; the app's settings follow. Change them in the app; the display follows.
7. Lock the phone with the drive running: does the display keep getting data for several minutes? (iOS background behaviour
   with `location` + `audio` + `bluetooth-central` is not verified.) Note the battery use.
8. A speed camera category appears on the display only with cameras switched on in the app.
9. *Forget display*: the phone stops using it; remove any pairing in the iOS Bluetooth settings.
10. Settings → Extensions → "TN-Display unterstützen" is off at first: no Display row, no Display line on the drive page. Switch it on: both appear.
11. Display page: night hours, picture cache, *Send time*, *Test sound* (a short tone on the display).
12. Firmware: *Check for update*. While `TN-DSP` is private the page says the source is not reachable. Once a release is public and newer
    than the display: *Install update* (confirmation, progress, restart, "Fertig: Version …"). Not while driving. A display that rolls back is
    reported as failed, not as done.
13. Automatic check: switch it on, reconnect; at most once a day it looks by itself and shows the badge on the Display row.
14. Voice pack: not built (none exists).
