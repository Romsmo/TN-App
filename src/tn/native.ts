/**
 * The only file that imports the client library. Everything else talks to `RawClient` / `TnService`,
 * so tests and Storybook-like previews never load native code.
 */
import { libraryVersion, TrafficNetworkClient } from '@trafficnetwork/react-native';
import { Directory, Paths } from 'expo-file-system';
import * as SecureStore from 'expo-secure-store';

import { createSecureStore, type LibrarySecureStore } from './secure-store';
import type { RawClient } from './service';
import type { ClientOptions } from './types';

/** Keychain service name, so the app's own items are kept apart. */
const KEYCHAIN_SERVICE = 'info.trafficnetwork.tnviewer';

export const secureStore: ReturnType<typeof createSecureStore> = createSecureStore({
  getItem: (key) => SecureStore.getItem(key, { keychainService: KEYCHAIN_SERVICE }),
  setItem: (key, value) => SecureStore.setItem(key, value, { keychainService: KEYCHAIN_SERVICE }),
});

/** Removes everything the library stored in the Keychain/Keystore (device credential and signing key). */
export async function wipeLibrarySecrets(): Promise<void> {
  for (const key of secureStore.keys()) {
    await SecureStore.deleteItemAsync(key, { keychainService: KEYCHAIN_SERVICE });
  }
}

/** Deletes the library's database directory. Close the client first. */
export function deleteLibraryData(): void {
  const dir = new Directory(Paths.document, 'trafficnetwork');
  if (dir.exists) dir.delete();
}

/** The directory the library keeps its database in, created if missing. */
export function libraryStoragePath(): string {
  const dir = new Directory(Paths.document, 'trafficnetwork');
  if (!dir.exists) dir.create({ intermediates: true, idempotent: true });
  return dir.uri.replace(/^file:\/\//, '').replace(/\/$/, '');
}

export function createNativeClient(options: Omit<ClientOptions, 'storagePath'>): RawClient {
  const store: LibrarySecureStore = secureStore;
  const client = new TrafficNetworkClient(
    JSON.stringify({ ...options, storagePath: libraryStoragePath() }),
    {
      get: (key: string) => store.get(key),
      set: (key: string, value: string) => store.set(key, value),
      delete_: (key: string) => store.delete_(key),
    },
  );
  return {
    callAsync: (method, argsJson) => client.callAsync(method, argsJson),
    startRealtime: () => client.startRealtime(),
    stopRealtime: () => client.stopRealtime(),
    setEventListener: (listener) => client.setEventListener(listener),
    uniffiDestroy: () => client.uniffiDestroy(),
  };
}

/** Version of the bundled library, for the info screen. */
export function getLibraryVersion(): string {
  return libraryVersion();
}
