import type { TnService } from '@/tn/service';
import type { NearbyItem, SpeedLimitAnswer } from '@/tn/types';

/** What the drive session reads. The library backs it on a real drive, `sim/sim-data.ts` in the simulation. */
export interface DriveDataSource {
  nearby(lat: number, lng: number, radiusM: number): Promise<NearbyItem[]>;
  speedLimit(lat: number, lng: number, heading: number | null): Promise<SpeedLimitAnswer | null>;
}

/**
 * Local reads only: the library answers both from its store without touching the network.
 * The client is looked up at every call: it is rebuilt when server, access or camera settings change, and a drive
 * that is on must not keep talking to a closed one.
 */
export function libraryDataSource(getService: () => TnService | null): DriveDataSource {
  return {
    nearby: async (lat, lng, radiusM) => (await getService()?.getNearby(lat, lng, radiusM)) ?? [],
    speedLimit: async (lat, lng, heading) => (await getService()?.getSpeedLimitAt(lat, lng, heading ?? undefined)) ?? null,
  };
}
