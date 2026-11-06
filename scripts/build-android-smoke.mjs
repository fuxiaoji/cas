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
const testName = 'CASQA-' + Date.now();
const testPassword = 'CAS offline smoke 2026';
const button = label => `Array.from(document.querySelectorAll('button')).find(b => b.textContent.trim() === ${JSON.stringify(label)} || b.getAttribute('aria-label') === ${JSON.stringify(label)})`;

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

async function openProduct(view, register) {
  await waitFor('local account login', () => view.evaluate("Boolean(document.querySelector('main.login-screen'))"));
  if (register) await view.evaluate(`${button('新用户，创建账号')}.click()`);
  const submit = button(register ? '注册并进入母港' : '登录并进入母港');
  await waitFor('enabled local account form', () => view.evaluate(`Boolean(${submit})`));
  await view.evaluate(`(() => {
    function fill(id, value) {
      const input = document.getElementById(id);
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(input, value);
      input.dispatchEvent(new Event('input', { bubbles: true }));
    }
    fill('account-username', ${JSON.stringify(testName)});
    fill('account-password', ${JSON.stringify(testPassword)});
    ${submit}.click();
  })()`);
  await waitFor('authenticated harbor', () => view.evaluate("Boolean(document.querySelector('.growth-campaign-entry'))"));
  const account = await view.evaluate(`JSON.parse(localStorage.getItem('cas.accounts.local.v1')).find(account => account.name === ${JSON.stringify(testName)})`);
  assert(account?.id && account.verifier !== testPassword, 'The app stores an offline account verifier');
  return 'cas.profile.' + account.id + '.cas.exercise.autosave.v1';
}

