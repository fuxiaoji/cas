import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import fs from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const ui = new URL(process.env.CAS_TEST_URL || 'http://127.0.0.1:5175/');
const api = new URL(process.env.CAS_ONLINE_TEST_API || 'http://127.0.0.1:8021/');
const API_HREF = api.href;
const loopback = new Set(['127.0.0.1', 'localhost', '[::1]']);
for (const url of [ui, api]) assert(loopback.has(url.hostname), 'Supply browser smoke only accepts loopback URLs.');
assert(process.env.CAS_ONLINE_TEST_DB, 'Set CAS_ONLINE_TEST_DB to the isolated QA database used by the local service.');
const db = await fs.realpath(process.env.CAS_ONLINE_TEST_DB);
const dbRelative = path.relative(await fs.realpath(path.join(root, 'artifacts')), db);
assert(!path.isAbsolute(dbRelative) && !dbRelative.startsWith('..') && /qa.*\.sqlite3$/i.test(path.basename(db)),
  'Only an explicit QA database under this workspace artifacts directory may back this smoke.');

const { chromium } = createRequire(import.meta.url)(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const out = process.env.CAS_ARTIFACTS || path.join(root, 'artifacts/client/online-supply');
const ledger = JSON.parse(await fs.readFile(path.join(root, 'client/src/assets/portraits/ledger.json'), 'utf8'));
const fletcherAsset = ledger.assets.find(asset => asset.ibs_character_id === 'IBS-U-USN-FLETCHER');
assert(fletcherAsset, 'The portrait ledger must still register the Fletcher asset.');
const health = await (await fetch(new URL('/health', api))).json();
assert.equal(health.real_payments, false);
await fs.mkdir(out, { recursive: true });
const browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });
const screenshot = (page, name) => page.screenshot({ path: path.join(out, name) });
const failures = [];
const username = 'cas-supply-qa-' + randomUUID().slice(0, 12);
const password = randomUUID();
const receipt = { checkIn: null, bundles: null, purchase: null, relogin: null, portrait: null };
let token = '';

