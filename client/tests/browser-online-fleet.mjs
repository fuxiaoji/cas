import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdir, mkdtemp, realpath, rm } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { createServer as openSocket } from 'node:net';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { setTimeout as wait } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';

const { chromium } = createRequire(import.meta.url)(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const temp = await realpath(tmpdir());
const dir = await mkdtemp(join(temp, 'cas-online-fleet-'));
const root = fileURLToPath(new URL('../', import.meta.url));
const project = fileURLToPath(new URL('../../', import.meta.url));
const loopback = '127.0.0.1';
const socket = openSocket();
await new Promise((resolve, reject) => socket.once('error', reject).listen(0, loopback, resolve));
const port = socket.address().port;
await new Promise(resolve => socket.close(resolve));
const base = `http://${loopback}:${port}`;
const python = process.env.CAS_ONLINE_TEST_PYTHON || 'python';
const env = { ...process.env, CAS_ACCOUNT_DB: join(dir, 'cas.sqlite3'), PYTHONIOENCODING: 'utf-8' };
delete env.CAS_SIM_PATH;
const api = spawn(python, ['-m', 'uvicorn', 'server.accounts:app', '--host', loopback, '--port', String(port), '--log-level', 'warning'],
  { cwd: project, env, windowsHide: true });
let failure = '';
api.on('error', error => { failure += error.message; });
api.stderr.on('data', chunk => { failure += chunk; });
api.stdout.resume();
let vite;
let browser;

async function ask(path, body, token) {
  const response = await fetch(base + path, { method: body ? 'POST' : 'GET',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) },
    body: body ? JSON.stringify(body) : undefined });
  const value = await response.json();
  assert.equal(response.status, 200, JSON.stringify(value));
  return value;
}

