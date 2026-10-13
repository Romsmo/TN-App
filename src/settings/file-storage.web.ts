import type { SettingsStorage } from './settings';

const KEY = 'tnviewer.settings';

/** The browser counterpart of the settings file: one `localStorage` entry. Failures read as "nothing stored", never crash. */
export function createFileStorage(): SettingsStorage {
  return {
    read() {
      try {
        return localStorage.getItem(KEY);
      } catch {
        return null;
      }
    },
    write(value) {
      try {
        localStorage.setItem(KEY, value);
      } catch {
        // settings are a convenience; the in-memory value stays valid for this visit
      }
    },
    remove() {
      try {
        localStorage.removeItem(KEY);
      } catch {
        // see write
      }
    },
  };
}
