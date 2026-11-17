"""Compare every tested public stream with the actual normal-launch core."""
from pathlib import Path
import argparse, hashlib, json, subprocess
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser()
p.add_argument('--candidate',type=Path,required=True)
p.add_argument('--installed',type=Path,required=True)
p.add_argument('--out',type=Path,default=ROOT/'artifacts/island-war-v4/core/installed-equivalence.json')
args=p.parse_args();rows=[]
folder=ROOT/'artifacts/island-war-v4'
names=[]
for receipt in ['receipt.json','shore-artillery-receipt.json','historical-wasm-receipt.json']:
 d=json.loads((folder/'parity'/receipt).read_text('utf8'));assert d['passed']
 names.extend(c['name'] for c in d['cases'])
assert len(set(names))==len(names)
for name in names:
 source=json.loads((folder/'core'/(name+'.json')).read_text('utf8'))
 processes=[subprocess.Popen([str(exe.resolve())],stdin=subprocess.PIPE,stdout=subprocess.PIPE) for exe in [args.candidate,args.installed]]
 h=hashlib.sha256();size=0;count=0;view=None
 def call(q):
  global count,size,view
  replies=[];wire=(json.dumps(q,ensure_ascii=False,separators=(',',':'))+'\n').encode('utf8')
  for proc in processes:
   proc.stdin.write(wire);proc.stdin.flush();replies.append(proc.stdout.readline())
  assert replies[0] and replies[0]==replies[1],(name,count,q['op'])
  h.update(replies[0]);size+=len(replies[0]);count+=1;r=json.loads(replies[0])
  if r['ok'] and 'ships' in r['data']:view=r['data']
  return r
 try:
  for q in source['commands']:call(q)
  if source.get('save') or source.get('snapshot'):
   save=call({'op':'save'})['data'];terminal=view
   call({'op':'load','save':save});assert view==terminal
   for tick in [0,min(save['tick'],12),save['tick']]:call({'op':'replay','save':save,'tick':tick})
   assert view==terminal
  row={'name':name,'requests':count,'bytes':size,'raw_sha256':h.hexdigest(),'raw_identical':True}
  rows.append(row);print(json.dumps(row),flush=True)
 finally:
  for proc in processes:proc.stdin.close();proc.wait(timeout=30)
receipt={'passed':True,'candidate':str(args.candidate.resolve()),'candidate_sha256':hashlib.sha256(args.candidate.read_bytes()).hexdigest(),
         'installed':str(args.installed.resolve()),'installed_sha256':hashlib.sha256(args.installed.read_bytes()).hexdigest(),
         'cases':rows,'requests':sum(r['requests'] for r in rows),'bytes':sum(r['bytes'] for r in rows),
         'scope':'Actual normal-launch core vs frozen final candidate, every raw reply for the tested complete public streams, rejected commands, save/load, replay0/12/end and terminals; no account/runtime/manifest mutation.'}
args.out.parent.mkdir(parents=True,exist_ok=True);args.out.write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'passed':True,'cases':len(rows),'requests':receipt['requests'],'output':str(args.out)}),flush=True)
