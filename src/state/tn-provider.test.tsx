import { act, render, screen } from '@testing-library/react-native';
import { Text } from 'react-native';

import { createCredentialsStore, type SecretStore } from '@/tn/credentials';
import type { RawClient } from '@/tn/service';

import { TnProvider, useTn } from './tn-provider';

let mockSettings = { serverAddress: null as string | null, hiddenHazardTypes: [] as string[], dataWifiOnly: true, camerasEnabled: false };
const mockListeners = new Set<() => void>();
jest.mock('@/settings', () => {
  const { useSyncExternalStore } = jest.requireActual('react');
  return {
    useSettings: () =>
      useSyncExternalStore(
        (l: () => void) => {
          mockListeners.add(l);
          return () => mockListeners.delete(l);
        },
        () => mockSettings,
      ),
  };
});

const ok = (value: unknown) => JSON.stringify({ ok: value });
const syncStatus = { connection: 'online', lastSyncedAtUnixMs: 1, pendingWrites: 0, subscribedTiles: [], staticDataVersion: 1, lastErrorCode: null, lastErrorMessage: null, storageBytes: 10 };
const networkStatus = { knownNodes: [], activeNodes: [], currentNodes: [], directoryGeneratedAt: null, configVersion: null, cameraNamespaceEnabled: false };

function fakeClient(answers: Record<string, string | (() => string)>) {
  const calls: string[] = [];
  const raw: RawClient = {
    callAsync: async (method) => {
      calls.push(method);
      const answer = answers[method];
      if (answer === undefined) throw new Error(`unexpected ${method}`);
      return typeof answer === 'function' ? answer() : answer;
    },
    startRealtime: jest.fn(),
    stopRealtime: jest.fn(),
    setEventListener: jest.fn(),
    uniffiDestroy: jest.fn(),
  };
  return { raw, calls };
}

function memorySecrets(): SecretStore {
  const data = new Map<string, string>();
  return { get: (k) => data.get(k), set: (k, v) => void data.set(k, v), delete_: (k) => void data.delete(k) };
}

function Probe() {
  const { phase, waitingForWifi, error, rejectedWrites, dismissRejected, resetLocalData, resetDeviceIdentity } = useTn();
  return (
    <>
      <Text>{`${phase}|${waitingForWifi ? 'wifi' : 'go'}|${error ?? ''}`}</Text>
      <Text>{`rejected:${rejectedWrites}`}</Text>
      <Text onPress={dismissRejected}>dismiss</Text>
      <Text onPress={() => void resetLocalData()}>reset-data</Text>
      <Text onPress={() => void resetDeviceIdentity()}>reset-identity</Text>
    </>
  );
}

const baseAnswers = {
  planBootstrap: ok({ partitionsTotal: 2, partitionsPending: 2, bytesTotal: 100, bytesPending: 100 }),
  tick: ok({ synced: true, report: null }),
  sync: ok({ skipped: false, ok: true, staticDataError: null, dynamicDataError: null, submitted: 0, rejected: 0, pendingWrites: 0 }),
  getSyncStatus: ok(syncStatus),
  getNetworkStatus: ok(networkStatus),
};

async function mount(client: ReturnType<typeof fakeClient>, onWifi: boolean) {
  const createClient = jest.fn((_options: unknown) => client.raw);
  await render(
    <TnProvider createClient={createClient} credentialsStore={createCredentialsStore(memorySecrets())} isOnWifi={async () => onWifi} tickIntervalMs={3_600_000}>
      <Probe />
    </TnProvider>,
  );
  await act(async () => {});
  return createClient;
}

beforeEach(() => {
  mockSettings = { serverAddress: null, hiddenHazardTypes: [], dataWifiOnly: true, camerasEnabled: false };
});

