import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import fs from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createServer as openSocket } from 'node:net';
import { createServer } from 'vite';

const { chromium } = createRequire(import.meta.url)(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const root = fileURLToPath(new URL('../', import.meta.url));          // client/
const project = fileURLToPath(new URL('../../', import.meta.url));    // workspace root
const loopback = '127.0.0.1';
const apiPort = 8032;
const uiPort = 5185;
const api = `http://${loopback}:${apiPort}`;
const ui = `http://${loopback}:${uiPort}`;
const artifacts = path.join(project, 'artifacts', 'client', 'online-ranked');
const out = process.env.CAS_ARTIFACTS || artifacts;
const python = process.env.CAS_ONLINE_TEST_PYTHON ||
  path.join(process.env.LOCALAPPDATA || '', 'Programs', 'Python', 'Python313', 'python.exe');
const sim = path.join(project, 'target', 'release', 'cas-sim.exe');
const points = path.join(project, 'data', 'rules', 'cas-competitive-points-v1.json');
const accountDb = path.join(project, 'artifacts', 'cas-ranked-ui-qa.sqlite3');
const duelsDb = path.join(project, 'artifacts', 'cas-ranked-ui-qa-duels.sqlite3');
const nonce = Date.now().toString(36);
const username = suffix => `ranked-${nonce}-${suffix}`;
const password = 'cas-ranked-qa-password-2026';
const failures = [];

// The QA run always starts from a brand-new QA database under artifacts/.
for (const db of [accountDb, duelsDb]) {
  for (const suffix of ['', '-wal', '-shm']) await fs.rm(db + suffix, { force: true });
}

const socket = openSocket();
await new Promise((resolve, reject) => socket.once('error', reject).listen(apiPort, loopback, resolve));
await new Promise(resolve => socket.close(resolve));
const env = { ...process.env,
  CAS_ENABLE_DUELS: '1',
  CAS_ENABLE_RANKED: '1',
  CAS_RANKED_POINTS: points,
  CAS_SIM_PATH: sim,
  CAS_ACCOUNT_DB: accountDb,
  CAS_ACCOUNT_ORIGINS: `http://${loopback}:${uiPort}`,
  PYTHONIOENCODING: 'utf-8' };
const service = spawn(python, ['-m', 'uvicorn', 'server.accounts:app', '--host', loopback,
  '--port', String(apiPort), '--log-level', 'warning'], { cwd: project, env, windowsHide: true });
let serviceFailure = '';
service.on('error', error => { serviceFailure += error.message; });
service.stderr.on('data', chunk => { serviceFailure += chunk; });
service.stdout.resume();
let vite;
let browser;

async function ask(pathname, body, token) {
  const response = await fetch(api + pathname, { method: body ? 'POST' : 'GET',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) },
    body: body ? JSON.stringify(body) : undefined });
  const value = await response.json();
  assert.equal(response.status, 200, pathname + ' -> ' + JSON.stringify(value));
  return value;
}

