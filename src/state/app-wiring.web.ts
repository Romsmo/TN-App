/** The browser counterpart of `app-wiring.ts`: the web library client, the browser's storage, the connection type. */
import { createCredentialsStore } from '@/tn/credentials';
import { createNativeClient, deleteLibraryData, wipeLibrarySecrets, secureStore } from '@/tn/native';
import type { Maintenance } from './tn-provider';

export { createNativeClient };

export const credentialsStore = createCredentialsStore(secureStore);

/**
 * Whether the connection is unmetered. A browser can only tell on some systems (`navigator.connection.type`, Chrome on
 * Android); everywhere else the type is unknown, and "unknown" counts as unmetered here: asking the user to choose "Wi-Fi
 * only" and then never loading anything would be worse than loading. Stated in docs/web-limits.md.
 */
export async function isOnWifi(): Promise<boolean> {
  const connection = (navigator as { connection?: { type?: string; saveData?: boolean } }).connection;
  if (connection?.saveData) return false;
  return connection?.type !== 'cellular';
}

export const maintenance: Maintenance = {
  deleteLocalData: async () => {
    await deleteLibraryData();
  },
  wipeSecrets: wipeLibrarySecrets,
};
