"""Index the isolated27-person river final; never rebuilds shared development."""
from pathlib import Path
from datetime import datetime,timezone
import argparse,hashlib,json
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--installed',type=Path);a=p.parse_args()
F=ROOT/'artifacts/island-war-v4';C=F/'core';N=C/'frozen-final-5edacf8b5da2a12d';S=F/'source-27-river';P=F/'river-parity'
def entry(p):return {'path':str(p.resolve()),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size}
def receipt(p):
 if not p.exists():return {'path':str(p.resolve()),'pending':True}
 d=json.loads(p.read_text('utf8'));return {**entry(p),'passed':bool(d.get('passed',d.get('ok',not d.get('failures')))),'data':d}
native=entry(N/'cas-sim.exe');wasm=entry(N/'cas_core.wasm');assert native['sha256']=='5edacf8b5da2a12d0690dd48a1ae698e5981b4204a535d2e3f763b9e95e92295';assert wasm['sha256']=='8fd63262e3644ec997b8145b6b2db89026d0a9c4dfdf4d48c1c4601d89b84d6c'
evidence={key:receipt(path) for key,path in {
 'same_data':C/'same-data-receipt.json','public_core':C/'receipt.json','six_training_terminals':C/'training-receipt.json','cover_and_new_five':C/'cover-and-five-receipt.json','shore_and_artillery':C/'shore-artillery-receipt.json','river_and_bridge':C/'river-receipt.json','new_native_wasm':P/'receipt.json','water_shore_native_wasm':P/'water-shore-receipt.json'}.items()}
pending=[k for k,v in evidence.items() if v.get('pending')]
for k,r in evidence.items():
 if r.get('pending'):continue
 assert r['passed'],k
 assert r['data']['native_sha256']==native['sha256'],k
 if 'wasm_sha256' in r['data']:assert r['data']['wasm_sha256']==wasm['sha256'],k
published=ROOT/'godot/data/island-war-v4-published.json';assert published.read_bytes()==(N/'data/island-war-v4.json').read_bytes();assert hashlib.sha256(published.read_bytes()).hexdigest()=='93b93830df79949bb676a2bea447c23514438b306d313f9da97d460bfafb5583'
fixtures={name:entry(C/(name+'.json')) for name in ['022-bodyless-snapshot','022-bodyless','manual-default-cover-snapshot','manual-default-cover','new-five-autonomy','shore-and-artillery','river-water-and-bridge',*[f'training-{lesson}-terminal' for lesson in ['landing','weapons','artillery','airborne','roles','combined_arms']]] if (C/(name+'.json')).exists()}
root_acceptance={key:receipt(F/path) for key,path in {'interactive_bodyless_cover':'presentation/bodyless-receipt.json','story_settlement':'presentation/story-receipt.json','formal_profile_copies':'presentation/formal-profile-receipt.json','legacy_browser':'browser-legacy/receipt.json'}.items()}
assert all(not r.get('pending') and r['passed'] for r in root_acceptance.values())
assert Path(root_acceptance['interactive_bodyless_cover']['data']['native_path']).resolve()==(N/'cas-sim.exe').resolve()
assert root_acceptance['legacy_browser']['data']['wasmSha256']==wasm['sha256']
installed={'state':'root_exact_binary_install_pending','expected_sha256':native['sha256']}
if a.installed:
 installed={'state':'exact_frozen_binary_verified',**entry(a.installed)};assert installed['sha256']==native['sha256']
index={'format':'cas-island-war-v4-published27-final-index-v1','generated_at':datetime.now(timezone.utc).isoformat(),'core_status':'awaiting_final_receipts' if pending else 'verified','pending':pending,'native':native,'wasm':wasm,'installed':installed,'runtime_data':{'published_catalogue':entry(published),'frozen_catalogue':entry(N/'data/island-war-v4.json'),'frozen_training':entry(N/'data/tactical-training-v4.json'),'personalities':27,'weapon_models':54,'weapon_families':18,'body_health_scale':4},'source_snapshot':entry(S/'snapshot-manifest.json'),'source_only_patch':entry(C/'river-only.patch'),'evidence':evidence,'fixtures':fixtures,'rust_tests':{'scope':'Eight final v4 accuracy/physical-cover/manual-command tests against the isolated27-person river source','passed':8,'failed':0,**entry(ROOT/'artifacts/v4-source27-rust-tests.log')},'root_acceptance':root_acceptance,'root_acceptance_binding':'Parent confirmed these were rerun against5ed/8fd: interactive128checks34inputs, story89, formal-copy10, browser18. Native path and served WASM SHA are embedded in interactive/browser receipts; story/formal-copy receipts have scope/counts and parent run binding.','prior_verified_freeze':entry(C/'frozen-final-211d162d832f0ce6/evidence/final-index.json'),'prior_freeze_scope':'The211d prior freeze retains24 old-v3 streams566requests, old-version smoke67responses, twelve historical seats84responses, native/WASM483responses, Edge18 and d0ff normal-launch equivalence23streams483responses. This patch changes only v4 vehicle water/bridge classification and speed; exact registered source/input comparisons are in same_data. Prior GUI receipt hashes retain their at-capture provenance; new river-final root GUI receipts are listed separately.','archive_correction':entry(C/'frozen-final-211d162d832f0ce6/evidence/archive-correction.json'),'notes':[entry(ROOT/'docs/rules/island-war-v4-contract.md'),entry(ROOT/'docs/rules/island-war-v4-source-notes.md')],'known_limits':['Regional highland cover and cliff line-of-sight are implemented; continuous elevation-profile ballistic occlusion remains unimplemented.','Seven historical source_only ships remain unavailable to combat consumers.','The concurrent306 extension remains a separate unverified development draft and is excluded from this published27-person binary/data.'],'isolation':'Only independently copied123-file source/input snapshot compiled. Original PDFs/reference project/formal accounts untouched. No mid-battle HP/position edits. Install this exact frozen binary; do not rebuild this release from the mutable shared28-person source tree.'}
if not pending:
 cases=evidence['new_native_wasm']['data']['cases']+evidence['water_shore_native_wasm']['data']['cases']
 index['new_native_wasm_totals']={'cases':len(cases),'requests':sum(r['requests'] for r in cases),'bytes':sum(r['bytes'] for r in cases),'raw_identical':True}
(C/'final-index.json').write_text(json.dumps(index,ensure_ascii=False,indent=2),encoding='utf8');print(json.dumps({'core_status':index['core_status'],'pending':pending,'index':str(C/'final-index.json')}))
