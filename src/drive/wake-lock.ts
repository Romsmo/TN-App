/** What a screen wake lock needs from the page. Real objects in the browser, fakes in tests. */
export interface WakeLockEnv {
  request: (() => Promise<{ release(): Promise<void> | void; addEventListener(type: 'release', listener: () => void): void }>) | null;
  isVisible(): boolean;
  onVisibilityChange(listener: () => void): () => void;
}

export type WakeLockState = 'active' | 'lost' | 'unavailable';

/**
 * Keeps the screen awake while the drive mode runs, in a browser. A browser releases the lock whenever the page goes to
 * the background, so it is requested again when the page comes back; a failed request (not supported, refused, low
 * battery) is a state the screen can show instead of an unhandled rejection. Returns `stop`.
 */
export function keepScreenAwake(env: WakeLockEnv, onState: (state: WakeLockState) => void): () => void {
  if (!env.request) {
    onState('unavailable');
    return () => undefined;
  }
  let stopped = false;
  let sentinel: { release(): Promise<void> | void } | null = null;
  let requesting = false;

  const acquire = async () => {
    if (stopped || sentinel || requesting || !env.isVisible() || !env.request) return;
    requesting = true;
    try {
      const lock = await env.request();
      if (stopped) {
        void lock.release();
        return;
      }
      sentinel = lock;
      lock.addEventListener('release', () => {
        sentinel = null;
        if (!stopped) onState('lost');
      });
      onState('active');
    } catch {
      onState('lost');
    } finally {
      requesting = false;
    }
  };

  const stopListening = env.onVisibilityChange(() => void acquire());
  void acquire();
  return () => {
    stopped = true;
    stopListening();
    void sentinel?.release();
    sentinel = null;
  };
}
