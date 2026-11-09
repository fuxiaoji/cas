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

async function verify(side, fleet, variant = '', seed = 6106, realtime = false, campaign = false, profile = null, opponent = null) {
  const channel = variant === 'channel-action-rts';
  const kula = variant === 'kula-gulf-rts';
  const empressCampaign = variant === 'empress-campaign';
  const esperanceCampaign = variant === 'esperance-campaign';
  const tassafarongaCampaign = variant === 'tassafaronga-campaign';
  const savoCampaign = variant === 'savo-campaign';
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
    campaign ? { op: 'new_campaign', id: empressCampaign ? (side === 'allies' ? 'CAMP-ALLIES-11' : 'CAMP-AXIS-11') : esperanceCampaign ? (side === 'allies' ? 'CAMP-ALLIES-02' : 'CAMP-AXIS-02') : tassafarongaCampaign ? (side === 'allies' ? 'CAMP-ALLIES-05' : 'CAMP-AXIS-05') : savoCampaign ? (side === 'allies' ? 'CAMP-ALLIES-10' : 'CAMP-AXIS-10') : 'CAMP-' + side.toUpperCase() + (kula ? '-04' : '-03'), difficulty: kula ? side === 'allies' ? 'standard' : 'challenge' : 'story', seed, ...(kula ? { profile: side === 'allies' ? 'gunnery' : 'torpedo' } : {}) } :
      { op: 'new', seed, side, enemy: opponent ?? (variant === 'night-training' ? 'gunnery' : 'torpedo'), variant, realtime, ...(profile ? { profile } : {}) },
  ];
  if (variant === 'night-training') commands.push(
    { op: 'route', fleet, mode: 'follow', speed: 15, points: [{ x: 13000, y: 6550 }, { x: 13000, y: 10400 }] },
  );
  if (realtime && !variant) commands.push(
    { op: 'aim', ship: 1, weapon: 'gun', target: 'C01' },
    { op: 'fire', ship: 1, weapon: 'gun', target: 'C01' },
    { op: 'step', seconds: 15 },
  );
  if (variant === 'prologue') {
    commands.push(
      { op: 'step', seconds: 204 },
      // cas-realtime-v10: the mid-battle switch requires a queue-end hull.
      { op: 'lead', fleet: 1, ship: 5 },
      { op: 'route', fleet: 1, mode: 'follow', points: [{ x: 11600, y: 6600 }, { x: 14100, y: 6600 }] },
    );
    // The sustained volleys land on their own reload clocks; scan 40 seconds
    // past the handover for the enemy shell in flight.
    for (let i = 0; i < 40; i++) commands.push({ op: 'step', seconds: 1 });
  } else if (variant === 'night-radar-training') {
    commands.push(
      { op: 'radar_set', ship: 1, radar: 'us_sg', powered: true },
      { op: 'step', seconds: 180 },
      { op: 'step', seconds: 540 },
    );
  } else if (kula) {
    for (const fleet of side === 'allies' ? [1] : [2, 3, 4]) commands.push(
      { op: 'ai', fleet, profile: fleet === 2 ? 'torpedo' : 'gunnery', mode: 'auto', move: side === 'allies', gun: true, torpedo: true });
  } else if (channel) {
    const ownFleets = side === 'axis' ? [1, 2, 3] : [4, 5, 6, 7, 8];
    for (const fleet of ownFleets) commands.push(
      { op: 'ai', fleet, profile: 'gunnery', mode: 'auto', move: side === 'axis', gun: true, torpedo: true });
  } else if (savoCampaign) {
    for (const fleet of side === 'allies' ? [3, 4, 5] : [1, 2]) commands.push(
      { op: 'ai', fleet, profile: 'coord', mode: 'auto', move: side === 'allies', gun: true, torpedo: true });
  } else if (tassafarongaCampaign) {
    for (const fleet of side === 'allies' ? [1, 2, 3] : [4, 5, 6, 7]) commands.push(
      { op: 'ai', fleet, profile: 'coord', mode: 'auto', move: true, gun: true, torpedo: true });
  } else if (esperanceCampaign) {
    for (const fleet of side === 'allies' ? [1] : [2, 3]) commands.push(
      { op: 'ai', fleet, profile: 'coord', mode: 'auto', move: true, gun: true, torpedo: true });
  } else if (variant === 'empress' || empressCampaign) {
    for (const fleet of side === 'allies' ? [1, 2, 3] : [4, 5, 6]) commands.push(
      { op: 'ai', fleet, profile: 'coord', mode: 'auto', move: true, gun: true, torpedo: true });
  } else if (campaign && side === 'axis') {
    for (const [fleet, x, y, speed] of [[3, 30000, 35000, 35], [4, 33000, 3000, 33]]) commands.push(
      { op: 'route', fleet, mode: 'follow', speed, points: [{ x, y }, { x: 400, y }] },
      { op: 'ai', fleet, profile: 'torpedo', mode: 'auto', move: false, gun: true, torpedo: true });
  } else if (campaign) {
    for (const fleet of [1, 2]) commands.push(
      { op: 'ai', fleet, profile: 'torpedo', mode: 'auto', move: true, gun: true, torpedo: true });
  } else commands.push(
    { op: 'ai', fleet, profile: profile ?? 'gunnery', mode: 'auto', move: true, gun: true, torpedo: true },
  );
  const wasmOutput = [];
  for (const command of commands) wasmOutput.push(call(command));
  // cas-realtime-v10: per-second detection acquires contacts at
  // geometry-driven times with version-dependent IDs, so the night-training
  // flow advances until a contact exists, then orders illumination on it —
  // before the generic battle-to-end step runs the whole exchange.
  if (variant === 'night-training') {
    let waited = 0;
    while (!wasmOutput.at(-1).data.contacts.length && waited < 2700) {
      const command = { op: 'step', seconds: 10 };
      commands.push(command);
      wasmOutput.push(call(command));
      waited += 10;
    }
    assert(wasmOutput.at(-1).data.contacts.length, 'night-training must make contact within 45 minutes');
    const mark = wasmOutput.at(-1).data.contacts.find(contact => contact.kind === 'cl') ?? wasmOutput.at(-1).data.contacts[0];
    for (const command of [
      { op: 'illumination_preview', ship: 5, target: mark.id },
      { op: 'illuminate', ship: 5, target: mark.id },
      { op: 'step', seconds: 180 },
    ]) {
      commands.push(command);
      wasmOutput.push(call(command));
    }
  }
  // cas-realtime-v10: per-second detection shifts when each contact id
  // appears, so the radar-training starshell previews live contacts until one
  // sits inside the starshell's range band, then fires.
  if (variant === 'night-radar-training') {
    let mark;
    let waited = 0;
    while (!mark && waited < 2700) {
      for (const contact of wasmOutput.at(-1).data.contacts) {
        const preview = call({ op: 'illumination_preview', ship: 5, target: contact.id });
        if (preview.ok && preview.data?.valid) {
          commands.push({ op: 'illumination_preview', ship: 5, target: contact.id });
          wasmOutput.push(preview);
          mark = contact;
          break;
        }
      }
      if (!mark) {
        const command = { op: 'step', seconds: 10 };
        commands.push(command);
        wasmOutput.push(call(command));
        waited += 10;
      }
    }
    assert(mark, 'radar training must reach a starshell-range contact');
    for (const command of [
      { op: 'illuminate', ship: 5, target: mark.id },
      { op: 'step', seconds: 180 },
    ]) {
      commands.push(command);
      wasmOutput.push(call(command));
    }
  }
  commands.push({ op: 'step', seconds: 2700 });
  wasmOutput.push(call(commands.at(-1)));
  if (campaign && !wasmOutput.at(-1).data?.result) {
    commands.push({ op: 'step', seconds: 2700 });
    wasmOutput.push(call(commands.at(-1)));
  }
  if (kula && !wasmOutput.at(-1).data?.result) {
    commands.push({ op: 'step', seconds: 1800 });
    wasmOutput.push(call(commands.at(-1)));
  }
  if (variant === 'empress' && !wasmOutput.at(-1).data?.result) {
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
    assert(wasmOutput[i].ok, `${side}/${variant || 'exercise'}/${seed}/${command.op} WASM rejected: ${wasmOutput[i].error}`);
    assert(nativeOutput[i].ok, `${side}/${variant || 'exercise'}/${seed}/${command.op} native rejected: ${nativeOutput[i].error}`);
    assert.equal(json(wasmOutput[i]), json(nativeOutput[i]), `${side}/${command.op} diverged between Windows native and WASM`);
  }
  const start = wasmOutput[1].data;
  const report = wasmOutput.at(-3).data;
  // cas-realtime-v10: the starshell fires the moment its mount trains and
  // loads, so assert it ignites inside the planned window, not at its boundary.
  // cas-realtime-v10: the starshell fires the moment its mount trains and
  // loads; the v3 window cadence still resolves it at the planned boundary.
  // Both must produce one real ignition somewhere in the exercised window.
  if (variant === 'night-training') assert(report.events.some(e => e.kind === 'illumination'));
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
  assert.equal(start.ships.length, variant === 'prologue' ? 9 : variant === 'empress' ? 12 : empressCampaign ? (side === 'allies' ? 12 : 10) : esperanceCampaign ? (side === 'allies' ? 9 : 5) : tassafarongaCampaign ? 11 : savoCampaign ? (side === 'allies' ? 49 : 8) : kula ? (side === 'allies' ? 7 : 10) : variant === 'challenge' || channel && side === 'axis' ? 3 : 5);
  assert.equal(start.variant, empressCampaign ? 'empress' : esperanceCampaign ? 'esperance' : tassafarongaCampaign ? 'tassafaronga' : savoCampaign ? 'savo' : variant);
  if (variant === 'empress') {
    assert.equal(start.fleets.length, 3);
    assert.equal(start.environment.visibility, 10);
    assert.equal(start.environment.precipitation, true);
  }
  if (variant === 'prologue') {
    const handover = wasmOutput[2].data;
    assert.equal(handover.contacts.filter(contact => contact.kind === 'bb').length, 2);
    assert(handover.shells.some(shell => shell.own));
    assert(wasmOutput.slice(2).some(output => output.data?.shells?.some(shell => !shell.own)),
      'enemy fire must be in flight near the handover');
    assert(handover.torpedoes.some(torpedo => torpedo.own && torpedo.trail?.length > 1));
    assert.equal(wasmOutput[3].data.fleets[0].leader, 5);
  }
  if (variant === 'night-radar-training') {
    const radar = wasmOutput[3].data;
    assert.equal(radar.contacts.length, 0);
    assert(radar.radarContacts.some(contact => contact.usableForShipIds.includes(1)));
    const lit = wasmOutput.map(output => output.data).reverse()
      .find(data => data?.illuminations?.length);
    assert(lit?.illuminations.some(mark => mark.own), 'the radar-cued starshell must ignite');
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
  } else if (empressCampaign) {
    assert(end.result);
    assert(end.result.grade !== undefined);
  } else if (campaign) {
    // cas-realtime-v10: sourced Fletcher train (28.7 deg/s) and per-second
    // detection engage both sides earlier; the allies escort DDs now soak
    // more than the decisive 25% allowance, so the cape fixture holds at
    // tactical (registered in the v10 ledger). Kula allies stays decisive.
    const expected = savoCampaign ? 'none' : esperanceCampaign || tassafarongaCampaign ? (side === 'allies' ? 'decisive' : 'none') : kula || channel ? 'decisive' : side === 'allies' ? 'tactical' : 'decisive';
    assert.equal(end.result.grade, expected, `${side} ${variant} ${seed}: ${end.result.grade}`);
    assert.equal(start.fleets.length, savoCampaign ? (side === 'allies' ? 8 : 2) : tassafarongaCampaign ? 3 : esperanceCampaign ? (side === 'allies' ? 1 : 2) : 2);
    if (side === 'axis' && !esperanceCampaign) assert.equal(report.events.filter(event => event.kind === 'withdrawal').length, 5);
    else if (savoCampaign || esperanceCampaign || tassafarongaCampaign) assert(report.events.length > 0);
    else assert(report.events.some(event => event.kind === 'torpedo_hit'));
  }
  assert(end.result, `${side}: exercise failed to produce a result`);
  assert.equal(json(wasmOutput.at(-1).data), json(end), `${side}: replay diverged from live result`);
  return { side, variant: variant || 'exercise', ...(profile ? { profile } : {}), version: start.version, seed, tick: end.tick, result: end.result, visibleEvents: report.events.length,
    canonicalSha256: createHash('sha256').update(json(wasmOutput)).digest('hex') };
}

