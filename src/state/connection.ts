import { TnError, TnService, type RawClient } from '@/tn/service';
import { shouldSync } from '@/tn/sync-policy';
import type { ClientOptions, NetworkStatus, SyncStatus } from '@/tn/types';

export type Phase = 'starting' | 'ready' | 'noCredentials' | 'error';

export type ConnectionSnapshot = {
  phase: Phase;
  error: string | null;
  service: TnService | null;
  sync: SyncStatus | null;
  network: NetworkStatus | null;
  /** The static data is still waiting for Wi-Fi (the "Wi-Fi only" setting). */
  waitingForWifi: boolean;
  /** Queued writes the server refused for good since the app started and the user has not yet acknowledged. */
  rejectedWrites: number;
  /** Bumps whenever data in the local store changed; screens re-read when it moves. */
  dataVersion: number;
};

type Deps = {
  createClient: (options: Omit<ClientOptions, 'storagePath'>) => RawClient;
  options: Omit<ClientOptions, 'storagePath'>;
  isOnWifi: () => Promise<boolean>;
  tickIntervalMs: number;
};

/** How often an "all static data loaded" is verified again. */
const STATIC_RECHECK_MS = 10 * 60 * 1000;

const INITIAL: ConnectionSnapshot = {
  phase: 'starting',
  error: null,
  service: null,
  sync: null,
  network: null,
  waitingForWifi: false,
  rejectedWrites: 0,
  dataVersion: 0,
};

/**
 * One library client for one set of options: starts it, keeps it ticking, tells subscribers what changed.
 * A plain class (not a hook) so the flow is testable without React and so React only has to subscribe.
 */
export class TnConnection {
  private snap: ConnectionSnapshot = INITIAL;
  private readonly listeners = new Set<() => void>();
  private client: TnService | null = null;
  private timer: ReturnType<typeof setInterval> | undefined;
  private bumpTimer: ReturnType<typeof setTimeout> | undefined;
  private staticComplete = false;
  private staticCheckedAt = 0;
  private current: Promise<void> | null = null;
  private busy = false;
  private stopped = false;
  private wifiOnly = true;

  constructor(private readonly deps: Deps) {}

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  getSnapshot = (): ConnectionSnapshot => this.snap;

  setWifiOnly(value: boolean): void {
    this.wifiOnly = value;
  }

  /** The user has read the notice about refused writes. */
  dismissRejected = (): void => this.set({ rejectedWrites: 0 });

  /** Sync now. `ignoreWifi` is for an explicit tap on "load anyway". */
  /** Waits for a pass that is already running, then runs: an explicit tap must not be dropped. */
  syncNow = async (options?: { ignoreWifi?: boolean }): Promise<void> => {
    while (this.busy && this.current) await this.current.catch(() => undefined);
    await this.run(true, options?.ignoreWifi ?? false);
  };

  start(): void {
    this.stopped = false;
    try {
      this.client = new TnService(this.deps.createClient(this.deps.options));
    } catch (e) {
      this.set({ phase: 'error', error: e instanceof Error ? e.message : String(e) });
      return;
    }
    const client = this.client;
    client.onEvents((event) => {
      if (event.type === 'dataChanged') this.bump();
      else if (event.type === 'bootstrapProgress' && event.partitionsDone >= event.partitionsTotal) this.bump();
    });
    this.set({ service: client });
    client.startRealtime();
    void this.run(false, false);
    this.timer = setInterval(() => void this.run(false, false), this.deps.tickIntervalMs);
  }

  stop(): void {
    this.stopped = true;
    clearInterval(this.timer);
    clearTimeout(this.bumpTimer);
    this.client?.close();
    this.client = null;
  }

  private set(patch: Partial<ConnectionSnapshot>): void {
    if (this.stopped) return;
    this.snap = { ...this.snap, ...patch };
    this.listeners.forEach((l) => l());
  }

  private bump(): void {
    clearTimeout(this.bumpTimer);
    this.bumpTimer = setTimeout(() => this.set({ dataVersion: this.snap.dataVersion + 1 }), 400);
  }

  private run(force: boolean, ignoreWifi: boolean): Promise<void> {
    if (this.busy) return this.current ?? Promise.resolve();
    const pass = this.pass(force, ignoreWifi);
    this.current = pass;
    return pass;
  }

  private async pass(force: boolean, ignoreWifi: boolean): Promise<void> {
    const client = this.client;
    if (!client || this.busy || this.stopped) return;
    this.busy = true;
    try {
      // "Complete" is not forever: the server publishes new static data, so look again now and then (the manifest is a few KB).
      if (this.staticComplete && Date.now() - this.staticCheckedAt > STATIC_RECHECK_MS) this.staticComplete = false;
      let bytesPending: number | null = this.staticComplete ? 0 : null;
      if (!this.staticComplete) {
        try {
          bytesPending = (await client.planBootstrap()).bytesPending;
          this.staticComplete = bytesPending === 0;
          this.staticCheckedAt = Date.now();
        } catch {
          bytesPending = null; // offline or no access: the sync below reports it
        }
      }
      const allowed = ignoreWifi || shouldSync({ wifiOnly: this.wifiOnly, onWifi: await this.deps.isOnWifi(), bytesPending });
      if (this.stopped) return;
      this.set({ waitingForWifi: !allowed });
      if (allowed) {
        const report = force ? await client.sync() : (await client.tick()).report;
        if (report && report.rejected > 0) this.set({ rejectedWrites: this.snap.rejectedWrites + report.rejected });
        // Screens re-read only when something changed: the library tells (dataChanged), or this pass sent something.
        if (report && report.submitted > 0) this.bump();
      }
      const [sync, network] = await Promise.all([client.getSyncStatus(), client.getNetworkStatus()]);
      const firstReady = this.snap.phase !== 'ready';
      this.set({ sync, network, phase: 'ready', error: null });
      if (firstReady) this.bump(); // the first successful pass: whatever it loaded is new to the screens
    } catch (e) {
      if (e instanceof TnError && e.code === 'notConfigured') this.set({ phase: 'noCredentials', error: null });
      else this.set({ phase: 'error', error: e instanceof Error ? e.message : String(e) });
    } finally {
      this.busy = false;
    }
  }
}