try {
  let health;
  for (let attempt = 0; attempt < 120; attempt++) {
    try { health = await ask('/health'); break; }
    catch { if (serviceFailure || service.exitCode !== null) break; await new Promise(resolve => setTimeout(resolve, 250)); }
  }
  assert(health?.pvp_available && health?.ranked_pvp, serviceFailure || 'Ranked duel service did not start');
  assert.deepEqual(health.ranked_budgets, [3000]);

  const starterFleet = { id: 'fleet-rank-3000', name: '第五驱逐小队', side: 'allies', budget: 3000,
    ship_ids: ['IBS-U-USN-FLETCHER', 'IBS-U-USN-PERKINS', 'IBS-U-USN-MAURY'],
    ai_profile: 'rc_coordinated', leader_id: 'IBS-U-USN-FLETCHER', cost_version: null };
  const tokens = {};
  for (const suffix of ['a', 'b']) {
    const auth = await ask('/auth/register', { username: username(suffix), password });
    tokens[suffix] = auth.token;
    await ask('/prologue/claim', { request_id: 'prologue-' + suffix + '-' + nonce, leader_id: 'IBS-U-USN-FLETCHER' }, auth.token);
    const saved = await ask('/fleets', { request_id: 'save-fleet-' + suffix + '-' + nonce, fleet: starterFleet }, auth.token);
    assert.equal(saved.validation.ranked_ready, true, 'starter fleet must be ranked ready');
    assert.equal(saved.validation.cost, 1875);
  }
  const fleetBook = await ask('/fleets', undefined, tokens.a);
  assert.equal(fleetBook.fleets[0].validation.point_table_version, 'cas-points-surface-v1');

  process.env.VITE_CAS_ACCOUNT_URL = api;
  vite = await createServer({ root, cacheDir: path.join(await fs.mkdtemp(path.join(project, 'artifacts', 'vite-ranked-')), 'cache'),
    server: { host: loopback, port: uiPort, strictPort: true } });
  await vite.listen();
  browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });

  async function openSeat(suffix, viewport) {
    const page = await browser.newPage({ viewport });
    page.setDefaultTimeout(15000);
    page.on('pageerror', error => failures.push(error.message));
    await page.goto(ui);
    await page.getByRole('button', { name: '切换联机内测账号' }).click();
    await page.getByLabel('用户名', { exact: true }).fill(username(suffix));
    await page.getByLabel('密码', { exact: true }).fill(password);
    await page.getByRole('button', { name: '登录并进入母港' }).click();
    await page.locator('.growth-port').waitFor();
    await page.getByRole('button', { name: '打开主菜单' }).click();
    await page.getByRole('button', { name: '线上舰桥', exact: true }).click();
    await page.getByRole('button', { name: '创建约战口令' }).waitFor();
    await page.getByRole('button', { name: '排位赛', exact: true }).click();
    await page.getByText('当前赛季', { exact: false }).waitFor();
    return page;
  }

  const allies = await openSeat('a', { width: 1024, height: 640 });
  const axis = await openSeat('b', { width: 740, height: 360 });
  for (const [page, label] of [[allies, 'desktop'], [axis, 'short landscape']]) {
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
      `ranked lobby overflows horizontally in the ${label} viewport`);
  }

  for (const page of [allies, axis]) {
    await page.getByText('S0001', { exact: false }).first().waitFor();
    await page.getByText('点表版本 cas-points-surface-v1').waitFor();
    await page.getByRole('button', { name: /3000 分护航战.*白银 · 1000 分/s }).waitFor();
    const closed = page.getByRole('button', { name: /10000 分战列舰交战.*未开放/s });
    await closed.waitFor();
    assert(await closed.isDisabled(), '10000 budget must not be selectable');
    const preset = page.getByLabel('出战预设');
    await preset.waitFor();
    assert.match(await preset.textContent(), /第五驱逐小队 · 点价 1875 分/);
  }
  if (process.env.CAS_ARTIFACTS) await allies.screenshot({ path: path.join(out, '00-ranked-lobby.png') });

  const commands = [];
  for (const page of [allies, axis]) page.on('request', request => {
    if (request.method() === 'POST' && new URL(request.url()).pathname.endsWith('/commands')) commands.push(request.url());
  });

  await allies.getByRole('button', { name: '入队', exact: true }).click();
  await allies.getByText(/正在寻找 3000 分护航战 对手/).waitFor();
  await allies.getByText(/前有效，超时自动退出/).waitFor();
  await axis.getByRole('button', { name: '入队', exact: true }).click();
  await axis.locator('.side-tag').waitFor();
  assert.equal(await axis.locator('.side-tag').textContent(), '轴心舰队');
  await allies.getByRole('button', { name: /进入对局 · 3000 分护航战 · 同盟舰队/ }).click();
  await allies.locator('.side-tag').waitFor();
  assert.equal(await allies.locator('.side-tag').textContent(), '同盟舰队');
  await allies.getByText('排位战进行中 · 3000 分', { exact: false }).waitFor();
  for (const page of [allies, axis]) {
    assert.equal(await page.getByRole('button', { name: '推进一秒' }).count(), 0);
    assert.equal(await page.getByRole('button', { name: '演习设置' }).count(), 0);
    assert.equal(await page.getByText('联机时钟 · 4×').count(), 1);
  }
  if (process.env.CAS_ARTIFACTS) await axis.screenshot({ path: path.join(out, '01-ranked-battle-axis.png') });

  // Ranked matches freeze the AI style; suggestions stay advisory until confirmed.
  await allies.getByRole('button', { name: '战术 AI', exact: true }).click();
  await allies.getByText(/指挥风格已冻结为/).waitFor();
  await allies.getByText('指挥权限固定为手动，战术建议仅供参考，需本人确认下令。').waitFor();
  assert.equal(await allies.getByLabel('AI 风格').count(), 0);
  assert.equal(await allies.getByLabel('指挥权限').count(), 0);
  const before = commands.length;
  await allies.getByRole('button', { name: '查看战术建议', exact: true }).click();
  await allies.waitForTimeout(1200);
  assert.equal(commands.length, before, 'asking for a suggestion must not send orders');
  const accept = await allies.getByRole('button', { name: '采纳建议' }).count();
  assert(accept === 0 || await allies.getByRole('button', { name: '采纳建议' }).isVisible(),
    'any suggested orders must wait for manual confirmation');

  await axis.getByRole('button', { name: '投降', exact: true }).click();
  await axis.getByRole('button', { name: '确认投降', exact: true }).click();
  for (const [page, change] of [[allies, '积分 1000 → 1012（+12 · 白银）'], [axis, '积分 1000 → 988（-12 · 青铜）']]) {
    await page.getByText('排位战果', { exact: true }).waitFor();
    await page.getByRole('heading', { name: '同盟舰队胜出' }).waitFor();
    await page.getByText(change, { exact: false }).waitFor();
    await page.getByText(/本席舰队 第五驱逐小队 · 点价 1875 分/).waitFor();
    await page.getByText(/3000 分护航战 · 赛季 S0001 · 点表 cas-points-surface-v1/).waitFor();
  }
  if (process.env.CAS_ARTIFACTS) await allies.screenshot({ path: path.join(out, '02-ranked-result-allies.png') });

  // Lobby shows the settled ladder, the outcome and the rating delta.
  await allies.getByRole('button', { name: '返回线上舰桥' }).click();
  await allies.getByRole('button', { name: '排位赛', exact: true }).click();
  await allies.getByText(/当前赛季/).waitFor();
  await allies.getByText(/查看战果 · 3000 分护航战 · 同盟舰队/).waitFor();
  await allies.getByText(/胜 1000→1012（\+12 · 白银）/).waitFor();
  await allies.getByRole('button', { name: /3000 分护航战.*白银 · 1012 分.*1 战 1 胜/s }).waitFor();

  // Re-queue, then cancel: the cancelled seat must not be matched again.
  await allies.getByRole('button', { name: '入队', exact: true }).click();
  await allies.getByText(/正在寻找 3000 分护航战 对手/).waitFor();
  await allies.getByRole('button', { name: '取消排队', exact: true }).click();
  await allies.getByRole('button', { name: '入队', exact: true }).waitFor();
  const quiet = await ask('/pvp/ranked/status', undefined, tokens.a);
  assert.equal(quiet.queue, null, 'cancelled queue must clear on the server');
  assert.equal(quiet.matches.length, 1, 'cancelling must not create a match');
  await allies.waitForTimeout(4500);
  const stillQuiet = await ask('/pvp/ranked/status', undefined, tokens.a);
  assert.equal(stillQuiet.matches.length, 1, 'no rematch may appear after cancelling');
  assert.equal(stillQuiet.matches[0].status, 'complete');
  assert.equal(await allies.getByRole('button', { name: /进入对局/ }).count(), 0);

  // Operator voids the next active ranked match; both seats must stop and show no rating change.
  await allies.getByRole('button', { name: '入队', exact: true }).click();
  await allies.getByText(/正在寻找 3000 分护航战 对手/).waitFor();
  await axis.getByRole('button', { name: '返回线上舰桥' }).click();
  await axis.getByRole('button', { name: '排位赛', exact: true }).click();
  await axis.getByText(/当前赛季/).waitFor();
  await axis.getByRole('button', { name: '入队', exact: true }).click();
  await axis.locator('.side-tag').waitFor();
  await allies.getByRole('button', { name: /进入对局 · 3000 分护航战 · 同盟舰队/ }).click();
  await allies.locator('.side-tag').waitFor();
  const active = (await ask('/pvp/ranked/status', undefined, tokens.a)).matches.find(entry => entry.status === 'active');
  assert(active, 'second ranked match must be active before the void');
  const voided = await new Promise((resolve, reject) => {
    const cli = spawn(python, ['-m', 'server.duels', '--db', duelsDb, '--void-ranked', active.match_id],
      { cwd: project, env: { ...process.env, PYTHONIOENCODING: 'utf-8' }, windowsHide: true });
    let stdout = ''; let stderr = '';
    cli.stdout.on('data', chunk => { stdout += chunk; });
    cli.stderr.on('data', chunk => { stderr += chunk; });
    cli.on('exit', code => code === 0 ? resolve(JSON.parse(stdout)) : reject(new Error(stderr || 'void exit ' + code)));
  });
  assert.equal(voided.voided, true);
  for (const page of [allies, axis]) {
    await page.getByText('本局作废、积分不变', { exact: true }).waitFor();
    await page.getByText('服务故障导致本局未能完成评分，双方积分保持不变。本局不可再下达命令。').waitFor();
    assert.equal(await page.getByRole('button', { name: '投降', exact: true }).count(), 0, 'voided match must stop all operations');
    assert.equal(await page.getByRole('button', { name: '返回线上舰桥' }).count(), 1);
  }
  if (process.env.CAS_ARTIFACTS) await axis.screenshot({ path: path.join(out, '03-ranked-void-axis.png') });

  const final = await ask('/pvp/ranked/status', undefined, tokens.b);
  assert.equal(final.matches.length, 2);
  const settled = final.matches.find(entry => entry.rated === true);
  const discarded = final.matches.find(entry => entry.rated === false);
  assert(settled && discarded, 'one rated match and one voided match expected');
  assert.equal(discarded.end_reason, 'server_fault');
  assert.equal(discarded.result, null);
  assert.equal(discarded.rating.delta, 0);
  assert.equal(final.ratings.find(entry => entry.budget === 3000).rating, settled.rating.after);

  const receipt = {
    season: final.season,
    pointTable: { version: final.point_table_version, budgets: final.available_budgets, starterCost: 1875 },
    ladder: final.ratings,
    ratedMatch: { match_id: settled.match_id, budget: settled.budget, season_id: settled.season_id,
      own_fleet: settled.own_fleet, fleet_cost: settled.fleet_cost, rated: settled.rated, rating: settled.rating,
      end_reason: settled.end_reason, result: settled.result },
    voidedMatch: { match_id: discarded.match_id, end_reason: discarded.end_reason, rated: discarded.rated,
      rating: discarded.rating, result: discarded.result, ui_stopped_operations: true },
    cancelAfterQueue: { rematch_count: final.matches.length, queue_cleared: true },
    suggestionRequiresConfirmation: true,
    aiStyleFrozen: true,
    accounts: { allies: username('a'), axis: username('b') },
  };
  await fs.mkdir(out, { recursive: true });
  await fs.writeFile(path.join(out, 'browser-receipt.json'), JSON.stringify(receipt, null, 2));
  assert.deepEqual(failures, []);
  console.log(JSON.stringify({ ok: true, season: final.season.id, budgets: final.available_budgets,
    ratedDelta: settled.rating.delta, voided: discarded.match_id, receipt: path.join(out, 'browser-receipt.json') }));
} finally {
  await browser?.close();
  await vite?.close();
  if (service.exitCode === null && service.signalCode === null && service.pid) {
    const exited = once(service, 'exit');
    service.kill();
    await exited;
  }
}
