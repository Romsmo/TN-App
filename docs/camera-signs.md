# Traffic signs by camera

The phone's camera reads the signs at the roadside during a drive (beta 6) and, since beta 7, the speed limits. What it reads is shown first on
the display and, where the database lacks it, fed into the database. Off at the first start; needs the calibration.

## The chain

```
camera frame (about 4 per second, only in drive mode, in memory)
  -> upright RGB picture, at most 960 px wide                    lib/services/camera_frame.dart
  -> CandidateFinder: red regions that look like a sign           tn_core camera/sign_detector.dart
  -> SignClassifier (32 x 32 crop, TFLite)                        lib/services/sign_model_io.dart, assets/models/signs.tflite
  -> RawDetection (catalogue number, confidence, box)
  -> SignRecognizer: tracks over frames, places the sign           tn_core camera/sign_recognizer.dart
  -> RecognizedSign -> DriveSnapshot.recognizedSigns
       -> display columns (signColumnsFor, camera first)
       -> SignReporter: confirm or propose in the database         tn_core camera/sign_reporter.dart
```

Everything except the camera plugin and the network runtime is plain Dart and tested without a device (`packages/tn_core/test/camera_*`,
`test/camera_frame_test.dart`).

## Calibration

*Settings -> Signs by camera -> Align the camera.* The car stands on a straight road. The owner drags a cross onto the point where the road
disappears (it gives the direction of travel `vanishingX` and the horizon `horizonY`) and turns a line with a slider until it lies on the
horizon (`rollDeg`). `CameraCalibration` turns an image point into an angle off the direction of travel and an elevation; a sign whose
angle is more than 35 degrees off the road stands at a side road and is ignored. The field of view of the lens is not readable from the
camera plugin: 65 degrees is assumed (`hFovDeg`), which makes distances rough (a typical sign of 0.6 m width is assumed; a motorway
sign is twice that). A small picture on the calibration page shows what the recognition itself sees, so a wrongly turned image is
noticed there. A placement is rejected with a hint when the horizon is outside the middle band, the image is turned by more than 8
degrees, or the road does not lead to the middle.

## Speed limits (beta 7)

The classifier reads the limits 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130 as `274-<km/h>`. They are not signs of the display's
catalogue (the display draws the limit from a number), so they never enter the sign columns; they set the limit of the drive.

* **Shown:** the latest speed sign the car has reached (or is less than 20 m before) sets `DriveSnapshot.limit`, with `limitFromCamera`;
  the database's value stays in `databaseLimit`. The speed state (over the limit), the display's limit and its speed-camera limit follow
  the shown limit. The drive screen marks a camera limit with a small camera badge.
* **Until when:** the next speed sign replaces it, the end of all limits (282, which the finder cannot see) ends it, **1.5 km** at most,
  and it gives way when the database later holds *another* value for the road (a value that differs from what it held when the sign was
  reached and from the camera's value, found more than 50 m after the sign). The end-of-limit signs have no red and are not read.
* **Not a lorry's sticker:** a speed sticker on the back of a lorry looks like a small sign. A speed sign counts only when, over at least 8 m
  driven, its apparent size grew the way a fixed sign's does when the car drives up to it (1 / width falls linearly with the odometer, at
  least 0.6 of the rate of the biggest real sign, 1.5 m). Something that keeps its distance to the car does not grow. A car that stands or
  crawls (under 8 m over the track) cannot show it, so a limit is not read then. Made up with synthetic tracks, never seen on a road.
* **Database (same switch as the other signs):** about 60 m after the sign the database is asked for the road's limit at the car's position
  (at the sign itself it may still hold the old limit: the sign stands where it changes). The same value -> nothing. Another value ->
  `reportWrongSpeedLimit` with the camera's value at the car's position. None, and the offline data covers the spot -> the stretch from this
  sign to the next limit sign is proposed (`reportSpeedLimitInterval`), once that sign is out of sight and read as strictly (4 frames, 0.85);
  30 m to 5 km. Skipped when the car turned off by more than 25 degrees, when the check came later than 400 m, for a database in mph, and
  after 20 reports a trip. One voice only: it counts when other devices agree.
* **Weak spots:** additional plates (time, wet, school) are not read, so a limit that holds only at times is proposed as always valid.
  Look-alikes: 60 / 80, 100 / 120 / 130, 30 / 50 are the likeliest misreadings; the track must agree in 70 % of its frames at a mean
  of 0.75 to be shown, 0.85 and 4 frames to be sent.

## From detections to signs (what is strict and why)

* A sign needs the same reading in **3 frames**, 70 % of the track's frames agreeing, mean confidence 0.75. Two boxes at one place that
  read differently vote against each other: nothing is shown.
* The finder only proposes **red-bordered** regions above the horizon (a sign hangs higher than the camera). **Signs without red are not
  found; this includes the end-of-ban signs 280, 281, 282.** Consequence: a ban the camera saw stays on the display until a database sign
  replaces it, the road ends it (not modelled), or **2 km** have been driven (warnings: 400 m).
* Priority on the display: a camera sign wins against a conflicting database sign that begins up to 30 m after it (both positions are
  estimates); a database sign that clearly begins later still applies. Conflict means the display's own rules (`sign-rules.json`:
  replacement families, `282` cancels bans, the cap of three).
