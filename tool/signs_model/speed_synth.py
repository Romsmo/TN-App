"""Made-up pictures of German speed-limit signs (Zeichen 274), for the limits the GTSRB does not contain (40, 90, 110, 130 and the small 5, 10, 15, 25) and as a
share of the others, so that "looks made-up" is no hint for the network which limit it is.

A sign is a white disc with a red ring and the number in black, in a DIN-like face (Bahnschrift, which ships with Windows), put on a
background (a CIFAR-100 picture or a plain colour), bent a little, blurred, darkened or lit unevenly and cut like the app's candidate
finder cuts a region: a square with a margin of 15 % around the red ring, with the placement error a real finder box has.

These pictures are only as good as they look like a road. `train.py --speed-gap` measures how well a network that has seen the real
limits only as made-up pictures reads the real ones: that number is the honest guess for the limits that exist only here.
"""

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT_PATHS = [
    "C:/Windows/Fonts/bahnschrift.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf",
    "C:/Windows/Fonts/arialbd.ttf",
]
VARIATIONS = [b"Bold", b"SemiBold", b"Bold SemiCondensed", b"Bold Condensed"]

CANVAS = 192  # the crop is drawn this big and scaled down
MARGIN = 0.15


def _font(size, rng):
    last = None
    for path in FONT_PATHS:
        try:
            f = ImageFont.truetype(path, size)
        except OSError as e:
            last = e
            continue
        try:
            f.set_variation_by_name(VARIATIONS[int(rng.integers(0, len(VARIATIONS)))])
        except (OSError, AttributeError, ValueError):
            pass  # a font without variations: its own weight
        return f
    raise OSError("no font found for the speed signs: %s" % last)


def _background(rng, bgs):
    s = CANVAS
    if bgs is not None and len(bgs) and rng.random() < 0.75:
        pic = Image.fromarray(bgs[int(rng.integers(0, len(bgs)))]).resize((s, s), Image.BILINEAR)
        pic = pic.filter(ImageFilter.GaussianBlur(float(rng.uniform(0, 3))))
        arr = np.asarray(pic).astype(np.float32)
    else:
        base = rng.integers(30, 220, 3).astype(np.float32)
        arr = np.tile(base, (s, s, 1))
        g = np.linspace(0, 1, s)[:, None, None] * rng.uniform(-40, 40)
        arr = arr + g
    return arr


