import { DEMO_ROUTE_GPX } from './demo-route.gpx';
import { buildRoute, parseGpx, pointAt } from './gpx';
import { RoutePlayer } from './player';
import { createSimDataSource, simLimitAt, simSpeedAt } from './sim-data';
import { bearingDegrees, distanceMeters } from '../geo';

describe('parseGpx', () => {
  it('reads track points in order and skips broken ones', () => {
    const xml = `<gpx><trk><trkseg>
      <trkpt lat="48.1" lon="11.5"></trkpt>
      <trkpt lat="x" lon="11.6"></trkpt>
      <trkpt lat="95" lon="11.6"></trkpt>
      <trkpt lon="11.7" lat="48.3"><ele>5</ele></trkpt>
    </trkseg></trk></gpx>`;
    expect(parseGpx(xml)).toEqual([{ lat: 48.1, lng: 11.5 }, { lat: 48.3, lng: 11.7 }]);
  });

  it('returns nothing for text without track points', () => {
    expect(parseGpx('not a gpx')).toEqual([]);
  });
});

describe('the bundled demo route', () => {
  const route = buildRoute(parseGpx(DEMO_ROUTE_GPX));

  it('is about seven kilometres long', () => {
    expect(route.points.length).toBeGreaterThan(50);
    expect(route.lengthM).toBeGreaterThan(6500);
    expect(route.lengthM).toBeLessThan(7500);
  });

  it('gives positions and headings along the road, clamped at the ends', () => {
    const start = pointAt(route, 0);
    const mid = pointAt(route, 3000);
    const end = pointAt(route, 99_999);
    expect(distanceMeters(start, route.points[0]!)).toBeLessThan(1);
    expect(distanceMeters(end, route.points[route.points.length - 1]!)).toBeLessThan(1);
    expect(distanceMeters(start, mid)).toBeGreaterThan(2500);
  });

  it('has headings that match the direction of travel', () => {
    const a = pointAt(route, 1000);
    const b = pointAt(route, 1100);
    const h = bearingDegrees(a, b);
    expect(Math.abs(((h - a.heading + 540) % 360) - 180)).toBeLessThan(8);
  });
});

describe('RoutePlayer', () => {
  const route = buildRoute(parseGpx(DEMO_ROUTE_GPX));

  it('drives the whole route in order at the profile speed, one fix per second', () => {
    const player = new RoutePlayer(route, () => 72, 1_000_000);
    const fixes = [];
    for (let f = player.next(); f; f = player.next()) fixes.push(f);
    expect(fixes[0]!.t).toBe(1_000_000);
    expect(fixes[1]!.t).toBe(1_001_000);
    expect(fixes.every((f) => f.speedKmh === 72 && f.heading !== null)).toBe(true);
    expect(fixes.length).toBeGreaterThan(300);
    expect(fixes.length).toBeLessThan(400);
    expect(player.finished).toBe(true);
    expect(player.next()).toBeNull();
    expect(player.progress).toBe(1);
  });
});

describe('simulation data', () => {
  const route = buildRoute(parseGpx(DEMO_ROUTE_GPX));

  it('has three limits and a speed that is a little over one of them for a stretch', () => {
    expect(simLimitAt(100)).toBe(50);
    expect(simLimitAt(2000)).toBe(100);
    expect(simLimitAt(6000)).toBe(70);
    expect(simSpeedAt(100)).toBeLessThan(50);
    expect(simSpeedAt(2800)).toBeGreaterThan(100);
  });

  it('offers the invented hazards, and a camera zone only when cameras were switched on', async () => {
    const start = pointAt(route, 2000);
    const off = await createSimDataSource(route, { camerasEnabled: false }).nearby(start.lat, start.lng, 20_000);
    expect(off.map((i) => i.kind)).toEqual(['hazard', 'hazard', 'hazard']);
    const on = await createSimDataSource(route, { camerasEnabled: true }).nearby(start.lat, start.lng, 20_000);
    expect(on.filter((i) => i.kind === 'cameraZone')).toHaveLength(1);
    expect(on.filter((i) => i.kind === 'camera')).toHaveLength(0);
  });

  it('answers the speed limit by position along the route', async () => {
    const data = createSimDataSource(route, { camerasEnabled: false });
    const p = pointAt(route, 3000);
    await expect(data.speedLimit(p.lat, p.lng, p.heading)).resolves.toMatchObject({ value: 100, unit: 'kmh' });
  });
});
