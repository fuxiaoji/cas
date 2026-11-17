"""Real public commands only. Separate memory session; no user account."""
import json,subprocess,hashlib
from pathlib import Path
R=Path(__file__).resolve().parents[1]
exe=R/'target-sixth/release/cas-sim.exe'
out=R/'artifacts/sixth-infantry';out.mkdir(exist_ok=True,parents=True)
p=subprocess.Popen([str(exe)],stdin=subprocess.PIPE,stdout=subprocess.PIPE)
commands=[];responses=[]
def call(q,ok=True):
 commands.append(q);p.stdin.write((json.dumps(q,ensure_ascii=False)+'\n').encode());p.stdin.flush()
 raw=p.stdout.readline();r=json.loads(raw);responses.append(raw.decode().strip());assert r['ok']==ok,(q,r)
 return r.get('data',r)
c=call({'op':'island_war_catalogue','version':'cas-island-war-v4'})
card=next(r for r in c['cards'] if r['id']=='MCP-306');assert card['body_count']==20 and card['company_count']==2 and card['body_stats']['hp']==360
q=json.loads((R/'godot/data/tactical-training-v4.json').read_text('utf8'))['lessons']['landing']['request']
for k in ['lesson','training_delay_seconds']:q.pop(k,None)
q['roster']=['MCP-306'];q['unit_condition']=[{'id':'MCP-306','hp':40}]
q['ships']=[{'id':'CAS-O-APV-TIDEBRIDGE','hp':100,'ammo':0}]
q['defender']['ships']=[{'id':'CAS-O-APV-TIDEBRIDGE','hp':100,'ammo':0}]
q['defender']['unit_condition']=[{'id':'MCP-034','hp':100}]
v=call(q);groups=v['littoral']['groups'];assert len(groups)==2
for g in groups:call({'op':'littoral_deploy','company_id':g['id'],'beach':2})
for _ in range(100):
 v=call({'op':'step','seconds':2})
 if all(g['stage']=='ground' for g in v['littoral']['groups']):break
else:raise AssertionError('physical landing did not complete')
cid=v['littoral']['groups'][0]['id']
def own(view):return [r for r in view['littoral']['land']['entities'] if r.get('company_id')==cid and r.get('hp',0)>0]
before={r['id']:r for r in own(v)};assert len(before)==10
v=call({'op':'littoral_ability','company_id':cid})
for r in own(v):
 b=before[r['id']];assert abs(r['hp']-min(b['max_hp'],b['hp']+90))<1e-8;assert r['ammo']==b['ammo'];assert r['passive']['damage_multiplier']<b['passive']['damage_multiplier']
call({'op':'littoral_ability','company_id':cid},False)
# Enable actual commander; real fire, finite ammo and casualties, terminal recovery.
v=call({'op':'littoral_autonomy','enabled':True})
fired=False
for _ in range(240):
 v=call({'op':'step','seconds':5})
 if any(r.get('unit_id')=='MCP-306' and r.get('ammo',60)<60 for r in v['littoral']['land']['entities']):fired=True
 if v.get('result'):break
assert fired,'actual rifle shots required'
assert v.get('result'),'real session must finish'
terminal=v;save=call({'op':'save'});loaded=call({'op':'load','save':save});assert loaded==terminal
(out/'public-session.json').write_text(json.dumps({'commands':commands,'responses':responses,'save':save},ensure_ascii=False),'utf8')
(out/'receipt.json').write_text(json.dumps({'passed':True,'requests':len(commands),'native_sha256':hashlib.sha256(exe.read_bytes()).hexdigest(),'actual_landing':True,'company_local_heal':True,'cooldown_rejected':True,'actual_rifle_fire':fired,'terminal':v.get('result'),'save_load_identical':True},ensure_ascii=False,indent=2),'utf8')
p.stdin.close();p.wait(timeout=10);print('sixth infantry public session passed',len(commands))
