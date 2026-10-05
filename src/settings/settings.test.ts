import { createSettingsStore, DEFAULT_SETTINGS, parseSettings, type SettingsStorage } from './settings';

function memoryStorage(initial: string | null = null): SettingsStorage & { value: string | null } {
  const storage = {
    value: initial,
    read: () => storage.value,
    write: (v: string) => {
      storage.value = v;
    },
    remove: () => {
      storage.value = null;
    },
  };
  return storage;
}

describe('parseSettings', () => {
  it('uses the defaults for nothing, garbage and wrong types', () => {
    expect(parseSettings(null)).toEqual(DEFAULT_SETTINGS);
    expect(parseSettings('not json')).toEqual(DEFAULT_SETTINGS);
    expect(parseSettings('[1,2]')).toEqual(DEFAULT_SETTINGS);
    expect(parseSettings(JSON.stringify({ serverAddress: 5, hiddenHazardTypes: 'x', dataWifiOnly: 'yes' }))).toEqual(DEFAULT_SETTINGS);
  });

  it('starts with Wi-Fi only on, no filter and no own server', () => {
    expect(DEFAULT_SETTINGS).toEqual({ serverAddress: null, hiddenHazardTypes: [], dataWifiOnly: true });
  });

  it('keeps valid values and drops unknown ones', () => {
    const parsed = parseSettings(JSON.stringify({ serverAddress: 'https://a.example', hiddenHazardTypes: ['ice', 4], extra: 1 }));
    expect(parsed).toEqual({ serverAddress: 'https://a.example', hiddenHazardTypes: ['ice'], dataWifiOnly: true });
  });
});

describe('settings store', () => {
  it('persists updates and tells listeners', () => {
    const storage = memoryStorage();
    const store = createSettingsStore(storage);
    const listener = jest.fn();
    store.subscribe(listener);
    store.update({ dataWifiOnly: false });
    expect(store.get().dataWifiOnly).toBe(false);
    expect(listener).toHaveBeenCalledTimes(1);
    expect(createSettingsStore(storage).get().dataWifiOnly).toBe(false);
  });

  it('resets to the defaults and removes the file', () => {
    const storage = memoryStorage();
    const store = createSettingsStore(storage);
    store.update({ serverAddress: 'https://a.example' });
    store.reset();
    expect(store.get()).toEqual(DEFAULT_SETTINGS);
    expect(storage.value).toBeNull();
  });

  it('stops notifying after unsubscribe', () => {
    const store = createSettingsStore(memoryStorage());
    const listener = jest.fn();
    const unsubscribe = store.subscribe(listener);
    unsubscribe();
    store.update({ dataWifiOnly: false });
    expect(listener).not.toHaveBeenCalled();
  });
});
