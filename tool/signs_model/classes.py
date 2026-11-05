"""The classes of the sign classifier and what each one means for the app.

The first 43 classes are those of the German Traffic Sign Recognition Benchmark (GTSRB), in its numbering. The last class is
"not a sign" (background): without it every red blob the finder proposes would be read as some sign.

`VZ` maps a class to the catalogue number of the display's sign list (docs/contract/sign-rules.json of the display repository). None
means the app does not use the class: speed limits and direction signs are not in the display's catalogue, and the right-hand curve
sign has no entry there (only the left-hand one).
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

VZ = {
    9: "276", 10: "277", 11: "102", 15: "250", 16: "253", 17: "267", 18: "101", 19: "103-10", 21: "105-10",
    22: "112", 23: "114", 24: "121-10", 25: "123", 26: "131", 27: "133-10", 28: "136-10", 29: "138-10",
    30: "101-51", 31: "142-10", 32: "282", 41: "280", 42: "281",
}

assert len(GTSRB_NAMES) == 43

BACKGROUND = 43  # the extra class
SIZE = 32  # crop size the classifier takes


def labels():
    """One entry per class except the background."""
    return [VZ.get(i) for i in range(43)]
