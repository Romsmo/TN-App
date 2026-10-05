/** Small geodesy helpers in a local flat projection: exact enough for the few kilometres a warning looks ahead. */
export type LatLng = { lat: number; lng: number };

const R = 6_371_000;
const rad = (d: number) => (d * Math.PI) / 180;
const deg = (r: number) => (r * 180) / Math.PI;

export function distanceMeters(a: LatLng, b: LatLng): number {
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** Initial bearing from a to b in degrees, 0 = north, clockwise, [0, 360). */
export function bearingDegrees(a: LatLng, b: LatLng): number {
  const y = Math.sin(rad(b.lng - a.lng)) * Math.cos(rad(b.lat));
  const x = Math.cos(rad(a.lat)) * Math.sin(rad(b.lat)) - Math.sin(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.cos(rad(b.lng - a.lng));
  return (deg(Math.atan2(y, x)) + 360) % 360;
}

/** Smallest absolute difference between two bearings, [0, 180]. */
export function angleDiff(a: number, b: number): number {
  const d = Math.abs(((a - b) % 360) + 360) % 360;
  return d > 180 ? 360 - d : d;
}

/** Point `meters` away from `from` along `bearing`. */
export function destination(from: LatLng, bearing: number, meters: number): LatLng {
  const d = meters / R;
  const b = rad(bearing);
  const lat1 = rad(from.lat);
  const lng1 = rad(from.lng);
  const lat2 = Math.asin(Math.sin(lat1) * Math.cos(d) + Math.cos(lat1) * Math.sin(d) * Math.cos(b));
  const lng2 = lng1 + Math.atan2(Math.sin(b) * Math.sin(d) * Math.cos(lat1), Math.cos(d) - Math.sin(lat1) * Math.sin(lat2));
  return { lat: deg(lat2), lng: ((deg(lng2) + 540) % 360) - 180 };
}

/** East/north offset in metres of `p` from `origin` (equirectangular, fine for a few km). */
export function toLocal(origin: LatLng, p: LatLng): { x: number; y: number } {
  return { x: rad(p.lng - origin.lng) * R * Math.cos(rad(origin.lat)), y: rad(p.lat - origin.lat) * R };
}

/**
 * Where a point lies relative to a vehicle: `along` metres in front of it (negative = behind) and `cross` metres to the side.
 */
export function alongCross(vehicle: LatLng, heading: number, p: LatLng): { along: number; cross: number } {
  const { x, y } = toLocal(vehicle, p);
  const h = rad(heading);
  const fx = Math.sin(h);
  const fy = Math.cos(h);
  return { along: x * fx + y * fy, cross: Math.abs(x * fy - y * fx) };
}

/** Ray from the vehicle along `heading` against a polygon ring ([lng, lat] corners): metres to the first edge crossed, 0 if inside, null if missed. */
export function rayEntryDistance(vehicle: LatLng, heading: number, ring: readonly (readonly [number, number])[]): number | null {
  if (ring.length < 3) return null;
  const pts = ring.map(([lng, lat]) => toLocal(vehicle, { lat, lng }));
  // inside? (ray casting on the origin)
  let inside = false;
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    const a = pts[i]!;
    const b = pts[j]!;
    if (a.y > 0 !== b.y > 0 && 0 < ((b.x - a.x) * (0 - a.y)) / (b.y - a.y) + a.x) inside = !inside;
  }
  if (inside) return 0;
  const h = rad(heading);
  const dx = Math.sin(h);
  const dy = Math.cos(h);
  let best: number | null = null;
  for (let i = 0; i < pts.length; i++) {
    const a = pts[i]!;
    const b = pts[(i + 1) % pts.length]!;
    const ex = b.x - a.x;
    const ey = b.y - a.y;
    const denom = dx * ey - dy * ex;
    if (Math.abs(denom) < 1e-9) continue;
    const t = (a.x * ey - a.y * ex) / denom; // along the ray
    const u = (a.x * dy - a.y * dx) / denom; // along the edge
    if (t >= 0 && u >= 0 && u <= 1 && (best === null || t < best)) best = t;
  }
  return best;
}
