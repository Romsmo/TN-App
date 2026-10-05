import type { Fix } from '../warning-engine';
import { pointAt, type Route } from './gpx';

/**
 * Plays a route as GPS fixes, one per `stepMs`, at the speed the profile gives for the distance driven so far.
 * No real movement, no real sensor: the simulated drive feeds the same pipeline as a real one.
 */
export class RoutePlayer {
  private distance = 0;
  private t: number;

  constructor(
    private readonly route: Route,
    private readonly speedKmhAt: (distanceM: number) => number,
    startMs: number,
    private readonly stepMs = 1000,
  ) {
    this.t = startMs;
  }

  get finished(): boolean {
    return this.distance >= this.route.lengthM;
  }

  get progress(): number {
    return this.route.lengthM === 0 ? 1 : Math.min(1, this.distance / this.route.lengthM);
  }

  /** The next fix, or null when the end of the route is reached. */
  next(): Fix | null {
    if (this.finished) return null;
    const speed = this.speedKmhAt(this.distance);
    const p = pointAt(this.route, this.distance);
    const fix: Fix = { lat: p.lat, lng: p.lng, speedKmh: speed, heading: p.heading, t: this.t };
    this.distance += (speed / 3.6) * (this.stepMs / 1000);
    this.t += this.stepMs;
    return fix;
  }
}
