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
const loopback = new Set(['127.0.0.1', 'localhost', '[::1]']);
for (const url of [ui, api]) assert(loopback.has(url.hostname), 'Online browser smoke only accepts loopback URLs.');
assert(process.env.CAS_ONLINE_TEST_DB, 'Set CAS_ONLINE_TEST_DB to the isolated QA database used by the local service.');
const db = await fs.realpath(process.env.CAS_ONLINE_TEST_DB);
const dbRelative = path.relative(await fs.realpath(path.join(root, 'artifacts')), db);
assert(!path.isAbsolute(dbRelative) && !dbRelative.startsWith('..') && /qa.*\.sqlite3$/i.test(path.basename(db)),
  'Only an explicit QA database under this workspace artifacts directory may receive fixture mail.');

const { chromium } = createRequire(import.meta.url)(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const out = process.env.CAS_ARTIFACTS || path.join(root, 'artifacts/client/online');
const health = await (await fetch(new URL('/health', api))).json();
assert.equal(health.pve_available, true, 'Local account service must have the real native PvE core.');
assert.equal(health.real_payments, false);
await fs.mkdir(out, { recursive: true });
const browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });
const screenshot = (page, name) => page.screenshot({ path: path.join(out, name) });
const username = 'cas-online-qa-' + randomUUID().slice(0, 12);
const password = randomUUID();
const mailId = 'browser-smoke-gift';
const mailTitle = '浏览器验收补给';
const attachments = { standard_tickets: 3, up_tickets: 2 };
const stageId = 'CAMP-ALLIES-03';
const scenarioShips = ['Charles F. Ausburne', 'Claxton', 'Dyson', 'Converse', 'Spence'];
const privateKeys = new Set(['seed', 'snapshot', 'save', 'commands', 'enemy', 'truth']);
function assertProjection(response) {
  assert.equal(response.stage_id, stageId);
  assert.equal(response.view.campaign.stageId, stageId);
  assert.equal(response.view.side, 'allies');
  assert.deepEqual(response.view.ships.map(({ name }) => name).sort(), [...scenarioShips].sort());
  for (const key of [...Object.keys(response), ...Object.keys(response.view)]) assert(!privateKeys.has(key), 'Authority disclosed ' + key);
}

