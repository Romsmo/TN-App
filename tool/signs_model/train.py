"""Trains the classifier that reads a cropped traffic-sign candidate (see docs/camera-signs.md).

Input of the network: a 32 x 32 RGB crop, values 0..1 (NHWC), cut with a margin of 15 % around the red border of the sign, exactly as
the app's candidate finder cuts it. Output: 48 probabilities, the 43 classes of the German Traffic Sign Recognition Benchmark (GTSRB) in
its numbering, four more speed limits the GTSRB lacks (40, 90, 110, 130; classes 43-46, trained on made-up pictures from
`speed_synth.py`) and "not a sign" (class 47). The classes are listed in `classes.py`.

Real training needs data that is NOT part of this repository and whose terms of use you must check yourself first:

  --gtsrb DIR       the GTSRB training images: DIR holds the folders 00000 ... 00042, each with its images and GT-NNNNN.csv
  --gtsrb-parquet FILE   the same data as one parquet file (columns Path.bytes, ClassId, Roi.X1..Y2), e.g. the Hugging Face mirror
  --gtsrb-test FILE      the official GTSRB test set (parquet), used only for the final numbers, never for training
  --cifar FILE      use the CIFAR-100 training pictures (parquet) (cars, trucks, buses, roads, houses, trees, sky ...) as "not a sign" examples, the
                    ones with much red first; plus made-up red distractors (tail lights, banners) and sign crops moved off-centre
  --background DIR  photographs of roads without the signs the app reads, to learn "not a sign"; red things that are no sign
                    (tail lights, cars, banners) are cut out as hard examples. Photos from the GTSDB can be used with
                    --gtsdb-gt gt.txt: the labelled signs are then kept out of the background crops.

`--synthetic` makes up a tiny data set to test this script from end to end. A model made like that is worthless on a road and is never
copied into the app.

By default everything is written to tool/signs_model/out/. `--install` copies signs.tflite and signs_labels.json into assets/models/.
"""

import argparse
import csv
import json
import os
import random
import shutil
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import classes  # noqa: E402
import speed_synth  # noqa: E402

SIZE = classes.SIZE
N_CLASSES = classes.N_CLASSES
MARGIN = 0.15
HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.abspath(os.path.join(HERE, "..", ".."))


def crop_square(img, cx, cy, side):
    """A square of `side` around (cx, cy), scaled to SIZE x SIZE; outside the image the edge pixels repeat."""
    arr = np.asarray(img)
    h, w = arr.shape[:2]
    xs = np.clip((cx - side / 2 + (np.arange(SIZE) + 0.5) * side / SIZE).astype(int), 0, w - 1)
    ys = np.clip((cy - side / 2 + (np.arange(SIZE) + 0.5) * side / SIZE).astype(int), 0, h - 1)
    return arr[np.ix_(ys, xs)]


def load_gtsrb(root):
    xs, ys, tracks = [], [], []
    for c in range(43):
        d = os.path.join(root, "%05d" % c)
        with open(os.path.join(d, "GT-%05d.csv" % c), newline="") as f:
            for row in csv.DictReader(f, delimiter=";"):
                img = Image.open(os.path.join(d, row["Filename"])).convert("RGB")
                x1, y1, x2, y2 = (int(row[k]) for k in ("Roi.X1", "Roi.Y1", "Roi.X2", "Roi.Y2"))
                w, h = x2 - x1 + 1, y2 - y1 + 1
                side = max(w, h) * (1 + 2 * MARGIN)
                xs.append(crop_square(img, x1 + w / 2, y1 + h / 2, side))
                ys.append(c)
                tracks.append(c * 1000 + int(row["Filename"].split("_")[0]))
    return np.stack(xs), np.array(ys), np.array(tracks)


