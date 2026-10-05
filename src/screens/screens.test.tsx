import { fireEvent, render, screen } from '@testing-library/react-native';

import { setLanguage } from '@/i18n';
import { createSettingsStore, type SettingsStorage } from '@/settings/settings';
import type { CredentialsStore } from '@/tn/credentials';
import type { TnState } from '@/state/tn-provider';

import { DataScreen } from './data/data-screen';
import { ServerScreen } from './server/server-screen';

// A real settings store over memory, and a hand-made provider state: the screens run against both without native code.
const mockStorage: SettingsStorage & { value: string | null } = {
  value: null,
  read() {
    return this.value;
  },
  write(v) {
    this.value = v;
  },
  remove() {
    this.value = null;
  },
};
let mockStore = createSettingsStore(mockStorage);
jest.mock('@/settings', () => {
  const { useSyncExternalStore } = jest.requireActual('react');
  return {
    get settingsStore() {
      return mockStore;
    },
    useSettings: () => useSyncExternalStore((l: () => void) => mockStore.subscribe(l), () => mockStore.get()),
  };
});

let mockTn: TnState;
jest.mock('@/state/tn-provider', () => ({ useTn: () => mockTn }));

function fakeCredentials(): CredentialsStore & { set: jest.Mock; clear: jest.Mock } {
  return { get: () => undefined, set: jest.fn(), clear: jest.fn(), subscribe: () => () => {} };
}

function tnState(overrides: Partial<TnState> = {}): TnState {
  return {
    phase: 'ready', error: null, service: null, sync: null, network: null, waitingForWifi: false, dataVersion: 0,
    rejectedWrites: 0, credentialsStore: fakeCredentials(), syncNow: jest.fn(async () => {}), dismissRejected: jest.fn(), resetLocalData: jest.fn(async () => {}), resetDeviceIdentity: jest.fn(async () => {}), ...overrides,
  };
}

beforeEach(() => {
  setLanguage('en');
  mockStorage.value = null;
  mockStore = createSettingsStore(mockStorage);
  mockTn = tnState();
});

describe('ServerScreen', () => {
  it('saves a valid address and shows it as the used server', async () => {
    await render(<ServerScreen />);
    await fireEvent.changeText(screen.getByLabelText('Server address'), 'node.example.org');
    await fireEvent.press(screen.getByRole('button', { name: 'Connect' }));
    expect(mockStore.get().serverAddress).toBe('https://node.example.org');
    expect(screen.getByText('Connected to: https://node.example.org')).toBeTruthy();
  });

  it('refuses plain http outside development builds and keeps the old setting', async () => {
    (globalThis as { __DEV__?: boolean }).__DEV__ = false;
    await render(<ServerScreen />);
    await fireEvent.changeText(screen.getByLabelText('Server address'), 'http://node.example.org');
    await fireEvent.press(screen.getByRole('button', { name: 'Connect' }));
    (globalThis as { __DEV__?: boolean }).__DEV__ = true;
    expect(screen.getByRole('alert')).toBeTruthy();
    expect(screen.getByText(/Unencrypted connections/)).toBeTruthy();
    expect(mockStore.get().serverAddress).toBeNull();
  });

  it('goes back to automatic discovery', async () => {
    mockStore.update({ serverAddress: 'https://node.example.org' });
    await render(<ServerScreen />);
    await fireEvent.press(screen.getByRole('button', { name: 'Find automatically' }));
    expect(mockStore.get().serverAddress).toBeNull();
    expect(screen.getByText('Servers are found automatically.')).toBeTruthy();
  });

  it('stores access data in the credentials store, not in the settings, and clears the fields', async () => {
    await render(<ServerScreen />);
    await fireEvent.changeText(screen.getByLabelText('ID'), ' my-id ');
    await fireEvent.changeText(screen.getByLabelText('Secret'), 'my-secret');
    await fireEvent.press(screen.getByRole('button', { name: 'Save access' }));
    expect(mockTn.credentialsStore.set).toHaveBeenCalledWith({ type: 'app', appClientId: 'my-id', appClientSecret: 'my-secret' });
    expect(JSON.stringify(mockStore.get())).not.toContain('my-secret');
    expect(screen.getByText('Access saved.')).toBeTruthy();
    expect(screen.getByLabelText('Secret').props.value).toBe('');
  });

  it('asks for both fields before saving access', async () => {
    await render(<ServerScreen />);
    await fireEvent.changeText(screen.getByLabelText('ID'), 'only-id');
    await fireEvent.press(screen.getByRole('button', { name: 'Save access' }));
    expect(mockTn.credentialsStore.set).not.toHaveBeenCalled();
    expect(screen.getByText('Please enter ID and secret.')).toBeTruthy();
  });

  it('says plainly that access is missing', async () => {
    mockTn = tnState({ phase: 'noCredentials' });
    await render(<ServerScreen />);
    expect(screen.getByText(/No access set up/)).toBeTruthy();
  });

  it('shows connection status and the known nodes', async () => {
    mockTn = tnState({
      sync: { connection: 'online', lastSyncedAtUnixMs: null, pendingWrites: 2, subscribedTiles: [], staticDataVersion: 1, lastErrorCode: 'network', lastErrorMessage: null, storageBytes: null },
      network: {
        knownNodes: [
          { nodeId: 'n1', address: 'https://a.example', tier: 'trusted', backedOff: false },
          { nodeId: 'n2', address: 'https://b.example', tier: 'probation', backedOff: true },
        ],
        activeNodes: ['n1'], currentNodes: ['n1'], directoryGeneratedAt: null, configVersion: null, cameraNamespaceEnabled: false,
      },
    });
    await render(<ServerScreen />);
    expect(screen.getByText('Online')).toBeTruthy();
    expect(screen.getByText('Last sync: never')).toBeTruthy();
    expect(screen.getByText('Waiting reports: 2')).toBeTruthy();
    expect(screen.getByText('Last error: network')).toBeTruthy();
    expect(screen.getByText('trusted · in use')).toBeTruthy();
    expect(screen.getByText('new · paused')).toBeTruthy();
  });
});

describe('DataScreen', () => {
  it('has "Wi-Fi only" on by default and lets the user turn it off', async () => {
    await render(<DataScreen />);
    const toggle = screen.getByLabelText('Load on Wi-Fi only');
    expect(toggle.props.value).toBe(true);
    await fireEvent(toggle, 'valueChange', false);
    expect(mockStore.get().dataWifiOnly).toBe(false);
  });

  it('says the size is not known while there is no service', async () => {
    await render(<DataScreen />);
    expect(screen.getByText(/Size not known yet/)).toBeTruthy();
  });
});