def render(value, rng, bgs=None):
    """One 32 x 32 uint8 picture of the limit [value]."""
    s = CANVAS
    d = s / (1 + 2 * MARGIN) * float(rng.uniform(0.9, 1.1))
    cx = s / 2 + float(rng.uniform(-0.06, 0.06)) * s
    cy = s / 2 + float(rng.uniform(-0.06, 0.06)) * s

    sign = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    dr = ImageDraw.Draw(sign)
    rim = d * 1.03
    dr.ellipse([cx - rim / 2, cy - rim / 2, cx + rim / 2, cy + rim / 2], fill=(235, 235, 235, 255))  # the thin white edge
    red = (int(rng.integers(180, 240)), int(rng.integers(8, 55)), int(rng.integers(8, 55)), 255)
    dr.ellipse([cx - d / 2, cy - d / 2, cx + d / 2, cy + d / 2], fill=red)
    inner = d * (1 - 2 * float(rng.uniform(0.11, 0.16)))
    white = int(rng.integers(205, 256))
    tint = rng.integers(-12, 8, 3)
    face = tuple(int(np.clip(white + t, 0, 255)) for t in tint) + (255,)
    dr.ellipse([cx - inner / 2, cy - inner / 2, cx + inner / 2, cy + inner / 2], fill=face)

    text = str(value)
    black = int(rng.integers(5, 55))
    target_h = inner * float(rng.uniform(0.46, 0.58)) * (0.86 if len(text) == 3 else 1.0)
    size = int(target_h / 0.72)  # a digit is about 0.72 of the font size high
    font = _font(max(8, size), rng)
    box = dr.textbbox((0, 0), text, font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    max_w = inner * 0.86
    if w > max_w:  # too wide: smaller, not squeezed
        font = _font(max(8, int(size * max_w / w)), rng)
        box = dr.textbbox((0, 0), text, font=font)
        w, h = box[2] - box[0], box[3] - box[1]
    tx = cx - w / 2 - box[0] + float(rng.uniform(-0.02, 0.02)) * d
    ty = cy - h / 2 - box[1] + float(rng.uniform(-0.02, 0.02)) * d
    dr.text((tx, ty), text, font=font, fill=(black, black, black, 255))

    # bent, turned a little (the camera is not square to the sign)
    ang = float(rng.uniform(-7, 7))
    sign = sign.rotate(ang, resample=Image.BICUBIC, center=(cx, cy))
    k = float(rng.uniform(-0.12, 0.12))
    sign = sign.transform((s, s), Image.AFFINE, (1, k, -k * cy, float(rng.uniform(-0.05, 0.05)), 1, 0), resample=Image.BICUBIC)

    bg = _background(rng, bgs)
    a = np.asarray(sign).astype(np.float32)
    alpha = a[..., 3:4] / 255
    img = bg * (1 - alpha) + a[..., :3] * alpha

    # uneven light: a shadow or a glare across the sign, a general brightness
    yy, xx = np.mgrid[0:s, 0:s].astype(np.float32) / s
    th = float(rng.uniform(0, 2 * np.pi))
    ramp = (np.cos(th) * (xx - 0.5) + np.sin(th) * (yy - 0.5))[..., None]
    img = img * (1 + ramp * float(rng.uniform(-0.6, 0.6)))
    img = img * float(rng.uniform(0.45, 1.25))
    mean = img.mean()
    img = (img - mean) * float(rng.uniform(0.6, 1.2)) + mean
    img = np.clip(img, 0, 255).astype(np.uint8)

    pic = Image.fromarray(img)
    if rng.random() < 0.25:  # motion blur
        n = int(rng.integers(3, 14))
        a = np.asarray(pic).astype(np.float32)
        acc = np.zeros_like(a)
        for sh in range(n):
            acc += np.roll(a, sh - n // 2, axis=1)
        pic = Image.fromarray(np.clip(acc / n, 0, 255).astype(np.uint8))
    pic = pic.filter(ImageFilter.GaussianBlur(float(rng.uniform(0.0, 3.2))))
    pic = pic.resize((32, 32), [Image.BILINEAR, Image.BOX, Image.LANCZOS][int(rng.integers(0, 3))])
    out = np.asarray(pic).astype(np.float32)
    out = out + rng.normal(0, float(rng.uniform(0, 7)), out.shape)
    return np.clip(out, 0, 255).astype(np.uint8)


def make(values, per_value, rng, bgs=None):
    """[(value, count)] -> (pictures, values)"""
    xs, vs = [], []
    for value in values:
        n = per_value[value] if isinstance(per_value, dict) else per_value
        for _ in range(n):
            xs.append(render(value, rng, bgs))
            vs.append(value)
    return np.stack(xs), np.array(vs)


if __name__ == "__main__":  # a contact sheet to look at
    import sys

    rng = np.random.default_rng(1)
    vals = [5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130]
    rows = []
    for v in vals:
        rows.append(np.concatenate([render(v, rng) for _ in range(10)], axis=1))
    sheet = np.concatenate(rows, axis=0)
    Image.fromarray(sheet).resize((sheet.shape[1] * 3, sheet.shape[0] * 3), Image.NEAREST).save(sys.argv[1] if len(sys.argv) > 1 else "speed_sheet.png")


# ---------------------------------------------------------------------------------------------------------------------------
# Real signs with new digits: the ring, the light, the blur and the noise of a real GTSRB crop of some speed limit stay; only the
# number is wiped out and written again. This closes most of the gap that made-up signs leave (see `--speed-gap`).

_YY, _XX = np.mgrid[0:32, 0:32]
_R = np.hypot(_XX - 15.5, _YY - 15.5)


def repaint(base, value, rng):
    """[base] is a real 32 x 32 crop of a speed sign (margin 15 %); the result shows the same sign with the number [value]."""
    img = base.astype(np.float32)
    disc_r = 32 / (1 + 2 * MARGIN) / 2  # radius of the red ring's outer edge
    ring_w = float(rng.uniform(0.11, 0.16)) * 2 * disc_r
    inner_r = disc_r - ring_w
    inside = _R < inner_r + 0.5
    lum = img.mean(axis=2)
    pix = img[inside]
    order = np.argsort(lum[inside])
    white = np.median(pix[order[-max(4, len(order) // 4):]], axis=0)  # the face of the sign
    ink = np.median(pix[order[:max(3, len(order) // 12)]], axis=0)  # the old digits
    ink = np.minimum(ink, white * float(rng.uniform(0.25, 0.5)))

    # wipe the old number: the disc inside the ring, a little smaller so the ring stays
    wipe_r = inner_r - 0.4
    m = np.clip(wipe_r + 0.6 - _R, 0, 1)[..., None]
    face = np.tile(white, (32, 32, 1)) + rng.normal(0, float(rng.uniform(1, 5)), (32, 32, 3))
    img = img * (1 - m) + face * m

    # the new number, drawn big and scaled down
    big = 256
    k = big / 32
    layer = Image.new("L", (big, big), 0)
    dr = ImageDraw.Draw(layer)
    text = str(value)
    target_h = 2 * inner_r * float(rng.uniform(0.46, 0.58)) * (0.86 if len(text) == 3 else 1.0) * k
    font = _font(max(8, int(target_h / 0.72)), rng)
    box = dr.textbbox((0, 0), text, font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    max_w = 2 * inner_r * 0.86 * k
    if w > max_w:
        font = _font(max(8, int(target_h / 0.72 * max_w / w)), rng)
        box = dr.textbbox((0, 0), text, font=font)
        w, h = box[2] - box[0], box[3] - box[1]
    cx = big / 2 + float(rng.uniform(-0.5, 0.5)) * k
    cy = big / 2 + float(rng.uniform(-0.5, 0.5)) * k
    dr.text((cx - w / 2 - box[0], cy - h / 2 - box[1]), text, font=font, fill=255)
    layer = layer.rotate(float(rng.uniform(-6, 6)), resample=Image.BICUBIC, center=(big / 2, big / 2))
    layer = layer.resize((32, 32), Image.BOX).filter(ImageFilter.GaussianBlur(float(rng.uniform(0.2, 1.0))))
    a = (np.asarray(layer).astype(np.float32) / 255)[..., None]
    img = img * (1 - a) + ink * a
    return np.clip(img, 0, 255).astype(np.uint8)


def make_repainted(bases, values, per_value, rng):
    xs, vs = [], []
    for value in values:
        n = per_value[value] if isinstance(per_value, dict) else per_value
        for _ in range(n):
            xs.append(repaint(bases[int(rng.integers(0, len(bases)))], value, rng))
            vs.append(value)
    return np.stack(xs), np.array(vs)
