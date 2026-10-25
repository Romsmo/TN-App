# Display feature checklist: what the app does (2026-10-25)

The list is the display project's `docs/app-feature-checklist.md` (firmware 0.2, contract 1.1.0, commit `8266371`). **done** = built and
tested without hardware; **not run** = nothing of it has run against the real display yet. R = required, O = optional, D = developer.

| ID | Function | State | Where / note |
|---|---|---|---|
| A1 | Find the display | done | scan by service UUID, `universal_ble` (`display_ble.dart`) |
| A2 | One client at a time / busy | done | after two failed attempts the page says it may be off, out of range or connected to another phone |
| A3 | MTU | done | negotiated MTU, frames within `MTU − 3` and 244 B |
| A4 | Read DeviceInfo | done | protocol, firmware, caps, size shown on the page |
| A5 | Version gate | done | newer protocol: app too old, no State; older: display too old |
| A6 | Capability bits | done | audio, SD (voice), camera code, OTA, RTC steer what is offered and sent |
| A7 | Subscribe | done | Event, Settings, UiConfig |
| A8 | Time after connect | done | epoch + UTC offset; "Uhrzeit senden" on request |
| A9 | Settings after connect | done | read, then the complete set written |
| A10 | Reconnect, `stateSeq` from 1 | done | reconnect loop with growing pause |
| A11 | Open link | done | the page says so; no reliance on bonding |
| B1 | Trip off: `driveActive = false` | done | contract 1.1.0 (`display_feed.dart`); the display shows its logo |
| B2 | Trip on | done | key absent on the wire = true |
| B3 | Keep-alive while idle | done | a packet at least every 4 s also without a trip |
| B4/B5 | Offline, Melden only on a trip | display side | nothing to do |
| C1 | Speed limit + unit | done | only during a trip |
| C2 | Internet flag | done | from the server connection |
| C3 | Peer count | done | from the network status |
| C4 | Free-road picture | done | trip without a warning |
| C5 | Context sign columns | **open** | the library reports only speed-limit signs (`speedLimit50`...), which the display already shows as the big sign; no source for the other signs exists. Columns stay empty. |
| C6 | Night mode | done | the app decides from the night hours in the display settings |
| C7 | `useMph` | done | follows the app's unit |
| C8/C9 | `epochS`, `stateSeq` | done | |
| D1-D5 | Sign rules | package only | in the vendored package and tested there; unused while C5 is open |
| E1 | Hazard overlay | done | nearest, second-stage first; trip only |
| E2 | Distance | done | zones send no distance |
| E3 | Enforced limit (`hazardSpeedLimit`) | done | for speed-camera hazards: the limit of the road (the one the drive mode shows), in the sign unit |
| E4-E5 | 11 categories, unknown types | done | unknown app categories are not sent |
| E6 | Camera group | done | only with the user's switch, the country rule and the firmware's camera code |
| E7 | User filter | done | both directions |
| E8 | Overlay strip (UiConfig) | done | developer switch |
| F1-F3 | "Gesehen?" prompt and answer | done | prompt stays set; the answer is counted |
| F4 | Prompt strip (UiConfig) | done | developer switch |
| G1 | `ReportPressed` | done | no action needed |
| G2 | `ReportSubmitted` | done | one report, never a camera category, doubled events ignored; only during a trip with a recent position |
| G3 | Speed value in mph | display side | the known issue is the display's |
| G4 | Melden page strip (UiConfig) | done | developer switch |
| H1-H3 | Audio cues | done | approach, imminent, prompt, **cleared** (new), info; same cue repeated for 1.5 s |
| H4 | Voice composition | display side | |
| H5 | Chime without clips | done | voice mode only if the display has a card |
| H6 | Master gate, no cue outside a trip | done | the stream sends no cue without a trip |
| H7 | Volume | done | slider, live |
| H8 | Upload voice clips | done | Display page → Sounds and voice files: the five tones and the 18 German clips (Piper, Thorsten voice, CC0 data; `docs/audio-sources.md`) are in the app; never heard on the real display |
| I1 | Settings fields | done | sound, mode, volume, unit, filter, night hours, cache minutes |
| I2 | On-device toggles reflected | done | sound, unit, general hazard filter |
| I3 | Factory reset on the display | done | the app reconnects; the page explains the pairing record |
| I4 | UiConfig developer switches | done | Display page → Advanced (ten switches) |
| J1 | Clock | done | |
| K1-K2 | Detect an update | done | check on a tap or daily; the repository is public now |
| K3 | Push the image | done | begin, wait for the erase notification, paced frames, end; tested against a fake display |
| K4 | After the reboot | done | success only when the new version was read |
| K5 | Image trust | done | Ed25519 signature of the manifest, checked in the app (`display-signing.md`); an unsigned release is installed only after a warning, a bad one never; `fw-v0.1.0` is signed locally but the `.sig` is not uploaded yet |
| K6 | File upload | done | Asset frames, one file after the other, a pause between files; tested against a fake display |
| K7 | Progress on the display | display side | |

Test with the real display: `display-device-test.md`.
