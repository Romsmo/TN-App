# Traffic signs by camera

The phone's camera reads the signs at the roadside during a drive (beta 6) and, since beta 7, the speed limits. What it reads is shown first on
the display and, where the database lacks it, fed into the database. Off at the first start. Nothing has to be aligned or set: the camera aligns itself while driving, and the **camera view** shows what the
phone sees.

## The chain

```
camera frame (about 7 per second, in a drive or while the camera view is open, in memory)
  -> upright RGB picture, at most 960 px wide                    lib/services/camera_frame.dart
  -> padded 640 x 640 square -> SignLocator (TFLite): where the   tn_core camera/sign_locator.dart, assets/models/signs_detector.tflite
     signs are (score, box per cell of a stride-4 grid)
     (without that model: CandidateFinder, red regions)            tn_core camera/sign_detector.dart
  -> SignClassifier (48 x 48 crop of the full frame, TFLite)      lib/services/sign_model_io.dart, assets/models/signs.tflite
  -> RawDetection (catalogue number, confidence, box)
  -> SignRecognizer: tracks over frames (predicted position),      tn_core camera/sign_recognizer.dart
     votes over the readings, places the sign
  -> RecognizedSign -> DriveSnapshot.recognizedSigns
       -> display columns (signColumnsFor, camera first)
       -> SignReporter: confirm or propose in the database         tn_core camera/sign_reporter.dart
```

Everything except the camera plugin and the network runtime is plain Dart and tested without a device (`packages/tn_core/test/camera_*`,
`test/camera_frame_test.dart`).

## Alignment (automatic) and the camera view

Until beta 8 the owner had to align the camera by hand (drag a cross onto the vanishing point, turn a slider) and the camera stayed **off**
until that was done. That is gone: the camera runs whenever the switch is on, and `AutoCalibration` (tn_core) learns what the alignment
gave.

* **Direction of travel and horizon** (`vanishingX`, `horizonY`): a sign stands still while the car drives up to it, so its box moves away
  from the vanishing point of the direction of travel in a straight line in the box's width. For every sign the recognition confirmed
  (5 or more frames, the width grew by at least 60 %), a least-squares line of x and y over the width, followed back to width zero, is
  one estimate of that point; estimates with a large standard error are dropped. After **3 signs** the median of the latest 30 replaces
  the image centre (limited to x 0.3-0.7, y 0.25-0.7). A bend, a lorry's sticker or a bad track does not fit a line or is outvoted by the
  median. What is learned is kept for the app's run, not stored.
* **Roll** is taken as 0 (a phone in a holder is upright).
* **Lens:** the field of view is not readable from the camera plugin; 65 degrees along the long side of the picture is assumed. A phone
  held upright shows the short side across: the field of view across the frame follows the frame's shape (`CameraCalibration.aspect`,
  about 39.5 degrees for 9:16), which keeps the distance estimate right in both holds. Distances stay rough (a 0.6 m sign is assumed).
* A sign whose angle is more than 35 degrees off the direction of travel stands at a side road and is ignored.
* **Camera view** (*Settings -> Signs by camera -> Open the camera view*, and a "Kamera" button in the drive): the live picture with a
  frame around every region the finder proposed. Green = read as a sign (name and confidence), amber = red region that was not read as a
  sign; a tick marks a sign the drive has confirmed and follows. It also shows how many pictures a second run through and what was
  learned. It works outside a drive too (then nothing is followed). Nothing is stored or sent.

## Speed limits (beta 7)

The classifier reads the limits 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130 as `274-<km/h>`. They are not signs of the display's
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

## The locator (beta 10)

Up to beta 9 the only way to find a sign was its red border (next section). That is what a system in a car never does: it looks at the
whole picture with a network that was trained on road scenes. Beta 10 does the same (`tool/signs_model/detect_train.py`):

* **Network:** a CenterNet-style heatmap detector. Backbone MobileNetV2 (width 0.35, ImageNet weights from Keras), a small feature
  pyramid down to stride 4, and per cell of the 160 x 160 grid five numbers: a sign score (0..1), width and height (in cells) and the
  centre's offset inside the cell. One class only, "a traffic sign"; the classifier says which. About 0.5 million weights, 2 MB.
* **Input:** the upright camera frame (at most 960 px wide) scaled so that its longer side is 640 px, put at the top left of a black
  640 x 640 square (`letterbox` in Dart, the same in Python). A phone held upright uses the left 360 px, one held sideways the top
  360 px. At 640 px a 0.6 m sign is about 10 px wide at 30 m, 6 px at 50 m.
* **Reading the output** (`decodeHeatmap`, the same rules in `detect_train.decode`): a cell whose score is at least **0.3** and the
  largest of its 3 x 3 neighbourhood is a sign; at most 20 per frame, boxes that cover another by more than half are dropped (NMS).
  A box in the black band or smaller than 6 px in the frame is dropped. The box, with a margin of 15 %, is cut from the full-resolution
  frame for the classifier (so a sign that is 10 px in the 640 square is read from its 15 px in the frame).
