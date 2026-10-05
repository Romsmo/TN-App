/**
 * The speed-camera namespace of the Trafficnetwork (server/docs/api.md, "Hazard types"). These types only ever surface
 * through the camera path: the user's switch, the country policy and the legal notice decide whether the app shows or
 * offers them.
 */
export const CAMERA_TYPES = ['fixedSpeedCamera', 'mobileSpeedCamera', 'trailerCamera', 'redLightCamera', 'distanceControl'] as const;

/** The one filter key that stands for all camera types (one chip, not five). */
export const CAMERAS_GROUP = 'cameras';

export function isCameraType(type: string): boolean {
  return (CAMERA_TYPES as readonly string[]).includes(type);
}

/** Whether a type is switched off by the filter: by its own key, or - for cameras - by the group key. */
export function isTypeHidden(type: string, hidden: ReadonlySet<string>): boolean {
  return hidden.has(type) || (isCameraType(type) && hidden.has(CAMERAS_GROUP));
}
