import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { signInLocal } from './browser-login.mjs';

const { chromium } = createRequire(import.meta.url)(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const out = process.env.CAS_ARTIFACTS || fileURLToPath(new URL('../../artifacts/client/campaign-modes/', import.meta.url));
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
  await signInLocal(page, 'cas-campaign-modes', true);
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await signInLocal(page, 'cas-campaign-modes-2', true);
  await page.getByRole('button', { name: '打开主菜单', exact: true }).click();
  await page.getByRole('button', { name: '返回母港', exact: true }).click();
  await page.locator('.growth-port').waitFor();
  await page.locator('.growth-campaign-entry').click();
  await page.locator('.campaign-lobby').waitFor();

  // The legacy archive stays reachable, and an unfinished source-only stage
  // must never offer a fake sortie button.
  await page.locator('.cl-archive-only summary').click();
  await page.locator('.cl-archive-only .cl-row').filter({ hasText: '第二次瓜达卡纳尔' }).first().click();
  await page.locator('.cl-detail-foot .cl-cta').waitFor();
  assert.equal(await page.locator('.cl-detail-foot .cl-cta').isDisabled(), true, 'source-only stages stay unlaunchable');
  assert.match(await page.locator('.cl-detail-foot .cl-cta').innerText(), /档案整理中/);
  await page.screenshot({ path: out + 'source-only-stage.png' });

  await button('史料馆').click();
  await page.locator('.campaign-archive.war-atlas').waitFor();
  assert.equal(await page.locator('.war-archive-entries li').count(), 11, 'the archive keeps all eleven dossiers');
  await page.screenshot({ path: out + 'archive.png' });
  await button('返回港口').click();
  await page.locator('.campaign-lobby').waitFor();

  // Standard difficulty uses the printed fleet directly, without the point picker.
  await page.locator('.cl-row').filter({ hasText: '埃斯佩兰斯角' }).first().click();
  await page.locator('.cl-diff button').filter({ hasText: '标准' }).click();
  await button('标准难度出击').click();
  await page.locator('.battle-map').waitFor();
  const obs = await q('observe');
  assert.equal(obs.campaign.stageId, 'CAMP-ALLIES-02');
  assert.equal(obs.campaign.difficulty, 'standard');
  assert.equal(obs.ships.length, 9, 'standard difficulty keeps the printed nine hulls');
  assert.deepEqual(errors, []);
  await page.screenshot({ path: out + 'standard-battle.png' });
  await fs.writeFile(out + 'receipt.json', JSON.stringify({
    ok: true,
    archiveRows: 11,
    sourceOnlyDisabled: true,
    stage: obs.campaign.stageId,
    difficulty: obs.campaign.difficulty,
    ships: obs.ships.length,
  }, null, 2));
  console.log('campaign modes receipt', obs.campaign.stageId, obs.campaign.difficulty, obs.ships.length);
} finally {
  await browser.close();
}
