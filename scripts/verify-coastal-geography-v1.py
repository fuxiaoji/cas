"""Black-box validation of the explicit, uninstalled continuous-coast candidate.

The imported Demo is not enlarged. No account, installed binary, source oracle,
or normal-launch manifest is written. Native/WASM byte comparison is optional
for a fast local check, and the receipt explicitly records which was exercised.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('geography_verifier', ROOT / 'scripts/verify-geography-snapshot-v1.py')
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)
VERSION = 'cas-island-war-coastal-v1'


class Session:
    def __init__(self, args):
        self.args = args
        self.processes = [subprocess.Popen([str(args.candidate)], stdin=subprocess.PIPE, stdout=subprocess.PIPE)]
        if args.wasm:
            bridge = args.out / 'wasm-bridge.mjs'
            bridge.write_text(common.NODE_BRIDGE, encoding='utf8')
            self.processes.append(subprocess.Popen([args.node, str(bridge), str(args.wasm)], stdin=subprocess.PIPE, stdout=subprocess.PIPE))
        self.requests, self.digest, self.bytes = [], hashlib.sha256(), 0

    def call(self, request, ok=True):
        request = common.normalized(request)
        wire = (json.dumps(request, ensure_ascii=False, separators=(',', ':'), allow_nan=False) + '\n').encode('utf8')
        responses = []
        for proc in self.processes:
            proc.stdin.write(wire)
            proc.stdin.flush()
            responses.append(proc.stdout.readline())
        assert responses[0] and all(r == responses[0] for r in responses), ('native/WASM mismatch', len(self.requests), request['op'])
        self.requests.append(request)
        self.digest.update(responses[0])
        self.bytes += len(responses[0])
        response = json.loads(responses[0])
        assert response['ok'] is ok, (request['op'], response)
        return response['data'] if ok else response

    def close(self):
        for proc in self.processes:
            proc.stdin.close()
            assert proc.wait(timeout=30) == 0
        commands = self.args.out / 'commands.json'
        commands.write_text(json.dumps({'commands': self.requests}, ensure_ascii=False, indent=2), encoding='utf8')
        return {'requests': len(self.requests), 'response_bytes': self.bytes,
                'response_sha256': self.digest.hexdigest(), 'commands': str(commands),
                'commands_sha256': common.sha(commands), 'raw_native_wasm_identical': bool(self.args.wasm)}


def main(args):
    args.out.mkdir(parents=True, exist_ok=True)
    receipt_path = args.out / 'receipt.json'
    receipt_path.write_text(json.dumps({'passed': False, 'running': True}), encoding='utf8')
    inputs = {str(path): common.sha(path) for path in [args.candidate, args.map, ROOT / 'godot/bin/core-current.json']}
    if args.wasm:
        inputs[str(args.wasm)] = common.sha(args.wasm)
    grid = json.loads(args.map.read_text('utf8'))
    session = Session(args)
    metrics = []
    try:
        preview = session.call({'op': 'island_home_preview', 'version': VERSION, 'hq_level': 5, 'geography': grid})
        land = preview['littoral']['land']
        terrain = land['geography']
        assert terrain['version'] == 'cas-coastal-geography-v1'
        assert terrain['heightfield']['columns'] == terrain['heightfield']['rows'] == 181
        assert terrain['heightfield']['cell_size_m'] == 4
        assert land['bounds']['width'] == land['bounds']['height'] == 720
        assert len(land['polygon']) > 100
        assert land['terrain']['roads'] and all(r['authority'] == 'surface_only' and not r['bridge'] for r in land['terrain']['roads'])
        construction = preview['construction_grid']
        assert construction['cell_size_m'] == 36 and construction['legacy_120m_addresses_accepted'] is False
        assert len(construction['buildable_cells']) >= 13
        origin = construction['origin']

        def world(cell):
            return {'x': origin['x'] + (cell['x'] + .5) * 36,
                    'y': origin['y'] + (cell['y'] + .5) * 36}

        cells = sorted(construction['buildable_cells'], key=lambda c: (world(c)['x'] - 14600) ** 2 + (world(c)['y'] - 13045) ** 2)
        hq, depot = cells[:2]
        buildings = [{'id': 'coast-hq', 'kind': 'hq', 'cell': hq, 'level': 1, 'hp': 100},
                     {'id': 'coast-depot', 'kind': 'warehouse', 'cell': depot, 'level': 1, 'hp': 100}]
        populated = session.call({'op': 'island_home_preview', 'version': VERSION, 'hq_level': 5, 'geography': grid, 'buildings': buildings})
        assert all(b['terrain_buildable'] for b in populated['littoral']['land']['buildings'])
        placement = populated['island_war']['placement']
        forts = []
        for building in buildings:
            point = world(building['cell'])
            forts.append({'id': building['id'], 'kind': building['kind'], 'level': 1, 'hp': 100,
                          'x': (point['x'] - placement['origin']['x']) / placement['width_m'],
                          'y': (point['y'] - placement['origin']['y']) / placement['height_m']})
        initial = {'op': 'new_island_battle', 'version': VERSION, 'geography': grid,
                   'seed': 714, 'mode': 'exercise', 'company_layout': 'multi-company-v1',
                   'transport_preset': 'combat', 'ships': [{'id': 'CAS-O-APV-TIDEBRIDGE', 'hp': 100, 'ammo': 0}],
                   'roster': ['MCP-034'],
                   'island': {'npc_id': '', 'island_level': 1, 'forts': forts,
                              'storage': {'credits': 100, 'scrap': 50, 'alloy': 10, 'protocols': 0}},
                   'defender': {'ships': [{'id': 'CAS-O-APV-TIDEBRIDGE', 'hp': 100, 'ammo': 0}],
                                'roster': ['MCP-009'], 'unit_condition': [{'id': 'MCP-009', 'hp': 0}]}}
        view = session.call(initial)
        saved = session.call({'op': 'save'})
        assert saved['version'] == VERSION and saved['config']['geography'] == common.normalized(grid)
        snapshot = session.call({'op': 'geography_snapshot', 'points': [world(hq), world(depot)]})
        assert all(q['supported'] and q['height']['supported'] for q in snapshot['queries'])
        assert snapshot['land']['polygon'] == land['polygon']
        assert 'heightfield' not in view['littoral']['land']['geography']
        assert snapshot['land']['geography']['heightfield']['heights'] == terrain['heightfield']['heights']
        assert session.call({'op': 'save'}) == saved
        hash_before = snapshot['header']['geometry_hash']
        session.call({'op': 'island_autonomy', 'enabled': True, 'version': VERSION})
        observed_ground = False
        for tick in range(10, args.seconds + 1, 10):
            view = session.call({'op': 'step', 'seconds': 10})
            groups = view['littoral']['groups']
            phases = {}
            for group in groups:
                phase = group.get('stage', group.get('phase'))
                phases[phase] = phases.get(phase, 0) + 1
            observed_ground |= bool(phases.get('ground'))
            row = {'tick': tick, 'phases': phases, 'result': view.get('result'),
                   'transports': len(view['littoral'].get('transports', []))}
            metrics.append(row)
            print(json.dumps(row, ensure_ascii=False), flush=True)
            if view.get('result') is not None:
                break
        assert observed_ground, 'No company actually landed during the simulated operation'
        end = session.call({'op': 'save'})
        assert session.call({'op': 'load', 'save': end}) == view
        for tick in [0, 10, end['tick']]:
            replay = session.call({'op': 'replay', 'save': end, 'tick': tick})
        assert replay == view
        assert session.call({'op': 'geography_snapshot'})['header']['geometry_hash'] == hash_before
        if args.require_terminal:
            assert view.get('result') is not None, 'Autonomy did not reach an actual terminal result within the declared simulation budget'
        evidence = session.close()
    except BaseException:
        for proc in session.processes:
            proc.kill()
        raise
    assert inputs == {path: common.sha(path) for path in inputs}, 'Read-only input changed during verification'
    receipt = {'passed': True, 'script_sha256': common.sha(__file__), 'inputs_unchanged': inputs,
               'metres': 720, 'height_points': 181 * 181, 'shore_contour_points': len(land['polygon']),
               'registered_slots': len(terrain['landing_slots']), 'buildable_cells': len(cells),
               'observed_ground': observed_ground, 'terminal_required': args.require_terminal,
               'terminal_reached': view.get('result') is not None, 'metrics': metrics, **evidence,
               'scope': 'Explicit imported procedural map, native or native/WASM black-box only; no mobile/GPU/account claim'}
    receipt_path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding='utf8')
    print(json.dumps({'passed': True, 'receipt': str(receipt_path), **evidence}, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--wasm', type=Path)
    parser.add_argument('--node', default='C:/Program Files/nodejs/node.exe')
    parser.add_argument('--map', type=Path, default=ROOT / 'godot/data/coastal-demo-v1-714.json')
    parser.add_argument('--out', type=Path, default=ROOT / 'artifacts/world3d-integration-20261116/coastal-verification')
    parser.add_argument('--seconds', type=int, default=120)
    parser.add_argument('--require-terminal', action='store_true')
    main(parser.parse_args())
