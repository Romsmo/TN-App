import { TnError, type TnService } from '@/tn/service';
import type { OfflineRegion, OfflineSettings, StorageUsage } from '@/tn/types';

import { isLeaving, loadOfflineView, regionName, toggleRegion, usedBytes } from './offline';

const region = (over: Partial<OfflineRegion> = {}): OfflineRegion => ({
  id: 'de', country: 'DE', tileCount: 10, downloadBytes: 1, sizeBytes: 1, estimatedDeviceBytes: 5_000_000, complete: true, bbox: [0, 0, 1, 1], selected: false, storedTiles: 0, state: 'none', ...over,
});
const settings = (over: Partial<OfflineSettings> = {}): OfflineSettings => ({ mode: 'auto', regions: [], home: null, maxBytes: null, wifiOnly: false, ...over });

describe('toggleRegion', () => {
  it('adds and removes, keeping the order of choice', () => {
    expect(toggleRegion([], 'de')).toEqual(['de']);
    expect(toggleRegion(['de'], 'at')).toEqual(['de', 'at']);
    expect(toggleRegion(['de', 'at'], 'de')).toEqual(['at']);
  });
});

describe('regionName', () => {
  it('names a country in the app language, and falls back to the id', () => {
    expect(regionName(region(), 'de')).toBe('Deutschland');
    expect(regionName(region(), 'en')).toBe('Germany');
    expect(regionName(region({ id: 'z-12', country: null }), 'de')).toBe('z-12');
    expect(regionName(region({ id: 'x', country: '??' }), 'de')).toBe('x');
  });
});

describe('usedBytes / isLeaving', () => {
  const usage = (over: Partial<StorageUsage>): StorageUsage => ({ storedTiles: 1, storeBytes: null, storedJsonBytes: 0, estimatedDeviceBytes: 7, maxBytes: null, ...over });
  it('takes the real store size when known, else the estimate', () => {
    expect(usedBytes(usage({ storeBytes: 100 }))).toBe(100);
    expect(usedBytes(usage({}))).toBe(7);
  });
  it('knows a deselected, still stored region leaves with the next sync', () => {
    expect(isLeaving(region({ storedTiles: 3 }), settings({ mode: 'regions', regions: [] }))).toBe(true);
    expect(isLeaving(region({ storedTiles: 3 }), settings({ mode: 'regions', regions: ['de'] }))).toBe(false);
    expect(isLeaving(region({ storedTiles: 0 }), settings({ mode: 'regions', regions: [] }))).toBe(false);
    expect(isLeaving(region({ storedTiles: 3 }), settings({ mode: 'auto' }))).toBe(false);
  });
});

describe('loadOfflineView', () => {
  const service = (over: Record<string, jest.Mock>) =>
    ({
      getOfflineSettings: jest.fn().mockResolvedValue(settings()),
      getStorageUsage: jest.fn().mockResolvedValue({ storedTiles: 0, storeBytes: 0, storedJsonBytes: 0, estimatedDeviceBytes: 0, maxBytes: null }),
      listOfflineRegions: jest.fn().mockResolvedValue([region()]),
      getStoragePlan: jest.fn().mockResolvedValue({ needsLocation: false }),
      ...over,
    }) as unknown as TnService;

  it('reads all four parts', async () => {
    const view = await loadOfflineView(service({}));
    expect(view.settings?.mode).toBe('auto');
    expect(view.regions).toHaveLength(1);
    expect(view.needsConnection).toBe(false);
  });

  it('keeps the local parts and says a connection is needed when the region list and plan ask the server in vain', async () => {
    const offline = jest.fn().mockRejectedValue(new TnError('network', 'down'));
    const view = await loadOfflineView(service({ listOfflineRegions: offline, getStoragePlan: offline }));
    expect(view).toMatchObject({ regions: null, plan: null, needsConnection: true });
    expect(view.settings).not.toBeNull();
    expect(view.usage).not.toBeNull();
  });

  it('does not call another failure a connection problem', async () => {
    const view = await loadOfflineView(service({ getStoragePlan: jest.fn().mockRejectedValue(new TnError('internal', 'x')) }));
    expect(view).toMatchObject({ plan: null, needsConnection: false });
  });
});
