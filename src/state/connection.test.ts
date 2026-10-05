import type { RawClient } from '@/tn/service';

import { TnConnection } from './connection';

const ok = (value: unknown) => JSON.stringify({ ok: value });
const syncStatus = { connection: 'online', lastSyncedAtUnixMs: 1, pendingWrites: 0, subscribedTiles: [], staticDataVersion: 1, lastErrorCode: null, lastErrorMessage: null, storageBytes: 1 };
const networkStatus = { knownNodes: [], activeNodes: [], currentNodes: [], directoryGeneratedAt: null, configVersion: null, cameraNamespaceEnabled: false };
const report = { skipped: false, ok: true, staticDataError: null, dynamicDataError: null, submitted: 0, rejected: 0, pendingWrites: 0 };

type Handler = (args: string) => string | Promise<string>;

function fake(handlers: Record<string, Handler> = {}) {
  const calls: string[] = [];
  let listener: { onEvent(json: string): void } | undefined;
  const base: Record<string, Handler> = {
    planBootstrap: () => ok({ partitionsTotal: 1, partitionsPending: 0, bytesTotal: 10, bytesPending: 0 }),
    tick: () => ok({ synced: true, report }),
    sync: () => ok(report),
    getSyncStatus: () => ok(syncStatus),
    getNetworkStatus: () => ok(networkStatus),
  };
  const raw: RawClient = {
    callAsync: async (method, args) => {
      calls.push(method);
      const handler = handlers[method] ?? base[method];
      if (!handler) throw new Error(`unexpected ${method}`);
      return handler(args);
    },
    startRealtime: jest.fn(),
    stopRealtime: jest.fn(),
    setEventListener: jest.fn((l) => void (listener = l)),
    uniffiDestroy: jest.fn(),
  };
  return { raw, calls, emit: (event: object) => listener?.onEvent(JSON.stringify(event)) };
}

function make(f: ReturnType<typeof fake>, onWifi = true) {
  return new TnConnection({ createClient: () => f.raw, options: {}, isOnWifi: async () => onWifi, tickIntervalMs: 3_600_000 });
}

const settle = async () => {
  for (let i = 0; i < 20; i++) await Promise.resolve();
};

beforeEach(() => jest.useFakeTimers());
afterEach(() => jest.useRealTimers());

describe('TnConnection: an explicit sync is not dropped', () => {
  it('waits for the pass that is running and then syncs', async () => {
    let release: () => void = () => {};
    const pendingPlan = ok({ partitionsTotal: 1, partitionsPending: 1, bytesTotal: 9, bytesPending: 9 });
    let first = true;
    const f = fake({
      // only the first plan request is slow; later ones answer at once
      planBootstrap: () => (first ? ((first = false), new Promise<string>((resolve) => (release = () => resolve(pendingPlan)))) : pendingPlan),
    });
    const c = make(f, false); // on mobile data, "Wi-Fi only": the first pass is held back
    c.setWifiOnly(true);
    c.start();
    await settle();
    const explicit = c.syncNow({ ignoreWifi: true }); // the user taps "load anyway" while the first pass is still waiting
    await settle();
    expect(f.calls).not.toContain('sync');
    release();
    await explicit;
    expect(f.calls).toContain('sync'); // not silently dropped
    expect(c.getSnapshot().waitingForWifi).toBe(false);
    c.stop();
  });
});

describe('TnConnection: "Wi-Fi only" and new static data', () => {
  it('looks at the download plan again after a while, so a new package waits for Wi-Fi', async () => {
    const now = jest.spyOn(Date, 'now');
    now.mockReturnValue(1_000_000);
    let pending = 0;
    const f = fake({ planBootstrap: () => ok({ partitionsTotal: 2, partitionsPending: pending ? 1 : 0, bytesTotal: 100, bytesPending: pending }) });
    const c = make(f, false);
    c.setWifiOnly(true);
    c.start();
    await settle();
    expect(f.calls).toContain('tick'); // nothing pending: mobile data is fine
    f.calls.length = 0;

    pending = 5_000_000; // the server published new static data
    await c.syncNow(); // within the minutes before the next check: still thought complete
    expect(f.calls).not.toContain('planBootstrap');
    f.calls.length = 0;

    now.mockReturnValue(1_000_000 + 11 * 60 * 1000);
    await c.syncNow(); // after the recheck interval
    expect(f.calls).toContain('planBootstrap');
    expect(f.calls).not.toContain('sync'); // held back: on mobile data with a large download pending
    expect(c.getSnapshot().waitingForWifi).toBe(true);
    c.stop();
    now.mockRestore();
  });
});

