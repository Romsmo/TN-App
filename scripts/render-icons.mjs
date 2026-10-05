// Renders assets/icon-src/*.svg to the PNGs the app uses, with headless Chromium.
// Usage: node scripts/render-icons.mjs   (needs `playwright-core` and a Chromium; not an app dependency)
import { chromium } from 'playwright-core';
import { readFileSync } from 'node:fs';

const jobs = [
  ['icon.svg', 'icon.png', false],
  ['icon-dark.svg', 'icon-dark.png', false],
  ['icon-tinted.svg', 'icon-tinted.png', false],
  ['android-foreground.svg', 'android-icon-foreground.png', true],
  ['android-background.svg', 'android-icon-background.png', false],
  ['android-monochrome.svg', 'android-icon-monochrome.png', true],
  ['splash.svg', 'splash-icon.png', true],
  ['splash-dark.svg', 'splash-icon-dark.png', true],
];
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const page = await browser.newPage({ viewport: { width: 1024, height: 1024 } });
for (const [from, to, transparent] of jobs) {
  const svg = readFileSync(new URL(`../assets/icon-src/${from}`, import.meta.url), 'utf8');
  await page.setContent(`<html><body style="margin:0;background:transparent">${svg}</body></html>`);
  await page.screenshot({ path: new URL(`../assets/images/${to}`, import.meta.url).pathname, omitBackground: transparent });
}
await browser.close();
