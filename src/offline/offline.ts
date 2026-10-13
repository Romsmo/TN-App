import type { TnService } from '@/tn/service';
import { TnError } from '@/tn/service';
import type { OfflineRegion, OfflineSettings, StoragePlan, StorageUsage } from '@/tn/types';

/** What the "Offline-Daten" screen shows. A part the library could not answer (no connection) is null, never made up. */
export type OfflineView = {
  settings: OfflineSettings | null;
  /** The server's regions; needs a connection. */
  regions: OfflineRegion[] | null;
  plan: StoragePlan | null;
  usage: StorageUsage | null;
  /** The region list or the plan could not be read because the server is not reachable. */
  needsConnection: boolean;
};

async function attempt<T>(read: () => Promise<T>): Promise<{ value: T | null; offline: boolean }> {
  try {
    return { value: await read(), offline: false };
  } catch (error) {
    // `network` is the library's honest "no server"; other errors are not a connection matter, but the screen has nothing to show either.
    return { value: null, offline: error instanceof TnError && (error.code === 'network' || error.code === 'unavailable') };
  }
}

/** Reads settings and usage (local) and the region list and plan (they ask the server). */
export async function loadOfflineView(service: TnService): Promise<OfflineView> {
  const [settings, usage, regions, plan] = await Promise.all([
    attempt(() => service.getOfflineSettings()),
    attempt(() => service.getStorageUsage()),
    attempt(() => service.listOfflineRegions()),
    attempt(() => service.getStoragePlan()),
  ]);
  return {
    settings: settings.value,
    usage: usage.value,
    regions: regions.value,
    plan: plan.value,
    needsConnection: regions.offline || plan.offline,
  };
}

/** The region ids after switching one: chosen regions stay in the order they were chosen. */
export function toggleRegion(selected: readonly string[], id: string): string[] {
  return selected.includes(id) ? selected.filter((r) => r !== id) : [...selected, id];
}

/** A name for a region: the country's own name in the app language where the server says which country, otherwise the id. */
export function regionName(region: OfflineRegion, language: string): string {
  if (region.country) {
    try {
      const name = new Intl.DisplayNames([language], { type: 'region' }).of(region.country);
      if (name) return name;
    } catch {
      // an unknown code: fall through to the id
    }
  }
  return region.id;
}

/** Sizes the user can cap the offline data at (bytes); null = no limit. */
export const LIMIT_CHOICES: readonly (number | null)[] = [null, 500_000_000, 1_000_000_000, 2_000_000_000];

/** Bytes the device really holds right now: the store's own size where known, else the library's estimate. */
export function usedBytes(usage: StorageUsage): number {
  return usage.storeBytes ?? usage.estimatedDeviceBytes;
}

/** Whether a deselected region is still on the device and goes with the next sync. */
export function isLeaving(region: OfflineRegion, settings: OfflineSettings): boolean {
  return settings.mode === 'regions' && !settings.regions.includes(region.id) && region.storedTiles > 0;
}
