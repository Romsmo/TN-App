import { act, fireEvent, render, screen, waitFor } from '@testing-library/react-native';

import { DriveProvider } from '@/drive/drive-provider';
import type { DriveHost } from '@/drive/drive-host';
import type { DriveSnapshot } from '@/drive/drive-session';
import { setLanguage } from '@/i18n';
import { CAMERA_NOTICE, DRIVE_NOTICE_EXTRA, plain } from '@/legal/texts';
import { createSettingsStore, type SettingsStorage } from '@/settings/settings';

import { DriveScreen, driveReportTypes } from './drive-screen';
import { DriveView } from './drive-view';

jest.mock('expo-keep-awake', () => ({ useKeepAwake: jest.fn() }));

const mockStorage: SettingsStorage = { read: () => null, write: () => {}, remove: () => {} };
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
jest.mock('@/state/tn-provider', () => ({ useTn: () => ({ service: null, dataVersion: 0 }) }));
let mockPolicy: { active: boolean; maxLevel: 'off' | 'zones' | 'full' } | null = null;
jest.mock('@/state/camera-policy', () => ({ useCameraPolicy: () => mockPolicy }));

const running: DriveSnapshot = {
  active: true, simulated: false, speedKmh: 62, limit: { value: 50, unit: 'kmh' }, speedState: 'over', warnings: [], prompt: null,
  muted: false, locked: true, speedLocked: true, gpsLost: false,
};

function fakeHost(initial: DriveSnapshot | null = null) {
  let snap = initial;
  const listeners = new Set<() => void>();
  const session = { report: jest.fn(async () => true), answerPrompt: jest.fn(async () => {}), setMuted: jest.fn() };
  const host = {
    subscribe: (l: () => void) => (listeners.add(l), () => listeners.delete(l)),
    getSnapshot: () => snap,
    get current() {
      return session;
    },
    start: jest.fn(async () => {
      snap = { ...running };
      listeners.forEach((l) => l());
    }),
    stop: jest.fn(() => {
      snap = null;
      listeners.forEach((l) => l());
    }),
  };
  return { host: host as unknown as DriveHost & typeof host, session };
}

beforeEach(() => {
  setLanguage('en');
  mockStore = createSettingsStore(mockStorage);
  mockPolicy = null;
});

describe('DriveScreen: starting', () => {
  it('shows the legal notice, with the camera wording and the operating hint, before the very first drive', async () => {
    const { host } = fakeHost();
    await render(<DriveProvider host={host}><DriveScreen /></DriveProvider>);
    await fireEvent.press(screen.getByRole('button', { name: 'Start driving' }));
    expect(screen.getByText(`${plain(CAMERA_NOTICE.en)}\n\n${DRIVE_NOTICE_EXTRA.en}`)).toBeTruthy();
    expect(host.start).not.toHaveBeenCalled();
    await fireEvent.press(screen.getByRole('button', { name: 'Understood' }));
    expect(mockStore.get().driveNoticeSeen).toBe(true);
    await waitFor(() => expect(host.start).toHaveBeenCalledWith('real', { speedup: 1 }));
    await act(async () => {});
  });

  it('does not show the notice again at the next start', async () => {
    mockStore.update({ driveNoticeSeen: true });
    const { host } = fakeHost();
    await render(<DriveProvider host={host}><DriveScreen /></DriveProvider>);
    await fireEvent.press(screen.getByRole('button', { name: 'Start driving' }));
    expect(screen.queryByText(/Operate the app only as a passenger/)).toBeNull();
    await waitFor(() => expect(host.start).toHaveBeenCalledWith('real', { speedup: 1 }));
    await act(async () => {});
  });

  it('offers a clearly labelled simulation, also faster', async () => {
    mockStore.update({ driveNoticeSeen: true });
    const { host } = fakeHost();
    await render(<DriveProvider host={host}><DriveScreen /></DriveProvider>);
    expect(screen.getByText(/invented demo route/)).toBeTruthy();
    await fireEvent.press(screen.getByRole('button', { name: 'Simulate a drive (4× faster)' }));
    await waitFor(() => expect(host.start).toHaveBeenCalledWith('simulation', { speedup: 4 }));
    await act(async () => {});
  });

  it('says what to do when location access is missing', async () => {
    mockStore.update({ driveNoticeSeen: true });
    const { host } = fakeHost();
    host.start.mockRejectedValueOnce(new Error('location-permission-denied'));
    await render(<DriveProvider host={host}><DriveScreen /></DriveProvider>);
    await fireEvent.press(screen.getByRole('button', { name: 'Start driving' }));
    await waitFor(() => expect(screen.getByRole('alert')).toBeTruthy());
    expect(screen.getByText(/cannot run without location access/)).toBeTruthy();
    await act(async () => {});
  });
});

