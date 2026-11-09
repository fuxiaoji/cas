import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs/promises';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const root = process.env.CAS_ARTIFACTS || 'artifacts/client/shop/';
const url = process.env.CAS_TEST_URL || 'http://127.0.0.1:5175/';
const portKey = 'cas.profile.test-commander.cas.harbor.progress.v1';
if (!root.endsWith('/')) throw new Error('CAS_ARTIFACTS must end with a slash');
await fs.mkdir(root, { recursive: true });

const now = Date.now();
const week = {
  '11111111-1111-4111-8111-111111111111': { time: now - 5000, first: true, claimed: true },
  '22222222-2222-4222-8222-222222222222': { time: now - 4000, first: false, claimed: false },
  '33333333-3333-4333-8333-333333333333': { time: now - 3000, first: false, claimed: false },
};
const seed = {
  version: 1,
  lessons: ['lead', 'follow', 'sync', 'gun', 'cancel', 'torpedo', 'override'],
  starter: true, challengeClear: true, challengeClaim: false,
  wallet: { standard: 5000, up: 10 }, marks: 20, pity: { standard: 0, up: 0 },
  owned: { fletcher: 4, cleveland: 1 }, profiles: ['coord'],
  preset: { side: 'allies', leaderSlot: 0, profile: 'coord' },
  upSide: 'axis', sequence: 0, history: [], credits: 5000, courses: [], attendance: [],
  challengeReceipts: week, mail: [],
  campaignProgress: {
    'CAMP-ALLIES-02': { best: { story: 2 }, claimed: 2 },
    'CAMP-ALLIES-03': { best: { story: 2 }, claimed: 2 },
    'CAMP-ALLIES-05': { best: { story: 2 }, claimed: 2 },
    'CAMP-ALLIES-06': { best: { story: 2 }, claimed: 2 },
    'CAMP-ALLIES-10': { best: { story: 2 }, claimed: 2 },
    'CAMP-ALLIES-11': { best: { story: 2 }, claimed: 2 },
  },
};

const errors = [];
const browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });
const page = await (await browser.newContext({ viewport: { width: 1360, height: 768 }, locale: 'zh-CN' })).newPage();
page.on('pageerror', error => errors.push(error.stack));
const readPort = () => page.evaluate(key => JSON.parse(localStorage.getItem(key) || 'null'), portKey);

async function openQuartermaster() {
  await page.locator('.growth-port').waitFor();
  await page.locator('.growth-dock button[data-guide="economy"]').click();
  await page.locator('.quartermaster').waitFor();
}
async function counter(name) {
  await page.getByRole('button', { name, exact: true }).click();
}
const overflow = () => page.evaluate(() =>
  document.documentElement.scrollWidth > window.innerWidth || document.body.scrollWidth > window.innerWidth);