* **Reporting** (switch *Feed the database*, off at first start): stricter than showing: 4 frames, confidence 0.85, a heading, at most 40
  actions per trip, one per sign and 60 m.
  * The database holds the same sign here (or one in force here) -> `voteContextSign(id, true)`, once per entry and trip.
  * Otherwise a **point sign** (`101-11`, `102`, `131`, `151`, `267`, `280`-`282`) -> `reportContextSign` with one point and the heading.
  * A **stretch sign** (`276`, `277`) waits until an end sign (`276`/`277`/`280`/`281`/`282`) was seen: then both points go out. The length is
    never guessed; 30 m to 5 km.
  * Other warnings (they stand over a stretch the camera cannot measure) and signs with a value (253, 262-266, 273, 270) are **never sent**.
  * A proposal is one voice; it counts as confirmed only when other devices agree (3 for bans, 2 for warnings). A write that fails is not retried.
  * The camera cannot read **additional plates** ("Mo-Fr 7-17 Uhr"): a proposal has no time window. This is the known weak spot of the
    feature.
  * What leaves the phone: sign type, a coordinate, the heading. Never an image.

## The model

`tool/signs_model/train.py` trains a small convolutional network (about 0.3 million weights, 1.2 MB as TFLite) on the German Traffic Sign
Recognition Benchmark (GTSRB, 43 classes), four more speed limits and a class "not a sign" (48 outputs). Of the 43 GTSRB classes the app
uses 22 signs of the display's catalogue plus the eight speed limits (`classes.py`); direction signs are not used, and the right-hand curve
has no entry. The end-of-limit signs (no red) are in the model but never found by the finder.

Why not a bigger model: the best published accuracy on the GTSRB (99.9 %, a ViT-Base fine-tuned,
[bazyl/gtsrb-model](https://huggingface.co/bazyl/gtsrb-model), Apache-2.0) needs 86 million weights and about 340 MB; on a phone, once per
candidate and frame, that does not run in time. The accuracy on cropped benchmark images says little about the road anyway: what limits the
feature are the finder, the distance, the light and the false readings of things that are no sign. Those are the "not a sign" class and the
tracking above.

Data used for the model in the app (see `docs/decisions.md` D-N27 for the figures and the licence question):

* GTSRB: the Hugging Face mirror `bazyl/GTSRB` (train 236 MB, test 76 MB), the official test set only for the final numbers.
* **Speed limits 40, 90, 110, 130** are not in the GTSRB. Their classes (43-46) are trained on **pictures made here** (`speed_synth.py`):
  real GTSRB speed-sign crops whose number is wiped out and written again in a DIN-like face (Windows' Bahnschrift), so ring, light, blur
  and noise stay real (`repaint`), plus a quarter of fully drawn signs. The other eight limits get the same treatment for a share of their
  pictures so that "painted" is no hint. **No real picture of a 40, 90, 110 or 130 sign was ever used or tested.**
* "Not a sign": CIFAR-100 training pictures (`uoft-cs/cifar100`, 119 MB: vehicles, houses, plants, sky ...), the ones with the most red
  first, plus made-up red distractors (tail lights, banners, barriers) and sign crops moved off-centre.

```
python tool/signs_model/train.py --gtsrb-parquet train.parquet --gtsrb-test test.parquet --cifar cifar-train.parquet --epochs 30 --install
```

(`--synthetic` tests the script without data; its model is never installed.) The result and its numbers are written to
`out/report.json`.

**Numbers of the model in the app** (beta 7, 48 classes; beta 6 had 44, see below; 30 epochs, `report.json`):

* **Official GTSRB test set, the eight real speed limits** (4,170 crops): 98.7 % read as the right limit, 1.0 % as another limit, 0.2 % as
  "not a sign". Weakest: 60 (95.6 %, 18 of 450 read as 80). **For 40, 90, 110, 130 there is no real data to measure with.** The only
  estimate is an experiment (`train.py --speed-gap`): a network that never saw a real sign of the eight limits, only painted ones, read
  the real ones **82 %** right (with fully drawn signs only: 63 %); the weakest were the three-digit limits (100: 54 %, read as 120 or
  130) and 80 (69 %). Expect the four new limits to be read worse than the other eight.
* Held-out part of the training data: 99.1 % correct (includes painted crops, which says little about the road).
* Official test set over all 43 classes: 97.7 %; over the 22 sign classes of beta 6: 96.7 % (beta 6: 96.9 %); 1.0 % read as "not a sign".

Numbers of the beta 6 model (kept for comparison, `tool/signs_model/out/report.json` then):

* Held-out part of the training data (whole tracks kept apart, 5,236 crops): 99.4 % correct; 0.15 % of the "not a sign" crops are read as a sign.
* **Official GTSRB test set** (12,630 crops, never used for training): 97.8 % correct over all 43 classes, **96.9 % over the 22 classes the app uses**; 0.8 % read as "not a sign". Weakest: pedestrians, road work, no passing.
* These are cropped benchmark pictures. The "not a sign" class comes from CIFAR-100 and made-up distractors, not from road scenes: the rate of false readings on real footage is **not measured**.

## What is not verified

* Nothing of this has run on a phone: not the camera stream, the turning of the image, the TFLite runtime, the speed of a pass.
* **Speed limits (beta 7):** the check that separates a sign from a lorry's speed sticker (growth of the apparent size over the distance
  driven) is tested with made-up tracks only; real boxes jitter, so it may reject real signs too (a missed limit, not a wrong one) or let
  a sticker through. The limits 40, 90, 110, 130 were never seen as real pictures (see the model numbers). Whether a camera limit on a
  real road matches the real limit, and how often the database proposals are right, is unknown. Start with the report switch off.
* The model was trained on cropped benchmark images and "not a sign" pictures that are not road scenes; it has never seen the finder's
  crops of real footage. The false-reading rate on a real road is unknown. A drive with a mounted phone and the report switch **off** is
  the first test; look at what the display shows before switching reporting on.
* The distance and the position of a sign are estimates (a few tens of metres at best).
* Dark, backlight, rain, dirty signs, signs on gantries and signs for other lanes are not handled specially.
