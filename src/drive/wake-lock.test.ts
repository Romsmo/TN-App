import { keepScreenAwake, type WakeLockEnv, type WakeLockState } from './wake-lock';

function fakeEnv(options: { supported?: boolean; visible?: boolean; failFirst?: boolean } = {}) {
  let visible = options.visible ?? true;
  let failures = options.failFirst ? 1 : 0;
  const listeners = new Set<() => void>();
  const locks: { released: boolean; release: () => void; fireRelease: () => void }[] = [];
  const env: WakeLockEnv = {
    request:
      options.supported === false
        ? null
        : async () => {
            if (failures > 0) {
              failures--;
              throw new Error('refused');
            }
            let onRelease = () => {};
            const lock = {
              released: false,
              release() {
                lock.released = true;
              },
              fireRelease: () => onRelease(),
              addEventListener: (_type: 'release', l: () => void) => void (onRelease = l),
            };
            locks.push(lock);
            return lock;
          },
    isVisible: () => visible,
    onVisibilityChange: (l) => (listeners.add(l), () => listeners.delete(l)),
  };
  return {
    env,
    locks,
    setVisible(v: boolean) {
      visible = v;
      listeners.forEach((l) => l());
    },
    listenerCount: () => listeners.size,
  };
}
const settle = async () => {
  for (let i = 0; i < 10; i++) await Promise.resolve();
};

describe('keepScreenAwake', () => {
  it('takes the lock and says it is active', async () => {
    const f = fakeEnv();
    const states: WakeLockState[] = [];
    keepScreenAwake(f.env, (s) => states.push(s));
    await settle();
    expect(f.locks).toHaveLength(1);
    expect(states).toEqual(['active']);
  });

  it('says "unavailable" when the browser has no wake lock', () => {
    const states: WakeLockState[] = [];
    keepScreenAwake(fakeEnv({ supported: false }).env, (s) => states.push(s));
    expect(states).toEqual(['unavailable']);
  });

  it('asks again when the page comes back after the browser released the lock in the background', async () => {
    const f = fakeEnv();
    const states: WakeLockState[] = [];
    keepScreenAwake(f.env, (s) => states.push(s));
    await settle();
    f.setVisible(false);
    f.locks[0]!.fireRelease(); // the browser lets go when the page is hidden
    expect(states.at(-1)).toBe('lost');
    f.setVisible(true);
    await settle();
    expect(f.locks).toHaveLength(2);
    expect(states.at(-1)).toBe('active');
  });

  it('does not ask while the page is hidden', async () => {
    const f = fakeEnv({ visible: false });
    keepScreenAwake(f.env, () => {});
    await settle();
    expect(f.locks).toHaveLength(0);
  });

  it('reports a refused request as lost, and tries again on the next visibility change', async () => {
    const f = fakeEnv({ failFirst: true });
    const states: WakeLockState[] = [];
    keepScreenAwake(f.env, (s) => states.push(s));
    await settle();
    expect(states).toEqual(['lost']);
    f.setVisible(false);
    f.setVisible(true);
    await settle();
    expect(states.at(-1)).toBe('active');
  });

  it('lets go and stops listening when the drive ends, also when the request was still under way', async () => {
    const f = fakeEnv();
    const stop = keepScreenAwake(f.env, () => {});
    stop(); // before the request resolved
    await settle();
    expect(f.locks[0]?.released).toBe(true);
    expect(f.listenerCount()).toBe(0);

    const g = fakeEnv();
    const stop2 = keepScreenAwake(g.env, () => {});
    await settle();
    stop2();
    expect(g.locks[0]!.released).toBe(true);
  });
});