const runs = [await verify('allies', 1, '', 6107), await verify('axis', 2), await verify('allies', 1, 'challenge'),
  await verify('allies', 1, 'night'), await verify('allies', 1, 'radar'), await verify('allies', 1, 'night-training'),
  await verify('allies', 1, '', 6106, true), await verify('allies', 1, 'night-training', 6106, true),
  await verify('allies', 1, 'radar', 6106, true),
  await verify('allies', 1, 'cape-st-george-rts', 6116, true, true),
  await verify('axis', 3, 'cape-st-george-rts', 6111, true, true),
  await verify('allies', 1, 'esperance-campaign', 6106, true, true),
  await verify('axis', 2, 'esperance-campaign', 6106, true, true),
  await verify('allies', 1, 'tassafaronga-campaign', 6106, true, true),
  await verify('allies', 1, 'savo-campaign', 6106, true, true),
  await verify('allies', 1, 'prologue', 6106, true),
  await verify('allies', 1, 'night-radar-training', 6106, true),
  await verify('allies', 1, 'empress', 6106, true),
  await verify('allies', 1, 'empress-campaign', 6106, true, true),
  await verify('allies', 1, 'kula-gulf-rts', 6106, true, true),
  await verify('axis', 2, 'kula-gulf-rts', 2, true, true),
  await verify('allies', 1, '', 6106, false, false, 'evo-brawler', 'coord'),
  await verify('allies', 1, '', 6112, false, false, 'evo-kiter', 'gunnery'),
  await verify('allies', 1, '', 6111, false, false, 'evo-denial', 'torpedo')];
const report = JSON.stringify({ ok: true, nativeWasmCanonicalMatch: true, replayMatch: true, runs }, null, 2) + '\n';
console.log(report);
if (evidence) {
  const out = resolve(evidence);
  await mkdir(dirname(out), { recursive: true });
  await writeFile(out, report, { flag: 'wx' });
}
