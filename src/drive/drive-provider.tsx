import { createContext, useContext, useSyncExternalStore } from 'react';

import { useSettings } from '@/settings';

import type { DriveHost } from './drive-host';
import type { DriveSnapshot } from './drive-session';
import { isLockActive } from './lock';

const DriveContext = createContext<DriveHost | null>(null);

export function DriveProvider({ host, children }: { host: DriveHost; children: React.ReactNode }) {
  return <DriveContext.Provider value={host}>{children}</DriveContext.Provider>;
}

export function useDriveHost(): DriveHost {
  const host = useContext(DriveContext);
  if (!host) throw new Error('useDriveHost must be used inside <DriveProvider>');
  return host;
}

/** The running drive's state, or null when no drive is on. */
export function useDriveSnapshot(): DriveSnapshot | null {
  const host = useDriveHost();
  return useSyncExternalStore(host.subscribe, host.getSnapshot);
}

/**
 * Whether settings, text input and server pages are locked right now: a drive is on, the lock setting is on, and the
 * car is moving. The speed comes from the drive session; the setting is read live, so switching the lock on again
 * takes effect at once.
 */
export function useLockActive(): boolean {
  const snapshot = useDriveSnapshot();
  const { driveLockEnabled } = useSettings();
  return isLockActive({ driving: snapshot?.active === true, lockEnabled: driveLockEnabled, locked: snapshot?.speedLocked === true });
}
