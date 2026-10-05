import { ALLOW_DISABLE_DRIVE_LOCK } from '@/config';

/** Local, non-secret settings. They live in an ordinary app file, never in the Keychain: that survives a reinstall on iOS. */
export type Settings = {
  /** A server the user entered ("Server verbinden"); null = use discovery from the built-in seeds. */
  serverAddress: string | null;
  /** Hazard types the user switched off in the map filter. Stored as "hidden", so a new type shows up by default. */
  hiddenHazardTypes: string[];
  /** Download data packages on Wi-Fi only. */
  dataWifiOnly: boolean;
  speedUnit: 'kmh' | 'mph';
  /** Tones and spoken warnings in the drive mode. */
  driveSound: boolean;
  driveVoice: boolean;
  /** Categories (hazard types, `cameras`) without drive-mode warnings. Stored as "off", so new types warn by default. */
  warnOffCategories: string[];
  /** Stretches or shrinks the warning distances. */
  warnScale: 0.75 | 1 | 1.5;
  /** The speed-camera category, like the checkbox on the web page: off at first start. */
  camerasEnabled: boolean;
  /** Version of the speed-camera notice the user has seen; null = never. */
  camerasNoticeSeen: string | null;
  /** The legal notice at the first start of the drive mode was shown. */
  driveNoticeSeen: boolean;
  /** The speed lock. On by default, also on a fresh install (no settings file) and after resetting the device identity. */
  driveLockEnabled: boolean;
};

export const DEFAULT_SETTINGS: Settings = {
  serverAddress: null,
  hiddenHazardTypes: [],
  dataWifiOnly: true,
  speedUnit: 'kmh',
  driveSound: true,
  driveVoice: true,
  warnOffCategories: [],
  warnScale: 1,
  camerasEnabled: false,
  camerasNoticeSeen: null,
  driveNoticeSeen: false,
  driveLockEnabled: true,
};

const stringList = (value: unknown, fallback: string[]): string[] =>
  Array.isArray(value) ? value.filter((v): v is string => typeof v === 'string') : fallback;
const bool = (value: unknown, fallback: boolean): boolean => (typeof value === 'boolean' ? value : fallback);

/** Reads stored JSON tolerantly: anything missing or of the wrong type falls back to the default. */
export function parseSettings(raw: string | null | undefined): Settings {
  let data: unknown;
  try {
    data = raw ? JSON.parse(raw) : {};
  } catch {
    data = {};
  }
  const o = (typeof data === 'object' && data !== null ? data : {}) as Record<string, unknown>;
  const d = DEFAULT_SETTINGS;
  return {
    serverAddress: typeof o.serverAddress === 'string' && o.serverAddress ? o.serverAddress : d.serverAddress,
    hiddenHazardTypes: stringList(o.hiddenHazardTypes, d.hiddenHazardTypes),
    dataWifiOnly: bool(o.dataWifiOnly, d.dataWifiOnly),
    speedUnit: o.speedUnit === 'mph' ? 'mph' : 'kmh',
    driveSound: bool(o.driveSound, d.driveSound),
    driveVoice: bool(o.driveVoice, d.driveVoice),
    warnOffCategories: stringList(o.warnOffCategories, d.warnOffCategories),
    warnScale: o.warnScale === 0.75 || o.warnScale === 1.5 ? o.warnScale : 1,
    camerasEnabled: bool(o.camerasEnabled, d.camerasEnabled),
    camerasNoticeSeen: typeof o.camerasNoticeSeen === 'string' && o.camerasNoticeSeen ? o.camerasNoticeSeen : null,
    driveNoticeSeen: bool(o.driveNoticeSeen, d.driveNoticeSeen),
    // Only an explicit `false` switches the lock off; garbage or a missing value means "on".
    driveLockEnabled: ALLOW_DISABLE_DRIVE_LOCK && o.driveLockEnabled === false ? false : true,
  };
}

export interface SettingsStorage {
  read(): string | null;
  write(value: string): void;
  remove(): void;
}

export interface SettingsStore {
  get(): Settings;
  update(patch: Partial<Settings>): void;
  /** "Lokale Daten löschen": back to the defaults. */
  reset(): void;
  subscribe(listener: () => void): () => void;
}

export function createSettingsStore(storage: SettingsStorage): SettingsStore {
  let current = parseSettings(storage.read());
  const listeners = new Set<() => void>();
  const emit = () => listeners.forEach((l) => l());
  return {
    get: () => current,
    update(patch) {
      current = parseSettings(JSON.stringify({ ...current, ...patch }));
      storage.write(JSON.stringify(current));
      emit();
    },
    reset() {
      current = { ...DEFAULT_SETTINGS };
      storage.remove();
      emit();
    },
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
  };
}
