import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { openAcademy, signInLocal } from './browser-login.mjs';

const { chromium } = createRequire(import.meta.url)(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const destination = process.env.CAS_ARTIFACTS || fileURLToPath(new URL('../../artifacts/client/story/', import.meta.url));
const url = process.env.CAS_TEST_URL || 'http://127.0.0.1:5175/';
await fs.mkdir(destination, { recursive: true });
const browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });
const page = await browser.newPage({ viewport: { width: 1360, height: 768 }, reducedMotion: 'reduce' });
const errors = [];
const checks = [];
page.on('pageerror', (error) => errors.push(error.stack));
page.setDefaultTimeout(6500);

const button = (name) => page.getByRole('button', { name, exact: true });
const text = (line) => page.getByText(line, { exact: true });
const screenshot = (name) => page.screenshot({ path: `${destination}/${name}.png` });
const q = (op, params = {}) => page.evaluate(async (request) => (await import(performance.getEntriesByType('resource')
  .filter((entry) => entry.name.includes('/src/engine.ts')).at(-1)?.name ?? '/src/engine.ts')).ask(request), { op, ...params });
const observed = () => q('observe');
const step = async () => { await button('推进一秒').click(); return observed(); };
const coach = () => page.getByRole('region', { name: '白汐实操引导' });
const continueDialogue = () => button('继续对话').click();

async function screenPosition(world, point) {
  const box = await page.locator('.battle-map').boundingBox();
  assert(box);
  const ratio = Math.min((box.width - 65) / world.width, (box.height - 42) / world.height);
  return { x: box.x + (box.width - world.width * ratio) / 2 + point.x * ratio, y: box.y + (box.height + world.height * ratio) / 2 - point.y * ratio };
}

async function planRoute(mode, options, speed) {
  await button('编队').click();
  const state = await observed();
  const fleet = state.fleets[0];
  let candidate;
  for (const points of options) {
    if ((await q('preview_route', { fleet: fleet.id, mode, points, speed })).valid) { candidate = points; break; }
  }
  assert(candidate, `No legal ${mode} training route at t=${state.tick}`);
  await button(mode === 'follow' ? '领舰移动' : '同步移动').click();
  if (speed !== undefined) {
    await page.locator('.speed-setting summary').click();
    await page.getByLabel('航速（节）').fill(String(speed));
  }
  for (const point of candidate) {
    const cursor = await screenPosition(state, point);
    await page.mouse.click(cursor.x, cursor.y);
  }
  await text('航线可用').waitFor();
  await button('下达航线').click();
  assert.equal((await observed()).fleets[0].mode, mode);
}

async function dragWeapon(weapon, world, ship, contact) {
  const marker = page.locator(`[data-ship="${ship.id}"] .weapon.${weapon}`);
  const box = await marker.boundingBox();
  assert(box, `Missing ${weapon} badge for ${ship.name}`);
  const anchor = await screenPosition(world, contact);
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await page.mouse.move(anchor.x, anchor.y, { steps: 16 });
  return anchor;
}

async function aimFrom(world, weapon) {
  for (const ship of world.ships.filter((ship) => ship[weapon])) {
    for (const contact of world.contacts) {
      const aim = await q('aim', { ship: ship.id, target: contact.id, weapon });
      if (aim.valid && !aim.friendly) return { ship, contact, aim };
    }
  }
  return null;
}

async function waitForLegalAim(weapon) {
  let world = await observed();
  for (let i = 0; i < 68 && !world.result; i++) {
    if (await aimFrom(world, weapon)) {
      world = await step();
      const shot = await aimFrom(world, weapon);
      if (shot) return { world, ...shot };
    }
    world = await q('step', { seconds: 20 });
  }
  throw new Error(`No legal ${weapon} solution in exercise`);
}

async function waitForWeapon(weapon, issuedTick) {
  const phase = 180 - issuedTick % 180;
  if (phase > 1) await q('step', { seconds: phase - 1 });
  await step();
  if (await coach().getByRole('button', { name: '继续序章' }).isVisible()) return;
  const observedState = await observed();
  assert(observedState.events.some((event) => event.tick >= issuedTick && event.kind === weapon), `No actual ${weapon} launch near t=${issuedTick}`);
}