try {
  await page.addInitScript(([key, value]) => {
    if (!localStorage.getItem('cas.shop.seeded')) {
      localStorage.setItem(key, JSON.stringify(value));
      localStorage.setItem('cas.shop.seeded', '1');
    }
  }, [portKey, seed]);
  await page.goto(url);
  await page.locator('.growth-port').waitFor();
  await page.waitForTimeout(800);

  await openQuartermaster();
  assert.equal((await page.locator('.harbor-head h1').innerText()).trim(), '军需处');
  assert.equal((await page.locator('.qm-title h2').innerText()).trim(), '干船坞账本');
  assert.equal(await page.locator('.qm-counter').count(), 4, 'the quartermaster has four counters');
  console.log('wallet', await page.locator('.qm-wallet').innerText());
  assert.match(await page.locator('[data-wallet-item="credits"]').innerText(), /5,000/);
  assert.match(await page.locator('[data-wallet-item="marks"]').innerText(), /20/);
  assert.match(await page.locator('[data-wallet-item="standard"]').innerText(), /5,000/);
  await page.screenshot({ path: root + 'quartermaster-1360.png' });

  // 1. 舰船柜台: recruit entry plus the four local hulls, no gacha in the shop.
  await counter('舰船');
  await page.locator('[data-quartermaster-shelf="ships"]').waitFor();
  assert.equal(await page.locator('[data-quartermaster-grid="ships"] .cas-card').count(), 5);
  assert.match(await page.locator('[data-quartermaster-shelf="ships"]').innerText(), /已拥有 5 艘（2 \/ 4 舰型）/);
  assert.ok(await page.getByRole('button', { name: '进入军港征募', exact: true }).count() >= 1);
  await page.screenshot({ path: root + 'quartermaster-ships.png' });

  // 2. 补给配给: weekly ticket and weekly supply use the existing reducers.
  await counter('补给配给');
  await page.locator('[data-quartermaster-shelf="supply"]').waitFor();
  assert.equal(await page.locator('[data-quartermaster-grid="supply"] .cas-card').count(), 3);
  let port = await readPort();
  assert.equal(port.credits, 5000);
  assert.equal(port.wallet.standard, 5000);
  const ticketCard = page.locator('[data-item="weekly-ticket"]');
  await ticketCard.locator('button', { hasText: '兑换常驻券' }).click();
  await page.locator('[data-qm-notice]').waitFor();
  port = await readPort();
  assert.equal(port.credits, 4500, 'weekly ticket costs 500 credits');
  assert.equal(port.wallet.standard, 5001, 'weekly ticket adds one standard ticket');
  assert.match(await ticketCard.innerText(), /本周已兑换/);
  await page.screenshot({ path: root + 'quartermaster-supply.png' });

  const supplyCard = page.locator('[data-item="weekly-supply"]');
  assert.equal(await supplyCard.locator('button').isDisabled(), false, '3 weekly clears unlock the supply claim');
  await supplyCard.locator('button', { hasText: '领取实战补给' }).click();
  await page.locator('[data-qm-notice]').waitFor();
  port = await readPort();
  assert.equal(port.credits, 5000, 'weekly supply refunds 500 credits');
  assert.equal(port.wallet.standard, 5004, 'weekly supply adds three standard tickets');

  // 3. AI 战术: read the live AI_SHOP projection; 3 today, 6 once the other
  // agent lands the expanded doctrine set.
  await counter('AI 战术');
  await page.locator('.ai-shop-grid').waitFor();
  const cards = page.locator('.ai-shop-card');
  const cardCount = await cards.count();
  const declared = Number(await page.locator('.ai-shop-grid').getAttribute('data-ai-count'));
  assert.equal(cardCount, declared, 'rendered AI cards match the shop projection');
  assert.ok(cardCount === 3 || cardCount === 6, `AI shop should be 3 or 6 cards, got ${cardCount}`);
  console.log('AI doctrine cards', cardCount);
  for (let index = 0; index < cardCount; index += 1) {
    const card = cards.nth(index);
    assert.match(await card.innerText(), /常驻征募券/);
    assert.match(await card.innerText(), /解锁/);
    assert.match(await card.innerText(), /暂定强度/);
    const axes = card.locator('[data-axes]');
    if (await axes.count()) {
      const hasAxes = await axes.first().getAttribute('data-axes');
      if (hasAxes === 'true') assert.equal(await card.locator('[data-axis]').count(), 3);
    }
    const role = await card.getAttribute('data-role');
    if (role) assert.equal(await card.locator('.ai-role').count(), 1);
  }
  await page.screenshot({ path: root + 'quartermaster-ai.png' });

  const buyable = page.locator('.ai-shop-card[data-unlocked="true"][data-owned="false"]').first();
  assert.ok(await buyable.count(), 'at least one unlocked AI card is purchasable');
  const buyText = await buyable.innerText();
  const price = Number(/^([0-9]+) 常驻征募券/m.exec(buyText)?.[1]);
  assert.ok(price > 0, 'AI card publishes its ticket price');
  const beforeStandard = (await readPort()).wallet.standard;
  const purchasedId = await buyable.getAttribute('data-ai-profile');
  await buyable.locator('button').click();
  await page.locator('[data-ai-shop-notice]').waitFor();
  const purchasedCard = page.locator(`[data-ai-profile="${purchasedId}"]`);
  assert.equal(await purchasedCard.getAttribute('data-owned'), 'true');
  port = await readPort();
  assert.equal(port.wallet.standard, beforeStandard - price, 'AI purchase deducts the published ticket price once');
  assert.equal(port.profiles.filter(id => id === purchasedId).length, 1,
    'the purchased profile is stored once');
  await page.screenshot({ path: root + 'quartermaster-ai-owned.png' });

  // 4. 礼包与兑换: keep the existing six-medal gunnery exchange.
  await counter('礼包与兑换');
  await page.locator('[data-quartermaster-grid="exchange"]').waitFor();
  assert.equal(await page.locator('[data-quartermaster-grid="exchange"] .cas-card').count(), 4);
  port = await readPort();
  assert.equal(port.marks, 20);
  await page.locator('[data-item="gunnery"] button', { hasText: '6 勋章兑换' }).click();
  await page.locator('[data-qm-notice]').waitFor();
  port = await readPort();
  assert.equal(port.marks, 14, 'gunnery costs six fleet medals');
  assert.ok(port.profiles.includes('gunnery'));
  assert.match(await page.locator('[data-item="gunnery"]').innerText(), /已拥有/);
  await page.screenshot({ path: root + 'quartermaster-exchange.png' });

  await page.setViewportSize({ width: 1024, height: 600 });
  await page.waitForTimeout(150);
  assert.equal(await overflow(), false, 'quartermaster must not scroll horizontally at 1024x600');
  await page.screenshot({ path: root + 'quartermaster-1024.png' });
  await page.setViewportSize({ width: 1360, height: 768 });

  // 740x360: horizontal counters, a single card column and the fixed buy bar.
  await page.setViewportSize({ width: 740, height: 360 });
  await page.waitForTimeout(200);
  await counter('AI 战术');
  await page.locator('.ai-shop-grid').waitFor();
  assert.equal(await overflow(), false, 'quartermaster must not scroll horizontally at 740x360');
  assert.equal(await page.locator('.qm-buybar').isVisible(), true, 'the buy bar stays visible at 740x360');
  const boxes = await page.locator('.qm-counter').evaluateAll(nodes => nodes.map(node => {
    const box = node.getBoundingClientRect();
    return { x: Math.round(box.x), y: Math.round(box.y), width: Math.round(box.width) };
  }));
  assert.ok(boxes.every(box => box.y === boxes[0].y), 'the four counters sit in one horizontal row');
  await page.screenshot({ path: root + 'quartermaster-740.png' });
  await page.locator('.qm-order-toggle').click();
  const order = page.locator('[data-drawer="quartermaster-order"]');
  await order.waitFor();
  const orderBox = await order.locator('.cas-drawer').boundingBox();
  assert.ok(orderBox && orderBox.width >= 700, 'the purchase order opens as a bottom sheet');
  await page.screenshot({ path: root + 'quartermaster-740-order.png' });
  await page.keyboard.press('Escape');
  await order.waitFor({ state: 'detached' });
  await page.setViewportSize({ width: 1360, height: 768 });

  // Reload: purchases and weekly flags persist in the local account save.
  await page.reload();
  await page.waitForTimeout(600);
  await openQuartermaster();
  port = await readPort();
  assert.equal(port.wallet.standard, beforeStandard - price, 'ticket balance survives the reload');
  assert.ok(port.profiles.includes('gunnery'));
  assert.ok(port.profiles.some(id => id.startsWith('evo-')));
  assert.equal(port.marks, 14);
  await counter('AI 战术');
  await page.locator('.ai-shop-grid').waitFor();
  assert.ok((await page.locator('.ai-shop-card[data-owned="true"]').count()) >= 1);

  // Insufficient-ticket state: keep the same unlocked cards but empty the
  // standard-ticket purse; the button must say 常驻券不足 and stay disabled.
  const insufficient = { ...port, wallet: { ...port.wallet, standard: 0 } };
  await page.evaluate(([key, value]) => localStorage.setItem(key, JSON.stringify(value)), [portKey, insufficient]);
  await page.reload();
  await page.waitForTimeout(600);
  await openQuartermaster();
  await counter('AI 战术');
  await page.locator('.ai-shop-grid').waitFor();
  const short = page.locator('.ai-shop-card[data-unlocked="true"][data-owned="false"]').first();
  assert.ok(await short.count(), 'an unlocked but unpurchased card remains for the insufficient check');
  assert.match(await short.innerText(), /券不足/);
  assert.equal(await short.locator('button').isDisabled(), true);
  assert.match(await short.locator('button').innerText(), /常驻券不足/);
  await page.screenshot({ path: root + 'quartermaster-ai-insufficient.png' });

  assert.deepEqual(errors, []);
  await fs.writeFile(root + 'browser-receipt.json', JSON.stringify({
    ok: true,
    counters: 4,
    aiCards: cardCount,
    aiCardStatus: cardCount === 6 ? 'six doctrine cards' : 'three current cards; new doctrine set not landed yet',
    purchasedAi: await page.locator('.ai-shop-card[data-owned="true"]').first().getAttribute('data-ai-profile'),
    gunnery: port.profiles.includes('gunnery'),
    wallet: port.wallet,
    marks: port.marks,
    weeklyTicket: true,
    weeklySupply: true,
    insufficientTickets: true,
    overflow1024: false,
    overflow740: false,
  }, null, 2));
  console.log('browser shop ok', { aiCards: cardCount, wallet: port.wallet, marks: port.marks });
} finally {
  await browser.close();
}
