/** Local, non-secret settings. They live in an ordinary app file, never in the Keychain: that survives a reinstall on iOS. */
export type Settings = {
  /** A server the user entered ("Server verbinden"); null = use discovery from the built-in seeds. */
  serverAddress: string | null;
  /** Hazard types the user switched off in the map filter. Stored as "hidden", so a new type shows up by default. */
  hiddenHazardTypes: string[];
  /** Download data packages on Wi-Fi only. */
  dataWifiOnly: boolean;
};

export const DEFAULT_SETTINGS: Settings = {
  serverAddress: null,
  hiddenHazardTypes: [],
  dataWifiOnly: true,
};

/** Reads stored JSON tolerantly: anything missing or of the wrong type falls back to the default. */
export function parseSettings(raw: string | null | undefined): Settings {
  let data: unknown;
  try {
    data = raw ? JSON.parse(raw) : {};
  } catch {
    data = {};
  }
  const o = (typeof data === 'object' && data !== null ? data : {}) as Record<string, unknown>;
  return {
    serverAddress: typeof o.serverAddress === 'string' && o.serverAddress ? o.serverAddress : DEFAULT_SETTINGS.serverAddress,
    hiddenHazardTypes: Array.isArray(o.hiddenHazardTypes)
      ? o.hiddenHazardTypes.filter((v): v is string => typeof v === 'string')
      : DEFAULT_SETTINGS.hiddenHazardTypes,
    dataWifiOnly: typeof o.dataWifiOnly === 'boolean' ? o.dataWifiOnly : DEFAULT_SETTINGS.dataWifiOnly,
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