def load_parquet(path):
    """The GTSRB as one parquet file; the track of an image is read from its file name (class_track_frame)."""
    import io

    import pyarrow.parquet as pq

    pf = pq.ParquetFile(path)
    xs, ys, tracks = [], [], []
    for g in range(pf.num_row_groups):
        t = pf.read_row_group(g).to_pydict()
        for i in range(len(t["ClassId"])):
            img = Image.open(io.BytesIO(t["Path"][i]["bytes"])).convert("RGB")
            x1, y1, x2, y2 = (int(t[k][i]) for k in ("Roi.X1", "Roi.Y1", "Roi.X2", "Roi.Y2"))
            w, h = x2 - x1 + 1, y2 - y1 + 1
            xs.append(crop_square(img, x1 + w / 2, y1 + h / 2, max(w, h) * (1 + 2 * MARGIN)))
            ys.append(int(t["ClassId"][i]))
            name = os.path.basename(t["Path"][i]["path"] or "")
            parts = os.path.splitext(name)[0].split("_")
            tracks.append(ys[-1] * 1000 + (int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else len(xs) // 30))
    return np.stack(xs), np.array(ys), np.array(tracks)


def cifar_negatives(path, count, rng):
    """CIFAR-100 pictures (a parquet file with an `img.bytes` column) as "not a sign": half the ones with the most red, half at random."""
    import io

    import pyarrow.parquet as pq

    col = pq.read_table(path, columns=["img"]).column("img").to_pylist()
    x = np.stack([np.asarray(Image.open(io.BytesIO(c["bytes"])).convert("RGB")) for c in col])
    red = is_sign_red(x).reshape(len(x), -1).mean(1)
    order = np.argsort(-red)
    hard = order[: count // 2]
    rest = rng.choice(len(x), count - len(hard), replace=False)
    pick = np.concatenate([hard, rest])
    out = x[pick]
    flip = rng.random(len(out)) < 0.5
    out[flip] = out[flip][:, :, ::-1]
    return out


def cifar_images(path, count, rng):
    """Some CIFAR-100 pictures as they are, as backgrounds for the made-up speed signs."""
    import io

    import pyarrow.parquet as pq

    col = pq.read_table(path, columns=["img"]).column("img").to_pylist()
    pick = rng.choice(len(col), min(count, len(col)), replace=False)
    return np.stack([np.asarray(Image.open(io.BytesIO(col[i]["bytes"])).convert("RGB")) for i in pick])


def distractors(count, rng):
    """Red things on roads that are no sign: tail lights, banners, bonnets, barriers, red-white stripes."""
    out = []
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    for _ in range(count):
        bg = rng.integers(40, 200, 3)
        img = np.tile(bg, (SIZE, SIZE, 1)).astype(np.float32) + rng.normal(0, 10, (SIZE, SIZE, 3))
        red = (rng.integers(150, 230), rng.integers(10, 70), rng.integers(10, 70))
        kind = rng.integers(0, 5)
        cx, cy = rng.integers(8, SIZE - 8, 2)
        if kind == 0:  # tail light, a filled disc or ellipse
            a, b = rng.integers(4, 12), rng.integers(3, 12)
            img[((xx - cx) / a) ** 2 + ((yy - cy) / b) ** 2 < 1] = red
        elif kind == 1:  # banner or car body, a filled rectangle
            x0, x1 = sorted(rng.integers(0, SIZE, 2))
            y0, y1 = sorted(rng.integers(0, SIZE, 2))
            img[y0:y1 + 2, x0:x1 + 2] = red
        elif kind == 2:  # red-white stripes (a barrier)
            period = rng.integers(3, 8)
            m = ((xx + yy) // period) % 2 == 0
            img[m] = red
            img[~m] = 235
        elif kind == 3:  # red gradient (a sunset, a roof)
            g = np.clip(yy / SIZE + rng.normal(0, 0.1), 0, 1)[..., None]
            img = img * g + np.array(red) * (1 - g)
        else:  # a ring that is cut off by the frame or filled: not a sign as the finder would cut it
            d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
            img[d < rng.integers(5, 10)] = red
            img[(d < 3)] = 235
        out.append(np.clip(img, 0, 255).astype(np.uint8))
    return np.stack(out)


def off_centre(x, y, count, rng):
    """Sign crops moved so far off-centre that the sign is mostly outside: a finder box that sits next to a sign."""
    idx = rng.integers(0, len(x), count)
    out = []
    for i in idx:
        img = x[i]
        dx, dy = rng.choice([-1, 1]) * rng.integers(24, 32), rng.choice([-1, 1]) * rng.integers(0, 12)
        shifted = np.roll(np.roll(img, dx, axis=1), dy, axis=0)
        if dx > 0:
            shifted[:, :dx] = shifted[:, dx:dx + 1]
        else:
            shifted[:, dx:] = shifted[:, dx - 1:dx]
        out.append(shifted)
    return np.stack(out)


def is_sign_red(a):
    r, g, b = (a[..., i].astype(int) for i in range(3))
    return (r >= 110) & (r * 10 >= g * 28) & (r * 10 >= b * 28) & ((r - np.minimum(g, b)) >= 60)


def load_background(root, gtsdb_gt, per_image_random=6, rng=None):
    """Crops without a sign: red regions that look like candidates (hard examples) and random squares."""
    import cv2

    rng = rng or random.Random(1)
    boxes = {}
    if gtsdb_gt:
        with open(gtsdb_gt) as f:
            for line in f:
                p = line.strip().split(";")
                if len(p) >= 6:
                    boxes.setdefault(p[0], []).append(tuple(int(v) for v in p[1:5]))

    def clear_of_signs(name, x0, y0, x1, y1):
        for (a, b, c, d) in boxes.get(name, []):
            if x0 < c and x1 > a and y0 < d and y1 > b:
                return False
        return True

    out = []
    for fn in sorted(os.listdir(root)):
        if not fn.lower().endswith((".png", ".jpg", ".jpeg", ".ppm", ".bmp")):
            continue
        img = Image.open(os.path.join(root, fn)).convert("RGB")
        a = np.asarray(img)
        h, w = a.shape[:2]
        mask = is_sign_red(a).astype(np.uint8)
        n, _, stats, cent = cv2.connectedComponentsWithStats(mask, connectivity=8)
        for i in range(1, n):
            x, y, bw, bh, area = stats[i]
            if bw < 9 or bh < 9 or not (0.7 <= bw / bh <= 1.45) or not (0.1 <= area / (bw * bh) <= 0.8):
                continue
            if clear_of_signs(fn, x, y, x + bw, y + bh):
                out.append(crop_square(img, x + bw / 2, y + bh / 2, max(bw, bh) * (1 + 2 * MARGIN)))
        for _ in range(per_image_random):
            side = rng.randint(16, max(17, min(h, w) // 3))
            cx, cy = rng.randint(0, w - 1), rng.randint(0, h - 1)
            if clear_of_signs(fn, cx - side / 2, cy - side / 2, cx + side / 2, cy + side / 2):
                out.append(crop_square(img, cx, cy, side))
    if not out:
        sys.exit("no background crops found in " + root)
    return np.stack(out)


def synthetic(rng):
    """Class k is a ring of a fixed colour pattern (k mod 7) with a bar at a fixed angle (k mod 5); the last class is noise and blobs."""
    xs, ys, tracks = [], [], []
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    d = np.sqrt((xx - SIZE / 2 + 0.5) ** 2 + (yy - SIZE / 2 + 0.5) ** 2)
    for c in range(N_CLASSES):
        for t in range(12):
            for _ in range(6):
                img = np.full((SIZE, SIZE, 3), 120, np.float32) + rng.normal(0, 8, (SIZE, SIZE, 3))
                if c < classes.N_SIGN_CLASSES:
                    ring = (d <= 13) & (d >= 9)
                    img[ring] = (200, 20 + 10 * (c % 7), 25)
                    inner = d < 9
                    img[inner] = 240
                    ang = (c % 5) * np.pi / 5
                    bar = np.abs((xx - SIZE / 2) * np.sin(ang) - (yy - SIZE / 2) * np.cos(ang)) < 1.5 + (c // 5) % 3
                    img[bar & inner] = 20
                else:
                    for _ in range(3):
                        cx, cy = rng.integers(0, SIZE, 2)
                        r = rng.integers(3, 9)
                        img[(xx - cx) ** 2 + (yy - cy) ** 2 < r * r] = rng.integers(0, 255, 3)
                xs.append(np.clip(img, 0, 255).astype(np.uint8))
                ys.append(c)
                tracks.append(c * 1000 + t)
    return np.stack(xs), np.array(ys), np.array(tracks)


def build_model(keras):
    L = keras.layers

    def block(x, n):
        x = L.Conv2D(n, 3, padding="same", use_bias=False)(x)
        x = L.BatchNormalization()(x)
        return L.Activation("relu")(x)

    inp = keras.Input((SIZE, SIZE, 3))
    x = block(inp, 32)
    x = block(x, 32)
    x = L.MaxPool2D()(x)
    x = block(x, 64)
    x = block(x, 64)
    x = L.MaxPool2D()(x)
    x = block(x, 128)
    x = block(x, 128)
    x = L.GlobalAveragePooling2D()(x)
    x = L.Dropout(0.3)(x)
    out = L.Dense(N_CLASSES, activation="softmax")(x)
    return keras.Model(inp, out)


def augment(keras):
    L = keras.layers
    return keras.Sequential([
        L.RandomTranslation(0.08, 0.08, fill_mode="nearest"),
        L.RandomZoom(0.12, fill_mode="nearest"),
        L.RandomRotation(0.04, fill_mode="nearest"),
        L.RandomBrightness(0.35, value_range=(0, 1)),
        L.RandomContrast(0.3),
    ])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--gtsrb")
    ap.add_argument("--gtsrb-parquet")
    ap.add_argument("--gtsrb-test")
    ap.add_argument("--cifar", help="CIFAR-100 train parquet file")
    ap.add_argument("--background")
    ap.add_argument("--gtsdb-gt")
    ap.add_argument("--synthetic", action="store_true")
    ap.add_argument("--speed-new", type=int, default=2000, help="made-up and repainted pictures per limit the GTSRB lacks (40, 90, 110, 130)")
    ap.add_argument("--speed-known", type=int, default=600, help="made-up and repainted pictures per limit the GTSRB has (so that 'made-up' is no hint)")
    ap.add_argument("--speed-gap", action="store_true",
                    help="experiment: leave the real pictures of the known limits out of the training; the official test then says how "
                         "well made-up pictures alone teach the real signs (never installed)")
    ap.add_argument("--epochs", type=int, default=25)
    ap.add_argument("--out", default=os.path.join(HERE, "out"))
    ap.add_argument("--install", action="store_true", help="copy the result into assets/models/ (never with --synthetic)")
    args = ap.parse_args()
    if (args.synthetic or args.speed_gap) and args.install:
        sys.exit("a synthetic model or a gap experiment is never installed")
    have_signs = args.gtsrb or args.gtsrb_parquet
    have_negatives = args.background or args.cifar
    if not args.synthetic and not (have_signs and have_negatives):
        sys.exit("give --gtsrb or --gtsrb-parquet, and --background or --cifar (or --synthetic for a test of the script)")

    os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
    import tensorflow as tf
    from tensorflow import keras

    rng = np.random.default_rng(7)
    if args.synthetic:
        x, y, tracks = synthetic(rng)
    else:
        x, y, tracks = load_parquet(args.gtsrb_parquet) if args.gtsrb_parquet else load_gtsrb(args.gtsrb)
        # real speed crops with a red ring: the ground for repainted signs (the real crops of the known limits are removed first in the gap
        # experiment, but still serve as ground: only their ring, light and blur are used, never their numbers)
        sp = np.isin(y, list(classes.GTSRB_SPEEDS))
        yy_, xx_ = np.mgrid[0:32, 0:32]
        dist_ = np.hypot(xx_ - 15.5, yy_ - 15.5)
        ring = (dist_ > 9.5) & (dist_ < 12.5)
        red_share = is_sign_red(x[sp])[:, ring].mean(1)
        bases = x[sp][red_share >= 0.35]
        print("repaint grounds:", len(bases), "of", int(sp.sum()))
        if args.speed_gap:
            keep = ~sp
            x, y, tracks = x[keep], y[keep], tracks[keep]
        # speed signs for all twelve limits: real signs with new numbers, plus a share of made-up ones (the CIFAR pictures as grounds);
        # the four limits the GTSRB lacks exist only like this
        bgs = cifar_images(args.cifar, 3000, rng) if args.cifar else None
        new_classes = range(43, 43 + len(classes.EXTRA_SPEEDS))
        total = {v: (args.speed_new if c in new_classes else args.speed_known) for c, v in classes.SPEED_OF_CLASS.items()}
        if args.speed_gap:
            total = {v: args.speed_new for v in total}
        made_up = {v: n // 4 for v, n in total.items()}
        repainted = {v: n - n // 4 for v, n in total.items()}
        rx, rv = speed_synth.make_repainted(bases, sorted(repainted), repainted, rng)
        mx, mv = speed_synth.make(sorted(made_up), made_up, rng, bgs)
        sx, sv = np.concatenate([rx, mx]), np.concatenate([rv, mv])
        class_of_value = {v: c for c, v in classes.SPEED_OF_CLASS.items()}
        sy = np.array([class_of_value[int(v)] for v in sv])
        x = np.concatenate([x, sx])
        y = np.concatenate([y, sy])
        tracks = np.concatenate([tracks, 70000 + sy * 1000 + (np.arange(len(sy)) % 40)])
        want = max(2000, len(x) // 5)  # about one "not a sign" crop for every five sign crops
        parts = []
        if args.background:
            bg = load_background(args.background, args.gtsdb_gt)
            parts.append(bg[rng.integers(0, len(bg), want)])
        if args.cifar:
            parts.append(cifar_negatives(args.cifar, want, rng))
            parts.append(distractors(want // 3, rng))
            parts.append(off_centre(x, y, want // 3, rng))
        bg = np.concatenate(parts)
        # the "not a sign" crops are split into pseudo tracks, so that the validation split keeps its own
        x = np.concatenate([x, bg])
        y = np.concatenate([y, np.full(len(bg), classes.BACKGROUND)])
        tracks = np.concatenate([tracks, 43000 + (np.arange(len(bg)) % 400)])
    print("crops:", len(x), "background:", int((y == classes.BACKGROUND).sum()))

    val = (tracks % 10) == 0  # whole tracks (one physical sign seen many times) stay on one side
    xt, yt, xv, yv = x[~val], y[~val], x[val], y[val]
    xt = xt.astype(np.float32) / 255
    xv = xv.astype(np.float32) / 255
    counts = np.bincount(yt, minlength=N_CLASSES).astype(float)
    weight = {c: float((counts[counts > 0].mean() / counts[c]) ** 0.5) if counts[c] else 1.0 for c in range(N_CLASSES)}
    sw = np.array([weight[int(c)] for c in yt], np.float32)

    aug = augment(keras)
    model = build_model(keras)
    steps = max(1, (len(xt) // 128)) * args.epochs
    model.compile(
        optimizer=keras.optimizers.Adam(keras.optimizers.schedules.CosineDecay(2e-3, steps)),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    ds = tf.data.Dataset.from_tensor_slices((xt, yt, sw)).shuffle(len(xt), seed=3).batch(128)
    ds = ds.map(lambda a, b, c: (aug(a, training=True), b, c)).prefetch(2)
    model.fit(ds, epochs=args.epochs, validation_data=(xv, yv), verbose=2)

    probs = model.predict(xv, verbose=0)
    pred = probs.argmax(1)
    report = {"validationCrops": int(len(xv)), "accuracy": float((pred == yv).mean()), "synthetic": bool(args.synthetic)}
    bgmask = yv == classes.BACKGROUND
    if bgmask.any():
        report["backgroundReadAsSign"] = float((pred[bgmask] != classes.BACKGROUND).mean())
    used = {}
    for c, vz in classes.VZ.items():
        m = yv == c
        if m.any():
            used[vz] = {"name": classes.NAMES[c], "n": int(m.sum()), "recall": float((pred[m] == c).mean())}
    report["usedClasses"] = used
    # what the app does with a reading: only a confident one is taken
    conf = probs.max(1)
    sure = conf >= 0.6
    report["takenAt0.6"] = float(sure.mean())
    report["accuracyOfTakenAt0.6"] = float((pred[sure] == yv[sure]).mean()) if sure.any() else None
    if args.gtsrb_test:
        xs_, ys_, _ = load_parquet(args.gtsrb_test)
        pt = model.predict(xs_.astype(np.float32) / 255, verbose=0)
        pred_t = pt.argmax(1)
        report["officialTest"] = {
            "crops": int(len(ys_)),
            "accuracy": float((pred_t == ys_).mean()),
            "accuracyOfUsedClasses": float((pred_t[np.isin(ys_, list(classes.VZ))] == ys_[np.isin(ys_, list(classes.VZ))]).mean()),
            "readAsNotASign": float((pred_t == classes.BACKGROUND).mean()),
            "takenAt0.6": float((pt.max(1) >= 0.6).mean()),
        }
        # the classes of beta 6 (without the speed limits), to compare with the figure of that model
        old = [c for c in classes.VZ if c not in classes.SPEED_OF_CLASS]
        om = np.isin(ys_, old)
        report["officialTest"]["accuracyOfBeta6Classes"] = float((pred_t[om] == ys_[om]).mean())
        # the real speed signs of the official test (the GTSRB's eight limits): how often the right limit is read
        spd = np.isin(ys_, list(classes.GTSRB_SPEEDS))
        report["officialTestSpeed"] = {
            "crops": int(spd.sum()),
            "recall": float((pred_t[spd] == ys_[spd]).mean()),
            "readAsAnotherSpeed": float(np.isin(pred_t[spd], list(classes.SPEED_OF_CLASS)).mean() - (pred_t[spd] == ys_[spd]).mean()),
            "readAsNotASign": float((pred_t[spd] == classes.BACKGROUND).mean()),
            "perLimit": {str(v): float((pred_t[ys_ == c] == c).mean()) for c, v in classes.GTSRB_SPEEDS.items()},
            "ofThemAs": {str(v): {str(classes.SPEED_OF_CLASS.get(int(k), k)): int(n) for k, n in zip(*np.unique(pred_t[ys_ == c], return_counts=True))}
                         for c, v in classes.GTSRB_SPEEDS.items()},
        }
    print(json.dumps(report, indent=1))

    os.makedirs(args.out, exist_ok=True)
    conv = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite = conv.convert()
    path = os.path.join(args.out, "signs.tflite")
    with open(path, "wb") as f:
        f.write(tflite)
    interp = tf.lite.Interpreter(model_content=tflite)
    interp.allocate_tensors()
    inp, outp = interp.get_input_details()[0], interp.get_output_details()[0]
    assert list(inp["shape"]) == [1, SIZE, SIZE, 3] and outp["shape"][-1] == N_CLASSES
    worst = 0.0
    for i in range(min(20, len(xv))):
        interp.set_tensor(inp["index"], xv[i:i + 1])
        interp.invoke()
        worst = max(worst, float(np.abs(interp.get_tensor(outp["index"]) - probs[i:i + 1]).max()))
    assert worst < 1e-3, "the exported model differs from the trained one by %g" % worst
    report["tfliteBytes"] = len(tflite)
    with open(os.path.join(args.out, "signs_labels.json"), "w") as f:
        json.dump({"size": SIZE, "classes": classes.labels()}, f, indent=1)
    with open(os.path.join(args.out, "report.json"), "w") as f:
        json.dump(report, f, indent=1)
    print("written to", args.out, "(%d bytes)" % len(tflite))
    if args.install:
        dest = os.path.join(APP, "assets", "models")
        shutil.copy(path, os.path.join(dest, "signs.tflite"))
        shutil.copy(os.path.join(args.out, "signs_labels.json"), os.path.join(dest, "signs_labels.json"))
        print("installed into", dest)


if __name__ == "__main__":
    main()