describe('DriveScreen: running', () => {
  async function runningScreen(snapshot: DriveSnapshot = running) {
    const fake = fakeHost(snapshot);
    await render(<DriveProvider host={fake.host}><DriveScreen /></DriveProvider>);
    return fake;
  }

  it('reports with one tap and shows a short confirmation', async () => {
    const { session } = await runningScreen();
    await fireEvent.press(screen.getByRole('button', { name: 'Report Accident' }));
    expect(session.report).toHaveBeenCalledWith('accident');
    await waitFor(() => expect(screen.getByText('Reported')).toBeTruthy());
    await act(async () => {});
  });

  it('mutes and ends the drive', async () => {
    const { session, host } = await runningScreen();
    await fireEvent.press(screen.getByRole('button', { name: 'Mute' }));
    expect(session.setMuted).toHaveBeenCalledWith(true);
    await fireEvent.press(screen.getByRole('button', { name: 'End' }));
    expect(host.stop).toHaveBeenCalled();
  });

  it('offers camera reports only where cameras are on and allowed in full', () => {
    expect(driveReportTypes(false, 'full')).not.toContain('mobileSpeedCamera');
    expect(driveReportTypes(true, 'zones')).not.toContain('mobileSpeedCamera');
    expect(driveReportTypes(true, null)).not.toContain('mobileSpeedCamera');
    for (const type of ['fixedSpeedCamera', 'mobileSpeedCamera', 'trailerCamera', 'redLightCamera', 'distanceControl']) expect(driveReportTypes(true, 'full')).toContain(type);
    expect(driveReportTypes(false, 'off')).toEqual(['traffic', 'accident', 'construction', 'ice']);
  });

  it('shows the "lock off" badge only when the lock is off and switches it on with a tap, no confirmation', async () => {
    await runningScreen();
    expect(screen.queryByRole('button', { name: 'Driving lock off' })).toBeNull();
    await act(async () => mockStore.update({ driveLockEnabled: false }));
    await fireEvent.press(screen.getByRole('button', { name: 'Driving lock off' }));
    expect(mockStore.get().driveLockEnabled).toBe(true);
    await act(async () => {});
    expect(screen.queryByRole('button', { name: 'Driving lock off' })).toBeNull();
  });
});

