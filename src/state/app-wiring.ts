/** Connects the app to the device: the native library client, the Keychain, the network type. Not loaded by unit tests. */
import * as Network from 'expo-network';

import { createCredentialsStore } from '@/tn/credentials';
import { createNativeClient, deleteLibraryData, wipeLibrarySecrets, secureStore } from '@/tn/native';
import type { Maintenance } from './tn-provider';

export { createNativeClient };

export const credentialsStore = createCredentialsStore(secureStore);

/** Wi-Fi and Ethernet count as unmetered. A failing check counts as "not on Wi-Fi": the cautious answer. */
export async function isOnWifi(): Promise<boolean> {
  try {
    const { type } = await Network.getNetworkStateAsync();
    return type === Network.NetworkStateType.WIFI || type === Network.NetworkStateType.ETHERNET;
  } catch {
    return false;
  }
}

/** The device-level parts of "delete local data" and "reset device identity". */
export const maintenance: Maintenance = {
  deleteLocalData: async () => deleteLibraryData(),
  wipeSecrets: wipeLibrarySecrets,
};
