import type { Credentials } from './types';

/** The part of the secure store this needs (the same shape the library's store has). */
export interface SecretStore {
  get(key: string): string | undefined;
  set(key: string, value: string): void;
  delete_(key: string): void;
}

/** Library secrets live under `tn.<key>`; the access data the user typed is kept under its own name so a device reset leaves it alone. */
export const CREDENTIALS_KEY = 'app_access';

export function parseCredentials(raw: string | undefined): Credentials | undefined {
  if (!raw) return undefined;
  try {
    const o = JSON.parse(raw) as Record<string, unknown>;
    if (o.type === 'client' && typeof o.clientId === 'string' && typeof o.clientSecret === 'string' && o.clientId && o.clientSecret) {
      return { type: 'client', clientId: o.clientId, clientSecret: o.clientSecret };
    }
    if (o.type === 'app' && typeof o.appClientId === 'string' && typeof o.appClientSecret === 'string' && o.appClientId && o.appClientSecret) {
      return { type: 'app', appClientId: o.appClientId, appClientSecret: o.appClientSecret };
    }
  } catch {
    // fall through
  }
  return undefined;
}

export interface CredentialsStore {
  get(): Credentials | undefined;
  set(credentials: Credentials): void;
  clear(): void;
  subscribe(listener: () => void): () => void;
}

export function createCredentialsStore(secrets: SecretStore): CredentialsStore {
  const listeners = new Set<() => void>();
  const emit = () => listeners.forEach((l) => l());
  let cached = parseCredentials(secrets.get(CREDENTIALS_KEY));
  return {
    get: () => cached,
    set(credentials) {
      secrets.set(CREDENTIALS_KEY, JSON.stringify(credentials));
      cached = credentials;
      emit();
    },
    clear() {
      secrets.delete_(CREDENTIALS_KEY);
      cached = undefined;
      emit();
    },
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
  };
}
