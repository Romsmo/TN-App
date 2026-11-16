"""Trains the sign detector: a network that looks at the whole camera frame and marks where traffic signs are (see
docs/camera-signs.md). What a sign is, the classifier of `train.py` then reads from the crop.

The network is a CenterNet-style heatmap detector on a MobileNetV2 backbone (alpha 0.35, ImageNet weights from Keras): the input is an
S x S RGB picture (values 0..1; the app pads the camera frame into a square, longest side S, content at the top left, black below or
right), the output is one tensor [1, S/4, S/4, 5] per cell of a stride-4 grid: (sign score 0..1, width, height, x offset, y offset).
Width and height are in cells (multiply by 4 for input pixels), the offsets are the centre's position inside the cell (0..1). A sign is
a cell whose score is a local maximum above a threshold. One class only ("a traffic sign"): the classifier tells which.

Training data (not in this repository; check the terms yourself):

  --gtsdb DIR      the German Traffic Sign Detection Benchmark, unpacked: 00000.ppm ... 00899.ppm and gt.txt (name;left;top;right;bottom;class).
                   Images 0-599 train, 600-899 are the official test set and are used only for the numbers.
  --gtsrb-parquet  the GTSRB training images (parquet, columns Path.bytes, ClassId, Roi.X1..Y2): real signs that are pasted into the
                   GTSDB frames as extra examples (with a soft edge), together with made-up speed signs from `speed_synth.py`.

`--smoke` makes up a tiny data set and runs everything once on the CPU (a test of the script, never a model for the app).
`--export-size` is the S of the exported model (default 640); training uses random crops of --crop (default 384) pixels, the
network is fully convolutional. `--install` copies signs_detector.tflite into assets/models/.
"""

import argparse
import io
import json
import math
import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
import speed_synth  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.abspath(os.path.join(HERE, "..", ".."))
STRIDE = 4
OUT_CHANNELS = 5


# ---------------------------------------------------------------------------------------------------------------------------
# data

def read_gt(path):
    """name -> [(left, top, right, bottom, class)] of the GTSDB ground truth (right/bottom inclusive in the file; here exclusive)."""
    boxes = {}
    with open(path) as f:
        for line in f:
            p = line.strip().split(";")
            if len(p) >= 6:
                boxes.setdefault(p[0], []).append((int(p[1]), int(p[2]), int(p[3]) + 1, int(p[4]) + 1, int(p[5])))
    return boxes


class Frames:
    """The GTSDB frames of one split, read from disk when needed (900 frames of 1360 x 800 do not fit in memory comfortably)."""

    def __init__(self, root, names, boxes):
        self.root = root
        self.names = names
        self.boxes = boxes

    def __len__(self):
        return len(self.names)

    def load(self, i):
        name = self.names[i]
        img = Image.open(os.path.join(self.root, name)).convert("RGB")
        return img, [b[:4] for b in self.boxes.get(name, [])]


def load_gtsrb_signs(path, limit=None, rng=None):
    """Real signs from the GTSRB parquet file as (RGB array of the sign's box with a thin margin, class), for pasting."""
    import pyarrow.parquet as pq

    pf = pq.ParquetFile(path)
    out = []
    for g in range(pf.num_row_groups):
        t = pf.read_row_group(g).to_pydict()
        for i in range(len(t["ClassId"])):
            img = Image.open(io.BytesIO(t["Path"][i]["bytes"])).convert("RGB")
            x1, y1, x2, y2 = (int(t[k][i]) for k in ("Roi.X1", "Roi.Y1", "Roi.X2", "Roi.Y2"))
            if x2 - x1 < 24 or y2 - y1 < 24:
                continue  # too small to be pasted at any useful size
            m = 2
            crop = img.crop((max(0, x1 - m), max(0, y1 - m), min(img.width, x2 + 1 + m), min(img.height, y2 + 1 + m)))
            out.append((np.asarray(crop), int(t["ClassId"][i])))
    if rng is not None and limit and len(out) > limit:
        pick = rng.choice(len(out), limit, replace=False)
        out = [out[i] for i in pick]
    return out


