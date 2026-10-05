import { createSecureStore, sanitizeKey, type SyncSecretBackend } from './secure-store';

function memoryBackend(): SyncSecretBackend & { data: Map<string, string> } {
  const data = new Map<string, string>();
  return {
    data,
    getItem: (k) => data.get(k) ?? null,
    setItem: (k, v) => void data.set(k, v),
  };
}

describe('secure store adapter', () => {
  it('only produces keys SecureStore accepts', () => {
    expect(sanitizeKey('device/credential:v1')).toBe('tn.device_credential_v1');
    expect(sanitizeKey('a b')).toMatch(/^[A-Za-z0-9._-]+$/);
  });

  it('returns undefined for missing entries and the value for stored ones', () => {
    const store = createSecureStore(memoryBackend());
    expect(store.get('k')).toBeUndefined();
    store.set('k', 'secret');
    expect(store.get('k')).toBe('secret');
  });

  it('treats a deleted entry as absent and allows setting it again', () => {
    const store = createSecureStore(memoryBackend());
    store.set('k', 'v1');
    store.delete_('k');
    expect(store.get('k')).toBeUndefined();
    store.set('k', 'v2');
    expect(store.get('k')).toBe('v2');
  });

  it('deleting something that was never stored writes nothing', () => {
    const backend = memoryBackend();
    createSecureStore(backend).delete_('never');
    expect(backend.data.size).toBe(0);
  });

  it('remembers every key it wrote once, so a reset can remove them', () => {
    const store = createSecureStore(memoryBackend());
    store.set('a', '1');
    store.set('b', '2');
    store.set('a', '3');
    expect(store.keys()).toEqual(['tn.a', 'tn.b']);
  });

  it('survives a corrupt key index', () => {
    const backend = memoryBackend();
    backend.setItem('tn.index', '{broken');
    const store = createSecureStore(backend);
    store.set('a', '1');
    expect(store.keys()).toEqual(['tn.a']);
  });
});
