import { alongCross, rayEntryDistance, type LatLng } from './geo';

/** A thing the driver may be warned about. A zone is an area: it has no point and is never announced with a distance to a spot. */
export type WarnCandidate =
  | { id: string; kind: 'point'; category: string; source: 'hazard' | 'camera'; lat: number; lng: number }
  | { id: string; kind: 'zone'; category: string; ring: readonly (readonly [number, number])[] };

export type Fix = { lat: number; lng: number; speedKmh: number | null; heading: number | null; t: number };

export type WarnConfig = {
  /** Seconds of driving time before the object for the first and the second warning. */
  leadFirstS: number;
  leadSecondS: number;
  /** Bounds for the warning distances (metres), before `scale`. */
  minFirstM: number;
  maxFirstM: number;
  minSecondM: number;
  /** User setting: stretches or shrinks all warning distances. */
  scale: number;
  /** No warnings below this speed (km/h): standing in a queue is not driving towards a hazard. */
  minSpeedKmh: number;
  /** Side tolerance of "on my carriageway": grows with distance (curves), within these bounds (metres). */
  lateralMinM: number;
  lateralMaxM: number;
  lateralFactor: number;
  /** How far behind (metres) an object must be to count as passed. */
  passedM: number;
};

export const DEFAULT_WARN_CONFIG: WarnConfig = {
  leadFirstS: 25,
  leadSecondS: 8,
  minFirstM: 300,
  maxFirstM: 2000,
  minSecondM: 80,
  scale: 1,
  minSpeedKmh: 10,
  lateralMinM: 25,
  lateralMaxM: 100,
  lateralFactor: 0.1,
  passedM: 30,
};

export type WarnEvent =
  | { type: 'warn'; level: 'first' | 'second'; id: string; kind: 'point' | 'zone'; category: string; source: 'hazard' | 'camera' | 'zone'; distanceM: number | null }
  | { type: 'passed'; id: string; kind: 'point' | 'zone'; category: string; source: 'hazard' | 'camera' | 'zone'; reachedSecond: boolean };

type Stage = 0 | 1 | 2;

/** The two warning distances for a speed. */
export function thresholds(speedKmh: number, config: WarnConfig): { first: number; second: number } {
  const v = Math.max(0, speedKmh) / 3.6;
  const first = Math.min(config.maxFirstM, Math.max(config.minFirstM, v * config.leadFirstS)) * config.scale;
  const second = Math.min(first * 0.6, Math.max(config.minSecondM, v * config.leadSecondS) * config.scale);
  return { first, second };
}

/**
 * Decides when to warn: only for objects in the direction of travel and on the own track, a first warning early
 * enough for the speed, a second one shortly before, never twice. Pure state machine: no clock, no I/O.
 *
 * Interim solution: the library has no road geometry for items, so "own carriageway" is a narrow corridor along the
 * heading. It cannot tell a hazard on the opposite lane from one on the own lane at long range. The proper filter
 * belongs into client-lib 1.2 (docs/todo.md); this class is the one place to replace.
 */
export class WarningEngine {
  private readonly stages = new Map<string, { stage: Stage; seenAhead: boolean }>();

  constructor(private readonly config: WarnConfig = DEFAULT_WARN_CONFIG) {}

  reset(): void {
    this.stages.clear();
  }

  update(fix: Fix, candidates: readonly WarnCandidate[]): WarnEvent[] {
    if (fix.speedKmh === null || fix.heading === null) return [];
    const here: LatLng = { lat: fix.lat, lng: fix.lng };
    const { first, second } = thresholds(fix.speedKmh, this.config);
    const moving = fix.speedKmh >= this.config.minSpeedKmh;
    const events: { along: number; event: WarnEvent }[] = [];
    const present = new Set<string>();

    for (const c of candidates) {
      present.add(c.id);
      let along: number | null; // metres to the object along the heading; null = not on the track
      let behind = false;
      if (c.kind === 'point') {
        const rel = alongCross(here, fix.heading, c);
        const lateral = Math.min(this.config.lateralMaxM, Math.max(this.config.lateralMinM, Math.abs(rel.along) * this.config.lateralFactor));
        along = rel.cross <= lateral ? rel.along : null;
        behind = rel.along < -this.config.passedM && rel.cross <= lateral;
      } else {
        along = rayEntryDistance(here, fix.heading, c.ring);
      }

      const state = this.stages.get(c.id) ?? { stage: 0 as Stage, seenAhead: false };
      const source = c.kind === 'zone' ? 'zone' : c.source;

      if (along !== null && along >= 0 && along <= first) {
        if (moving) {
          if (along <= second && state.stage < 2) {
            state.stage = 2;
            events.push({ along, event: { type: 'warn', level: 'second', id: c.id, kind: c.kind, category: c.category, source, distanceM: c.kind === 'zone' ? null : Math.round(along) } });
          } else if (along > second && state.stage < 1) {
            state.stage = 1;
            events.push({ along, event: { type: 'warn', level: 'first', id: c.id, kind: c.kind, category: c.category, source, distanceM: c.kind === 'zone' ? null : Math.round(along) } });
          }
        }
        state.seenAhead = true;
        this.stages.set(c.id, state);
      } else if (state.seenAhead && (behind || (c.kind === 'zone' && along === null))) {
        // it was ahead of us and now it is behind us (or the zone is left)
        events.push({ along: -1, event: { type: 'passed', id: c.id, kind: c.kind, category: c.category, source, reachedSecond: state.stage >= 2 } });
        this.stages.delete(c.id);
      } else if (along === null || along > first * 1.6 || along < -2000) {
        // far away or off the track again: forget, so it can warn anew on a later approach
        if (!state.seenAhead || along === null || along > first * 1.6) this.stages.delete(c.id);
      }
    }

    for (const id of this.stages.keys()) if (!present.has(id)) this.stages.delete(id);
    return events.sort((a, b) => a.along - b.along).map((e) => e.event);
  }
}