# circle, triangle, diamond, octagon, inverted triangle: the soft mask a pasted sign gets (GTSRB class -> shape)
_TRIANGLE = {11, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31}
_SHAPES = {13: "down", 12: "diamond", 14: "octagon"}


def shape_mask(cls, w, h, feather):
    """Alpha mask (float 0..1) of a sign's shape in a w x h box, feathered."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    nx = (xx + 0.5) / w * 2 - 1
    ny = (yy + 0.5) / h * 2 - 1
    kind = "triangle" if cls in _TRIANGLE else _SHAPES.get(cls, "circle")
    if kind == "circle" or kind == "octagon":
        d = 1 - np.sqrt(nx ** 2 + ny ** 2)
    elif kind == "diamond":
        d = 1 - (np.abs(nx) + np.abs(ny))
    elif kind == "triangle":  # apex up, base down
        d = np.minimum(1 - ny * 0 - (ny < -1) * 0 + 0, 1)  # placeholder, replaced below
        d = np.minimum.reduce([(ny + 1) / 2 * 1.15 + 0.0 - np.abs(nx) * 1.0 + 0.1, 1 - ny])
    else:  # inverted triangle
        d = np.minimum.reduce([(1 - ny) / 2 * 1.15 - np.abs(nx) * 1.0 + 0.1, ny + 1])
    f = max(feather, 1e-3) / (min(w, h) / 2)
    return np.clip(d / f + 0.5, 0, 1)


def paste(frame, sign, cls, box, rng):
    """Pastes [sign] (RGB array) into [frame] (float RGB array, in place) at [box] = (x, y, w, h), soft edge, light matched."""
    x, y, w, h = box
    H, W = frame.shape[:2]
    if w < 6 or h < 6 or x < 0 or y < 0 or x + w > W or y + h > H:
        return False
    pic = Image.fromarray(sign).resize((w, h), Image.LANCZOS if w < sign.shape[1] else Image.BICUBIC)
    if rng.random() < 0.3:
        pic = pic.filter(ImageFilter.GaussianBlur(float(rng.uniform(0.3, 1.5))))
    a = np.asarray(pic).astype(np.float32)
    # match the light of the spot: scale the sign's brightness towards the frame's
    spot = frame[y:y + h, x:x + w]
    k = float(np.clip((spot.mean() + 40) / (a.mean() + 40), 0.5, 1.6)) * float(rng.uniform(0.8, 1.2))
    a = np.clip(a * k, 0, 255)
    alpha = shape_mask(cls, w, h, feather=max(1.0, min(w, h) * 0.08))[..., None]
    frame[y:y + h, x:x + w] = spot * (1 - alpha) + a * alpha
    return True


def overlaps(box, boxes, pad=4):
    x, y, w, h = box
    for (a, b, c, d) in boxes:
        if x < c + pad and x + w > a - pad and y < d + pad and y + h > b - pad:
            return True
    return False


class Composer:
    """Makes training pictures: a GTSDB frame, scaled at random, with real GTSRB signs and made-up speed signs pasted in, cropped to
    crop x crop, with its boxes."""

    def __init__(self, frames, signs, crop, rng, paste_prob=0.7, max_paste=4):
        self.frames = frames
        self.signs = signs
        self.crop = crop
        self.rng = rng
        self.paste_prob = paste_prob
        self.max_paste = max_paste

    def one(self):
        rng = self.rng
        img, boxes = self.frames.load(int(rng.integers(0, len(self.frames))))
        W, H = img.size
        scale = float(rng.uniform(0.3, 0.95))
        sw, sh = max(self.crop, int(W * scale)), max(self.crop, int(H * scale))
        scale_x, scale_y = sw / W, sh / H
        img = img.resize((sw, sh), Image.BILINEAR)
        frame = np.asarray(img).astype(np.float32)
        boxes = [(int(a * scale_x), int(b * scale_y), int(c * scale_x), int(d * scale_y)) for (a, b, c, d) in boxes]
        boxes = [b for b in boxes if b[2] - b[0] >= 6 and b[3] - b[1] >= 6]
        # pasted signs: real ones from the GTSRB, made-up speed limits
        if self.signs and rng.random() < self.paste_prob:
            for _ in range(int(rng.integers(1, self.max_paste + 1))):
                side = int(rng.choice([rng.integers(8, 24), rng.integers(16, 60), rng.integers(40, 140)]))
                x = int(rng.integers(0, max(1, sw - side)))
                y = int(rng.integers(0, max(1, int(sh * 0.75) - side)))
                if overlaps((x, y, side, side), boxes):
                    continue
                if rng.random() < 0.3:
                    value = int(rng.choice([5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130]))
                    pic, cx, cy, d = speed_synth.sign_rgba(value, rng)
                    r = int(d / 2 * 1.08)
                    cut = pic.crop((int(cx - r), int(cy - r), int(cx + r), int(cy + r)))
                    rgba = np.asarray(cut).astype(np.float32)
                    bgc = frame[y:y + side, x:x + side].mean((0, 1))
                    rgb = (rgba[..., :3] * (rgba[..., 3:4] / 255) + bgc * (1 - rgba[..., 3:4] / 255)).astype(np.uint8)
                    cls = 0
                else:
                    rgb, cls = self.signs[int(rng.integers(0, len(self.signs)))]
                h = int(side * rgb.shape[0] / rgb.shape[1])
                if paste(frame, rgb, cls, (x, y, side, max(6, h)), rng):
                    boxes.append((x, y, x + side, y + max(6, h)))
        # the crop: around a sign most of the time
        c = self.crop
        if boxes and rng.random() < 0.75:
            a, b, cc, d = boxes[int(rng.integers(0, len(boxes)))]
            cx0 = int(np.clip((a + cc) / 2 - rng.uniform(0.15, 0.85) * c, 0, sw - c))
            cy0 = int(np.clip((b + d) / 2 - rng.uniform(0.15, 0.85) * c, 0, sh - c))
        else:
            cx0 = int(rng.integers(0, sw - c + 1))
            cy0 = int(rng.integers(0, sh - c + 1))
        crop = frame[cy0:cy0 + c, cx0:cx0 + c].copy()
        out_boxes = []
        for (a, b, cc, d) in boxes:
            a2, b2, c2, d2 = max(a - cx0, 0), max(b - cy0, 0), min(cc - cx0, c), min(d - cy0, c)
            if c2 - a2 >= 5 and d2 - b2 >= 5 and (c2 - a2) * (d2 - b2) >= 0.5 * (cc - a) * (d - b):
                out_boxes.append((a2, b2, c2, d2))
        crop = self.augment(crop)
        if rng.random() < 0.5:
            crop = crop[:, ::-1]
            out_boxes = [(c - c2, b2, c - a2, d2) for (a2, b2, c2, d2) in out_boxes]
        if rng.random() < 0.25:  # the black band of the app's padded square
            if rng.random() < 0.5:
                k = int(rng.integers(c // 4, c // 2))
                crop[-k:] = 0
                out_boxes = [bx for bx in out_boxes if bx[3] <= c - k]
            else:
                k = int(rng.integers(c // 4, c // 2))
                crop[:, -k:] = 0
                out_boxes = [bx for bx in out_boxes if bx[2] <= c - k]
        return np.clip(crop, 0, 255).astype(np.uint8), out_boxes

    def augment(self, crop):
        rng = self.rng
        crop = crop * float(rng.uniform(0.35, 1.3))  # brightness (dusk to glare)
        mean = crop.mean()
        crop = (crop - mean) * float(rng.uniform(0.7, 1.3)) + mean  # contrast
        grey = crop.mean(2, keepdims=True)
        crop = grey + (crop - grey) * float(rng.uniform(0.6, 1.3))  # saturation
        crop = crop + rng.normal(0, 4, 3)[None, None, :]  # colour cast
        if rng.random() < 0.3:
            pic = Image.fromarray(np.clip(crop, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(float(rng.uniform(0.3, 1.6))))
            crop = np.asarray(pic).astype(np.float32)
        if rng.random() < 0.2:  # motion blur
            n = int(rng.integers(3, 9))
            acc = np.zeros_like(crop)
            for sh in range(n):
                acc += np.roll(crop, sh - n // 2, axis=1)
            crop = acc / n
        crop = crop + rng.normal(0, float(rng.uniform(0, 8)), crop.shape)
        return crop


def gaussian_radius(h, w, min_overlap=0.7):
    """CenterNet's radius of the heatmap peak for a box of h x w cells."""
    a1 = 1
    b1 = h + w
    c1 = w * h * (1 - min_overlap) / (1 + min_overlap)
    r1 = (b1 + math.sqrt(b1 ** 2 - 4 * a1 * c1)) / 2
    a2 = 4
    b2 = 2 * (h + w)
    c2 = (1 - min_overlap) * w * h
    r2 = (b2 + math.sqrt(b2 ** 2 - 4 * a2 * c2)) / 2
    a3 = 4 * min_overlap
    b3 = -2 * min_overlap * (h + w)
    c3 = (min_overlap - 1) * w * h
    r3 = (b3 + math.sqrt(b3 ** 2 - 4 * a3 * c3)) / 2
    return max(0, min(r1, r2, r3))


