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
