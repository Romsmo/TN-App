# Traffic signs by camera

The phone's camera reads the signs at the roadside during a drive (beta 6). What it reads is shown first on the display and, where the
database lacks it, fed into the database. Off at the first start; needs the calibration.

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
Recognition Benchmark (GTSRB, 43 classes) plus a class "not a sign". Of the 43 classes the app uses 22 (the ones in the display's
catalogue, `classes.py`): speed limits and direction signs are not in the catalogue, and the right-hand curve has no entry.

Why not a bigger model: the best published accuracy on the GTSRB (99.9 %, a ViT-Base fine-tuned,
[bazyl/gtsrb-model](https://huggingface.co/bazyl/gtsrb-model), Apache-2.0) needs 86 million weights and about 340 MB; on a phone, once per
candidate and frame, that does not run in time. The accuracy on cropped benchmark images says little about the road anyway: what limits the
feature are the finder, the distance, the light and the false readings of things that are no sign. Those are the "not a sign" class and the
tracking above.

Data used for the model in the app (see `docs/decisions.md` D-N27 for the figures and the licence question):

* GTSRB: the Hugging Face mirror `bazyl/GTSRB` (train 236 MB, test 76 MB), the official test set only for the final numbers.
* "Not a sign": CIFAR-100 training pictures (`uoft-cs/cifar100`, 119 MB: vehicles, houses, plants, sky ...), the ones with the most red
  first, plus made-up red distractors (tail lights, banners, barriers) and sign crops moved off-centre.

```
python tool/signs_model/train.py --gtsrb-parquet train.parquet --gtsrb-test test.parquet --cifar cifar-train.parquet --epochs 30 --install
```

(`--synthetic` tests the script without data; its model is never installed.) The result and its numbers are written to
`out/report.json`.

**Numbers of the model in the app** (30 epochs, `tool/signs_model/out/report.json`):

* Held-out part of the training data (whole tracks kept apart, 5,236 crops): 99.4 % correct; 0.15 % of the "not a sign" crops are read as a sign.
* **Official GTSRB test set** (12,630 crops, never used for training): 97.8 % correct over all 43 classes, **96.9 % over the 22 classes the app uses**; 0.8 % read as "not a sign". Weakest: pedestrians, road work, no passing.
* These are cropped benchmark pictures. The "not a sign" class comes from CIFAR-100 and made-up distractors, not from road scenes: the rate of false readings on real footage is **not measured**.

## What is not verified

* Nothing of this has run on a phone: not the camera stream, the turning of the image, the TFLite runtime, the speed of a pass.
* The model was trained on cropped benchmark images and "not a sign" pictures that are not road scenes; it has never seen the finder's
  crops of real footage. The false-reading rate on a real road is unknown. A drive with a mounted phone and the report switch **off** is
  the first test; look at what the display shows before switching reporting on.
* The distance and the position of a sign are estimates (a few tens of metres at best).
* Dark, backlight, rain, dirty signs, signs on gantries and signs for other lanes are not handled specially.