def targets(boxes, size):
    """The training target of one picture: [size/4, size/4, 6] = heat, w, h, dx, dy, mask(1 at the centre cell)."""
    g = size // STRIDE
    t = np.zeros((g, g, 6), np.float32)
    for (a, b, c, d) in boxes:
        w, h = (c - a) / STRIDE, (d - b) / STRIDE
        cx, cy = (a + c) / 2 / STRIDE, (b + d) / 2 / STRIDE
        ix, iy = min(int(cx), g - 1), min(int(cy), g - 1)
        r = max(0, int(gaussian_radius(h, w)))
        sigma = (2 * r + 1) / 6
        y0, y1 = max(0, iy - r), min(g, iy + r + 1)
        x0, x1 = max(0, ix - r), min(g, ix + r + 1)
        yy, xx = np.mgrid[y0:y1, x0:x1]
        gauss = np.exp(-((xx - ix) ** 2 + (yy - iy) ** 2) / (2 * sigma ** 2))
        t[y0:y1, x0:x1, 0] = np.maximum(t[y0:y1, x0:x1, 0], gauss)
        t[iy, ix, 1] = w
        t[iy, ix, 2] = h
        t[iy, ix, 3] = cx - ix
        t[iy, ix, 4] = cy - iy
        t[iy, ix, 5] = 1
    return t


