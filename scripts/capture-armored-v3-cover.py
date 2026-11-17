"""Capture real public-command armored-infantry arrival; never edits a live body."""
from pathlib import Path
import argparse,json,math,subprocess
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--native',type=Path,required=True);p.add_argument('--unit',choices=['MCP-022','MCP-103'],required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
q=json.loads((root/'godot/data/tactical-training-v3.json').read_text('utf8'))['lessons']['combined_arms']['request']
q['roster']=[a.unit];q.pop('lesson',None);q.pop('training_delay_seconds',None);q['defender']['unit_condition']=[];q['defender']['ships'][0]['hp']=100
process=subprocess.Popen([str(a.native.resolve())],stdin=subprocess.PIPE,stdout=subprocess.PIPE);commands=[]
def call(q):
 commands.append(q);process.stdin.write((json.dumps(q,separators=(',',':'))+'\n').encode());process.stdin.flush();r=json.loads(process.stdout.readline());assert r['ok'],r;return r['data']
try:
 call(q);call({'op':'island_autonomy','enabled':True})
 for i in range(480):
  v=call({'op':'step','seconds':.5});land=v['littoral']['land'];vehicles={t['id']:t for t in land['combat_vehicles']}
  for b in land['entities']:
   if b.get('unit_id')!=a.unit or b.get('tactical_state')!='covered' or b.get('hp',0)<=0:continue
   t=vehicles[b['cover_vehicle_id']];goal=b['tactical_goal'];error=math.hypot(b['x']-goal['x'],b['y']-goal['y']);rear=math.hypot(b['x']-t['x'],b['y']-t['y'])
   if error<3 and 5<rear<35:
    saved=call({'op':'save'});e={'tick':v['tick'],'body_id':b['id'],'company_id':b['company_id'],'vehicle_id':t['id'],'body_position':{'x':b['x'],'y':b['y']},'vehicle_position':{'x':t['x'],'y':t['y']},'actual_goal':goal,'goal_distance_m':error,'vehicle_distance_m':rear,'body_velocity':b.get('velocity'),'state':b['tactical_state'],'original_body_ids':[e['id']for e in land['entities']if e.get('company_id')==b['company_id']and e.get('render_as_infantry')is not None]}
    doc={'initial_request':q,'serialized':json.dumps(saved,separators=(',',':'),ensure_ascii=False),'commands':commands,'evidence':e,'source':'actual public new/autonomy/step/save; no live position, HP, goal or state edits'};a.output.parent.mkdir(exist_ok=True,parents=True);a.output.write_text(json.dumps(doc,ensure_ascii=False),'utf8');print(json.dumps(e));raise SystemExit
  if v.get('result'):break
 raise AssertionError('actual rear-cover arrival was not observed in this standard exercise')
finally:process.terminate();process.wait()
