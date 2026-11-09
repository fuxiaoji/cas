import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { signInLocal } from './browser-login.mjs';

const { chromium } = createRequire(import.meta.url)(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const out = process.env.CAS_ARTIFACTS || fileURLToPath(new URL('../../artifacts/client/challenge/', import.meta.url));
await fs.mkdir(out, { recursive: true });
const browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });
try {
  const page = await browser.newPage({ viewport: { width: 1360, height: 768 } });
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.stack));
  const q = (op, params = {}) => page.evaluate(async (request) =>
    (await import('/src/engine.ts')).ask(request), { op, ...params });
  const button = (name) => page.getByRole('button', { name, exact: true });
  const walletTickets = async () => {
    const match = (await page.locator('.harbor-wallet').innerText()).match(/征募券\s*(\d+)/);
    assert(match, 'wallet shows recruit tickets');
    return Number(match[1]);
  };
  const openChallenge = async () => {
    await page.locator('.growth-challenge-entry').click();
    await page.locator('.challenge-ladder').waitFor();
  };
  const backToHarbor = async () => {
    const link = page.locator('.harbor-link');
    if (await link.count()) await link.click();
    else await page.getByRole('button', { name: '返回母港', exact: true }).click();
    await page.locator('.growth-port').waitFor();
  };
  const stageCards = () => page.locator('.challenge-stage-card');
  async function clearSelectedStage(expect) {
    await button('出航挑战').click();
    await page.locator('.battle-map').waitFor();
    const before = await q('observe');
    const saved = await q('save');
    assert.equal(saved.challenge_stage, expect.id, `${expect.id} engine stage`);
    assert.equal(saved.seed, expect.seed, `${expect.id} engine seed`);
    assert.equal(before.variant, 'challenge');
    assert.equal(before.side, 'allies', `${expect.id} default side`);
    assert.equal(before.ships.length, expect.ships, `${expect.id} roster size`);
    assert.equal(before.fleets[0].ai.profile, expect.profile, `${expect.id} player AI profile`);
    if (expect.width) assert.equal(before.width, expect.width, `${expect.id} chart width`);
    const leaderBefore = before.ships.find((ship) => ship.id === before.fleets[0].leader);
    assert.equal(leaderBefore?.kind, expect.leaderKind, `${expect.id} leader kind`);
    if (expect.capital) {
      assert(before.ships.some((ship) => ship.kind === 'bb'), `${expect.id} fields a battleship`);
    }
    await button('战术 AI').click();
    await page.getByLabel('指挥权限').selectOption('auto');
    let state = await q('observe');
    let remaining = before.limit + 200;
    while (!state.result && remaining > 0) {
      const seconds = Math.min(600, remaining);
      state = await q('step', { seconds });
      remaining -= seconds;
    }
    if (!state.result) state = await q('step', { seconds: 8 });
    await button('推进一秒').click();
    const after = await q('observe');
    assert(after.result?.primary, `${expect.id} primary ${JSON.stringify(after.result)}`);
    await page.locator('.result-card h2').filter({ hasText: '挑战目标达成' }).waitFor();
    return { before, after };
  }
  async function ladderDocument() {
    return page.evaluate(() => {
      const rows = Object.entries(localStorage)
        .filter(([, value]) => value.includes('"challengeLadder"'))
        .map(([, value]) => {
          try { return JSON.parse(value); } catch { return null; }
        })
        .filter(Boolean);
      return rows.at(-1) ?? null;
    });
  }

  await page.goto(process.env.CAS_TEST_URL || 'http://127.0.0.1:5175/');
  await signInLocal(page, 'cas-challenge-qa', true);
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await signInLocal(page, 'cas-challenge-qa2', true);
  const portKey = await page.evaluate(() => Object.keys(localStorage).find((key) => key.includes('cas.harbor.progress.v1')));
  assert(portKey, 'the local port document exists');
  await page.evaluate((key) => {
    const state = JSON.parse(localStorage.getItem(key));
    state.starter = true;
    localStorage.setItem(key, JSON.stringify(state));
  }, portKey);
  await page.reload();
  await page.locator('.growth-port').waitFor();
  await openChallenge();

  const cards = stageCards();
  assert.equal(await cards.count(), 5, 'five staged challenge missions');
  assert.equal(await page.locator('.challenge-stage-card.blocked').count(), 0, 'no blocked placeholder stages');
  assert.match(await page.locator('.challenge-ladder').first().innerText(), /0 \/ 5 已通关/);
  assert.equal(await cards.nth(0).getAttribute('aria-pressed'), 'true');
  assert.equal(await cards.nth(1).isDisabled(), true, 'stage 2 starts locked');
  assert.equal(await cards.nth(4).isDisabled(), true, 'stage 5 starts locked');
  assert.match(await page.locator('.challenge-detail').innerText(), /1875 \/ 2000/);
  assert.match(await page.locator('.challenge-detail').innerText(), /种子 6100/);
  await page.screenshot({ path: out + 'challenge-stages-1360.png' });

  const stages = [
    { id: 'challenge-01', seed: 6100, ships: 3, profile: 'gunnery', leaderKind: 'cl' },
    { id: 'challenge-02', seed: 6102, ships: 3, profile: 'gunnery', leaderKind: 'cl' },
    { id: 'challenge-03', seed: 6124, ships: 4, profile: 'torpedo', leaderKind: 'dd' },
    { id: 'challenge-04', seed: 6212, ships: 5, profile: 'gunnery', leaderKind: 'bb', capital: true, width: 60000 },
    { id: 'challenge-05', seed: 6133, ships: 6, profile: 'coord', leaderKind: 'bb', capital: true, width: 60000 },
  ];
  const results = {};
  let firstClearTickets = null;
  for (const [index, expect] of stages.entries()) {
    if (index > 0) {
      await backToHarbor();
      await openChallenge();
      assert.equal(await cards.nth(index).isDisabled(), false, `${expect.id} unlocks after the previous stage`);
      await cards.nth(index).click();
    }
    const { after } = await clearSelectedStage(expect);
    results[expect.id] = after.result;
    if (index === 0) {
      await backToHarbor();
      await openChallenge();
      assert.match(await page.locator('.challenge-ladder').first().innerText(), /1 \/ 5 已通关/);
      assert.equal(await cards.nth(0).innerText().then((text) => /已通关/.test(text)), true);
      const ticketsBefore = await walletTickets();
      await button('领取挑战奖励').click();
      assert.equal(await button('已领取挑战奖励').isDisabled(), true);
      firstClearTickets = (await walletTickets()) - ticketsBefore;
      assert.equal(firstClearTickets, 2, 'first-clear reward stays 2 tickets');
    }
  }

  await backToHarbor();
  await openChallenge();
  assert.match(await page.locator('.challenge-ladder').first().innerText(), /5 \/ 5 已通关/);
  assert.equal(await page.locator('.challenge-stage-card.blocked').count(), 0);
  const beforeRepeat = await walletTickets();
  for (let index = 0; index < 3; index++) await button('领取复战奖励').click();
  const ticketsAfterRepeat = await walletTickets();
  assert.equal(ticketsAfterRepeat, beforeRepeat + 6, 'three repeat receipts pay 2 tickets each');
  assert.equal(await button('领取复战奖励').isDisabled(), true, 'no pending repeat receipts remain');
  const stored = await ladderDocument();
  assert.deepEqual(stored?.challengeLadder?.cleared, stages.map((stage) => stage.id));
  assert.equal(stored?.challengePending, undefined, 'the pending stage is consumed after a win');

  await page.reload();
  await page.locator('.growth-port').waitFor();
  await openChallenge();
  assert.match(await page.locator('.challenge-ladder').first().innerText(), /5 \/ 5 已通关/);
  await page.setViewportSize({ width: 740, height: 360 });
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  assert(overflow <= 1, `740x360 must not scroll horizontally (overflow ${overflow})`);
  await page.screenshot({ path: out + 'challenge-stages-740.png' });
  assert.deepEqual(errors, []);

  const receipt = {
    ok: true,
    stages: 5,
    blocked: 0,
    clearOrder: stages.map((stage) => stage.id),
    results,
    persisted: stored?.challengeLadder ?? null,
    rewards: { firstClearTickets, repeatTickets: ticketsAfterRepeat - beforeRepeat },
    viewport740Overflow: overflow,
    screenshots: ['challenge-stages-1360.png', 'challenge-stages-740.png'],
  };
  await fs.writeFile(out + 'receipt.json', JSON.stringify(receipt, null, 2));
  console.log('challenge receipt', JSON.stringify(receipt));
} finally {
  await browser.close();
}
