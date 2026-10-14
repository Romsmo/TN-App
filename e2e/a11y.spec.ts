import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';

// WCAG 2.2 AA (and the A levels below it). The drive mode is left out on purpose: its own rules (very large targets, no
// text input) are tested in the unit tests; this checks the screens a person uses while standing.
const TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'];

async function audit(page: Page) {
  // axe brings its own copy of the Playwright types; the page object is the same
  const results = await new AxeBuilder({ page: page as never }).withTags(TAGS).analyze();
  return results.violations.map((v) => `${v.id} (${v.impact}): ${v.help} — ${v.nodes.slice(0, 3).map((n) => n.target.join(' ')).join(', ')}`);
}

test.beforeEach(async ({ context, page }) => {
  await context.grantPermissions(['geolocation']);
  await context.setGeolocation({ latitude: 52.0, longitude: 13.0, accuracy: 5 });
  await page.goto('./');
  await expect(page.getByRole('tab', { name: 'Karte' })).toBeVisible();
  await page.getByRole('button', { name: 'Später' }).click().catch(() => undefined);
  await page.waitForTimeout(1500);
});

test('the map screen', async ({ page }) => {
  expect(await audit(page)).toEqual([]);
});

test('the list of reports', async ({ page }) => {
  await page.getByRole('button', { name: 'Als Liste anzeigen' }).click();
  expect(await audit(page)).toEqual([]);
});

test('the report sheet', async ({ page }) => {
  await page.getByRole('button', { name: 'Melden', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Was möchtest du melden?' })).toBeVisible();
  expect(await audit(page)).toEqual([]);
});

test('the drive start screen', async ({ page }) => {
  await page.getByRole('tab', { name: 'Fahrmodus' }).click();
  expect(await audit(page)).toEqual([]);
});

test('the settings', async ({ page }) => {
  await page.getByRole('tab', { name: 'Einstellungen' }).click();
  await expect(page.getByRole('heading', { name: 'Einstellungen' })).toBeVisible();
  expect(await audit(page)).toEqual([]);
});

for (const [link, heading] of [
  ['Server verbinden', 'Server verbinden'],
  ['Datenpakete', 'Datenpakete'],
  ['Quellen und Lizenzen', 'Quellen und Lizenzen'],
] as const) {
  test(`the screen "${link}"`, async ({ page }) => {
    await page.getByRole('tab', { name: 'Einstellungen' }).click();
    await page.getByRole('link', { name: new RegExp(link) }).click();
    await expect(page.getByRole('heading', { name: heading }).first()).toBeVisible();
    expect(await audit(page)).toEqual([]);
  });
}

test('the emergency mode card', async ({ page }) => {
  await page.route('http://127.0.0.1:18990/**', (route) => route.abort('connectionrefused'));
  await page.reload();
  await expect(page.getByRole('heading', { name: 'Notmodus' })).toBeVisible({ timeout: 30_000 });
  expect(await audit(page)).toEqual([]);
});

test.describe('dark', () => {
  test.use({ colorScheme: 'dark' });
  test('the map screen and the settings', async ({ page }) => {
    expect(await audit(page)).toEqual([]);
    await page.getByRole('tab', { name: 'Einstellungen' }).click();
    await expect(page.getByRole('heading', { name: 'Einstellungen' })).toBeVisible();
    expect(await audit(page)).toEqual([]);
  });
});
