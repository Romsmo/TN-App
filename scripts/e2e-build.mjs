// The web app as the browser tests need it: wired to the mock server of the client library, with a public app key
// that only exists for the tests. Never published.
import { spawnSync } from 'node:child_process';

const env = {
  ...process.env,
  WEB_OUT: 'dist-e2e',
  EXPO_BASE_URL: '/TN-App',
  WEB_CONNECT_EXTRA: 'http://127.0.0.1:18990 ws://127.0.0.1:18990',
  EXPO_PUBLIC_TN_DEFAULT_NODE: 'http://127.0.0.1:18990/i/1',
  EXPO_PUBLIC_TN_APP_CLIENT_ID: 'e2e-app',
  EXPO_PUBLIC_TN_APP_CLIENT_SECRET: 'e2e-secret',
};
const result = spawnSync('node', ['scripts/web-build.mjs'], { stdio: 'inherit', env });
process.exit(result.status ?? 1);
