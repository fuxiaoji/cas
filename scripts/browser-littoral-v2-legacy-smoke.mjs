// Legacy Web compatibility gate for the new WASM. This does not exercise Godot UI.
import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';

const root = fileURLToPath(new URL('../', import.meta.url));
const client = path.join(root, 'client');
const require = createRequire(path.join(client, 'package.json'));
const { chromium } = require('playwright');
const { createServer } = await import(pathToFileURL(require.resolve('vite')).href);
const folder = path.join(root, 'artifacts/littoral-v2/browser-legacy');
const arenaWasmBytes=await fs.readFile(path.join(root,'artifacts/littoral-v2/cas-core-67ab469d.wasm'));
await fs.mkdir(folder, { recursive: true });
const hash = value => createHash('sha256').update(value).digest('hex');
const expectedWasm = hash(arenaWasmBytes);
const checks = [], errors = [], wasmRequests = [], screenshots = [];
const check = (ok, label, evidence) => checks.push({ ok: !!ok, label, ...(evidence ? { evidence } : {}) });
let browser, context, server, before, after, saved, snapshotHash, bounds, version, base;
try {
  server = await createServer({ root: client, plugins:[{name:'arena-audit-wasm',configureServer(s){s.middlewares.use('/cas_core.wasm',(req,res)=>{res.setHeader('Content-Type','application/wasm');res.end(arenaWasmBytes);});}}], server: { host: '127.0.0.1', port: 5186, strictPort: false } });
  await server.listen();
  base = server.resolvedUrls.local[0];
  browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', headless: false });
  version = browser.version();
  context = await browser.newContext({ viewport: { width: 1360, height: 768 } });
  const page = await context.newPage();
  page.on('pageerror', error => errors.push(String(error.stack || error)));
  context.on('response', response => {
    if (response.url().endsWith('/cas_core.wasm')) wasmRequests.push({ url: response.url(), status: response.status() });
  });
  const button = name => page.getByRole('button', { name, exact: true });
  const q = (op, params = {}) => page.evaluate(async request =>
    (await import(performance.getEntriesByType('resource').filter(e => e.name.includes('/src/engine.ts')).at(-1)?.name ?? '/src/engine.ts')).ask(request), { op, ...params });
  const shot = async name => { await page.screenshot({ path: path.join(folder, name) }); screenshots.push(name); };

  await page.goto(base);
  await page.locator('.growth-port').waitFor();
  await page.locator('.growth-campaign-entry').click();
  await page.locator('.campaign-lobby').waitFor();
  await page.locator('.cl-row').filter({ hasText: '埃斯佩兰斯角' }).first().click();
  await page.locator('.cl-diff button').filter({ hasText: '标准' }).click();
  await button('标准难度出击').click();
  await page.locator('.battle-map').waitFor();
  before = await q('observe');
  check(before.campaign?.stageId === 'CAMP-ALLIES-02' && before.campaign?.difficulty === 'standard', 'Visible UI starts requested historical campaign');
  check(before.ships.length === 9, 'Original nine-ship borrowed fleet remains intact', before.ships.map(s => s.name));
  check(before.environment?.light === 'night', 'Historical authoritative night environment remains intact', before.environment);
  check(!before.salvage?.adventure, 'Historical battle does not acquire adventure profile or monster readouts');
  await button('推进一秒').click();
  await page.waitForFunction(expected => document.querySelector('.time strong')?.textContent === expected, '00:01');
  after = await q('observe');
  check(after.tick === before.tick + 1, 'Visible step advances exactly one simulation second');
  saved = await q('save');
  await button('保存进度').click();
  await page.waitForFunction(() => Object.keys(localStorage).some(key => key.includes('cas.exercise.autosave.v1') && JSON.parse(localStorage.getItem(key) || '{}').tick === 1));
  const repeated = await q('save');
  snapshotHash = hash(JSON.stringify(saved));
  check(JSON.stringify(repeated) === JSON.stringify(saved), 'Visible saving preserves exact serialized core snapshot');
  await shot('01-historical-saved.png');

  await page.reload();
  await page.locator('.growth-port').waitFor();
  await button('打开主菜单').click();
  await button('继续演习').click();
  await page.locator('.battle-map').waitFor();
  const restored = await q('observe');
  const restoredSave = await q('save');
  check(restored.campaign?.stageId === before.campaign.stageId && restored.tick === after.tick, 'Reload and resume restore historical campaign and paused tick');
  check(hash(JSON.stringify(restoredSave)) === snapshotHash, 'Reload and resume preserve exact serialized snapshot');
  check(await button('开始演习').count() === 1 && await button('暂停演习').count() === 0, 'Restored historical battle stays paused');
  bounds = await page.evaluate(() => ['.masthead', '.battle-map', '.staff-panel'].map(selector => {
    const r = document.querySelector(selector)?.getBoundingClientRect();
    return { selector, rect: r ? { x: r.x, y: r.y, w: r.width, h: r.height } : null };
  }));
  check(bounds.every(({ rect: r }) => r && r.x >= -1 && r.y >= -1 && r.x + r.w <= 1361 && r.y + r.h <= 769), 'Browser map, header and staff controls fit declared viewport', bounds);
  const served = await context.request.get(new URL('cas_core.wasm', base).href);
  const servedHash = hash(await served.body());
  check(served.ok() && servedHash === expectedWasm && wasmRequests.length > 0, 'Browser loads and serves exact final release WASM', { expectedWasm, servedHash, requests: wasmRequests });
  await shot('02-historical-restored.png');
  for (const mode of ['ranked','team3']) {
    const v=await q('new_arena',{arena_version:'cas-local-arena-v1',seed:6106,mode,groups:[{id:'g1',name:'玩家舰队',ships:['IBS-U-USN-FLETCHER','IBS-U-USN-PERKINS','IBS-U-USN-MAURY']}]});
    check(v.arena?.mode===mode && v.arena?.budget===10000, 'Actual browser creates new '+mode+' arena');
    if(mode==='team3') check(v.arena.groups.filter(g=>g.side==='allies'&&g.bot).length===2 && v.arena.groups.filter(g=>g.side==='axis').length===3, 'Browser 3v3 has two AI allies and three AI opponents');
    const v2=await q('step',{seconds:4}),snapshot=await q('save'),restoredArena=await q('load',{save:snapshot});
    check(JSON.stringify(restoredArena)===JSON.stringify(v2),'Browser '+mode+' save/replay equality');
  }
  check(errors.length === 0, 'No browser runtime errors', errors);
} catch (error) {
  errors.push(String(error.stack || error));
  check(false, 'Smoke flow completed', errors.at(-1));
} finally {
  if (context) await context.close();
  if (browser) await browser.close();
  if (server) await server.close();
  const report = { date: new Date().toISOString().slice(0, 10), browser: version, runtime: 'headed Edge / temporary nonpersistent context', scope: 'cas-littoral-v2 WASM compatibility of legacy historical Web UI; not a Web littoral interface', server: base, checks, passed: checks.filter(c => c.ok).length, errors, coreSnapshotSha256: snapshotHash, wasmSha256: expectedWasm, servedWasm: wasmRequests, screenshots, cleanup: 'Owned nonpersistent browser context, Edge process and temporary Vite server closed', knownPresentationDifference: 'Legacy browser map caption still uses fixed daytime exercise label. Authoritative environment is Esperance at night; existing historical source blocker retained.' };
  await fs.writeFile(path.join(folder, 'receipt.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ passed: report.passed, checks: checks.length, failures: checks.filter(c => !c.ok), errors, wasmSha256: expectedWasm, report: path.join(folder, 'receipt.json') }));
  if (checks.some(c => !c.ok) || errors.length) process.exitCode = 1;
}
