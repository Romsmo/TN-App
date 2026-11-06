/// Speed-limit signs (Zeichen 274) are read by the camera as `274-<km/h>` (`274-50`). The display draws the limit itself from a number,
/// so they are not in its sign catalogue and never become a sign in the columns; the app takes their value instead.
library;

const String speedVzPrefix = '274-';

/// The limits a German sign can show and the classifier reads, including the small ones of pedestrian zones, car parks and
/// residential areas (5, 10, 15, 25 km/h). The "walking pace" sign (Zeichen 325.1) and 35/45/55 are not read.
const List<int> readableSpeeds = [5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130];

String speedVzOf(int kmh) => '$speedVzPrefix$kmh';

/// The limit of a `274-<km/h>` number, or null for anything else.
int? speedOfVz(String vz) {
  if (!vz.startsWith(speedVzPrefix)) return null;
  final v = int.tryParse(vz.substring(speedVzPrefix.length));
  return v != null && readableSpeeds.contains(v) ? v : null;
}

bool isSpeedVz(String vz) => speedOfVz(vz) != null;
