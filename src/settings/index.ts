import { useSyncExternalStore } from 'react';

import { createFileStorage } from './file-storage';
import { createSettingsStore, type Settings, type SettingsStore } from './settings';

export const settingsStore: SettingsStore = createSettingsStore(createFileStorage());

export function useSettings(): Settings {
  return useSyncExternalStore(settingsStore.subscribe, settingsStore.get);
}

export type { Settings };