* **Training data:** the German Traffic Sign Detection Benchmark (GTSDB, 900 frames of 1360 x 800 from a car, 1,213 signs; frames
  0-599 for training, 600-899 only for the numbers below; its ReadMe says "You are free to use this data package for any purpose you
  like", the paper Houben et al., IJCNN 2013 is to be cited). Into the training frames real GTSRB signs and made-up speed signs are
  pasted with a soft edge of their shape and matched brightness (up to 4 per frame, 8-140 px, 70 % of the pictures), so that the
  network sees far more signs, small ones in particular, and the sixteen limits. Random scale (0.3-0.95 of the frame), 384 px crops,
  flips, brightness 0.35-1.3, contrast, saturation, colour cast, blur, motion blur, noise, and in a quarter of the pictures the black
  band of the padded square. Loss: CenterNet focal loss on the heatmap, L1 on size and offset. 50 epochs of 2,400 pictures on a GPU
  (RTX 3060 in WSL: 40 s per epoch; the process grows to 7.5 GB over the epochs and WSL froze or killed it twice, so every epoch is
  checkpointed in `--out` and `--resume` goes on from there).
* **Numbers** (`out-detector/report.json`, `eval_chain.py`; the 300 GTSDB test frames 600-899, 361 signs, never trained on):
  AP50 **0.91**. At the app's score 0.3 the locator finds **94.5 %** of the signs (signs up to 12 px in the 640 square: 84 %,
  12-24 px: 97 %, 24 px and more: 100 %) with 0.5 false boxes per frame (at 0.4: 91 % and 0.21; at 0.5: 81 % and 0.08). Whole chain,
  locator plus classifier at probability 0.6, on the 238 signs of classes the app uses: **95.8 % found and read as the right sign**;
  of the found ones 100 % were read right, none wrong, none as "not a sign". False boxes that the classifier reads as a sign:
  **0.017 per frame** (one in 60 frames, before the tracking, which needs three frames). Caveat: the training frames are the same
  drive (frames 0-599), so the numbers are for that camera, road and weather; other roads will be worse.
* **Signs without red** (the end of a limit, 278; the end of all limits, 282; the end of an overtaking ban, 280/281) are found now.
  The classifier knew them all along (GTSRB classes 6, 32, 41, 42); the finder never proposed them.
* **Fallback:** an app built without `signs_detector.tflite` uses the colour finder as before; the camera view says which is at work.

## The finder's "red" (beta 8, the fallback since beta 10)

Measured on 2,878 real German circle signs of the GTSRB (32 x 32 crops): the red of a ring is rarely the pure red the old rule asked
for (R >= 110, R >= 2.8 G, R >= 2.8 B, R - min(G, B) >= 60). The ring's median is about (120, 53, 47), R over max(G, B) about 2.2. With
the old rule **only 7 % of the real signs gave a candidate at all**, so the camera practically saw nothing. The rule now measures red
against the pixel's own brightness (`isSignRed`): R >= 40, the lead of R over G and B at least 16 % of R + G + B, and G and B about equal
(that keeps orange out; it costs no recall). The mask is thickened by one pixel before grouping so that a ring broken by a branch stays one
region; shape limits are wider (aspect 0.6-1.65, fill 0.08-0.92 so that the filled no-entry disc passes), smallest side 7 px of 480.
Same test, same data: **67 % of the signs give a candidate** (59 % at least 60 % of the crop's size); on CIFAR-100 pictures (no signs)
25 % give a candidate, against 4 % with the old rule: the classifier's class "not a sign" and the tracking have to catch those (more
false candidates cost a little time, not false signs). These are 32 x 32 crops of dark, partly blurred benchmark pictures; on a
phone's video the ring is wider and better lit, so the share should be higher. **Not measured on road video.**


## From detections to signs (what is strict and why)

* **Tracks** (beta 10): a detection joins the track whose sign is expected nearest in this frame, the last place moved on with the
  speed the box had in the picture (a sign the car drives past moves outward faster and faster: at 7 frames a second and 100 km/h a
  near sign jumps by a fifth of the picture between frames, which broke tracks before). The allowed distance is 0.12 of the width or
  1.5 times the box, whichever is more; the size may change by 0.4-2.5 between frames; the same reading counts as nearer.
* A sign needs the same reading in **3 frames**, 70 % of the track's frames agreeing, mean confidence 0.75. Two boxes at one place that
  read differently vote against each other: nothing is shown.
* The finder only proposes **red-bordered** regions (not in the lower 28 % of the picture, not far below the horizon: a sign hangs
  higher than the camera, but a low post is possible). **Signs without red are not
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

