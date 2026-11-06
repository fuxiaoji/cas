import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { resumeExercise, signInLocal } from './browser-login.mjs';

const { chromium } = createRequire(import.meta.url)(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const out = process.env.CAS_ARTIFACTS || fileURLToPath(new URL('../../artifacts/client/campaign/', import.meta.url));
const url = process.env.CAS_TEST_URL || 'http://127.0.0.1:5175/';
const portraitLedger = JSON.parse(await fs.readFile(new URL('../src/assets/portraits/ledger.json', import.meta.url), 'utf8'));
const namedIds = {
  allies: { 'Charles F. Ausburne': 'IBS-U-USN-CF-AUSBURNE', Claxton: 'IBS-U-USN-CLAXTON',
    Dyson: 'IBS-U-USN-DYSON', Converse: 'IBS-U-USN-CONVERSE', Spence: 'IBS-U-USN-SPENCE' },
  axis: { Onami: 'IBS-U-IJN-ONAMI', Makinami: 'IBS-U-IJN-MAKINAMI', Amagiri: 'IBS-U-IJN-AMAGIRI',
    Yugiri: 'IBS-U-IJN-YUGIRI', Uzuki: 'IBS-U-IJN-UZUKI' },
};
await fs.mkdir(out, { recursive: true });
const browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });
try {
  const page = await browser.newPage({ viewport: { width: 1360, height: 768 } });
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.stack));
  const button = (name) => page.getByRole('button', { name, exact: true });
  const q = (op, params = {}) => page.evaluate(async (request) =>
    (await import(performance.getEntriesByType('resource').filter((e) => e.name.includes('/src/engine.ts')).at(-1)?.name ?? '/src/engine.ts')).ask(request),
  { op, ...params });
  const archive = page.getByRole('region', { name: 'CAS 战役档案' });
  const stage = (side, chapter = '03') => archive.locator(`[data-stage-id="CAMP-${side.toUpperCase()}-${chapter}"]`);
  const stamp = (tick) => String(Math.floor(tick / 60)).padStart(2, '0') + ':' + String(tick % 60).padStart(2, '0');
  async function toArchive() {
    if (await archive.locator('.archive-list').isVisible()) return;
    if (await page.locator('.battle-map').isVisible()) await button('母港').click();
    await page.locator('.growth-campaign-entry').click();
    await archive.locator('.archive-list').waitFor();
  }
  async function selectStage(side, difficulty, chapter = '03') {
    await button(side === 'allies' ? '同盟战线' : '轴心战线').click();
    await archive.getByLabel('难度').selectOption(difficulty);
    const row = stage(side, chapter);
    assert.equal(await row.getAttribute('data-playable'), 'true');
    const info = row.locator('details').first();
    if (!await info.evaluate((el) => el.open)) await row.locator('summary').first().click();
    await row.getByRole('button', { name: '出航作战', exact: true }).waitFor();
    return row;
  }
  async function launch(side, difficulty) {
    const row = await selectStage(side, difficulty);
    assert.match(await row.locator('.archive-sortie-brief').innerText(), /RTS 改编/);
    await row.getByRole('button', { name: '出航作战', exact: true }).click();
    await page.locator('.battle-map').waitFor();
    const o = await q('observe');
    assert.equal(o.campaign.stageId, `CAMP-${side.toUpperCase()}-03`);
    assert.equal(o.campaign.difficulty, difficulty);
    assert.equal(o.side, side);
    assert.equal(o.ships.length, 5);
    assert(o.ships.every((ship) => ship.kind === 'dd'), 'The scenario must borrow historical destroyers');
    assert(o.ships.every((ship) => !ship.name.includes('级 ')), 'Generic exercise hulls cannot replace historical identities');
    assert(o.campaign.objectives.length > 10);
    await page.getByRole('region', { name: '战役任务' }).waitFor();
    assert.match(await page.getByRole('region', { name: '战役任务' }).innerText(), /圣乔治角/);
    return o;
  }
  async function inspectNamedPortraits(state, chapter = '03') {
    const expected = chapter === '03' ? namedIds[state.side] :
      Object.fromEntries(state.ships.map(ship => [ship.name, ship.classId]));
    assert.deepEqual(Object.fromEntries(state.ships.map(ship => [ship.name, ship.characterId])), expected);
    await button('舰况').click();
    const picker = page.getByRole('combobox', { name: '查看舰艇' });
    const decoded = [];
    for (const ship of state.ships) {
      const source = portraitLedger.assets.find(item => item.ibs_character_id === expected[ship.name]);
      assert(source && source.mapping === 'named_identity');
      assert.equal(ship.classId, source.cas_class_id);
      await picker.selectOption(String(ship.id));
      const card = page.locator('.ship-portrait[data-character="' + ship.characterId + '"]');
      const image = card.getByAltText(source.character_name + '舰娘立绘', { exact: true });
      await image.waitFor();
      const decodedImage = await image.evaluate(async (img) => {
        await img.decode();
        const response = await fetch(img.currentSrc);
        if (!response.ok) throw new Error('Could not fetch displayed portrait bytes: ' + response.status);
        const hash = await crypto.subtle.digest('SHA-256', await response.arrayBuffer());
        return { width: img.naturalWidth, height: img.naturalHeight,
          sha256: Array.from(new Uint8Array(hash), n => n.toString(16).padStart(2, '0')).join('') };
      });
      assert(decodedImage.width > 0 && decodedImage.height > 0);
      assert.equal(decodedImage.sha256, source.sha256);
      assert.doesNotMatch(await card.locator('figcaption').innerText(), /舰型代表/);
      decoded.push({ ship: ship.name, characterId: ship.characterId, ...decodedImage });
      if (ship === state.ships[0]) await page.screenshot({ path: out + '/04-named-' + chapter + '-' + state.side + '.png' });
    }
    return decoded;
  }
  async function replayAndReturn(expected) {
    await button('战情记录').click();
    await button('重演').click();
    await page.getByRole('slider', { name: '重演时间' }).waitFor();
    await page.waitForFunction(() => document.querySelector('.time strong')?.textContent === '00:00');
    assert.equal((await q('observe')).campaign.stageId, expected.campaign.stageId, 'Replay mutated the live session');
    await button('返回现局').click();
    await page.getByRole('slider', { name: '重演时间' }).waitFor({ state: 'hidden' });
    assert.equal((await q('observe')).tick, expected.tick);
  }

  await page.goto(url);
  await signInLocal(page, 'cas-campaign-qa', true);
  await toArchive();
  assert.equal(await archive.locator('.archive-list > li').count(), 16);
  const locked = archive.locator('.archive-list > li[data-playable=false]').first();
  await locked.locator('summary').first().click();
  assert.match(await locked.locator('.archive-lock').innerText(), /未开放/);
  assert.equal(await locked.getByRole('button', { name: '出航作战' }).count(), 0);
  await assert.rejects(q('new_campaign', { id: await locked.getAttribute('data-stage-id'), difficulty: 'story', seed: 6106 }));
  const first = await selectStage('allies', 'story');
  await first.locator('.archive-source').waitFor();
  await first.getByText('原书版本仍待核验', { exact: true }).waitFor();
  await page.locator('.harbor-content').evaluate(el => { el.scrollTop = 0; });
  await page.screenshot({ path: out + '/01-cape-sortie.png' });

  const opened = [];
  const namedPortraits = [];
  for (const [side, difficulty] of [['allies', 'story'], ['axis', 'challenge'], ['allies', 'standard']]) {
    const state = await launch(side, difficulty);
    opened.push({ side, difficulty, stage: state.campaign.stageId, ships: state.ships.map((ship) => ship.name), objectives: state.campaign.objectives });
    if (difficulty !== 'standard') namedPortraits.push(...await inspectNamedPortraits(state));
    if (difficulty !== 'standard') await toArchive();
  }
  await page.screenshot({ path: out + '/02-live-mission.png' });
  await button('推进一秒').click();
  await page.waitForFunction(() => document.querySelector('.time strong')?.textContent === '00:01');
  const before = await q('observe');
  await replayAndReturn(before);
  await button('保存进度').click();
  await page.getByRole('status').filter({ hasText: '演习已保存' }).waitFor();
  await page.reload();
  await signInLocal(page, 'cas-campaign-qa');
  await resumeExercise(page);
  const restored = await q('observe');
  assert.equal(restored.tick, before.tick);
  assert.deepEqual(restored.campaign, before.campaign);
  assert.deepEqual(restored.ships, before.ships);

  // The winning fixture uses an actual command or AI delegation supplied
  // for the released campaign and never writes credits or progress directly.
  const receipt = { lockedStageDenied: true, opened, namedPortraits, savedAndRestoredTick: restored.tick, replayReturnedToLive: true };
  if (process.env.CAS_CAMPAIGN_REWARD === '1') {
    const winningSide = process.env.CAS_CAMPAIGN_WIN_SIDE ?? 'allies';
    const winningDifficulty = process.env.CAS_CAMPAIGN_WIN_DIFFICULTY ?? 'story';
    await toArchive();
    const winRow = await selectStage(winningSide, winningDifficulty);
    assert.equal(await winRow.getByRole('button', { name: '领取战役奖励' }).count(), 0);
    const balance = () => page.locator('.harbor-wallet').innerText();
    const originalBalance = await balance();
    const winning = await launch(winningSide, winningDifficulty);
    for (const fleet of winning.fleets) {
      await button('编队').click();
      if (winning.fleets.length > 1) await page.getByLabel('选择编队').selectOption(String(fleet.id));
      await button('战术 AI').click();
      await page.getByLabel('AI 风格').selectOption('coord');
      await page.getByLabel('指挥权限').selectOption('auto');
    }
    let state = await q('observe');
    assert(state.fleets.every(fleet => fleet.ai.profile === 'coord' && fleet.ai.mode === 'auto' && fleet.ai.move && fleet.ai.gun && fleet.ai.torpedo));
    for (let i = 0; !state.result && i < 8; i++) state = await q('step', { seconds: 900 });
    assert(state.result && ['tactical', 'decisive'].includes(state.result.grade), JSON.stringify(state.result));
    await button('推进一秒').click();
    await page.locator('.campaign-debrief').waitFor();
    const stars = state.result.grade === 'decisive' ? 3 : 2;
    assert.equal(await page.locator('.campaign-debrief .campaign-stars').getAttribute('data-stars'), String(stars));
    assert.match(await page.locator('.campaign-debrief').innerText(), state.result.grade === 'decisive' ? /决定(?:性)?胜利/ : /战术胜利/);
    await page.screenshot({ path: out + '/03-battle-rating.png' });
    const claimFromResult = process.env.CAS_CAMPAIGN_CLAIM_FROM_RESULT === '1';
    if (claimFromResult) {
      await button('领取战役奖励').click();
      await page.getByText('已达成的星级奖励已领取。').waitFor();
    }
    await toArchive();
    const clearedRow = await selectStage(winningSide, winningDifficulty);
    if (!claimFromResult) await clearedRow.getByRole('button', { name: '领取战役奖励', exact: true }).click();
    await clearedRow.getByText('已达成的星级奖励已领取。').waitFor();
    const creditedBalance = await balance();
    assert.notEqual(creditedBalance, originalBalance);
    assert.match(creditedBalance, /补给币 600/);
    assert.match(creditedBalance, stars === 3 ? /常驻券 4/ : /常驻券 2/);
    if (stars === 3) assert.match(creditedBalance, /舰队勋章 10/);
    await page.reload();
    await signInLocal(page, 'cas-campaign-qa');
    await toArchive();
    const reloaded = await selectStage(winningSide, winningDifficulty);
    await reloaded.getByText('已达成的星级奖励已领取。').waitFor();
    assert.equal(await balance(), creditedBalance);
    assert.equal(await reloaded.getByRole('button', { name: '领取战役奖励' }).count(), 0);
    const otherDifficulty = winningDifficulty === 'standard' ? 'story' : 'standard';
    await archive.getByLabel('难度').selectOption(otherDifficulty);
    assert.equal(await reloaded.getByRole('button', { name: '领取战役奖励' }).count(), 0);
    await button('返回母港').click();
    await button('打开主菜单').click();
    await button('退出登录').click();
    await signInLocal(page, 'cas-campaign-separate-qa', true);
    await toArchive();
    const separate = await selectStage(winningSide, winningDifficulty);
    assert.match(await separate.locator('.archive-sortie-brief').innerText(), /尚无战果/);
    assert.match(await balance(), /补给币 0/);
    receipt.reward = { stageId: winning.campaign.stageId, grade: state.result.grade, stars, balance: creditedBalance, claimedFrom: claimFromResult ? 'battle-result' : 'archive',
      reloadBlockedDuplicate: true, rewardsSharedAcrossDifficulties: true, accountIsolated: true };
  }
  if (process.env.CAS_CAMPAIGN_REWARD !== '1') assert.equal(await page.locator('.time strong').textContent(), stamp(restored.tick));
  const channel = [];
  for (const side of ['allies', 'axis']) {
    await toArchive();
    const row = await selectStage(side, 'story', '01');
    await row.locator('.archive-deployment').waitFor();
    await row.getByRole('button', { name: '出航作战', exact: true }).click();
    await page.locator('.battle-map').waitFor();
    const state = await q('observe');
    assert.equal(state.variant, 'channel-action-rts');
    assert.equal(state.ships.length, side === 'allies' ? 5 : 3);
    assert.match(await page.getByRole('region', { name: '战役任务' }).innerText(), /通道行动/);
    channel.push({ side, stage: state.campaign.stageId, namedPortraits: await inspectNamedPortraits(state, '01') });
  }
  receipt.channel = channel;
  assert.deepEqual(errors, []);
  await fs.writeFile(out + '/browser-receipt.json', JSON.stringify(receipt, null, 2));
  console.log(JSON.stringify(receipt, null, 2));
} finally { await browser.close(); }