describe('DriveView', () => {
  const base = {
    snapshot: running, unit: 'kmh' as const, lockEnabled: true, reportTypes: ['traffic', 'ice'], toast: null,
    onReport: jest.fn(), onAnswer: jest.fn(), onMute: jest.fn(), onStop: jest.fn(), onEnableLock: jest.fn(),
  };

  it('shows speed and limit, and says "over the limit" for screen readers', async () => {
    await render(<DriveView {...base} />);
    expect(screen.getByText('62')).toBeTruthy();
    expect(screen.getByText('50')).toBeTruthy();
    expect(screen.getByLabelText('62 km/h, over the speed limit')).toBeTruthy();
  });

  it('shows mph when the user chose it', async () => {
    await render(<DriveView {...base} unit="mph" />);
    expect(screen.getByText('39')).toBeTruthy(); // 62 km/h
    expect(screen.getByText('mph')).toBeTruthy();
    expect(screen.getByText('30')).toBeTruthy(); // 50 km/h as a 5-step
  });

  it('marks a simulation unmistakably', async () => {
    await render(<DriveView {...base} snapshot={{ ...running, simulated: true }} />);
    expect(screen.getByText('SIMULATION – not a real drive')).toBeTruthy();
  });

  it('puts all camera kinds behind one "Camera" tile and reports the chosen kind', async () => {
    const onReport = jest.fn();
    const types = ['traffic', 'fixedSpeedCamera', 'mobileSpeedCamera', 'trailerCamera', 'redLightCamera', 'distanceControl'];
    await render(<DriveView {...base} reportTypes={types} onReport={onReport} />);
    expect(screen.queryByRole('button', { name: /Report Speed camera/ })).toBeNull();
    await fireEvent.press(screen.getByRole('button', { name: 'Camera' }));
    for (const label of ['Speed camera (fixed)', 'Speed camera (mobile)', 'Speed camera (trailer)', 'Red-light camera', 'Distance control']) {
      expect(screen.getByLabelText(new RegExp(label.replace(/[()]/g, '\\$&')))).toBeTruthy();
    }
    await fireEvent.press(screen.getByLabelText(/Red-light camera/));
    expect(onReport).toHaveBeenCalledWith('redLightCamera');
    // back on the first screen after a report
    expect(screen.getByRole('button', { name: 'Camera' })).toBeTruthy();
  });

  it('shows no camera tile when no camera kind is offered', async () => {
    await render(<DriveView {...base} />);
    expect(screen.queryByRole('button', { name: 'Camera' })).toBeNull();
  });

  it('shows an area warning without any distance and without a spot', async () => {
    const snapshot: DriveSnapshot = { ...running, warnings: [{ id: 'z', level: 'first', kind: 'zone', category: 'cameras', label: 'Danger area', distanceM: null, since: 0 }] };
    await render(<DriveView {...base} snapshot={snapshot} />);
    expect(screen.getByText('Danger area')).toBeTruthy();
    expect(screen.getByText('An area, not an exact spot')).toBeTruthy();
    expect(screen.queryByText(/ m$/)).toBeNull();
  });

  it('shows a point warning with its distance', async () => {
    const snapshot: DriveSnapshot = { ...running, warnings: [{ id: 'h', level: 'second', kind: 'point', category: 'accident', label: 'Accident', distanceM: 200, since: 0 }] };
    await render(<DriveView {...base} snapshot={snapshot} />);
    expect(screen.getByText('in 200 m')).toBeTruthy();
  });

  it('shows the "still there?" card with two big answers', async () => {
    const onAnswer = jest.fn();
    const snapshot: DriveSnapshot = { ...running, prompt: { id: 'h', hazardType: 'ice', since: 0 } };
    await render(<DriveView {...base} snapshot={snapshot} onAnswer={onAnswer} />);
    expect(screen.getByText('Ice: still there?')).toBeTruthy();
    await fireEvent.press(screen.getByRole('button', { name: 'Still there' }));
    await fireEvent.press(screen.getByRole('button', { name: 'Gone' }));
    expect(onAnswer.mock.calls).toEqual([[true], [false]]);
  });

  it('has no text input and no menu while driving', async () => {
    await render(<DriveView {...base} />);
    const tree = JSON.stringify(screen.toJSON());
    expect(tree).not.toContain('"TextInput"');
    expect(tree).not.toMatch(/"(textinput|TextInput)"/i);
    expect(screen.queryByRole('link')).toBeNull();
  });

  it('makes every button much larger than the platform minimum', async () => {
    await render(<DriveView {...base} />);
    const style = screen.getByRole('button', { name: 'Report Ice' }).props.style;
    const flat = typeof style === 'function' ? style({ pressed: false }) : style;
    const minHeight = [flat].flat(3).reduce((m: number, s: { minHeight?: number }) => Math.max(m, s?.minHeight ?? 0), 0);
    expect(minHeight).toBeGreaterThanOrEqual(80);
  });
});

describe('DriveView in the emergency mode', () => {
  const base = {
    snapshot: running, unit: 'kmh' as const, lockEnabled: true, reportTypes: ['traffic'], toast: null,
    onReport: jest.fn(), onAnswer: jest.fn(), onMute: jest.fn(), onStop: jest.fn(), onEnableLock: jest.fn(),
  };

  it('says so, and still shows the speed and offers reports', async () => {
    await render(<DriveView {...base} emergency />);
    expect(screen.getByText('Emergency mode: no warning data')).toBeTruthy();
    expect(screen.getByText('No warning data, only your speed')).toBeTruthy();
    expect(screen.queryByText('Watching the road ahead')).toBeNull();
    expect(screen.getByText('62')).toBeTruthy();
    expect(screen.getByRole('button', { name: /Report Traffic jam/ })).toBeTruthy();
  });

  it('shows no emergency chip normally', async () => {
    await render(<DriveView {...base} />);
    expect(screen.queryByText(/Emergency mode/)).toBeNull();
  });
});