## The classifier

`tool/signs_model/train.py` trains a small convolutional network (about 0.3 million weights, 1.3 MB as TFLite) on the German Traffic Sign
Recognition Benchmark (GTSRB, 43 classes), eight more speed limits and a class "not a sign" (52 outputs). Since beta 10 the crop is
**48 x 48** (was 32: a three-digit limit needs the pixels) and the training data also holds the signs of the GTSDB training frames cut
out of the road scene four times each with the jitter a located box has (3,408 crops), plus "not a sign" crops of those frames
(red regions and random squares, the signs kept out). Of the 43 GTSRB classes the app
uses 22 signs of the display's catalogue plus the eight speed limits (`classes.py`); direction signs are not used, and the right-hand curve
has no entry. The end-of-limit signs (no red) are in the model but never found by the finder.

Why not a bigger model: the best published accuracy on the GTSRB (99.9 %, a ViT-Base fine-tuned,
[bazyl/gtsrb-model](https://huggingface.co/bazyl/gtsrb-model), Apache-2.0) needs 86 million weights and about 340 MB; on a phone, once per
candidate and frame, that does not run in time. The accuracy on cropped benchmark images says little about the road anyway: what limits the
feature are the finder, the distance, the light and the false readings of things that are no sign. Those are the "not a sign" class and the
tracking above.

Data used for the model in the app (see `docs/decisions.md` D-N27 for the figures and the licence question):

* GTSRB: the Hugging Face mirror `bazyl/GTSRB` (train 236 MB, test 76 MB), the official test set only for the final numbers.
* **Speed limits 40, 90, 110, 130 and the small 5, 10, 15, 25** (pedestrian zones, car parks, residential areas) are not in the GTSRB. Their classes (43-50) are trained on **pictures made here** (`speed_synth.py`):
  real GTSRB speed-sign crops whose number is wiped out and written again in a DIN-like face (Windows' Bahnschrift), so ring, light, blur
  and noise stay real (`repaint`), plus a quarter of fully drawn signs. The other eight limits get the same treatment for a share of their
  pictures so that "painted" is no hint. **No real picture of a 5, 10, 15, 25, 40, 90, 110 or 130 sign was ever used or tested.**
* "Not a sign": CIFAR-100 training pictures (`uoft-cs/cifar100`, 119 MB: vehicles, houses, plants, sky ...), the ones with the most red
  first, plus made-up red distractors (tail lights, banners, barriers) and sign crops moved off-centre.

```
python tool/signs_model/train.py --gtsrb-parquet train.parquet --gtsrb-test test.parquet --cifar cifar-train.parquet --epochs 30 --install
```

(`--synthetic` tests the script without data; its model is never installed.) The result and its numbers are written to
`out/report.json`.

**Numbers of the model in the app** (beta 10: 48 x 48, 52 classes, GTSDB road-scene crops added; 30 epochs, `report.json`):

* **Official GTSRB test set, the eight real speed limits** (4,170 crops): **99.1 %** read as the right limit (beta 8: 98.9 %), 0.7 % as
  another limit, 0.1 % as "not a sign". Weakest: 60 (96.7 %, read as 80). **For 40, 90, 110, 130 and 5, 10, 15, 25 there is no real
  data to measure with.** The only estimate is an experiment at 32 px (`train.py --speed-gap`, beta 7): a network that never saw a real
  sign of the eight limits, only painted ones, read the real ones **82 %** right (with fully drawn signs only: 63 %); the weakest were
  the three-digit limits (100: 54 %, read as 120 or 130) and 80 (69 %). Expect the eight new limits to be read worse than the other
  eight; 5 / 10 / 15 / 25 and 10 / 100 / 110 are the likeliest mix-ups.
* Official test set over all 43 classes: **98.5 %** (beta 8: 97.8 %); over the 22 sign classes of beta 6: 98.3 % (beta 6: 96.9 %);
  0.9 % read as "not a sign". At 0.6 minimum probability 99.2 % of the crops are taken.
* Held-out part of the training data (9,540 crops, whole tracks kept apart): 99.7 % correct (includes painted crops, which says little
  about the road); 0.03 % of the "not a sign" crops are read as a sign.
* What the whole chain reads on real road frames: the locator section above and `eval_chain.py`.

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
* The locator and the classifier were trained on 600 road frames of one German drive in 2013 (GTSDB) and cropped benchmark images, and
  measured on 300 frames of the same kind. Other cameras, other roads, night, rain and a phone's windscreen reflection are not in that
  data. A drive with a mounted phone and the report switch **off** is the first test; look at the camera view before switching reporting on.
* The distance and the position of a sign are estimates (a few tens of metres at best).
* Dark, backlight, rain, dirty signs, signs on gantries and signs for other lanes are not handled specially.
