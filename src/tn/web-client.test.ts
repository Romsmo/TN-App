import { createWebRawClient, type WebLibrary, type WebLibraryClient, type WebRawClientDeps } from './web-client';

function fakeLibrary() {
  const calls: [string, unknown][] = [];
  let eventListener: ((event: unknown) => void) | null = null;
  const client: WebLibraryClient & { freed: boolean; realtime: boolean } = {
    freed: false,
    realtime: false,
    call: jest.fn(async (method: string, args?: Record<string, unknown>) => {
      calls.push([method, args]);
      if (method === 'boom') throw Object.assign(new Error('network: down'), { code: 'network', detail: 'every server failed' });
      if (method === 'odd') throw 'something else';
      return method === 'nothing' ? undefined : { method };
    }),
    onEvent: (l) => void (eventListener = l),
    startRealtime() {
      client.realtime = true;
    },
    stopRealtime() {
      client.realtime = false;
    },
    free() {
      client.freed = true;
    },
  };
  const create = jest.fn(async () => client);
  const lib: WebLibrary = { Client: { create } };
  return { lib, client, create, calls, emit: (event: unknown) => eventListener?.(event) };
}

const secureStore = { get: () => undefined, set: () => {}, delete_: () => {} };
const deps = (lib: WebLibrary): WebRawClientDeps => ({ loadLibrary: async () => lib, storagePath: 'tn-test', wasm: '/lib/x.wasm', secureStore });
const settle = async () => {
  for (let i = 0; i < 10; i++) await Promise.resolve();
};

describe('createWebRawClient', () => {
  it('starts the library with the options, the database name, the wasm location and the secret store', async () => {
    const f = fakeLibrary();
    const raw = createWebRawClient(deps(f.lib), { discovery: false, nodes: ['https://n.example'] });
    await raw.callAsync('getSyncStatus', '{}');
    const [options, extras] = f.create.mock.calls[0] as unknown as [Record<string, unknown>, { wasm: unknown; secureStore: { delete: unknown } }];
    expect(options).toMatchObject({ discovery: false, nodes: ['https://n.example'], storagePath: 'tn-test' });
    expect(extras.wasm).toBe('/lib/x.wasm');
    expect(typeof extras.secureStore.delete).toBe('function');
  });

  it('answers a call with the JSON envelope the app expects, waiting for the start', async () => {
    const f = fakeLibrary();
    const raw = createWebRawClient(deps(f.lib), {});
    expect(JSON.parse(await raw.callAsync('getNearby', JSON.stringify({ lat: 1 })))).toEqual({ ok: { method: 'getNearby' } });
    expect(f.calls).toEqual([['getNearby', { lat: 1 }]]);
  });

  it('answers a missing result as ok null and an empty argument string as no arguments', async () => {
    const f = fakeLibrary();
    const raw = createWebRawClient(deps(f.lib), {});
    expect(JSON.parse(await raw.callAsync('nothing', ''))).toEqual({ ok: null });
    expect(f.calls[0]).toEqual(['nothing', {}]);
  });

  it('turns a library error into an error envelope with its code and its own message', async () => {
    const raw = createWebRawClient(deps(fakeLibrary().lib), {});
    expect(JSON.parse(await raw.callAsync('boom', '{}'))).toEqual({ error: { code: 'network', message: 'every server failed' } });
    expect(JSON.parse(await raw.callAsync('odd', '{}'))).toEqual({ error: { code: 'internal', message: 'something else' } });
  });

  it('answers every call with the error when the library cannot start', async () => {
    const raw = createWebRawClient({ ...deps(fakeLibrary().lib), loadLibrary: async () => Promise.reject(new Error('no wasm')) }, {});
    expect(JSON.parse(await raw.callAsync('getSyncStatus', '{}'))).toEqual({ error: { code: 'internal', message: 'no wasm' } });
  });

  it('starts realtime and the event listener once the client exists, and hands events over as JSON', async () => {
    const f = fakeLibrary();
    const raw = createWebRawClient(deps(f.lib), {});
    const onEvent = jest.fn();
    raw.setEventListener({ onEvent });
    raw.startRealtime(); // before the client exists
    await settle();
    expect(f.client.realtime).toBe(true);
    f.emit({ type: 'dataChanged' });
    expect(onEvent).toHaveBeenCalledWith(JSON.stringify({ type: 'dataChanged' }));
    raw.setEventListener(undefined);
    await settle();
    expect(f.emit({ type: 'x' })).toBeUndefined();
    expect(onEvent).toHaveBeenCalledTimes(1);
    raw.stopRealtime();
    await settle();
    expect(f.client.realtime).toBe(false);
  });

  it('frees the library client when destroyed, also when it is destroyed before the start finished', async () => {
    const f = fakeLibrary();
    const raw = createWebRawClient(deps(f.lib), {});
    raw.uniffiDestroy(); // immediately
    await settle();
    expect(f.client.freed).toBe(true);
  });
});
