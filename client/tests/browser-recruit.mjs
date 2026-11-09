import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs/promises';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const root = process.env.CAS_ARTIFACTS || 'artifacts/client/recruit/';
const url = process.env.CAS_TEST_URL || 'http://127.0.0.1:5175/';
const portKey = 'cas.profile.test-commander.cas.harbor.progress.v1';
if (!root.endsWith('/')) throw new Error('CAS_ARTIFACTS must end with a slash');
await fs.mkdir(root, { recursive: true });

const seed = {
  version: 1,
  lessons: ['lead', 'follow', 'sync', 'gun', 'cancel', 'torpedo', 'override'],
  starter: true, challengeClear: false, challengeClaim: false,
  wallet: { standard: 20, up: 10 }, marks: 0, pity: { standard: 9, up: 0 },
  owned: { fletcher: 4, cleveland: 1 }, profiles: ['coord'],
  preset: { side: 'allies', leaderSlot: 0, profile: 'coord' },
  upSide: 'axis', sequence: 0, history: [], credits: 5000, courses: [], attendance: [],
  challengeReceipts: {}, mail: [],
  campaignProgress: {
    'CAMP-ALLIES-02': { best: { story: 2 }, claimed: 2 },
    'CAMP-ALLIES-03': { best: { story: 2 }, claimed: 2 },
    'CAMP-ALLIES-11': { best: { story: 2 }, claimed: 2 },
  },
};

const errors = [];
const browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });
const page = await (await browser.newContext({ viewport: { width: 1360, height: 768 }, locale: 'zh-CN' })).newPage();
page.on('pageerror', error => errors.push(error.stack));
const readPort = () => page.evaluate(key => JSON.parse(localStorage.getItem(key) || 'null'), portKey);
const overflow = () => page.evaluate(() =>
  document.documentElement.scrollWidth > window.innerWidth || document.body.scrollWidth > window.innerWidth);
const drawer = name => page.locator(`[data-drawer="${name}"]`);

async function openRecruit() {
  await page.locator('.growth-port').waitFor();
  await page.locator('.growth-dock button[data-guide="economy"]').click();
  await page.locator('.quartermaster').waitFor();
  await page.locator('[data-item="recruit"] button', { hasText: '进入军港征募' }).click();
  await page.locator('.recruit-screen').waitFor();
}
async function closeArrival() {
  const dialog = page.locator('dialog.recruit-arrival');
  await dialog.waitFor();
  await dialog.getByRole('button', { name: '跳过动画' }).click();
  await dialog.getByRole('button', { name: '确认入列' }).click();
  await dialog.waitFor({ state: 'detached' });
}

