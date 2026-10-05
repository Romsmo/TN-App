/** Synchronous key/value backend with the shape of expo-secure-store's getItem/setItem. */
export interface SyncSecretBackend {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}

/** What the library's `SecureStore` callback interface asks for (client-lib README: it must answer synchronously). */
export interface LibrarySecureStore {
  get(key: string): string | undefined;
  set(key: string, value: string): void;
  delete_(key: string): void;
}

const INDEX_KEY = 'tn.index';
/** expo-secure-store has no synchronous delete: a deleted entry is overwritten with this marker and reads as absent. */
const TOMBSTONE = '\u0000deleted';

/** SecureStore only accepts letters, digits, ".", "-" and "_" in keys. */
export function sanitizeKey(key: string): string {
  return `tn.${key.replace(/[^A-Za-z0-9._-]/g, '_')}`;
}

/**
 * Keeps the library's device credential and signing key in the Keychain/Keystore.
 * Remembers which keys it wrote, so "reset device identity" can remove them all.
 */
export function createSecureStore(backend: SyncSecretBackend): LibrarySecureStore & { keys(): string[] } {
  const readIndex = (): string[] => {
    try {
      const parsed: unknown = JSON.parse(backend.getItem(INDEX_KEY) ?? '[]');
      return Array.isArray(parsed) ? parsed.filter((k): k is string => typeof k === 'string') : [];
    } catch {
      return [];
    }
  };
  const remember = (storageKey: string) => {
    const index = readIndex();
    if (!index.includes(storageKey)) backend.setItem(INDEX_KEY, JSON.stringify([...index, storageKey]));
  };

  return {
    get(key) {
      const value = backend.getItem(sanitizeKey(key));
      return value === null || value === TOMBSTONE ? undefined : value;
    },
    set(key, value) {
      const storageKey = sanitizeKey(key);
      backend.setItem(storageKey, value);
      remember(storageKey);
    },
    delete_(key) {
      const storageKey = sanitizeKey(key);
      if (backend.getItem(storageKey) !== null) backend.setItem(storageKey, TOMBSTONE);
    },
    keys: readIndex,
  };
}

/** The Keychain keys a "reset device identity" removes: everything the library wrote, but none of the `keep` entries (e.g. the access data the user typed). */
export function keysToWipe(allKeys: readonly string[], keep: readonly string[]): string[] {
  const kept = new Set(keep.map(sanitizeKey));
  return allKeys.filter((key) => key !== INDEX_KEY && !kept.has(key));
}