# ---------------------------------------------------------------------------------------------------------------------------
# model

def build_model(keras, input_size=None, alpha=0.35, weights="imagenet"):
    import tensorflow as tf

    L = keras.layers

    class Up2(L.Layer):
        """Nearest-neighbour upsampling by 2 that exports as one RESIZE_NEAREST_NEIGHBOR op with a fixed size (Keras' own
        UpSampling2D becomes a chain of SHAPE / TILE / RESHAPE ops with dynamic shapes, which old TFLite runtimes handle badly)."""

        def call(self, x):
            h, w = x.shape[1], x.shape[2]
            if h is None or w is None:
                s = tf.shape(x)
                return tf.image.resize(x, (s[1] * 2, s[2] * 2), method="nearest")
            return tf.image.resize(x, (h * 2, w * 2), method="nearest")

        def compute_output_shape(self, s):
            return (s[0], None if s[1] is None else s[1] * 2, None if s[2] is None else s[2] * 2, s[3])

    shape = (input_size, input_size, 3)
    inp = keras.Input(shape)
    x = L.Rescaling(2.0, offset=-1.0)(inp)  # 0..1 -> -1..1, as MobileNetV2 was trained
    base = keras.applications.MobileNetV2(input_shape=(None, None, 3), alpha=alpha, include_top=False, weights=weights)
    feats = keras.Model(base.input, [base.get_layer(n).output for n in ("block_3_expand_relu", "block_6_expand_relu", "block_13_expand_relu", "out_relu")])
    s4, s8, s16, s32 = feats(x)

    def lateral(t, n, name):
        t = L.Conv2D(n, 1, padding="same", use_bias=False, name=name + "_conv")(t)
        t = L.BatchNormalization(name=name + "_bn")(t)
        return L.ReLU(name=name + "_relu")(t)

    def smooth(t, n, name):
        t = L.DepthwiseConv2D(3, padding="same", use_bias=False, name=name + "_dw")(t)
        t = L.BatchNormalization(name=name + "_dwbn")(t)
        t = L.ReLU(name=name + "_dwrelu")(t)
        t = L.Conv2D(n, 1, padding="same", use_bias=False, name=name + "_pw")(t)
        t = L.BatchNormalization(name=name + "_pwbn")(t)
        return L.ReLU(name=name + "_pwrelu")(t)

    n = 48
    p32 = lateral(s32, n, "p32")
    p16 = L.Add()([Up2(name="up32")(p32), lateral(s16, n, "p16")])
    p16 = smooth(p16, n, "s16")
    p8 = L.Add()([Up2(name="up16")(p16), lateral(s8, n, "p8")])
    p8 = smooth(p8, n, "s8")
    p4 = L.Add()([Up2(name="up8")(p8), lateral(s4, n, "p4")])
    p4 = smooth(p4, n, "s4")
    head = L.Conv2D(48, 3, padding="same", use_bias=False, name="head_conv")(p4)
    head = L.BatchNormalization(name="head_bn")(head)
    head = L.ReLU(name="head_relu")(head)
    heat = L.Conv2D(1, 1, activation="sigmoid", name="heat", bias_initializer=keras.initializers.Constant(-2.19))(head)
    size = L.Conv2D(2, 1, activation="relu", name="size")(head)
    off = L.Conv2D(2, 1, activation="sigmoid", name="offset")(head)
    out = L.Concatenate(name="out")([heat, size, off])
    return keras.Model(inp, out, name="sign_detector")


