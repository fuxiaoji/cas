import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { resumeExercise, signInLocal } from './browser-login.mjs';

const { chromium } = createRequire(import.meta.url)(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const out = process.env.CAS_ARTIFACTS || fileURLToPath(new URL('../../artifacts/client/realtime/', import.meta.url));
const url = process.env.CAS_TEST_URL || 'http://127.0.0.1:5175/';
await fs.mkdir(out, { recursive: true });
const browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });
try {
  const page = await browser.newPage({ viewport: { width: 1360, height: 768 } });
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.stack));
  const button = (name) => page.getByRole('button', { name, exact: true });
  const q = (op, params = {}) => page.evaluate(async (request) =>
    (await import(performance.getEntriesByType('resource').filter((e) => e.name.includes('/src/engine.ts')).at(-1)?.name ?? '/src/engine.ts')).ask(request),
  { op, ...params });
  const stamp = (tick) => String(Math.floor(tick / 60)).padStart(2, '0') + ':' + String(tick % 60).padStart(2, '0');
  async function advance(seconds = 1) {
    const time = (await q('observe')).tick + seconds;
    if (seconds > 1) await q('step', { seconds: seconds - 1 });
    await button('推进一秒').click();
    await page.waitForFunction((expected) => document.querySelector('.time strong')?.textContent === expected, stamp(time));
    return q('observe');
  }
  async function position(point, state) {
    const rect = await page.locator('.battle-map').boundingBox();
    const ratio = Math.min((rect.width - 65) / state.width, (rect.height - 42) / state.height);
    return { x: rect.x + (rect.width - state.width * ratio) / 2 + point.x * ratio,
      y: rect.y + (rect.height + state.height * ratio) / 2 - point.y * ratio };
  }
  async function aimGun(state, ship, target) {
    const icon = page.locator(`[data-ship="${ship.id}"] .gun`);
    const at = await icon.boundingBox();
    assert(at, `No gun marker for ${ship.name}`);
    await page.mouse.move(at.x + at.width / 2, at.y + at.height / 2);
    await page.mouse.down();
    const dest = await position(target, state);
    await page.mouse.move(dest.x, dest.y, { steps: 16 });
    const tip = page.locator('.gesture-tip[data-first-fire-tick]');
    await tip.waitFor();
    assert.match(await tip.innerText(), /预计首炮/);
    return Number(await tip.getAttribute('data-first-fire-tick'));
  }

  await page.goto(url);
  await signInLocal(page, 'cas-realtime-qa', true);
  await resumeExercise(page);
  const initial = await q('observe');
  assert.equal(initial.realtimeGunnery, true, 'A new free exercise should open in realtime mode');
  await button('舰况').click();
  const ship = initial.ships[0];
  const lead = initial.contacts.find((track) => track.id === 'C01');
  const solution = await q('aim', { ship: ship.id, weapon: 'gun', target: lead.id });
  assert(solution.valid && solution.mounts.length > 0);
  const initialBearings = ship.systems.guns.map((mount) => mount.bearing);
  const previewFire = await aimGun(initial, ship, lead);
  assert.equal(previewFire, Math.min(...solution.mounts.map((mount) => mount.readyTick)));
  const turrets = page.locator(`[data-ship="${ship.id}"] .tactical-turret`);
  assert.deepEqual(await turrets.evaluateAll((mounts) => mounts.map((mount) => Number(mount.dataset.bearing))), initialBearings);
  assert.equal(await page.locator('[data-contact] .tactical-turret').count(), 0);
  await page.screenshot({ path: out + '/01-aim-estimate.png' });
  await page.mouse.up();
  const pending = button('取消待发炮击');
  await pending.waitFor();
  assert.equal((await q('observe')).ships.find((s) => s.id === ship.id).gunTarget, lead.id);
  await pending.click();
  await pending.waitFor({ state: 'hidden' });
  assert((await q('report')).events.some((event) => event.kind === 'fire_held' && event.text.includes(ship.name)));

  // Move the formation across the line of sight to give aft mounts a genuine
  // training delay. The route is a fixture; aiming, issuing and cancelling use UI.
  const route = { fleet: initial.fleets[0].id, mode: 'sync', points: [{ x: 6400, y: 11900 }] };
  assert((await q('preview_route', route)).valid);
  await q('route', route);
  const onTurn = await advance(245);
  const turningShip = onTurn.ships.find((s) => s.id === ship.id);
  const turningTarget = onTurn.contacts.find((track) => track.id === lead.id);
  const turningSolution = await q('aim', { ship: ship.id, weapon: 'gun', target: turningTarget.id });
  assert(turningSolution.valid && turningSolution.mounts.some((mount) => mount.turnSeconds > 1), JSON.stringify({ship:turningShip, target:turningTarget, solution:turningSolution}));
  const trainingEta = await aimGun(onTurn, turningShip, turningTarget);
  await page.mouse.up();
  await pending.waitFor();
  const one = await advance();
  const rotatingShip = one.ships.find((s) => s.id === ship.id);
  assert(rotatingShip.systems.guns.some((mount) => mount.training));
  await page.locator('.mount-readiness.turning').first().waitFor();
  assert.deepEqual(await turrets.evaluateAll((mounts) => mounts.map((mount) => Number(mount.dataset.bearing))), rotatingShip.systems.guns.map((mount) => mount.bearing));
  await page.screenshot({ path: out + '/02-training-mounts.png' });

  let launched = one;
  while (!launched.shells.some((shell) => shell.own) && launched.tick < onTurn.tick + 20) launched = await advance();
  const shell = launched.shells.find((round) => round.own);
  assert(shell && shell.launchTick < 360 && shell.impactTick > shell.launchTick && shell.arcHeightM > 0);
  assert(launched.events.some((event) => event.kind === 'gun' && event.text.includes(ship.name)));
  const loading = page.locator('.mount-readiness.loading').first();
  await loading.waitFor();
  assert.match(await loading.innerText(), /装填 \d+ 秒/);
  await page.screenshot({ path: out + '/03-launch-and-reload.png' });
  const middle = await advance(Math.ceil((shell.impactTick - shell.launchTick) / 2));
  assert(middle.shells.some((round) => round.id === shell.id && round.progress > 0 && round.progress < 1));
  await page.screenshot({ path: out + '/04-ballistic-flight.png' });
  let at = middle;
  if (at.tick < shell.impactTick) at = await advance(shell.impactTick - at.tick);
  assert(!at.shells.some((round) => round.id === shell.id));
  assert.equal(at.ships.find((s) => s.id === ship.id).gunTarget, undefined);

  await button('演习设置').click();
  await page.getByLabel('所属方').selectOption('axis');
  await button('开始新演习').click();
  await page.getByRole('dialog').waitFor({ state: 'hidden' });
  await button('战术 AI').click();
  await page.getByLabel('AI 风格').selectOption('torpedo');
  await page.getByLabel('指挥权限').selectOption('auto');
  let longWake;
  for (let i = 0; i < 150; i++) {
    const state = await q('step', { seconds: 16 });
    longWake = state.torpedoes.find((torpedo) => torpedo.own && torpedo.trail?.length >= 2 &&
      Math.hypot(torpedo.x - torpedo.trail[0].x, torpedo.y - torpedo.trail[0].y) > 850);
    if (longWake || state.result) break;
  }
  assert(longWake, 'The real exercise did not emit a torpedo wake');
  const after = await advance();
  const actual = after.torpedoes.find((torpedo) => torpedo.id === longWake.id);
  assert.deepEqual(actual.trail[0], longWake.trail[0]);
  const canvas = page.locator('.projectile-layer');
  assert(Number(await canvas.getAttribute('data-torpedo-trails')) > 0);
  const center = await position({ x: (actual.x + actual.trail[0].x) / 2, y: (actual.y + actual.trail[0].y) / 2 }, after);
  assert(await canvas.evaluate((el, at) => {
    const rect = el.getBoundingClientRect();
    const ratio = el.width / rect.width;
    const pixels = el.getContext('2d').getImageData(Math.round((at.x - rect.x) * ratio) - 3, Math.round((at.y - rect.y) * ratio) - 3, 7, 7).data;
    return pixels.some((value, index) => index % 4 === 3 && value > 90 && pixels[index - 2] > pixels[index - 1]);
  }, center), 'The canvas did not paint the middle of the visible torpedo wake');
  await page.screenshot({ path: out + '/05-torpedo-long-wake.png' });
  assert(after.torpedoes.filter((torpedo) => !torpedo.own).every((torpedo) => !torpedo.from));
  assert.deepEqual(errors, []);
  const receipt = { previewFire, cancelledBeforeFire: true, trainingEta, trainingTick: one.tick,
    actualFirstFire: shell.launchTick, impact: shell.impactTick, arcHeightM: shell.arcHeightM,
    visibleWake: actual.trail, hiddenLaunchOriginsExcluded: true };
  await fs.writeFile(out + '/browser-receipt.json', JSON.stringify(receipt, null, 2));
  console.log(JSON.stringify(receipt, null, 2));
} finally { await browser.close(); }
