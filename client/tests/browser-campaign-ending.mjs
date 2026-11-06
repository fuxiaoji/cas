import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { signInLocal } from './browser-login.mjs';

const { chromium } = createRequire(import.meta.url)(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const out = process.env.CAS_ARTIFACTS || fileURLToPath(new URL('../../artifacts/client/campaign-endings/', import.meta.url));
const url = process.env.CAS_TEST_URL || 'http://127.0.0.1:5175/';
const ledger = JSON.parse(await fs.readFile(new URL('../src/campaign-ending/ledger.json', import.meta.url), 'utf8'));
const cases = [
  ['CAMP-ALLIES-01', 'story', 'victory'],
  ['CAMP-ALLIES-01', 'challenge', 'defeat'],
  ['CAMP-AXIS-01', 'standard', 'victory', 'gunnery'],
  ['CAMP-AXIS-01', 'story', 'defeat'],
  ['CAMP-ALLIES-03', 'story', 'victory', 'coord'],
  ['CAMP-ALLIES-03', 'story', 'defeat'],
  ['CAMP-AXIS-03', 'story', 'victory', 'withdraw'],
  ['CAMP-AXIS-03', 'standard', 'draw'],
  ['CAMP-AXIS-03', 'story', 'defeat'],
];
await fs.mkdir(out, { recursive: true });
const browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });

