import { createContext, useCallback, useContext, useEffect, useMemo, useState, useSyncExternalStore } from 'react';

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
  dismissRejected(): void;
  /** Deletes the library's database on this device (it is learned again from the server) and restarts the client. */
  resetLocalData(): Promise<void>;
  /** Deletes the device's credential and signing key from the Keychain/Keystore and the local database; the device registers anew. */
  resetDeviceIdentity(): Promise<void>;
};

/** The device-level operations behind the two reset actions; native in the app, fakes in tests. */
export type Maintenance = {
  deleteLocalData(): Promise<void>;
  wipeSecrets(): Promise<void>;
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
  maintenance?: Maintenance;
};

/** Runs one library client for the current server and access settings and hands its state to the screens. */
export function TnProvider({ children, createClient, credentialsStore, isOnWifi, tickIntervalMs = TICK_INTERVAL_MS, maintenance }: Props) {
  const { serverAddress, dataWifiOnly, camerasEnabled } = useSettings();
  const [generation, setGeneration] = useState(0);
  const credentials = useSyncExternalStore(credentialsStore.subscribe, credentialsStore.get);

  const connection = useMemo(
    () => new TnConnection({ createClient, options: buildClientOptions({ serverAddress, credentials, cameraNamespaceEnabled: camerasEnabled }), isOnWifi, tickIntervalMs }),
    // `generation` is not read inside: it only forces a fresh client after a reset
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [createClient, serverAddress, credentials, camerasEnabled, isOnWifi, tickIntervalMs, generation],
  );

  // Declared before the start effect, so the first sync already sees the current "Wi-Fi only" choice.
  useEffect(() => {
    connection.setWifiOnly(dataWifiOnly);
  }, [connection, dataWifiOnly]);

  useEffect(() => {
    connection.start();
    return () => connection.stop();
  }, [connection]);

  const resetLocalData = useCallback(async () => {
    connection.stop(); // closes the client, so its database files can be removed
    await maintenance?.deleteLocalData();
    setGeneration((g) => g + 1);
  }, [connection, maintenance]);

  const resetDeviceIdentity = useCallback(async () => {
    connection.stop();
    await maintenance?.wipeSecrets();
    await maintenance?.deleteLocalData();
    setGeneration((g) => g + 1);
  }, [connection, maintenance]);

  const snapshot = useSyncExternalStore(connection.subscribe, connection.getSnapshot);
  const value = useMemo<TnState>(
    () => ({ ...snapshot, credentialsStore, syncNow: connection.syncNow, dismissRejected: connection.dismissRejected, resetLocalData, resetDeviceIdentity }),
    [snapshot, credentialsStore, connection, resetLocalData, resetDeviceIdentity],
  );
  return <TnContext.Provider value={value}>{children}</TnContext.Provider>;
}