describe('TnProvider', () => {
  it('becomes ready after a successful tick and starts realtime', async () => {
    const client = fakeClient(baseAnswers);
    await mount(client, true);
    expect(screen.getByText('ready|go|')).toBeTruthy();
    expect(client.calls).toContain('tick');
    expect(client.raw.startRealtime).toHaveBeenCalled();
  });

  it('holds the data download back on mobile data while "Wi-Fi only" is on', async () => {
    const client = fakeClient(baseAnswers);
    await mount(client, false);
    expect(screen.getByText('ready|wifi|')).toBeTruthy();
    expect(client.calls).not.toContain('tick');
    expect(client.calls).not.toContain('sync');
  });

  it('syncs on mobile data once nothing big is left to download', async () => {
    const client = fakeClient({ ...baseAnswers, planBootstrap: ok({ partitionsTotal: 2, partitionsPending: 0, bytesTotal: 100, bytesPending: 0 }) });
    await mount(client, false);
    expect(screen.getByText('ready|go|')).toBeTruthy();
    expect(client.calls).toContain('tick');
  });

  it('syncs on mobile data when the user turned "Wi-Fi only" off', async () => {
    mockSettings = { ...mockSettings, dataWifiOnly: false };
    const client = fakeClient(baseAnswers);
    await mount(client, false);
    expect(client.calls).toContain('tick');
  });

  it('counts writes the server refused and lets the user acknowledge them', async () => {
    const report = { skipped: false, ok: true, staticDataError: null, dynamicDataError: null, submitted: 0, rejected: 2, pendingWrites: 0 };
    const client = fakeClient({ ...baseAnswers, tick: ok({ synced: true, report }) });
    await mount(client, true);
    expect(screen.getByText('rejected:2')).toBeTruthy();
    await act(async () => screen.getByText('dismiss').props.onPress());
    expect(screen.getByText('rejected:0')).toBeTruthy();
  });

  it('builds the client with the camera switch the user chose, off by default', async () => {
    const client = fakeClient(baseAnswers);
    const first = await mount(client, true);
    expect(first.mock.calls[0]![0]).toMatchObject({ cameraNamespaceEnabled: false });
    mockSettings = { ...mockSettings, camerasEnabled: true };
    const second = await mount(fakeClient(baseAnswers), true);
    expect(second.mock.calls[0]![0]).toMatchObject({ cameraNamespaceEnabled: true });
  });

  it('reports missing credentials as its own phase, not as an error', async () => {
    const client = fakeClient({ ...baseAnswers, tick: JSON.stringify({ error: { code: 'notConfigured', message: 'no credentials' } }) });
    await mount(client, true);
    expect(screen.getByText('noCredentials|go|')).toBeTruthy();
  });

  it('shows other library failures as an error', async () => {
    const client = fakeClient({ ...baseAnswers, tick: JSON.stringify({ error: { code: 'storageFull', message: 'disk full' } }) });
    await mount(client, true);
    expect(screen.getByText('error|go|disk full')).toBeTruthy();
  });

  it('shows a failing client constructor as an error', async () => {
    await render(
      <TnProvider
        createClient={() => {
          throw new Error('bad options');
        }}
        credentialsStore={createCredentialsStore(memorySecrets())}
        isOnWifi={async () => true}>
        <Probe />
      </TnProvider>,
    );
    await act(async () => {});
    expect(screen.getByText('error|go|bad options')).toBeTruthy();
  });

  it('closes the old client and builds a new one when the server changes', async () => {
    const first = fakeClient(baseAnswers);
    const second = fakeClient(baseAnswers);
    const clients = [first, second];
    const createClient = jest.fn((_options: unknown) => clients.shift()!.raw);
    await render(
      <TnProvider createClient={createClient} credentialsStore={createCredentialsStore(memorySecrets())} isOnWifi={async () => true} tickIntervalMs={3_600_000}>
        <Probe />
      </TnProvider>,
    );
    await act(async () => {});
    mockSettings = { ...mockSettings, serverAddress: 'https://node.example.org' };
    await act(async () => mockListeners.forEach((l) => l()));
    expect(createClient).toHaveBeenCalledTimes(2);
    expect(createClient.mock.calls[1]![0]).toMatchObject({ discovery: false, nodes: ['https://node.example.org'] });
    expect(first.raw.uniffiDestroy).toHaveBeenCalled();
  });
});

describe('TnProvider resets', () => {
  async function mountWithMaintenance() {
    const order: string[] = [];
    const clients = [fakeClient(baseAnswers), fakeClient(baseAnswers)];
    const created: ReturnType<typeof fakeClient>[] = [];
    const createClient = jest.fn((_options: unknown) => {
      const c = clients[created.length]!;
      created.push(c);
      return c.raw;
    });
    (clients[0]!.raw.uniffiDestroy as jest.Mock).mockImplementation(() => order.push('close'));
    const maintenance = {
      deleteLocalData: jest.fn(async () => void order.push('delete-data')),
      wipeSecrets: jest.fn(async () => void order.push('wipe-secrets')),
    };
    await render(
      <TnProvider createClient={createClient} credentialsStore={createCredentialsStore(memorySecrets())} isOnWifi={async () => true} tickIntervalMs={3_600_000} maintenance={maintenance}>
        <Probe />
      </TnProvider>,
    );
    await act(async () => {});
    return { order, maintenance, createClient };
  }

  it('closes the client, deletes the local data and starts a fresh client', async () => {
    const { order, maintenance, createClient } = await mountWithMaintenance();
    await act(async () => screen.getByText('reset-data').props.onPress());
    expect(order).toEqual(['close', 'delete-data']);
    expect(maintenance.wipeSecrets).not.toHaveBeenCalled();
    expect(createClient).toHaveBeenCalledTimes(2);
  });

  it('removes the secrets first when the device identity is reset, then the data, then starts anew', async () => {
    const { order, maintenance, createClient } = await mountWithMaintenance();
    await act(async () => screen.getByText('reset-identity').props.onPress());
    expect(order).toEqual(['close', 'wipe-secrets', 'delete-data']);
    expect(maintenance.wipeSecrets).toHaveBeenCalledTimes(1);
    expect(createClient).toHaveBeenCalledTimes(2);
  });
});