try {
  const page = await browser.newPage({ viewport: { width: 1360, height: 768 } });
  page.setDefaultTimeout(10_000);
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  const button = (name, scope = page) => scope.getByRole('button', { name, exact: true });
  const map = page.locator('.battle-map');
  const archive = page.getByRole('region', { name: 'CAS 战役档案' });
  const ask = (op, parameters = {}) => page.evaluate(async request =>
    (await import(performance.getEntriesByType('resource').filter(entry => entry.name.includes('/src/engine.ts')).at(-1)?.name
      ?? '/src/engine.ts')).ask(request), { op, ...parameters });

  async function selectFleet(fleet) {
    await button('编队').click();
    await page.getByLabel('选择编队').selectOption(String(fleet.id));
  }
  async function enableAi(fleet, profile, move) {
    await selectFleet(fleet);
    await button('战术 AI').click();
    await page.getByLabel('AI 风格').selectOption(profile);
    await page.getByLabel('指挥权限').selectOption('auto');
    const maneuver = page.getByLabel('编队机动');
    await maneuver.waitFor();
    if (!move) {
      await maneuver.click();
      await page.waitForFunction(() => document.querySelector('.ai-panel fieldset input')?.checked === false);
    }
    const observation = await ask('observe');
    assert.deepEqual(observation.fleets.find(value => value.id === fleet.id).ai,
      { profile, mode: 'auto', move, gun: true, torpedo: true });
  }
  async function withdraw(fleet, x, y, speed) {
    await selectFleet(fleet);
    await button('领舰移动').click();
    await page.locator('.speed-setting summary').click();
    await page.getByLabel('航速（节）').fill(String(speed));
    for (const xWaypoint of [x, 400]) {
      const point = await map.evaluate((element, { x, y }) => {
        const box = element.getBoundingClientRect();
        return { x: box.x + Number(element.dataset.chartLeft) + x * Number(element.dataset.chartRatio),
          y: box.y + Number(element.dataset.chartBottom) - y * Number(element.dataset.chartRatio) };
      }, { x: xWaypoint, y });
      await page.mouse.click(point.x, point.y);
    }
    await page.getByText('航线可用', { exact: true }).waitFor();
    await button('下达航线').click();
    await page.getByRole('status').filter({ hasText: '新航线已下达。' }).waitFor();
    await enableAi(fleet, 'torpedo', false);
  }

  await page.goto(url);
  await signInLocal(page, 'cas-ending-qa', true);
  const evidence = [];
  for (const [stageId, difficulty, expected, strategy] of cases) {
    const side = stageId.includes('ALLIES') ? 'allies' : 'axis';
    // The axis loss in the short layout checks the original fullscreen image and
    // all controls with the same constrained height as the mobile game.
    if (stageId === 'CAMP-AXIS-03' && expected === 'defeat') await page.setViewportSize({ width: 740, height: 360 });
    if (await map.isVisible()) await button('母港').click();
    await page.locator('.growth-campaign-entry').click();
    await archive.locator('.archive-list').waitFor();
    await button(side === 'allies' ? '同盟战线' : '轴心战线', archive).click();
    await archive.getByLabel('难度').selectOption(difficulty);
    const row = archive.locator(`[data-stage-id="${stageId}"]`);
    await row.locator('summary').first().click();
    await button('出航作战', row).click();
    await map.waitFor();

    let state = await ask('observe');
    assert.equal(state.campaign.stageId, stageId);
    assert.equal(state.side, side);
    assert.equal(state.campaign.roster, undefined);
    const openingCast = state.ships.map(ship => ship.characterId).sort();
    assert(openingCast.every(Boolean));
    if (strategy === 'withdraw') {
      for (const [id, x, y, speed] of [[3, 30_000, 35_000, 35], [4, 33_000, 3_000, 33]]) {
        await withdraw(state.fleets.find(fleet => fleet.id === id), x, y, speed);
      }
    } else if (strategy) {
      for (const fleet of state.fleets) await enableAi(fleet, strategy, true);
    }
    for (let i = 0; i < 3 && !state.result; i++) state = await ask('step', { seconds: 2700 });
    assert(state.result, stageId + ' never reached the real result');
    const outcome = state.result.winner === 'draw' ? 'draw' : state.result.winner === side ? 'victory' : 'defeat';
    assert.equal(outcome, expected, stageId + ' ' + difficulty + ' ' + strategy);
    assert.deepEqual(state.campaign.roster.map(ship => ship.characterId).sort(), openingCast);
    await button('推进一秒').click(); // Let the actual client receive the final worker projection.

    if (outcome === 'draw') {
      await page.locator('.campaign-debrief').waitFor();
      assert.equal(await page.locator('dialog.campaign-ending[open]').count(), 0);
      assert.equal(await button('回看结局').count(), 0);
      evidence.push({ stageId, difficulty, outcome, winner: state.result.winner, tick: state.tick, skippedVictoryAndDefeat: true });
      continue;
    }

    const dialog = page.getByRole('dialog', { name: outcome === 'victory' ? '战斗胜利' : '战斗失利' });
    await dialog.waitFor();
    assert.equal(await dialog.getAttribute('data-stage-id'), stageId);
    assert.equal(await dialog.getAttribute('data-side'), side);
    assert.equal(await dialog.getAttribute('data-outcome'), outcome);
    assert.equal(await dialog.locator('.campaign-ending__frame').getAttribute('data-art-kind'), 'illustration');
    assert.equal(await page.locator('.campaign-debrief').count(), 0);
    const art = dialog.locator('img.campaign-ending__plate');
    const actual = await art.evaluate(async img => {
      await img.decode();
      const response = await fetch(img.currentSrc);
      if (!response.ok) throw new Error('Could not load the displayed CG');
      const bytes = await response.arrayBuffer();
      const digest = await crypto.subtle.digest('SHA-256', bytes);
      return { size: [img.naturalWidth, img.naturalHeight],
        sha256: Array.from(new Uint8Array(digest), x => x.toString(16).padStart(2, '0')).join('') };
    });
    const original = ledger.assets.find(asset => asset.stage_id === stageId && asset.outcome === outcome);
    assert.deepEqual(actual, { size: original.size, sha256: original.sha256 });
    await button('舰名', dialog).click();
    const cast = dialog.getByRole('list', { name: '本方参战舰娘' });
    const ids = await cast.locator('li').evaluateAll(elements => elements.map(element => element.dataset.shipId).sort());
    assert.deepEqual(ids, openingCast);
    await button('放大', dialog).click();
    assert.equal(await button('全景', dialog).getAttribute('aria-pressed'), 'true');
    await button('全景', dialog).click();
    if (side === 'axis' || outcome === 'victory') await page.screenshot({ path: `${out}/${stageId}-${outcome}.png` });
    if (stageId === 'CAMP-AXIS-03' && outcome === 'defeat') {
      await page.evaluate(() => window.dispatchEvent(new Event('hardware-back')));
    } else {
      await button('查看战果', dialog).click();
    }
    await page.locator('.campaign-debrief').waitFor();
    assert.equal(await page.locator('dialog.campaign-ending[open]').count(), 0);
    if (!evidence.length) {
      await button('回看结局').click();
      await dialog.waitFor();
      assert.equal(await dialog.getAttribute('data-stage-id'), stageId);
      await button('查看战果', dialog).click();
      await page.locator('.campaign-debrief').waitFor();
      await button('母港').click();
      await button('打开主菜单').click();
      await button('继续演习').click();
      await page.locator('.campaign-debrief').waitFor();
      assert.equal(await page.locator('dialog.campaign-ending[open]').count(), 0);
    }
    evidence.push({ stageId, difficulty, outcome, winner: state.result.winner, grade: state.result.grade, tick: state.tick,
      participants: ids, remainingOnChart: state.ships.length, image: actual });
  }

  const replay = page.getByRole('slider', { name: '重演时间' });
  await button('重演战局').click();
  await replay.waitFor();
  await replay.fill(await replay.getAttribute('max'));
  assert.equal(await page.locator('dialog.campaign-ending[open]').count(), 0);
  await button('返回现局').click();
  await replay.waitFor({ state: 'hidden' });
  assert.equal(await page.locator('dialog.campaign-ending[open]').count(), 0);
  assert.deepEqual(errors, []);
  const receipt = { evidence, replayDoesNotReopenCG: true, sameSessionDoesNotReopenCG: true, manualEndingReview: true };
  await fs.writeFile(out + '/browser-receipt.json', JSON.stringify(receipt, null, 2));
  console.log(JSON.stringify(receipt, null, 2));
} finally {
  await browser.close();
}
