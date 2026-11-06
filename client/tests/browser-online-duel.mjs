import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const { chromium } = createRequire(import.meta.url)(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const base = process.env.CAS_DUEL_CLIENT_URL || 'http://127.0.0.1:5184';
const browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });
const nonce = Date.now().toString(36);
const failures = [];

async function openAccount(suffix, viewport) {
  const page = await browser.newPage({ viewport });
  page.on('pageerror', error => failures.push(error.message));
  await page.goto(base);
  await page.getByRole('button', { name: '切换联机内测账号' }).click();
  await page.getByRole('button', { name: '新用户，创建账号' }).click();
  await page.getByLabel('用户名').fill(`duel-${nonce}-${suffix}`);
  await page.getByLabel('密码').fill('cas-duel-test-2026');
  await page.getByRole('button', { name: '注册并进入母港' }).click();
  await enterLobby(page);
  return page;
}

async function enterLobby(page) {
  await page.getByRole('button', { name: '打开主菜单' }).click();
  await page.getByRole('button', { name: '线上舰桥', exact: true }).click();
  await page.getByRole('button', { name: '创建约战口令' }).waitFor();
}

try {
  const [first, second] = await Promise.all([
    openAccount('a', { width: 1220, height: 760 }), openAccount('b', { width: 740, height: 360 }),
  ]);
  await first.getByRole('button', { name: '创建约战口令' }).click();
  const invite = first.getByLabel('约战口令');
  await invite.waitFor();
  const code = await invite.textContent();
  assert.match(code, /^invite-[A-Za-z0-9_-]{16}$/);
  await second.getByLabel('好友口令').fill(code);
  await second.getByRole('button', { name: '加入约战' }).click();
  await second.locator('.side-tag').waitFor();
  await first.getByRole('button', { name: /进入对局 · 同盟舰队/ }).click();
  await first.getByText('线上约战进行中').waitFor();
  assert.equal(await first.locator('.side-tag').textContent(), '同盟舰队');
  assert.equal(await second.locator('.side-tag').textContent(), '轴心舰队');
  assert.equal(await first.getByRole('button', { name: '推进一秒' }).count(), 0);
  assert.equal(await second.getByRole('button', { name: '演习设置' }).count(), 0);
  const start = await first.locator('.time strong').textContent();
  await first.waitForFunction(start => document.querySelector('.time strong')?.textContent !== start, start);

  await second.getByRole('button', { name: '线上舰桥', exact: true }).click();
  await second.getByRole('button', { name: /进入对局 · 轴心舰队/ }).click();
  await second.locator('.side-tag').waitFor();
  await second.getByRole('button', { name: '投降', exact: true }).click();
  await second.getByRole('button', { name: '确认投降', exact: true }).click();
  for (const page of [first, second]) {
    await page.getByText('线上约战结束', { exact: true }).waitFor();
    await page.getByText('一方投降', { exact: true }).waitFor();
    await page.getByRole('heading', { name: '同盟舰队胜出' }).waitFor();
    assert.equal(await page.getByRole('button', { name: '领取联机战役奖励' }).count(), 0);
  }
  assert.deepEqual(failures, []);
  console.log('两席实际登录、区分大小写的口令、服务器时钟、短屏重连及双方终局通过。');
} finally { await browser.close(); }
