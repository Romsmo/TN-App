import type { TnService } from '@/tn/service';
import type { NearbyItem, SpeedLimitAnswer } from '@/tn/types';

/** What the drive session reads. The library backs it on a real drive, `sim/sim-data.ts` in the simulation. */
export interface DriveDataSource {
  nearby(lat: number, lng: number, radiusM: number): Promise<NearbyItem[]>;
  speedLimit(lat: number, lng: number, heading: number | null): Promise<SpeedLimitAnswer | null>;
}

/** Local reads only: the library answers both from its store without touching the network. */
export function libraryDataSource(service: TnService): DriveDataSource {
  return {
    nearby: (lat, lng, radiusM) => service.getNearby(lat, lng, radiusM),
    speedLimit: (lat, lng, heading) => service.getSpeedLimitAt(lat, lng, heading ?? undefined),
  };
}
