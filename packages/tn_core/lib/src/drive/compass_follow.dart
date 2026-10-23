/// The eight points of the compass, as an index 0 (north) .. 7 (north-west), for a heading in degrees from north.
int cardinalIndex(double heading) {
  final normalised = ((heading % 360) + 360) % 360;
  return (normalised / 45).round() % 8;
}

const cardinalPoints = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

/// What the "centre on me" button does: nothing, centred once, or follows the position (the map moves with it).
enum FollowMode { off, centered, follow }

/// One tap on the button: off -> centred -> follows -> off.
FollowMode nextFollowMode(FollowMode mode) => switch (mode) {
      FollowMode.off => FollowMode.centered,
      FollowMode.centered => FollowMode.follow,
      FollowMode.follow => FollowMode.off,
    };

/// The user moved the map with a finger: the map no longer follows, whatever it did before.
FollowMode afterUserMove(FollowMode mode) => FollowMode.off;

/// Only a following map moves with each new position.
bool shouldMoveWithPosition(FollowMode mode) => mode == FollowMode.follow;

/// The zoom the map goes to when it centres on the position.
const double centerZoom = 15;
