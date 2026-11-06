"""The classes of the sign classifier and what each one means for the app.

The first 43 classes are those of the German Traffic Sign Recognition Benchmark (GTSRB), in its numbering. The GTSRB has eight speed
limits (20, 30, 50, 60, 70, 80, 100, 120); the German limits 40, 90, 110 and 130 are not in it, so four more classes (43-46) are
added for them, trained on made-up pictures (`speed_synth.py`). The last class is "not a sign" (background): without it every red blob
the finder proposes would be read as some sign.

`VZ` maps a class to the catalogue number of the display's sign list (docs/contract/sign-rules.json of the display repository) or, for
a speed limit, to `274-<km/h>` (the display draws the limit itself; the app takes the value). None means the app does not use the
class: direction signs are not in the display's catalogue, and the right-hand curve sign has no entry there (only the left-hand one).
"""

GTSRB_NAMES = [
    "Speed limit 20", "Speed limit 30", "Speed limit 50", "Speed limit 60", "Speed limit 70", "Speed limit 80",
    "End of speed limit 80", "Speed limit 100", "Speed limit 120", "No passing",
    "No passing for vehicles over 3.5 t", "Right of way at next intersection", "Priority road", "Yield", "Stop",
    "No vehicles", "Vehicles over 3.5 t prohibited", "No entry", "General caution", "Dangerous curve left",
    "Dangerous curve right", "Double curve", "Bumpy road", "Slippery road", "Road narrows on the right", "Road work",
    "Traffic signals", "Pedestrians", "Children crossing", "Bicycles crossing", "Beware of ice/snow",
    "Wild animals crossing", "End of all speed and passing limits", "Turn right ahead", "Turn left ahead", "Ahead only",
    "Go straight or right", "Go straight or left", "Keep right", "Keep left", "Roundabout mandatory",
    "End of no passing", "End of no passing for vehicles over 3.5 t",
]

# the speed limits the GTSRB does not have, in the order of their classes 43, 44, ...
EXTRA_SPEEDS = [40, 90, 110, 130]
EXTRA_NAMES = ["Speed limit %d" % v for v in EXTRA_SPEEDS]

# GTSRB class -> speed value
GTSRB_SPEEDS = {0: 20, 1: 30, 2: 50, 3: 60, 4: 70, 5: 80, 7: 100, 8: 120}

NAMES = GTSRB_NAMES + EXTRA_NAMES

VZ = {
    9: "276", 10: "277", 11: "102", 15: "250", 16: "253", 17: "267", 18: "101", 19: "103-10", 21: "105-10",
    22: "112", 23: "114", 24: "121-10", 25: "123", 26: "131", 27: "133-10", 28: "136-10", 29: "138-10",
    30: "101-51", 31: "142-10", 32: "282", 41: "280", 42: "281",
}
for _c, _v in GTSRB_SPEEDS.items():
    VZ[_c] = "274-%d" % _v
for _i, _v in enumerate(EXTRA_SPEEDS):
    VZ[43 + _i] = "274-%d" % _v

assert len(GTSRB_NAMES) == 43

N_SIGN_CLASSES = 43 + len(EXTRA_SPEEDS)
BACKGROUND = N_SIGN_CLASSES  # the extra class, always the last one
N_CLASSES = N_SIGN_CLASSES + 1
SIZE = 32  # crop size the classifier takes

# class -> speed value, for all twelve
SPEED_OF_CLASS = dict(GTSRB_SPEEDS)
SPEED_OF_CLASS.update({43 + i: v for i, v in enumerate(EXTRA_SPEEDS)})


def labels():
    """One entry per class except the background."""
    return [VZ.get(i) for i in range(N_SIGN_CLASSES)]