def make_loss(ops):
    def loss(y_true, y_pred):
        heat_t = y_true[..., 0:1]
        wh_t = y_true[..., 1:3]
        off_t = y_true[..., 3:5]
        mask = y_true[..., 5:6]
        heat = ops.clip(y_pred[..., 0:1], 1e-4, 1 - 1e-4)
        wh = y_pred[..., 1:3]
        off = y_pred[..., 3:5]
        pos = ops.cast(heat_t >= 0.999, "float32")
        n = ops.maximum(ops.sum(pos), 1.0)
        pos_loss = -ops.sum(ops.log(heat) * (1 - heat) ** 2 * pos)
        neg_loss = -ops.sum(ops.log(1 - heat) * heat ** 2 * (1 - heat_t) ** 4 * (1 - pos))
        focal = (pos_loss + neg_loss) / n
        size_l1 = ops.sum(ops.abs(wh - wh_t) * mask) / n
        off_l1 = ops.sum(ops.abs(off - off_t) * mask) / n
        return focal + 0.1 * size_l1 + off_l1

    return loss


# ---------------------------------------------------------------------------------------------------------------------------
# decoding and evaluation (the same rules the app uses)

def decode(out, threshold=0.3, top_k=20):
    """[g, g, 5] -> [(score, cx, cy, w, h)] in input pixels: local maxima of the score above the threshold."""
    heat = out[..., 0]
    g = heat.shape[0]
    padded = np.pad(heat, 1, constant_values=-1)
    local = np.ones_like(heat, dtype=bool)
    for dy in range(3):
        for dx in range(3):
            if dy == 1 and dx == 1:
                continue
            local &= heat >= padded[dy:dy + g, dx:dx + g]
    ys, xs = np.nonzero(local & (heat >= threshold))
    found = []
    for y, x in zip(ys, xs):
        s = float(heat[y, x])
        w, h = float(out[y, x, 1]) * STRIDE, float(out[y, x, 2]) * STRIDE
        cx, cy = (x + float(out[y, x, 3])) * STRIDE, (y + float(out[y, x, 4])) * STRIDE
        found.append((s, cx, cy, w, h))
    found.sort(reverse=True)
    return nms(found[:top_k])


def iou(a, b):
    ax0, ay0, ax1, ay1 = a[1] - a[3] / 2, a[2] - a[4] / 2, a[1] + a[3] / 2, a[2] + a[4] / 2
    bx0, by0, bx1, by1 = b[1] - b[3] / 2, b[2] - b[4] / 2, b[1] + b[3] / 2, b[2] + b[4] / 2
    iw, ih = max(0, min(ax1, bx1) - max(ax0, bx0)), max(0, min(ay1, by1) - max(ay0, by0))
    inter = iw * ih
    return inter / max(1e-6, a[3] * a[4] + b[3] * b[4] - inter)


