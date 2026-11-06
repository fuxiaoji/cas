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

async function verify(side, fleet, variant = '', seed = 6106) {
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
    { op: 'new', seed, side, enemy: 'torpedo', variant },
    { op: 'ai', fleet, profile: 'gunnery', mode: 'auto', move: true, gun: true, torpedo: true },
    { op: 'step', seconds: 2700 },
  ];
  const wasmOutput = commands.map(call);
  if (!wasmOutput.at(-1).data?.result) {
    commands.push({ op: 'step', seconds: 8 });
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
  assert.equal(start.ships.length, variant === 'challenge' ? 3 : 5);
  assert.equal(start.variant, variant);
  assert(end.result, `${side}: exercise failed to produce a result`);
  assert.equal(json(wasmOutput.at(-1).data), json(end), `${side}: replay diverged from live result`);
  return { side, variant: variant || 'exercise', seed, tick: end.tick, result: end.result, visibleEvents: report.events.length,
    canonicalSha256: createHash('sha256').update(json(wasmOutput)).digest('hex') };
}

const runs = [await verify('allies', 1, '', 6107), await verify('axis', 2), await verify('allies', 1, 'challenge'), await verify('allies', 1, 'night')];
const report = JSON.stringify({ ok: true, nativeWasmCanonicalMatch: true, replayMatch: true, runs }, null, 2) + '\n';
console.log(report);
if (evidence) {
  const out = resolve(evidence);
  await mkdir(dirname(out), { recursive: true });
  await writeFile(out, report, { flag: 'wx' });
}
