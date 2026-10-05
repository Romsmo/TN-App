export const NetworkStateType = { WIFI: 'WIFI', ETHERNET: 'ETHERNET', CELLULAR: 'CELLULAR' };
export async function getNetworkStateAsync() {
  return { type: 'WIFI', isConnected: true, isInternetReachable: true };
}