def nms(found, thr=0.5):
    keep = []
    for f in found:
        if all(iou(f, k) < thr for k in keep):
            keep.append(f)
    return keep


def letterbox(img, size):
    """The app's padded square: the picture scaled so that its longer side is [size], at the top left, black elsewhere."""
    W, H = img.size
    scale = size / max(W, H)
    sw, sh = max(1, round(W * scale)), max(1, round(H * scale))
    out = np.zeros((size, size, 3), np.uint8)
    out[:sh, :sw] = np.asarray(img.resize((sw, sh), Image.BILINEAR))
    return out, scale


def evaluate(predict, frames, size, thresholds=(0.2, 0.3, 0.4, 0.5)):
    """Recall and precision over a split at a few thresholds (a detection counts at IoU >= 0.5), plus recall by sign size."""
    all_dets = []  # (score, matched)
    n_gt = 0
    by_size = {"<12px": [0, 0], "12-24px": [0, 0], ">=24px": [0, 0]}
    best = {t: [0, 0] for t in thresholds}  # tp, fp at threshold
    for i in range(len(frames)):
        img, boxes = frames.load(i)
        inp, scale = letterbox(img, size)
        out = predict(inp)
        dets = decode(out, threshold=min(thresholds), top_k=50)
        gts = [(1.0, (a + c) / 2 * scale, (b + d) / 2 * scale, (c - a) * scale, (d - b) * scale) for (a, b, c, d) in boxes]
        n_gt += len(gts)
        used = [False] * len(gts)
        for d in dets:
            j = -1
            bi = 0.5
            for k, gt in enumerate(gts):
                v = iou(d, gt)
                if v >= bi and not used[k]:
                    bi, j = v, k
            if j >= 0:
                used[j] = True
            all_dets.append((d[0], j >= 0, j))
            for t in thresholds:
                if d[0] >= t:
                    best[t][0 if j >= 0 else 1] += 1
        for k, gt in enumerate(gts):
            key = "<12px" if max(gt[3], gt[4]) < 12 else ("12-24px" if max(gt[3], gt[4]) < 24 else ">=24px")
            by_size[key][1] += 1
            if used[k]:
                by_size[key][0] += 1
    # average precision (VOC style, all points)
    all_dets.sort(key=lambda d: -d[0])
    tp = np.cumsum([1 if d[1] else 0 for d in all_dets])
    fp = np.cumsum([0 if d[1] else 1 for d in all_dets])
    rec = tp / max(1, n_gt)
    prec = tp / np.maximum(1, tp + fp)
    ap = 0.0
    for r in np.linspace(0, 1, 101):
        p = prec[rec >= r].max() if (rec >= r).any() else 0
        ap += p / 101
    rep = {"signs": int(n_gt), "ap50": float(ap), "atThreshold": {}, "recallBySize": {}}
    for t in thresholds:
        tp_, fp_ = best[t]
        rep["atThreshold"][str(t)] = {"recall": tp_ / max(1, n_gt), "precision": tp_ / max(1, tp_ + fp_), "falsePerFrame": fp_ / max(1, len(frames))}
    for k, (hit, tot) in by_size.items():
        rep["recallBySize"][k] = {"signs": tot, "recall": hit / tot if tot else None}
    return rep


# ---------------------------------------------------------------------------------------------------------------------------

