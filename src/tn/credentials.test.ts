import { CREDENTIALS_KEY, createCredentialsStore, parseCredentials, type SecretStore } from './credentials';

function memorySecrets(): SecretStore & { data: Map<string, string> } {
  const data = new Map<string, string>();
  return { data, get: (k) => data.get(k), set: (k, v) => void data.set(k, v), delete_: (k) => void data.delete(k) };
}

describe('parseCredentials', () => {
  it('accepts both kinds and rejects incomplete or foreign data', () => {
    expect(parseCredentials(JSON.stringify({ type: 'client', clientId: 'a', clientSecret: 'b' }))).toEqual({ type: 'client', clientId: 'a', clientSecret: 'b' });
    expect(parseCredentials(JSON.stringify({ type: 'app', appClientId: 'a', appClientSecret: 'b' }))).toEqual({ type: 'app', appClientId: 'a', appClientSecret: 'b' });
    expect(parseCredentials(JSON.stringify({ type: 'client', clientId: '', clientSecret: 'b' }))).toBeUndefined();
    expect(parseCredentials(JSON.stringify({ type: 'other' }))).toBeUndefined();
    expect(parseCredentials('nope')).toBeUndefined();
    expect(parseCredentials(undefined)).toBeUndefined();
  });
});

describe('credentials store', () => {
  it('keeps what was set across instances and forgets on clear', () => {
    const secrets = memorySecrets();
    const store = createCredentialsStore(secrets);
    expect(store.get()).toBeUndefined();
    store.set({ type: 'app', appClientId: 'id', appClientSecret: 'secret' });
    expect(createCredentialsStore(secrets).get()).toEqual({ type: 'app', appClientId: 'id', appClientSecret: 'secret' });
    store.clear();
    expect(secrets.data.has(CREDENTIALS_KEY)).toBe(false);
    expect(createCredentialsStore(secrets).get()).toBeUndefined();
  });

  it('notifies listeners on set and clear', () => {
    const store = createCredentialsStore(memorySecrets());
    const listener = jest.fn();
    store.subscribe(listener);
    store.set({ type: 'client', clientId: 'a', clientSecret: 'b' });
    store.clear();
    expect(listener).toHaveBeenCalledTimes(2);
  });
});
