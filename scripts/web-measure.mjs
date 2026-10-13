// Measures the web app in Chromium: bytes of the first load, time until the app is usable on a slow mobile connection,
// and the browser storage after the first sync. Needs the test build (npm run e2e:build) and the mock server of the
// client library; prints Markdown for docs/web-geraetetest.md. Numbers from a desktop Chromium, not from a phone.
//   TRAFFICNETWORK_DIR=… node scripts/web-measure.mjs
import { spawn } from 'node:child_process';
import { chromium } from '@playwright/test';

const dir = process.env.TRAFFICNETWORK_DIR ?? '/home/user/romsmo/trafficnetwork';
const children = [
  spawn('node', [`${dir}/client-lib/conformance/mock-server.mjs`, '--port', '18990'], { stdio: 'ignore' }),
  spawn('node', ['scripts/web-serve.mjs', 'dist-e2e', '4174', '/TN-App'], { stdio: 'ignore' }),
];
await new Promise((r) => setTimeout(r, 1500));
await fetch('http://127.0.0.1:18990/__instances', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ cameraNamespace: true, cameraPolicy: { defaultLevel: 'full', byCountry: {}, namespaceEnabled: true }, cameraData: { camera: true } }) });

const browser = await chromium.launch(process.env.PW_CHROMIUM ? { executablePath: process.env.PW_CHROMIUM } : {});
const rows = [];
for (const [label, conditions] of [
  ['schnelles Netz (kein Limit)', null],
  ['langsames Mobilfunknetz (1,6 Mbit/s, 150 ms)', { offline: false, latency: 150, downloadThroughput: (1.6 * 1024 * 1024) / 8, uploadThroughput: (750 * 1024) / 8 }],
]) {
  const context = await browser.newContext({ locale: 'de-DE', viewport: { width: 390, height: 844 }, geolocation: { latitude: 52, longitude: 13 }, permissions: ['geolocation'], isMobile: true });
  const page = await context.newPage();
  const client = await context.newCDPSession(page);
  await client.send('Network.enable');
  if (conditions) await client.send('Network.emulateNetworkConditions', conditions);
  let wire = 0;
  const byType = new Map();
  client.on('Network.loadingFinished', (e) => {
    wire += e.encodedDataLength;
  });
  client.on('Network.responseReceived', (e) => byType.set(e.requestId, e.response.url.split('/').slice(3).join('/').split('?')[0]));
  page.on('pageerror', (e) => console.error('pageerror', e.message));
  page.on('console', (m) => m.type() === 'error' && console.error('console', m.text().slice(0, 160)));
  console.error('start', label);
  page.on('requestfailed', (r) => console.error('failed', r.url().slice(0, 90), r.failure()?.errorText));
  const start = Date.now();
  await page.goto('http://localhost:4174/TN-App/');
  await page.getByRole('tab', { name: 'Karte' }).waitFor({ timeout: 120_000 });
  const shell = Date.now() - start;
  await page.waitForFunction(() => Boolean(window.__tnMap), undefined, { timeout: 120_000 });
  const map = Date.now() - start;
  await page.waitForTimeout(4000);
  const storage = await page.evaluate(async () => {
    const e = await navigator.storage.estimate();
    return { usage: e.usage ?? 0, local: JSON.stringify(localStorage).length };
  });
  rows.push({ label, wire, shell, map, storage });
  await context.close();
}
await browser.close();
children.forEach((c) => c.kill());
const kb = (n) => `${(n / 1024).toFixed(0)} kB`;
console.log('| Verbindung | Übertragen beim ersten Laden (komprimiert, bis die Karte steht + 4 s) | App-Rahmen sichtbar | Karte steht | Speicher des Browsers danach |');
console.log('|---|---|---|---|---|');
for (const r of rows) console.log(`| ${r.label} | ${kb(r.wire)} | ${(r.shell / 1000).toFixed(1)} s | ${(r.map / 1000).toFixed(1)} s | ${kb(r.storage.usage)} (IndexedDB, Cache, Local Storage) |`);