def smoke_frames(rng, n, root):
    """Made-up frames: grey with a few red rings and triangles, written as PPM into [root], with a gt.txt."""
    os.makedirs(root, exist_ok=True)
    names = []
    with open(os.path.join(root, "gt.txt"), "w") as gt:
        for i in range(n):
            W, H = 680, 400
            img = np.full((H, W, 3), 110, np.uint8) + rng.integers(0, 40, (H, W, 3), dtype=np.uint8)
            name = "%05d.ppm" % i
            for _ in range(int(rng.integers(1, 4))):
                s = int(rng.integers(14, 80))
                x, y = int(rng.integers(0, W - s)), int(rng.integers(0, H // 2))
                yy, xx = np.mgrid[0:s, 0:s]
                d = np.hypot(xx - s / 2, yy - s / 2)
                ring = (d < s / 2) & (d > s / 2 - max(2, s / 8))
                inner = d <= s / 2 - max(2, s / 8)
                patch = img[y:y + s, x:x + s]
                patch[ring] = (200, 30, 30)
                patch[inner] = 235
                gt.write("%s;%d;%d;%d;%d;%d\n" % (name, x, y, x + s - 1, y + s - 1, 1))
            Image.fromarray(img).save(os.path.join(root, name))
            names.append(name)
    return names


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--gtsdb")
    ap.add_argument("--gtsrb-parquet")
    ap.add_argument("--smoke", action="store_true")
    ap.add_argument("--crop", type=int, default=384)
    ap.add_argument("--export-size", type=int, default=640)
    ap.add_argument("--epochs", type=int, default=60)
    ap.add_argument("--per-epoch", type=int, default=1600, help="training pictures made per epoch")
    ap.add_argument("--batch", type=int, default=16)
    ap.add_argument("--alpha", type=float, default=0.35)
    ap.add_argument("--out", default=os.path.join(HERE, "out-detector"))
    ap.add_argument("--install", action="store_true")
    ap.add_argument("--resume", action="store_true", help="go on from the last epoch's checkpoint in --out")
    args = ap.parse_args()
    if args.smoke and args.install:
        sys.exit("a smoke-test model is never installed")
    if not args.smoke and not args.gtsdb:
        sys.exit("give --gtsdb DIR (or --smoke)")

    os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
    import tensorflow as tf
    from tensorflow import keras
    from keras import ops

    rng = np.random.default_rng(11)
    if args.smoke:
        root = os.path.join(args.out, "smoke-data")
        names = smoke_frames(rng, 24, root)
        boxes = read_gt(os.path.join(root, "gt.txt"))
        train = Frames(root, names[:18], boxes)
        test = Frames(root, names[18:], boxes)
        signs = []
        args.epochs, args.per_epoch, args.crop, args.export_size = 2, 32, 256, 320
        weights = None
    else:
        boxes = read_gt(os.path.join(args.gtsdb, "gt.txt"))
        names = sorted(n for n in os.listdir(args.gtsdb) if n.endswith(".ppm"))
        train = Frames(args.gtsdb, [n for n in names if int(n[:5]) < 600], boxes)
        test = Frames(args.gtsdb, [n for n in names if int(n[:5]) >= 600], boxes)
        signs = load_gtsrb_signs(args.gtsrb_parquet, limit=6000, rng=rng) if args.gtsrb_parquet else []
        weights = "imagenet"
    print("frames: train %d, test %d; pasted signs: %d" % (len(train), len(test), len(signs)))

    composer = Composer(train, signs, args.crop, rng)

    class Batches(keras.utils.PyDataset):
        def __init__(self, n, batch, **kw):
            super().__init__(**kw)
            self.n, self.batch = n, batch

        def __len__(self):
            return max(1, self.n // self.batch)

        def __getitem__(self, idx):
            xs, ys = [], []
            for _ in range(self.batch):
                img, bx = composer.one()
                xs.append(img.astype(np.float32) / 255)
                ys.append(targets(bx, args.crop))
            return np.stack(xs), np.stack(ys)

    model = build_model(keras, None, alpha=args.alpha, weights=weights)
    model.summary(line_length=100, print_fn=lambda s: None)
    print("parameters:", model.count_params())
    per_epoch = len(Batches(args.per_epoch, args.batch))
    steps = per_epoch * args.epochs

    # after every epoch the weights go to disk, so that a frozen machine (WSL froze once at epoch 46 of 50) costs one epoch, not all
    os.makedirs(args.out, exist_ok=True)
    ckpt = os.path.join(args.out, "checkpoint.weights.h5")
    ckpt_meta = os.path.join(args.out, "checkpoint.json")
    initial_epoch = 0
    if args.resume and os.path.exists(ckpt) and os.path.exists(ckpt_meta):
        model.load_weights(ckpt)
        initial_epoch = json.load(open(ckpt_meta))["epoch"]
        print("resumed after epoch", initial_epoch)

    class Shifted(keras.optimizers.schedules.LearningRateSchedule):
        """The cosine schedule continued where the checkpoint left it (the optimizer's step count starts at 0 again)."""

        def __init__(self, inner, offset):
            self.inner, self.offset = inner, offset

        def __call__(self, step):
            return self.inner(step + self.offset)

        def get_config(self):
            return {"offset": self.offset}

    schedule = Shifted(keras.optimizers.schedules.CosineDecay(1e-3, steps, warmup_target=None), initial_epoch * per_epoch)
    model.compile(optimizer=keras.optimizers.Adam(schedule), loss=make_loss(ops), jit_compile=False)  # XLA has no gradient for the nearest resize

    def note_epoch(epoch, logs):
        with open(ckpt_meta, "w") as f:
            json.dump({"epoch": epoch + 1, "loss": float(logs.get("loss", 0))}, f)

    callbacks = [
        keras.callbacks.ModelCheckpoint(ckpt, save_weights_only=True, save_freq="epoch"),
        keras.callbacks.LambdaCallback(on_epoch_end=note_epoch),
    ]
    model.fit(Batches(args.per_epoch, args.batch, workers=2, use_multiprocessing=False), epochs=args.epochs, initial_epoch=initial_epoch,
              callbacks=callbacks, verbose=2)

    model.save_weights(os.path.join(args.out, "detector.weights.h5"))

    # the fixed-size model for the app
    fixed = build_model(keras, args.export_size, alpha=args.alpha, weights=None)
    fixed.set_weights(model.get_weights())

    def predict(inp):
        return fixed.predict(inp[None].astype(np.float32) / 255, verbose=0)[0]

    report = {"exportSize": args.export_size, "alpha": args.alpha, "epochs": args.epochs, "smoke": args.smoke}
    report["test"] = evaluate(predict, test, args.export_size)
    print(json.dumps(report, indent=1))

    conv = tf.lite.TFLiteConverter.from_keras_model(fixed)
    tflite = conv.convert()
    path = os.path.join(args.out, "signs_detector.tflite")
    with open(path, "wb") as f:
        f.write(tflite)
    interp = tf.lite.Interpreter(model_content=tflite)
    interp.allocate_tensors()
    i_, o_ = interp.get_input_details()[0], interp.get_output_details()[0]
    assert list(i_["shape"]) == [1, args.export_size, args.export_size, 3], i_["shape"]
    assert list(o_["shape"]) == [1, args.export_size // STRIDE, args.export_size // STRIDE, OUT_CHANNELS], o_["shape"]
    img, _ = test.load(0)
    inp, _ = letterbox(img, args.export_size)
    interp.set_tensor(i_["index"], inp[None].astype(np.float32) / 255)
    interp.invoke()
    lite, ref = interp.get_tensor(o_["index"])[0], predict(inp)
    diff = float(np.abs(lite[..., 0] - ref[..., 0]).max())  # the score, 0..1
    assert diff < 5e-3, "the exported model's scores differ from the trained one's by %g" % diff
    rel = float((np.abs(lite[..., 1:] - ref[..., 1:]) / (np.abs(ref[..., 1:]) + 1)).max())  # sizes in cells, offsets
    assert rel < 1e-2, "the exported model's boxes differ from the trained one's by %g" % rel
    report["exportDiff"] = {"score": diff, "boxRelative": rel}
    report["tfliteBytes"] = len(tflite)
    with open(os.path.join(args.out, "signs_detector.json"), "w") as f:
        json.dump({"inputSize": args.export_size, "stride": STRIDE, "channels": ["score", "width", "height", "dx", "dy"]}, f, indent=1)
    with open(os.path.join(args.out, "report.json"), "w") as f:
        json.dump(report, f, indent=1)
    print("written to", args.out, "(%d bytes)" % len(tflite))
    if args.install:
        dest = os.path.join(APP, "assets", "models")
        shutil.copy(path, os.path.join(dest, "signs_detector.tflite"))
        shutil.copy(os.path.join(args.out, "signs_detector.json"), os.path.join(dest, "signs_detector.json"))
        print("installed into", dest)


if __name__ == "__main__":
    main()
