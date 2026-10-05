import { DriveHost, type PositionSource } from './drive-host';
import type { DriveSession } from './drive-session';
import type { Fix } from './warning-engine';

function fakeSession() {
  let snap = { active: false } as ReturnType<DriveSession['getSnapshot']>;
  const listeners = new Set<() => void>();
  const session = {
    subscribe: (l: () => void) => (listeners.add(l), () => listeners.delete(l)),
    getSnapshot: () => snap,
    start: jest.fn(() => {
      snap = { ...snap, active: true };
      listeners.forEach((l) => l());
    }),
    stop: jest.fn(() => {
      snap = { ...snap, active: false };
      listeners.forEach((l) => l());
    }),
    onFix: jest.fn(),
    tick: jest.fn(),
  };
  return session as unknown as DriveSession & typeof session;
}

function fakeSource(): PositionSource & { start: jest.Mock; stop: jest.Mock; push(f: Fix): void } {
  let sink: (f: Fix) => void = () => {};
  return {
    start: jest.fn((onFix: (f: Fix) => void) => {
      sink = onFix;
    }),
    stop: jest.fn(),
    push: (f) => sink(f),
  };
}

function setup() {
  const sessions: ReturnType<typeof fakeSession>[] = [];
  const real = fakeSource();
  const sim = fakeSource();
  const timers: { fn: () => void }[] = [];
  const host = new DriveHost({
    createSession: () => {
      const s = fakeSession();
      sessions.push(s);
      return s;
    },
    realSource: () => real,
    simSource: () => sim,
    setInterval: (fn) => {
      const handle = { fn };
      timers.push(handle);
      return handle;
    },
    clearInterval: (h) => void timers.splice(timers.indexOf(h as { fn: () => void }), 1),
  });
  return { host, sessions, real, sim, timers };
}

const fix: Fix = { lat: 1, lng: 2, speedKmh: 50, heading: 0, t: 0 };

describe('DriveHost', () => {
  it('starts a real drive: session, position source and heartbeat', async () => {
    const { host, sessions, real, timers } = setup();
    await host.start('real');
    expect(host.isActive).toBe(true);
    expect(sessions[0]!.start).toHaveBeenCalled();
    expect(real.start).toHaveBeenCalled();
    expect(timers).toHaveLength(1);
    real.push(fix);
    expect(sessions[0]!.onFix).toHaveBeenCalledWith(fix);
    timers[0]!.fn();
    expect(sessions[0]!.tick).toHaveBeenCalled();
  });

  it('uses the simulated source, and only that, for a simulation', async () => {
    const { host, sim, real } = setup();
    await host.start('simulation');
    expect(sim.start).toHaveBeenCalled();
    expect(real.start).not.toHaveBeenCalled();
  });

  it('stops everything: source, heartbeat, session', async () => {
    const { host, sessions, real, timers } = setup();
    await host.start('real');
    host.stop();
    expect(real.stop).toHaveBeenCalled();
    expect(sessions[0]!.stop).toHaveBeenCalled();
    expect(timers).toHaveLength(0);
    expect(host.isActive).toBe(false);
    expect(host.getSnapshot()).toBeNull();
  });

  it('tells subscribers about start and stop', async () => {
    const { host } = setup();
    const listener = jest.fn();
    host.subscribe(listener);
    await host.start('real');
    const afterStart = listener.mock.calls.length;
    expect(afterStart).toBeGreaterThan(0);
    host.stop();
    expect(listener.mock.calls.length).toBeGreaterThan(afterStart);
  });

  it('cleans up and rethrows when the position source cannot start (no permission)', async () => {
    const { host, sessions, real, timers } = setup();
    real.start.mockRejectedValueOnce(new Error('permission denied'));
    await expect(host.start('real')).rejects.toThrow('permission denied');
    expect(host.isActive).toBe(false);
    expect(sessions[0]!.stop).toHaveBeenCalled();
    expect(timers).toHaveLength(0);
  });

  it('does not leave a heartbeat behind when the drive is stopped while the source is still starting', async () => {
    const { host, real, timers } = setup();
    let finishStart: () => void = () => {};
    real.start.mockImplementationOnce(() => new Promise<void>((resolve) => (finishStart = resolve)));
    const starting = host.start('real');
    host.stop(); // the user ends it during the permission dialog
    finishStart();
    await starting;
    expect(timers).toHaveLength(0);
    expect(real.stop).toHaveBeenCalled();
    expect(host.isActive).toBe(false);
  });

  it('ignores positions of a start that was replaced, and a failing old start does not stop the new drive', async () => {
    const { host, sessions, real, sim } = setup();
    let failFirst: (e: Error) => void = () => {};
    real.start.mockImplementationOnce(() => new Promise<void>((_, reject) => (failFirst = reject)));
    const first = host.start('real');
    const second = host.start('simulation');
    await second;
    failFirst(new Error('permission denied'));
    await expect(first).rejects.toThrow('permission denied');
    expect(host.isActive).toBe(true); // the second drive is still on
    expect(sessions[1]!.stop).not.toHaveBeenCalled();
    sim.push(fix);
    expect(sessions[1]!.onFix).toHaveBeenCalledWith(fix);
  });

  it('replaces a running drive when started again', async () => {
    const { host, sessions } = setup();
    await host.start('real');
    await host.start('simulation');
    expect(sessions).toHaveLength(2);
    expect(sessions[0]!.stop).toHaveBeenCalled();
  });
});
