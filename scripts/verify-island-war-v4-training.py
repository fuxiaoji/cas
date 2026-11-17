"""Complete the six separate v4 borrowed lessons using real public commands."""
import argparse,json,subprocess,hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[1];p=argparse.ArgumentParser();p.add_argument('--native',type=Path,required=True);p.add_argument('--lesson');p.add_argument('--training',type=Path,default=root/'godot/data/tactical-training-v4.json');p.add_argument('--out',type=Path,default=root/'artifacts/island-war-v4/core');a=p.parse_args();a.out.mkdir(parents=True,exist_ok=True);rows=[]
lessons=json.loads(a.training.read_text('utf8'))['lessons']
for name,l in lessons.items():
 if a.lesson and name!=a.lesson:continue
 proc=subprocess.Popen([str(a.native.resolve())],stdin=subprocess.PIPE,stdout=subprocess.PIPE);commands=[];v=None
 def call(q):
  global v
  commands.append(q);proc.stdin.write((json.dumps(q,ensure_ascii=False)+'\n').encode());proc.stdin.flush();r=json.loads(proc.stdout.readline());assert r['ok'],r
  if 'ships' in r['data']:v=r['data']
  return r['data']
 try:
  call(l['request']);call({'op':'island_autonomy','enabled':True,'version':'cas-island-war-v4'})
  for n in range(120):
   call({'op':'step','seconds':10})
   if v['result']:break
  snapshot=call({'op':'save'});training=v['littoral']['training'];passed=bool(v['result'] and v['result']['success'] and training['complete']);row={'lesson':name,'passed':passed,'tick':v['tick'],'checks':training['checks'],'success':v['result'] and v['result']['success']};rows.append(row)
  (a.out/('training-'+name+'-terminal.json')).write_text(json.dumps({'commands':commands,'view':v,'final':v,'snapshot':snapshot,'serialized':json.dumps(snapshot,ensure_ascii=False)},ensure_ascii=False),encoding='utf8');print(json.dumps(row,ensure_ascii=False),flush=True)
 finally:proc.stdin.close();proc.wait(timeout=10)
(a.out/'training-receipt.json').write_text(json.dumps({'passed':all(r['passed'] for r in rows),'native_sha256':hashlib.sha256(a.native.read_bytes()).hexdigest(),'lessons':rows,'account_access':False},ensure_ascii=False,indent=2),encoding='utf8');assert all(r['passed'] for r in rows),rows
