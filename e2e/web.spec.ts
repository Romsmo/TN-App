import { expect, test, type Page } from '@playwright/test';

const MOCK = 'http://127.0.0.1:18990';
const TAB = (page: Page, name: string) => page.getByRole('tab', { name });

async function openApp(page: Page) {
  await page.goto('./');
  await expect(TAB(page, 'Karte')).toBeVisible();
}

test.describe('the installable web app', () => {
  test.beforeEach(async ({ context }) => {
    await context.grantPermissions(['geolocation']);
    await context.setGeolocation({ latitude: 52.0, longitude: 13.0, accuracy: 10 });
  });

  test('starts under the sub-path, loads the library (WebAssembly) and says "Testversion"', async ({ page }) => {
    await openApp(page);
    expect(new URL(page.url()).pathname).toBe('/TN-App/');
    const exports = await page.evaluate(async () => Object.keys(await (window as unknown as { __tnLibReady: Promise<object> }).__tnLibReady));
    expect(exports).toContain('Client');
    await expect(page.getByText('Testversion')).toBeVisible();
  });

  test('registers the device with the public app key and loads the data around the position (mock server)', async ({ page }) => {
    const calls: string[] = [];
    page.on('request', (r) => {
      if (r.url().startsWith(MOCK)) calls.push(`${r.method()} ${new URL(r.url()).pathname.replace('/i/1', '')}`);
    });
    await openApp(page);
    await expect.poll(() => calls.some((c) => c.startsWith('GET /v1/static-data/partitions/')), { timeout: 30_000 }).toBe(true);
    expect(calls).toContain('POST /v1/devices/register');
    expect(calls).toContain('POST /v1/devices/bind-key');
    await expect(page.getByRole('heading', { name: 'Notmodus' })).toHaveCount(0);
  });

  test('talks only to its own origin and to the configured server', async ({ page }) => {
    const origins = new Set<string>();
    page.on('request', (r) => {
      if (!r.url().startsWith('data:') && !r.url().startsWith('blob:')) origins.add(new URL(r.url()).origin);
    });
    await openApp(page);
    await page.waitForTimeout(4000);
    expect([...origins].sort()).toEqual(['http://127.0.0.1:18990', 'http://localhost:4174']);
  });

  test('shows the emergency mode when no server answers, and ends it when one does', async ({ page }) => {
    await page.route(`${MOCK}/**`, (route) => route.abort('connectionrefused'));
    await openApp(page);
    await expect(page.getByRole('heading', { name: 'Notmodus' })).toBeVisible({ timeout: 30_000 });
    await expect(page.getByRole('button', { name: 'Erneut versuchen' })).toBeVisible();
    await page.unroute(`${MOCK}/**`);
    await page.getByRole('button', { name: 'Erneut versuchen' }).click();
    await expect(page.getByRole('heading', { name: 'Notmodus' })).toHaveCount(0, { timeout: 30_000 });
  });

  test('starts again without any network after one visit (service worker)', async ({ page, context }) => {
    await openApp(page);
    await page.evaluate(() => navigator.serviceWorker.ready.then(() => undefined));
    await page.reload(); // now controlled by the service worker
    await expect.poll(() => page.evaluate(() => navigator.serviceWorker.controller !== null)).toBe(true);
    await context.setOffline(true);
    await page.reload();
    await expect(TAB(page, 'Fahrmodus')).toBeVisible();
    await context.setOffline(false);
  });

  test('offers an update when a new version waits, and applies it on request', async ({ page }) => {
    await openApp(page);
    await page.evaluate(() => {
      const w = window as unknown as { __tnWaiting: unknown; __tnApplyUpdate: () => void; __applied?: boolean };
      w.__tnWaiting = {};
      w.__tnApplyUpdate = () => {
        w.__applied = true;
      };
      window.dispatchEvent(new Event('tn-update-available'));
    });
    await expect(page.getByText('Eine neue Version ist da.')).toBeVisible();
    await page.getByRole('button', { name: 'Aktualisieren' }).click();
    expect(await page.evaluate(() => (window as unknown as { __applied?: boolean }).__applied)).toBe(true);
  });

  test('runs only in one tab at a time', async ({ page, context }) => {
    await openApp(page);
    const second = await context.newPage();
    await second.goto('./');
    await expect(second.getByRole('heading', { name: 'Schon geöffnet' })).toBeVisible();
    await expect(second.getByRole('tab', { name: 'Karte' })).toHaveCount(0);
    await second.close();
  });

  test('the speed-camera filter is off at the first start', async ({ page }) => {
    await openApp(page);
    await TAB(page, 'Einstellungen').click();
    await expect(page.getByRole('switch', { name: 'Blitzer anzeigen und melden' })).not.toBeChecked();
  });
});

test.describe('install hint', () => {
  test('is shown on a phone in a browser tab, and stays away once dismissed', async ({ page, isMobile }) => {
    test.skip(!isMobile, 'phone projects only');
    await openApp(page);
    await expect(page.getByText('Als App installieren')).toBeVisible();
    await page.getByRole('button', { name: 'Später' }).click();
    await expect(page.getByText('Als App installieren')).toHaveCount(0);
    await page.reload();
    await expect(TAB(page, 'Karte')).toBeVisible();
    await expect(page.getByText('Als App installieren')).toHaveCount(0);
  });

  test('names the iPhone steps on an iPhone and the browser menu on Android', async ({ page }, info) => {
    await openApp(page);
    const text = info.project.name === 'iphone-size' ? /Zum Home-Bildschirm/ : /App installieren“ oder „Zum Startbildschirm/;
    await expect(page.getByText(text)).toBeVisible();
  });
});
