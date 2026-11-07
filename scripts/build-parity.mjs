import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const defaults = [resolve(root, 'target/release/cas-sim.exe'), resolve(root, 'target/wasm32-unknown-unknown/release/cas_core.wasm')];
const [native = defaults[0], wasm = defaults[1], evidence] = process.argv.slice(2);
const source = await readFile(wasm);
const json = value => JSON.stringify(value, (_, item) =>
  item && !Array.isArray(item) && typeof item === 'object' ? Object.fromEntries(Object.entries(item).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)) : item);
const encode = new TextEncoder();
const decode = new TextDecoder('utf-8', { fatal: true });

async function verify(side, fleet, variant = '', seed = 6106, realtime = false, campaign = false) {
  const channel = variant === 'channel-action-rts';
  const kula = variant === 'kula-gulf-rts';
  const { instance } = await WebAssembly.instantiate(source, {});
  const api = instance.exports;
  function call(req) {
    const bytes = encode.encode(JSON.stringify(req));
    const start = api.cas_alloc(bytes.length) >>> 0;
    new Uint8Array(api.memory.buffer, start, bytes.length).set(bytes);
    const out = api.cas_request(start, bytes.length) >>> 0;
    return JSON.parse(decode.decode(new Uint8Array(api.memory.buffer, out, api.cas_response_len() >>> 0)));
  }

  const commands = [
    { op: 'info' },
    campaign ? { op: 'new_campaign', id: 'CAMP-' + side.toUpperCase() + (channel ? '-01' : kula ? '-04' : '-03'), difficulty: kula ? side === 'allies' ? 'standard' : 'challenge' : 'story', seed, ...(kula ? { profile: side === 'allies' ? 'gunnery' : 'torpedo' } : {}) } :
      { op: 'new', seed, side, enemy: variant === 'night-training' ? 'gunnery' : 'torpedo', variant, realtime },
  ];
  if (variant === 'night-training') commands.push(
    { op: 'route', fleet, mode: 'follow', speed: 15, points: [{ x: 13000, y: 6550 }, { x: 13000, y: 10400 }] },
    { op: 'step', seconds: 360 },
    { op: 'illumination_preview', ship: 5, target: 'C05' },
    { op: 'illuminate', ship: 5, target: 'C05' },
    { op: 'step', seconds: 180 },
  );
  if (realtime && !variant) commands.push(
    { op: 'aim', ship: 1, weapon: 'gun', target: 'C01' },
    { op: 'fire', ship: 1, weapon: 'gun', target: 'C01' },
    { op: 'step', seconds: 15 },
  );
  if (variant === 'prologue') {
    commands.push(
      { op: 'step', seconds: 204 },
      { op: 'lead', fleet: 1, ship: 2 },
      { op: 'route', fleet: 1, mode: 'follow', points: [{ x: 11600, y: 6600 }, { x: 14100, y: 6600 }] },
    );
  } else if (variant === 'night-radar-training') {
    commands.push(
      { op: 'radar_set', ship: 1, radar: 'us_sg', powered: true },
      { op: 'step', seconds: 180 },
      { op: 'step', seconds: 540 },
      { op: 'illuminate', ship: 5, target: 'C03' },
      { op: 'step', seconds: 180 },
    );
  } else if (kula) {
    for (const fleet of side === 'allies' ? [1] : [2, 3, 4]) commands.push(
      { op: 'ai', fleet, profile: fleet === 2 ? 'torpedo' : 'gunnery', mode: 'auto', move: side === 'allies', gun: true, torpedo: true });
  } else if (channel) {
    const ownFleets = side === 'axis' ? [1, 2, 3] : [4, 5, 6, 7, 8];
    for (const fleet of ownFleets) commands.push(
      { op: 'ai', fleet, profile: 'gunnery', mode: 'auto', move: side === 'axis', gun: true, torpedo: true });
  } else if (campaign && side === 'axis') {
    for (const [fleet, x, y, speed] of [[3, 30000, 35000, 35], [4, 33000, 3000, 33]]) commands.push(
      { op: 'route', fleet, mode: 'follow', speed, points: [{ x, y }, { x: 400, y }] },
      { op: 'ai', fleet, profile: 'torpedo', mode: 'auto', move: false, gun: true, torpedo: true });
  } else if (campaign) {
    for (const fleet of [1, 2]) commands.push(
      { op: 'ai', fleet, profile: 'torpedo', mode: 'auto', move: true, gun: true, torpedo: true });
  } else commands.push(
    { op: 'ai', fleet, profile: 'gunnery', mode: 'auto', move: true, gun: true, torpedo: true },
  );
  commands.push({ op: 'step', seconds: 2700 });
  const wasmOutput = commands.map(call);
  if (campaign && !wasmOutput.at(-1).data?.result) {
    commands.push({ op: 'step', seconds: 2700 });
    wasmOutput.push(call(commands.at(-1)));
  }
  if (kula && !wasmOutput.at(-1).data?.result) {
    commands.push({ op: 'step', seconds: 1800 });
    wasmOutput.push(call(commands.at(-1)));
  }
  if (!wasmOutput.at(-1).data?.result) {
    commands.push({ op: 'step', seconds: realtime ? 120 : 8 });
    wasmOutput.push(call(commands.at(-1)));
  }
  const end = wasmOutput.at(-1).data;
  commands.push({ op: 'report' }, { op: 'save' });
  wasmOutput.push(...commands.slice(-2).map(call));
  commands.push({ op: 'replay', save: wasmOutput.at(-1).data });
  wasmOutput.push(call(commands.at(-1)));
  const result = spawnSync(native, { input: commands.map(command => JSON.stringify(command)).join('\n') + '\n', encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
  assert.equal(result.status, 0, result.error?.message ?? result.stderr);
  const nativeOutput = result.stdout.trim().split(/\r?\n/).map(line => JSON.parse(line));
  assert.equal(nativeOutput.length, commands.length);
  for (const [i, command] of commands.entries()) {
    assert(wasmOutput[i].ok, `${side}/${command.op} WASM rejected: ${wasmOutput[i].error}`);
    assert(nativeOutput[i].ok, `${side}/${command.op} native rejected: ${nativeOutput[i].error}`);
    assert.equal(json(wasmOutput[i]), json(nativeOutput[i]), `${side}/${command.op} diverged between Windows native and WASM`);
  }
  const start = wasmOutput[1].data;
  const report = wasmOutput.at(-3).data;
  if (variant === 'night-training') assert(report.events.some(e => e.kind === 'illumination' && e.tick === 540));
  if (variant === 'radar' && side === 'allies') {
    assert(report.events.some(e => e.kind === 'gun' && e.text.includes('水面搜索雷达')));
    if (realtime) assert(report.events.some(e => e.kind === 'gun' && e.text.includes('火控雷达 Mk4')));
  }
  if (realtime && !variant) {
    const gun = report.events.find(event => event.kind === 'gun');
    const onTheWay = wasmOutput[4].data.shells.find(shell => shell.own);
    assert(gun && gun.tick > 0 && gun.tick < 180);
    assert(onTheWay && onTheWay.arcHeightM > 0 && onTheWay.impactTick - onTheWay.launchTick > 8);
  }
  assert.equal(start.ships.length, variant === 'prologue' ? 9 : kula ? (side === 'allies' ? 7 : 10) : variant === 'challenge' || channel && side === 'axis' ? 3 : 5);
  assert.equal(start.variant, variant);
  if (variant === 'prologue') {
    const handover = wasmOutput[2].data;
    assert.equal(handover.contacts.filter(contact => contact.kind === 'bb').length, 2);
    assert(handover.shells.some(shell => shell.own) && handover.shells.some(shell => !shell.own));
    assert(handover.torpedoes.some(torpedo => torpedo.own && torpedo.trail?.length > 1));
    assert.equal(wasmOutput[3].data.fleets[0].leader, 2);
  }
  if (variant === 'night-radar-training') {
    const radar = wasmOutput[3].data;
    assert.equal(radar.contacts.length, 0);
    assert(radar.radarContacts.some(contact => contact.usableForShipIds.includes(1)));
    assert(wasmOutput[6].data.illuminations.some(mark => mark.own));
  }
  if (kula) {
    assert.equal(start.environment.visibility, 10);
    assert.equal(end.result.grade, side === 'allies' ? 'decisive' : 'tactical');
    if (side === 'axis') {
      assert(end.campaign.supplyComplete);
      assert(report.events.some(event => event.kind === 'torpedo_hit'));
    } else assert.equal(end.campaign.supplySeconds, undefined);
  } else if (channel) {
    assert.equal(start.environment.visibility, 5);
    assert(start.ships.every(ship => ship.classId === ship.characterId));
    assert.equal(start.fleets.length, start.ships.length);
    assert.equal(end.result.winner, side);
    // cas-realtime-v10: the axis escort AI now also reaches the decisive tier.
    assert.equal(end.result.grade, 'decisive');
    assert(end.tick >= 720);
    assert(report.events.some(event => event.kind === 'sunk'));
    if (side === 'axis') assert(report.events.some(event => event.kind === 'torpedo_hit'));
  } else if (campaign) {
    assert.equal(end.result.grade, 'decisive');
    assert.equal(start.fleets.length, 2);
    if (side === 'axis') assert.equal(report.events.filter(event => event.kind === 'withdrawal').length, 5);
    else assert(report.events.some(event => event.kind === 'torpedo_hit'));
  }
  assert(end.result, `${side}: exercise failed to produce a result`);
  assert.equal(json(wasmOutput.at(-1).data), json(end), `${side}: replay diverged from live result`);
  return { side, variant: variant || 'exercise', version: start.version, seed, tick: end.tick, result: end.result, visibleEvents: report.events.length,
    canonicalSha256: createHash('sha256').update(json(wasmOutput)).digest('hex') };
}

const runs = [await verify('allies', 1, '', 6107), await verify('axis', 2), await verify('allies', 1, 'challenge'),
  await verify('allies', 1, 'night'), await verify('allies', 1, 'radar'), await verify('allies', 1, 'night-training'),
  await verify('allies', 1, '', 6106, true), await verify('allies', 1, 'night-training', 6106, true),
  await verify('allies', 1, 'radar', 6106, true),
  await verify('allies', 1, 'cape-st-george-rts', 6148, true, true),
  await verify('axis', 3, 'cape-st-george-rts', 6106, true, true),
  await verify('allies', 4, 'channel-action-rts', 6107, true, true),
  await verify('axis', 1, 'channel-action-rts', 57, true, true),
  await verify('allies', 1, 'prologue', 6106, true),
  await verify('allies', 1, 'night-radar-training', 6106, true),
  await verify('allies', 1, 'kula-gulf-rts', 6106, true, true),
  await verify('axis', 2, 'kula-gulf-rts', 2, true, true)];
const report = JSON.stringify({ ok: true, nativeWasmCanonicalMatch: true, replayMatch: true, runs }, null, 2) + '\n';
console.log(report);
if (evidence) {
  const out = resolve(evidence);
  await mkdir(dirname(out), { recursive: true });
  await writeFile(out, report, { flag: 'wx' });
}
