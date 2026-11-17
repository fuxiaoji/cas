"""Isolated public-command audits; never opens a real account or edits snapshots."""
import argparse, hashlib, json, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--native',type=Path,required=True);p.add_argument('--training',type=Path,default=ROOT/'godot/data/tactical-training-v4.json');p.add_argument('--out',type=Path,default=ROOT/'artifacts/island-war-v4/core');args=p.parse_args();args.out.mkdir(parents=True,exist_ok=True)
class Session:
 def __init__(self,name):self.name=name;self.commands=[];self.process=subprocess.Popen([str(args.native.resolve())],stdin=subprocess.PIPE,stdout=subprocess.PIPE);self.view=None
 def call(self,q,ok=True):
  self.commands.append(q);self.process.stdin.write((json.dumps(q,ensure_ascii=False)+'\n').encode());self.process.stdin.flush();r=json.loads(self.process.stdout.readline());assert r['ok']==ok,(q,r)
  if ok and 'ships' in r['data']:self.view=r['data']
  return r.get('data',r)
 def close(self):
  save=self.call({'op':'save'}) if self.view else None
  if save:
   old=self.view;self.call({'op':'load','save':save});assert old==self.view
  (args.out/(self.name+'.json')).write_text(json.dumps({'commands':self.commands,'view':self.view,'save':save},ensure_ascii=False),encoding='utf8');self.process.stdin.close();self.process.wait(timeout=10)
def base(roster):
 q=json.loads(args.training.read_text('utf8'))['lessons']['landing']['request'];q.pop('lesson',None);q.pop('training_delay_seconds',None);q['roster']=roster;q['defender']['ships']=[{'id':'CAS-O-APV-TIDEBRIDGE','hp':100,'ammo':0}];q['defender']['unit_condition']=[{'id':'MCP-034','hp':100}];return q
s=Session('catalogue-and-preview');c=s.call({'op':'island_war_catalogue','version':'cas-island-war-v4'});assert len(c['cards'])==27
for row in c['cards']:assert row['body_stats']['hp']==row['body_stats']['baseline_hp']*4 and len(row['weapon_composition'])==row['personnel_per_company']
positions=[]
for level in range(1,6):
 v=s.call({'op':'island_home_preview','version':'cas-island-war-v4','seed':714,'hq_level':level,'buildings':[{'id':'hq','kind':'hq','cell':{'x':6,'y':4},'level':level,'hp':100}]});positions.append(v['littoral']['land']['buildings'][0]['world_position']);assert v['island_war']['width_m']==3200+(level-1)*1200
assert positions.count(positions[0])==5;s.close()
s=Session('022-bodyless');q=base(['MCP-022']);q['unit_condition']=[{'id':'MCP-022','hp':1}];q['vehicle_condition']=[{'id':'MCP-022','company':i,'hp_percent':100} for i in range(1,4)];v=s.call(q)
for row in v['littoral']['groups']:s.call({'op':'littoral_deploy','company_id':row['company_id'],'beach':2})
for n in range(40):
 v=s.call({'op':'step','seconds':5});groups=v['littoral']['groups'];vehicles=v['littoral']['land']['combat_vehicles']
 dead=[r for r in groups if r['personnel_count']==0]
 if dead and any(r['company_id']==dead[0]['company_id'] and r['hp']>0 and r['active'] for r in vehicles):break
 for row in groups:
  if row['stage']=='ground':s.call({'op':'littoral_order','company_id':row['company_id'],'action':'move','x':14600,'y':13000})
else:raise AssertionError('real bodyless tank state required')
snapshot=s.call({'op':'save'});(args.out/'022-bodyless-snapshot.json').write_text(json.dumps(snapshot,ensure_ascii=False),encoding='utf8')
tank=next(r for r in vehicles if r['company_id']==dead[0]['company_id'] and r['hp']>0);vid=tank['id'];initial_ammo=tank['ammo'];initial_x=tank['x'];cid=tank['company_id']
s.call({'op':'littoral_vehicle_order','vehicle_id':vid,'action':'face','x':15000,'y':13000});s.call({'op':'littoral_vehicle_order','vehicle_id':vid,'action':'fire_at','x':999,'y':999},ok=False)
s.call({'op':'littoral_vehicle_order','vehicle_id':vid,'action':'move','x':13850,'y':13000})
for n in range(8):v=s.call({'op':'step','seconds':5})
tank=next(r for r in v['littoral']['land']['combat_vehicles'] if r['id']==vid);assert tank['x']>initial_x+300 and tank['ammo']<initial_ammo and tank['hp']>0
for row in v['littoral']['groups']:s.call({'op':'littoral_order','company_id':row['company_id'],'action':'extract'})
for n in range(80):
 v=s.call({'op':'step','seconds':5});vehicles=v['littoral']['land']['combat_vehicles']
 if all(r['phase']=='recovered' for r in vehicles if r['side']=='allies' and r['hp']>0):break
else:raise AssertionError('bodyless tank must physically recover')
v=s.call({'op':'littoral_abandon'});out=v['result']['vehicles'];assert any(r['vehicle_id']==vid and r['recovered'] and not r['lost'] for r in out);s.close()
(args.out/'receipt.json').write_text(json.dumps({'passed':True,'native_sha256':hashlib.sha256(args.native.read_bytes()).hexdigest(),'scope':'27 catalogue HP and loadout; HQ1-5 stable cells; real initial 1% infantry/100% equipment 022 deaths, vehicle move/fire/recovery/account-independent result; no snapshot edits'},ensure_ascii=False,indent=2),encoding='utf8');print('v4 public command checks passed')
