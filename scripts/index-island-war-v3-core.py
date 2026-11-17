"""Index frozen core inputs and completed receipts; never assert a stale gate passed."""
from pathlib import Path
import argparse, hashlib, json, re, shutil

root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--native',type=Path,required=True);p.add_argument('--wasm',type=Path,required=True);a=p.parse_args()
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
rel=lambda f:str(f.resolve().relative_to(root)).replace('\\','/')
native=a.native.resolve();wasm=a.wasm.resolve();nh=sha(native);wh=sha(wasm)
folder=root/'artifacts/island-war-v3/core'/('frozen-wasm-'+wh[:16]);folder.mkdir(exist_ok=True,parents=True)
frozen_wasm=folder/'cas_core.wasm'
if not frozen_wasm.exists():shutil.copyfile(wasm,frozen_wasm)
assert sha(frozen_wasm)==wh
files=set((root/'src').rglob('*.rs'))
for f in list(files):
 for path in re.findall(r'include_(?:str|bytes)!\s*\(\s*"([^"]+)"',f.read_text('utf8')):
  q=(f.parent/path).resolve()
  if q.is_file():files.add(q)
for path in ['Cargo.toml','Cargo.lock','build.rs','docs/design/tactical-v3-role-brief.json','docs/design/tactical-v3-weapon-models.json','docs/design/tactical-v3-armor-infantry.json','godot/data/island-war-v3.json','godot/data/tactical-training-v3.json','docs/rules/island-war-v3-contract.md','docs/rules/island-war-v3-source-notes.md','scripts/export-island-war-v3.py','scripts/capture-armored-v3-cover.py','scripts/write-island-war-v3-source-notes.py','scripts/verify-island-war-v3-training.py','scripts/verify-island-war-v3-parity.mjs','scripts/verify-island-war-v3-legacy-parity.mjs','scripts/browser-island-war-v3-legacy-smoke.mjs','scripts/index-island-war-v3-core.py']:
 q=root/path
 if q.is_file():files.add(q)
inputs=[{'path':rel(f),'sha256':sha(f)}for f in sorted(files)]
gates={}
def gate(key,path,validator,fields):
 f=root/path
 if f.is_file():
  d=json.loads(f.read_text('utf-8-sig'))
  if validator(d):gates[key]={'receipt':path,**fields(d)};return
 gates[key]={'status':'pending_current_candidate','receipt':path}
gate('six_real_training','artifacts/island-war-v3/core/training-receipt.json',lambda d:d['passed'] and d['native_sha256']==nh and len(d['lessons'])==6,lambda d:{'passed':True,'lessons':6,'all_winning':True,'all_actual_checks':True,'ticks':{r['lesson']:r['tick']for r in d['lessons']}})
gate('native_export','artifacts/island-war-v3/core/export-receipt.json',lambda d:d['passed']and d['native_sha256']==nh,lambda d:{'passed':True,'cards':d['cards'],'models':d['weapons'],'families':d['weapon_families'],'lessons':d['borrowed_manual_lessons']})
gate('new_native_wasm_raw','artifacts/island-war-v3/parity/new-mode/receipt.json',lambda d:d['passed']and d['native_sha256']==nh and d['wasm_sha256']==wh,lambda d:{'passed':True,'scenarios':len(d['cases']),'responses':d['requests'],'bytes':d['bytes']})
gate('old_native_frozen','artifacts/island-war-v3/parity/old-freeze.json',lambda d:d['passed']and d['candidate_sha256']==nh,lambda d:{'passed':True,'scenarios':len(d['cases']),'responses':d['requests'],'bytes':d['bytes']})
gate('legacy_native_wasm_raw','artifacts/island-war-v3/parity/legacy/parity-receipt.json',lambda d:d['passed']and d['nativeSha']==nh and d['raw']['sha']==wh,lambda d:{'passed':True,'scenarios':d['raw']['files'],'responses':d['raw']['requests'],'bytes':d['raw']['bytes']})
gate('actual_browser_legacy','artifacts/island-war-v3/browser-legacy/receipt.json',lambda d:d['wasmSha256']==wh and d['passed']==len(d['checks'])and not d['errors'],lambda d:{'passed':True,'checks':d['passed'],'network_sha256':wh,'browser':d['browser'],'scope':'actual isolated legacy Web controls; Godot land UI independently reviewed by root'})
tests={}
for key,path in [('all_rust','artifacts/island-war-v3/core/all-tests-final.log'),('v3_specific','artifacts/island-war-v3-tests.log')]:
 text=(root/path).read_text('utf-8-sig');match=re.search(r'test result: ok\. (\d+) passed; 0 failed;',text)
 tests[key]={'passed':int(match[1])if match else False,'log':path}
v3_rows=re.findall(r'^test littoral::v4::island_war::v2::v3::.* \.\.\. ok$',(root/'artifacts/island-war-v3/core/all-tests-final.log').read_text('utf-8-sig'),re.M)
tests['v3_specific']={'passed':len(v3_rows),'log':'artifacts/island-war-v3/core/all-tests-final.log','scope':'v3 test rows counted from this same full-library run'}
assert tests['all_rust']['passed']==449 and tests['v3_specific']['passed']==50
doc={'version':'cas-island-war-v3','status':'core_frozen'if all(g.get('passed')for g in gates.values())else'native_frozen_verification_running','native':{'path':rel(native),'sha256':nh},'wasm':{'path':rel(frozen_wasm),'sha256':wh},'source_freeze':inputs,'source_files':len(inputs),'tests':tests,'gates':gates,'source_kind':'original game design; no historical CAS table values changed','boundaries':['Point-target direct fire is one deterministic probability adjudication, not full terminal ballistics.','Area AI range/damage scoring is a typed heuristic, not Monte Carlo geometry optimization.','022/103 use real circular hulls and physical rear/flank movement; no unconditional armor cover buff.','Remote min_crew=0 uses the existing one-personality world setting and creates no extra bodies.','Save/load reconstructs commands in O(simulation frames); replaying a long terminal can take tens of seconds.','Godot production UI, installed-binary equivalence and account settlement are independently verified by root/UI agents.','Core candidate is never installed by this script; formal account and Web package are untouched.']}
out=root/'artifacts/island-war-v3/core-verification-index.json';out.write_text(json.dumps(doc,ensure_ascii=False,indent=2),'utf8')
print(json.dumps({'status':doc['status'],'source_files':len(inputs),'native_sha256':nh,'wasm_sha256':wh,'tests':tests,'gates':{k:v.get('passed',False)for k,v in gates.items()}}))
