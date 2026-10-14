import type { RawClient } from './service';
import type { ClientOptions } from './types';

/** The part of the browser library (`@trafficnetwork/client-web`) this adapter uses. Tests pass a fake. */
export interface WebLibraryClient {
  call(method: string, args?: Record<string, unknown>): Promise<unknown>;
  onEvent(listener: ((event: unknown) => void) | null): void;
  startRealtime(): void;
  stopRealtime(): void;
  free(): void;
}

export interface WebLibrary {
  Client: {
    create(
      options: Record<string, unknown>,
      extras?: { secureStore?: { get(key: string): string | null | undefined; set(key: string, value: string): void; delete(key: string): void }; wasm?: unknown },
    ): Promise<WebLibraryClient>;
  };
}

export type WebRawClientDeps = {
  /** Loads the library module (a dynamic import of the copy next to the app, see `scripts/web-postbuild.mjs`). */
  loadLibrary: () => Promise<WebLibrary>;
  /** Name of the IndexedDB database. */
  storagePath: string;
  /** Where the `.wasm` file is served from. */
  wasm: unknown;
  /** The device's secrets; the browser has no keystore, this is a synchronous store the app controls. */
  secureStore: { get(key: string): string | undefined; set(key: string, value: string): void; delete_(key: string): void };
};

/** What a rejected library call looks like: a `TrafficNetworkError` with a `code`, or anything else. */
function envelopeOf(error: unknown): string {
  const e = error as { code?: unknown; detail?: unknown; message?: unknown } | null;
  const code = typeof e?.code === 'string' ? e.code : 'internal';
  const message = typeof e?.detail === 'string' ? e.detail : typeof e?.message === 'string' ? e.message : String(error);
  return JSON.stringify({ error: { code, message } });
}

/**
 * Presents the browser library as the `RawClient` the app already speaks (`callAsync` with a JSON answer), so `TnService`
 * and everything above it stay the same on every platform.
 *
 * The library starts asynchronously (it loads WebAssembly); the app's `createClient` is synchronous. The first call, and the
 * realtime and event setup, therefore wait for the client to exist. A start that fails answers every call with the error.
 */
export function createWebRawClient(deps: WebRawClientDeps, options: Omit<ClientOptions, 'storagePath'>): RawClient {
  let closed = false;
  let listener: { onEvent(json: string): void } | undefined;
  let realtime = false;

  const ready: Promise<WebLibraryClient> = deps
    .loadLibrary()
    .then((lib) =>
      lib.Client.create(
        { ...options, storagePath: deps.storagePath },
        { wasm: deps.wasm, secureStore: { get: (k) => deps.secureStore.get(k), set: (k, v) => deps.secureStore.set(k, v), delete: (k) => deps.secureStore.delete_(k) } },
      ),
    )
    .then((client) => {
      if (closed) {
        client.free();
        throw new Error('closed');
      }
      applyListener(client);
      if (realtime) client.startRealtime();
      return client;
    });
  // a failed start is reported on the calls; this keeps it from being an unhandled rejection
  ready.catch(() => undefined);

  function applyListener(client: WebLibraryClient) {
    client.onEvent(listener ? (event) => listener?.onEvent(JSON.stringify(event)) : null);
  }

  return {
    async callAsync(method, argsJson) {
      try {
        const client = await ready;
        const args = argsJson ? (JSON.parse(argsJson) as Record<string, unknown>) : {};
        return JSON.stringify({ ok: (await client.call(method, args)) ?? null });
      } catch (error) {
        return envelopeOf(error);
      }
    },
    startRealtime() {
      realtime = true;
      void ready.then((client) => client.startRealtime()).catch(() => undefined);
    },
    stopRealtime() {
      realtime = false;
      void ready.then((client) => client.stopRealtime()).catch(() => undefined);
    },
    setEventListener(next) {
      listener = next;
      void ready.then(applyListener).catch(() => undefined);
    },
    uniffiDestroy() {
      closed = true;
      void ready.then((client) => client.free()).catch(() => undefined);
    },
  };
}