try {
  let health;
  for (let attempt = 0; attempt < 80; attempt++) {
    try { health = await ask('/health'); break; }
    catch { if (failure || api.exitCode !== null) break; await wait(100); }
  }
  assert(health?.fleet_presets_available, failure || 'Fleet API did not start');
  const first = await ask('/auth/register', { username: 'fleet-browser', password: 'fleet-browser-test-password' });
  const second = await ask('/auth/register', { username: 'other-fleet-browser', password: 'fleet-browser-test-password' });
  await ask('/prologue/claim', { request_id: 'fleet-browser-gift', leader_id: 'IBS-U-USN-FLETCHER' }, first.token);

  process.env.VITE_CAS_ACCOUNT_URL = base;
  vite = await createServer({ root, cacheDir: join(dir, 'vite'), server: { host: loopback, port: 0 } });
  await vite.listen();
  const url = `http://${loopback}:${vite.httpServer.address().port}/tests/online-fleet.html`;
  browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });
  const page = await browser.newPage({ viewport: { width: 1180, height: 730 } });
  page.setDefaultTimeout(8000);
  const pageErrors = [];
  page.on('pageerror', error => pageErrors.push(error.message));
  await page.addInitScript(token => sessionStorage.setItem('cas-fleet-test-token', token), first.token);
  await page.goto(url);
  const button = name => page.getByRole('button', { name, exact: true });
  const alert = page.getByRole('alert');
  const save = button('保存为当前预设');
  await button('编入 弗莱彻').waitFor();
  assert(await button('排位未开放').isDisabled());
  assert(await save.isDisabled());
  assert.equal(await page.getByRole('button', { name: '编入 密苏里' }).count(), 0);
  await page.getByLabel('阵营').selectOption('axis');
  await page.getByText('本账号尚无该阵营舰船。', { exact: false }).waitFor();
  assert.equal(await button('编入 弗莱彻').count(), 0);
  await page.getByLabel('阵营').selectOption('allies');
  await page.getByLabel('筛选已拥有舰船').fill('帕金斯');
  assert.equal(await button('编入 弗莱彻').count(), 0);
  await button('编入 帕金斯').click();
  await page.getByLabel('筛选已拥有舰船').fill('');
  await button('编入 弗莱彻').click();
  await button('编入 莫里').click();
  await page.getByLabel('编队名称').fill('舰队编辑器验收');
  await page.getByLabel('编队领舰').selectOption('IBS-U-USN-MAURY');
  await page.getByLabel('AI 指挥风格').selectOption('rc_coordinated');

  await page.getByLabel('编制档位').selectOption('10000');
  await page.getByText('3 至 8 艘，1 至 2 艘战列舰', { exact: false }).waitFor();
  await save.click();
  await alert.filter({ hasText: '需要1至2艘战列舰' }).waitFor();
  assert.equal((await ask('/fleets', undefined, first.token)).fleets.length, 0);

  await page.getByLabel('编制档位').selectOption('3000');
  await page.getByText('3 至 6 艘，至少 2 艘驱逐舰', { exact: false }).waitFor();
  const attempts = [];
  await page.route(base + '/fleets', async route => {
    const request = route.request();
    if (request.method() === 'POST') {
      attempts.push(request.postDataJSON().request_id);
      if (attempts.length === 1) {
        const result = await route.fetch();
        assert.equal(result.status(), 200);
        await route.abort();
        return;
      }
    }
    await route.continue();
  });
  await save.click();
  await alert.filter({ hasText: '无法连接内测服务' }).waitFor();
  await save.click();
  await page.getByText('已保存「舰队编辑器验收」，并设为当前预设。').waitFor();
  assert.equal(attempts.length, 2);
  assert.equal(attempts[0], attempts[1]);
  const book = await ask('/fleets', undefined, first.token);
  assert.equal(book.fleets.length, 1);
  assert.equal(book.fleets[0].fleet.leader_id, 'IBS-U-USN-MAURY');
  assert.equal(book.fleets[0].validation.cost, null);
  assert.equal(book.fleets[0].validation.ranked_ready, false);
  await page.getByRole('button', { name: /^已保存预设/ }).click();
  await button('载入 舰队编辑器验收').waitFor();
  await button('新建预设').click();
  assert.equal(await page.getByLabel('编队名称').inputValue(), '我的同盟舰队');
  await page.getByRole('button', { name: /^已保存预设/ }).click();
  await button('载入 舰队编辑器验收').click();
  assert.equal(await page.getByLabel('编队领舰').inputValue(), 'IBS-U-USN-MAURY');

  const out = process.env.CAS_ARTIFACTS;
  if (out) { await mkdir(out, { recursive: true }); await page.screenshot({ path: join(out, 'cloud-fleet-desktop.png') }); }
  const short = await browser.newPage({ viewport: { width: 740, height: 360 }, isMobile: true, hasTouch: true });
  short.setDefaultTimeout(8000);
  await short.addInitScript(token => sessionStorage.setItem('cas-fleet-test-token', token), first.token);
  await short.goto(url);
  const shortButton = name => short.getByRole('button', { name, exact: true });
  await shortButton('移出 弗莱彻').waitFor();
  assert.equal(await short.getByLabel('编队领舰').inputValue(), 'IBS-U-USN-MAURY');
  const shortSave = shortButton('保存为当前预设');
  const box = await shortSave.boundingBox();
  assert(box.y >= 0 && box.y + box.height <= 360, 'the short landscape viewport clipped the save button');
  assert(await short.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth));
  await shortButton('移出 弗莱彻').tap();
  await shortButton('编入 弗莱彻').tap();
  await shortSave.tap();
  await short.getByText('已保存「舰队编辑器验收」，并设为当前预设。').waitFor();
  const updated = await ask('/fleets', undefined, first.token);
  assert.equal(updated.fleets.length, 1);
  assert.equal(updated.fleets[0].fleet.ship_ids.at(-1), 'IBS-U-USN-FLETCHER');
  if (out) await short.screenshot({ path: join(out, 'cloud-fleet-landscape.png') });

  const other = await browser.newPage();
  await other.addInitScript(token => sessionStorage.setItem('cas-fleet-test-token', token), second.token);
  await other.goto(url);
  await other.getByText('本账号尚无该阵营舰船。', { exact: false }).waitFor();
  await other.getByRole('button', { name: /^已保存预设/ }).click();
  assert.equal(await other.getByRole('button', { name: '载入 舰队编辑器验收' }).count(), 0);
  assert.deepEqual(pageErrors, []);
  console.log(JSON.stringify({ ok: true, realLoopback: true, rosterScoped: true, savedLeader: true,
    ranked3000Draft: true, ranked10000Rejection: true, rankedLocked: true,
    savedPresetRestored: true, retryAfterLostResponse: true, accountIsolation: true, landscapeTouch: [740, 360] }));
} finally {
  await browser?.close();
  await vite?.close();
  if (api.exitCode === null && api.signalCode === null && api.pid) {
    const exited = once(api, 'exit');
    api.kill();
    await exited;
  }
  if (dirname(await realpath(dir)) === temp) await rm(dir, { recursive: true });
}
