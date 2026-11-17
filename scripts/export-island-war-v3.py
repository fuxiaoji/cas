"""Export v3's single runtime catalogue and validate borrowed training construction.
All engine processes are isolated in memory; this never reads or changes an account.
"""
from pathlib import Path
import argparse,json,subprocess,hashlib
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--native',type=Path,required=True);p.add_argument('--output',type=Path,default=ROOT/'godot/data/island-war-v3.json');p.add_argument('--training',type=Path,default=ROOT/'godot/data/tactical-training-v3.json');a=p.parse_args()
def call(request):
 r=subprocess.run([str(a.native.resolve())],input=json.dumps(request,ensure_ascii=False)+'\n',capture_output=True,text=True,encoding='utf8',check=True);r=json.loads(r.stdout);assert r['ok'],r;return r['data']
catalogue=call({'op':'island_war_catalogue','version':'cas-island-war-v3'});assert catalogue['version']=='cas-island-war-v3';assert len(catalogue['cards'])==22;assert len(catalogue['weapons'])==43;assert len(catalogue['weapon_families'])==18
for c in catalogue['cards']:assert len(c['weapon_composition'])==c['personnel_per_company']
training=json.loads(a.training.read_text('utf8'));assert set(training['lessons'])=={'landing','weapons','artillery','airborne','roles','combined_arms'}
for name,lesson in training['lessons'].items():
 q=lesson['request'];assert q['lesson']==name and q['mode']=='exercise' and q['version']=='cas-island-war-v3';v=call(q);assert v['littoral']['training']['lesson']==name;assert not v['littoral']['autonomy']['enabled']
a.output.parent.mkdir(exist_ok=True,parents=True);tmp=a.output.with_suffix('.tmp');tmp.write_text(json.dumps(catalogue,ensure_ascii=False,indent=2),'utf8');tmp.replace(a.output)
print(json.dumps({'passed':True,'native_sha256':hashlib.sha256(a.native.read_bytes()).hexdigest(),'catalogue_sha256':hashlib.sha256(a.output.read_bytes()).hexdigest(),'training_sha256':hashlib.sha256(a.training.read_bytes()).hexdigest(),'cards':22,'weapons':len(catalogue['weapons']),'weapon_families':18,'borrowed_manual_lessons':6}))
