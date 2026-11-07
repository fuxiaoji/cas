import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { resumeExercise, signInLocal } from './browser-login.mjs';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const root = process.env.CAS_ARTIFACTS || fileURLToPath(new URL('../../artifacts/client/empress/', import.meta.url));
await fs.mkdir(root, { recursive: true });
const url = process.env.CAS_TEST_URL || 'http://127.0.0.1:5175/';
const browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });
const context = await browser.newContext({ viewport: { width: 1360, height: 768 } });
const page = await context.newPage();
const errors = [];
page.on('pageerror', error => errors.push(error.stack));
const q = (op, params = {}) => page.evaluate(async request =>
  (await import(performance.getEntriesByType('resource').filter(e => e.name.includes('/src/engine.ts')).at(-1)?.name ?? '/src/engine.ts')).ask(request),
  { op, ...params });
const btn = label => page.getByRole('button', { name: label, exact: true });

try {
  await page.goto(url);
  await signInLocal(page, 'cas-empress-qa', true);
  await resumeExercise(page);
  await btn('演习设置').click();
  await page.getByLabel('演习时段').selectOption('empress');
  await page.getByLabel('对手 AI').selectOption('coord');
  await page.getByLabel('演习编号').fill('6100');
  await btn('开始新演习').click();
  await page.getByRole('dialog').waitFor({ state: 'hidden' });
  const start = await q('observe');
  assert.equal(start.variant, 'empress');
  assert.equal(start.ships.length, 12, 'the allied seat sees twelve hulls');
  assert.equal(start.fleets.length, 3, 'three allied columns');
  assert.equal(start.environment.light, 'night');
  assert.equal(start.environment.visibility, 10);
  assert.equal(start.environment.precipitation, true);
  assert.equal(start.ships.filter(ship => ship.kind === 'cl').length, 4);
  for (const fleet of [1, 2, 3]) {
    await q('ai', { fleet, profile: 'coord', mode: 'auto', move: true, gun: true, torpedo: true });
  }
  let end = await q('step', { seconds: 2700 });
  if (!end.result) end = await q('step', { seconds: 2700 });
  assert(end.result, 'the scenario must resolve');
  const report = await q('report');
  for (const kind of ['secondary', 'illumination', 'gun', 'torpedo_detected']) {
    assert(report.events.some(event => event.kind === kind), 'missing ' + kind);
  }
  await page.screenshot({ path: root + 'empress-battle.png' });
  // Campaign slot 11: the same action launches from the campaign chart.
  await btn('母港').click();
  await page.locator('.growth-campaign-entry').click();
  await page.locator('.archive-list').waitFor();
  await page.getByRole('button', { name: '同盟战线', exact: true }).click();
  const row = page.locator('li[data-stage-id="CAMP-ALLIES-11"]');
  await row.waitFor();
  assert.equal(await row.getAttribute('data-playable'), 'true');
  await row.locator(':scope > details > summary').first().click();
  await row.getByRole('button', { name: '出航作战' }).click();
  await page.locator('.battle-map').waitFor();
  const campaign = await q('observe');
  assert.equal(campaign.campaign.stageId, 'CAMP-ALLIES-11');
  assert.equal(campaign.ships.length, 12);
  assert.equal(campaign.fleets.length, 3);
  await page.screenshot({ path: root + 'empress-campaign.png' });
  await fs.writeFile(root + 'browser-receipt.json', JSON.stringify({
    ok: true,
    variant: start.variant,
    alliedShips: start.ships.length,
    columns: start.fleets.length,
    environment: start.environment,
    result: end.result,
    events: report.events.length,
    secondary: report.events.some(event => event.kind === 'secondary'),
    illumination: report.events.some(event => event.kind === 'illumination'),
    gun: report.events.some(event => event.kind === 'gun'),
    torpedo: report.events.some(event => event.kind === 'torpedo'),
  }, null, 2) + '\n');
  assert.deepEqual(errors, []);
  console.log(JSON.stringify({ ok: true, result: end.result }, null, 2));
} finally {
  await browser.close();
}
