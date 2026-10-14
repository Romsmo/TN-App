import { useKeepAwake } from 'expo-keep-awake';

import type { WakeLockState } from './wake-lock';

/** Keeps the screen on while the drive mode runs. Native: the system does it, so it is always "active". */
export function useDriveWakeLock(): WakeLockState {
  useKeepAwake();
  return 'active';
}
