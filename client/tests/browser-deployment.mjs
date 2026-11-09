import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { signInLocal } from './browser-login.mjs';

const { chromium } = createRequire(import.meta.url)(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const out = process.env.CAS_ARTIFACTS || fileURLToPath(new URL('../../artifacts/client/deployment/', import.meta.url));
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
  await signInLocal(page, 'cas-deployment-qa', true);
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await signInLocal(page, 'cas-deployment-qa2', true);
  await page.getByRole('button', { name: '打开主菜单', exact: true }).click();
  await page.getByRole('button', { name: '返回母港', exact: true }).click();
  await page.locator('.growth-port').waitFor();

  async function openDeployment() {
    await page.locator('.growth-campaign-entry').click();
    await page.locator('.campaign-lobby').waitFor();
    await button('同盟战线').click();
    const row = page.locator('.cl-row').filter({ hasText: '埃斯佩兰斯角' }).first();
    await row.click();
    await button('编成出击').click();
    await page.locator('.deployment-screen').waitFor();
    await page.locator('.dep-slot').first().waitFor();
  }

  await openDeployment();
  const slots = page.locator('.dep-slot');
  assert.equal(await slots.count(), 9, 'the historical column must keep nine slots');
  assert.match(await page.locator('.budget-meter__head b').innerText(), /6,850/);
  await page.screenshot({ path: out + 'deployment-1360.png' });

  await slots.first().click();
  await page.locator('.dep-candidate').waitFor();
  await page.locator('.dep-candidate__row').filter({ hasText: '拉姆森' }).click();
  await button('换上该舰').click();
  assert.match(await slots.first().innerText(), /拉姆森/, 'slot 1 must show the swapped ship');
  assert.match(await slots.first().innerText(), /原 法伦霍尔特/, 'the original historical identity stays visible');
  assert.match(await page.locator('.budget-meter__head b').innerText(), /6,825/);

  await page.screenshot({ path: out + 'deployment-swapped.png' });
  await button('保存为预设').click();
  await page.getByLabel('载入预设').waitFor();
  await button('按历史编制').click();
  assert.match(await slots.first().innerText(), /法伦霍尔特/, 'history reset restores the printed hull');
  await page.getByLabel('载入预设').selectOption({ index: 1 });
  assert.match(await slots.first().innerText(), /拉姆森/, 'the saved preset restores the swapped hull');

  await page.setViewportSize({ width: 740, height: 360 });
  await button('参谋').click();
  await page.locator('.dep-sheet').waitFor();
  await page.screenshot({ path: out + 'deployment-740-staff.png' });
  await page.locator('.dep-sheet').getByRole('button', { name: '关闭', exact: true }).click();
  await page.locator('.dep-sheet').waitFor({ state: 'hidden' });
  await page.screenshot({ path: out + 'deployment-740.png' });
  await page.setViewportSize({ width: 1360, height: 768 });

  // A reload must restore the draft from localStorage.
  await page.reload();
  await signInLocal(page, 'cas-deployment-qa3', true);
  if (await page.locator('.battle-map').count()) {
    await page.getByRole('button', { name: '打开主菜单', exact: true }).click();
    await page.getByRole('button', { name: '返回母港', exact: true }).click();
  }
  await page.locator('.growth-port').waitFor();
  await openDeployment();
  assert.match(await page.locator('.dep-slot').first().innerText(), /拉姆森/, 'the draft must survive a reload');

  await button('出航作战').click();
  await page.locator('.battle-map').waitFor();
  const obs = await q('observe');
  assert.equal(obs.campaign.stageId, 'CAMP-ALLIES-02');
  assert.equal(obs.campaign.difficulty, 'story');
  assert.equal(obs.ships.length, 9, 'the sortie keeps the printed nine hulls');
  assert.equal(obs.ships[0].name, '拉姆森', 'the kernel received the swapped first slot');
  assert.equal(obs.side, 'allies');
  assert.deepEqual(errors, []);
  await page.screenshot({ path: out + 'deployment-launch.png' });
  await fs.writeFile(out + 'receipt.json', JSON.stringify({
    ok: true,
    stage: obs.campaign.stageId,
    difficulty: obs.campaign.difficulty,
    ships: obs.ships.length,
    firstShip: obs.ships[0].name,
    draft: '拉姆森',
  }, null, 2));
  console.log('deployment receipt', obs.campaign.stageId, obs.ships.length, obs.ships[0].name);
} finally {
  await browser.close();
}