async function continueExercise(view) {
  await view.evaluate(`${button('打开主菜单')}.click()`);
  await waitFor('continue exercise is enabled', () => view.evaluate(`Boolean(${button('继续演习')} && !${button('继续演习')}.disabled)`));
  await view.evaluate(`${button('继续演习')}.click()`);
  await waitFor('the actual realtime tactical chart', () => view.evaluate(
    "Boolean(document.querySelector('canvas') && document.querySelector('[data-ship]') && document.querySelector('.realtime-badge'))"));
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
    const start = await ask({ op: 'new', seed: 6106, side: 'allies', enemy: 'coord', realtime: true });
    await ask({ op: 'step', seconds: 1 });
    await ask({ op: 'ai', fleet: start.fleets[0].id, profile: 'coord', mode: 'auto', move: true, gun: true, torpedo: true });
    const end = await ask({ op: 'step', seconds: 359 });
    const save = await ask({ op: 'save' });
    const replay = await ask({ op: 'replay', save });
    const restore = await ask({ op: 'load', save });
    const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(end)));
    const stateSha256 = [...new Uint8Array(hash)].map(n => n.toString(16).padStart(2, '0')).join('');
    const night = await ask({ op: 'new', seed: 6106, variant: 'night', realtime: true });
    const campaign = await ask({ op: 'campaign' });
    const cape = await ask({ op: 'new_campaign', id: 'CAMP-AXIS-03', difficulty: 'story', seed: 6106 });
    const capeSave = await ask({ op: 'save' });
    const capeReplay = await ask({ op: 'replay', save: capeSave });
    const channel = await ask({ op: 'new_campaign', id: 'CAMP-AXIS-01', difficulty: 'story', seed: 53 });
    const channelSave = await ask({ op: 'save' });
    const channelReplay = await ask({ op: 'replay', save: channelSave });
    const legacyStages = [];
    for (const n of ['01', '07', '12', '15', '16']) {
      const detail = await ask({ op: 'campaign_detail', id: 'CAMP-AXIS-' + n });
      if (detail.record || detail.legacy?.playable !== false ||
          detail.legacy.ships?.some(ship => ship.cas_profile_id !== null)) throw Error('Unsafe fallback stage: ' + n);
      legacyStages.push(detail.legacy.ships.length);
    }
    return { origin: location.href, viewport: [innerWidth, innerHeight], version: start.version,
      baselineVersion: info.version, realtimeVersion: info.realtimeVersion, savedVersion: save.version,
      realtimeGunnery: start.realtimeGunnery && start.ships.every(ship => ship.systems.guns.every(mount => Number.isInteger(mount.readyTick))),
      ownShips: start.ships.length, tickBefore: start.tick, tickAfter: end.tick, stateSha256,
      nightExerciseStarted: night.variant === 'night' && night.ships?.length === 5 && night.version === info.realtimeVersion,
      historicalCatalogueRows: campaign.scenarios?.length, historicalSourceRecords: campaign.scenarios?.filter(row => row.cas?.import).length,
      playableAdaptations: campaign.scenarios?.filter(row => row.playable && row.runtime?.historicalReady === false).length,
      capeReplay: cape.ships.length === 5 && cape.fleets.length === 2 && cape.environment.visibility === 10 &&
        JSON.stringify(cape) === JSON.stringify(capeReplay), legacyStages,
      channelReplay: channel.ships.length === 3 && channel.fleets.length === 3 && channel.environment.visibility === 5 &&
        channel.ships.every(ship => ship.classId === ship.characterId) && JSON.stringify(channel) === JSON.stringify(channelReplay),
      sameReplay: JSON.stringify(end) === JSON.stringify(replay), sameRestore: JSON.stringify(end) === JSON.stringify(restore) };
  } finally { worker.terminate(); }
})()`;

const airplaneMode = run('shell', 'settings', 'get', 'global', 'airplane_mode_on');
assert.equal(airplaneMode, '1', 'Enable airplane mode on the dedicated CAS test device before running this test.');
run('shell', 'am', 'force-stop', packageName);
run('shell', 'am', 'start', '-W', '-n', activity);
const first = await connect();
let detail;
let saveKey;
try {
  saveKey = await openProduct(first, true);
  await first.evaluate("document.querySelector('.growth-campaign-entry').click()");
  await waitFor('16 allied campaign stages', () => first.evaluate(`document.querySelectorAll('[data-stage-id^="CAMP-ALLIES-"]').length === 16`));
  await first.evaluate(`document.querySelector('[data-stage-id="CAMP-ALLIES-03"] summary').click()`);
  await waitFor('the Cape St. George source record', () => first.evaluate(`Boolean(document.querySelector('[data-source-stage="CAMP-ALLIES-03"]'))`));
  await first.evaluate(`${button('轴心战线')}.click()`);
  await waitFor('16 Axis campaign stages and Cape record', () => first.evaluate(`document.querySelectorAll('[data-stage-id^="CAMP-AXIS-"]').length === 16 &&
    Boolean(document.querySelector('[data-source-stage="CAMP-AXIS-03"]'))`));
  const sourceStages = ['02', '03', '04', '05', '06', '08', '09', '10', '11', '13', '14'];
  for (const node of sourceStages.filter(node => node !== '03')) {
    const stage = 'CAMP-AXIS-' + node;
    await first.evaluate(`document.querySelector('[data-stage-id="${stage}"] summary').click()`);
    await waitFor('source record for ' + stage, () => first.evaluate(`Boolean(document.querySelector('[data-source-stage="${stage}"]'))`));
    if (node === '04') {
      assert(await first.evaluate(`document.querySelector('[data-source-stage="${stage}"]').textContent.includes('损伤点比达到 2:1')`),
        'The original Kula Gulf damage ratio must render in the packaged archive');
    }
  }
  const legacyStages = ['01', '07', '12', '15', '16'];
  for (const node of legacyStages) {
    const stage = 'CAMP-AXIS-' + node;
    await first.evaluate(`document.querySelector('[data-stage-id="${stage}"] summary').click()`);
    await waitFor('legacy deployment for ' + stage, () => first.evaluate(`Boolean(document.querySelector('[data-legacy-stage="${stage}"]'))`));
  }
  const readMidnightChart = () => first.evaluate(`Array.from(document.querySelectorAll(
    '[data-legacy-stage="CAMP-AXIS-16"] svg.archive-deployment g'), mark => mark.getAttribute('transform'))`);
  const originalPlacement = await readMidnightChart();
  assert.equal(originalPlacement.length, 91);
  await first.evaluate(`document.querySelector('[data-legacy-stage="CAMP-AXIS-16"] .archive-placement-toggle input').click()`);
  await waitFor('the old midnight fleet default formation chart', async () => {
    const positions = await readMidnightChart();
    return positions.length === 91 && positions.some((mark, i) => mark !== originalPlacement[i]);
  });
  await first.evaluate(`${button('返回母港')}.click()`);
  await continueExercise(first);
  const commandCount = () => first.evaluate(`JSON.parse(localStorage.getItem(${JSON.stringify(saveKey)}))?.commands?.length ?? 0`);
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

  await first.evaluate(`${button('舰况')}.click()`);
  const shipPortrait = await waitFor('the packaged ship portrait in offline ship status', () => first.evaluate(`(() => {
    const img = Array.from(document.querySelectorAll('.ship-portrait img')).find(item => item.complete && item.naturalWidth > 0);
    return img?.closest('[data-character]')?.dataset.character ?? null;
  })()`));
  await first.evaluate(`${button('母港')}.click()`);
  await waitFor('real return to harbor', () => first.evaluate("Boolean(document.querySelector('.growth-campaign-entry'))"));
  await continueExercise(first);
  const probe = await first.evaluate(sessionProbe);
  assert.equal(probe.origin, origin);
  assert(probe.realtimeVersion);
  assert.equal(probe.version, probe.realtimeVersion);
  assert.equal(probe.savedVersion, probe.realtimeVersion);
  assert.equal(probe.realtimeGunnery, true);
  assert.equal(probe.ownShips, 5);
  assert.equal(probe.tickBefore, 0);
  assert.equal(probe.tickAfter, 360);
  assert.equal(probe.nightExerciseStarted, true);
  assert.equal(probe.historicalCatalogueRows, 16);
  assert.equal(probe.historicalSourceRecords, 11);
  assert.equal(probe.playableAdaptations, 2);
  assert.equal(probe.capeReplay, true);
  assert.equal(probe.channelReplay, true);
  assert.deepEqual(probe.legacyStages, [8, 22, 14, 24, 91]);
  assert(probe.sameReplay && probe.sameRestore, 'Offline replay and saved battle must agree');
  assert(probe.viewport[0] > probe.viewport[1], 'Battle WebView must be landscape');
  await first.evaluate("localStorage.setItem('cas.android-smoke', 'native-webview-origin-persists')");
  detail = { ...probe, touchCancelNoCommand: true, backgroundCancelsGesture: true, shipPortrait,
    harborNavigation: true, historicalStageIds: 32, historicalSourceRecordsRendered: sourceStages.length,
    legacyStagesRendered: legacyStages.length, legacyMidnightFormationSwitch: true,
    kulaGulfDamageRatioRendered: true, offlineLocalAccountRegistered: true };
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
  assert.equal(await openProduct(second, false), saveKey, 'Restart login returns to the same local profile');
  await continueExercise(second);
  const saved = await second.evaluate(`Boolean(localStorage.getItem(${JSON.stringify(saveKey)}))`);
  assert(saved, 'The product should autosave the battle as well as the smoke key');
  const evidence = { ok: true, serial, airplaneMode: true, localStorageSurvivedRestart: true, sameLocalAccountAfterRestart: true, appAutosavePresent: saved, ...detail };
  const out = resolve(evidencePath);
  await mkdir(dirname(out), { recursive: true });
  await writeFile(out, JSON.stringify(evidence, null, 2) + '\n', { flag: 'wx' });
  console.log(evidence);
  console.log(`Android evidence: ${out}`);
} finally { second.close(); }
