/** What the "centre on me" button does: nothing, centred once, or follows the position (the map moves with it). */
export type FollowMode = 'off' | 'centered' | 'follow';

/** One tap on the button: off -> centred -> follows -> off. */
export function nextFollowMode(mode: FollowMode): FollowMode {
  return mode === 'off' ? 'centered' : mode === 'centered' ? 'follow' : 'off';
}

/** The user moved the map with a finger: the map no longer follows, whatever it did before. */
export function afterUserMove(_mode: FollowMode): FollowMode {
  return 'off';
}

/** Where the map should go when the position changed: only a following map moves with each new position. */
export function shouldMoveWithPosition(mode: FollowMode): boolean {
  return mode === 'follow';
}

/** The zoom the map goes to when it centres on the position (close enough to see the road, not as close as a manoeuvre). */
export const CENTER_ZOOM = 15;
