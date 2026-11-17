"""Real sea/river/bridge vehicle movement through public commands only."""
from pathlib import Path
import argparse, hashlib, json, math, subprocess
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--native',type=Path,required=True);p.add_argument('--out',type=Path,default=ROOT/'artifacts/island-war-v4/river-core');a=p.parse_args();a.out.mkdir(parents=True,exist_ok=True)
proc=subprocess.Popen([str(a.native.resolve())],stdin=subprocess.PIPE,stdout=subprocess.PIPE);commands=[];samples=[]
def call(q):
 commands.append(q);proc.stdin.write((json.dumps(q,ensure_ascii=False)+'\n').encode('utf8'));proc.stdin.flush();r=json.loads(proc.stdout.readline());assert r['ok'],(q,r);return r['data']
def inside(p,poly):
 result=False
 for u,v in zip(poly,poly[1:]+poly[:1]):
  if (u['y']>p['y'])!=(v['y']>p['y']) and p['x']<(v['x']-u['x'])*(p['y']-u['y'])/(v['y']-u['y'])+u['x']:result=not result
 return result
try:
 q=json.loads((ROOT/'artifacts/island-war-v4/core/manual-default-cover.json').read_text('utf8'))['commands'][0];q['roster']=['MCP-103','MCP-304','MCP-305'];q['defender']['unit_condition']=[{'id':'MCP-034','hp':15}]
 q['island']['forts']=[{'id':'river-test-hq','kind':'hq','x':0.85,'y':0.80,'level':1,'hp':100},{'id':'river-test-depot','kind':'warehouse','x':0.80,'y':0.85,'level':1,'hp':100}]
 v=call(q);cids={u:u+'-C01' for u in q['roster']};stats={u:{'sea':[],'river':[],'bridge':[],'land':[]} for u in cids}
 def sample(v):
  land=v['littoral']['land'];features=land['terrain']['features']
  for vehicle in land['combat_vehicles']:
   u=vehicle['unit_id']
   if u not in cids or vehicle['company_id']!=cids[u] or not vehicle['active']:continue
   river=any(f['kind']=='river' and inside(vehicle,f['polygon']) for f in features)
   bridge=river and any(f['kind'] in ['ford','road'] and inside(vehicle,f['polygon']) for f in features)
   where='bridge' if bridge else 'river' if river else 'land' if inside(vehicle,land['polygon']) else 'sea'
   if where in ['river','sea']:assert vehicle['movement_domain']=='water',(where,vehicle)
   if where=='bridge':assert vehicle['movement_domain']=='land',vehicle
   speed=math.hypot(vehicle['velocity']['x'],vehicle['velocity']['y'])
   if speed>0.1:stats[u][where].append(speed)
   if where in ['river','bridge']:samples.append({'tick':v['tick'],'unit_id':u,'where':where,'x':vehicle['x'],'y':vehicle['y'],'speed':speed,'movement_domain':vehicle['movement_domain']})
 for u,cid in cids.items():call({'op':'littoral_deploy','company_id':cid,'beach':2,'x':15300,'y':13680})
 for _ in range(240):
  v=call({'op':'step','seconds':0.5});sample(v)
  vehicles={r['unit_id']:r for r in v['littoral']['land']['combat_vehicles'] if r['company_id'] in cids.values()}
  if all(stats[u]['river'] and vehicles[u]['phase']=='active' for u in cids):break
 else:raise AssertionError(('actual off-bridge river crossing required',stats))
 # Use the real narrow bridge one vehicle at a time, so traffic avoidance
 # cannot legitimately steer a faster amphibian off its 24m roadway.
 for u in cids:
  r=next(r for r in v['littoral']['land']['combat_vehicles'] if r['company_id']==cids[u])
  call({'op':'littoral_vehicle_order','vehicle_id':r['id'],'action':'move','x':15100,'y':13000})
  for _ in range(100):
   v=call({'op':'step','seconds':0.5});sample(v);vehicle=next(r for r in v['littoral']['land']['combat_vehicles'] if r['company_id']==cids[u])
   if math.hypot(vehicle['x']-15100,vehicle['y']-13000)<10.1:break
  else:raise AssertionError(('bridge approach required',u,vehicle['x'],vehicle['y']))
  call({'op':'littoral_vehicle_order','vehicle_id':r['id'],'action':'move','x':14200,'y':13000})
  for _ in range(100):
   v=call({'op':'step','seconds':0.5});sample(v);vehicle=next(r for r in v['littoral']['land']['combat_vehicles'] if r['company_id']==cids[u])
   if vehicle['x']<14600 and stats[u]['bridge']:break
  else:raise AssertionError(('bridge crossing required',u,vehicle['x'],vehicle['y']))
 for u,water in [('MCP-103',32),('MCP-304',40),('MCP-305',24)]:
  assert stats[u]['sea'] and stats[u]['river'] and stats[u]['bridge'] and stats[u]['land'],(u,stats[u])
  assert max(stats[u]['river'])<=water*0.8+0.01,(u,stats[u]['river'])
  assert max(stats[u]['sea'])<=water+0.01,(u,stats[u]['sea'])
  assert max(stats[u]['bridge'])>water*1.5,(u,stats[u]['bridge'])
 save=call({'op':'save'});(a.out/'river-water-and-bridge.json').write_text(json.dumps({'commands':commands,'view':v,'save':save,'samples':samples},ensure_ascii=False),encoding='utf8')
 receipt={'passed':True,'native_sha256':hashlib.sha256(a.native.read_bytes()).hexdigest(),'rows':[{ 'unit_id':u,**{where:{'samples':len(values),'max_speed_mps':max(values) if values else None} for where,values in buckets.items()}} for u,buckets in stats.items()], 'scope':'Public initial configuration only: real outer-sea approach, off-bridge river swimming, inland movement, and a commanded 24m bridge crossing for103/304/305; no HP or position snapshot edits.'}
 (a.out/'river-receipt.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf8');print(json.dumps(receipt))
finally:proc.stdin.close();proc.wait(timeout=30)
