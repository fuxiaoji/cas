import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { resumeExercise, signInLocal } from './browser-login.mjs';

const { chromium } = createRequire(import.meta.url)(process.env.CAS_PLAYWRIGHT_MODULE || 'playwright');
const url = process.env.CAS_TEST_URL || 'http://127.0.0.1:5175/';
const out = process.env.CAS_ARTIFACTS || fileURLToPath(new URL('../../artifacts/client/radio/', import.meta.url));
const archiveLedgerPath = fileURLToPath(new URL('../src/audio/archive/ledger.json', import.meta.url));
const archiveLedger = JSON.parse(await fs.readFile(archiveLedgerPath, 'utf8'));
const scoreLedgerPath = fileURLToPath(new URL('../src/audio/score/ledger.json', import.meta.url));
const scoreLedger = JSON.parse(await fs.readFile(scoreLedgerPath, 'utf8'));
await fs.mkdir(out, { recursive: true });

const sha256 = async (path) => crypto.createHash('sha256').update(await fs.readFile(path)).digest('hex');
for (const track of scoreLedger.tracks) {
  const path = fileURLToPath(new URL('../src/audio/score/' + track.file, import.meta.url));
  const stat = await fs.stat(path);
  assert.equal(stat.size, track.bytes, 'score ledger byte count matches ' + track.file);
  assert.equal(await sha256(path), track.sha256, 'score ledger sha256 matches ' + track.file);
}
assert.deepEqual(scoreLedger.tracks.map((track) => track.cue), ['prologue', 'maneuver', 'engagement', 'victory', 'defeat'],
  'score ledger carries the five scene cues');
for (const asset of archiveLedger.assets) {
  const path = fileURLToPath(new URL('../src/audio/archive/' + asset.path, import.meta.url));
  const stat = await fs.stat(path);
  assert.equal(stat.size, asset.bytes, 'archive ledger byte count matches ' + asset.path);
  assert.equal(await sha256(path), asset.sha256, 'archive ledger sha256 matches ' + asset.path);
  assert.equal(asset.sha256, asset.source_sha256, 'archive copy is byte-identical to its registered source: ' + asset.path);
  assert(!asset.synthetic, 'archive assets are never tagged synthetic: ' + asset.path);
}
for (const asset of archiveLedger.synthetic_assets) {
  const path = fileURLToPath(new URL('../src/audio/synthetic/' + asset.path, import.meta.url));
  const stat = await fs.stat(path);
  assert.equal(stat.size, asset.bytes, 'synthetic ledger byte count matches ' + asset.path);
  assert.equal(await sha256(path), asset.sha256, 'synthetic ledger sha256 matches ' + asset.path);
  assert.equal(asset.synthetic, true, 'synthetic asset is explicitly tagged: ' + asset.path);
  assert.equal(asset.kind, 'synthetic_ui', 'synthetic asset kind is synthetic_ui: ' + asset.path);
  assert.equal(asset.match, 'synthetic', 'synthetic asset match is not exact/semantic: ' + asset.path);
  assert.equal(asset.source_sha256, null, 'synthetic asset has no archive source hash: ' + asset.path);
  assert.equal(asset.source_path, null, 'synthetic asset has no archive source path: ' + asset.path);
  assert(asset.flags.includes('not_archive_original'), 'synthetic asset is flagged not_archive_original: ' + asset.path);
}
assert.equal(archiveLedger.assets.length, 56, 'archive ledger has the 56 registered archive clips');
assert.equal(archiveLedger.synthetic_assets.length, 2, 'synthetic ledger has the two UI fire-control lines');
assert.deepEqual(new Set(archiveLedger.assets.map((a) => a.event)), new Set([
  'battle_start', 'contact', 'torpedo_warning', 'hit', 'torpedo_hit', 'damage', 'enemy_sunk',
  'fire', 'friendly_fire', 'exposed', 'autopilot', 'manual_fire', 'casualty',
]), 'archive ledger covers every required battle event');
assert.deepEqual(archiveLedger.events.own_sunk.bound, [], 'own_sunk has no exact archive line');
assert(archiveLedger.blockers.some((item) => item.event === 'own_sunk'), 'own_sunk blocker is recorded');
assert(archiveLedger.blockers.some((item) => item.event === 'damage' && item.variant === 'control'),
  'damage-control blocker is recorded');
assert.equal(archiveLedger.events.damage.bound.includes('allies:control-fire (synthetic UI)'), true,
  'damage ledger records the synthetic fire-control line');
assert.equal(archiveLedger.events.damage.bound.includes('axis:control-flood (closest archive flood alias)'), true,
  'damage ledger records the approximate flood-control alias');

