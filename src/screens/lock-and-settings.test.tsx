import { act, fireEvent, render, screen, waitFor } from '@testing-library/react-native';
import { Text } from 'react-native';

import { LockGuard } from '@/components/lock-guard';
import { DriveProvider } from '@/drive/drive-provider';
import type { DriveHost } from '@/drive/drive-host';
import type { DriveSnapshot } from '@/drive/drive-session';
import { setLanguage } from '@/i18n';
import { CAMERA_NOTICE, LOCK_WARNING, plain } from '@/legal/texts';
import { createSettingsStore, type SettingsStorage } from '@/settings/settings';
import type { TnState } from '@/state/tn-provider';

import { DataScreen } from './data/data-screen';
import { InfoScreen } from './info/info-screen';
import { ServerScreen } from './server/server-screen';
import { SettingsScreen } from './settings/settings-screen';

jest.mock('expo-router', () => ({ Link: ({ children }: { children: React.ReactNode }) => children }));
jest.mock('expo-linking', () => ({ openURL: jest.fn() }));

const mockStorage: SettingsStorage & { value: string | null } = {
  value: null,
  read() { return this.value; },
  write(v) { this.value = v; },
  remove() { this.value = null; },
};
let mockStore = createSettingsStore(mockStorage);
jest.mock('@/settings', () => {
  const { useSyncExternalStore } = jest.requireActual('react');
  return {
    get settingsStore() { return mockStore; },
    useSettings: () => useSyncExternalStore((l: () => void) => mockStore.subscribe(l), () => mockStore.get()),
  };
});

let mockTn: TnState;
jest.mock('@/state/tn-provider', () => ({ useTn: () => mockTn }));
let mockPolicy: unknown = null;
jest.mock('@/state/camera-policy', () => ({ useCameraPolicy: () => mockPolicy }));

const snapshot = (over: Partial<DriveSnapshot> = {}): DriveSnapshot => ({
  active: true, simulated: false, speedKmh: 50, limit: null, speedState: 'ok', warnings: [], prompt: null, muted: false,
  locked: true, speedLocked: true, gpsLost: false, ...over,
});

function fakeHost(initial: DriveSnapshot | null) {
  let snap = initial;
  const listeners = new Set<() => void>();
  const host = {
    subscribe: (l: () => void) => (listeners.add(l), () => listeners.delete(l)),
    getSnapshot: () => snap,
    set(next: DriveSnapshot | null) { snap = next; listeners.forEach((l) => l()); },
  };
  return host as unknown as DriveHost & typeof host;
}

const tnState = (overrides: Partial<TnState> = {}): TnState => ({
  phase: 'ready', error: null, service: null, sync: null, network: null, waitingForWifi: false, dataVersion: 0, rejectedWrites: 0, emergency: null,
  credentialsStore: { get: () => undefined, set: jest.fn(), clear: jest.fn(), subscribe: () => () => {} },
  syncNow: jest.fn(async () => {}), dismissRejected: jest.fn(), resetLocalData: jest.fn(async () => {}), resetDeviceIdentity: jest.fn(async () => {}), ...overrides,
});

beforeEach(() => {
  setLanguage('en');
  mockStore = createSettingsStore(mockStorage);
  mockStorage.value = null;
  mockTn = tnState();
  mockPolicy = null;
});

const guarded = (host: DriveHost, child: React.ReactNode) => (
  <DriveProvider host={host}>
    <LockGuard>{child}</LockGuard>
  </DriveProvider>
);

describe('the speed lock (Fahrsperre) guards the pages', () => {
  it('is on by default', () => {
    expect(mockStore.get().driveLockEnabled).toBe(true);
  });

  it.each([
    ['settings', () => <SettingsScreen />, 'Driving lock'],
    ['server', () => <ServerScreen />, 'Server address'],
    ['data', () => <DataScreen />, 'Load on Wi-Fi only'],
    ['info', () => <InfoScreen libraryVersion="1.1.0" />, 'Sources and licences'],
  ])('keeps %s out of reach above the speed threshold, and shows why', async (_name, screenFor, marker) => {
    await render(guarded(fakeHost(snapshot()), screenFor()));
    expect(screen.getByText('Locked while driving')).toBeTruthy();
    expect(screen.queryByLabelText(marker)).toBeNull();
    expect(screen.queryByText(marker)).toBeNull();
  });

  it('makes the lock option itself unreachable while driving', async () => {
    await render(guarded(fakeHost(snapshot()), <SettingsScreen />));
    expect(screen.queryByLabelText('Driving lock')).toBeNull();
  });

  it('has no text input reachable while driving (server address and access fields are gone)', async () => {
    await render(guarded(fakeHost(snapshot()), <ServerScreen />));
    expect(JSON.stringify(screen.toJSON())).not.toContain('"TextInput"');
  });

  it('opens when the car stands still, when no drive is on, and when no lock applies', async () => {
    await render(guarded(fakeHost(snapshot({ speedLocked: false, locked: false })), <Text>content</Text>));
    expect(screen.getByText('content')).toBeTruthy();
    await render(guarded(fakeHost(null), <Text>content-2</Text>));
    expect(screen.getByText('content-2')).toBeTruthy();
  });

  it('opens when the user switched the lock off, and the lock option is then reachable', async () => {
    mockStore.update({ driveLockEnabled: false });
    await render(guarded(fakeHost(snapshot()), <SettingsScreen />));
    expect(screen.getByLabelText('Driving lock')).toBeTruthy();
  });

  it('locks again at once when the lock is switched back on while driving', async () => {
    mockStore.update({ driveLockEnabled: false });
    await render(guarded(fakeHost(snapshot()), <Text>content</Text>));
    expect(screen.getByText('content')).toBeTruthy();
    await act(async () => mockStore.update({ driveLockEnabled: true }));
    expect(screen.getByText('Locked while driving')).toBeTruthy();
  });

  it('opens again after the car stopped', async () => {
    const host = fakeHost(snapshot());
    await render(guarded(host, <Text>content</Text>));
    expect(screen.queryByText('content')).toBeNull();
    await act(async () => host.set(snapshot({ speedLocked: false, locked: false })));
    expect(screen.getByText('content')).toBeTruthy();
  });
});