try {
  await page.addInitScript(([key, value]) => {
    if (!localStorage.getItem('cas.recruit.seeded')) {
      localStorage.setItem(key, JSON.stringify(value));
      localStorage.setItem('cas.recruit.seeded', '1');
    }
  }, [portKey, seed]);
  await page.goto(url);
  await openRecruit();
  assert.equal((await page.locator('.rs-title h1').innerText()).trim(), '军港征募');
  assert.equal(await page.locator('.rs-pools > button').count(), 2, 'two pool berths are listed');
  assert.match(await page.locator('.rs-stage-copy h2').innerText(), /远洋群舰/);
  assert.match(await page.locator('.rs-intel').innerText(), /本期焦点/);
  assert.match(await page.locator('.rs-intel').innerText(), /本池概率/);
  assert.match(await page.locator('.rs-intel').innerText(), /保底/);
  assert.match(await page.locator('.rs-intel').innerText(), /兑换与重复/);
  assert.equal(await page.locator('.rs-draw-actions [data-draw="1"]').count(), 1);
  assert.equal(await page.locator('.rs-draw-actions [data-draw="10"]').count(), 1);
  assert.match(await page.locator('.rs-draw-actions').innerText(), /征募 1/);
  assert.match(await page.locator('.rs-draw-actions').innerText(), /征募 10/);
  await page.screenshot({ path: root + 'recruit-1360.png' });

  // Probability drawer: local rules stay 85% / 15% with a ten-draw light-cruiser pity.
  await page.locator('.rs-stage-links button', { hasText: '概率' }).click();
  await drawer('probability').waitFor();
  assert.equal(await drawer('probability').locator('tbody tr').count(), 4, 'the standard pool lists four hulls');
  assert.match(await drawer('probability').innerText(), /85%/);
  assert.match(await drawer('probability').innerText(), /15%/);
  assert.match(await drawer('probability').innerText(), /连续 9 次未获得轻巡/);
  await page.screenshot({ path: root + 'recruit-probability.png' });
  await page.keyboard.press('Escape');
  await drawer('probability').waitFor({ state: 'detached' });
  assert.ok(await page.locator('.recruit-screen').isVisible(), 'Esc closes the drawer before the screen');

  // Draw 1 with pity 9: the next draw is guaranteed to be a light cruiser.
  await page.locator('[data-draw="1"]').click();
  await closeArrival();
  let port = await readPort();
  assert.equal(port.wallet.standard, 19);
  assert.equal(port.pity.standard, 0, 'the guaranteed draw resets the pity counter');
  assert.equal(port.history.length, 1);
  assert.equal(port.history[0].guaranteed, true);
  assert.match(await page.locator('.rs-last').innerText(), /保底到港/);
  assert.equal(await page.locator('.rs-last').getAttribute('data-last-draw'), '1');

  // Records drawer and replay: both read the stored receipt, no new roll.
  await page.locator('[data-open-drawer="records"]').click();
  await drawer('records').waitFor();
  assert.equal(await drawer('records').locator('[data-draw-id]').count(), 1);
  assert.match(await drawer('records').innerText(), /保底/);
  await page.screenshot({ path: root + 'recruit-records.png' });
  await page.keyboard.press('Escape');
  await drawer('records').waitFor({ state: 'detached' });
  await page.locator('.rs-last .rs-link').click();
  await page.locator('dialog.recruit-arrival').waitFor();
  assert.equal(await page.locator('dialog.recruit-arrival').getAttribute('data-phase'), 'receipt');
  assert.match(await page.locator('dialog.recruit-arrival').innerText(), /到港清册/);
  await page.locator('dialog.recruit-arrival').getByRole('button', { name: '确认入列' }).click();
  await page.locator('dialog.recruit-arrival').waitFor({ state: 'detached' });
  assert.equal((await readPort()).history.length, 1, 'replay does not roll another draw');

  // Pool switch: UP pool only draws the current UP side.
  await page.locator('.rs-pools button[data-pool="up"]').click();
  await page.locator('.recruit-screen[data-pool="up"]').waitFor();
  assert.match(await page.locator('.rs-stage-copy h2').innerText(), /轴心舰队 · UP/);
  assert.match(await page.locator('.rs-intel').innerText(), /本期 UP/);
  assert.equal(await page.locator('.rs-pools button[data-pool="up"]').getAttribute('aria-pressed'), 'true');
  assert.match(await page.locator('.rs-intel').innerText(), /85%/);
  assert.match(await page.locator('.rs-intel').innerText(), /15%/);
  await page.screenshot({ path: root + 'recruit-up-pool.png' });

  // 740x360: main visual, horizontal pool switch, fixed draw bar, bottom-sheet drawers.
  await page.setViewportSize({ width: 740, height: 360 });
  await page.waitForTimeout(200);
  assert.equal(await overflow(), false, 'the recruit screen must not scroll horizontally at 740x360');
  assert.equal(await page.locator('.rs-intel').isVisible(), false, 'the right rail folds into drawers at 740x360');
  assert.equal(await page.locator('.rs-draw-bar').isVisible(), true, 'the draw bar stays fixed at 740x360');
  await page.locator('.rs-stage-links button', { hasText: '记录' }).click();
  await drawer('records').waitFor();
  const sheet = await drawer('records').locator('.cas-drawer').boundingBox();
  assert.ok(sheet && sheet.width >= 700, 'the mobile drawer opens as a bottom sheet');
  await page.screenshot({ path: root + 'recruit-740-drawer.png' });
  await page.keyboard.press('Escape');
  await drawer('records').waitFor({ state: 'detached' });
  await page.screenshot({ path: root + 'recruit-740.png' });
  await page.setViewportSize({ width: 1360, height: 768 });

  // Draw 10 on the standard pool.
  await page.locator('.rs-pools button[data-pool="standard"]').click();
  await page.locator('.recruit-screen[data-pool="standard"]').waitFor();
  await page.locator('[data-draw="10"]').click();
  await closeArrival();
  port = await readPort();
  assert.equal(port.wallet.standard, 9, 'a ten-draw costs ten standard tickets');
  assert.equal(port.history.length, 11);
  assert.equal(port.history[0].batchSize, 10, 'the ten-draw batch is stored on the latest receipt');
  assert.match(await page.locator('.rs-last').innerText(), /十连|最近到港|保底到港/);

  // Exchange drawer routes back to the quartermaster counters, not a new economy.
  await page.locator('.rs-stage-links button', { hasText: '兑换' }).click();
  await drawer('exchange').waitFor();
  assert.match(await drawer('exchange').innerText(), /重复驱逐舰：\+1/);
  assert.match(await drawer('exchange').innerText(), /6 舰队勋章/);
  await page.screenshot({ path: root + 'recruit-exchange.png' });
  await drawer('exchange').getByRole('button', { name: '前往军需处兑换', exact: true }).click();
  await page.locator('.quartermaster').waitFor();
  assert.equal(await page.locator('.recruit-screen').count(), 0);
  assert.equal(await page.getByRole('button', { name: '礼包与兑换', exact: true }).getAttribute('aria-pressed'), 'true');

  // Reopen and close with Escape/back.
  await page.getByRole('button', { name: '舰船', exact: true }).click();
  await page.locator('[data-item="recruit"] button', { hasText: '进入军港征募' }).click();
  await page.locator('.recruit-screen').waitFor();
  await page.keyboard.press('Escape');
  await page.locator('.recruit-screen').waitFor({ state: 'detached' });
  await page.locator('[data-item="recruit"] button', { hasText: '进入军港征募' }).click();
  await page.locator('.recruit-screen').waitFor();
  await page.getByRole('button', { name: '‹ 返回军需处' }).click();
  await page.locator('.recruit-screen').waitFor({ state: 'detached' });

  assert.deepEqual(errors, []);
  await fs.writeFile(root + 'browser-receipt.json', JSON.stringify({
    ok: true,
    pools: 2,
    draws: { single: port.pity.standard, tenBatch: port.history[0].batchSize, history: port.history.length },
    wallet: port.wallet,
    probability: { standard: '85/15 with 10-draw light-cruiser pity' },
    overflow740: false,
    drawers: ['probability', 'records', 'exchange'],
  }, null, 2));
  console.log('browser recruit ok', { wallet: port.wallet, history: port.history.length });
} finally {
  await browser.close();
}
