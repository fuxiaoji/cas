import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const [adb, serial, evidencePath] = process.argv.slice(2);
assert(adb && serial && evidencePath, 'Usage: node scripts/build-android-smoke.mjs <adb.exe> <serial> <evidence.json>');
const packageName = 'org.casnaval.exercise';
const origin = 'https://appassets.androidplatform.net/index.html';
const activity = `${packageName}/.MainActivity`;
const run = (...args) => execFileSync(adb, ['-s', serial, ...args], { encoding: 'utf8', timeout: 10000 }).trim();

async function waitFor(description, test, ms = 20000) {
  const end = Date.now() + ms;
  let last;
  do {
    try { const value = await test(); if (value) return value; }
    catch (error) { last = error; }
    await delay(250);
  } while (Date.now() < end);
  throw new Error(`Timed out waiting for ${description}`, { cause: last });
}

async function connect() {
  const pid = await waitFor('CAS app process', () => run('shell', 'pidof', packageName).split(' ')[0]);
  const port = run('forward', 'tcp:0', `localabstract:webview_devtools_remote_${pid}`);
  assert.match(port, /^\d+$/);
  let ws;
  try {
    const target = await waitFor('the app WebView page', async () => {
      const res = await fetch(`http://127.0.0.1:${port}/json/list`, { signal: AbortSignal.timeout(2500) });
      return (await res.json()).find(page => page.url === origin);
    });
    ws = new WebSocket(target.webSocketDebuggerUrl);
    await new Promise((ok, fail) => {
      const limit = setTimeout(() => fail(new Error('CDP socket timed out')), 5000);
      ws.addEventListener('open', () => { clearTimeout(limit); ok(); }, { once: true });
      ws.addEventListener('error', () => { clearTimeout(limit); fail(new Error('CDP socket failed')); }, { once: true });
    });
    let id = 0;
    const pending = new Map();
    ws.addEventListener('message', event => {
      const { id, result, error } = JSON.parse(event.data);
      const entry = pending.get(id);
      if (!entry) return;
      pending.delete(id);
      clearTimeout(entry.limit);
      if (error) entry.fail(new Error(error.message));
      else entry.ok(result);
    });
    const call = (method, params) => {
        const current = ++id;
        return new Promise((ok, fail) => {
          const limit = setTimeout(() => { pending.delete(current); fail(new Error('WebView evaluation timed out')); }, 20000);
          pending.set(current, { ok, fail, limit });
          ws.send(JSON.stringify({ id: current, method, params }));
        });
    };
    return {
      async evaluate(expression) {
        const response = await call('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
        if (response.exceptionDetails) throw new Error(response.exceptionDetails.exception?.description ?? response.exceptionDetails.text);
        return response.result.value;
      },
      touch(type, point) { return call('Input.dispatchTouchEvent', { type, touchPoints: point ? [{ ...point, id: 1 }] : [] }); },
      close() { ws.close(); run('forward', '--remove', `tcp:${port}`); }
    };
  } catch (error) {
    ws?.close();
    run('forward', '--remove', `tcp:${port}`);
    throw error;
  }
}

const sessionProbe = `(async () => {
  const worker = new Worker(new URL('./engine-worker.js', document.baseURI));
  let id = 0;
  function ask(request) {
    const current = ++id;
    return new Promise((resolve, reject) => {
      worker.onmessage = ({data}) => {
        if (data.id === current) data.response.ok ? resolve(data.response.data) : reject(Error(data.response.error));
      };
      worker.onerror = e => reject(Error(e.message));
      worker.postMessage({ id: current, request });
    });
  }
  try {
    const info = await ask({ op: 'info' });
    const start = await ask({ op: 'new', seed: 6106, side: 'allies', enemy: 'coord' });
    await ask({ op: 'step', seconds: 1 });
    await ask({ op: 'ai', fleet: start.fleets[0].id, profile: 'coord', mode: 'auto', move: true, gun: true, torpedo: true });
    const end = await ask({ op: 'step', seconds: 359 });
    const save = await ask({ op: 'save' });
    const replay = await ask({ op: 'replay', save });
    const restore = await ask({ op: 'load', save });
    const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(end)));
    const stateSha256 = [...new Uint8Array(hash)].map(n => n.toString(16).padStart(2, '0')).join('');
    const night = await ask({ op: 'new', seed: 6106, variant: 'night' });
    const campaign = await ask({ op: 'campaign' });
    return { origin: location.href, viewport: [innerWidth, innerHeight], version: info.version,
      ownShips: start.ships.length, tickBefore: start.tick, tickAfter: end.tick, stateSha256,
      nightExerciseStarted: night.variant === 'night' && night.ships?.length === 5,
      historicalCatalogueRows: campaign.scenarios?.length, allHistoryLocked: campaign.scenarios?.every(row => row.playable === false),
      sameReplay: JSON.stringify(end) === JSON.stringify(replay), sameRestore: JSON.stringify(end) === JSON.stringify(restore) };
  } finally { worker.terminate(); }
})()`;

const airplaneMode = run('shell', 'settings', 'get', 'global', 'airplane_mode_on');
assert.equal(airplaneMode, '1', 'Enable airplane mode on the dedicated CAS test device before running this test.');
run('shell', 'am', 'start', '-W', '-n', activity);
const first = await connect();
let detail;
try {
  await waitFor('the actual tactical chart', () => first.evaluate("Boolean(document.querySelector('canvas') && document.querySelector('[data-ship]'))"));
  const commandCount = () => first.evaluate("JSON.parse(localStorage.getItem('cas.exercise.autosave.v1'))?.commands?.length ?? 0");
  const before = await commandCount();
  const weapon = await waitFor('a reachable deck weapon badge', () => first.evaluate(`Array.from(document.querySelectorAll('.weapon:not(:disabled)')).map(button => {
    const box = button.getBoundingClientRect(), x = Math.round(box.x + box.width / 2), y = Math.round(box.y + box.height / 2);
    return {x, y, live: button.contains(document.elementFromPoint(x, y))};
  }).find(point => point.live) ?? null`));
  await first.touch('touchStart', { x: weapon.x, y: weapon.y });
  const cancel = await waitFor('the native touch cancel well', () => first.evaluate(`(() => {
    const box = document.querySelector('.cancel-well.visible')?.getBoundingClientRect();
    return box ? {x: Math.round(box.x + box.width / 2), y: Math.round(box.y + box.height / 2)} : null;
  })()`));
  await first.touch('touchMove', cancel);
  await waitFor('the touch is over the cancel well', () => first.evaluate("Boolean(document.querySelector('.cancel-well.hot'))"));
  await first.touch('touchEnd');
  await waitFor('the gesture closes on release', () => first.evaluate("!document.querySelector('.cancel-well.visible')"));
  assert.equal(await commandCount(), before, 'Dragging a weapon into the cancel well must not submit a command');

  await first.touch('touchStart', { x: weapon.x, y: weapon.y });
  await waitFor('second fire gesture before switching apps', () => first.evaluate("Boolean(document.querySelector('.cancel-well.visible'))"));
  run('shell', 'input', 'keyevent', 'KEYCODE_HOME');
  await delay(350);
  run('shell', 'am', 'start', '-W', '-n', activity);
  await waitFor('the fire gesture is cleared on returning to CAS', () => first.evaluate("!document.hidden && !document.querySelector('.cancel-well.visible')"));
  assert.equal(await commandCount(), before, 'Switching apps mid-gesture must not submit a command');
  await first.touch('touchCancel');

  const button = label => `Array.from(document.querySelectorAll('button')).find(b => b.textContent.trim() === '${label}' || b.getAttribute('aria-label') === '${label}')`;
  await first.evaluate(`${button('舰况')}.click()`);
  const shipPortrait = await waitFor('the packaged ship portrait in offline ship status', () => first.evaluate(`(() => {
    const img = Array.from(document.querySelectorAll('.ship-portrait img')).find(item => item.complete && item.naturalWidth > 0);
    return img?.closest('[data-character]')?.dataset.character ?? null;
  })()`));
  const harbor = await first.evaluate(`Boolean(${button('母港')})`);
  if (harbor) {
    await first.evaluate(`${button('母港')}.click()`);
    for (const item of ['舰桥学堂', '舰库与编队', '本机征募', '越级挑战']) {
      await waitFor(`CAS harbor navigation: ${item}`, () => first.evaluate(`Boolean(${button(item)})`));
    }
    await first.evaluate(`${button('返回海图')}.click()`);
    await waitFor('the tactical chart after leaving harbor', () => first.evaluate("Boolean(document.querySelector('canvas'))"));
  }
  const probe = await first.evaluate(sessionProbe);
  assert.equal(probe.origin, origin);
  assert.equal(probe.version, 'cas-battle-v2');
  assert.equal(probe.ownShips, 5);
  assert.equal(probe.tickBefore, 0);
  assert.equal(probe.tickAfter, 360);
  assert.equal(probe.nightExerciseStarted, true);
  assert.equal(probe.historicalCatalogueRows, 16);
  assert.equal(probe.allHistoryLocked, true);
  assert(probe.sameReplay && probe.sameRestore, 'Offline replay and saved battle must agree');
  assert(probe.viewport[0] > probe.viewport[1], 'Battle WebView must be landscape');
  await first.evaluate("localStorage.setItem('cas.android-smoke', 'native-webview-origin-persists')");
  detail = { ...probe, touchCancelNoCommand: true, backgroundCancelsGesture: true, shipPortrait, harborNavigation: harbor };
} finally { first.close(); }

// Model a normal close/reopen: background the app first, which lets WebView's
// origin storage finish its asynchronous disk write before process teardown.
run('shell', 'input', 'keyevent', 'KEYCODE_HOME');
await delay(5500);
run('shell', 'am', 'force-stop', packageName);
run('shell', 'am', 'start', '-W', '-n', activity);
const second = await connect();
try {
  assert.equal(await second.evaluate("localStorage.getItem('cas.android-smoke')"), 'native-webview-origin-persists');
  await second.evaluate("localStorage.removeItem('cas.android-smoke')");
  await waitFor('the chart after restarting Android app', () => second.evaluate("Boolean(document.querySelector('canvas'))"));
  const saved = await second.evaluate("Boolean(localStorage.getItem('cas.exercise.autosave.v1'))");
  assert(saved, 'The product should autosave the battle as well as the smoke key');
  const evidence = { ok: true, serial, airplaneMode: true, localStorageSurvivedRestart: true, appAutosavePresent: saved, ...detail };
  const out = resolve(evidencePath);
  await mkdir(dirname(out), { recursive: true });
  await writeFile(out, JSON.stringify(evidence, null, 2) + '\n', { flag: 'wx' });
  console.log(evidence);
  console.log(`Android evidence: ${out}`);
} finally { second.close(); }
