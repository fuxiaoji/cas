import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { resumeExercise, signInLocal } from './browser-login.mjs';

const { chromium } = createRequire(import.meta.url)(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const url = process.env.CAS_TEST_URL || 'http://127.0.0.1:5175/';
const out = process.env.CAS_ARTIFACTS || fileURLToPath(new URL('../../artifacts/client/radio/', import.meta.url));
await fs.mkdir(out, { recursive: true });
const browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });
try {
  const page = await browser.newPage({ viewport: { width: 1360, height: 768 } });
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.stack));
  const button = (name) => page.getByRole('button', { name, exact: true });
  const observe = () => page.evaluate(async () =>
    (await import(performance.getEntriesByType('resource').filter((e) => e.name.includes('/src/engine.ts')).at(-1)?.name ?? '/src/engine.ts')).ask({ op: 'observe' }));
  const state = () => page.locator('audio[data-channel=fleet-radio]').evaluate((audio) => ({
    paused: audio.paused, time: audio.currentTime, src: audio.currentSrc, id: audio.dataset.eventId, cue: audio.dataset.voiceCue, volume: audio.volume,
  }));
  const pauseNative = () => page.evaluate(() => window.dispatchEvent(new Event('app-background')));
  const resumeNative = () => page.evaluate(() => window.dispatchEvent(new Event('app-foreground')));
  await page.addInitScript(() => {
    window.casRadioLoads = [];
    document.addEventListener('loadstart', ({ target }) => {
      if (target instanceof HTMLAudioElement && target.dataset.channel === 'fleet-radio' && target.getAttribute('src')) {
        window.casRadioLoads.push({ id: target.dataset.eventId, cue: target.dataset.voiceCue, source: target.getAttribute('src') });
      }
    }, true);
  });
  const loads = () => page.evaluate(() => window.casRadioLoads);
  const waitAudio = (paused) => page.waitForFunction((expected) =>
    document.querySelector('audio[data-channel=fleet-radio]')?.paused === expected, paused);

  await page.goto(url);
  await signInLocal(page, 'cas-radio-qa', true);
  await resumeExercise(page);
  const initial = await observe();
  const started = initial.events.find((event) => event.voiceCue === 'battle_start');
  assert(started, 'The engine did not emit a seat-visible start cue');
  await button('战情记录').click();
  assert(await page.getByRole('checkbox', { name: '舰队电台语音' }).isChecked());
  assert.deepEqual(await loads(), [], 'No voice should load while initial battle is paused');
  await button('开始演习').click();
  await waitAudio(false);
  await page.waitForFunction(() => document.querySelector('audio[data-channel=fleet-radio]').currentTime > .08);
  const allies = await state();
  assert.equal(allies.id, String(started.id));
  assert.equal(allies.cue, started.voiceCue);
  assert.match(allies.src, /wows-us-battle_start-0/);

  await pauseNative();
  await waitAudio(true);
  const backgrounded = await state();
  await page.waitForTimeout(230);
  assert.equal((await state()).time, backgrounded.time);
  await button('暂停演习').click();
  await resumeNative();
  await waitAudio(true); // Foreground alone must not bypass an explicit pause.
  await button('开始演习').click();
  await waitAudio(false);
  await page.waitForFunction((time) => document.querySelector('audio[data-channel=fleet-radio]').currentTime > time + .08, backgrounded.time);
  assert.equal((await state()).id, allies.id);
  await page.waitForFunction(() => document.querySelector('.time strong')?.textContent !== '00:00');
  assert.equal((await loads()).filter((item) => item.id === allies.id).length, 1);

  await button('暂停演习').click();
  await button('重演').click();
  await page.getByRole('slider', { name: '重演时间' }).waitFor();
  assert.equal((await state()).id, undefined);
  await button('开始演习').click();
  await page.waitForTimeout(400);
  assert.equal((await loads()).length, 1, 'Replay reissued a recorded voice cue');
  await button('返回现局').click();
  await page.getByRole('slider', { name: '重演时间' }).waitFor({ state: 'hidden' });
  assert.equal((await loads()).length, 1, 'Returning to the live battle reissued a recorded voice cue');

  await button('演习设置').click();
  await page.getByLabel('所属方').selectOption('axis');
  await page.getByLabel('电台音量').fill('0.5');
  await button('开始新演习').click();
  await page.getByRole('dialog').waitFor({ state: 'hidden' });
  await button('开始演习').click();
  await waitAudio(false);
  const axis = await state();
  assert.match(axis.src, /wows-jp-battle_start-0/);
  assert.equal(axis.volume, .5);
  await button('战情记录').click();
  await page.getByRole('checkbox', { name: '舰队电台语音' }).uncheck();
  await waitAudio(true);
  assert.equal((await state()).id, undefined);
  assert.deepEqual(errors, []);
  const report = { realSeatEvent: started.id, sameCueLoadedOnce: true, nativeBackgroundPaused: true,
    foregroundRespectedManualPause: true, resumedSameClip: true, silentReplay: true, safeReturnToLive: true,
    distinctPacks: ['wows-us', 'wows-jp'], volume: axis.volume, muteStopsPlaying: true };
  await fs.writeFile(out + '/browser-receipt.json', JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
} finally { await browser.close(); }