try {
  const page = await browser.newPage({ viewport: { width: 1360, height: 768 } });
  // Never let a local test site's misconfigured build register or write to a deployed service.
  await page.route('**/*', route => route.request().method() === 'POST' &&
    new URL(route.request().url()).origin !== api.origin ? route.abort() : route.continue());
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  const button = (name, scope = page) => scope.getByRole('button', { name, exact: true });
  const reply = (method, pathname) => page.waitForResponse(response => {
    const requested = new URL(response.url());
    return requested.origin === api.origin && requested.pathname === pathname && response.request().method() === method;
  });
  async function answer(response, label) {
    const body = await response.json();
    const ok = typeof response.ok === 'function' ? response.ok() : response.ok;
    const status = typeof response.status === 'function' ? response.status() : response.status;
    assert(ok, label + ' returned HTTP ' + status +
      (typeof body?.detail === 'string' ? ': ' + body.detail : ''));
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
    await page.locator('.growth-port').waitFor();
    return auth;
  }
  async function supply() {
    await page.locator('[data-guide=economy]').click();
    await page.locator('.online-wallet').waitFor();
    return page.locator('.online-supply');
  }
  async function wallet(credits, standard, up) {
    const value = page.locator('.online-wallet');
    for (const [label, amount] of [['补给币', credits], ['常驻券', standard], ['UP 券', up]]) {
      await value.locator('span').filter({ hasText: new RegExp('^' + label + '\\s+' + amount + '$') }).waitFor();
    }
  }

  await page.goto(ui.href);
  const auth = await login(true);
  assert.equal(auth.username, username);
  assert(typeof auth.account_id === 'string' && typeof auth.token === 'string');
  const activity = page.locator('.activity-center');
  const activityButton = page.getByRole('button', { name: /活动中心/ });
  const checkInStart = reply('GET', '/missions/check-in');
  await activityButton.click();
  const firstDay = await answer(await checkInStart, 'Load cloud check-in');
  assert.equal(firstDay.claimed, 0);
  assert.equal(firstDay.available, true);
  assert.equal(firstDay.rewards.length, 7);
  await activity.getByText('联机免费内测', { exact: true }).waitFor();
  const checkInRequest = reply('POST', '/missions/check-in/claim');
  await button('领取第 1 天奖励', activity).click();
  const checkIn = await answer(await checkInRequest, 'Claim cloud check-in');
  assert.equal(checkIn.claimed, true);
  assert.equal(checkIn.check_in.claimed, 1);
  assert.equal(checkIn.meta.wallet.credits, 500);
  assert.equal(checkIn.meta.wallet.standard_tickets, 2);
  assert.deepEqual(checkIn.rewards.map(reward => ({ credits: reward.credits, standard: reward.standard_tickets })), [{ credits: 500, standard: 2 }]);
  await activity.getByRole('status').filter({ hasText: '已领取补给币 ×500、常驻券 ×2。' }).waitFor();
  assert(await button('今日已领取', activity).isDisabled());
  await screenshot(page, '00-cloud-check-in.png');
  await button('返回', activity).click();
  execFileSync(process.env.CAS_ONLINE_TEST_PYTHON || 'python', ['-c', [
    'import json, sys',
    'from server.accounts import AccountService',
    '_, db, account, mid, title, attachment_json = sys.argv',
    'AccountService(db).deliver_mail(account, mid, title=title, body="Browser QA fixture", attachments=json.loads(attachment_json))'
  ].join('\n'), db, auth.account_id, mailId, mailTitle, JSON.stringify(attachments)], { cwd: root });

  const supplies = await supply();
  await wallet(500, 2, 0);
  await button('邮箱', supplies).click();
  const letter = supplies.locator('article').filter({ has: page.getByRole('heading', { name: mailTitle, exact: true }) });
  await letter.waitFor();
  assert.match(await letter.innerText(), /UP 券 2 · 常驻券 3/);
  const mailRequest = reply('POST', '/mail/' + mailId + '/claim');
  await button('领取附件', letter).click();
  const claimed = await answer(await mailRequest, 'Mail claim');
  assert.equal(claimed.mail.id, mailId);
  assert(claimed.mail.claimed_at);
  assert.deepEqual(claimed.mail.attachments, attachments);
  await wallet(500, 5, 2);
  assert(await button('已领取', letter).isDisabled());
  await screenshot(page, '01-mail-claimed.png');

  await button('征募', supplies).click();
  await supplies.getByRole('button', { name: /^常驻 · / }).click();
  const recruitRequest = reply('POST', '/recruit');
  await button('征募 1 次', supplies).click();
  const recruit = await recruitRequest;
  assert.equal(recruit.request().postDataJSON().pool_id, 'standard-v2');
  const drawn = await answer(recruit, 'Recruit');
  assert.equal(drawn.receipts.length, 1);
  assert(drawn.receipts[0].ship_id);
  const recruitResult = supplies.locator('[aria-label="征募结果"]');
  await recruitResult.waitFor();
  assert.match(await recruitResult.innerText(), /入列|重复转为勋章/);
  await wallet(500, 4, 2);
  await screenshot(page, '02-recruit-receipt.png');
  // The restored 0.6.11 arrival dialog is modal; skip the reveal and close it
  // before using other tabs.
  await button('跳过动画', page).click();
  await button('关闭到港清册', page).click();
  await page.locator('.online-recruit-arrival').waitFor({ state: 'detached' });

  // The currency for this purchase comes from the UI check-in above.
  await button('补给商店', supplies).click();
  const purchaseRequest = reply('POST', '/shop/purchase');
  await button('500 补给币兑常驻券', supplies).click();
  const purchase = await purchaseRequest;
  assert.equal(purchase.request().postDataJSON().kind, 'weekly_ticket');
  await answer(purchase, 'Shop redemption');
  await wallet(0, 5, 2);
  await screenshot(page, '03-shop-redeemed.png');

  await button('‹ 返回母港', supplies).click();
  await page.locator('.growth-campaign-entry').click();
  const archive = page.getByRole('region', { name: 'CAS 战役档案' });
  await archive.locator('.archive-list').waitFor();
  await button('同盟战线', archive).click();
  await archive.getByLabel('难度').selectOption('story');
  const stage = archive.locator('[data-stage-id="' + stageId + '"]');
  await stage.locator('summary').first().click();
  const startRequest = reply('POST', '/battles');
  await button('出航作战', stage).click();
  const start = await answer(await startRequest, 'Create authoritative battle');
  assertProjection(start);
  assert.equal(start.difficulty, 'story');
  assert.equal(start.revision, 0);
  assert.equal(start.status, 'active');
  const battle = '/battles/' + encodeURIComponent(start.battle_id);
  await page.getByText('联机时钟 · 4×', { exact: true }).waitFor();
  assert.equal(await button('推进一秒').count(), 0);
  const mission = page.getByRole('region', { name: '战役任务' });
  assert.match(await mission.innerText(), /圣乔治角/);

  await button('战术 AI').click();
  const orderRequest = reply('POST', battle + '/commands');
  await page.getByLabel('指挥权限').selectOption('auto');
  const order = await orderRequest;
  const { command } = order.request().postDataJSON();
  assert.equal(command.op, 'ai');
  assert.equal(command.mode, 'auto');
  const accepted = await answer(order, 'Authoritative AI delegation');
  assertProjection(accepted);
  assert.equal(accepted.revision, 1);
  const delegated = (view) => view.fleets.find(({ id }) => id === command.fleet)?.ai;
  assert.equal(delegated(accepted.view)?.mode, 'auto');
  assert.equal(delegated(accepted.view)?.move, true);
  await page.getByRole('group', { name: '允许 AI 执行' }).waitFor();
  const advanced = await answer(await reply('GET', battle), 'Authority clock');
  assert(advanced.tick >= accepted.tick);
  await screenshot(page, '04-live-delegation.png');

  await button('母港').click();
  await button('打开主菜单').click();
  const logoutRequest = reply('POST', '/auth/logout');
  await button('退出登录').click();
  assert.equal((await answer(await logoutRequest, 'Logout')).logged_out, true);
  await page.reload();
  const reauth = await login(false);
  assert.equal(reauth.account_id, auth.account_id);
  const statusRequest = reply('GET', '/missions/check-in');
  await activityButton.click();
  const afterLogin = await answer(await statusRequest, 'Restore cloud check-in');
  assert.equal(afterLogin.last_day, checkIn.check_in.last_day);
  assert.equal(afterLogin.claimed, 1);
  assert.equal(afterLogin.available, false);
  await button('今日已领取', activity).waitFor();
  assert(await button('今日已领取', activity).isDisabled());
  await button('返回', activity).click();
  const returnedSupply = await supply();
  await wallet(0, 5, 2);
  await button('邮箱', returnedSupply).click();
  assert(await button('已领取', letter).isDisabled());
  await button('‹ 返回母港', returnedSupply).click();

  const listRequest = reply('GET', '/battles');
  await button('打开主菜单').click();
  const list = await answer(await listRequest, 'Account battle list');
  assert.equal(list.length, 1);
  assert.equal(list[0].battle_id, start.battle_id);
  const menu = page.getByRole('dialog', { name: '主菜单' });
  const continued = menu.getByRole('button', { name: /^继续战役 · 同盟 · / });
  await continued.waitFor();
  await screenshot(page, '05-resume-menu.png');
  const resumeRequest = reply('GET', battle);
  await continued.click();
  const restored = await answer(await resumeRequest, 'Resume authoritative battle');
  assertProjection(restored);
  assert.equal(restored.battle_id, start.battle_id);
  assert.equal(restored.revision, accepted.revision);
  assert(restored.tick > accepted.tick, 'Server clock must continue independently of the client.');
  assert.deepEqual(delegated(restored.view), delegated(accepted.view));
  await page.getByText('联机时钟 · 4×', { exact: true }).waitFor();
  await button('战术 AI').click();
  assert.equal(await page.getByLabel('指挥权限').inputValue(), 'auto');
  await screenshot(page, '06-resumed-battle.png');
  assert.deepEqual(errors, []);

  const receipt = {
    checkIn: { rewards: { credits: 500, standard_tickets: 2 }, days: afterLogin.claimed, claimDisabledAfterRelogin: true },
    mail: { attachments, claimPersisted: true },
    recruit: { pool: 'standard-v2', shipId: drawn.receipts[0].ship_id, dedicatedTicketsSpent: 1 },
    shop: { purchase: 'weekly_ticket', creditsSpent: 500,
      walletAfterRelogin: { credits: 0, standard_tickets: 5, up_tickets: 2 } },
    battle: { stageId, difficulty: start.difficulty, acceptedRevision: accepted.revision, resumedRevision: restored.revision,
      acceptedTick: accepted.tick, resumedTick: restored.tick, sameBattle: true, ownSeatOnly: true, delegatedFleet: command.fleet,
      completed: restored.status === 'complete' },
  };
  await fs.writeFile(path.join(out, 'browser-receipt.json'), JSON.stringify(receipt, null, 2));
  console.log(JSON.stringify(receipt, null, 2));
} finally {
  await browser.close();
}
