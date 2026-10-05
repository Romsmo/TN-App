import { destination } from './geo';
import { DEFAULT_WARN_CONFIG, thresholds, WarningEngine, type Fix, type WarnCandidate, type WarnEvent } from './warning-engine';

const start = { lat: 52.5, lng: 13.4 };
const NORTH = 0;

/** The vehicle drives north from `start` at `speed` km/h; positions are generated every `stepM` metres. */
function drive(engine: WarningEngine, candidates: (origin: typeof start) => WarnCandidate[], opts: { speed?: number; fromM?: number; toM?: number; stepM?: number; heading?: number | null } = {}): WarnEvent[] {
  const { speed = 100, fromM = 0, toM = 3500, stepM = 25, heading = NORTH } = opts;
  const out: WarnEvent[] = [];
  const list = candidates(start);
  for (let m = fromM; m <= toM; m += stepM) {
    const p = destination(start, NORTH, m);
    const fix: Fix = { lat: p.lat, lng: p.lng, speedKmh: speed, heading, t: m };
    out.push(...engine.update(fix, list));
  }
  return out;
}

const hazardAt = (north: number, east = 0, id = 'h1'): ((o: typeof start) => WarnCandidate[]) => (o) => {
  const p = destination(destination(o, NORTH, north), 90, east);
  return [{ id, kind: 'point', category: 'accident', source: 'hazard', lat: p.lat, lng: p.lng }];
};

describe('thresholds', () => {
  it.each([
    // speed km/h, first m, second m
    [30, 300, 80], // slow: the minimum distances apply
    [100, 694, 222],
    [130, 903, 289],
  ])('at %d km/h: first ≈ %d m, second ≈ %d m', (speed, first, second) => {
    const t = thresholds(speed, DEFAULT_WARN_CONFIG);
    expect(t.first).toBeCloseTo(first, -1);
    expect(t.second).toBeCloseTo(second, -1);
  });

  it('caps the early warning and keeps the second one well inside the first', () => {
    const t = thresholds(400, DEFAULT_WARN_CONFIG);
    expect(t.first).toBe(DEFAULT_WARN_CONFIG.maxFirstM);
    expect(t.second).toBeLessThanOrEqual(t.first * 0.6);
  });

  it('scales with the user setting', () => {
    const normal = thresholds(100, DEFAULT_WARN_CONFIG);
    const far = thresholds(100, { ...DEFAULT_WARN_CONFIG, scale: 1.5 });
    expect(far.first).toBeCloseTo(normal.first * 1.5, 3);
  });

  it('warns earlier the faster you drive', () => {
    expect(thresholds(130, DEFAULT_WARN_CONFIG).first).toBeGreaterThan(thresholds(60, DEFAULT_WARN_CONFIG).first);
  });
});

