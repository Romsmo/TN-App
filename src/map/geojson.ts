import type { Feature, FeatureCollection, Point, Polygon } from 'geojson';

import type { CameraZoneItem, NearbyItem } from '@/tn/types';

import { CAMERAS_GROUP, isCameraType, isTypeHidden } from './camera-types';

export type MapFilter = { hiddenHazardTypes: ReadonlySet<string> };

export type MapData = {
  hazards: FeatureCollection<Point>;
  signs: FeatureCollection<Point>;
  /** Areas only. A camera zone never becomes a point (the country policy says "zones", not "locations"). */
  zones: FeatureCollection<Polygon>;
};

function point(item: { id: string; lat: number; lng: number }, properties: Record<string, unknown>): Feature<Point> {
  return { type: 'Feature', id: item.id, geometry: { type: 'Point', coordinates: [item.lng, item.lat] }, properties };
}

function zonePolygon(zone: CameraZoneItem): Feature<Polygon> | null {
  const ring = zone.outline;
  if (ring.length < 3) return null;
  const closed = ring[0]![0] === ring[ring.length - 1]![0] && ring[0]![1] === ring[ring.length - 1]![1] ? ring : [...ring, ring[0]!];
  return {
    type: 'Feature',
    id: zone.id,
    geometry: { type: 'Polygon', coordinates: [closed] },
    properties: { id: zone.id, cameraTypes: zone.cameraTypes.join(',') },
  };
}

/**
 * Turns what the library returns into map layers. Individual cameras (`kind: "camera"`) are drawn as hazards-like points
 * only when the library delivered them, which it does only when the user switched cameras on and the country policy
 * allows it; this function adds no gate of its own and never invents one.
 */
export function toMapData(items: readonly NearbyItem[], filter: MapFilter): MapData {
  const hazards: Feature<Point>[] = [];
  const signs: Feature<Point>[] = [];
  const zones: Feature<Polygon>[] = [];

  for (const item of items) {
    switch (item.kind) {
      case 'hazard':
        if (isTypeHidden(item.hazardType, filter.hiddenHazardTypes)) break;
        hazards.push(
          point(item, {
            id: item.id,
            kind: 'hazard',
            type: item.hazardType,
            confirmCount: item.confirmCount,
            denyCount: item.denyCount,
            pending: item.pending,
          }),
        );
        break;
      case 'camera':
        if (isTypeHidden(item.cameraType, filter.hiddenHazardTypes)) break;
        hazards.push(point(item, { id: item.id, kind: 'camera', type: item.cameraType, confirmCount: 0, denyCount: 0, pending: false }));
        break;
      case 'sign':
        signs.push(point(item, { id: item.id, kind: 'sign', type: item.signType }));
        break;
      case 'cameraZone': {
        if (filter.hiddenHazardTypes.has(CAMERAS_GROUP)) break;
        const polygon = zonePolygon(item);
        if (polygon) zones.push(polygon);
        break;
      }
    }
  }
  return {
    hazards: { type: 'FeatureCollection', features: hazards },
    signs: { type: 'FeatureCollection', features: signs },
    zones: { type: 'FeatureCollection', features: zones },
  };
}

/**
 * The distinct types present in the data, for the filter chips: the list comes from the data, not from the app.
 * All camera types (reports, fixed devices, zones) collapse into one entry, the camera group.
 */
export function hazardTypesIn(items: readonly NearbyItem[]): string[] {
  const types = new Set<string>();
  for (const item of items) {
    if (item.kind === 'hazard') types.add(isCameraType(item.hazardType) ? CAMERAS_GROUP : item.hazardType);
    else if (item.kind === 'camera' || item.kind === 'cameraZone') types.add(CAMERAS_GROUP);
  }
  return [...types].sort();
}

/** What a pin on the map is: a report (with votes) or a permanently installed device. */
export type PointItem = Extract<NearbyItem, { kind: 'hazard' | 'camera' }>;

export function pointType(item: PointItem): string {
  return item.kind === 'hazard' ? item.hazardType : item.cameraType;
}
