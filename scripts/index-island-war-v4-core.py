"""Index immutable binaries and their scoped receipts; does not run or install."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib, json
ROOT=Path(__file__).resolve().parents[1]
FOLDER=ROOT/'artifacts/island-war-v4'
CORE=FOLDER/'core'
FROZEN=CORE/'frozen-final-211d162d832f0ce6'
def digest(file):return hashlib.sha256(file.read_bytes()).hexdigest()
def entry(file):return {'path':str(file.resolve()),'sha256':digest(file),'bytes':file.stat().st_size}
def receipt(file):
 if not file.exists():return {'path':str(file.resolve()),'pending':True}
 d=json.loads(file.read_text('utf8'))
 return {**entry(file),'passed':d.get('passed',d.get('ok',not d.get('failures'))),'data':d}
catalogue=json.loads((ROOT/'godot/data/island-war-v4.json').read_text('utf8'))
training=json.loads((CORE/'training-receipt.json').read_text('utf8'))
native=entry(FROZEN/'cas-sim.exe');wasm=entry(FROZEN/'cas_core.wasm')
assert native['sha256']=='211d162d832f0ce6ddbd0c44988c1b931402866afb606d1add6db0dadc6b97b4'
assert wasm['sha256']=='e38e3a61d0cbdab324ef8172a9362b69b37914039086e4a122f7b41eaca9fdb1'
evidence={
 'public_core':receipt(CORE/'receipt.json'),
 'home_and_battle_same_geometry':receipt(CORE/'home-battle-same-geometry.json'),
 'six_real_training_terminals':receipt(CORE/'training-receipt.json'),
 'shore_and_spg':receipt(CORE/'shore-artillery-receipt.json'),
 'new_native_wasm':receipt(FOLDER/'parity/receipt.json'),
 'shore_native_wasm':receipt(FOLDER/'parity/shore-artillery-receipt.json'),
 'historical_native_freeze':receipt(FOLDER/'parity/historical-freeze.json'),
 'historical_native_wasm':receipt(FOLDER/'parity/historical-wasm-receipt.json'),
 'explicit_replay_clock':receipt(FOLDER/'parity/replay-clock-receipt.json'),
 'old_v3_final_full_freeze':receipt(FOLDER/'parity/final-old-v3-freeze.json'),
 'old_versions_final_smoke':receipt(FOLDER/'parity/final-frozen-smoke.json'),
 'installed_equivalence':receipt(CORE/'installed-equivalence.json'),
 'legacy_browser':receipt(FOLDER/'browser-legacy/receipt.json'),
}
for key in ['public_core','six_real_training_terminals','shore_and_spg']:
 assert evidence[key]['data']['native_sha256']==native['sha256'],key
for key in ['new_native_wasm','shore_native_wasm','historical_native_wasm','explicit_replay_clock']:
 assert evidence[key]['data']['native_sha256']==native['sha256'] and evidence[key]['data']['wasm_sha256']==wasm['sha256'],key
assert evidence['legacy_browser']['data']['wasmSha256']==wasm['sha256']
fixture_names=['022-bodyless-snapshot','022-bodyless','manual-default-cover-snapshot','manual-default-cover','new-five-autonomy','shore-and-artillery',*[f'training-{l["lesson"]}-terminal' for l in training['lessons']]]
source_names=['src/lib.rs','src/island_war.rs','src/island_war_v4.rs','src/island_war_v4_base.rs','src/island_war_v4_roles.rs','src/island_war_v4_firearms.rs','src/island_war_v4_vehicles.rs','docs/design/tactical-v4-weapon-models.json']
external={name:entry(FOLDER/name) for name in ['presentation/bodyless-receipt.json','presentation/controls-receipt.json','home/receipt-ui.json','home/receipt-account.json','codex/receipt.json','codex/new-five-receipt.json'] if (FOLDER/name).exists()}
pending=[k for k,v in evidence.items() if v.get('pending')]
index={'format':'cas-island-war-v4-final-index-v1','generated_at':datetime.now(timezone.utc).isoformat(),
 'status':'awaiting_final_receipts' if pending else 'verified','pending':pending,
 'native':native,'wasm':wasm,
 'runtime_data':{'catalogue':entry(ROOT/'godot/data/island-war-v4.json'),'training':entry(ROOT/'godot/data/tactical-training-v4.json'),'personalities':len(catalogue['cards']),'concrete_weapon_models':len(catalogue['weapons']),'weapon_families':len(catalogue['weapon_families']),'body_health_scale':4},
 'relevant_rust_and_design_inputs':[entry(ROOT/f) for f in source_names],
 'evidence':evidence,'fixtures':{name:entry(CORE/(name+'.json')) for name in fixture_names},
 'rust_tests':[{'scope':'Eight final v4 accuracy/physical armor-cover/manual-command tests; final source','passed':8,'failed':0,**entry(ROOT/'artifacts/v4-rust-final-tests.log')},{'scope':'Broad 86 island tests, before final v4-only route precision/performance changes; targeted final eight rerun afterwards','passed':86,'failed':0,**entry(ROOT/'artifacts/v4-rust-all-island-tests.log')}],
 'external_ui_and_gpu_receipts':external,
 'notes':[entry(ROOT/'docs/rules/island-war-v4-contract.md'),entry(ROOT/'docs/rules/island-war-v4-source-notes.md')],
 'known_limits':['Highlands have real regional cover and cliffs block direct fire; continuous elevation-profile ballistic occlusion remains unimplemented.','Seven historical source_only ships remain unavailable to combat consumers.','Network multiplayer and complete historical carrier-aircraft rules are outside this original-island change.'],
 'isolation':'All core tests use isolated processes and legal initial configurations; no mid-battle HP/position snapshot edits, formal account writes, original PDF writes, or installation by the core agent.'}
if not pending:
 assert all(v['passed'] for v in evidence.values())
 assert evidence['old_v3_final_full_freeze']['data']['native_sha256']==native['sha256']
 assert evidence['installed_equivalence']['data']['candidate_sha256']==native['sha256']
index_path=CORE/'final-index.json';index_path.write_text(json.dumps(index,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'status':index['status'],'pending':pending,'index':str(index_path.resolve())}))
