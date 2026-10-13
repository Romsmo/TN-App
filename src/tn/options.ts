import { DEFAULT_NODE, NETWORK_ROOT_KEY, PUBLIC_APP_KEY, SEED_SERVERS } from '@/config';

import type { ClientOptions, Credentials } from './types';

/**
 * The library options for the current settings. A server the user entered is used directly and alone (no discovery);
 * otherwise the library discovers servers from the seeds, starting with the build's default node if it has one.
 */
export function buildClientOptions(input: {
  serverAddress: string | null;
  credentials: Credentials | undefined;
  cameraNamespaceEnabled?: boolean;
}): Omit<ClientOptions, 'storagePath'> {
  const options: Omit<ClientOptions, 'storagePath'> = input.serverAddress
    ? { discovery: false, nodes: [input.serverAddress] }
    : DEFAULT_NODE
      ? { discovery: true, nodes: [DEFAULT_NODE], seeds: [DEFAULT_NODE, ...SEED_SERVERS] }
      : { discovery: true, seeds: [...SEED_SERVERS] };
  if (NETWORK_ROOT_KEY) options.networkRootKey = NETWORK_ROOT_KEY;
  // Access the user typed wins; otherwise a build that is open to everyone registers the device with its public app key.
  if (input.credentials) options.credentials = input.credentials;
  else if (PUBLIC_APP_KEY) options.credentials = { type: 'app', appClientId: PUBLIC_APP_KEY.id, appClientSecret: PUBLIC_APP_KEY.secret };
  options.cameraNamespaceEnabled = input.cameraNamespaceEnabled ?? false;
  return options;
}
