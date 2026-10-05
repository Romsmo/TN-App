import { alongCross, angleDiff, bearingDegrees, destination, distanceMeters, rayEntryDistance } from './geo';

const here = { lat: 52.5, lng: 13.4 };

describe('distance and bearing', () => {
  it('measures about 111 km per degree of latitude', () => {
    expect(distanceMeters({ lat: 0, lng: 0 }, { lat: 1, lng: 0 })).toBeCloseTo(111_195, -2);
  });

  it.each([
    [{ lat: 1, lng: 0 }, 0],
    [{ lat: 0, lng: 1 }, 90],
    [{ lat: -1, lng: 0 }, 180],
    [{ lat: 0, lng: -1 }, 270],
  ])('bearing from the origin to %j is %d', (to, expected) => {
    expect(bearingDegrees({ lat: 0, lng: 0 }, to)).toBeCloseTo(expected, 3);
  });

  it.each([
    [10, 350, 20],
    [350, 10, 20],
    [0, 180, 180],
    [90, 90, 0],
    [725, 5, 0],
  ])('angleDiff(%d, %d) = %d', (a, b, expected) => {
    expect(angleDiff(a, b)).toBeCloseTo(expected, 6);
  });

  it('destination and distance agree', () => {
    const p = destination(here, 73, 1500);
    expect(distanceMeters(here, p)).toBeCloseTo(1500, 0);
    expect(bearingDegrees(here, p)).toBeCloseTo(73, 1);
  });
});

describe('alongCross', () => {
  it('puts a point straight ahead on the track', () => {
    const p = destination(here, 90, 500);
    const { along, cross } = alongCross(here, 90, p);
    expect(along).toBeCloseTo(500, 0);
    expect(cross).toBeLessThan(1);
  });

  it('puts a point behind at negative along', () => {
    expect(alongCross(here, 90, destination(here, 270, 300)).along).toBeCloseTo(-300, 0);
  });

  it('measures the side offset', () => {
    const ahead = destination(here, 0, 400);
    const side = destination(ahead, 90, 40);
    const { along, cross } = alongCross(here, 0, side);
    expect(along).toBeCloseTo(400, 0);
    expect(cross).toBeCloseTo(40, 0);
  });
});

describe('rayEntryDistance', () => {
  // a square about 400 m wide, whose near edge is 1000 m north of `here`
  const corner = (north: number, east: number) => {
    const p = destination(destination(here, 0, north), 90, east);
    return [p.lng, p.lat] as [number, number];
  };
  const square = [corner(1000, -200), corner(1000, 200), corner(1400, 200), corner(1400, -200)];

  it('finds the first edge on the heading', () => {
    expect(rayEntryDistance(here, 0, square)).toBeCloseTo(1000, -1);
  });

  it('is null when the heading misses the zone', () => {
    expect(rayEntryDistance(here, 90, square)).toBeNull();
    expect(rayEntryDistance(here, 180, square)).toBeNull();
  });

  it('is 0 inside the zone', () => {
    const inside = destination(here, 0, 1200);
    expect(rayEntryDistance(inside, 0, square)).toBe(0);
  });

  it('is null for a degenerate ring', () => {
    expect(rayEntryDistance(here, 0, [[13.4, 52.5], [13.5, 52.6]])).toBeNull();
  });
});
