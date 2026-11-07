import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
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
    window.casUiCues = [];
    document.addEventListener('cas-ui-cue', ({ detail }) => window.casUiCues.push(detail));
  });
  const loads = () => page.evaluate(() => window.casRadioLoads);
  const cues = () => page.evaluate(() => window.casUiCues);
  const lastCue = async () => (await cues()).at(-1);
  const cueError = () => page.evaluate(async () =>
    (await import('/src/audio/click/ClickCues.ts')).playClickCue('error'));
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

  // --- Operation click cues (port of the 0.6.11 synthesized uiCue) ---
  await button('编队').click();
  assert.equal((await lastCue()).kind, 'tap', 'ordinary controls play the tap cue');
  await page.locator('.roster-ship').first().click();
  assert.equal((await lastCue()).kind, 'select', 'picking a ship plays the select cue');
  await cueError();
  assert.equal((await lastCue()).kind, 'error', 'rejected or failed actions play the error cue');
  await button('演习设置').click();
  await page.getByLabel('操作音量').fill('0.25');
  await button('开始新演习').click();
  await page.getByRole('dialog').waitFor({ state: 'hidden' });
  assert.equal((await lastCue()).kind, 'confirm', 'primary actions play the confirm cue');
  await page.waitForFunction(() => Object.entries(localStorage)
    .some(([key, value]) => key.endsWith(':ui-cues') && JSON.parse(value).volume === .25));

  await page.reload();
  await signInLocal(page, 'cas-radio-qa', false);
  await resumeExercise(page);
  const firstReload = await page.evaluate(() => Object.fromEntries(Object.entries(localStorage)));
  const uiKey = Object.keys(firstReload).find((key) => key.endsWith(':ui-cues'));
  assert.deepEqual(JSON.parse(firstReload[uiKey]), { enabled: true, volume: .25 }, 'click-cue volume persists');
  await button('战情记录').click();
  await page.getByRole('checkbox', { name: '操作点击音效' }).uncheck();
  await page.waitForFunction(() => Object.entries(localStorage)
    .some(([key, value]) => key.endsWith(':ui-cues') && JSON.parse(value).enabled === false));
  const quiet = (await cues()).length;
  await button('舰况').click();
  await cueError();
  assert.equal((await cues()).length, quiet, 'switching the click cues off silences them');

  await page.reload();
  await signInLocal(page, 'cas-radio-qa', false);
  await resumeExercise(page);
  const secondReload = await page.evaluate(() => Object.fromEntries(Object.entries(localStorage)));
  assert.deepEqual(JSON.parse(secondReload[uiKey]), { enabled: false, volume: .25 }, 'click-cue switch persists');
  await button('战情记录').click();
  assert(!(await page.getByRole('checkbox', { name: '操作点击音效' }).isChecked()), 'switch stays off after reload');
  const quietReload = (await cues()).length;
  await button('舰况').click();
  assert.equal((await cues()).length, quietReload, 'no cue after reload while the switch stays off');
  await button('战情记录').click();
  await page.getByRole('checkbox', { name: '操作点击音效' }).check();
  await page.getByRole('checkbox', { name: '舰队电台语音' }).check();
  await page.waitForFunction(() => Object.entries(localStorage)
    .some(([key, value]) => key.endsWith(':ui-cues') && JSON.parse(value).enabled === true));
  await button('编队').click();
  const restored = await lastCue();
  assert.equal(restored.kind, 'tap', 're-enabling restores ordinary tap cues');
  assert.ok(Math.abs(restored.level - .25 * .11) < 1e-9, `restored volume drives the gain: ${restored.level}`);

  assert.deepEqual(errors, []);
  const report = { realSeatEvent: started.id, sameCueLoadedOnce: true, nativeBackgroundPaused: true,
    foregroundRespectedManualPause: true, resumedSameClip: true, silentReplay: true, safeReturnToLive: true,
    distinctPacks: ['wows-us', 'wows-jp'], volume: axis.volume, muteStopsPlaying: true,
    clickCues: { tap: true, select: true, error: true, confirm: true, switchSilences: true, persistsAcrossReload: true },
    clickCueVolumeDrivesGain: true };
  await fs.writeFile(out + '/browser-receipt.json', JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
} finally { await browser.close(); }

// --- A formal build must not carry the private faction radio ---
if (!process.env.CAS_SKIP_FORMAL_BUILD) {
  const clientRoot = fileURLToPath(new URL('../', import.meta.url));
  const dist = clientRoot + 'dist/';
  await fs.rm(dist, { recursive: true, force: true });
  const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('VITE_CAS_')));
  await new Promise((resolve, reject) => {
    const child = spawn('npm', ['run', 'build'], { cwd: clientRoot, env, shell: process.platform === 'win32' });
    child.on('exit', (code) => code === 0 ? resolve(undefined) : reject(new Error('formal build exited with ' + code)));
  });
  const offenders = [];
  const walk = async (dir) => {
    for (const entry of await fs.readdir(dir, { withFileTypes: true })) {
      const path = dir + entry.name;
      if (entry.isDirectory()) await walk(path + '/');
      else if (/\.m4a$/i.test(entry.name)) offenders.push(path);
    }
  };
  await walk(dist);
  assert.equal(offenders.length, 0, 'formal build must not carry radio audio: ' + offenders);
  for (const entry of await fs.readdir(dist + 'assets/', { withFileTypes: true })) {
    if (entry.name.endsWith('.js')) {
      const text = await fs.readFile(dist + 'assets/' + entry.name, 'utf8');
      assert.ok(!text.includes('wows-us'), entry.name + ' references the faction radio files');
    }
  }
  console.log(JSON.stringify({ formalBuildClean: true, dist: dist }, null, 2));
}
