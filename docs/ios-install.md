# Getting the app onto the iPhone from Windows (Gate 0)

Status 2026-10-23: **not done.** The chosen way is **(b)**: a macOS runner in the cloud builds an unsigned `.ipa`; **xtool**
([github.com/xtool-org/xtool](https://github.com/xtool-org/xtool)) in WSL signs and installs it. Nothing of the Windows side is installed
(an earlier attempt with xcross was a misunderstanding and has been removed completely).

## The owner's situation

iPhone on iOS 27; an Apple ID **without** Developer Program enrolment (a free account: 7-day profiles, about 3 apps, about 10 App IDs
per 7 days; secondary sources only: [Corellium](https://support.corellium.com/features/apps/sideloadly),
[mybyways](https://mybyways.com/blog/new-limitations-imposed-on-free-apple-developer-account)); Windows 11, no Mac; WSL2 with only the
`docker-desktop` distribution; Flutter 3.38.7; Norton intercepts TLS (pip needs `--cert C:\ProgramData\Norton\Antivirus\wscert.pem`).

## What xtool can and cannot do (README and docs read 2026-10-23, release 1.23.0)

- It builds SwiftPM packages, signs and installs `.ipa` files, talks to Apple Developer Services.
- It does **not** build Flutter apps: the maintainer says it can sign but not build such apps (issue
  [#28](https://github.com/xtool-org/xtool/issues/28)). So the `.ipa` must come from elsewhere.
- Windows means WSL: Ubuntu in WSL2, Swift 6.4 for Linux, `usbmuxd`, USB passthrough with `usbipd-win` (or the iTunes relay of
  [issue #19](https://github.com/xtool-org/xtool/issues/19)), then `xtool-x86_64.AppImage` (54,098,424 bytes).
- `xtool auth` asks for a login mode: **Password** works with any Apple ID (private Apple APIs; a throwaway ID is advised), **API key**
  needs the paid program. `xtool setup` is `xtool auth` plus `xtool sdk`; the second part asks for `Xcode.xip` (Xcode 27.1 from developer.apple.com/download/all, after logging in with the
  Apple ID and accepting the licence agreement). **`xtool install` does not need that SDK:** its source (`Sources/XToolSupport/InstallCommand.swift`, read 2026-10-24) only
  loads the saved auth token from `xtool auth`. So the Xcode download and the Swift toolchain are only needed to *build* with xtool, which
  this project does not do.
- Not verified by anyone: that a Flutter `.ipa` with the embedded dynamic framework `TrafficNetworkDart.framework` is signed correctly.

## Part A: the cloud build (`.github/workflows/ios-beta.yml`)

Runs on `macos-26` (Xcode 26.6; an Xcode 27 exists only as a beta there). Public repository: standard runners are free there (GitHub's
billing page; it does not name macOS explicitly). It fetches client-lib 1.2.1 with checksum check, runs analysis and tests, builds with
`flutter build ios --release --no-codesign`, zips `Payload/Runner.app` to `TNViewer-unsigned.ipa` and keeps it as an artifact for 7 days.
The server values are repository variables (`TN_DEFAULT_NODE`, `TN_APP_CLIENT_ID`, `TN_NETWORK_ROOT_KEY`, `MAP_STYLE_URL`,
`MAP_STYLE_URL_DARK`) and the secret `TN_APP_CLIENT_SECRET`; **the owner types them**. Without them the app runs in emergency mode.

Plugins without SwiftPM support (`flutter_tts`, and `path_provider_foundation` in the pinned version) are built with CocoaPods on the
runner, which Flutter does by itself; this does not matter for the way (b).

## Part B: Windows (each step is confirmed by the owner one by one)

| # | Step | Source, file, size | The owner |
|---|---|---|---|
| 1 | Linux in WSL2 | `wsl --install -d Ubuntu-24.04` (Microsoft; size unknown) | Ubuntu user name and password |
| 2 | USB passthrough | `usbipd-win_5.3.0_x64.msi`, 4,501,504 bytes, SHA-256 `1c984914aec944de19b64eff232421439629699f8138e3ddc29301175bc6d938` | administrator (UAC) |
| 3 | `usbmuxd` | `sudo apt-get install usbmuxd` | Ubuntu password |
| 4 | xtool | `xtool-x86_64.AppImage`, 54,098,424 bytes, release 1.23.0 (FUSE may be missing in WSL: `--appimage-extract-and-run`, untested) | — |
| 5 | `xtool auth` | login mode **Password** | Apple ID, password, 2FA code — typed by the owner, never in chat or a file |
| 6 | iPhone | Developer Mode (Settings → Privacy & Security), cable, trust; `usbipd bind` and `attach` | on the phone; administrator for `bind` |
| 7 | Install | `xtool install TNViewer-unsigned.ipa`; then trust the developer under Settings → General → VPN & Device Management | on the phone |

Part A is done (see below). Part B has no Swift toolchain and no Xcode download any more.

## Result of Part A (2026-10-23, run 40027344526, ~7 minutes)

Unsigned `TNViewer-unsigned.ipa`, 18,104,588 bytes (artifact zip 18,023,116 bytes, SHA-256 `f44d81b6…8237d33f`, checked). Inside: bundle id
`info.trafficnetwork.tnviewer`, version 0.1.0 (1), built with iphoneos 26.5 / Xcode 26.6, minimum iOS 13.1, arm64; `UIBackgroundModes` =
`location`, `audio`; only `NSLocationWhenInUseUsageDescription`; `TrafficNetworkDart.framework` 1.2.1 embedded as a dynamic arm64 library
with the `frb_*` symbols; no code signature and no provisioning profile (as intended).

## Result of Part B (2026-10-24)

`xtool install` through `usbipd` + WSL `usbmuxd` hung at "[Connecting] 100%" (the known usbipd-win/usbmuxd problem, see
[xtool#19](https://github.com/xtool-org/xtool/issues/19), [usbipd-win#959](https://github.com/dorssel/usbipd-win/issues/959)). What worked:
"Apple Devices" (Microsoft Store, `9NP83LWLPZ9K`) on Windows owns the iPhone; its service listens on `127.0.0.1:27015`; a firewall rule
(TCP 27015, WSL interface only) and `netsh interface portproxy` from the WSL gateway address (`172.19.144.1`, may change after a WSL
restart) to `127.0.0.1:27015`; in WSL `export USBMUXD_SOCKET_ADDRESS=<gateway>:27015` and `xtool install TNViewer-unsigned.ipa`.
Output ended with "Successfully installed!". The iPhone must not be attached with `usbipd attach`. **Not yet verified:** that the app
starts and runs on the phone (device trust, Developer Mode, first launch).

## Risks

Private Apple APIs for the free login; 7-day profiles (re-install weekly); WSL USB passthrough can be fiddly; every test round is a
cloud run plus a re-install; iOS 27 against an iOS 26 SDK build (apps built with an older SDK run on newer systems, not tested here).
