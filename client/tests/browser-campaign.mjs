import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { resumeExercise, signInLocal } from './browser-login.mjs';

const { chromium } = createRequire(import.meta.url)(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const out = process.env.CAS_ARTIFACTS || fileURLToPath(new URL('../../artifacts/client/campaign/', import.meta.url));
const url = process.env.CAS_TEST_URL || 'http://127.0.0.1:5175/';
const portraitLedger = JSON.parse(await fs.readFile(new URL('../src/assets/portraits/ledger.json', import.meta.url), 'utf8'));
const campaignSource = JSON.parse(await fs.readFile(new URL('../../data/campaign/crosswalk.json', import.meta.url), 'utf8'));
const zhLabels = JSON.parse(await fs.readFile(new URL('../../data/campaign/locale/zh-labels.json', import.meta.url), 'utf8'));
const hanzi = /\p{Script=Han}/u;
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
    for (const ship of state.ships) {
      const name = zhLabels.ships[state.side][ship.name] ?? ship.name;
      assert.match(name, hanzi);
      assert.match(await picker.locator(`option[value="${ship.id}"]`).innerText(), hanzi);
      assert((await picker.locator(`option[value="${ship.id}"]`).innerText()).includes(name));
    }
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

  function archivedShipNames(value) {
    if (typeof value === 'string') return [value];
    if (Array.isArray(value)) return value.flatMap(archivedShipNames);
    if (!value || typeof value !== 'object') return [];
    if (typeof (value.name ?? value.ship) === 'string') return [value.name ?? value.ship];
    if (typeof value.class === 'string' && Number.isInteger(value.count)) return [value.class];
    return Object.entries(value).flatMap(([key, member]) =>
      key !== 'deployment' && member && typeof member === 'object' ? archivedShipNames(member) : []);
  }

  async function verifyChineseArchive() {
    const verified = [];
    for (const [side, buttonName] of [['allies', '同盟战线'], ['axis', '轴心战线']]) {
      await button(buttonName).click();
      for (const entry of campaignSource.scenarios) {
        const stageId = entry.stage_ids.find(id => id.startsWith(`CAMP-${side.toUpperCase()}-`));
        const row = archive.locator(`[data-stage-id="${stageId}"]`);
        assert.equal(await row.locator('.archive-name strong').innerText(), entry.ibs_title);
        assert.match(entry.ibs_title, hanzi);
        if (!await row.locator('details').first().evaluate(el => el.open)) await row.locator('summary').first().click();
        const detail = row.locator('.archive-source');
        await detail.waitFor();
        if (entry.cas) {
          const source = row.locator('[data-source-title]');
          assert.equal(await source.getAttribute('data-source-title'), entry.cas.title);
          assert.equal(await source.innerText(), zhLabels.scenario_titles[entry.cas.scenario_id] ?? entry.ibs_title);
        }
        const sections = detail.locator('.archive-sides > section');
        assert.equal(await sections.count(), 2);
        const { record, legacy } = await q('campaign_detail', { id: stageId });
        for (const [index, faction] of [side, side === 'allies' ? 'axis' : 'allies'].entries()) {
          const sectionText = await sections.nth(index).textContent();
          if (legacy) {
            const ships = legacy.ships.filter(ship => ship.side === faction);
            assert.equal(await sections.nth(index).locator('li').count(), ships.length);
            assert(ships.every(ship => hanzi.test(ship.name) && sectionText.includes(ship.name)));
            assert.doesNotMatch(sectionText, /原编队/);
          } else {
            const names = archivedShipNames(record.forces?.[faction]);
            for (const group of record.groups?.filter(group => group.side === faction) ?? []) {
              for (const id of group.members_in_order) names.push(record.ships.find(ship => ship.id === id).name);
            }
            assert(names.length > 0);
            for (const name of names) {
              const localized = zhLabels.ships[faction][name];
              assert(localized && hanzi.test(localized), `${stageId}: missing Chinese name for ${name}`);
              assert(sectionText.includes(localized), `${stageId}: ${localized} missing from fleet display`);
            }
          }
          assert.match(sectionText, hanzi);
          assert.doesNotMatch(sectionText, /Desron|Desdiv|Crudiv|Batdiv|allies-[a-z]|axis-[a-z]|Buka Reinforcement|Destroyer Transport Group/);
          assert.doesNotMatch(sectionText, /\b(?:Charles F\. Ausburne|Hamakaze|McCawley|Denver|Kazagumo|Hayashimo)\b/);
        }
        if (stageId.endsWith('-06')) assert.match(await detail.innerText(), /早霜.*山浦丸/s);
        if (stageId.endsWith('-13')) {
          const text = await detail.innerText();
          assert.match(text, /风云/);
          assert.match(text, /零式水上观测机/);
        }
        if (stageId.endsWith('-14')) assert.match(await detail.innerText(), /甲型大发登陆艇 × 13/);
        if (stageId.endsWith('-16')) assert.match(await detail.textContent(), /挺身夜战战队/);
        verified.push(stageId);
      }
    }
    assert.equal(new Set(verified).size, 32);
    await button('同盟战线').click();
    return verified;
  }

  async function verifyCampaignMap() {
    const map = archive.getByRole('region', { name: '海战地理航图' });
    const area = name => map.getByRole('navigation', { name: '战区' }).getByRole('button', { name, exact: true });
    const pin = name => map.getByRole('button', { name });
    const visibleIds = () => archive.locator('.archive-list > li').evaluateAll(rows => rows.map(row => row.dataset.stageId));
    const chapterIds = (side, ...chapters) => chapters.map(chapter => `CAMP-${side}-${chapter}`);

    assert.match(await map.getByRole('status').innerText(), /16 个关卡/);
    await pin(/^欧洲战区，1 个关卡/).click();
    assert.deepEqual(await visibleIds(), chapterIds('ALLIES', '01'));
    await pin(/^普利茅斯外海，1 个关卡/).click();
    assert.equal(await pin(/^普利茅斯外海/).getAttribute('aria-pressed'), 'true');
    await archive.getByLabel('档案范围').selectOption('exact_historical_counterpart');
    assert.deepEqual(await visibleIds(), []);
    await archive.getByText('该海域没有符合筛选的关卡。', { exact: true }).waitFor();
    assert.match(await map.getByRole('status').innerText(), /0 个关卡/);
    await archive.getByLabel('档案范围').selectOption('all');
    assert.deepEqual(await visibleIds(), chapterIds('ALLIES', '01'));

    await area('北所罗门').click();
    assert.deepEqual(await visibleIds(), chapterIds('ALLIES', '03', '11', '12'));
    const georgePin = pin(/^圣乔治角外海，1 个关卡/);
    await stage('allies').locator('summary').first().click();
    await stage('allies').locator('.archive-source').waitFor();
    assert.equal(await georgePin.getAttribute('data-highlighted'), 'true');
    await georgePin.click();
    assert.deepEqual(await visibleIds(), chapterIds('ALLIES', '03'));
    assert(await stage('allies').locator('.archive-source').isVisible());
    await map.getByRole('button', { name: '显示全战区' }).click();
    assert.deepEqual(await visibleIds(), chapterIds('ALLIES', '03', '11', '12'));

    await area('中所罗门').click();
    assert.deepEqual(await visibleIds(), chapterIds('ALLIES', '04', '07', '08', '13', '14'));
    await pin(/^韦拉拉韦拉，2 个关卡/).click();
    assert.deepEqual(await visibleIds(), chapterIds('ALLIES', '13', '14'));
    await button('轴心战线').click();
    assert.deepEqual(await visibleIds(), chapterIds('AXIS', '13', '14'));
    await stage('axis', '14').locator('summary').first().click();
    await stage('axis', '14').locator('.archive-source').waitFor();
    assert.match(await stage('axis', '14').locator('.archive-source').innerText(), /甲型大发登陆艇 × 13/);
    await map.screenshot({ path: out + '/06-campaign-geography.png' });
    await area('战区总览').click();
    assert.equal((await visibleIds()).length, 16);
    await button('同盟战线').click();
    assert.equal((await visibleIds()).length, 16);

    const mobile = await browser.newPage({ viewport: { width: 740, height: 360 }, hasTouch: true, isMobile: true });
    try {
      await mobile.goto(url);
      await signInLocal(mobile, 'cas-campaign-map-touch', true);
      await mobile.locator('.growth-campaign-entry').tap();
      const mobileMap = mobile.getByRole('region', { name: '海战地理航图' });
      await mobileMap.getByRole('button', { name: '铁底湾', exact: true }).tap();
      await mobileMap.getByRole('button', { name: /^铁底湾，6 个关卡/ }).tap();
      assert.equal(await mobile.locator('.archive-list > li').count(), 6);
      const rect = await mobileMap.boundingBox();
      assert(rect && rect.x >= 0 && rect.x + rect.width <= 741);
    } finally {
      await mobile.close();
    }
    return { overviewPerSide: 16, channelStages: 1, northStages: 3, vellaStagesPerSide: 2, emptyFilter: true, landscapeTouch: true };
  }

  await page.goto(url);
  await signInLocal(page, 'cas-campaign-qa', true);
  await toArchive();
  assert.equal(await archive.locator('.archive-list > li').count(), 16);
  const map = await verifyCampaignMap();
  const chineseStages = await verifyChineseArchive();
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
  const receipt = { map, chineseStages, lockedStageDenied: true, opened, namedPortraits, savedAndRestoredTick: restored.tick, replayReturnedToLive: true };
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
  if (process.env.CAS_CAMPAIGN_REWARD === '1') {
    const axis = await q('new_campaign', { id: 'CAMP-AXIS-01', difficulty: 'story', seed: 53 });
    for (const fleet of axis.fleets) await q('ai', { fleet: fleet.id, profile: 'gunnery', mode: 'auto', move: true, gun: true, torpedo: true });
    const end = await q('step', { seconds: 840 });
    assert.equal(end.result?.grade, 'tactical');
    assert.equal(end.result?.winner, 'axis');
    assert.equal(end.result?.allies, 0);
    const report = await q('report');
    assert(report.events.some(event => event.kind === 'torpedo_hit'));
    await button('推进一秒').click();
    await page.locator('.campaign-debrief .campaign-stars[data-stars="2"]').waitFor();
    await button('领取战役奖励').click();
    await page.getByText('已达成的星级奖励已领取。').waitFor();
    await toArchive();
    const cleared = await selectStage('axis', 'standard', '01');
    assert.equal(await cleared.getByRole('button', { name: '领取战役奖励' }).count(), 0);
    const balance = await page.locator('.harbor-wallet').innerText();
    assert.match(balance, /补给币 600/);
    assert.match(balance, /常驻券 2/);
    receipt.channelReward = { stageId: end.campaign.stageId, tick: end.tick, grade: end.result.grade, balance,
      torpedoHit: true, duplicateDeniedAtOtherDifficulty: true };
  }
  assert.deepEqual(errors, []);
  await fs.writeFile(out + '/browser-receipt.json', JSON.stringify(receipt, null, 2));
  console.log(JSON.stringify(receipt, null, 2));
} finally { await browser.close(); }
