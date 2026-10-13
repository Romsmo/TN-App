import { existsSync } from 'node:fs';

import { defineConfig, devices } from '@playwright/test';

/**
 * Browser tests of the web app. They run the exported app (`npm run e2e:build` -> dist-e2e) in a phone-sized Chromium
 * against the Trafficnetwork client library's own scripted mock server (client-lib/conformance/mock-server.mjs, real
 * signatures, no real server) — a mock, not the operator's server, and not a real phone or Safari.
 *
 * TRAFFICNETWORK_DIR: a checkout of the Trafficnetwork repository (CI checks out the release tag of the library).
 */
const trafficnetwork = process.env.TRAFFICNETWORK_DIR ?? (existsSync('/home/user/romsmo/trafficnetwork') ? '/home/user/romsmo/trafficnetwork' : '../Trafficnetwork');
const MOCK_PORT = 18990;
const APP_PORT = 4174;

export default defineConfig({
  testDir: 'e2e',
  timeout: 60_000,
  expect: { timeout: 15_000 },
  fullyParallel: false,
  workers: 1,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL: `http://localhost:${APP_PORT}/TN-App/`,
    locale: 'de-DE',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  globalSetup: './e2e/global-setup.ts',
  webServer: [
    { command: `node ${trafficnetwork}/client-lib/conformance/mock-server.mjs --port ${MOCK_PORT}`, port: MOCK_PORT, reuseExistingServer: !process.env.CI },
    { command: `node scripts/web-serve.mjs dist-e2e ${APP_PORT} /TN-App`, port: APP_PORT, reuseExistingServer: !process.env.CI },
  ],
  projects: [
    // Chromium with an Android phone's screen, touch and user agent
    { name: 'android', use: { ...devices['Pixel 7'] } },
    // Chromium with an iPhone's screen and user agent: the layout and the install hint, NOT Safari's behaviour
    { name: 'iphone-size', use: { viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true, userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1' } },
  ],
});
