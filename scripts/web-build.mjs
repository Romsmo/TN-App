// Builds the web app: Expo's web export, then scripts/web-postbuild.mjs. Portable (no shell variable syntax).
//   WEB_OUT=dist-web EXPO_BASE_URL=/TN-App node scripts/web-build.mjs
import { spawnSync } from 'node:child_process';

const out = process.env.WEB_OUT ?? 'dist-web';
const run = (command, args) => {
  const result = spawnSync(command, args, { stdio: 'inherit', shell: process.platform === 'win32' });
  if (result.status !== 0) process.exit(result.status ?? 1);
};
// --clear: EXPO_PUBLIC_* values are inlined while bundling, and Metro's cache does not know they changed
run('npx', ['expo', 'export', '--platform', 'web', '--output-dir', out, '--clear']);
run('node', ['scripts/web-postbuild.mjs', out]);
