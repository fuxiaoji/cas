"""The published27-person river patch must preserve all content inputs."""
from pathlib import Path
import argparse, hashlib, json, subprocess, difflib
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--native',type=Path,required=True);p.add_argument('--snapshot',type=Path,required=True);p.add_argument('--out',type=Path,default=ROOT/'artifacts/island-war-v4/river-core');a=p.parse_args();a.out.mkdir(parents=True,exist_ok=True)
old=ROOT/'artifacts/island-war-v4/core/frozen-final-211d162d832f0ce6';prior=old/'evidence';index=json.loads((prior/'final-index.json').read_text('utf8'))
processes=[subprocess.Popen([str(exe.resolve())],stdin=subprocess.PIPE,stdout=subprocess.PIPE) for exe in [old/'cas-sim.exe',a.native]];rows=[];catalogue=None
try:
 queries=[{'op':'island_war_catalogue','version':'cas-island-war-v4'},*[{'op':'island_home_preview','version':'cas-island-war-v4','seed':714,'hq_level':level,'buildings':[{'id':'hq','kind':'hq','cell':{'x':6,'y':4},'level':1,'hp':100},{'id':'warehouse','kind':'warehouse','cell':{'x':7,'y':4},'level':1,'hp':100}],'candidate':{'kind':'warehouse','cell':{'x':4,'y':4}}} for level in range(1,6)]]
 for q in queries:
  replies=[];wire=(json.dumps(q,ensure_ascii=False)+'\n').encode('utf8')
  for proc in processes:proc.stdin.write(wire);proc.stdin.flush();replies.append(proc.stdout.readline())
  assert replies[0]==replies[1],q
  r=json.loads(replies[0]);assert r['ok'],r
  if q['op']=='island_war_catalogue':catalogue=r['data']
  rows.append({'op':q['op'],'hq_level':q.get('hq_level'),'raw_identical':True,'response_sha256':hashlib.sha256(replies[0]).hexdigest()})
finally:
 for proc in processes:proc.stdin.close();proc.wait(timeout=30)
assert len(catalogue['cards'])==27 and len(catalogue['weapons'])==54 and len(catalogue['weapon_families'])==18
export=a.out/'island-war-v4.json';export.write_text(json.dumps(catalogue,ensure_ascii=False,indent=2),encoding='utf8');baseline=ROOT/'output/tactical-codex-v4-20261115/baseline-native.json';assert export.read_bytes()==baseline.read_bytes()
training=a.snapshot/'godot/data/tactical-training-v4.json';assert hashlib.sha256(training.read_bytes()).hexdigest()==index['runtime_data']['training']['sha256']
source_rows=[]
for item in index['relevant_rust_and_design_inputs']:
 original=Path(item['path']);rel=original.relative_to(prior/'source');candidate=a.snapshot/rel
 if original.name=='island_war_v4_vehicles.rs':
  diff=''.join(difflib.unified_diff(original.read_text('utf8').splitlines(True),candidate.read_text('utf8').splitlines(True),fromfile='211d/'+str(rel),tofile='27-river/'+str(rel)))
  (a.out/'river-only.patch').write_text(diff,encoding='utf8')
 else:assert hashlib.sha256(candidate.read_bytes()).hexdigest()==item['sha256'],str(rel)
 source_rows.append({'path':str(rel),'original_sha256':item['sha256'],'new_sha256':hashlib.sha256(candidate.read_bytes()).hexdigest(),'same':original.read_bytes()==candidate.read_bytes()})
assert sum(not r['same'] for r in source_rows)==1
receipt={'passed':True,'native_sha256':hashlib.sha256(a.native.read_bytes()).hexdigest(),'baseline_sha256':hashlib.sha256((old/'cas-sim.exe').read_bytes()).hexdigest(),'catalogue_sha256':hashlib.sha256(export.read_bytes()).hexdigest(),'training_sha256':hashlib.sha256(training.read_bytes()).hexdigest(),'cards':27,'weapons':54,'families':18,'same_raw_queries':rows,'source_inputs':source_rows,'scope':'Exact27-person runtime export bytes, teaching input bytes, all HQ1-5 complete terrain/building/placement/buildability observations and registered source inputs unchanged; only v4 vehicle river/bridge speed+movement-domain source differs. Shared28-person development source/export not modified.'}
(a.out/'same-data-receipt.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf8');print(json.dumps(receipt))
