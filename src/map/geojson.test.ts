import type { NearbyItem } from '@/tn/types';

import { hazardTypesIn, toMapData } from './geojson';

const hazard = (id: string, hazardType: string): NearbyItem => ({
  kind: 'hazard', id, hazardType, lat: 52.5, lng: 13.4, distanceMeters: 10, expiresAt: '2026-10-05T12:00:00Z', confirmCount: 2, denyCount: 0, pending: false,
});
const zone: NearbyItem = {
  kind: 'cameraZone', id: 'z1', cell: '871f1d489ffffff', resolution: 7, cameraTypes: ['mobileSpeedCamera'], distanceMeters: 0,
  outline: [[13.0, 52.0], [13.1, 52.0], [13.1, 52.1]],
};
const camera: NearbyItem = { kind: 'camera', id: 'c1', cameraType: 'fixedSpeedCamera', lat: 52.1, lng: 13.1, distanceMeters: 5 };

const none = { hiddenHazardTypes: new Set<string>() };

describe('toMapData', () => {
  it('draws hazards as points in [lng, lat] order', () => {
    const data = toMapData([hazard('h1', 'ice')], none);
    expect(data.hazards.features).toHaveLength(1);
    expect(data.hazards.features[0]!.geometry.coordinates).toEqual([13.4, 52.5]);
  });

  it('hides the types the user switched off, and shows new types by default', () => {
    const items = [hazard('h1', 'ice'), hazard('h2', 'traffic'), hazard('h3', 'somethingNew')];
    const data = toMapData(items, { hiddenHazardTypes: new Set(['ice']) });
    expect(data.hazards.features.map((f) => f.properties!.type)).toEqual(['traffic', 'somethingNew']);
  });

  it('draws a camera zone only as a closed polygon, never as a point', () => {
    const data = toMapData([zone], none);
    expect(data.hazards.features).toHaveLength(0);
    expect(data.signs.features).toHaveLength(0);
    expect(data.zones.features).toHaveLength(1);
    const ring = data.zones.features[0]!.geometry.coordinates[0]!;
    expect(ring[0]).toEqual(ring[ring.length - 1]);
    expect(ring).toHaveLength(4);
  });

  it('adds no coordinate to a zone feature beyond the outline corners', () => {
    const data = toMapData([zone], none);
    const json = JSON.stringify(data);
    for (const [lng, lat] of zone.kind === 'cameraZone' ? zone.outline : []) {
      expect(json).toContain(`[${lng},${lat}]`);
    }
    expect(JSON.stringify(data.zones.features[0]!.properties)).not.toMatch(/lat|lng|coordinates/);
  });

  it('skips a degenerate zone outline instead of drawing garbage', () => {
    const broken: NearbyItem = { ...(zone as Extract<NearbyItem, { kind: 'cameraZone' }>), outline: [[1, 2], [3, 4]] };
    expect(toMapData([broken], none).zones.features).toHaveLength(0);
  });

  it('shows individual cameras only if the library delivered them', () => {
    expect(toMapData([], none).hazards.features).toHaveLength(0);
    expect(toMapData([camera], none).hazards.features).toHaveLength(1);
  });
});

describe('hazardTypesIn', () => {
  it('lists the distinct hazard types from the data, sorted', () => {
    expect(hazardTypesIn([hazard('1', 'traffic'), hazard('2', 'ice'), hazard('3', 'traffic'), zone, camera])).toEqual(['ice', 'traffic']);
  });
});
