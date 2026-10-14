import { expect, test, type Page } from '@playwright/test';

const MOCK = 'http://127.0.0.1:18990';
const TAB = (page: Page, name: string) => page.getByRole('tab', { name });

async function openApp(page: Page) {
  await page.goto('./');
  await expect(TAB(page, 'Karte')).toBeVisible();
}

/** The install hint (phones) sits over the top of the map until it is dismissed; tests that use the map dismiss it first. */
async function dismissInstallHint(page: Page) {
  const later = page.getByRole('button', { name: 'Später' });
  if (await later.isVisible()) await later.click();
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

test.describe('the map', () => {
  test.beforeEach(async ({ context }) => {
    await context.grantPermissions(['geolocation']);
    await context.setGeolocation({ latitude: 52.0, longitude: 13.0, accuracy: 10 });
  });

  test('draws a report the user makes, and opens its details on a tap', async ({ page }) => {
    await openApp(page);
    await dismissInstallHint(page);
    await page.waitForFunction(() => Boolean((window as unknown as { __tnMap?: unknown }).__tnMap));
    await page.getByRole('button', { name: 'Melden', exact: true }).click();
    await expect(page.getByText('An deinem Standort')).toBeVisible({ timeout: 20_000 });
    await page.getByRole('button', { name: 'Stau melden' }).click();
    await expect(page.getByText(/Gespeichert/)).toBeVisible();

    type Probe = { __tnMap: { queryRenderedFeatures(o: object): { properties: { type: string } }[]; project(c: [number, number]): { x: number; y: number }; getCanvas(): HTMLCanvasElement } };
    await expect
      .poll(() => page.evaluate(() => (window as unknown as Probe).__tnMap.queryRenderedFeatures({ layers: ['hazards-circle'] }).map((f) => f.properties.type)), { timeout: 20_000 })
      .toContain('traffic');
    const where = await page.evaluate(() => {
      const map = (window as unknown as Probe).__tnMap;
      const rect = map.getCanvas().getBoundingClientRect();
      const p = map.project([13.0, 52.0]);
      return { x: rect.left + p.x, y: rect.top + p.y };
    });
    await page.mouse.click(where.x, where.y);
    await expect(page.getByRole('heading', { name: 'Stau' })).toBeVisible();
  });

  test('moves to the position of the device when it is known', async ({ page }) => {
    await openApp(page);
    await page.waitForFunction(() => Boolean((window as unknown as { __tnMap?: unknown }).__tnMap));
    await expect
      .poll(() => page.evaluate(() => (window as unknown as { __tnMap: { getCenter(): { lat: number } } }).__tnMap.getCenter().lat), { timeout: 20_000 })
      .toBeCloseTo(52.0, 1);
  });
});

test.describe('the arrow and "follows me"', () => {
  type Probe = {
    __tnMap: {
      queryRenderedFeatures(o: object): { properties: Record<string, unknown> }[];
      getCenter(): { lat: number; lng: number };
      getCanvas(): HTMLCanvasElement;
    };
  };
  test.beforeEach(async ({ context }) => {
    await context.grantPermissions(['geolocation']);
    await context.setGeolocation({ latitude: 52.0, longitude: 13.0, accuracy: 5 });
  });

  test('draws an arrow in the direction of travel (worked out from the positions) and an accuracy circle', async ({ page, context }) => {
    await openApp(page);
    await dismissInstallHint(page);
    await page.waitForFunction(() => Boolean((window as unknown as { __tnMap?: unknown }).__tnMap));
    // a first request for the position (the report button asks for permission and starts the live position)
    await page.getByRole('button', { name: 'Auf mich zentrieren' }).click();
    // 15 m per second to the east
    for (let i = 1; i <= 6; i++) {
      await context.setGeolocation({ latitude: 52.0, longitude: 13.0 + i * 0.00022, accuracy: 5 });
      await page.waitForTimeout(1100);
    }
    await expect
      .poll(() => page.evaluate(() => (window as unknown as Probe).__tnMap.queryRenderedFeatures({ layers: ['me-arrow'] })[0]?.properties.heading), { timeout: 15_000 })
      .toBeGreaterThan(80);
    const heading = await page.evaluate(() => Number((window as unknown as Probe).__tnMap.queryRenderedFeatures({ layers: ['me-arrow'] })[0]?.properties.heading));
    expect(heading).toBeLessThan(100);
    expect(await page.evaluate(() => (window as unknown as Probe).__tnMap.queryRenderedFeatures({ layers: ['me-accuracy'] }).length)).toBeGreaterThan(0);
  });

  test('cycles centre, follow, off; follows the position while on; a finger on the map ends it', async ({ page, context }) => {
    await openApp(page);
    await dismissInstallHint(page);
    await page.waitForFunction(() => Boolean((window as unknown as { __tnMap?: unknown }).__tnMap));
    const centre = () => page.evaluate(() => (window as unknown as Probe).__tnMap.getCenter());
    await page.getByRole('button', { name: 'Auf mich zentrieren' }).click(); // first press: permission, then centred
    await expect(page.getByRole('button', { name: 'Zentriert, tippen zum Folgen' })).toBeVisible();
    await page.getByRole('button', { name: 'Zentriert, tippen zum Folgen' }).click();
    await expect(page.getByRole('button', { name: 'Folgt dir, tippen zum Beenden' })).toBeVisible();

    await context.setGeolocation({ latitude: 52.003, longitude: 13.003, accuracy: 5 });
    await expect.poll(async () => (await centre()).lat, { timeout: 15_000 }).toBeCloseTo(52.003, 3);

    // a finger on the map: drag
    const box = (await page.locator('[role="application"]').boundingBox())!;
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.down();
    await page.mouse.move(box.x + box.width / 2 + 80, box.y + box.height / 2 + 60, { steps: 8 });
    await page.mouse.up();
    await expect(page.getByRole('button', { name: 'Auf mich zentrieren' })).toBeVisible();
  });
});


test.describe('speed limit and offline data', () => {
  type Probe = { __tnMap: { jumpTo(o: object): void; project(c: [number, number]): { x: number; y: number }; getCanvas(): HTMLCanvasElement } };
  test.beforeEach(async ({ context }) => {
    await context.grantPermissions(['geolocation']);
    await context.setGeolocation({ latitude: 52.0, longitude: 13.0, accuracy: 10 });
  });

  async function tapAt(page: Page, lng: number, lat: number) {
    const where = await page.evaluate(
      ([x, y]: [number, number]) => {
        const map = (window as unknown as Probe).__tnMap;
        map.jumpTo({ center: [x, y], zoom: 14 });
        return null;
      },
      [lng, lat] as [number, number],
    );
    expect(where).toBeNull();
    await page.waitForTimeout(500);
    const point = await page.evaluate(
      ([x, y]: [number, number]) => {
        const map = (window as unknown as Probe).__tnMap;
        const rect = map.getCanvas().getBoundingClientRect();
        const p = map.project([x, y]);
        return { x: rect.left + p.x, y: rect.top + p.y };
      },
      [lng, lat] as [number, number],
    );
    await page.mouse.click(point.x, point.y);
  }

  test('shows the limit of a tapped road from the offline data, and lets a stationary user correct it', async ({ page }) => {
    await openApp(page);
    await dismissInstallHint(page);
    await page.waitForFunction(() => Boolean((window as unknown as { __tnMap?: unknown }).__tnMap));
    await expect(page.getByRole('heading', { name: 'Notmodus' })).toHaveCount(0);
    await page.getByRole('button', { name: 'Tempolimit', exact: true }).click();
    await expect(page.getByText(/Tippe auf eine Straße/)).toBeVisible();
    await tapAt(page, 13.005, 52.0);
    await expect(page.getByLabel('Tempolimit 50 km/h')).toBeVisible({ timeout: 20_000 });
    await page.getByRole('button', { name: 'Stimmt nicht?' }).click();
    await expect(page.getByText('Nur eintragen, was die Beschilderung vor Ort zeigt.')).toBeVisible();
  });

  test('outside the offline area it asks the server (and the exact coordinate is what goes out)', async ({ page }) => {
    const asked: string[] = [];
    page.on('request', (r) => {
      if (r.url().includes('/v1/speed-limit?')) asked.push(new URL(r.url()).search);
    });
    await openApp(page);
    await dismissInstallHint(page);
    await page.waitForFunction(() => Boolean((window as unknown as { __tnMap?: unknown }).__tnMap));
    await expect(page.getByRole('heading', { name: 'Notmodus' })).toHaveCount(0);
    await page.getByRole('button', { name: 'Tempolimit', exact: true }).click();
    await tapAt(page, 10.0, 45.0);
    await expect(page.getByLabel('Tempolimit 80 km/h')).toBeVisible({ timeout: 20_000 });
    expect(asked.length).toBeGreaterThan(0);
    expect(asked[0]).toMatch(/lat=45(\.\d+)?&lng=10(\.\d+)?/);
  });

  test('the offline data screen lists the regions with their size and the note about online-only', async ({ page }) => {
    await openApp(page);
    await dismissInstallHint(page);
    await expect(page.getByRole('heading', { name: 'Notmodus' })).toHaveCount(0);
    await TAB(page, 'Einstellungen').click();
    await page.getByRole('link', { name: /Offline-Daten/ }).click();
    await expect(page.getByText('Automatisch', { exact: true }).first()).toBeVisible();
    await expect(page.getByText(/Belegt auf diesem Gerät/)).toBeVisible({ timeout: 20_000 });
    await expect(page.getByText(/Außerhalb des Offline-Bereichs gibt es Tempolimits nur online/)).toBeVisible();
    await expect(page.getByText('Deutschland').first()).toBeVisible({ timeout: 20_000 });
  });
});
