import { bearingDegrees, distanceMeters } from './geo';
import type { Fix } from './warning-engine';

/** A device position (the browser's or expo-location's shape) as the drive's `Fix`: m/s to km/h, a missing or invalid speed or heading as null. */
export function fixFromPosition(position: { coords: { latitude: number; longitude: number; speed: number | null; heading: number | null }; timestamp: number }): Fix {
  const { latitude, longitude, speed, heading } = position.coords;
  return {
    lat: latitude,
    lng: longitude,
    speedKmh: speed !== null && Number.isFinite(speed) && speed >= 0 ? speed * 3.6 : null,
    heading: heading !== null && Number.isFinite(heading) && heading >= 0 ? heading : null,
    t: position.timestamp,
  };
}

/**
 * Browsers differ in what a position carries: phones usually give speed and heading, many desktop browsers and some
 * phones give neither. Where they are missing, they are worked out from the step to the previous position: speed from
 * distance over time (only for steps of 0.5 to 15 seconds), heading from the direction (only for a step of 3 m or more,
 * so standing still does not turn the arrow; steps within the position's own uncertainty count as standing). Values the
 * browser did give are never replaced.
 */
export function deriveFix(previous: Fix | null, fix: Fix, accuracyM = 0): Fix {
  if (!previous) return fix;
  const seconds = (fix.t - previous.t) / 1000;
  if (seconds < 0.5 || seconds > 15) return fix;
  const meters = distanceMeters(previous, fix);
  // a step smaller than half the position's own uncertainty is noise, not movement (standing still must not read as walking)
  const noise = Math.max(2, accuracyM / 2);
  return {
    ...fix,
    speedKmh: fix.speedKmh ?? (meters < noise ? 0 : (meters / seconds) * 3.6),
    heading: fix.heading ?? (meters >= 3 ? bearingDegrees(previous, fix) : previous.heading),
  };
}
