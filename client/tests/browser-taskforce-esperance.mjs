import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { signInLocal } from './browser-login.mjs';

const { chromium } = createRequire(import.meta.url)(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const out = process.env.CAS_ARTIFACTS || fileURLToPath(new URL('../../artifacts/client/taskforce-esperance/', import.meta.url));
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
  await signInLocal(page, 'cas-taskforce-esperance', true);
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await signInLocal(page, 'cas-taskforce-esperance-2', true);
  await page.getByRole('button', { name: '打开主菜单', exact: true }).click();
  await page.getByRole('button', { name: '返回母港', exact: true }).click();
  await page.locator('.growth-port').waitFor();

  await page.locator('.growth-campaign-entry').click();
  await page.locator('.campaign-lobby').waitFor();
  await page.getByRole('button', { name: '同盟战线', exact: true }).click();
  await page.locator('.cl-row').filter({ hasText: '埃斯佩兰斯角' }).first().click();
  await button('编成出击').click();
  await page.locator('.deployment-screen').waitFor();
  await page.getByRole('button', { name: '特混编成', exact: true }).click();
  await page.locator('.taskforce').waitFor();
  const positions = page.locator('.tf-position');
  assert.equal(await positions.count(), 1, 'Esperance has one printed player column');
  await positions.first().getByRole('button', { name: '编成', exact: true }).click();
  await page.locator('.tf-picker').waitFor();
  await page.locator('.tf-candidate').filter({ hasText: '北卡罗来纳' }).first().click();
  await button('完成').click();
  await page.screenshot({ path: out + 'taskforce-esperance.png' });
  await button('特混出航').click();
  await page.locator('.battle-map').waitFor();
  const obs = await q('observe');
  assert.equal(obs.campaign.stageId, 'CAMP-ALLIES-02');
  assert.equal(obs.ships.length, 1, 'the extreme single-ship group is allowed');
  assert.equal(obs.ships[0].name, '北卡罗来纳');
  assert.equal(obs.fleets.length, 1);
  assert(Math.abs(obs.ships[0].x - 32187.546) < 1e-3 && Math.abs(obs.ships[0].y - 12954.984) < 1e-3,
    'the single group starts on the printed Esperance anchor');
  assert.deepEqual(errors, []);
  await page.screenshot({ path: out + 'taskforce-esperance-battle.png' });
  await fs.writeFile(out + 'receipt.json', JSON.stringify({
    ok: true,
    stage: obs.campaign.stageId,
    ship: { name: obs.ships[0].name, x: obs.ships[0].x, y: obs.ships[0].y },
    fleets: obs.fleets.length,
  }, null, 2));
  console.log('taskforce esperance receipt', obs.ships.length, obs.fleets.length, obs.ships[0].name);
} finally {
  await browser.close();
}
