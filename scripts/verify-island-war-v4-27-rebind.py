"""Recreate unchanged manual cover and real five-person autonomy on27 final."""
from pathlib import Path
import argparse,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--native',type=Path,required=True);p.add_argument('--out',type=Path,default=ROOT/'artifacts/island-war-v4/river-core');a=p.parse_args();a.out.mkdir(parents=True,exist_ok=True)
prior=ROOT/'artifacts/island-war-v4/core/frozen-final-211d162d832f0ce6/evidence/core';rows=[]
for name in ['manual-default-cover','new-five-autonomy']:
 old=json.loads((prior/(name+'.json')).read_text('utf8'));proc=subprocess.Popen([str(a.native.resolve())],stdin=subprocess.PIPE,stdout=subprocess.PIPE);commands=[];view=None
 def call(q):
  global view
  commands.append(q);proc.stdin.write((json.dumps(q,ensure_ascii=False)+'\n').encode('utf8'));proc.stdin.flush();r=json.loads(proc.stdout.readline());assert r['ok'],(q,r)
  if 'ships'in r['data']:view=r['data']
  return r['data']
 try:
  if name=='manual-default-cover':
   for q in old['commands']:call(q)
   covered=sum(b.get('hp',0)>0 and bool(b.get('cover_vehicle_id')) for b in view['littoral']['land']['entities']);assert covered>=60 and not view['littoral']['autonomy']['enabled'];extra={'covered_bodies':covered}
  else:
   call(old['commands'][0]);call({'op':'island_autonomy','version':'cas-island-war-v4','enabled':True})
   for _ in range(100):
    call({'op':'step','seconds':10})
    if view['result']:break
   assert view['result'] and view['result']['success'];extra={'success':True}
  save=call({'op':'save'});terminal=view;call({'op':'load','save':save});assert view==terminal
  (a.out/(name+'.json')).write_text(json.dumps({'commands':commands,'view':view,'save':save,'native_sha256':hashlib.sha256(a.native.read_bytes()).hexdigest(),**extra},ensure_ascii=False),encoding='utf8')
  if name=='manual-default-cover':(a.out/(name+'-snapshot.json')).write_text(json.dumps(save,ensure_ascii=False),encoding='utf8')
  rows.append({'name':name,'tick':view['tick'],**extra});print(json.dumps(rows[-1]),flush=True)
 finally:proc.stdin.close();proc.wait(timeout=30)
(a.out/'cover-and-five-receipt.json').write_text(json.dumps({'passed':True,'native_sha256':hashlib.sha256(a.native.read_bytes()).hexdigest(),'rows':rows},indent=2),encoding='utf8')
