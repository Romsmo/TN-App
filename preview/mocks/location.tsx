export const Accuracy = { Balanced: 3, High: 4, BestForNavigation: 6 };
export const ActivityType = { AutomotiveNavigation: 2 };
const granted = { granted: true, status: 'granted', canAskAgain: true, expires: 'never' };
export async function requestForegroundPermissionsAsync() {
  return granted;
}
export async function getForegroundPermissionsAsync() {
  return granted;
}
export async function getCurrentPositionAsync() {
  return { coords: { latitude: 48.2, longitude: 11.6, speed: 0, heading: 0, accuracy: 5 }, timestamp: Date.now() };
}
export async function startLocationUpdatesAsync(): Promise<void> {}
export async function stopLocationUpdatesAsync(): Promise<void> {}
export async function hasStartedLocationUpdatesAsync(): Promise<boolean> {
  return false;
}
