import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs/promises';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const root = process.env.CAS_ARTIFACTS || 'artifacts/client/ai-shop/';
const url = process.env.CAS_TEST_URL || 'http://127.0.0.1:5175/';
const portKey = 'cas.profile.test-commander.cas.harbor.progress.v1';
const saveKey = 'cas.profile.test-commander.cas.exercise.autosave.v1';
await fs.mkdir(root, { recursive: true });

const seed = {
  version: 1,
  lessons: ['lead', 'follow', 'sync', 'gun', 'cancel', 'torpedo', 'override'],
  starter: true, challengeClear: false, challengeClaim: false,
  wallet: { standard: 5000, up: 0 }, marks: 0, pity: { standard: 0, up: 0 },
  owned: { fletcher: 4, cleveland: 1 },
  profiles: ['coord'],
  preset: { side: 'allies', leaderSlot: 0, profile: 'coord' },
  upSide: 'axis', sequence: 0, history: [], credits: 0, courses: [], attendance: [],
  challengeReceipts: {}, mail: [],
  campaignProgress: {
    'CAMP-ALLIES-02': { best: { story: 2 }, claimed: 2 },
    'CAMP-ALLIES-03': { best: { story: 2 }, claimed: 2 },
  },
};

const errors = [];
const browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });
const page = await (await browser.newContext({ viewport: { width: 1360, height: 768 }, locale: 'zh-CN' })).newPage();
page.on('pageerror', error => errors.push(error.stack));
const readPort = () => page.evaluate(key => JSON.parse(localStorage.getItem(key) || 'null'), portKey);
const writePort = value => page.evaluate(([key, state]) => localStorage.setItem(key, JSON.stringify(state)), [portKey, value]);
const q = (op, params = {}) => page.evaluate(async request =>
  (await import(performance.getEntriesByType('resource').filter(entry => entry.name.includes('/src/engine.ts')).at(-1)?.name ?? '/src/engine.ts')).ask(request), { op, ...params });
const openShop = async () => {
  await page.locator('.growth-dock button[data-guide="economy"]').click();
  await page.locator('.harbor').waitFor();
  await page.getByRole('button', { name: 'AI 战术', exact: true }).click();
  await page.locator('.ai-shop-grid').waitFor();
};
const openHarbor = async section => {
  await page.locator(`.growth-dock button[data-guide="${section}"]`).click();
  await page.locator('.harbor').waitFor();
};

