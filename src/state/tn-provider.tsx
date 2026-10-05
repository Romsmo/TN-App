import { createContext, useContext, useEffect, useMemo, useSyncExternalStore } from 'react';

import { TICK_INTERVAL_MS } from '@/config';
import { useSettings } from '@/settings';
import type { CredentialsStore } from '@/tn/credentials';
import { buildClientOptions } from '@/tn/options';
import type { RawClient } from '@/tn/service';
import type { ClientOptions } from '@/tn/types';

import { TnConnection, type ConnectionSnapshot } from './connection';

export type { Phase } from './connection';

export type TnState = ConnectionSnapshot & {
  credentialsStore: CredentialsStore;
  syncNow(options?: { ignoreWifi?: boolean }): Promise<void>;
};

const TnContext = createContext<TnState | null>(null);

export function useTn(): TnState {
  const state = useContext(TnContext);
  if (!state) throw new Error('useTn must be used inside <TnProvider>');
  return state;
}

type Props = {
  children: React.ReactNode;
  /** Builds the library client; the native one in the app, a fake in tests. */
  createClient: (options: Omit<ClientOptions, 'storagePath'>) => RawClient;
  credentialsStore: CredentialsStore;
  isOnWifi: () => Promise<boolean>;
  tickIntervalMs?: number;
};

/** Runs one library client for the current server and access settings and hands its state to the screens. */
export function TnProvider({ children, createClient, credentialsStore, isOnWifi, tickIntervalMs = TICK_INTERVAL_MS }: Props) {
  const { serverAddress, dataWifiOnly } = useSettings();
  const credentials = useSyncExternalStore(credentialsStore.subscribe, credentialsStore.get);

  const connection = useMemo(
    () => new TnConnection({ createClient, options: buildClientOptions({ serverAddress, credentials }), isOnWifi, tickIntervalMs }),
    [createClient, serverAddress, credentials, isOnWifi, tickIntervalMs],
  );

  // Declared before the start effect, so the first sync already sees the current "Wi-Fi only" choice.
  useEffect(() => {
    connection.setWifiOnly(dataWifiOnly);
  }, [connection, dataWifiOnly]);

  useEffect(() => {
    connection.start();
    return () => connection.stop();
  }, [connection]);

  const snapshot = useSyncExternalStore(connection.subscribe, connection.getSnapshot);
  const value = useMemo<TnState>(
    () => ({ ...snapshot, credentialsStore, syncNow: connection.syncNow }),
    [snapshot, credentialsStore, connection],
  );
  return <TnContext.Provider value={value}>{children}</TnContext.Provider>;
}