try {
  const context = await browser.newContext({ viewport: { width: 1360, height: 768 } });
  const page = await context.newPage();
  page.setDefaultTimeout(20_000);
  page.on('pageerror', error => failures.push(error.message));
  await page.route('**/*', route => route.request().method() === 'POST' &&
    new URL(route.request().url()).origin !== api.origin ? route.abort() : route.continue());
  const button = (name, scope = page) => scope.getByRole('button', { name, exact: true });
  const reply = (method, pathname, scope = page) => scope.waitForResponse(response => {
    const requested = new URL(response.url());
    return requested.origin === api.origin && requested.pathname === pathname && response.request().method() === method;
  });
  async function answer(response, label) {
    const body = await response.json();
    const ok = typeof response.ok === 'function' ? response.ok() : response.ok;
    const status = typeof response.status === 'function' ? response.status() : response.status;
    assert(ok, label + ' returned HTTP ' + status + (typeof body?.detail === 'string' ? ': ' + body.detail : ''));
    return body;
  }
  async function login(register) {
    await button('切换联机内测账号').click();
    if (register) await button('新用户，创建账号').click();
    await page.getByLabel('用户名', { exact: true }).fill(username);
    await page.getByLabel('密码', { exact: true }).fill(password);
    const done = reply('POST', register ? '/auth/register' : '/auth/login');
    await button(register ? '注册并进入母港' : '登录并进入母港').click();
    const auth = await answer(await done, register ? 'Register' : 'Login');
    token = auth.token;
    await page.locator('.growth-port').waitFor();
    return auth;
  }
  const walletKeys = { 补给币: 'credits', 常驻券: 'standard_tickets', 'UP 券': 'up_tickets', 舰队勋章: 'medals' };
  const serverWallet = async () => (await (await fetch(new URL('/me', API_HREF), {
    headers: { Authorization: 'Bearer ' + token } })).json()).meta.wallet;
  async function reconcile(supplies, label) {
    const truth = await serverWallet();
    for (const [name, key] of Object.entries(walletKeys)) {
      const row = supplies.locator('.online-wallet span').filter({ hasText: new RegExp('^' + name + '\\s') }).first();
      await row.waitFor();
      assert.equal(Number((await row.innerText()).replace(/\D/g, '')), truth[key], label + ' wallet ' + name + ' must match /me');
    }
    return truth;
  }

  await page.goto(ui.href);
  const auth = await login(true);
  // The account must exist in the isolated QA database, not in some other store.
  const found = execFileSync(process.env.CAS_ONLINE_TEST_PYTHON || 'python', ['-c', [
    'import sqlite3, sys',
    'db, account = sys.argv[1], sys.argv[2]',
    'conn = sqlite3.connect("file:" + db + "?mode=ro", uri=True)',
    'print(1 if conn.execute("SELECT 1 FROM accounts WHERE id=?", (account,)).fetchone() else 0)'
  ].join('\n'), db, auth.account_id], { cwd: root }).toString().trim();
  assert.equal(found, '1', 'The registered browser account must live in the isolated QA database.');

  // Day 1 of the cloud check-in through the real activity UI.
  const activity = page.locator('.activity-center');
  const checkInRequest = reply('GET', '/missions/check-in');
  await page.getByRole('button', { name: /活动中心/ }).click();
  const firstDay = await answer(await checkInRequest, 'Load cloud check-in');
  assert.equal(firstDay.claimed, 0);
  assert.equal(firstDay.available, true);
  // Day 7 is no longer a preview: the schedule carries the verified North
  // Carolina identity and its registered CAS period-card source.
  const daySeven = firstDay.rewards.at(-1);
  assert.deepEqual(daySeven.ship_ids, ['IBS-U-USN-UNNAMED-T01-R03']);
  assert.match(daySeven.ship_source, /north-carolina/);
  await activity.getByRole('img', { name: '北卡罗来纳立绘' }).waitFor();
  assert.equal(await activity.getByRole('img', { name: '北卡罗来纳立绘' }).getAttribute('data-character'),
    'IBS-U-USN-UNNAMED-T01-R03');
  assert.match(await activity.locator('.activity-day.is-flagship').innerText(), /北卡罗来纳/);
  // The day-7 card is verified now, so the stale preview copy is gone.
  assert.match(await activity.locator('.activity-flagship').innerText(), /舰卡已核验 · 第 7 天入列/);
  assert.doesNotMatch(await activity.innerText(), /尚未就绪|核验完成后开放/);
  const claimRequest = reply('POST', '/missions/check-in/claim');
  await button('领取第 1 天奖励', activity).click();
  const claimed = await answer(await claimRequest, 'Claim cloud check-in');
  assert.equal(claimed.claimed, true);
  assert.equal(claimed.meta.wallet.credits, 500);
  await screenshot(page, '00-check-in-day1.png');
  await button('返回', activity).click();

  // Server-owned funding fixture through the real starter-gift endpoints:
  // 800+600+1000 credits plus the five tutorial hulls (Fletcher carries a
  // ledger portrait and Honolulu later duplicates inside the bundle).
  for (const [index, course] of ['bridge', 'night', 'torpedo'].entries()) {
    const gift = await answer(await fetch(new URL('/starter-gifts/claim', API_HREF), {
      method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
      body: JSON.stringify({ request_id: 'supply-fixture-gift-' + index, course }) }), 'Starter gift ' + course);
    assert.equal(gift.gift_id, 'tutorial-' + course);
    assert.equal(gift.claimed, true);
  }
  const funded = await serverWallet();
  assert.equal(funded.credits, 2900, 'Check-in plus three starter gifts must fund 2900 credits.');

  await page.locator('[data-guide=economy]').click();
  let supplies = page.locator('.online-supply');
  await supplies.locator('.online-wallet').waitFor();
  await button('补给商店', supplies).click();

  // Only the bundles the server catalog actually issues are listed, each
  // fixed at three recruitable hulls with a fixed 补给币 price.
  const catalog = await (await fetch(new URL('/catalog', API_HREF))).json();
  const shelf = supplies.locator('.ship-bundle-shelf');
  await shelf.waitFor();
  assert.equal(await shelf.locator('.ship-bundle').count(), catalog.ship_bundles.length,
    'Shelf must list exactly the catalog bundles.');
  const listed = [];
  for (const bundle of catalog.ship_bundles) {
    const card = shelf.locator('[data-bundle="' + bundle.id + '"]');
    await card.waitFor();
    const ships = await card.locator('.ship-bundle-ships > div strong').allInnerTexts();
    assert.equal(ships.length, 3, bundle.id + ' must show exactly three hulls');
    assert.match(await card.innerText(), new RegExp(bundle.name));
    assert.match(await card.innerText(), new RegExp(bundle.credits.toLocaleString('en-US') + ' 补给币'));
    assert.match(await card.innerText(), /可购买|还差/);
    listed.push({ id: bundle.id, ships: bundle.ship_ids, price: bundle.credits });
  }
  await screenshot(page, '01-bundle-shelf.png');

  // Buy the allied cruiser detachment through the shelf button.
  const purchaseRequest = reply('POST', '/shop/purchase');
  await button('购买同盟巡洋支援包', shelf).click();
  const purchase = await purchaseRequest;
  const body = purchase.request().postDataJSON();
  assert.equal(body.kind, 'ship_bundle');
  assert.equal(body.item_id, 'allied-cruiser-detachment');
  assert.equal(body.currency, 'credits');
  assert.match(body.request_id, /\S/);
  const bought = await answer(purchase, 'Bundle purchase');
  assert.deepEqual(bought.receipts.map(row => row.ship_id),
    ['IBS-U-USN-HONOLULU', 'IBS-U-USN-MINNEAPOLIS', 'IBS-U-USN-SAN-FRANCISCO']);
  assert.deepEqual(bought.receipts.map(row => row.duplicate), [true, false, false]);
  assert.equal(bought.meta.wallet.credits, 1100);
  assert.equal(bought.meta.wallet.medals, 5);  // Honolulu is elite: 5 medals.
  for (const ship of ['IBS-U-USN-MINNEAPOLIS', 'IBS-U-USN-SAN-FRANCISCO']) {
    assert(bought.meta.owned_ships.includes(ship), ship + ' must join the collection');
  }
  receipt.purchase = { bundle: 'allied-cruiser-detachment', creditsSpent: 1800,
    receipts: bought.receipts.map(row => ({ ship: row.ship_id, duplicate: row.duplicate })),
    walletAfter: { credits: bought.meta.wallet.credits, medals: bought.meta.wallet.medals } };
  // The card flips to 已购买 and the receipt list names the duplicate conversion.
  await shelf.locator('[data-bundle="allied-cruiser-detachment"]').getByText('已购买', { exact: true }).waitFor();
  assert(await button('购买同盟巡洋支援包', shelf).isDisabled());
  const receiptList = supplies.locator('[aria-label="征募结果"]');
  assert.match(await receiptList.innerText(), /火奴鲁鲁 · 重复转为勋章/);
  assert.match(await receiptList.innerText(), /明尼阿波里斯 · 入列/);
  assert.match(await receiptList.innerText(), /旧金山 · 入列/);
  const afterBundle = await reconcile(supplies, 'after-bundle');
  assert.equal(afterBundle.credits, 1100);
  await screenshot(page, '02-bundle-purchased.png');

  // Collection tab: the portrait entry appears only for ledger assets.
  await button('舰船收藏', supplies).click();
  const collection = supplies.locator('section').filter({ has: page.getByRole('heading', { name: /联机收藏/ }) });
  const fletcherArticle = collection.locator('article').filter({ has: page.getByRole('heading', { name: '弗莱彻', exact: true }) });
  await fletcherArticle.waitFor();
  assert.match(await fletcherArticle.innerText(), /驱逐舰 · 普通/);
  assert.equal(await collection.getByRole('button', { name: '查看全身立绘', exact: true }).count(), 1,
    'Only Fletcher owns a ledger portrait among these hulls.');
  const perkinsArticle = collection.locator('article').filter({ has: page.getByRole('heading', { name: '帕金斯', exact: true }) });
  await perkinsArticle.waitFor();
  assert.equal(await perkinsArticle.getByRole('button', { name: '查看全身立绘', exact: true }).count(), 0,
    'A ship without a ledger asset must not offer a fake viewer button.');
  await screenshot(page, '03-collection.png');

  // Open the viewer and prove the rendered bytes are the ledger-registered asset.
  const dialog = page.getByRole('dialog', { name: '弗莱彻全身立绘' });
  await button('查看全身立绘', fletcherArticle).click();
  await dialog.waitFor();
  const image = dialog.getByRole('img', { name: '弗莱彻全身立绘' });
  await image.waitFor();
  assert.equal(await image.getAttribute('data-character'), 'IBS-U-USN-FLETCHER');
  assert.match(await dialog.innerText(), /驱逐舰/);
  assert.match(await dialog.innerText(), /弗莱彻/);
  const natural = await image.evaluate(node => ({ width: node.naturalWidth, height: node.naturalHeight,
    src: node.currentSrc, box: { width: node.clientWidth, height: node.clientHeight } }));
  assert(natural.width > 0 && natural.height > 0, 'The portrait image must actually decode.');
  assert.match(natural.src, /fletcher\.png/);
  const served = Buffer.from(await (await fetch(new URL(natural.src, ui))).arrayBuffer());
  const digest = createHash('sha256').update(served).digest('hex');
  assert.equal(digest, fletcherAsset.sha256, 'Viewer must render the ledger-registered asset bytes.');
  assert.equal(await page.evaluate(() => document.querySelector('dialog.online-portrait-dialog')?.open), true);
  assert(natural.box.height > 200, 'Full-body art must fill the dialog height.');
  receipt.portrait = { ship: 'IBS-U-USN-FLETCHER', asset: fletcherAsset.path, sha256: digest,
    natural: { width: natural.width, height: natural.height },
    rendered: { width: natural.box.width, height: natural.box.height }, negativeShip: 'IBS-U-USN-PERKINS' };
  await screenshot(page, '04-portrait-viewer.png');

  // Escape closes the viewer.
  await page.keyboard.press('Escape');
  await dialog.waitFor({ state: 'hidden' });
  // A second open closes with the visible close button.
  await button('查看全身立绘', fletcherArticle).click();
  await dialog.waitFor();
  await button('关闭立绘', dialog).click();
  await dialog.waitFor({ state: 'hidden' });
  // A third open closes by clicking the backdrop outside the art panel.
  await button('查看全身立绘', fletcherArticle).click();
  await dialog.waitFor();
  await page.mouse.click(4, 4);
  await dialog.waitFor({ state: 'hidden' });

  // 740×360 landscape must still fit and show the art.
  await page.setViewportSize({ width: 740, height: 360 });
  await button('查看全身立绘', fletcherArticle).click();
  await dialog.waitFor();
  const box = await dialog.boundingBox();
  assert(box && box.width <= 740 && box.height <= 360, 'Viewer must fit a 740x360 landscape screen.');
  const shortImage = await dialog.getByRole('img').boundingBox();
  assert(shortImage && shortImage.height > 100, 'Short-screen viewer must still show the art.');
  receipt.portrait.shortScreen = { viewport: '740x360',
    dialog: { width: Math.round(box.width), height: Math.round(box.height) },
    image: { width: Math.round(shortImage.width), height: Math.round(shortImage.height) } };
  await screenshot(page, '05-portrait-740x360.png');
  await page.keyboard.press('Escape');
  await dialog.waitFor({ state: 'hidden' });
  await page.setViewportSize({ width: 1360, height: 768 });
  await supplies.locator('.online-wallet').waitFor();

  // Reload and re-login: no second grant and no double charge.
  await page.reload();
  const reauth = await login(false);
  assert.equal(reauth.account_id, auth.account_id);
  await page.locator('[data-guide=economy]').click();
  supplies = page.locator('.online-supply');
  await supplies.locator('.online-wallet').waitFor();
  await button('补给商店', supplies).click();
  const reloadedShelf = supplies.locator('.ship-bundle-shelf');
  await reloadedShelf.locator('[data-bundle="allied-cruiser-detachment"]').getByText('已购买', { exact: true }).waitFor();
  assert(await button('购买同盟巡洋支援包', reloadedShelf).isDisabled());
  const reloaded = await reconcile(supplies, 'after-relogin');
  assert.deepEqual([reloaded.credits, reloaded.medals], [1100, 5]);
  // Another request id cannot re-buy the same bundle on the server either.
  const replay = await fetch(new URL('/shop/purchase', API_HREF), {
    method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ request_id: 'supply-qa-rebuy-' + randomUUID().slice(0, 8),
      kind: 'ship_bundle', item_id: 'allied-cruiser-detachment', currency: 'credits' }) });
  assert.equal(replay.status, 409, 'Server must refuse a second purchase of the same bundle.');
  const afterReplay = await serverWallet();
  assert.deepEqual([afterReplay.credits, afterReplay.medals], [1100, 5]);
  receipt.relogin = { wallet: { credits: afterReplay.credits, medals: afterReplay.medals }, rebuyStatus: replay.status };
  await screenshot(page, '06-relogin-state.png');
  assert.deepEqual(failures, []);

  receipt.checkIn = { daySevenShip: daySeven.ship_ids[0], shipSource: daySeven.ship_source,
    dayOneCredits: claimed.meta.wallet.credits };
  receipt.bundles = listed;
  await fs.writeFile(path.join(out, 'browser-receipt.json'), JSON.stringify(receipt, null, 2));
  console.log(JSON.stringify(receipt, null, 2));
} finally {
  await browser.close();
}
