"""Freeze the six existing CAS campaign consumers in both player seats."""
from pathlib import Path
import argparse, hashlib, json, subprocess
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser()
p.add_argument('--native',type=Path,required=True)
p.add_argument('--baseline',type=Path,default=ROOT/'artifacts/island-war-v3/core/frozen-final-298b78ecd20420cf/cas-sim.exe')
p.add_argument('--out',type=Path,default=ROOT/'artifacts/island-war-v4/core')
args=p.parse_args();args.out.mkdir(parents=True,exist_ok=True);rows=[]
for number in [2,3,4,5,10,11]:
 for side in ['ALLIES','AXIS']:
  stage=f'CAMP-{side}-{number:02}'
  processes=[subprocess.Popen([str(exe.resolve())],stdin=subprocess.PIPE,stdout=subprocess.PIPE) for exe in [args.native,args.baseline]]
  commands=[];digest=hashlib.sha256();size=0;view=None
  def call(q):
   global size,view
   commands.append(q);replies=[];wire=(json.dumps(q,ensure_ascii=False,separators=(',',':'))+'\n').encode('utf8')
   for proc in processes:
    proc.stdin.write(wire);proc.stdin.flush();replies.append(proc.stdout.readline())
   assert replies[0] and replies[0]==replies[1],(stage,q['op'])
   reply=json.loads(replies[0]);assert reply['ok'],(stage,q,reply)
   digest.update(replies[0]);size+=len(replies[0])
   if 'ships' in reply['data']:view=reply['data']
   return reply['data']
  try:
   initial=call({'op':'new_campaign','id':stage,'difficulty':'standard','seed':6106})
   call({'op':'observe'});call({'op':'step','seconds':30});save=call({'op':'save'})
   terminal=view
   call({'op':'load','save':save});assert view==terminal
   call({'op':'replay','save':save,'tick':0});call({'op':'replay','save':save,'tick':30});assert view==terminal
   name='historical-'+stage.lower()
   (args.out/(name+'.json')).write_text(json.dumps({'commands':commands,'view':view,'save':save},ensure_ascii=False),encoding='utf8')
   rows.append({'stage':stage,'fixture':name,'requests':len(commands),'bytes':size,'raw_sha256':digest.hexdigest(),'raw_identical':True,'initial_ships':len(initial['ships']),'tick':view['tick']})
   print(json.dumps(rows[-1]),flush=True)
  finally:
   for proc in processes:proc.stdin.close();proc.wait(timeout=30)
report={'passed':True,'native_sha256':hashlib.sha256(args.native.read_bytes()).hexdigest(),'baseline_sha256':hashlib.sha256(args.baseline.read_bytes()).hexdigest(),'cases':rows,'requests':sum(r['requests'] for r in rows),'scope':'All six existing historical consumers, both player seats, standard difficulty; untouched initial OOB, 30 real seconds, save/load and replay0/30; every raw response identical to frozen298b; no account or old evidence mutated.'}
(args.out.parent/'parity/historical-freeze.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'passed':True,'cases':len(rows),'requests':report['requests']}))
