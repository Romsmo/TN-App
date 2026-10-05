import * as Location from 'expo-location';
import * as TaskManager from 'expo-task-manager';

import { t } from '@/i18n';

import type { PositionSource } from './drive-host';
import { nextRegime, samplingFor, type Sampling } from './sampling';
import type { Fix } from './warning-engine';

/** Name of the background location task. Runs only while a drive is on; the OS shows that it is running. */
export const DRIVE_LOCATION_TASK = 'tnviewer-drive-location';

let sink: ((fix: Fix) => void) | null = null;

/**
 * Must run at module load of the app (the task has to exist before the OS wakes the app for it).
 * The task only forwards fixes to the drive session that is running; with no drive it ignores them.
 */
export function defineDriveLocationTask(): void {
  if (TaskManager.isTaskDefined(DRIVE_LOCATION_TASK)) return;
  TaskManager.defineTask<{ locations: Location.LocationObject[] }>(DRIVE_LOCATION_TASK, async ({ data, error }) => {
    if (error || !data || !sink) return;
    for (const l of data.locations) {
      const speedMs = l.coords.speed;
      const heading = l.coords.heading;
      sink({
        lat: l.coords.latitude,
        lng: l.coords.longitude,
        speedKmh: speedMs !== null && speedMs >= 0 ? speedMs * 3.6 : null,
        heading: heading !== null && heading >= 0 ? heading : null,
        t: l.timestamp,
      });
    }
  });
}

const ACCURACY: Record<Sampling['accuracy'], Location.Accuracy> = {
  balanced: Location.Accuracy.Balanced,
  high: Location.Accuracy.High,
  navigation: Location.Accuracy.BestForNavigation,
};

/**
 * The device's location while the drive mode runs: "while using the app" permission, background updates with a visible
 * indicator (iOS) / foreground-service notification (Android), accuracy and rate adapted to the speed.
 * Nothing runs outside the drive mode: `stop` ends the updates.
 */
export function createLocationSource(): PositionSource {
  let regime: Sampling['regime'] | null = null;

  const begin = async (sampling: Sampling) => {
    await Location.startLocationUpdatesAsync(DRIVE_LOCATION_TASK, {
      accuracy: ACCURACY[sampling.accuracy],
      distanceInterval: sampling.distanceIntervalM,
      timeInterval: sampling.timeIntervalMs,
      activityType: Location.ActivityType.AutomotiveNavigation,
      pausesUpdatesAutomatically: false,
      showsBackgroundLocationIndicator: true,
      foregroundService: { notificationTitle: t('drive.notification.title'), notificationBody: t('drive.notification.body'), killServiceOnDestroy: true },
    });
    regime = sampling.regime;
  };

  return {
    async start(onFix) {
      const permission = await Location.requestForegroundPermissionsAsync();
      if (!permission.granted) throw new Error('location-permission-denied');
      sink = (fix) => {
        onFix(fix);
        // restart with other accuracy/rate only when the speed regime really changed
        const next = nextRegime(regime ?? 'crawl', fix.speedKmh);
        if (regime !== null && next !== regime) {
          const sampling = samplingFor(next === 'crawl' ? 0 : next === 'city' ? 40 : 100);
          regime = next;
          void Location.stopLocationUpdatesAsync(DRIVE_LOCATION_TASK).then(() => begin(sampling)).catch(() => undefined);
        }
      };
      await begin(samplingFor(null));
    },
    stop() {
      sink = null;
      regime = null;
      void Location.hasStartedLocationUpdatesAsync(DRIVE_LOCATION_TASK)
        .then((started) => (started ? Location.stopLocationUpdatesAsync(DRIVE_LOCATION_TASK) : undefined))
        .catch(() => undefined);
    },
  };
}
