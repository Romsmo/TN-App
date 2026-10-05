export type SyncGate = {
  /** The user's "download data packages on Wi-Fi only" choice. */
  wifiOnly: boolean;
  onWifi: boolean;
  /** From `planBootstrap`: how much static data is still to download; null = not known yet. */
  bytesPending: number | null;
};

/**
 * Whether the app lets the library sync now. Live reports are tiny and always allowed; the static data packages are
 * the big download, and with "Wi-Fi only" they wait for Wi-Fi. The library cannot split the two, so the app decides
 * before it calls `tick`.
 */
export function shouldSync({ wifiOnly, onWifi, bytesPending }: SyncGate): boolean {
  if (!wifiOnly || onWifi) return true;
  return bytesPending === 0;
}