describe('SettingsScreen', () => {
  async function open() {
    await render(guarded(fakeHost(null), <SettingsScreen />));
  }

  it('switching the lock off needs the confirmed warning, and the choice is remembered', async () => {
    await open();
    await fireEvent(screen.getByLabelText('Driving lock'), 'valueChange', false);
    expect(screen.getByText(LOCK_WARNING.en)).toBeTruthy();
    expect(mockStore.get().driveLockEnabled).toBe(true);
    await fireEvent.press(screen.getByRole('button', { name: 'I understand, switch it off' }));
    expect(mockStore.get().driveLockEnabled).toBe(false);
    await fireEvent(screen.getByLabelText('Driving lock'), 'valueChange', true);
    expect(mockStore.get().driveLockEnabled).toBe(true);
  });

  it('shows the speed-camera option off at the first start, and the notice exactly once when ticked', async () => {
    await open();
    expect(screen.getByLabelText('Show and report speed cameras').props.value).toBe(false);
    await fireEvent(screen.getByLabelText('Show and report speed cameras'), 'valueChange', true);
    expect(mockStore.get().camerasEnabled).toBe(true);
    expect(screen.getByText(plain(CAMERA_NOTICE.en))).toBeTruthy();
    await fireEvent.press(screen.getByRole('button', { name: 'Understood' }));
    expect(mockStore.get().camerasNoticeSeen).not.toBeNull();
    await fireEvent(screen.getByLabelText('Show and report speed cameras'), 'valueChange', false);
    await fireEvent(screen.getByLabelText('Show and report speed cameras'), 'valueChange', true);
    expect(screen.queryByText(plain(CAMERA_NOTICE.en))).toBeNull();
  });

  it('takes the camera option away when the policy of the network is "off"', async () => {
    mockPolicy = { maxLevel: 'off', notice: { version: '1' } };
    await open();
    expect(screen.getByLabelText('Show and report speed cameras').props.disabled).toBe(true);
  });

  it('changes the unit and the warning distance', async () => {
    await open();
    await fireEvent.press(screen.getByRole('button', { name: 'mph' }));
    await fireEvent.press(screen.getByRole('button', { name: 'Earlier' }));
    expect(mockStore.get()).toMatchObject({ speedUnit: 'mph', warnScale: 1.5 });
  });

  it('turns warnings off per category and offers the camera category only when cameras are on', async () => {
    await open();
    expect(screen.queryByLabelText('Warn about Speed cameras')).toBeNull();
    await fireEvent(screen.getByLabelText('Warn about Ice'), 'valueChange', false);
    expect(mockStore.get().warnOffCategories).toEqual(['ice']);
    await fireEvent(screen.getByLabelText('Warn about Ice'), 'valueChange', true);
    expect(mockStore.get().warnOffCategories).toEqual([]);
    await act(async () => mockStore.update({ camerasEnabled: true }));
    expect(screen.getByLabelText('Warn about Speed cameras')).toBeTruthy();
  });

  it('deletes local data only after confirmation, and resets the settings', async () => {
    mockStore.update({ speedUnit: 'mph' });
    await open();
    await fireEvent.press(screen.getByRole('button', { name: 'Delete local data' }));
    expect(mockTn.resetLocalData).not.toHaveBeenCalled();
    await fireEvent.press(screen.getByRole('button', { name: 'Delete' }));
    await waitFor(() => expect(mockTn.resetLocalData).toHaveBeenCalled());
    expect(mockStore.get().speedUnit).toBe('kmh');
  });

  it('does nothing when the deletion is cancelled', async () => {
    await open();
    await fireEvent.press(screen.getByRole('button', { name: 'Delete local data' }));
    await fireEvent.press(screen.getByRole('button', { name: 'Cancel' }));
    expect(mockTn.resetLocalData).not.toHaveBeenCalled();
  });

  it('resetting the device identity switches the speed lock on again', async () => {
    mockStore.update({ driveLockEnabled: false });
    await open();
    await fireEvent.press(screen.getByRole('button', { name: 'Reset device identity' }));
    await fireEvent.press(screen.getByRole('button', { name: 'Reset' }));
    await waitFor(() => expect(mockTn.resetDeviceIdentity).toHaveBeenCalled());
    await waitFor(() => expect(mockStore.get().driveLockEnabled).toBe(true));
  });
});

describe('InfoScreen', () => {
  it('shows the speed-camera notice permanently, word for word', async () => {
    setLanguage('de');
    await render(<InfoScreen libraryVersion="1.1.0" />);
    expect(screen.getByText(plain(CAMERA_NOTICE.de))).toBeTruthy();
  });
});
