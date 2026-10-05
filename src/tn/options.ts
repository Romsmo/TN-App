import { NETWORK_ROOT_KEY, SEED_SERVERS } from '@/config';

import type { ClientOptions, Credentials } from './types';

/**
 * The library options for the current settings. A server the user entered is used directly and alone (no discovery);
 * otherwise the library discovers servers from the built-in seeds.
 */
export function buildClientOptions(input: {
  serverAddress: string | null;
  credentials: Credentials | undefined;
  cameraNamespaceEnabled?: boolean;
}): Omit<ClientOptions, 'storagePath'> {
  const options: Omit<ClientOptions, 'storagePath'> = input.serverAddress
    ? { discovery: false, nodes: [input.serverAddress] }
    : { discovery: true, seeds: [...SEED_SERVERS] };
  if (NETWORK_ROOT_KEY) options.networkRootKey = NETWORK_ROOT_KEY;
  if (input.credentials) options.credentials = input.credentials;
  options.cameraNamespaceEnabled = input.cameraNamespaceEnabled ?? false;
  return options;
}
