import * as Location from 'expo-location';
import * as TaskManager from 'expo-task-manager';

import { t } from '@/i18n';

import type { LocationBackend } from './location-source';
import type { Sampling } from './sampling';
import type { Fix } from './warning-engine';

/** Name of the background location task. Runs only while a drive is on; the OS shows that it is running. */
export const DRIVE_LOCATION_TASK = 'tnviewer-drive-location';

let sink: ((fix: Fix) => void) | null = null;

/**
 * Must run at module load of the app (the task has to exist before the OS wakes the app for it).
 * The task only forwards fixes to the drive that is running; with no drive it ignores them.
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
 * "While using the app" permission; updates continue in the background because the user started them (iOS: background
 * mode `location` with the status indicator, no "Always" needed, read in expo-location's source; Android: foreground service).
 */
export const expoLocationBackend: LocationBackend = {
  setSink(fn) {
    sink = fn;
  },
  async requestPermission() {
    return (await Location.requestForegroundPermissionsAsync()).granted;
  },
  async start(sampling) {
    await Location.startLocationUpdatesAsync(DRIVE_LOCATION_TASK, {
      accuracy: ACCURACY[sampling.accuracy],
      distanceInterval: sampling.distanceIntervalM,
      timeInterval: sampling.timeIntervalMs,
      activityType: Location.ActivityType.AutomotiveNavigation,
      pausesUpdatesAutomatically: false,
      showsBackgroundLocationIndicator: true,
      foregroundService: { notificationTitle: t('drive.notification.title'), notificationBody: t('drive.notification.body'), killServiceOnDestroy: true },
    });
  },
  async stop() {
    if (await Location.hasStartedLocationUpdatesAsync(DRIVE_LOCATION_TASK)) await Location.stopLocationUpdatesAsync(DRIVE_LOCATION_TASK);
  },
};
