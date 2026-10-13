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

  describe('a build with a default node and a public app key (the web test app)', () => {
    const load = () => {
      let module!: typeof import('./options');
      jest.isolateModules(() => {
        process.env.EXPO_PUBLIC_TN_DEFAULT_NODE = 'https://node.example.org';
        process.env.EXPO_PUBLIC_TN_APP_CLIENT_ID = 'app-id';
        process.env.EXPO_PUBLIC_TN_APP_CLIENT_SECRET = 'app-secret';
        // eslint-disable-next-line @typescript-eslint/no-require-imports
        module = require('./options');
      });
      delete process.env.EXPO_PUBLIC_TN_DEFAULT_NODE;
      delete process.env.EXPO_PUBLIC_TN_APP_CLIENT_ID;
      delete process.env.EXPO_PUBLIC_TN_APP_CLIENT_SECRET;
      return module;
    };

    it('tries the default node first and still discovers from the seeds', () => {
      const options = load().buildClientOptions({ serverAddress: null, credentials: undefined });
      expect(options.discovery).toBe(true);
      expect(options.nodes).toEqual(['https://node.example.org']);
      expect(options.seeds?.[0]).toBe('https://node.example.org');
    });

    it('registers a fresh device with the public app key', () => {
      expect(load().buildClientOptions({ serverAddress: null, credentials: undefined }).credentials).toEqual({ type: 'app', appClientId: 'app-id', appClientSecret: 'app-secret' });
    });

    it('lets access the user typed win over the public app key', () => {
      const typed = { type: 'client', clientId: 'a', clientSecret: 'b' } as const;
      expect(load().buildClientOptions({ serverAddress: null, credentials: typed }).credentials).toEqual(typed);
    });

    it('lets an entered server win over the default node', () => {
      const options = load().buildClientOptions({ serverAddress: 'https://other.example.org', credentials: undefined });
      expect(options).toMatchObject({ discovery: false, nodes: ['https://other.example.org'] });
    });
  });
});
