/** Connects the app to the device: the native library client, the Keychain, the network type. Not loaded by unit tests. */
import * as Network from 'expo-network';

import { createCredentialsStore } from '@/tn/credentials';
import { createNativeClient, secureStore } from '@/tn/native';

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