try {
  await page.addInitScript(([key, value]) => {
    if (!localStorage.getItem('cas.ai-shop.seeded')) {
      localStorage.setItem(key, JSON.stringify(value));
      localStorage.setItem('cas.ai-shop.seeded', '1');
    }
  }, [portKey, seed]);
  await page.goto(url);
  await page.locator('.growth-port').waitFor();
  await page.waitForTimeout(1500); // the fixed test commander opens a fresh exercise in the background
  await page.screenshot({ path: root + 'mother-port.png' });

  await openShop();
  const cards = page.locator('.ai-shop-card');
  assert.equal(await cards.count(), 3, 'the evolved AI shop lists three profiles');
  const screenCard = page.locator('[data-ai-profile="evo-screen"]');
  const torpedoCard = page.locator('[data-ai-profile="evo-torpedo"]');
  const gunneryCard = page.locator('[data-ai-profile="evo-gunnery"]');
  assert.equal(await screenCard.getAttribute('data-unlocked'), 'true');
  assert.equal(await screenCard.getAttribute('data-owned'), 'false');
  assert.match(await screenCard.innerText(), /帷幄 · 屏护协同/);
  assert.match(await screenCard.innerText(), /800 常驻征募券/);
  assert.match(await screenCard.innerText(), /暂定强度/);
  assert.equal(await gunneryCard.getAttribute('data-unlocked'), 'false');
  assert.equal(await gunneryCard.locator('button').isDisabled(), true);
  assert.match(await gunneryCard.innerText(), /通关「奥古斯塔皇后湾」/);
  console.log('shop cards', await cards.count(), 'gunnery locked');

  await page.setViewportSize({ width: 740, height: 360 });
  await page.waitForTimeout(150);
  const shopOverflow = await page.evaluate(() =>
    document.documentElement.scrollWidth > window.innerWidth || document.body.scrollWidth > window.innerWidth);
  assert.equal(shopOverflow, false, 'the 740x360 AI shop must not scroll horizontally');
  await page.screenshot({ path: root + 'ai-shop-740.png' });
  await page.setViewportSize({ width: 1360, height: 768 });

  await screenCard.locator('button').click();
  await page.locator('[data-ai-shop-notice]').waitFor();
  assert.equal(await screenCard.getAttribute('data-owned'), 'true');
  let port = await readPort();
  assert.equal(port.wallet.standard, 4200, 'the 800-ticket price is deducted once');
  assert.ok(port.profiles.includes('evo-screen'));

  await page.reload();
  await page.locator('.growth-port').waitFor();
  await page.waitForTimeout(800);
  port = await readPort();
  assert.equal(port.wallet.standard, 4200, 'the ticket balance survives a reload');
  assert.equal(port.profiles.filter(id => id === 'evo-screen').length, 1, 'no duplicate profile purchase');

  // Clearing the third campaign unlocks the gunnery profile; the torpedo
  // profile stays purchasable but unowned so the battle dropdown can show a
  // disabled option with its reason.
  port.campaignProgress['CAMP-ALLIES-11'] = { best: { story: 2 }, claimed: 2 };
  await writePort(port);
  await page.reload();
  await page.locator('.growth-port').waitFor();
  await page.waitForTimeout(800);
  await openShop();
  assert.equal(await gunneryCard.getAttribute('data-unlocked'), 'true');
  assert.equal(await gunneryCard.locator('button').isDisabled(), false);
  assert.equal(await torpedoCard.getAttribute('data-owned'), 'false');
  await gunneryCard.locator('button').click();
  await page.locator('[data-ai-shop-notice]').waitFor();
  port = await readPort();
  assert.equal(port.wallet.standard, 3200, 'two purchases cost 800 + 1000 tickets');
  assert.deepEqual(port.profiles.filter(id => id.startsWith('evo-')), ['evo-screen', 'evo-gunnery']);
  await page.screenshot({ path: root + 'ai-shop-owned.png' });

  await page.getByRole('button', { name: '返回母港', exact: true }).click();
  await page.locator('.growth-port').waitFor();
  await openHarbor('fleet');
  await page.getByLabel('协助风格').selectOption('evo-screen');
  const launch = page.getByRole('button', { name: '用预设出航', exact: true });
  await page.waitForFunction(() => {
    const button = [...document.querySelectorAll('button')].find(el => el.textContent?.trim() === '用预设出航');
    return button && !button.disabled;
  });
  await launch.click();
  await page.locator('.battle-map').waitFor();
  await page.locator('[data-guide-control="ai-tab"]').click();
  await page.locator('.ai-panel').waitFor();
  const ownStyle = page.getByLabel('AI 风格');
  assert.equal(await ownStyle.inputValue(), 'evo-screen');
  assert.match(await page.locator('.ai-panel').innerText(), /屏护协同/);
  const options = await ownStyle.locator('option').evaluateAll(list => list.map(option => ({
    value: option.value, disabled: option.disabled, text: option.textContent ?? '' })));
  assert.equal(options.find(option => option.value === 'evo-screen')?.disabled, false);
  assert.equal(options.find(option => option.value === 'evo-gunnery')?.disabled, false);
  assert.equal(options.find(option => option.value === 'evo-torpedo')?.disabled, true);
  assert.match(options.find(option => option.value === 'evo-torpedo')?.text ?? '', /未拥有/);
  await page.screenshot({ path: root + 'battle-ai-profile.png' });

  const save = await page.evaluate(key => JSON.parse(localStorage.getItem(key) || 'null'), saveKey);
  assert.equal(save?.profile, 'evo-screen', 'the evolved profile is written into the local session save');
  await page.reload();
  await page.locator('.growth-port').waitFor();
  await page.getByRole('button', { name: '打开主菜单' }).click();
  await page.getByRole('button', { name: '继续演习', exact: true }).click();
  await page.locator('.battle-map').waitFor();
  await page.locator('[data-guide-control="ai-tab"]').click();
  assert.equal(await page.getByLabel('AI 风格').inputValue(), 'evo-screen', 'reloading the session keeps the evolved profile');
  await page.screenshot({ path: root + 'battle-ai-profile-reload.png' });

  // new_campaign: the same evolved profile must pass through the campaign
  // launch path (CampaignLaunch.profile -> new_campaign), not just the
  // standalone exercise path.
  await page.getByRole('button', { name: '母港', exact: true }).click();
  await page.locator('.growth-port').waitFor();
  await page.locator('.growth-campaign-entry').click();
  await page.locator('.campaign-lobby').waitFor();
  await page.getByRole('button', { name: '同盟战线', exact: true }).click();
  const esperance = page.locator('.cl-row').filter({ hasText: '埃斯佩兰斯角' }).first();
  await esperance.waitFor();
  await esperance.click();
  await page.getByRole('button', { name: '编成出击', exact: true }).click();
  await page.locator('.deployment-screen').waitFor();
  await page.locator('.dep-slot').first().waitFor();
  await page.getByLabel('战术风格').selectOption('evo-gunnery');
  await page.getByRole('button', { name: '出航作战', exact: true }).click();
  await page.locator('.battle-map').waitFor();
  await page.locator('[data-guide-control="ai-tab"]').click();
  assert.equal(await page.getByLabel('AI 风格').inputValue(), 'evo-gunnery');
  const campaign = await q('observe');
  assert.equal(campaign.campaign.stageId, 'CAMP-ALLIES-02');
  const campaignSave = await page.evaluate(key => JSON.parse(localStorage.getItem(key) || 'null'), saveKey);
  assert.equal(campaignSave?.profile, 'evo-gunnery', 'new_campaign carries the evolved profile into the save');
  await page.screenshot({ path: root + 'campaign-ai-profile.png' });
  await page.reload();
  await page.locator('.growth-port').waitFor();
  await page.getByRole('button', { name: '打开主菜单' }).click();
  await page.getByRole('button', { name: '继续演习', exact: true }).click();
  await page.locator('.battle-map').waitFor();
  await page.locator('[data-guide-control="ai-tab"]').click();
  assert.equal(await page.getByLabel('AI 风格').inputValue(), 'evo-gunnery',
    'reloading the campaign save keeps the evolved profile');

  // Finish the set: buy the torpedo profile after its disabled-option check
  // and fly one exercise with it, so all three bought profiles are exercised.
  await page.getByRole('button', { name: '母港', exact: true }).click();
  await page.locator('.growth-port').waitFor();
  await openShop();
  await page.locator('[data-ai-profile="evo-torpedo"] button').click();
  await page.locator('[data-ai-shop-notice]').waitFor();
  port = await readPort();
  assert.equal(port.wallet.standard, 2300);
  assert.deepEqual(port.profiles.filter(id => id.startsWith('evo-')),
    ['evo-screen', 'evo-gunnery', 'evo-torpedo']);
  await page.getByRole('button', { name: '返回母港', exact: true }).click();
  await page.locator('.growth-port').waitFor();
  await openHarbor('fleet');
  await page.getByLabel('协助风格').selectOption('evo-torpedo');
  await page.waitForFunction(() => {
    const button = [...document.querySelectorAll('button')].find(el => el.textContent?.trim() === '用预设出航');
    return button && !button.disabled;
  });
  await page.getByRole('button', { name: '用预设出航', exact: true }).click();
  await page.locator('.battle-map').waitFor();
  await page.locator('[data-guide-control="ai-tab"]').click();
  assert.equal(await page.getByLabel('AI 风格').inputValue(), 'evo-torpedo');
  await page.screenshot({ path: root + 'battle-ai-torpedo.png' });

  assert.deepEqual(errors, []);
  await fs.writeFile(root + 'browser-receipt.json', JSON.stringify({
    ok: true,
    storefront: { profiles: 3, prices: { 'evo-screen': 800, 'evo-torpedo': 900, 'evo-gunnery': 1000 },
      currency: 'recruit_ticket', provisional: true },
    unlockedByCampaign: ['CAMP-ALLIES-02', 'CAMP-ALLIES-03', 'CAMP-ALLIES-11'],
    purchased: ['evo-screen', 'evo-gunnery', 'evo-torpedo'],
    wallet: { before: 5000, after: 2300 },
    unownedOptionDisabledBeforePurchase: 'evo-torpedo',
    battleProfiles: { exercise: 'evo-screen', campaign: 'evo-gunnery', torpedoExercise: 'evo-torpedo' },
    saveReload: { exercise: 'evo-screen', campaign: 'evo-gunnery' },
    campaign: { stageId: campaign.campaign.stageId, profile: 'evo-gunnery', saveReload: 'evo-gunnery' },
    overflow740: shopOverflow,
  }, null, 2));
  console.log('browser ai shop ok', { wallet: port.wallet.standard, profiles: port.profiles });
} finally {
  await browser.close();
}
