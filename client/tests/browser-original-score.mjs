import assert from 'node:assert/strict';
import { mkdtemp, realpath, rm } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';

const { chromium } = createRequire(import.meta.url)(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const root = fileURLToPath(new URL('../', import.meta.url));
const temp = await realpath(tmpdir());
const cache = await mkdtemp(join(temp, 'cas-score-vite-'));
let server;
let browser;
try {
  server = await createServer({ root, cacheDir: cache, server: { host: '127.0.0.1', port: 0 } });
  await server.listen();
  browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });
  const page = await browser.newPage();
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  const audio = page.locator('audio[data-channel="cas-original-score"]');
  const button = (name) => page.getByRole('button', { name, exact: true });
  const state = () => audio.evaluate(media => ({
    track: media.dataset.track, paused: media.paused, time: media.currentTime, ended: media.ended,
    duration: media.duration, volume: media.volume, loop: media.loop, source: media.currentSrc,
  }));
  const waitTrack = (track) => page.waitForFunction(expected => {
    const media = document.querySelector('audio[data-channel="cas-original-score"]');
    return media?.dataset.track === expected && !media.paused && media.currentTime > .08;
  }, track);
  const waitVolume = (target) => page.waitForFunction(expected => {
    const media = document.querySelector('audio[data-channel="cas-original-score"]');
    return media && Math.abs(media.volume - expected) < .008;
  }, target);

  await page.goto(`http://127.0.0.1:${server.httpServer.address().port}/tests/original-score.html`);
  await audio.waitFor({ state: 'attached' });
  assert.equal((await state()).paused, true);
  const observed = [];
  for (const [track, loop] of [['prologue', true], ['maneuver', true], ['engagement', true], ['victory', false], ['defeat', false]]) {
    await button(track).click();
    await waitTrack(track);
    const cue = await state();
    assert.equal(cue.loop, loop);
    assert(cue.duration > 10 && cue.duration < 40, `decoded ${track}: ${cue.duration}`);
    observed.push({ track, loop, duration: cue.duration });
  }
  await audio.evaluate(media => { media.currentTime = media.duration - .10; });
  await page.waitForFunction(() => document.querySelector('audio[data-channel="cas-original-score"]').ended);
  await page.evaluate(() => {
    window.dispatchEvent(new Event('app-background'));
    window.dispatchEvent(new Event('app-foreground'));
  });
  assert.equal((await state()).ended, true, 'a completed ending cue must not replay on foreground');

  await button('engagement').click();
  await waitTrack('engagement');
  await waitVolume(.54 * .92);
  await page.evaluate(() => {
    const radio = new Audio(document.querySelector('audio[data-channel="cas-original-score"]').currentSrc);
    radio.dataset.channel = 'fleet-radio';
    radio.muted = true;
    document.body.append(radio);
    return radio.play();
  });
  await waitVolume(.54 * .92 * .29);
  await page.evaluate(() => document.querySelector('audio[data-channel="fleet-radio"]').pause());
  await waitVolume(.54 * .92);

  await page.evaluate(() => window.dispatchEvent(new Event('app-background')));
  const suspended = await state();
  assert.equal(suspended.paused, true);
  assert.equal(suspended.volume, 0);
  await page.evaluate(() => window.dispatchEvent(new Event('app-foreground')));
  await waitVolume(.54 * .92);
  const resumed = await state();
  assert.equal(resumed.paused, false);
  assert(resumed.time > suspended.time);

  await button('pause/resume').click();
  assert.equal((await state()).paused, true);
  await button('pause/resume').click();
  await waitTrack('engagement');
  await button('low volume').click();
  await waitVolume(.2 * .92);
  await button('mute/unmute').click();
  assert.equal((await state()).paused, true);
  await page.reload();
  await button('prologue').click();
  assert.equal((await state()).paused, true, 'mute preference must survive reload');
  await button('mute/unmute').click();
  await waitTrack('prologue');
  await waitVolume(.2 * .77);
  await button('off').click();
  await page.waitForFunction(() => !document.querySelector('audio[data-channel="cas-original-score"]').hasAttribute('src'));
  assert.deepEqual(errors, []);
  console.log(JSON.stringify({ ok: true, cues: observed, radioDucking: true, pauseAndResume: true,
    noEndingReplay: true, settingsRestored: true, offClearsSource: true }));
} finally {
  await browser?.close();
  await server?.close();
  if (dirname(await realpath(cache)) === temp) await rm(cache, { recursive: true });
}
