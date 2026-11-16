"""Measures the whole chain as the app runs it, on the GTSDB test frames (never used for training): the locator marks the signs in
the padded square, the classifier reads a crop of each (margin 15 %), and a sign counts as right when a box at IoU >= 0.5 was read as
its class. Reports recall of "found", "found and read right", false signs per frame, by sign size. Uses the exported TFLite files, so
what is measured is what the app ships.

  python eval_chain.py --gtsdb-test DIR --detector signs_detector.tflite --classifier signs.tflite --labels signs_labels.json
"""

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import classes  # noqa: E402
import detect_train as dt  # noqa: E402
from train import crop_square  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--gtsdb-test", required=True)
    ap.add_argument("--detector", required=True)
    ap.add_argument("--classifier", required=True)
    ap.add_argument("--labels", required=True)
    ap.add_argument("--threshold", type=float, default=0.3)
    ap.add_argument("--min-prob", type=float, default=0.6)
    ap.add_argument("--out")
    args = ap.parse_args()

    os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
    import tensorflow as tf

    det = tf.lite.Interpreter(model_path=args.detector)
    det.allocate_tensors()
    di, do = det.get_input_details()[0], det.get_output_details()[0]
    size = int(di["shape"][1])
    cls = tf.lite.Interpreter(model_path=args.classifier)
    cls.allocate_tensors()
    ci, co = cls.get_input_details()[0], cls.get_output_details()[0]
    csize = int(ci["shape"][1])
    labels = json.load(open(args.labels))["classes"]
    vz_of_class = {c: v for c, v in classes.VZ.items()}

    boxes = dt.read_gt(os.path.join(args.gtsdb_test, "gt.txt"))
    names = sorted(n for n in os.listdir(args.gtsdb_test) if n.endswith(".ppm"))
    stats = {"frames": 0, "signs": 0, "signsUsed": 0, "found": 0, "foundUsed": 0, "readRight": 0, "readWrong": 0, "readAsNothing": 0,
             "falseBoxes": 0, "falseSigns": 0}
    by_size = {"<16px": [0, 0, 0], "16-32px": [0, 0, 0], ">=32px": [0, 0, 0]}  # signs, found, read right (size in the frame)
    confusions = {}
    for name in names:
        img = Image.open(os.path.join(args.gtsdb_test, name)).convert("RGB")
        inp, scale = dt.letterbox(img, size)
        det.set_tensor(di["index"], inp[None].astype(np.float32) / 255)
        det.invoke()
        out = det.get_tensor(do["index"])[0]
        found = dt.decode(out, threshold=args.threshold, top_k=20)
        gts = []
        for (a, b, c, d, k) in boxes.get(name, []):
            gts.append(((a + c) / 2, (b + d) / 2, c - a, d - b, k))
        stats["frames"] += 1
        stats["signs"] += len(gts)
        used = [False] * len(gts)
        for f in found:
            fx, fy, fw, fh = f[1] / scale, f[2] / scale, f[3] / scale, f[4] / scale
            j, bi = -1, 0.5
            for k, g in enumerate(gts):
                v = dt.iou((1, fx, fy, fw, fh), (1, g[0], g[1], g[2], g[3]))
                if v >= bi and not used[k]:
                    bi, j = v, k
            # the classifier's reading
            side = max(fw, fh) * (1 + 2 * 0.15)
            crop = crop_square(img, fx, fy, side).astype(np.float32) / 255
            cls.set_tensor(ci["index"], crop[None])
            cls.invoke()
            p = cls.get_tensor(co["index"])[0]
            best = int(p.argmax())
            read = None if best >= len(labels) or p[best] < args.min_prob else labels[best]
            if j < 0:
                stats["falseBoxes"] += 1
                if read is not None:
                    stats["falseSigns"] += 1
                continue
            used[j] = True
            g = gts[j]
            stats["found"] += 1
            key = "<16px" if max(g[2], g[3]) < 16 else ("16-32px" if max(g[2], g[3]) < 32 else ">=32px")
            by_size[key][1] += 1
            truth = vz_of_class.get(g[4])
            if truth is None:
                continue  # a class the app does not use: only "found" counts
            stats["foundUsed"] += 1
            if read is None:
                stats["readAsNothing"] += 1
            elif read == truth:
                stats["readRight"] += 1
                by_size[key][2] += 1
            else:
                stats["readWrong"] += 1
                confusions["%s->%s" % (truth, read)] = confusions.get("%s->%s" % (truth, read), 0) + 1
        for k, g in enumerate(gts):
            key = "<16px" if max(g[2], g[3]) < 16 else ("16-32px" if max(g[2], g[3]) < 32 else ">=32px")
            by_size[key][0] += 1
            if vz_of_class.get(g[4]) is not None:
                stats["signsUsed"] += 1
    rep = {
        "inputSize": size,
        "classifierSize": csize,
        "threshold": args.threshold,
        "minProb": args.min_prob,
        "frames": stats["frames"],
        "signs": stats["signs"],
        "foundRecall": stats["found"] / max(1, stats["signs"]),
        "signsOfUsedClasses": stats["signsUsed"],
        "foundAndReadRight": stats["readRight"] / max(1, stats["signsUsed"]),
        "ofFound": {"readRight": stats["readRight"] / max(1, stats["foundUsed"]), "readWrong": stats["readWrong"] / max(1, stats["foundUsed"]),
                    "readAsNothing": stats["readAsNothing"] / max(1, stats["foundUsed"])},
        "falseBoxesPerFrame": stats["falseBoxes"] / max(1, stats["frames"]),
        "falseSignsPerFrame": stats["falseSigns"] / max(1, stats["frames"]),
        "bySize": {k: {"signs": v[0], "foundRecall": v[1] / v[0] if v[0] else None, "readRightOfAll": v[2] / v[0] if v[0] else None} for k, v in by_size.items()},
        "confusions": dict(sorted(confusions.items(), key=lambda kv: -kv[1])[:12]),
    }
    print(json.dumps(rep, indent=1))
    if args.out:
        with open(args.out, "w") as f:
            json.dump(rep, f, indent=1)


if __name__ == "__main__":
    main()