async function advanceTo(tick) {
  const now = (await observed()).tick;
  if (tick > now + 1) await q('step', { seconds: tick - now - 1 });
  return tick > now ? step() : observed();
}

try {
  await page.goto(url);
  await signInLocal(page, 'cas-story-qa', true);
  const story = page.getByRole('main', { name: '序章：未明的海' });
  if (!await story.isVisible()) await page.getByRole('button', { name: /^序章/ }).click();
  await story.waitFor();
  await page.locator('.prologue-film-strip').waitFor({ timeout: 12_000 });
  await page.waitForFunction(() => +(document.querySelector('.projectile-layer')?.dataset.shells || 0) > 0);
  await screenshot('10-integrated-opening');
  await button('进入舰桥').click();
  await continueDialogue();
  await button('先告诉我，舰队怎么样了？').click();
  const duty = '你先问舰队的状况……这一点倒是和从前一样。五艘驱逐舰仍在等你的命令。';
  await text(duty).waitFor();
  await page.reload();
  await signInLocal(page, 'cas-story-qa');
  if (!await story.isVisible()) await page.getByRole('button', { name: /^序章/ }).click();
  await text(duty).waitFor();
  await continueDialogue(); await continueDialogue();
  await button('接入辅助').click();
  for (let i = 0; i < 5; i++) await continueDialogue();
  await button('帕金斯').click();
  await screenshot('11-integrated-leader');
  await button('任命帕金斯为领舰').click();
  await text('收到。我会替你守住队形，也会提醒你每一个遗漏。').waitFor();
  await continueDialogue(); await continueDialogue();
  checks.push({ actualOpeningShells: true, originalDutyBranchRestored: true, storyLeader: 'IBS-U-USN-PERKINS' });

  await button('前往海图实操').click();
  await coach().waitFor();
  const followPoints = [{ x: 9200, y: 6550 }, { x: 9200, y: 10400 }];
  await planRoute('follow', [followPoints]);
  const gun = await waitForLegalAim('gun');
  await dragWeapon('gun', gun.world, gun.ship, gun.contact);
  await page.waitForFunction(() => document.querySelector('.gesture-tip')?.textContent.includes('门炮可用'));
  await page.mouse.up();
  await page.getByRole('status').filter({ hasText: '已下达炮击' }).waitFor();
  await waitForWeapon('gun', gun.world.tick);
  await button('继续序章').click();
  await button('返回剧情').click();
  for (let i = 0; i < 5; i++) await continueDialogue();

  await button('前往海图实操').click();
  await coach().waitFor();
  await button('编队').click(); await button('领舰移动').click();
  const at = await screenPosition(await observed(), followPoints[0]);
  await page.mouse.click(at.x, at.y);
  await button('取消草稿').click();
  await planRoute('sync', [followPoints, [{ x: 8850, y: 6550 }, { x: 11600, y: 7950 }]]);
  await button('继续序章').click();
  await button('返回剧情').click();
  await continueDialogue(); await continueDialogue();

  await button('前往海图实操').click();
  await coach().waitFor();
  const freshTorpedo = await observed();
  if (!freshTorpedo.fleets[0].points.length && freshTorpedo.tick === 0) await planRoute('follow', [followPoints]);
  const torpedo = await waitForLegalAim('torpedo');
  const anchor = await dragWeapon('torpedo', torpedo.world, torpedo.ship, torpedo.contact);
  const tip = page.locator('.gesture-tip').filter({ hasText: '鱼雷瞄准' });
  await tip.waitFor();
  const center = await screenPosition(torpedo.world, torpedo.ship);
  const before = await tip.locator('strong').textContent();
  let difference;
  for (const delta of [-3, 3, -2, 2, -5, 5]) {
    if ((await q('aim', { ship: torpedo.ship.id, target: torpedo.contact.id, weapon: 'torpedo', heading: (torpedo.aim.heading + delta + 360) % 360 })).valid) { difference = delta; break; }
  }
  assert(difference);
  const rad = difference * Math.PI / 180, dx = anchor.x - center.x, dy = anchor.y - center.y;
  await page.mouse.move(center.x + dx * Math.cos(rad) - dy * Math.sin(rad), center.y + dx * Math.sin(rad) + dy * Math.cos(rad), { steps: 9 });
  assert.notEqual(await tip.locator('strong').textContent(), before);
  await screenshot('12-integrated-torpedo');
  await page.mouse.up();
  await page.getByRole('status').filter({ hasText: '已下达雷击' }).waitFor();
  await waitForWeapon('torpedo', torpedo.world.tick);
  await button('继续序章').click(); await button('返回剧情').click();
  for (let i = 0; i < 3; i++) await continueDialogue();
  await page.locator('.prologue-victory > img').evaluate((img) => img.decode());
  await screenshot('13-integrated-homecoming');
  await button('领取序章奖励').click();
  await story.waitFor({ state: 'hidden' });
  const wallet = page.locator('.growth-wallet');
  await wallet.waitFor();
  const reward = await wallet.innerText();
  assert.match(reward, /2,000/);
  await page.getByRole('button', { name: /^序章/ }).click();
  assert.equal(await button('领取序章奖励').count(), 0);
  await button('返回母港').click();
  assert.equal(await wallet.innerText(), reward);
  checks.push({ actualFollowAndGun: true, actualCancelAndSync: true, adjustedAndActuallyLaunchedTorpedo: true, originalVictoryCg: true, rewardOnce: true });

  if (!process.env.CAS_STORY_ONLY) {
    await openAcademy(page);
    await button('夜战教学').click();
    await coach().waitFor();
    const night = await observed();
    assert.equal(night.variant, 'night-training');
    assert.equal(night.contacts.length, 0);
    await button('编队').click();
    const sea = await screenPosition(night, { x: 9000, y: 9700 });
    await page.mouse.click(sea.x, sea.y);
    await planRoute('follow', [[{ x: 13000, y: 6550 }, { x: 13000, y: 10400 }]], 15);
    await button('开始演习').click();
    await button('暂停演习').click();
    await step();
    const contacted = await advanceTo(360);
    assert.equal(contacted.tick, 360);
    assert(contacted.contacts.some((c) => c.id === 'C05'));
    await page.locator('.roster-ship').filter({ hasText: contacted.ships.find((s) => s.id === 5).name }).click();
    await page.getByRole('combobox', { name: '可见接触' }).selectOption('C05');
    const orderLight = page.getByRole('button', { name: /^下达照明弹/ });
    await orderLight.click();
    await page.getByRole('status').filter({ hasText: '照明弹已下令' }).waitFor();
    const lit = await advanceTo(540);
    assert(lit.events.some((e) => e.kind === 'illumination' && e.tick === 540));
    assert(lit.illuminations.some((mark) => mark.own));
    await screenshot('14-integrated-night-light');
    const litGun = await aimFrom(lit, 'gun');
    assert(litGun);
    await dragWeapon('gun', lit, litGun.ship, litGun.contact);
    await page.waitForFunction(() => document.querySelector('.gesture-tip')?.textContent.includes('门炮可用'));
    await page.mouse.up();
    await page.getByRole('status').filter({ hasText: '已下达炮击' }).waitFor();
    assert((await advanceTo(720)).events.some((event) => event.kind === 'gun' && event.tick > lit.tick));
    const inRange = await advanceTo(770);
    const nightTorpedo = await aimFrom(inRange, 'torpedo');
    assert(nightTorpedo);
    await dragWeapon('torpedo', inRange, nightTorpedo.ship, nightTorpedo.contact);
    await page.locator('.gesture-tip').filter({ hasText: '鱼雷瞄准' }).waitFor();
    await page.mouse.up();
    await page.getByRole('status').filter({ hasText: '已下达雷击' }).waitFor();
    const afterNightAttack = await advanceTo(900);
    assert(afterNightAttack.events.some((e) => e.kind === 'torpedo' && e.tick === 900));
    await button('战情记录').click();
    await coach().getByText('10/10', { exact: true }).waitFor();
    await screenshot('15-integrated-night-complete');
    await button('完成课程').click();
    await button('复习夜战教学').waitFor();
    checks.push({ nightRealRoute: true, contactTick: 360, ownIlluminationTick: 540, ownGunTick: 720, ownTorpedoTick: 900, nightCheckpoints: 10 });
  }
  assert.deepEqual(errors, []);
  await fs.writeFile(`${destination}/browser-story-receipt.json`, JSON.stringify(checks, null, 2));
  console.log(JSON.stringify(checks, null, 2));
} finally { await browser.close(); }
