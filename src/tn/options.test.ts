import { SEED_SERVERS } from '@/config';

import { buildClientOptions } from './options';

describe('buildClientOptions', () => {
  it('uses discovery from the built-in seeds when no server was entered', () => {
    const options = buildClientOptions({ serverAddress: null, credentials: undefined });
    expect(options.discovery).toBe(true);
    expect(options.seeds).toEqual([...SEED_SERVERS]);
    expect(options.nodes).toBeUndefined();
  });

  it('uses exactly the entered server and no discovery', () => {
    const options = buildClientOptions({ serverAddress: 'https://node.example.org', credentials: undefined });
    expect(options.discovery).toBe(false);
    expect(options.nodes).toEqual(['https://node.example.org']);
  });

  it('keeps the camera display off unless asked', () => {
    expect(buildClientOptions({ serverAddress: null, credentials: undefined }).cameraNamespaceEnabled).toBe(false);
    expect(buildClientOptions({ serverAddress: null, credentials: undefined, cameraNamespaceEnabled: true }).cameraNamespaceEnabled).toBe(true);
  });

  it('passes credentials through only when there are some', () => {
    expect(buildClientOptions({ serverAddress: null, credentials: undefined })).not.toHaveProperty('credentials');
    const credentials = { type: 'client', clientId: 'a', clientSecret: 'b' } as const;
    expect(buildClientOptions({ serverAddress: null, credentials }).credentials).toEqual(credentials);
  });
});
