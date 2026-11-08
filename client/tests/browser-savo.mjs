import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs/promises';
import { signInLocal } from './browser-login.mjs';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const root = process.env.CAS_ARTIFACTS || 'artifacts/client/savo/';
await fs.mkdir(root, { recursive: true });
const errors = [];
const browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });
const page = await (await browser.newContext({ viewport: { width: 1360, height: 768 } })).newPage();
page.on('pageerror', e => errors.push(e.stack));
const q = (op, params = {}) => page.evaluate(async request =>
  (await import(performance.getEntriesByType('resource').filter(e => e.name.includes('/src/engine.ts')).at(-1)?.name ?? '/src/engine.ts')).ask(request), { op, ...params });
try {
  await page.goto('http://127.0.0.1:5175/');
  await signInLocal(page, 'cas-savo-' + Date.now().toString(36), true);
  await page.locator('.growth-campaign-entry').click();
  const row = page.locator('.war-archive-entries li').filter({ hasText: '萨沃岛' }).first();
  await row.waitFor();
  console.log('status', await row.locator('.war-entry-status').innerText());
  await row.locator('button.war-entry').click();
  await page.getByRole('button', { name: '作战简报', exact: true }).click();
  await page.locator('.war-brief').waitFor();
  await page.getByRole('button', { name: '出航作战', exact: true }).click();
  await page.locator('.battle-map').waitFor();
  const obs = await q('observe');
  console.log('stage', obs.campaign.stageId, 'ships', obs.ships.length, 'fleets', obs.fleets.length,
    'env', JSON.stringify(obs.environment));
  assert.equal(obs.campaign.stageId, 'CAMP-ALLIES-10');
  assert.equal(obs.ships.length, 49);  // 49 own-side allied hulls are visible to the seat
  console.log('sea_state', obs.environment.sea_state);
  await page.screenshot({ path: root + 'savo.png' });
  assert.deepEqual(errors, []);
  await fs.writeFile(root + 'browser-receipt.json', JSON.stringify({ ok: true, stage: obs.campaign.stageId, ships: obs.ships.length, fleets: obs.fleets.length }, null, 2));
} finally { await browser.close(); }
