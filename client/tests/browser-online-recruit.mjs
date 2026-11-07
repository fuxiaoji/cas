import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const ui = new URL(process.env.CAS_TEST_URL || 'http://127.0.0.1:5175/');
const api = new URL(process.env.CAS_ONLINE_TEST_API || 'http://127.0.0.1:8021/');
const API_HREF = api.href;
const loopback = new Set(['127.0.0.1', 'localhost', '[::1]']);
for (const url of [ui, api]) assert(loopback.has(url.hostname), 'Online recruit smoke only accepts loopback URLs.');
assert(process.env.CAS_ONLINE_TEST_DB, 'Set CAS_ONLINE_TEST_DB to the isolated QA database used by the local service.');
const db = await fs.realpath(process.env.CAS_ONLINE_TEST_DB);
const dbRelative = path.relative(await fs.realpath(path.join(root, 'artifacts')), db);
assert(!path.isAbsolute(dbRelative) && !dbRelative.startsWith('..') && /qa.*\.sqlite3$/i.test(path.basename(db)),
  'Only an explicit QA database under this workspace artifacts directory may receive fixture mail.');

const { chromium } = createRequire(import.meta.url)(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const out = process.env.CAS_ARTIFACTS || path.join(root, 'artifacts/client/online-recruit');
const health = await (await fetch(new URL('/health', api))).json();
assert.equal(health.real_payments, false);
await fs.mkdir(out, { recursive: true });
const browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });
const username = 'cas-recruit-qa-' + randomUUID().slice(0, 12);
const password = randomUUID();
const mailId = 'recruit-smoke-tickets';
const mailTitle = '征募验收券包';
// 105 standard tickets fund one ten-draw, the duplicate-request single, the
// short-screen single and eight API ten-draws that unlock one exchange; 13 UP
// tickets fund the banner single. Final balance: 13 standard, 12 UP.
const attachments = { standard_tickets: 105, up_tickets: 13 };
const failures = [];
const receipt = { themeArt: false, probabilityPage: false, tenDraw: false, skipAnimation: false,
  reviewArrival: false, poolSwitch: false, shipReveal: false, duplicateRequest: null, reloadRestores: false,
  exchange: null, shortScreen: false, reloginBalance: false, walletChecks: [] };
let token = '';