const browser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });
try {
  const page = await browser.newPage({ viewport: { width: 1360, height: 768 } });
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.stack));
  const button = (name) => page.getByRole('button', { name, exact: true });
  const ask = (request) => page.evaluate(async (request) =>
    (await import(performance.getEntriesByType('resource').filter((e) => e.name.includes('/src/engine.ts')).at(-1)?.name ?? '/src/engine.ts')).ask(request), request);
  const observe = () => ask({ op: 'observe' });
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
  const waitCue = async (cue, count = 1) => {
    await page.waitForFunction(({ cue, count }) =>
      window.casRadioLoads.filter((item) => item.cue === cue).length >= count,
    { cue, count }, { timeout: 20000 });
    return (await loads()).filter((item) => item.cue === cue).at(-1);
  };
  const position = async (point, state) => {
    const rect = await page.locator('.battle-map').boundingBox();
    const ratio = Math.min((rect.width - 65) / state.width, (rect.height - 42) / state.height);
    return { x: rect.x + (rect.width - state.width * ratio) / 2 + point.x * ratio,
      y: rect.y + (rect.height + state.height * ratio) / 2 - point.y * ratio };
  };
  const aimGun = async (state, ship, target) => {
    const icon = page.locator(`[data-ship="${ship.id}"] .gun`);
    const at = await icon.boundingBox();
    assert(at, `No gun marker for ${ship.name}`);
    await page.mouse.move(at.x + at.width / 2, at.y + at.height / 2);
    await page.mouse.down();
    const dest = await position(target, state);
    await page.mouse.move(dest.x, dest.y, { steps: 16 });
    await page.locator('.gesture-tip[data-first-fire-tick]').waitFor();
  };

  await page.goto(url);
  await signInLocal(page, 'cas-radio-qa', true);
  await resumeExercise(page);
  const initial = await observe();
  const started = initial.events.find((event) => event.voiceCue === 'battle_start');
  assert(started, 'The engine did not emit a seat-visible start cue');

  // --- Archived crew radio: ledger, resolver and actual decode/playback ---
  const archiveApi = await page.evaluate(async ({ assets, synthetic }) => {
    const { archiveClip, archiveClips, syntheticClip, localClip, archiveFiles, syntheticFiles } =
      await import('/src/audio/localRadioClips.ts');
    const resolved = assets.map(({ event, seat, variant, path }) => ({
      path, urls: archiveClips(seat, event, variant),
    }));
    const syntheticResolved = synthetic.map(({ event, seat, variant, path }) => ({
      path, url: syntheticClip(seat, event, variant),
    }));
    return {
      files: archiveFiles,
      syntheticFiles,
      resolved,
      syntheticResolved,
      genericWarning: archiveClip('allies', 'torpedo_warning') ?? null,
      axisGunDamage: archiveClip('axis', 'damage', 'gun') ?? null,
      controlFireArchive: archiveClip('allies', 'damage', 'control-fire') ?? null,
      controlFloodArchive: archiveClip('allies', 'damage', 'control-flood') ?? null,
      genericControlArchive: archiveClip('allies', 'damage', 'control') ?? null,
      fireOpenArchive: archiveClip('allies', 'fire', 'open') ?? null,
      fireOpenFallback: localClip('allies', 'fire') ?? null,
      fireOpenAxisFallback: localClip('axis', 'fire') ?? null,
      exposedAllies: archiveClips('allies', 'exposed').length,
      exposedAxis: archiveClips('axis', 'exposed').length,
      autopilotAllies: [archiveClips('allies', 'autopilot', 'on').length, archiveClips('allies', 'autopilot', 'off').length],
      autopilotAxis: [archiveClips('axis', 'autopilot', 'on').length, archiveClips('axis', 'autopilot', 'off').length],
      manualAllies: archiveClips('allies', 'manual_fire').length,
      manualAxis: archiveClips('axis', 'manual_fire').length,
      winningAllies: archiveClips('allies', 'casualty', 'winning').length,
      winningAxis: archiveClips('axis', 'casualty', 'winning').length,
      losingAllies: archiveClips('allies', 'casualty', 'losing').length,
      losingAxis: archiveClips('axis', 'casualty', 'losing').length,
      syntheticAllies: syntheticClip('allies', 'damage', 'control-fire') ?? null,
      syntheticAxis: syntheticClip('axis', 'damage', 'control-fire') ?? null,
      syntheticWrongCue: syntheticClip('allies', 'damage', 'flood') ?? null,
    };
  }, {
    assets: archiveLedger.assets.map(({ event, seat, variant, path }) => ({ event, seat, variant, path })),
    synthetic: archiveLedger.synthetic_assets.map(({ event, seat, variant, path }) => ({ event, seat, variant, path })),
  });
  assert.equal(archiveApi.files.length, archiveLedger.assets.length, 'every ledgered archive WAV is packed');
  assert.equal(archiveApi.syntheticFiles.length, archiveLedger.synthetic_assets.length,
    'every synthetic UI WAV is packed separately');
  for (const item of archiveApi.resolved) {
    assert(item.urls.length, 'archive resolver returned at least one URL for ' + item.path);
    assert(item.urls.some((url) => url.endsWith('/archive/' + item.path)),
      'archive resolver returned ' + item.path + ': ' + item.urls.join(', '));
  }
  for (const item of archiveApi.syntheticResolved) {
    assert(item.url, 'synthetic resolver returned a URL for ' + item.path);
    assert(item.url.endsWith('/synthetic/' + item.path),
      'synthetic resolver returned ' + item.path + ': ' + item.url);
  }
  assert.equal(archiveApi.genericWarning, null,
    'a bearing-less torpedo warning must not guess a direction');
  assert.equal(archiveApi.axisGunDamage, null,
    'the unbound Japanese generic gun-damage variant must fall through');
  assert.match(archiveApi.controlFireArchive, /archive\/allies-fire-damage-0\.wav$/,
    'control-fire aliases to the closest registered fire report');
  assert.match(archiveApi.controlFloodArchive, /archive\/allies-damage-flood-0\.wav$/,
    'control-flood aliases to the closest registered flood report');
  assert.equal(archiveApi.genericControlArchive, null,
    'a generic control report must not be bound to an archive fire or flood line');
  assert.equal(archiveApi.fireOpenArchive, null,
    'there is no archive open-fire line to bind');
  assert.match(archiveApi.fireOpenFallback, /assets\/wows-us-fire-0\.m4a$/,
    'the allies fire-open variant falls back to the original m4a');
  assert.match(archiveApi.fireOpenAxisFallback, /assets\/wows-jp-fire-0\.m4a$/,
    'the axis fire-open variant falls back to the original m4a');
  assert.deepEqual({
    exposed: [archiveApi.exposedAllies, archiveApi.exposedAxis],
    autopilot: [archiveApi.autopilotAllies, archiveApi.autopilotAxis],
    manual: [archiveApi.manualAllies, archiveApi.manualAxis],
    winning: [archiveApi.winningAllies, archiveApi.winningAxis],
    losing: [archiveApi.losingAllies, archiveApi.losingAxis],
  }, {
    exposed: [2, 1], autopilot: [[1, 1], [1, 1]], manual: [2, 2],
    winning: [5, 2], losing: [1, 1],
  }, 'randomised cue pools match the ledger');
  assert.match(archiveApi.syntheticAllies, /synthetic\/damage-control-fire-en\.wav$/);
  assert.match(archiveApi.syntheticAxis, /synthetic\/damage-control-fire-zh\.wav$/);
  assert.equal(archiveApi.syntheticWrongCue, null, 'synthetic UI line is limited to control-fire');

  const directions = await page.evaluate(async () => {
    const { directionFor } = await import('/src/audio/BattleVoice.ts');
    const ship = { x: 0, y: 0, heading: 0 };
    const event = (x, y) => ({ tick: 0, kind: 'torpedo_detected', text: '', x, y });
    return {
      front: directionFor(event(0, 100), [ship]),
      starboard: directionFor(event(100, 0), [ship]),
      astern: directionFor(event(0, -100), [ship]),
      port: directionFor(event(-100, 0), [ship]),
      noCoordinate: directionFor({ tick: 0, kind: 'torpedo_detected', text: '' }, [ship]) ?? null,
      noShip: directionFor(event(0, 100), []) ?? null,
    };
  });
  assert.deepEqual(directions, {
    front: 'front', starboard: 'starboard', astern: 'astern', port: 'port',
    noCoordinate: null, noShip: null,
  }, 'seat-visible bearing selects the matching directional warning');

  const variants = await page.evaluate(async () => {
    const { variantFor, derivedCue, chooseClip, casualtyVariant } = await import('/src/audio/BattleVoice.ts');
    const ship = { x: 0, y: 0, heading: 0 };
    const contacts = [
      { id: 'C01', x: 100, y: 0, heading: 0, speed: 10, kind: 'dd' },
      { id: 'C02', x: -5000, y: 0, heading: 0, speed: 10, kind: 'ca' },
      { id: 'C03', x: 0, y: 8000, heading: 0, speed: 10, kind: 'bb' },
      { id: 'C04', x: 9000, y: 0, heading: 0, speed: 10, kind: 'cv' },
      { id: 'C05', x: -9000, y: -9000, heading: 0, speed: 10, kind: 'unknown' },
    ];
    const event = (kind, text, extra = {}) => ({ tick: 0, kind, text, ...extra });
    const fire = (kind, text) => ({ tick: 0, kind, text, voiceCue: 'fire' });
    return {
      warning: variantFor(event('torpedo_detected', '', { x: 100, y: 0, voiceCue: 'torpedo_warning' }), [ship], contacts),
      torpedoDamage: variantFor(event('damage', '扶桑 中雷受损 12.0 DP', { voiceCue: 'damage' }), [ship], contacts),
      gunDamage: variantFor(event('damage', '扶桑 中弹受损 12.0 DP', { voiceCue: 'damage' }), [ship], contacts),
      fireDamage: variantFor(fire('critical', '扶桑 · 起火 · 严重度 12%'), [ship], contacts),
      fireOpenGun: variantFor(fire('gun', '扶桑 · 中射程，8 门主炮实际发射'), [ship], contacts),
      fireOpenTorpedo: variantFor(fire('torpedo', '扶桑 发射 8 枚九三式直航鱼雷'), [ship], contacts),
      turret: variantFor(event('critical', '扶桑 · 主炮座 2 失效'), [ship], contacts),
      turretMagazine: variantFor(event('critical', '扶桑 · 主炮弹药库爆炸'), [ship], contacts),
      flood: variantFor(event('critical', '扶桑 · 进水 · 严重度 8%'), [ship], contacts),
      controlFire: variantFor(event('critical', '扶桑 · 火灾损管 · 严重度 -8%'), [ship], contacts),
      controlFireWorse: variantFor(event('critical', '扶桑 · 火灾损管 · 严重度 +8%'), [ship], contacts),
      controlFlood: variantFor(event('critical', '扶桑 · 进水损管 · 严重度 -8%'), [ship], contacts),
      contactDd: variantFor(event('contact', '发现夜间水面接触 C01', { x: 100, y: 0, voiceCue: 'contact' }), [ship], contacts),
      contactCa: variantFor(event('contact', '发现夜间水面接触 C02', { x: -5000, y: 0, voiceCue: 'contact' }), [ship], contacts),
      contactBb: variantFor(event('contact', '发现夜间水面接触 C03', { x: 0, y: 8000, voiceCue: 'contact' }), [ship], contacts),
      contactCv: variantFor(event('contact', '发现夜间水面接触 C04', { x: 9000, y: 0, voiceCue: 'contact' }), [ship], contacts),
      contactUnknown: variantFor(event('contact', '发现夜间水面接触 C05', { x: -9000, y: -9000, voiceCue: 'contact' }), [ship], contacts) ?? null,
      contactNoCoordinate: variantFor(event('contact', '发现夜间水面接触', { voiceCue: 'contact' }), [ship], contacts) ?? null,
      friendlyFire: variantFor(event('torpedo_hit', '友舰误中 2 枚鱼雷', { voiceCue: 'friendly_fire' }), [ship], contacts) ?? null,
      hit: variantFor(event('hit', '可见接触受到炮弹命中', { voiceCue: 'hit' }), [ship], contacts) ?? null,
      derived: [
        derivedCue(event('critical', '扶桑 · 主炮座 2 失效')),
        derivedCue(event('critical', '扶桑 · 进水 · 严重度 8%')),
        derivedCue(event('critical', '扶桑 · 火灾损管 · 严重度 -8%')),
        derivedCue(fire('critical', '扶桑 · 起火 · 严重度 12%')),
      ],
      random: [
        chooseClip(['a', 'b', 'c'], 'a', () => 0),
        chooseClip(['a', 'b'], undefined, () => 0.99),
        chooseClip([], undefined) ?? null,
      ],
      casualty: [casualtyVariant(3, 1), casualtyVariant(1, 3), casualtyVariant(1, 0) ?? null],
    };
  });
  assert.deepEqual(variants, {
    warning: 'starboard', torpedoDamage: 'torpedo', gunDamage: 'gun',
    fireDamage: 'damage', fireOpenGun: 'open', fireOpenTorpedo: 'open',
    turret: 'turret', turretMagazine: 'turret', flood: 'flood',
    controlFire: 'control-fire', controlFireWorse: 'control', controlFlood: 'control-flood',
    contactDd: 'dd', contactCa: 'cl', contactBb: 'bb', contactCv: 'cv',
    contactUnknown: null, contactNoCoordinate: null,
    friendlyFire: null, hit: null,
    derived: ['damage', 'damage', 'damage', 'fire'],
    random: ['b', 'b', null],
    casualty: ['winning', 'losing', null],
  }, 'cue text, kind and nearest contact select the registered archive variant');

  const playbackUrls = [...new Set([
    ...archiveApi.resolved.flatMap((item) => item.urls),
    ...archiveApi.syntheticResolved.map((item) => item.url),
  ])];
  const audioPlayback = await page.evaluate(async (urls) => {
    const results = [];
    for (const url of urls) {
      const audio = new Audio(url);
      audio.volume = 0.01;
      await new Promise((resolve, reject) => {
        audio.addEventListener('loadedmetadata', resolve, { once: true });
        audio.addEventListener('error', () => reject(new Error('load failed: ' + url)), { once: true });
        audio.load();
      });
      await audio.play();
      await new Promise((resolve) => setTimeout(resolve, 100));
      results.push({ url, duration: audio.duration, time: audio.currentTime });
      audio.pause();
    }
    return results;
  }, playbackUrls);
  const archivePlayback = audioPlayback.filter((item) => item.url.includes('/archive/'));
  const syntheticPlayback = audioPlayback.filter((item) => item.url.includes('/synthetic/'));
  assert.equal(archivePlayback.length, archiveLedger.assets.length, 'every archive take was actually played');
  assert.equal(syntheticPlayback.length, archiveLedger.synthetic_assets.length, 'every synthetic UI take was actually played');
  for (const item of audioPlayback) {
    assert(item.duration > .8, 'voice clip decodes with a real duration: ' + item.url + ' ' + item.duration);
    assert(item.time > 0, 'voice clip actually advances during playback: ' + item.url);
  }

  const scorePlayback = await page.evaluate(async (files) => {
    const results = [];
    for (const file of files) {
      const audio = new Audio('/src/audio/score/' + file);
      audio.volume = 0.01;
      await new Promise((resolve, reject) => {
        audio.addEventListener('loadedmetadata', resolve, { once: true });
        audio.addEventListener('error', () => reject(new Error('score load failed: ' + file)), { once: true });
        audio.load();
      });
      await audio.play();
      await new Promise((resolve) => setTimeout(resolve, 100));
      results.push({ file, duration: audio.duration, time: audio.currentTime, src: audio.currentSrc });
      audio.pause();
    }
    return results;
  }, scoreLedger.tracks.map((track) => track.file));
  for (const item of scorePlayback) {
    const expected = scoreLedger.tracks.find((track) => track.file === item.file);
    assert(Math.abs(item.duration - expected.duration_s) < .25,
      `score cue ${item.file} decodes near its ledgered ${expected.duration_s}s: ${item.duration}`);
    assert(item.time > 0, 'score cue actually advances during playback: ' + item.file);
  }

  await button('战情记录').click();
  assert(await page.getByRole('checkbox', { name: '舰队电台语音' }).isChecked());
  assert.deepEqual(await loads(), [], 'No voice should load while initial battle is paused');
  await button('开始演习').click();
  await waitAudio(false);
  await page.waitForFunction(() => document.querySelector('audio[data-channel=fleet-radio]').currentTime > .08);
  const allies = await state();
  assert.equal(allies.id, String(started.id));
  assert.equal(allies.cue, started.voiceCue);
  assert.match(allies.src, /archive\/allies-battle_start-0/, 'auto pack plays the archived battle_start clip');

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
  assert.match(axis.src, /archive\/axis-battle_start-0/, 'axis auto pack plays the archived Japanese battle_start clip');
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
  await page.getByLabel('语音包').selectOption('al-enterprise');
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
  const radioKeyStored = Object.keys(firstReload).find((key) => key.endsWith(':fleet-radio'));
  assert.deepEqual(JSON.parse(firstReload[uiKey]), { enabled: true, volume: .25 }, 'click-cue volume persists');
  assert.equal(JSON.parse(firstReload[radioKeyStored]).pack, 'al-enterprise', 'voice pack choice persists');
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

  // --- Personal commander pack on a fresh seat battle ---
  await button('演习设置').click();
  await page.getByLabel('语音包').waitFor();
  assert.equal(await page.getByLabel('语音包').inputValue(), 'al-enterprise');
  await page.screenshot({ path: out + '/settings-voice-pack.png' });
  await button('开始新演习').click();
  await page.getByRole('dialog').waitFor({ state: 'hidden' });
  await button('开始演习').click();
  await waitAudio(false);
  const commander = await state();
  assert.equal(commander.cue, 'battle_start');
  assert.match(commander.src, /al-enterprise-battle_start-0/);
  await page.screenshot({ path: out + '/commander-battle-start.png' });
  await page.waitForFunction(() => document.querySelector('audio[data-channel=cas-original-score]').volume < .2,
    undefined, { timeout: 5000 });
  const ducked = await page.locator('audio[data-channel=cas-original-score]').evaluate((media) => media.volume);
  // End the clip early so the score's return to its own level is observable fast.
  await page.locator('audio[data-channel=fleet-radio]').evaluate((media) => {
    media.currentTime = Math.max(0, media.duration - .15);
  });
  await page.waitForFunction(() => {
    const media = document.querySelector('audio[data-channel=cas-original-score]');
    const gain = { prologue: .77, maneuver: .63, engagement: .92, victory: .8, defeat: .76 }[media?.dataset.track];
    return !!gain && Math.abs(media.volume - .54 * gain) < .01;
  }, undefined, { timeout: 20000 });
  assert.equal((await loads()).filter((item) => item.id === commander.id).length, 1, 'commander battle_start loaded once');

  const liveScore = await page.locator('audio[data-channel=cas-original-score]').evaluate((media) => ({
    track: media.dataset.track, src: media.currentSrc, duration: media.duration, paused: media.paused,
  }));
  assert(['maneuver', 'engagement'].includes(liveScore.track), 'live score uses a battle scene: ' + liveScore.track);
  assert(liveScore.src.includes('/' + liveScore.track + '.ogg'), 'live score plays the ledgered file: ' + liveScore.src);
  assert(liveScore.duration > 40, 'live score loop is at least 40 s: ' + liveScore.duration);
  assert.equal(liveScore.paused, false, 'live score is actually playing after the voice clip');

  // --- Player-only trigger cues: autopilot, manual gun order, exposure ---
  // A reload clears the long replay/settings transcript and leaves the fresh
  // trigger section on a clean React battle state.
  await page.reload();
  await signInLocal(page, 'cas-radio-qa', false);
  await resumeExercise(page);
  await button('演习设置').click();
  await page.getByLabel('演习时段').selectOption('');
  await page.getByLabel('所属方').selectOption('allies');
  await button('开始新演习').click();
  await page.getByRole('dialog').waitFor({ state: 'hidden' });
  await button('开始演习').click();
  await waitAudio(false);

  // The manual gun order must run before the autopilot toggle: switching to
  // auto makes the AI issue gun orders, and a pending order removes the manual
  // weapon badge (can_gun) for the rest of that battle.
  await button('舰况').click();
  const firing = await observe();
  assert(firing.contacts.length, 'manual fire trigger needs a visible contact');
  await page.waitForFunction(() => document.querySelectorAll('.map-ship .gun').length > 0,
    undefined, { timeout: 15000 });
  const gunnerId = Number(await page.locator('.map-ship .gun').first().evaluate((el) =>
    el.closest('.map-ship')?.getAttribute('data-ship')));
  const firingShip = firing.ships.find((ship) => ship.id === gunnerId);
  assert(firingShip, 'the rendered gun badge belongs to a visible own ship');
  const firingTarget = firing.contacts[0];
  await aimGun(firing, firingShip, firingTarget);
  await page.mouse.up();
  const manual = await waitCue('manual_fire');
  assert.match(manual.source, /allies-manual_fire-[01]\.wav/,
    'a player gun order plays a random archived fire-order line');

  const autopilotBefore = (await loads()).filter((item) => item.cue === 'autopilot').length;
  await button('战术 AI').click();
  await page.getByLabel('指挥权限').selectOption('auto');
  const autopilotOn = await waitCue('autopilot', autopilotBefore + 1);
  assert.match(autopilotOn.source, /allies-autopilot-on-0\.wav/,
    'switching to auto plays the archived autopilot-on line');
  await page.getByLabel('指挥权限').selectOption('manual');
  const autopilotOff = await waitCue('autopilot', autopilotBefore + 2);
  assert.match(autopilotOff.source, /allies-autopilot-off-0\.wav/,
    'switching back to manual plays the archived autopilot-off line');
  await page.waitForTimeout(400);
  assert.equal((await loads()).filter((item) => item.cue === 'manual_fire').length, 1,
    'AI auto fire must not replay the player manual fire-order cue');

  // Night searchlight is the player-only exposure path. Fast-forward the
  // authoritative engine while paused, then step once through the UI so the
  // observation (and the player command) sees the contact.
  await button('演习设置').click();
  await page.getByLabel('演习时段').selectOption('night');
  await page.getByLabel('所属方').selectOption('allies');
  await button('开始新演习').click();
  await page.getByRole('dialog').waitFor({ state: 'hidden' });
  await button('开始演习').click();
  await waitAudio(false);
  await button('暂停演习').click();
  await waitAudio(true);
  const opening = await observe();
  const route = { fleet: opening.fleets[0].id, mode: 'sync', speed: 26, points: [{ x: 16000, y: 6550 }] };
  assert((await ask({ op: 'preview_route', ...route })).valid, 'the night approach route must be valid');
  await ask({ op: 'route', ...route });
  let night;
  for (let attempt = 0; attempt < 40; attempt++) {
    night = await ask({ op: 'step', seconds: 16 });
    if (night.contacts.length) break;
  }
  assert(night.contacts.length, 'the night exercise did not establish a contact');
  await button('推进一秒').click();
  await page.waitForFunction(() => document.querySelector('.time strong')?.textContent !== '00:00');
  await button('开始演习').click();
  await waitAudio(false);
  await button('舰况').click();
  const nightState = await observe();
  assert(nightState.contacts.length, 'the night contact disappeared before the light order');
  const litContact = nightState.contacts[0];
  const exposedBefore = (await loads()).filter((item) => item.cue === 'exposed').length;
  await page.getByLabel('照亮接触').selectOption(litContact.id);
  await button('开启探照灯').click();
  const exposed = await waitCue('exposed', exposedBefore + 1);
  assert.match(exposed.source, /allies-exposed-[01]\.wav/,
    'switching a searchlight on plays a random exact exposure line');

  assert.deepEqual(errors, []);
  const report = { realSeatEvent: started.id, sameCueLoadedOnce: true, nativeBackgroundPaused: true,
    foregroundRespectedManualPause: true, resumedSameClip: true, silentReplay: true, safeReturnToLive: true,
    distinctPacks: ['wows-us', 'wows-jp'], volume: axis.volume, muteStopsPlaying: true,
    archive: {
      ledgerClips: archiveLedger.assets.length,
      syntheticClips: archiveLedger.synthetic_assets.length,
      resolverCovered: archiveApi.resolved.length,
      playbackPlayed: archivePlayback.length,
      syntheticPlaybackPlayed: syntheticPlayback.length,
      playbackMinDuration: Math.min(...archivePlayback.map((item) => item.duration)),
      playbackMaxDuration: Math.max(...archivePlayback.map((item) => item.duration)),
      directionalBearingTest: true,
      fireDamageVariant: true, fireOpenVariant: true, turretVariant: true, floodVariant: true,
      controlFireVariant: true, controlFloodVariant: true, contactClassVariants: true,
      friendlyFireVariant: true, randomNoImmediateRepeat: true, casualtyThresholds: true,
      genericControlUnbound: true, fireOpenFallback: archiveApi.fireOpenFallback,
      controlFireArchive: archiveApi.controlFireArchive,
      controlFloodArchive: archiveApi.controlFloodArchive,
      syntheticAllies: archiveApi.syntheticAllies,
      syntheticAxis: archiveApi.syntheticAxis,
      pools: {
        exposed: [archiveApi.exposedAllies, archiveApi.exposedAxis],
        autopilot: [archiveApi.autopilotAllies, archiveApi.autopilotAxis],
        manualFire: [archiveApi.manualAllies, archiveApi.manualAxis],
        casualtyWinning: [archiveApi.winningAllies, archiveApi.winningAxis],
        casualtyLosing: [archiveApi.losingAllies, archiveApi.losingAxis],
      },
      ownSunkBlocker: archiveLedger.blockers.some((item) => item.event === 'own_sunk'),
      damageControlBlocker: archiveLedger.blockers.some((item) => item.event === 'damage' && item.variant === 'control'),
      autoAlliesSource: allies.src,
      autoAxisSource: axis.src,
    },
    playerTriggers: {
      autopilotOn: autopilotOn.source,
      autopilotOff: autopilotOff.source,
      manualFire: manual.source,
      exposed: exposed.source,
      searchlightOnlyPlayer: true,
      manualFireSkipsAi: true,
      exposureNotContact: true,
    },
    score: {
      ledgerTracks: scoreLedger.tracks.length,
      playback: scorePlayback.map((item) => ({ file: item.file, duration: Number(item.duration.toFixed(3)) })),
      liveTrack: liveScore.track,
      liveSource: liveScore.src,
      liveDuration: Number(liveScore.duration.toFixed(3)),
    },
    clickCues: { tap: true, select: true, error: true, confirm: true, switchSilences: true, persistsAcrossReload: true },
    commanderPack: 'al-enterprise', commanderCue: commander.cue, commanderLoadedOnce: true,
    scoreDuckedUnderCommander: true, scoreDuckedVolume: Number(ducked.toFixed(3)), scoreReturnedAfterVoice: true };
  await fs.writeFile(out + '/browser-receipt.json', JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
} finally { await browser.close(); }