describe('WarningEngine, point objects', () => {
  it('warns exactly once early and once shortly before, then reports the pass', () => {
    const events = drive(new WarningEngine(), hazardAt(3000));
    expect(events.map((e) => (e.type === 'warn' ? e.level : e.type))).toEqual(['first', 'second', 'passed']);
    const first = events[0] as Extract<WarnEvent, { type: 'warn' }>;
    const second = events[1] as Extract<WarnEvent, { type: 'warn' }>;
    expect(first.distanceM).toBeGreaterThan(second.distanceM ?? 0);
    expect(first.distanceM).toBeLessThanOrEqual(700);
    expect(second.distanceM).toBeLessThanOrEqual(210);
    expect(events[2]).toMatchObject({ type: 'passed', reachedSecond: true });
  });

  it('does not repeat while the vehicle stays near the same spot', () => {
    const engine = new WarningEngine();
    const candidates = hazardAt(500)(start);
    const fix: Fix = { ...start, speedKmh: 100, heading: NORTH, t: 0 };
    const again = Array.from({ length: 20 }, () => engine.update(fix, candidates)).flat();
    expect(again.filter((e) => e.type === 'warn')).toHaveLength(1);
  });

  it('warns only the second time when the object shows up late', () => {
    const events = drive(new WarningEngine(), hazardAt(3000), { fromM: 2900 }).filter((e) => e.type === 'warn');
    expect(events).toHaveLength(1);
    expect(events[0]).toMatchObject({ level: 'second' });
  });

  it('ignores objects behind the vehicle (the other direction)', () => {
    const engine = new WarningEngine();
    const events = drive(engine, hazardAt(-1000), { fromM: 0, toM: 500 });
    expect(events).toEqual([]);
  });

  it('ignores an object that is driven towards but on the other side of the heading line', () => {
    expect(drive(new WarningEngine(), hazardAt(3000, 160))).toEqual([]);
  });

  it('accepts a small side offset (own lane, GPS noise)', () => {
    const events = drive(new WarningEngine(), hazardAt(3000, 12));
    expect(events.some((e) => e.type === 'warn')).toBe(true);
  });

  it('is silent below the minimum speed', () => {
    const events = drive(new WarningEngine(), hazardAt(300), { speed: 5, fromM: 0, toM: 400 });
    expect(events.filter((e) => e.type === 'warn')).toEqual([]);
  });

  it('is silent without a heading or speed', () => {
    expect(drive(new WarningEngine(), hazardAt(300), { heading: null, toM: 400 })).toEqual([]);
    const engine = new WarningEngine();
    expect(engine.update({ ...start, speedKmh: null, heading: NORTH, t: 0 }, hazardAt(300)(start))).toEqual([]);
  });

  it('warns again on a later approach after the object was left far behind', () => {
    const engine = new WarningEngine();
    const list = hazardAt(1000)(start);
    drive(engine, hazardAt(1000), { toM: 1200 });
    // far away again (U-turn and back): the memory is dropped once the object is out of range
    const far = destination(start, NORTH, -3000);
    engine.update({ ...far, speedKmh: 100, heading: NORTH, t: 1 }, list);
    const events = [];
    for (let m = -3000; m <= 950; m += 25) {
      const p = destination(start, NORTH, m);
      events.push(...engine.update({ ...p, speedKmh: 100, heading: NORTH, t: m }, list));
    }
    expect(events.filter((e) => e.type === 'warn' && e.level === 'first')).toHaveLength(1);
  });

  it('handles several objects independently and in order of distance', () => {
    const both = (o: typeof start): WarnCandidate[] => [...hazardAt(1500, 0, 'far')(o), ...hazardAt(900, 0, 'near')(o)];
    const events = drive(new WarningEngine(), both, { fromM: 0, toM: 1700 }).filter((e) => e.type === 'warn');
    expect(events.filter((e) => e.id === 'far')).toHaveLength(2);
    expect(events.filter((e) => e.id === 'near')).toHaveLength(2);
  });
});

describe('WarningEngine, zones', () => {
  const zoneAhead = (entryM: number, id = 'z1') => (o: typeof start): WarnCandidate[] => {
    const corner = (n: number, e: number) => {
      const p = destination(destination(o, NORTH, n), 90, e);
      return [p.lng, p.lat] as [number, number];
    };
    return [{ id, kind: 'zone', category: 'cameras', ring: [corner(entryM, -300), corner(entryM, 300), corner(entryM + 800, 300), corner(entryM + 800, -300)] }];
  };

  it('warns about the area, never with a distance to a point', () => {
    const events = drive(new WarningEngine(), zoneAhead(2000), { toM: 3200 });
    const warns = events.filter((e): e is Extract<WarnEvent, { type: 'warn' }> => e.type === 'warn');
    expect(warns.length).toBeGreaterThanOrEqual(1);
    for (const w of warns) {
      expect(w.kind).toBe('zone');
      expect(w.source).toBe('zone');
      expect(w.distanceM).toBeNull();
    }
  });

  it('warns once on the approach and once inside, then reports the area as left', () => {
    const events = drive(new WarningEngine(), zoneAhead(2000), { toM: 3200 });
    expect(events.map((e) => (e.type === 'warn' ? e.level : e.type))).toEqual(['first', 'second', 'passed']);
  });

  it('does not warn about a zone beside the road', () => {
    const aside = (o: typeof start): WarnCandidate[] => {
      const east = destination(o, 90, 2000);
      const corner = (n: number, e: number) => {
        const p = destination(destination(east, NORTH, n), 90, e);
        return [p.lng, p.lat] as [number, number];
      };
      return [{ id: 'z2', kind: 'zone', category: 'cameras', ring: [corner(0, 0), corner(0, 500), corner(3000, 500), corner(3000, 0)] }];
    };
    expect(drive(new WarningEngine(), aside, { toM: 3000 })).toEqual([]);
  });
});
