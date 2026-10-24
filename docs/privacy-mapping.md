# What leaves the device (draft for a lawyer, not legal advice)

Replaces the privacy mapping of the Expo version. **Differences from the Expo documents are marked ⚠.** Verified by reading the
code, **not** by watching network traffic on a device.

| What | When | How exact | Where |
|---|---|---|---|
| Device access created / key bound | first sync | pseudonymous (client ID, public key) | the network |
| Tile IDs (H3 resolution 7, ≈ 2.4 km) via `updatePosition` | after the map's first position; ⚠ **and during a real drive, at most once a minute or per 500 m** (decision D-N1) | coarse: a cell, no coordinate | the network |
| Report / confirm / deny / "camera gone" (type + **exact coordinate**, signed) | only on a deliberate action | exact | the network |
| Chosen report duration (`ttlSeconds`) | with the report | one number | the network |
| Speed-limit correction (value, unit, reason + **exact coordinate** of the tapped road) | after "Senden" only, never while driving | exact | the network |
| ⚠ Speed-limit proposal for a stretch (value, unit + **the exact coordinates of both end points**) | after "Senden" only, never while driving | exact | the network |
| ⚠ Preview of the stretch (`resolveRoadInterval`: both end points) | when the second end is picked, needs the network | exact | the network |
| Online speed-limit lookup (`lookupSpeedLimit`) outside the offline area: `GET /v1/speed-limit?lat&lng` | when a road is tapped outside the offline area; **never in the drive mode** | exact (the library's own docs say otherwise; wish 4) | the network |
| IP address | every request | technical | the network |

Not sent: name, e-mail, phone, contacts, photos, advertising ID, usage statistics, crash reports (there is no analytics,
advertising or crash library). Speed, heading and distances of the drive mode are computed **only on the device**; the speed is
handed to `updatePosition` only as the library's optional hint.

Stored on the device: the library's database (the network's data), settings in a plain file (never the Keychain, which survives
a reinstall on iOS), device credential and signing key and the user's access data in the Keychain/Keystore.

Permissions: location **while using the app** only (never "Always"); iOS background modes `location` and `audio` only; Android
fine/coarse location and a foreground service with a notification while the drive mode runs; storage access removed.


## Added 2026-10-24 (draft for a lawyer)

* **Map tiles:** the map background is loaded from `tile.openstreetmap.org` (OpenStreetMap Foundation). The operator of the tile server
  sees the phone's IP address and the map section being viewed, and the app's name in the `User-Agent` (`TNViewer/<version>` and the
  project's repository address, no personal data). Same as the operator's web map. Tiles are cached as the server allows.
* **Join code / camera:** the camera is used only while the scan page is open, to read one QR code. The image is not stored and
  does not leave the device. The code is checked on the device; it is not logged. After the user confirms, the app contacts the
  address in the code (that server sees the phone's IP address, as before). Stored in the Keychain/Keystore, this device only: address,
  app key (id and derived secret) and the public network key. The seed of the code is not stored.
* **Threat note:** a foreign code leads into a foreign network. The app shows the address and the key's fingerprint and asks first;
  it cannot do more. A code shown on a web page is practically public (see the server's `join-code.md`).
* No analytics, no telemetry.


## Added 2026-10-24 (display, draft for a lawyer)

* **Bluetooth** (new permission, `NSBluetoothAlwaysUsageDescription` / Android `BLUETOOTH_SCAN` (not used for location), `BLUETOOTH_CONNECT`;
  iOS background mode `bluetooth-central`): the app talks to one TN display chosen by the user. Exchanged with the display: the speed limit,
  warnings (category, distance), the "still there?" prompt, announcement cues, the app's display settings (sound, volume, units, filter,
  night hours), the time, and the display's events (report, answer). **No position, no track, no identifier of the user is sent.** The
  display's Bluetooth id and name are stored on the phone (settings file) to reconnect.
* The link is **not secured** in protocol v1 (the display requires no pairing). Anyone in range could connect while the phone is not
  connected. The app says so on the display page.
* **Reports from the display** become ordinary reports of the app (same rules as the one-tap tiles: only during a drive with a recent
  position; general hazards only, never a speed-camera category).
* **Speed-camera data** reaches the display only if the user switched cameras on and the country rule allows it (the same switch as in the app).
* **Firmware update check (new connection, only with the display feature on):** on a tap, or once a day while the display is connected if the user switched "automatic check" on (off by default), the app asks `github.com/Romsmo/TN-DSP` (the repository of the display project) for `manifest.json`; GitHub sees the phone's IP address and the app's name in the `User-Agent` (`TNViewer/<version>` and the project's repository address), nothing else. The image is downloaded only after the user confirmed the install. Nothing is installed without a tap; the download is checked for size and SHA-256 against the manifest before the first byte goes to the display. The manifest is **not signed** (no scheme exists yet), which the confirmation says.
* **The display feature is off by default** (Settings → Extensions → "TN-Display unterstützen"): until it is switched on, the app does not scan, connect or read any Bluetooth data and shows nothing of the feature. The Bluetooth permission is asked for on the first search only. (iOS: the background mode `bluetooth-central` is declared in the app and cannot depend on the switch.)
* No analytics, no telemetry.
