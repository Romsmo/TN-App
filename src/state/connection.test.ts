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
