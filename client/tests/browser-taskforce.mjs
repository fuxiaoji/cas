import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { signInLocal } from './browser-login.mjs';

const { chromium } = createRequire(import.meta.url)(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const out = process.env.CAS_ARTIFACTS || fileURLToPath(new URL('../../artifacts/client/taskforce/', import.meta.url));
await fs.mkdir(out, { recursive: true });
const browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });
try {
  const page = await browser.newPage({ viewport: { width: 1360, height: 768 } });
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.stack));
  const q = (op, params = {}) => page.evaluate(async (request) =>
    (await import(performance.getEntriesByType('resource').filter((e) => e.name.includes('/src/engine.ts')).at(-1)?.name ?? '/src/engine.ts')).ask(request),
  { op, ...params });
  const button = (name) => page.getByRole('button', { name, exact: true });

  await page.goto(process.env.CAS_TEST_URL || 'http://127.0.0.1:5175/');
  await signInLocal(page, 'cas-taskforce-qa', true);
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await signInLocal(page, 'cas-taskforce-qa2', true);
  await page.getByRole('button', { name: '打开主菜单', exact: true }).click();
  await page.getByRole('button', { name: '返回母港', exact: true }).click();
  await page.locator('.growth-port').waitFor();

  await page.locator('.growth-campaign-entry').click();
  await page.locator('.campaign-lobby').waitFor();
  await page.getByRole('button', { name: '同盟战线', exact: true }).click();
  await page.locator('.cl-row').filter({ hasText: '奥古斯塔皇后湾' }).first().click();
  await button('编成出击').click();
  await page.locator('.deployment-screen').waitFor();
  await page.locator('.dep-slot').first().waitFor();
  await page.getByRole('button', { name: '特混编成', exact: true }).click();
  await page.locator('.taskforce').waitFor();
  const positions = page.locator('.tf-position');
  assert.equal(await positions.count(), 3, 'Empress must expose the three printed player positions');

  // Position 1: a battleship. Position 3: one destroyer. Position 2 stays empty.
  await positions.nth(0).getByRole('button', { name: '编成', exact: true }).click();
  await page.locator('.tf-picker').waitFor();
  await page.locator('.tf-candidate').filter({ hasText: '北卡罗来纳' }).first().click();
  await button('完成').click();
  await positions.nth(2).getByRole('button', { name: '编成', exact: true }).click();
  await page.locator('.tf-picker').waitFor();
  await page.locator('.tf-candidate').filter({ hasText: '奥兹本' }).first().click();
  await button('完成').click();
  await page.screenshot({ path: out + 'taskforce-empress.png' });
  assert.match(await positions.nth(0).innerText(), /北卡罗来纳/);
  assert.match(await positions.nth(2).innerText(), /奥兹本|弗莱彻级/);
  assert.equal(await positions.nth(1).locator('.tf-position__empty').count(), 1, 'the middle position can stay empty');

  await button('特混出航').click();
  await page.locator('.battle-map').waitFor();
  const obs = await q('observe');
  assert.equal(obs.campaign.stageId, 'CAMP-ALLIES-11');
  assert.equal(obs.ships.length, 2, 'two task-force groups deploy two hulls');
  assert.equal(obs.fleets.length, 2, 'the empty middle position has no fleet');
  const battleship = obs.ships.find((ship) => ship.name === '北卡罗来纳');
  assert(battleship, 'the battleship group must be in the observation');
  assert(Math.abs(battleship.x - 39374.2545) < 1e-3 && Math.abs(battleship.y - 25181.6568) < 1e-3,
    'the group must start on the printed position 1 anchor');
  const destroyer = obs.ships.find((ship) => ship.name !== '北卡罗来纳');
  assert(Math.abs(destroyer.x - 36071.6507) < 1e-3 && Math.abs(destroyer.y - 17521.6439) < 1e-3,
    'the second group must start on the printed position 3 anchor');
  assert.deepEqual(errors, []);
  await page.screenshot({ path: out + 'taskforce-empress-battle.png' });
  await fs.writeFile(out + 'receipt.json', JSON.stringify({
    ok: true,
    stage: obs.campaign.stageId,
    ships: obs.ships.map((ship) => ({ name: ship.name, x: ship.x, y: ship.y })),
    fleets: obs.fleets.map((fleet) => ({ id: fleet.id, members: fleet.members })),
  }, null, 2));
  console.log('taskforce receipt', obs.ships.length, obs.fleets.length, obs.ships.map((ship) => ship.name));
} finally {
  await browser.close();
}
