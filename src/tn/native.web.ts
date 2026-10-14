/**
 * The browser counterpart of `native.ts`: the only web file that touches the client library.
 *
 * The library is the WebAssembly build of the same client the native apps use (`@trafficnetwork/client-web`). It is not
 * bundled by Metro: `scripts/web-postbuild.mjs` copies it next to the app (`tnlib/`) and a small classic script
 * (`tnlib-loader.js`) imports it, so Metro never sees `import.meta` or the `.wasm` file, and the Content-Security-Policy
 * can stay strict (`script-src 'self'`).
 */
import { CREDENTIALS_KEY } from './credentials';
import { createSecureStore, keysToWipe } from './secure-store';
import type { RawClient } from './service';
import type { ClientOptions } from './types';
import { createWebRawClient, type WebLibrary } from './web-client';

/** Name of the IndexedDB database of the one client this browser profile has. */
export const DATABASE_NAME = 'tnviewer';

/**
 * The browser has no keystore. The device credential and the signing key sit in `localStorage`, readable by any script of
 * this origin (client-lib/docs/integration-web.md, "Secrets are weaker"). The app serves no third-party scripts, and its
 * Content-Security-Policy forbids them; that is the whole protection, and it is stated in docs/web-limits.md.
 */
export const secureStore = createSecureStore({
  getItem: (key) => {
    try {
      return localStorage.getItem(key);
    } catch {
      return null;
    }
  },
  setItem: (key, value) => {
    try {
      localStorage.setItem(key, value);
    } catch {
      // storage refused (private mode, full): the device registers again next time
    }
  },
});

declare global {
  var __tnLibReady: Promise<WebLibrary> | undefined;
}

/** Where the app is served from, ending in a slash (a sub-path on GitHub Pages). */
function appBase(): string {
  const configured = (globalThis as { __tnBase?: string }).__tnBase; // set by tnlib-loader.js from its own address
  return (configured ?? new URL('./', globalThis.location?.href ?? 'http://localhost/').href).replace(/\/?$/, '/');
}

function loadLibrary(): Promise<WebLibrary> {
  return globalThis.__tnLibReady ?? Promise.reject(new Error('The library loader (tnlib-loader.js) is missing; build the web app with `npm run web:build`.'));
}

export function createNativeClient(options: Omit<ClientOptions, 'storagePath'>): RawClient {
  const base = appBase();
  return createWebRawClient({ loadLibrary, storagePath: DATABASE_NAME, wasm: `${base}tnlib/pkg/trafficnetwork_wasm_bg.wasm`, secureStore }, options);
}

/** Removes what the library stored for the device identity (credential, signing key). The access the user typed stays. */
export async function wipeLibrarySecrets(): Promise<void> {
  for (const key of keysToWipe(secureStore.keys(), [CREDENTIALS_KEY])) {
    try {
      localStorage.removeItem(key);
    } catch {
      // nothing more to do
    }
  }
}

/** Deletes the library's IndexedDB database. Close the client first. */
export function deleteLibraryData(): Promise<void> {
  return new Promise((resolve) => {
    try {
      const request = indexedDB.deleteDatabase(DATABASE_NAME);
      request.onsuccess = () => resolve();
      request.onerror = () => resolve();
      request.onblocked = () => resolve(); // another connection is still open; it goes with the page reload
    } catch {
      resolve();
    }
  });
}

/** Version of the library, for the info screen: read from the file the build copied (`tnlib/package.json`). */
export function getLibraryVersion(): string {
  return (globalThis as { __tnLibVersion?: string }).__tnLibVersion ?? '1.2.0 (WebAssembly)';
}

