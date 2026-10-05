import { File, Paths } from 'expo-file-system';

import type { SettingsStorage } from './settings';

/** Settings in `<documents>/settings.json`. Failures read as "nothing stored" and never crash the app. */
export function createFileStorage(): SettingsStorage {
  const file = new File(Paths.document, 'settings.json');
  return {
    read() {
      try {
        return file.exists ? file.textSync() : null;
      } catch {
        return null;
      }
    },
    write(value) {
      try {
        if (!file.exists) file.create({ intermediates: true });
        file.write(value);
      } catch {
        // settings are a convenience; the in-memory value stays valid for this run
      }
    },
    remove() {
      try {
        if (file.exists) file.delete();
      } catch {
        // see write
      }
    },
  };
}
