import type { DriveSession, DriveSnapshot } from './drive-session';
import type { Fix } from './warning-engine';

/** A stream of position fixes: the device's location updates, or the simulated route. */
export interface PositionSource {
  start(onFix: (fix: Fix) => void): Promise<void> | void;
  stop(): void;
}

export type DriveMode = 'real' | 'simulation';

type Deps = {
  createSession: (simulated: boolean) => DriveSession;
  realSource: () => PositionSource;
  simSource: (speedup: number) => PositionSource;
  /** Regular heartbeat of the session (warnings expire, the lock goes stale). */
  setInterval: (fn: () => void, ms: number) => unknown;
  clearInterval: (handle: unknown) => void;
};


/**
 * Owns one drive: the session, the position source and the heartbeat. Lives outside React so that the drive
 * (and its lock) survives screen changes. Start errors (no permission) are thrown to the caller.
 */
export class DriveHost {
  private session: DriveSession | null = null;
  private source: PositionSource | null = null;
  private heartbeat: unknown = null;
  private unsubscribe: (() => void) | null = null;
  private snap: DriveSnapshot | null = null;
  private readonly listeners = new Set<() => void>();

  constructor(private readonly deps: Deps) {}

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  getSnapshot = (): DriveSnapshot | null => this.snap;

  get isActive(): boolean {
    return this.snap?.active === true;
  }

  get current(): DriveSession | null {
    return this.session;
  }

  private emit(): void {
    this.listeners.forEach((l) => l());
  }

  async start(mode: DriveMode, options: { speedup?: number } = {}): Promise<void> {
    if (this.session) this.stop();
    const session = this.deps.createSession(mode === 'simulation');
    const source = mode === 'simulation' ? this.deps.simSource(options.speedup ?? 1) : this.deps.realSource();
    this.session = session;
    this.source = source;
    this.unsubscribe = session.subscribe(() => {
      this.snap = session.getSnapshot();
      this.emit();
    });
    session.start();
    try {
      await source.start((fix) => session.onFix(fix));
    } catch (error) {
      this.stop();
      throw error;
    }
    this.heartbeat = this.deps.setInterval(() => session.tick(), 1000);
  }

  stop(): void {
    if (this.heartbeat !== null) this.deps.clearInterval(this.heartbeat);
    this.heartbeat = null;
    this.source?.stop();
    this.source = null;
    this.session?.stop();
    this.unsubscribe?.();
    this.unsubscribe = null;
    this.session = null;
    this.snap = null;
    this.emit();
  }
}

