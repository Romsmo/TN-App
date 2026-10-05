import type { NearbyItem, SpeedLimitAnswer } from '@/tn/types';

import type { DriveDataSource } from '../data-source';
import { destination, distanceMeters } from '../geo';
import { pointAt, type Route } from './gpx';

/** Speed limits along the demo route: [from metres, limit km/h]. */
export const SIM_LIMITS: readonly (readonly [number, number])[] = [
  [0, 50],
  [1500, 100],
  [4500, 70],
];

export function simLimitAt(distanceM: number): number {
  let limit = SIM_LIMITS[0]![1];
  for (const [from, value] of SIM_LIMITS) if (distanceM >= from) limit = value;
  return limit;
}

/** The speed of the simulated car: just under the limit, with one stretch a little over it to show the colour change. */
export function simSpeedAt(distanceM: number): number {
  const limit = simLimitAt(distanceM);
  if (distanceM >= 2600 && distanceM < 3200) return limit + 12;
  return limit - 3;
}

type SimHazard = { id: string; hazardType: string; atM: number };
const SIM_HAZARDS: readonly SimHazard[] = [
  { id: 'sim-accident', hazardType: 'accident', atM: 2300 },
  { id: 'sim-construction', hazardType: 'construction', atM: 3900 },
  { id: 'sim-ice', hazardType: 'ice', atM: 5600 },
];
/** A camera zone across the route, only offered when the user switched cameras on (default: off, like in the real app). */
const SIM_ZONE = { id: 'sim-zone', fromM: 4800, toM: 5200, halfWidthM: 250 } as const;

/** Synthetic, clearly marked data for the simulated drive. The route and everything on it are invented. */
export function createSimDataSource(route: Route, options: { camerasEnabled: boolean }): DriveDataSource {
  const items: NearbyItem[] = SIM_HAZARDS.map((h) => {
    const p = pointAt(route, h.atM);
    return {
      kind: 'hazard' as const,
      id: h.id,
      hazardType: h.hazardType,
      lat: p.lat,
      lng: p.lng,
      distanceMeters: 0,
      expiresAt: new Date(Date.now() + 3_600_000).toISOString(),
      confirmCount: 3,
      denyCount: 0,
      pending: false,
    };
  });
  if (options.camerasEnabled) {
    const a = pointAt(route, SIM_ZONE.fromM);
    const b = pointAt(route, SIM_ZONE.toM);
    const corner = (p: { lat: number; lng: number; heading: number }, side: number): [number, number] => {
      const q = destination(p, (p.heading + (side > 0 ? 90 : 270)) % 360, SIM_ZONE.halfWidthM);
      return [q.lng, q.lat];
    };
    items.push({ kind: 'cameraZone', id: SIM_ZONE.id, cell: 'sim', resolution: 7, cameraTypes: ['mobileSpeedCamera'], distanceMeters: 0, outline: [corner(a, -1), corner(a, 1), corner(b, 1), corner(b, -1)] });
  }

  const distanceAlong = (lat: number, lng: number): number => {
    let best = 0;
    let bestD = Infinity;
    for (let i = 0; i < route.points.length; i++) {
      const d = distanceMeters({ lat, lng }, route.points[i]!);
      if (d < bestD) {
        bestD = d;
        best = route.cumulative[i]!;
      }
    }
    return best;
  };

  return {
    nearby: async (lat, lng, radiusM) =>
      items
        .map((item) => (item.kind === 'hazard' ? { ...item, distanceMeters: distanceMeters({ lat, lng }, item) } : item))
        .filter((item) => item.kind === 'cameraZone' || item.distanceMeters <= radiusM),
    speedLimit: async (lat, lng): Promise<SpeedLimitAnswer> => ({
      value: simLimitAt(distanceAlong(lat, lng)),
      unit: 'kmh',
      segmentId: 'sim-segment',
      segmentKey: null,
      distanceMeters: 0,
      origin: { kind: 'imported' },
      importedValue: null,
    }),
  };
}
