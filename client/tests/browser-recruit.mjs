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

const starShips = [
  'IBS-U-USN-FLETCHER', 'IBS-U-USN-PERKINS', 'IBS-U-USN-MAURY',
  'IBS-U-USN-DRAYTON', 'IBS-U-USN-HONOLULU',
];
const seed = {
  version: 1,
  lessons: ['lead', 'follow', 'sync', 'gun', 'cancel', 'torpedo', 'override'],
  starter: true, challengeClear: false, challengeClaim: false,
  wallet: { standard: 20, up: 10 }, marks: 0, pity: { standard: 9, up: 0 },
  owned: Object.fromEntries(starShips.map(id => [id, true])), profiles: ['coord'],
  preset: { side: 'allies', leaderSlot: 0, profile: 'coord', ships: starShips },
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
  const ship = await dialog.getAttribute('data-ship');
  await dialog.getByRole('button', { name: '跳过动画' }).click();
  await dialog.getByRole('button', { name: '确认入列' }).click();
  await dialog.waitFor({ state: 'detached' });
  return ship;
}
// Deterministic draws for the UP banner and the two-side standard checks.
// Only intercept a 3-word Uint32Array while a forced vector is installed.
async function installDrawHook() {
  await page.evaluate(() => {
    const original = crypto.getRandomValues.bind(crypto);
    window.__casOriginalGetRandomValues = original;
    window.__casDrawWords = null;
    crypto.getRandomValues = array => {
      if (array instanceof Uint32Array && array.length === 3 && window.__casDrawWords) {
        array.set(window.__casDrawWords);
        return array;
      }
      return original(array);
    };
  });
}
const forceDraw = words => page.evaluate(value => { window.__casDrawWords = value; }, words);
const releaseDraw = () => page.evaluate(() => { window.__casDrawWords = null; });

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
  assert.match(await page.locator('.rs-intel').innerText(), /密苏里/, 'Missouri is the featured hull');
  assert.match(await page.locator('.rs-intel').innerText(), /本池概率/);
  assert.match(await page.locator('.rs-intel').innerText(), /保底/);
  assert.match(await page.locator('.rs-intel').innerText(), /兑换与重复/);
  assert.equal(await page.locator('.rs-draw-actions [data-draw="1"]').count(), 1);
  assert.equal(await page.locator('.rs-draw-actions [data-draw="10"]').count(), 1);
  assert.match(await page.locator('.rs-draw-actions').innerText(), /征募 1/);
  assert.match(await page.locator('.rs-draw-actions').innerText(), /征募 10/);
  await page.screenshot({ path: root + 'recruit-1360.png' });

  // The standard pool is the whole 202-card catalogue, both sides and all types.
  const rates = page.locator('.rs-rates');
  assert.equal(await rates.getAttribute('data-candidate-count'), '202', 'standard pool holds all 202 playable identities');
  assert.match(await rates.innerText(), /UR/);
  assert.match(await rates.innerText(), /SSR/);
  assert.match(await rates.innerText(), /SR/);
  assert.match(await rates.innerText(), /R/);

  // Probability drawer: every identity is listed as a single-ship row, and the
  // seven axis battleships are projected as UR without touching data/ships.
  await page.locator('.rs-stage-links button', { hasText: '概率' }).click();
  await drawer('probability').waitFor();
  assert.equal(await drawer('probability').locator('tbody tr').count(), 202, 'the standard pool lists 202 single ships');
  assert.match(await drawer('probability').innerText(), /同盟舰队/);
  assert.match(await drawer('probability').innerText(), /轴心舰队/);
  const yamato = drawer('probability').locator('tbody tr[data-ship="IBS-U-IJN-ERMA-YAMATO"]');
  assert.equal(await yamato.count(), 1, 'Yamato is a single-ship row');
  assert.equal((await yamato.locator('td').nth(2).innerText()).trim(), 'UR', 'axis BB is UR in the gacha layer');
  assert.match(await drawer('probability').innerText(), /UR 2%/);
  assert.match(await drawer('probability').innerText(), /SSR 8%/);
  assert.match(await drawer('probability').innerText(), /SR 20%/);
  assert.match(await drawer('probability').innerText(), /R 70%/);
  assert.match(await drawer('probability').innerText(), /连续 9 次未获得 SR 及以上/);
  await page.screenshot({ path: root + 'recruit-probability.png' });
  await page.keyboard.press('Escape');
  await drawer('probability').waitFor({ state: 'detached' });
  assert.ok(await page.locator('.recruit-screen').isVisible(), 'Esc closes the drawer before the screen');

  // Draw 1 with pity 9: the next draw is guaranteed to be SR or above, and the
  // receipt stores one identity (never a class row).
  await page.locator('[data-draw="1"]').click();
  const arrivedShip = await closeArrival();
  let port = await readPort();
  assert.equal(port.wallet.standard, 19);
  assert.equal(port.pity.standard, 0, 'the guaranteed draw resets the pity counter');
  assert.equal(port.history.length, 1);
  assert.equal(port.history[0].guaranteed, true);
  assert.match(port.history[0].ship, /^IBS-U-/, 'a draw stores one identity');
  assert.equal(port.history[0].hull, undefined, 'the old 4-hull field is gone');
  assert.equal(port.owned[port.history[0].ship], true, 'the drawn identity enters the owned set once');
  assert.match(await page.locator('.rs-last').innerText(), /保底到港/);
  assert.equal(await page.locator('.rs-last').getAttribute('data-last-draw'), '1');
  assert.equal(arrivedShip, port.history[0].ship, 'the arrival dialog shows the same single ship');

  // Force a UR index in the standard pool to prove both sides are drawable from
  // the same pool.  UR indices: 0 = allied, 12 = the last axis BB.
  await installDrawHook();
  await forceDraw([0, 0, 0]);
  await page.locator('[data-draw="1"]').click();
  await closeArrival();
  port = await readPort();
  const alliedDraw = port.history[0].ship;
  assert.match(alliedDraw, /^IBS-U-USN-/, 'the standard pool draws allied identities');
  await forceDraw([0, 0, 12]);
  await page.locator('[data-draw="1"]').click();
  await closeArrival();
  port = await readPort();
  const axisDraw = port.history[0].ship;
  assert.match(axisDraw, /^IBS-U-IJN-/, 'the standard pool draws axis identities');
  assert.notEqual(axisDraw, alliedDraw);
  await releaseDraw();
  assert.equal(port.history.length, 3);
  assert.equal(port.wallet.standard, 17);

  // Records drawer and replay: both read the stored receipt, no new roll.
  await page.locator('[data-open-drawer="records"]').click();
  await drawer('records').waitFor();
  assert.equal(await drawer('records').locator('[data-draw-id]').count(), 3);
  assert.match(await drawer('records').innerText(), /保底/);
  await page.screenshot({ path: root + 'recruit-records.png' });
  await page.keyboard.press('Escape');
  await drawer('records').waitFor({ state: 'detached' });
  await page.locator('.rs-last .rs-link').click();
  await page.locator('dialog.recruit-arrival').waitFor();
  assert.equal(await page.locator('dialog.recruit-arrival').getAttribute('data-phase'), 'receipt');
  assert.match(await page.locator('dialog.recruit-arrival').innerText(), /到港清册/);
  assert.doesNotMatch(await page.locator('dialog.recruit-arrival').innerText(), /弗莱彻级|克利夫兰级/);
  await page.locator('dialog.recruit-arrival').getByRole('button', { name: '确认入列' }).click();
  await page.locator('dialog.recruit-arrival').waitFor({ state: 'detached' });
  assert.equal((await readPort()).history.length, 3, 'replay does not roll another draw');

  // UP pool: still all 202, but the Missouri banner is 50% of the UR tier.
  await page.locator('.rs-pools button[data-pool="up"]').click();
  await page.locator('.recruit-screen[data-pool="up"]').waitFor();
  assert.match(await page.locator('.rs-stage-copy h2').innerText(), /密苏里 · UP/);
  assert.match(await page.locator('.rs-intel').innerText(), /本期 UP/);
  assert.match(await page.locator('.rs-intel').innerText(), /密苏里/);
  assert.match(await page.locator('.rs-intel').innerText(), /1\.0%/);
  assert.equal(await page.locator('.rs-pools button[data-pool="up"]').getAttribute('aria-pressed'), 'true');
  assert.equal(await rates.getAttribute('data-candidate-count'), '202', 'the UP pool also holds all 202');
  await page.screenshot({ path: root + 'recruit-up-pool.png' });

  await installDrawHook();
  await forceDraw([0, 0, 0]); // UR tier, featured word 0 → Missouri
  await page.locator('[data-draw="1"]').click();
  await closeArrival();
  port = await readPort();
  assert.equal(port.history[0].ship, 'IBS-U-USN-ERMA-MISSOURI', 'the UP pool can draw the Missouri banner');
  assert.equal(port.history[0].pool, 'up');
  assert.equal(port.wallet.up, 9);
  await releaseDraw();

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

  // Draw 10 on the standard pool: ten identities, one batch receipt.
  await page.locator('.rs-pools button[data-pool="standard"]').click();
  await page.locator('.recruit-screen[data-pool="standard"]').waitFor();
  await page.locator('[data-draw="10"]').click();
  await closeArrival();
  port = await readPort();
  assert.equal(port.wallet.standard, 7, 'a ten-draw costs ten standard tickets');
  assert.equal(port.history.length, 14);
  assert.equal(port.history[0].batchSize, 10, 'the ten-draw batch is stored on the latest receipt');
  assert.match(await page.locator('.rs-last').innerText(), /十连|最近到港|保底到港/);

  // Exchange drawer: duplicates follow the four gacha tiers.
  await page.locator('.rs-stage-links button', { hasText: '兑换' }).click();
  await drawer('exchange').waitFor();
  const exchangeRows = drawer('exchange').locator('tbody tr');
  assert.equal(await exchangeRows.count(), 4);
  assert.match(await exchangeRows.nth(0).innerText(), /UR[\s\S]*\+5/);
  assert.match(await exchangeRows.nth(1).innerText(), /SSR[\s\S]*\+3/);
  assert.match(await exchangeRows.nth(2).innerText(), /SR[\s\S]*\+2/);
  assert.match(await exchangeRows.nth(3).innerText(), /R[\s\S]*\+1/);
  assert.match(await drawer('exchange').innerText(), /6 舰队勋章/);
  await page.screenshot({ path: root + 'recruit-exchange.png' });
  await drawer('exchange').getByRole('button', { name: '前往军需处兑换', exact: true }).click();
  await page.locator('.quartermaster').waitFor();
  assert.equal(await page.locator('.recruit-screen').count(), 0);
  assert.equal(await page.getByRole('button', { name: '礼包与兑换', exact: true }).getAttribute('aria-pressed'), 'true');

  // The drawn identities enter a five-slot fleet and launch through Harbour.
  await page.getByRole('button', { name: '返回母港', exact: true }).click();
  await page.locator('.growth-port').waitFor();
  await page.locator('.growth-dock button[data-guide="fleet"]').click();
  await page.locator('.harbor-section').waitFor();
  assert.ok(await page.locator('.ship-card').count() >= 5, 'the owned single-ship cards are listed');
  assert.equal(await page.locator('.fleet-slot').count(), 5, 'five fleet slot selectors');
  let slots = await page.locator('.fleet-slot select').evaluateAll(nodes => nodes.map(node => node.value));
  assert.equal(slots.length, 5);
  assert.ok(slots.every(id => id.startsWith('IBS-U-')), 'each slot holds one identity');
  // A freshly drawn identity (not part of the starter five) can take a slot.
  await page.locator('.fleet-slot select').first().selectOption(alliedDraw);
  slots = await page.locator('.fleet-slot select').evaluateAll(nodes => nodes.map(node => node.value));
  assert.equal(slots[0], alliedDraw, 'the drawn single ship is selectable in the five-slot fleet');
  assert.equal(new Set(slots).size, 5, 'the fleet never repeats an identity');
  assert.equal(await page.locator('[data-fleet-summary]').getAttribute('data-ready'), 'true');
  assert.match(await page.locator('[data-fleet-summary]').innerText(), /5 舰齐全/);
  assert.match(await page.locator('[data-fleet-summary]').innerText(), /总点价/);
  assert.equal(await page.locator('[data-launch-preset]').isEnabled(), true);
  await page.locator('[data-fleet-leader]').selectOption('2');
  await page.screenshot({ path: root + 'fleet-five-slots.png' });

  await page.locator('[data-launch-preset]').click();
  await page.locator('.battle-map').waitFor();
  assert.ok(await page.locator('.command-shell').isVisible(), 'the five-ship preset launches a local exercise');
  const saveKey = 'cas.profile.test-commander.cas.exercise.autosave.v1';
  const save = await page.evaluate(key => JSON.parse(localStorage.getItem(key) || 'null'), saveKey);
  assert.deepEqual(save.ships, slots, 'the launched session carries the five preset identities in slot order');
  assert.equal(save.leader_slot, 2, 'the leader slot is the index into the ships array');
  await page.screenshot({ path: root + 'fleet-launch.png' });

  // Reopen and close with Escape/back (fresh page state after launch is enough:
  // the modal behaviour is already covered above and on mobile).
  assert.deepEqual(errors, []);
  await fs.writeFile(root + 'browser-receipt.json', JSON.stringify({
    ok: true,
    pools: 2,
    catalogue: { total: 202, standard: 202, up: 202, featured: 'IBS-U-USN-ERMA-MISSOURI' },
    draws: {
      guaranteed: { ship: port.history[13]?.ship, batch: port.history[0].batchSize },
      allied: alliedDraw, axis: axisDraw, missouri: 'IBS-U-USN-ERMA-MISSOURI',
      history: port.history.length,
    },
    wallet: port.wallet,
    probability: { weights: { UR: 2, SSR: 8, SR: 20, R: 70 }, pity: '10-draw SR+' },
    axisBbRarity: 'UR',
    fleet: { slots: slots.length, ready: true, ships: slots },
    overflow740: false,
    drawers: ['probability', 'records', 'exchange'],
    battle: { ships: save.ships, leaderSlot: save.leader_slot,
      note: 'the local exercise accepted the five identities and the leader index; combat outcomes are not asserted in this browser batch' },
  }, null, 2));
  console.log('browser recruit ok', { wallet: port.wallet, history: port.history.length, fleet: slots });
} finally {
  await browser.close();
}