// --- Formal build must not carry the private radio or commander audio ---
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
      else if (/\.(m4a|wav)$/i.test(entry.name) || entry.name.includes('al-enterprise')) offenders.push(path);
    }
  };
  await walk(dist);
  assert.equal(offenders.length, 0, 'formal build must not carry radio, commander or archive audio: ' + offenders);
  for (const entry of await fs.readdir(dist + 'assets/', { withFileTypes: true })) {
    if (entry.name.endsWith('.js')) {
      const text = await fs.readFile(dist + 'assets/' + entry.name, 'utf8');
      assert.ok(!text.includes('al-enterprise'), entry.name + ' references the commander pack');
      assert.ok(!text.includes('wows-us'), entry.name + ' references the faction radio files');
    }
  }
  console.log(JSON.stringify({ formalBuildClean: true, dist: dist }, null, 2));
}

// --- Explicit local playtest build (VITE_CAS_LOCAL_VOICE=1) must ship the audio ---
if (!process.env.CAS_SKIP_LOCAL_BUILD) {
  const clientRoot = fileURLToPath(new URL('../', import.meta.url));
  const dist = clientRoot + 'dist/';
  const build = (env) => new Promise((resolve, reject) => {
    const child = spawn('npm', ['run', 'build'], { cwd: clientRoot, env, shell: process.platform === 'win32', stdio: 'ignore' });
    child.on('exit', (code) => code === 0 ? resolve(undefined) : reject(new Error('build exited with ' + code)));
  });
  const list = async (dir) => {
    const names = [];
    for (const entry of await fs.readdir(dir, { withFileTypes: true })) {
      if (entry.isDirectory()) names.push(...await list(dir + entry.name + '/'));
      else names.push(dir + entry.name);
    }
    return names;
  };
  await fs.rm(dist, { recursive: true, force: true });
  await build({ ...process.env, VITE_CAS_LOCAL_VOICE: '1' });
  const files = await list(dist);
  const commanderFiles = files.filter((path) => /al-enterprise-.*\.m4a$/i.test(path));
  assert.equal(commanderFiles.length, 6, 'local build carries the six commander clips: ' + commanderFiles.length);
  assert.equal(files.filter((path) => /wows-us-battle_start-0[^/]*\.m4a$/i.test(path)).length, 1,
    'local build still carries the faction radio');
  assert.equal(files.filter((path) => /\.wav$/i.test(path)).length, 58,
    'local build carries the 56 archive WAVs and 2 synthetic UI WAVs');
  assert.equal(files.filter((path) => /damage-control-fire-(en|zh)/.test(path)).length, 2,
    'local build carries both synthetic UI lines');

  const port = 5191;
  const viteBin = clientRoot + 'node_modules/vite/bin/vite.js';
  const preview = spawn(process.execPath, [viteBin, 'preview', '--port', String(port), '--strictPort'],
    { cwd: clientRoot, stdio: 'ignore' });
  const localBrowser = await chromium.launch({ executablePath: process.env.CAS_BROWSER_PATH, headless: true });
  try {
    let live = false;
    for (let attempt = 0; attempt < 40 && !live; attempt++) {
      try { live = (await fetch(`http://127.0.0.1:${port}/`)).ok; }
      catch { await new Promise((done) => setTimeout(done, 250)); }
    }
    assert.ok(live, 'preview server did not start');
    const page = await localBrowser.newPage({ viewport: { width: 1360, height: 768 } });
    const errors = [];
    page.on('pageerror', (error) => errors.push(error.stack));
    const button = (name) => page.getByRole('button', { name, exact: true });
    await page.goto(`http://127.0.0.1:${port}/`);
    await signInLocal(page, 'cas-local-build-qa', true);
    await resumeExercise(page);
    // Auto pack must resolve to the packed archive WAV, not a missing URL.
    await button('开始演习').click();
    await page.waitForFunction(() => {
      const media = document.querySelector('audio[data-channel=fleet-radio]');
      return media && !media.paused && media.currentTime > .08
        && media.currentSrc.includes('allies-battle_start-0');
    }, undefined, { timeout: 15000 });
    await button('暂停演习').click();
    await button('演习设置').click();
    await page.getByLabel('语音包').waitFor();
    await page.getByLabel('语音包').selectOption('al-enterprise');
    await button('开始新演习').click();
    await page.getByRole('dialog').waitFor({ state: 'hidden' });
    await button('开始演习').click();
    await page.waitForFunction(() => {
      const media = document.querySelector('audio[data-channel=fleet-radio]');
      return media && !media.paused && media.currentTime > .08;
    }, undefined, { timeout: 15000 });
    const packed = await page.locator('audio[data-channel=fleet-radio]').evaluate((media) => ({
      src: media.currentSrc, cue: media.dataset.voiceCue }));
    assert.equal(packed.cue, 'battle_start');
    assert.match(packed.src, /al-enterprise-battle_start-0/);
    await page.screenshot({ path: out + '/local-build-commander.png' });
    assert.deepEqual(errors, []);
    await fs.writeFile(out + '/local-build-receipt.json', JSON.stringify({
      build: 'VITE_CAS_LOCAL_VOICE=1', commanderFiles: commanderFiles.length,
      factionRadioPacked: true, archiveWavsPacked: 56, syntheticWavsPacked: 2, autoArchivePlayed: true,
      playedCue: packed.cue, playedSource: packed.src,
      emitted: files.filter((path) => /\.m4a$/i.test(path)).length }, null, 2));
    console.log(JSON.stringify({ localBuildUsable: true, commanderFiles: commanderFiles.length }, null, 2));
  } finally {
    preview.kill();
    await localBrowser.close();
  }
}
