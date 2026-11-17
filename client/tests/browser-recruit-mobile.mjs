import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { signInLocal } from './browser-login.mjs';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const root = process.env.CAS_ARTIFACTS || 'artifacts/client/recruit-mobile/';
const url = process.env.CAS_TEST_URL || 'http://127.0.0.1:5175/';
const portKey = 'cas.profile.test-commander.cas.harbor.progress.v1';
if (!root.endsWith('/')) throw new Error('CAS_ARTIFACTS must end with a slash');
await fs.mkdir(root, { recursive: true });

const seed = {
  version: 1,
  lessons: [],
  starter: false, challengeClear: false, challengeClaim: false,
  wallet: { standard: 0, up: 0 }, marks: 0, pity: { standard: 0, up: 0 }, owned: {},
  profiles: ['coord'], preset: { side: 'allies', leaderSlot: 0, profile: 'coord' },
  upSide: 'axis', sequence: 0, history: [], credits: 0, courses: [], attendance: [],
  challengeReceipts: {},
  mail: [{ id: 'welcome-20', title: '内测启航补给', body: '20 次征募补给已放入邮箱，请在邮箱领取。', sender: '舰桥补给处', created: 0, claimed: false, standard: 20, up: 0 }],
};

const errors = [];
const browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });
const page = await (await browser.newContext({ viewport: { width: 740, height: 360 }, locale: 'zh-CN' })).newPage();
page.on('pageerror', error => errors.push(error.stack));
const readPort = () => page.evaluate(key => JSON.parse(localStorage.getItem(key) || 'null'), portKey);
const overflow = () => page.evaluate(() =>
  document.documentElement.scrollWidth > window.innerWidth || document.body.scrollWidth > window.innerWidth);
const drawer = name => page.locator(`[data-drawer="${name}"]`);

async function closeArrival() {
  const dialog = page.locator('dialog.recruit-arrival');
  await dialog.waitFor();
  await dialog.getByRole('button', { name: '跳过动画' }).click();
  await dialog.getByRole('button', { name: '确认入列' }).click();
  await dialog.waitFor({ state: 'detached' });
}

try {
  await page.addInitScript(([key, value]) => {
    if (!localStorage.getItem('cas.mobile-recruit.seeded')) {
      localStorage.setItem(key, JSON.stringify(value));
      localStorage.setItem('cas.mobile-recruit.seeded', '1');
    }
  }, [portKey, seed]);
  await page.goto(url);
  await signInLocal(page, 'cas-mobile-recruit', true);
  await page.locator('.growth-port').waitFor();
  await page.locator('.growth-dock button[data-guide="economy"]').click();
  await page.locator('.quartermaster').waitFor();

  assert.equal(await page.locator('.harbor-mobile-nav').isVisible(), true, 'mobile bottom nav is visible at 740');
  assert.equal(await page.locator('.harbor-mobile-nav button').count(), 6, 'five sections plus direct recruit');
  assert.equal(await page.locator('.harbor-mobile-nav [data-mobile-draw]').count(), 1);
  await page.screenshot({ path: root + 'quartermaster-mobile.png' });

  // Direct recruit: no training/starter gate; the welcome supply is a one-tap claim.
  await page.locator('[data-mobile-draw]').click();
  await page.locator('.recruit-screen').waitFor();
  assert.equal(await page.locator('.rs-block').count(), 0, 'no tutorial/starter block');
  assert.equal(await page.locator('.rs-hint button').count(), 1, 'welcome supply can be claimed from the recruit screen');
  assert.equal(await page.locator('[data-draw="10"]').isEnabled(), false, 'ten-pull stays disabled with zero tickets');
  await page.locator('.rs-hint button').click();
  assert.equal((await readPort()).wallet.standard, 20, 'welcome supply adds 20 tickets');
  assert.equal(await page.locator('[data-draw="10"]').isEnabled(), true, 'ten-pull enabled without starter');
  await page.screenshot({ path: root + 'recruit-mobile.png' });

  await page.locator('[data-draw="10"]').click();
  await closeArrival();
  const after = await readPort();
  assert.equal(after.starter, false, 'drawing does not force the tutorial/starter');
  assert.equal(after.wallet.standard, 10, 'ten tickets were spent');
  assert.equal(after.history.length, 10, 'ten arrivals recorded');
  assert.ok(after.history.every(draw => /^IBS-U-/.test(draw.ship)), 'every arrival is one single-ship identity');
  assert.ok(after.history.every(draw => draw.hull === undefined), 'no 4-hull rows remain');
  assert.ok(Object.values(after.owned).every(value => value === true), 'owned rows are unique identity flags');
  assert.equal(after.preset.ships.length, 5, 'a legacy preset without ships is filled with five starters');
  assert.ok(after.preset.ships.every(id => id.startsWith('IBS-U-')));
  assert.equal(await overflow(), false, 'mobile recruit has no horizontal overflow');
  await page.screenshot({ path: root + 'recruit-mobile-after.png' });

  await page.locator('.rs-back').click();
  await page.locator('.quartermaster').waitFor();
  await page.locator('.harbor-mobile-nav button', { hasText: '编队' }).click();
  await page.locator('.harbor-section').waitFor();
  assert.equal(await page.locator('.harbor-mobile-nav button[aria-pressed="true"]').innerText(), '▦\n编队');
  assert.equal(await page.locator('.fleet-slot').count(), 5, 'the fleet editor exposes five identity slots');
  assert.ok(await page.locator('.ship-card').count() >= 1, 'drawn single ships appear in the dock');
  assert.equal(await page.locator('[data-fleet-summary]').getAttribute('data-ready'), 'false');
  assert.equal(await page.locator('[data-launch-preset]').isDisabled(), true, 'without the starter fleet the preset cannot launch');
  assert.equal(await overflow(), false, 'the five-slot fleet does not scroll horizontally at 740');
  await page.screenshot({ path: root + 'fleet-mobile.png' });
  assert.equal(errors.length, 0, errors.join('\n'));
  console.log('mobile recruit ok', { tickets: after.wallet.standard, starter: after.starter, history: after.history.length });
} finally {
  await browser.close();
}
