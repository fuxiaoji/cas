"""Verify a named, uninstalled 27-person core and its read-only geography API.

Existing release/oracle files are inputs only. All new receipts and the small
Node WASM bridge live under --out. No account, runtime or manifest is written.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
NODE_BRIDGE = r"""import {readFile} from 'node:fs/promises';
import {createInterface} from 'node:readline';
const {instance}=await WebAssembly.instantiate(await readFile(process.argv[2]),{});
const api=instance.exports,enc=new TextEncoder(),dec=new TextDecoder();
for await(const line of createInterface({input:process.stdin,crlfDelay:Infinity})) {
 const b=enc.encode(line),p=api.cas_alloc(b.length)>>>0;
 new Uint8Array(api.memory.buffer,p,b.length).set(b);
 const r=api.cas_request(p,b.length)>>>0;
 process.stdout.write(dec.decode(new Uint8Array(api.memory.buffer,r,api.cas_response_len()>>>0))+'\n');
}
"""


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def normalized(value):
    # Same integer wire representation as JSON.stringify in existing WASM
    # clients; genuine fractional coordinates and 0.1s replay ticks are kept.
    if isinstance(value, dict):
        return {k: normalized(v) for k, v in value.items()}
    if isinstance(value, list):
        return [normalized(v) for v in value]
    if isinstance(value, float) and value.is_integer() and abs(value) <= 9007199254740991:
        return int(value)
    return value


class Dual:
    def __init__(self, args, name):
        self.args, self.name = args, name
        self.native = subprocess.Popen([str(args.candidate)], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        self.wasm = subprocess.Popen([args.node, str(args.out / 'wasm-bridge.mjs'), str(args.wasm)], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        self.requests, self.digest, self.size = [], hashlib.sha256(), 0

    def call(self, request, ok=True):
        request = normalized(request)
        wire = (json.dumps(request, ensure_ascii=False, separators=(',', ':'), allow_nan=False) + '\n').encode('utf8')
        # Every request has a corresponding read before the next request. This
        # keeps large battle/save replies from filling a child process pipe.
        replies = []
        for proc in [self.native, self.wasm]:
            proc.stdin.write(wire)
            proc.stdin.flush()
            replies.append(proc.stdout.readline())
        assert replies[0] and replies[0] == replies[1], (self.name, len(self.requests), request['op'], 'native/WASM reply differs')
        self.requests.append(request)
        self.digest.update(replies[0])
        self.size += len(replies[0])
        response = json.loads(replies[0])
        if ok is not None:
            assert response['ok'] is ok, (self.name, request['op'], response)
        return response.get('data') if response['ok'] else response

    def close(self):
        for proc in [self.native, self.wasm]:
            proc.stdin.close()
            assert proc.wait(timeout=30) == 0
        path = self.args.out / 'streams' / (self.name + '.json')
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({'commands': self.requests}, ensure_ascii=False, indent=2), encoding='utf8')
        row = {'name': self.name, 'requests': len(self.requests), 'bytes': self.size,
               'response_sha256': self.digest.hexdigest(), 'raw_native_wasm_identical': True,
               'commands': str(path), 'commands_sha256': sha(path)}
        print(json.dumps(row, ensure_ascii=False), flush=True)
        return row


def legacy_names():
    names = []
    for file in ['receipt.json', 'shore-artillery-receipt.json', 'historical-wasm-receipt.json']:
        receipt = json.loads((ROOT / 'artifacts/island-war-v4/parity' / file).read_text('utf8'))
        assert receipt['passed']
        names.extend(c['name'] for c in receipt['cases'])
    assert len(names) == len(set(names))
    return names


def run_legacy(args):
    for script, switches, file in [
        ('verify-island-war-v4-installed-equivalence.py', ['--candidate', str(args.candidate), '--installed', str(args.baseline)], 'legacy-installed-equivalence.json'),
        ('verify-island-war-v4-old-oracle.py', ['--native', str(args.candidate)], 'legacy-old-v3-oracle.json'),
    ]:
        command = [sys.executable, str(ROOT / 'scripts' / script), *switches, '--out', str(args.out / file)]
        with (args.out / (file + '.log')).open('w', encoding='utf8') as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=1800)
        assert result.returncode == 0, (script, str(args.out / (file + '.log')))
        receipt = json.loads((args.out / file).read_text('utf8'))
        assert receipt['passed']
        print(json.dumps({'legacy': file, 'passed': True, 'cases': len(receipt['cases']), 'requests': receipt['requests']}), flush=True)


def verify(args):
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / 'wasm-bridge.mjs').write_text(NODE_BRIDGE, encoding='utf8')
    inputs = {str(p): sha(p) for p in [args.candidate, args.baseline, args.wasm, ROOT / 'godot/bin/core-current.json']}
    assert inputs[str(args.baseline)].startswith('5edacf8b'), 'Expected the explicit published 27-person river baseline'
    if not args.skip_legacy:
        run_legacy(args)
    rows = []
    # Replay the registered v4/historical streams with this exact candidate WASM,
    # independently of the native/native and old-v3 frozen-oracle checks above.
    if not args.skip_legacy:
        for name in legacy_names():
            fixture = json.loads((ROOT / 'artifacts/island-war-v4/core' / (name + '.json')).read_text('utf8'))
            dual, view = Dual(args, 'legacy-' + name), None
            try:
                for request in fixture['commands']:
                    response = dual.call(request, ok=None)
                    if isinstance(response, dict) and 'ships' in response:
                        view = response
                if fixture.get('save') or fixture.get('snapshot'):
                    saved = dual.call({'op': 'save'})
                    terminal = view
                    assert dual.call({'op': 'load', 'save': saved}) == terminal
                    for tick in [0, min(saved['tick'], 12), saved['tick']]:
                        response = dual.call({'op': 'replay', 'save': saved, 'tick': tick})
                    assert response == terminal
            finally:
                rows.append(dual.close())

    dual = Dual(args, 'geography-home-and-catalogue')
    try:
        catalogue = dual.call({'op': 'island_war_catalogue', 'version': 'cas-island-war-v4'})
        assert len(catalogue['cards']) == 27
        assert len(catalogue['weapons']) == 54 and len(catalogue['weapon_families']) == 18
        assert not any(c['id'] == 'MCP-306' for c in catalogue['cards'])
        for level in range(1, 6):
            for seed in [1, 714, 18031]:
                request = {'op': 'geography_snapshot', 'home': True, 'hq_level': level, 'seed': seed,
                           'buildings': [{'id': 'hq', 'kind': 'hq', 'cell': {'x': 6, 'y': 4}, 'hp': 100}],
                           'points': [{'x': 14600, 'y': 13000}, {'x': 15100, 'y': 13000}, {'x': 15100, 'y': 13100}]}
                snapshot = dual.call(request)
                preview = dual.call({**request, 'op': 'island_home_preview', 'version': 'cas-island-war-v4'})
                assert snapshot['land']['terrain'] == preview['littoral']['land']['terrain']
                assert snapshot['land']['polygon'] == preview['littoral']['land']['polygon']
                assert snapshot['header']['units'] == 'metres'
                assert snapshot['header']['island_id'].strip()
                assert not snapshot['height_surface']['adds_noise'] and not snapshot['height_surface']['continuous_height_physics']
                assert all(q['landing']['valid'] is None and q['landing']['supported'] is False for q in snapshot['queries'])
                assert snapshot['land']['bounds']['width'] == 3600 + 1200 * (level - 1)
                assert snapshot['land']['bounds']['height'] == 4800 + 1400 * (level - 1)
                request['buildings'][0]['hp'] = 1
                assert dual.call(request)['header']['geometry_hash'] == snapshot['header']['geometry_hash']
        dual.call({'op': 'geography_snapshot', 'home': True, 'hq_level': 5, 'points': [{'x': 1, 'y': 2}] * 4097}, ok=False)
    finally:
        rows.append(dual.close())

    dual = Dual(args, 'geography-live-island-readonly-save-replay')
    try:
        fixture = json.loads((ROOT / 'artifacts/island-war-v4/river-core/training-combined_arms-terminal.json').read_text('utf8'))
        start = fixture['commands'][0]
        view = dual.call(start)
        saved = dual.call({'op': 'save'})
        snapshot = dual.call({'op': 'geography_snapshot', 'points': [{'x': 14600, 'y': 13000}]})
        assert snapshot['header']['island_id'] == 'home', 'Empty NPC identity in a local exercise must resolve to a stable island ID'
        assert snapshot['land']['polygon'] == view['littoral']['land']['polygon']
        assert snapshot['land']['terrain'] == view['littoral']['land']['terrain']
        assert dual.call({'op': 'save'}) == saved
        dual.call({'op': 'island_autonomy', 'enabled': True, 'version': 'cas-island-war-v4'})
        terminal = dual.call({'op': 'step', 'seconds': 30})
        end = dual.call({'op': 'save'})
        assert dual.call({'op': 'load', 'save': end}) == terminal
        after = dual.call({'op': 'geography_snapshot'})
        assert snapshot['header']['geometry_hash'] == after['header']['geometry_hash']
        assert dual.call({'op': 'save'}) == end
        for tick in [0, 12, end['tick']]:
            replay = dual.call({'op': 'replay', 'save': end, 'tick': tick})
            assert replay['littoral']['land']['polygon'] == snapshot['land']['polygon']
            assert replay['littoral']['land']['terrain'] == snapshot['land']['terrain']
    finally:
        rows.append(dual.close())

    dual = Dual(args, 'geography-extraction-multi-island-save-replay')
    try:
        start = {'content': 'salvage-v4', 'gameplay_profile': 'cas-adventure-v3',
                 'fleet': [{'id': 'IBS-U-USN-FLETCHER', 'hp': 100, 'ammo': 100, 'level': 0}],
                 'mission': {'kind': 'salvage', 'id': 'calm', 'loot_kind': 'scrap'},
                 'cargo_v4': {'commander_level': 20, 'difficulty': 'calm', 'environment': 'atoll', 'weather': 'clear', 'loadouts': {}},
                 'expedition_v2': {'scene': 'sunken_metropolis', 'munitions': {}},
                 'amphibious_expedition': {'companies': [{'unit_id': 'MCP-034', 'carrier_identity': 'IBS-U-USN-FLETCHER', 'transport_kind': 'landing_craft', 'condition_percent': 100}]}}
        for seed in [42, 714, 18031]:
            view = dual.call({'op': 'new_salvage', 'seed': seed, 'start': start})
            tasks = view['salvage']['amphibious']['tasks']
            assert len(tasks) == 3
            saved = dual.call({'op': 'save'})
            dual.call({'op': 'geography_snapshot'}, ok=False)
            hashes = {}
            for task in tasks:
                snapshot = dual.call({'op': 'geography_snapshot', 'island_index': task['island'], 'points': [{'x': task['x'], 'y': task['y']}]})
                assert snapshot['land']['polygon'] == task['polygon'] and snapshot['land']['terrain'] == task['terrain']
                assert snapshot['registered_beaches'][0]['land'] == task['beach']
                assert snapshot['registered_beaches'][0]['sea'] == task['shore']
                assert snapshot['queries'][0]['slope']['supported']
                hashes[task['island']] = snapshot['header']['geometry_hash']
            assert len(set(hashes.values())) == 3
            assert dual.call({'op': 'save'}) == saved
            dual.call({'op': 'extraction_autopilot', 'enabled': True, 'policy': 'bold', 'version': 'cas-extraction-pilot-v3'})
            terminal = dual.call({'op': 'step', 'seconds': 32})
            end = dual.call({'op': 'save'})
            assert dual.call({'op': 'load', 'save': end}) == terminal
            for island, expected in hashes.items():
                assert dual.call({'op': 'geography_snapshot', 'island_index': island})['header']['geometry_hash'] == expected
            assert dual.call({'op': 'save'}) == end
            for tick in [0, 12, end['tick']]:
                replay = dual.call({'op': 'replay', 'save': end, 'tick': tick})
                assert [t['polygon'] for t in replay['salvage']['amphibious']['tasks']] == [t['polygon'] for t in tasks]
    finally:
        rows.append(dual.close())

    dual = Dual(args, 'geography-historical-refusal-does-not-replace-world')
    try:
        view = dual.call({'op': 'new', 'seed': 6106, 'side': 'allies', 'enemy': 'coord'})
        saved = dual.call({'op': 'save'})
        dual.call({'op': 'geography_snapshot'}, ok=False)
        dual.call({'op': 'geography_snapshot', 'home': True, 'hq_level': 1, 'seed': 714, 'buildings': []})
        assert dual.call({'op': 'save'}) == saved
        assert dual.call({'op': 'observe'}) == view
    finally:
        rows.append(dual.close())

    for path, digest in inputs.items():
        assert sha(path) == digest, ('input changed during verification', path)
    return {'passed': True, 'candidate': str(args.candidate), 'candidate_sha256': sha(args.candidate),
            'wasm': str(args.wasm), 'wasm_sha256': sha(args.wasm), 'baseline': str(args.baseline),
            'baseline_sha256': sha(args.baseline), 'catalogue': {'cards': 27, 'weapons': 54, 'families': 18, 'mcp306_present': False},
            'legacy_checks_run': not args.skip_legacy, 'verification_script_sha256': sha(__file__), 'streams': rows, 'requests': sum(r['requests'] for r in rows),
            'bytes': sum(r['bytes'] for r in rows), 'readonly_inputs': inputs,
            'scope': 'Explicit uninstalled candidate; registered legacy native/native and old-v3 raw oracle, current candidate native/WASM streams; new read-only home, live island, 3 seeds x 3 extraction islands, save/load/replay, unknown landing/physics honesty. No account/runtime/manifest write. Does not validate new terrain generation, new landing physics, visual quality, Android or economic content.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--wasm', type=Path, required=True)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--out', type=Path, default=ROOT / 'artifacts/world3d-integration-20261116/geography-verification')
    parser.add_argument('--node', default=shutil.which('node') or r'C:\Program Files\nodejs\node.exe')
    parser.add_argument('--skip-legacy', action='store_true', help='Development iteration only; receipt marks legacy coverage false')
    args = parser.parse_args()
    for key in ['candidate', 'wasm', 'baseline', 'out']:
        setattr(args, key, getattr(args, key).resolve())
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / 'receipt.json').write_text(json.dumps({'passed': False, 'running': True, 'candidate': str(args.candidate)}, indent=2), encoding='utf8')
    result = verify(args)
    file = args.out / 'receipt.json'
    file.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf8')
    print(json.dumps({'passed': True, 'streams': len(result['streams']), 'requests': result['requests'], 'receipt': str(file)}), flush=True)


if __name__ == '__main__':
    main()
