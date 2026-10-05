/** Builds the drive host for the app: library data on a real drive, invented data in the simulation. Not loaded by unit tests. */
import { DriveHost } from '@/drive/drive-host';
import { DriveSession, type DriveSettings } from '@/drive/drive-session';
import { libraryDataSource, type DriveDataSource } from '@/drive/data-source';
import { createNativeFeedback } from '@/drive/feedback-native';
import { createLocationSource } from '@/drive/location-source';
import { createSimSource, demoRoute } from '@/drive/sim/sim-source';
import { createSimDataSource } from '@/drive/sim/sim-data';
import { submitHazard, voteOnReport } from '@/report/submit';
import { settingsStore } from '@/settings';
import type { TnService } from '@/tn/service';

const emptyData: DriveDataSource = { nearby: async () => [], speedLimit: async () => null };

function driveSettings(): DriveSettings {
  const s = settingsStore.get();
  return { unit: s.speedUnit, sound: s.driveSound, voice: s.driveVoice, warnOff: s.warnOffCategories, scale: s.warnScale, lockEnabled: s.driveLockEnabled };
}

let currentService: TnService | null = null;

/** The app tells the wiring which library client is current (it is rebuilt when the server or access changes). */
export function setDriveService(service: TnService | null): void {
  currentService = service;
}

export function createAppDriveHost(getService: () => TnService | null = () => currentService): DriveHost {
  const feedback = createNativeFeedback();
  return new DriveHost({
    createSession: (simulated) => {
      const service = getService();
      const data = simulated ? createSimDataSource(demoRoute, { camerasEnabled: settingsStore.get().camerasEnabled }) : service ? libraryDataSource(service) : emptyData;
      return new DriveSession({
        data,
        feedback,
        getSettings: driveSettings,
        now: Date.now,
        simulated,
        // A simulated drive must never put invented reports or votes into the real queue.
        submitReport: async (type, position) => {
          if (simulated) return true;
          const current = getService();
          return current ? (await submitHazard(current, type, position)).ok : false;
        },
        vote: async (reportId, stillThere) => {
          if (simulated) return true;
          const current = getService();
          return current ? (await voteOnReport(current, reportId, stillThere)).ok : false;
        },
      });
    },
    realSource: createLocationSource,
    simSource: (speedup) => createSimSource(speedup),
    setInterval: (fn, ms) => setInterval(fn, ms),
    clearInterval: (handle) => clearInterval(handle as ReturnType<typeof setInterval>),
  });
}
