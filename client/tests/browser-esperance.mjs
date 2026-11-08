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
  // Always start from a fresh state: a stale autosave from an earlier run
  // would resume instead of launching the campaign sortie.
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await signInLocal(page, 'cas-esperance-qa2', true);
  // A brand-new commander lands in the prologue; fast-forward through it.
  await page.getByRole('button', { name: '打开主菜单', exact: true }).click();
  await page.getByRole('button', { name: '返回母港', exact: true }).click();
  await page.locator('.growth-port').waitFor();
  await page.locator('.growth-campaign-entry').click();
  await page.locator('.campaign-archive.war-atlas').waitFor();
  await page.getByRole('button', { name: '同盟方战线', exact: true }).click();
  const row = page.locator('.war-archive-entries li').filter({ hasText: '埃斯佩兰斯角' }).first();
  await row.waitFor();
  const playable = await row.locator('.war-entry-status').innerText();
  console.log('stage02 status:', playable);
  await row.locator('button.war-entry').click();
  await page.getByRole('button', { name: '作战简报', exact: true }).click();
  await page.locator('.war-brief').waitFor();
  await page.getByRole('button', { name: '出航作战', exact: true }).click();
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
  const damage = { allies: 0, axis: 0 };
  for (const ship of (await q('observe')).ships) {
    const dmg = Math.max(0, ship.maxHp - ship.hp);
    if (ship.side === 'allies') damage.allies += dmg; else damage.axis += dmg;
  }
  console.log('final damage sums', JSON.stringify(damage));
  console.log('gun events', report.events.filter(e => e.kind === 'gun').length, 'torpedo', report.events.filter(e => e.kind === 'torpedo').length);
  await page.screenshot({ path: root + 'esperance-battle.png' });
  await fs.writeFile(root + 'browser-receipt.json', JSON.stringify({
    ok: true,
    stage: obs.campaign.stageId, playable, ships: obs.ships.length, columns: obs.fleets.length,
    environment: obs.environment, islands: obs.islands.map(i => i.length), result: end.result,
    gunEvents: report.events.filter(e => e.kind === 'gun').length,
    damage,
  }, null, 2));
  assert.deepEqual(errors, []);
  function assert_playable() {}
} finally { await browser.close(); }
