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
    expect(parseSettings(JSON.stringify({ serverAddress: 5, hiddenHazardTypes: 'x', dataWifiOnly: 'yes', speedUnit: 'knots', warnScale: 3, camerasEnabled: 'yes' }))).toEqual(DEFAULT_SETTINGS);
  });

  it('starts with Wi-Fi only on, no filter, no own server, cameras off, notices unseen and the speed lock on', () => {
    expect(DEFAULT_SETTINGS).toMatchObject({
      serverAddress: null,
      hiddenHazardTypes: [],
      dataWifiOnly: true,
      camerasEnabled: false,
      camerasNoticeSeen: null,
      driveNoticeSeen: false,
      driveLockEnabled: true,
      speedUnit: 'kmh',
    });
  });

  it('keeps valid values and drops unknown ones', () => {
    const parsed = parseSettings(JSON.stringify({ serverAddress: 'https://a.example', hiddenHazardTypes: ['ice', 4], extra: 1, speedUnit: 'mph', warnScale: 1.5 }));
    expect(parsed).toMatchObject({ serverAddress: 'https://a.example', hiddenHazardTypes: ['ice'], speedUnit: 'mph', warnScale: 1.5 });
    expect(parsed).not.toHaveProperty('extra');
  });

  describe('the speed lock', () => {
    it.each([
      [null, true],
      ['{}', true],
      ['not json', true],
      [JSON.stringify({ driveLockEnabled: true }), true],
      [JSON.stringify({ driveLockEnabled: 'false' }), true], // only a real boolean false counts
      [JSON.stringify({ driveLockEnabled: 0 }), true],
      [JSON.stringify({ driveLockEnabled: null }), true],
      [JSON.stringify({ driveLockEnabled: false }), false],
    ])('stored %s reads as lock enabled = %s', (raw, expected) => {
      expect(parseSettings(raw).driveLockEnabled).toBe(expected);
    });

    it('is on again on a fresh install, where no settings file exists', () => {
      expect(createSettingsStore(memoryStorage(null)).get().driveLockEnabled).toBe(true);
    });

    it('is on again after the settings are reset', () => {
      const store = createSettingsStore(memoryStorage());
      store.update({ driveLockEnabled: false });
      expect(store.get().driveLockEnabled).toBe(false);
      store.reset();
      expect(store.get().driveLockEnabled).toBe(true);
    });
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
