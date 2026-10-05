import { bearingDegrees, destination, distanceMeters, type LatLng } from '../geo';

/** Track points of a GPX document (`<trkpt lat=".." lon="..">`), in file order. Anything unreadable is skipped. */
export function parseGpx(xml: string): LatLng[] {
  const points: LatLng[] = [];
  const re = /<trkpt\b([^>]*)>/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml)) !== null) {
    const attrs = m[1] ?? '';
    const lat = /\blat\s*=\s*"([^"]+)"/.exec(attrs)?.[1];
    const lng = /\blon\s*=\s*"([^"]+)"/.exec(attrs)?.[1];
    const point = { lat: Number(lat), lng: Number(lng) };
    if (lat !== undefined && lng !== undefined && Number.isFinite(point.lat) && Number.isFinite(point.lng) && Math.abs(point.lat) <= 90 && Math.abs(point.lng) <= 180) {
      points.push(point);
    }
  }
  return points;
}

export type Route = {
  points: readonly LatLng[];
  /** Cumulative distance of each point from the start, metres. */
  cumulative: readonly number[];
  lengthM: number;
};

export function buildRoute(points: readonly LatLng[]): Route {
  const cumulative: number[] = [0];
  for (let i = 1; i < points.length; i++) cumulative.push(cumulative[i - 1]! + distanceMeters(points[i - 1]!, points[i]!));
  return { points, cumulative, lengthM: cumulative[cumulative.length - 1] ?? 0 };
}

/** Position and heading at `distanceM` along the route (clamped to its ends). */
export function pointAt(route: Route, distanceM: number): { lat: number; lng: number; heading: number } {
  const d = Math.min(Math.max(distanceM, 0), route.lengthM);
  let i = 1;
  while (i < route.points.length - 1 && route.cumulative[i]! < d) i++;
  const a = route.points[i - 1]!;
  const b = route.points[i]!;
  const segLen = route.cumulative[i]! - route.cumulative[i - 1]!;
  const heading = bearingDegrees(a, b);
  const into = d - route.cumulative[i - 1]!;
  const p = segLen > 0 ? destination(a, heading, into) : a;
  return { lat: p.lat, lng: p.lng, heading };
}