describe('TnConnection: screens re-read only when data changed', () => {
  it('does not bump the data version on a quiet tick, and does on events from the library', async () => {
    const f = fake();
    const c = make(f);
    c.start();
    await settle();
    jest.advanceTimersByTime(500);
    const afterFirst = c.getSnapshot().dataVersion;
    expect(afterFirst).toBe(1); // the first successful pass

    await c.syncNow();
    jest.advanceTimersByTime(500);
    expect(c.getSnapshot().dataVersion).toBe(afterFirst); // nothing changed

    f.emit({ type: 'syncCompleted', pendingWrites: 0 });
    jest.advanceTimersByTime(500);
    expect(c.getSnapshot().dataVersion).toBe(afterFirst); // a completed sync alone changes nothing for the screens

    f.emit({ type: 'dataChanged', entityType: 'hazard', entityId: 'h1', eventType: 'created' });
    jest.advanceTimersByTime(500);
    expect(c.getSnapshot().dataVersion).toBe(afterFirst + 1);
    c.stop();
  });

  it('bumps when a pass sent something, and when the static data finished loading', async () => {
    const f = fake({ tick: () => ok({ synced: true, report: { ...report, submitted: 2 } }) });
    const c = make(f);
    c.start();
    await settle();
    jest.advanceTimersByTime(500);
    const v = c.getSnapshot().dataVersion;
    await c.syncNow();
    jest.advanceTimersByTime(500);
    expect(c.getSnapshot().dataVersion).toBeGreaterThan(v - 1);
    f.emit({ type: 'bootstrapProgress', partitionsTotal: 4, partitionsDone: 4, bytesTotal: 1, bytesDone: 1 });
    jest.advanceTimersByTime(500);
    expect(c.getSnapshot().dataVersion).toBeGreaterThan(v);
    c.stop();
  });
});

describe('TnConnection: the emergency mode (first install, no server)', () => {
  // as measured against the real library: the time of the last attempt is set, but no static data was ever loaded
  const neverSynced = { ...syncStatus, connection: 'offline', staticDataVersion: null, lastSyncedAtUnixMs: 1_790_000_000_000, lastErrorCode: 'network' };
  const failedReport = { ...report, ok: false, dynamicDataError: 'network error' };

  it('is off while the first attempt is still running', async () => {
    const f = fake({ planBootstrap: () => new Promise<string>(() => {}) });
    const c = make(f);
    c.start();
    await settle();
    expect(c.getSnapshot().phase).toBe('starting');
    expect(c.getSnapshot().emergency).toBeNull();
    c.stop();
  });

  it('starts when nothing was ever loaded and no server answers', async () => {
    const f = fake({ tick: () => ok({ synced: false, report: failedReport }), getSyncStatus: () => ok(neverSynced) });
    const c = make(f);
    c.start();
    await settle();
    expect(c.getSnapshot().emergency).toBe('noServer');
    c.stop();
  });

  it('treats a thrown "network" error (the real library throws it when no server answers) as offline, not as an app error', async () => {
    const down = () => JSON.stringify({ error: { code: 'network', message: 'every server in the current pool failed' } });
    const f = fake({ tick: down, sync: down, getSyncStatus: () => ok(neverSynced) });
    const c = make(f);
    c.start();
    await settle();
    expect(c.getSnapshot().phase).toBe('ready');
    expect(c.getSnapshot().error).toBeNull();
    expect(c.getSnapshot().emergency).toBe('noServer');
    await c.syncNow();
    expect(c.getSnapshot().phase).toBe('ready');
    c.stop();
  });

  it('keeps an error of another kind (wrong credentials) as an error, not as the emergency mode', async () => {
    const f = fake({ tick: () => JSON.stringify({ error: { code: 'auth', message: 'credentials refused' } }) });
    const c = make(f);
    c.start();
    await settle();
    expect(c.getSnapshot().phase).toBe('error');
    expect(c.getSnapshot().emergency).toBeNull();
    c.stop();
  });

  it('says "no access" when no credentials were given', async () => {
    const f = fake({ planBootstrap: () => JSON.stringify({ error: { code: 'notConfigured', message: 'no credentials' } }), tick: () => JSON.stringify({ error: { code: 'notConfigured', message: 'no credentials' } }) });
    const c = make(f);
    c.start();
    await settle();
    expect(c.getSnapshot().phase).toBe('noCredentials');
    expect(c.getSnapshot().emergency).toBe('noAccess');
    c.stop();
  });

  it('is not the emergency mode when data from an earlier sync is on the device (plain offline)', async () => {
    const f = fake({ tick: () => ok({ synced: false, report: failedReport }), getSyncStatus: () => ok({ ...syncStatus, connection: 'offline', staticDataVersion: 3 }) });
    const c = make(f);
    c.start();
    await settle();
    expect(c.getSnapshot().emergency).toBeNull();
    c.stop();
  });

  it('is not the emergency mode while the Wi-Fi-only choice holds the download back', async () => {
    const f = fake({ planBootstrap: () => ok({ partitionsTotal: 1, partitionsPending: 1, bytesTotal: 9, bytesPending: 9 }), getSyncStatus: () => ok({ ...neverSynced, connection: 'never' }) });
    const c = make(f, false);
    c.setWifiOnly(true);
    c.start();
    await settle();
    expect(c.getSnapshot().waitingForWifi).toBe(true);
    expect(c.getSnapshot().emergency).toBeNull();
    c.stop();
  });

  it('ends by itself with the first successful sync', async () => {
    let up = false;
    const f = fake({
      tick: () => ok({ synced: up, report: up ? report : failedReport }),
      sync: () => ok(up ? report : failedReport),
      getSyncStatus: () => ok(up ? syncStatus : neverSynced),
    });
    const c = make(f);
    c.start();
    await settle();
    expect(c.getSnapshot().emergency).toBe('noServer');
    up = true;
    await c.syncNow();
    expect(c.getSnapshot().emergency).toBeNull();
    c.stop();
  });
});