try {
  const context = await browser.newContext({ viewport: { width: 1360, height: 768 } });
  const page = await context.newPage();
  page.setDefaultTimeout(15_000);
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
    assert(await response.ok(), label + ' returned HTTP ' + await response.status() + ': ' + (body?.detail ?? ''));
    return body;
  }
  async function login(register, scope = page) {
    await button('切换联机内测账号', scope).click();
    if (register) await button('新用户，创建账号', scope).click();
    await scope.getByLabel('用户名', { exact: true }).fill(username);
    await scope.getByLabel('密码', { exact: true }).fill(password);
    const done = reply('POST', register ? '/auth/register' : '/auth/login', scope);
    await button(register ? '注册并进入母港' : '登录并进入母港', scope).click();
    const auth = await answer(await done, register ? 'Register' : 'Login');
    token = auth.token;
    await scope.locator('.growth-port').waitFor();
    return auth;
  }
  async function supply(scope = page) {
    await scope.locator('[data-guide=economy]').click();
    const desk = scope.locator('.online-supply');
    await desk.locator('.online-wallet').waitFor();
    return desk;
  }
  async function wallet(supplies, expected, label) {
    const value = supplies.locator('.online-wallet');
    for (const [name, amount] of [['补给币', expected.credits], ['常驻券', expected.standard_tickets], ['UP 券', expected.up_tickets]]) {
      await value.locator('span').filter({ hasText: new RegExp('^' + name + '\\s+' + amount + '$') }).waitFor();
    }
    receipt.walletChecks.push({ at: label, credits: expected.credits, standard: expected.standard_tickets, up: expected.up_tickets });
  }
  const serverWallet = scope => scope.evaluate(async ({ bearer, apiHref }) =>
    (await (await fetch(new URL('/me', apiHref).href, { headers: { Authorization: 'Bearer ' + bearer } })).json()).meta.wallet,
    { bearer: token, apiHref: API_HREF });
  async function reconcile(supplies, label) {
    await wallet(supplies, await serverWallet(page), label);
  }
  const phase = wanted => page.waitForFunction(want =>
    document.querySelector('.online-recruit-arrival')?.dataset.phase === want, wanted);
  async function closeArrival(supplies) {
    await button('关闭到港清册').click();
    await page.locator('.online-recruit-arrival').waitFor({ state: 'detached' });
    await reconcile(supplies, 'arrival-closed');
  }

  await page.goto(ui.href);
  const auth = await login(true);
  execFileSync(process.env.CAS_ONLINE_TEST_PYTHON || 'python', ['-c', [
    'import json, sys',
    'from server.accounts import AccountService',
    '_, db, account, mid, title, attachment_json = sys.argv',
    'AccountService(db).deliver_mail(account, mid, title=title, body="Recruit QA fixture", attachments=json.loads(attachment_json))'
  ].join('\n'), db, auth.account_id, mailId, mailTitle, JSON.stringify(attachments)], { cwd: root });

  // Claim the fixture mail through the real UI so the tickets reach the wallet.
  let supplies = await supply();
  await button('邮箱', supplies).click();
  const letter = supplies.locator('article').filter({ has: page.getByRole('heading', { name: mailTitle, exact: true }) });
  await letter.waitFor();
  const claim = reply('POST', '/mail/' + mailId + '/claim');
  await button('领取附件', letter).click();
  const claimed = await answer(await claim, 'Mail claim');
  assert.deepEqual(claimed.mail.attachments, attachments);
  await button('征募', supplies).click();

  // Theme art, pity meters and the probability page.
  const stage = supplies.locator('.online-recruit-stage');
  const feature = stage.locator('.online-recruit-feature');
  await feature.waitFor();
  assert(/data:image|assets\/.*\.webp$/.test(await feature.getAttribute('src')));
  await stage.locator('.online-recruit-meters b').first().waitFor();
  const rules = supplies.locator('details').filter({ hasText: '概率与保证规则' });
  await rules.locator('summary').click();
  assert(await rules.locator('table tbody tr').count() >= 10);
  assert.match(await rules.innerText(), /抽保证/);
  receipt.themeArt = true;
  receipt.probabilityPage = true;
  await reconcile(supplies, 'initial');

  // Ten-draw with the skip button straight to the arrival report.
  const ten = reply('POST', '/recruit');
  await button('征募 10 次', supplies).click();
  const tenBody = await answer(await ten, 'Ten draw');
  assert.equal(tenBody.receipts.length, 10);
  await page.locator('dialog.online-recruit-arrival').waitFor();
  await button('跳过动画').click();
  await phase('report');
  assert.equal(await page.locator('[aria-label="本次到港清册"] > li').count(), 10);
  receipt.tenDraw = true;
  receipt.skipAnimation = true;
  await closeArrival(supplies);

  // Review replays the last batch without another charge.
  await button('查看上次到港', supplies).click();
  await page.locator('dialog.online-recruit-arrival').waitFor();
  await phase('report');
  assert.equal(await page.locator('[aria-label="本次到港清册"] > li').count(), 10);
  receipt.reviewArrival = true;
  await closeArrival(supplies);

  // Switch to the UP pool and walk the ship-by-ship reveal to the report.
  await page.locator('.online-recruit-tabs button[aria-label^="密苏里"]').click();
  await page.locator('.cas-online-recruit.is-up').waitFor();
  const upDraw = reply('POST', '/recruit');
  await button('征募 1 次', supplies).click();
  const upBody = await answer(await upDraw, 'UP draw');
  assert.equal(upBody.receipts[0] ? upBody.receipts.length : 0, 1);
  await page.locator('dialog.online-recruit-arrival').waitFor();
  await phase('ship');
  assert.match(await page.locator('dialog.online-recruit-arrival h2').innerText(), /舰船到港/);
  receipt.poolSwitch = true;
  receipt.shipReveal = true;
  await button('查看到港清册').click();
  await closeArrival(supplies);

  // Replaying one request id must neither re-draw nor re-charge.
  await page.locator('.online-recruit-tabs button[aria-label^="常驻"]').click();
  const single = reply('POST', '/recruit');
  await button('征募 1 次', supplies).click();
  const drawn = await answer(await single, 'Single draw');
  const body = (await single).request().postDataJSON();
  const beforeWallet = await serverWallet(page);
  const replay = await page.evaluate(async ({ body, bearer, apiHref }) => {
    const again = await fetch(new URL('/recruit', apiHref).href, {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + bearer },
      body: JSON.stringify(body) });
    return { status: again.status, json: await again.json() };
  }, { body, bearer: token, apiHref: API_HREF });
  assert.equal(replay.status, 200);
  assert.deepEqual(replay.json.receipts, drawn.receipts);
  const clash = await page.evaluate(async ({ body, bearer, apiHref }) => (await fetch(new URL('/recruit', apiHref).href, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + bearer },
    body: JSON.stringify({ ...body, count: 10 }) })).status, { body, bearer: token, apiHref: API_HREF });
  assert.equal(clash, 409);
  assert.deepEqual(await serverWallet(page), beforeWallet);
  receipt.duplicateRequest = { receiptsStable: true, walletUnchanged: true, conflictingPayload: 409 };
  await reconcile(supplies, 'duplicate-request');

  // Reload restores wallet and draw history after re-authentication.
  await page.reload();
  await login(false);
  supplies = await supply();
  const records = supplies.locator('details').filter({ hasText: '征募记录' });
  await records.locator('summary').click();
  assert.match(await records.locator('summary').innerText(), /征募记录（11 次）/);
  receipt.reloadRestores = true;
  await reconcile(supplies, 'after-reload');

  // Eight server ten-draws accumulate the 80-point exchange, then exchange one UR.
  await page.evaluate(async ({ bearer, apiHref }) => {
    for (let index = 0; index < 8; index += 1) {
      const answer = await fetch(new URL('/recruit', apiHref).href, {
        method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + bearer },
        body: JSON.stringify({ pool_id: 'standard-v2', count: 10, request_id: 'recruit-qa-exchange-' + index }) });
      if (!answer.ok) throw new Error('exchange draw ' + index + ' returned HTTP ' + answer.status);
    }
  }, { bearer: token, apiHref: API_HREF });
  await page.reload();
  await login(false);
  supplies = await supply();
  // Pity may already have granted some URs; exchange the first card the account
  // does not own yet.
  const cards = supplies.locator('[aria-label="本池 UR 舰船"] article');
  await cards.first().waitFor();
  const total = await cards.count();
  assert.ok(total >= 2, 'The standard pool lists its UR lineup.');
  let target = null;
  let targetId = '';
  for (let index = 0; index < total; index += 1) {
    const card = cards.nth(index);
    const label = await card.getByRole('button').textContent();
    if (label && !label.startsWith('已拥有')) { target = card; targetId = await card.getAttribute('data-character'); break; }
  }
  assert.ok(target, 'At least one UR is still available for exchange.');
  await target.getByRole('button').click();
  await page.waitForFunction(selector =>
    document.querySelector(selector)?.textContent?.startsWith('已拥有'), `[data-character="${targetId}"] button`);
  const meta = await page.evaluate(async ({ bearer, apiHref }) => (await (await fetch(new URL('/me', apiHref).href,
    { headers: { Authorization: 'Bearer ' + bearer } })).json()).meta, { bearer: token, apiHref: API_HREF });
  assert(meta.owned_ships.includes(targetId));
  assert.equal(meta.pools['standard-v2'].exchange_points, 11);
  for (let index = 0; index < total; index += 1) {
    const card = cards.nth(index);
    if (await card.getAttribute('data-character') !== targetId) {
      assert(await card.getByRole('button').isDisabled(), 'Remaining UR cards cannot be exchanged below the price.');
    }
  }
  receipt.exchange = { shipId: targetId, progressAfter: 11 };
  await reconcile(supplies, 'after-exchange');

  // 740×360 short screen: the desk and arrival stay operable.
  const short = await context.newPage();
  await short.setViewportSize({ width: 740, height: 360 });
  await short.goto(ui.href);
  await login(false, short);
  const shortSupplies = await supply(short);
  await shortSupplies.getByRole('button', { name: '征募 1 次', exact: true }).click();
  const shortDialog = short.locator('dialog.online-recruit-arrival');
  await shortDialog.waitFor();
  await short.screenshot({ path: path.join(out, '740-recruit-arrival.png') });
  await short.getByRole('button', { name: '跳过动画' }).click();
  await short.getByRole('button', { name: '关闭到港清册' }).click();
  await shortDialog.waitFor({ state: 'detached' });
  receipt.shortScreen = true;
  await short.close();

  // Relogin reconciles the wallet with the server state.
  await button('‹ 返回母港', supplies).click();
  await button('打开主菜单').click();
  const logout = reply('POST', '/auth/logout');
  await button('退出登录').click();
  assert.equal((await answer(await logout, 'Logout')).logged_out, true);
  await page.reload();
  await login(false);
  supplies = await supply();
  const final = await serverWallet(page);
  await wallet(supplies, final, 'relogin');
  assert.equal(final.standard_tickets, 13);
  assert.equal(final.up_tickets, 12);
  receipt.reloginBalance = true;
  assert.deepEqual(failures, []);

  await fs.writeFile(path.join(out, 'browser-receipt.json'), JSON.stringify(receipt, null, 2));
  console.log(JSON.stringify(receipt, null, 2));
} finally {
  await browser.close();
}
