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
10. Firmware update and voice pack: not built (update source and signed manifest are open).
