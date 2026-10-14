import { useEffect, useState } from 'react';

import { keepScreenAwake, type WakeLockEnv, type WakeLockState } from './wake-lock';

function browserEnv(): WakeLockEnv {
  const wakeLock = 'wakeLock' in navigator ? navigator.wakeLock : null;
  return {
    request: wakeLock ? () => wakeLock.request('screen') : null,
    isVisible: () => document.visibilityState === 'visible',
    onVisibilityChange: (listener) => {
      document.addEventListener('visibilitychange', listener);
      return () => document.removeEventListener('visibilitychange', listener);
    },
  };
}

/** The browser's Screen Wake Lock, held while the drive mode is on and asked for again after the page was in the background. */
export function useDriveWakeLock(): WakeLockState {
  const [state, setState] = useState<WakeLockState>('active');
  useEffect(() => keepScreenAwake(browserEnv(), setState), []);
  return state;
}
