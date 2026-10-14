import { expect, test, type Page } from '@playwright/test';

const TAB = (page: Page, name: string) => page.getByRole('tab', { name });

test.beforeEach(async ({ context, page }) => {
  await context.grantPermissions(['geolocation']);
  await context.setGeolocation({ latitude: 52.0, longitude: 13.0, accuracy: 5 });
  // a stand-in for the Screen Wake Lock that counts what the app asks for
  await page.addInitScript(() => {
    const counts = { requested: 0, released: 0 };
    (window as unknown as { __wake: typeof counts }).__wake = counts;
    Object.defineProperty(navigator, 'wakeLock', {
      configurable: true,
      value: {
        request: async () => {
          counts.requested++;
          return { release: async () => void counts.released++, addEventListener: () => undefined };
        },
      },
    });
  });
  await page.goto('./');
  await expect(TAB(page, 'Karte')).toBeVisible();
  const later = page.getByRole('button', { name: 'Später' });
  if (await later.isVisible()) await later.click();
});

const wake = (page: Page) => page.evaluate(() => (window as unknown as { __wake: { requested: number; released: number } }).__wake);

test('the simulated drive warns ahead, locks the settings, keeps the screen on and ends cleanly', async ({ page }) => {
  test.setTimeout(150_000);
  await TAB(page, 'Fahrmodus').click();
  await page.getByRole('button', { name: 'Fahrt simulieren (4× schneller)' }).click();
  // the legal notice comes first, every time the drive mode starts for the first time
  await expect(page.getByRole('heading', { name: 'Bevor es losgeht' })).toBeVisible();
  await page.getByRole('button', { name: 'Verstanden' }).click();
  await expect(page.getByText('SIMULATION – keine echte Fahrt')).toBeVisible();
  await expect.poll(async () => (await wake(page)).requested).toBeGreaterThan(0);

  // a warning with its distance (first warning of the invented route)
  await expect(page.getByText(/^in \d+ m$/).first()).toBeVisible({ timeout: 100_000 });

  // above 10 km/h the settings are locked
  await TAB(page, 'Einstellungen').click();
  await expect(page.getByRole('heading', { name: 'Gesperrt während der Fahrt' })).toBeVisible();

  await TAB(page, 'Fahrmodus').click();
  await page.getByRole('button', { name: 'Beenden' }).click();
  await expect(page.getByRole('button', { name: 'Fahrt starten' })).toBeVisible();
  await expect.poll(async () => (await wake(page)).released).toBeGreaterThan(0);
});

test('a real drive works out speed and heading from the positions (browsers without speed), shows the limit and locks the settings', async ({ page, context }) => {
  test.setTimeout(120_000);
  await TAB(page, 'Fahrmodus').click();
  await page.getByRole('button', { name: 'Fahrt starten' }).click();
  await page.getByRole('button', { name: 'Verstanden' }).click();
  await expect(page.getByRole('button', { name: 'Beenden' })).toBeVisible({ timeout: 20_000 });

  // 20 m per second to the east, along the mock server's road [(13.0, 52.0) to (13.01, 52.0)]: 72 km/h, with no speed and no
  // heading in the positions themselves
  for (let i = 0; i < 20; i++) {
    await context.setGeolocation({ latitude: 52.0, longitude: 13.0 + i * 0.000292, accuracy: 5 });
    await page.waitForTimeout(1000);
  }
  const speed = await page.getByLabel(/km\/h/).first().getAttribute('aria-label');
  const kmh = Number(/^(\d+)/.exec(speed ?? '')?.[1]);
  expect(kmh).toBeGreaterThan(55);
  expect(kmh).toBeLessThan(90);
  await expect(page.getByLabel('Tempolimit 50')).toBeVisible();

  await TAB(page, 'Einstellungen').click();
  await expect(page.getByRole('heading', { name: 'Gesperrt während der Fahrt' })).toBeVisible();
  await TAB(page, 'Fahrmodus').click();
  await page.getByRole('button', { name: 'Beenden' }).click();
});

test('says so when the screen cannot be kept on', async ({ page }) => {
  await page.evaluate(() => {
    Object.defineProperty(navigator, 'wakeLock', { configurable: true, value: { request: async () => Promise.reject(new Error('refused')) } });
  });
  await TAB(page, 'Fahrmodus').click();
  await page.getByRole('button', { name: 'Fahrt simulieren' }).first().click();
  await page.getByRole('button', { name: 'Verstanden' }).click();
  await expect(page.getByText('Bildschirm bleibt nicht von selbst an')).toBeVisible();
  await page.getByRole('button', { name: 'Beenden' }).click();
});
