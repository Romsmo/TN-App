# Getting the app onto the iPhone from Windows (Gate 0)

Status 2026-10-23: **not done.** Facts so far, with sources and dates; nothing below was executed.

## What the owner has

iPhone with iOS 27; a **paid** Apple Developer account (profiles valid one year, TestFlight possible — but TestFlight / store
upload is outside this job and needs an explicit approval); Windows 11, no Mac; Flutter 3.38.7; Visual Studio 2022 with MSVC
14.37 and the Windows 11 SDK; no Swift, no LLVM, no xcross, no usable Python with pip.

## Why path (a) (xcross) is plausible now

- The Flutter plugin of `client-lib-v1.2.1` ships a Swift Package manifest (`ios/trafficnetwork_flutter/Package.swift`, product
  `trafficnetwork-flutter`) and a **dynamic** `TrafficNetworkDart.framework` (read on the tag; wish 1 of `wishes-clientlib.md`).
  xcross skips plugins that only have a podspec ([github.com/arxdeus/xcross](https://github.com/arxdeus/xcross), README read
  2026-10-22). `maplibre_gl` also has `ios/maplibre_gl/Package.swift`. Other plugins used: `geolocator`, `flutter_secure_storage`,
  `audioplayers`, `flutter_tts`, `wakelock_plus`, `connectivity_plus`, `path_provider`, `url_launcher` — **their SwiftPM support
  has not been checked.**
- xcross v2.0.6 (released 2026-10-16, AGPL-3.0, repo created 2026-07-02): `xcross-windows-x64.zip`, 43,895,804 bytes,
  SHA-256 `4bae6f8dec3024135dbebf892bf8eaffa11267dc62de43c6d00d05c49a4adbd2` (matches `SHA256SUMS.txt`; build provenance
  attestation verified with `gh attestation verify` on 2026-10-23). Needs Swift ≥ 6.4 (winget: `Swift.Toolchain` 6.4.1,
  installer 2,097,955,608 bytes), LLVM, Python 3 + `pymobiledevice3`, a **full `Xcode.xip`** from Apple (you download it with your
  Apple ID), an administrator PowerShell for `xcross tunnel` (again after every reconnect), iOS ≥ 17 on the phone.
- **Not verified:** that xcross embeds and signs a *dynamic* framework from a SwiftPM binary target; that release (AOT) builds
  work; how large the SDK is on disk (74.8 GB free on `D:`).
- Risks named by xcross itself: sign-in path "may trigger account locks" (use a separate Apple ID if you can); it downloads
  Android ADI libraries from the Apple Music APK on first use — **I do not allow that without your explicit yes.**

## Path (b): a macOS runner builds, Windows installs

`.github/workflows/ios-unsigned.yml` (manual start) builds an **unsigned** `.ipa` on `macos-15` with CocoaPods/SwiftPM as
Flutter does it, tests included. Then sign and install it from Windows with your own Apple ID (xtool `install` or a sideloading
tool; xtool's Windows install page was not reachable on 2026-10-22, so that route is unverified). macOS minutes cost about ten
times Linux minutes (list price 0.062 $/min against 0.006 $/min, from the Enterprise Server pricing page; the github.com page was
not read). Each test round is a cloud run plus a re-install.

## Path (c): borrow or rent a Mac

Technically the safest; cost and availability are yours to decide.

## Free vs paid account (for the record)

A free account: profiles of 7 days, about 3 apps, about 10 App IDs per 7 days (secondary sources only:
[Corellium](https://support.corellium.com/features/apps/sideloadly),
[mybyways](https://mybyways.com/blog/new-limitations-imposed-on-free-apple-developer-account); Apple's own page not read).
Not relevant with the paid account.

## What you do yourself (never in chat, never in a file)

Apple ID, password, 2FA codes, the Xcode download, `xcross auth`, Developer Mode on the iPhone (Settings → Privacy & Security),
trusting the developer profile, the administrator prompt for the tunnel.

## Suggested order

1. Decide (a), (b) or (c). 2. Hello-world Flutter app **with** `trafficnetwork_flutter` (one call) on the iPhone: if that
fails, find out why before anything else. 3. This app.
