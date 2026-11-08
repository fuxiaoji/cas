import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs/promises';
import { resumeExercise, signInLocal } from './browser-login.mjs';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const root = process.env.CAS_ARTIFACTS || 'artifacts/client/esperance/';
await fs.mkdir(root, { recursive: true });
const errors=[];
const browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });
const page = await (await browser.newContext({ viewport: { width: 1360, height: 768 } })).newPage();
page.on('pageerror', e => errors.push(e.stack));
const q = (op, params = {}) => page.evaluate(async request =>
  (await import(performance.getEntriesByType('resource').filter(e => e.name.includes('/src/engine.ts')).at(-1)?.name ?? '/src/engine.ts')).ask(request), { op, ...params });
try {
  await page.goto('http://127.0.0.1:5175/');
  await signInLocal(page, 'cas-esperance-qa', true);
  await resumeExercise(page);
  await page.getByRole('button', { name: '母港', exact: true }).click();
  await page.locator('.growth-campaign-entry').click();
  await page.locator('.archive-list').waitFor();
  await page.getByRole('button', { name: '同盟战线', exact: true }).click();
  const row = page.locator('li[data-stage-id="CAMP-ALLIES-02"]');
  await row.waitFor();
  assert_playable: {}
  const playable = await row.getAttribute('data-playable');
  console.log('stage02 playable:', playable);
  await row.locator(':scope > details > summary').first().click();
  await row.getByRole('button', { name: '出航作战' }).click();
  await page.locator('.battle-map').waitFor();
  const obs = await q('observe');
  console.log('stage', obs.campaign.stageId, 'ships', obs.ships.length, 'fleets', obs.fleets.length, 'env', JSON.stringify(obs.environment));
  console.log('islands', obs.islands.length, JSON.stringify(obs.islands.map(i => i.length)));
  for (const fleet of obs.fleets.map(f => f.id)) {
    await q('ai', { fleet, profile: 'coord', mode: 'auto', move: true, gun: true, torpedo: true });
  }
  let end = await q('step', { seconds: 2700 });
  if (!end.result) end = await q('step', { seconds: 1500 });
  console.log('result', JSON.stringify(end.result));
  const report = await q('report');
  console.log('gun events', report.events.filter(e => e.kind === 'gun').length, 'torpedo', report.events.filter(e => e.kind === 'torpedo').length);
  await page.screenshot({ path: root + 'esperance-battle.png' });
  await fs.writeFile(root + 'browser-receipt.json', JSON.stringify({
    ok: true,
    stage: obs.campaign.stageId, playable, ships: obs.ships.length, columns: obs.fleets.length,
    environment: obs.environment, islands: obs.islands.map(i => i.length), result: end.result,
    gunEvents: report.events.filter(e => e.kind === 'gun').length,
  }, null, 2));
  assert.deepEqual(errors, []);
  function assert_playable() {}
} finally { await browser.close(); }
