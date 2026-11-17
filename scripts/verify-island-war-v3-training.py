"""Re-run six public training command streams on a chosen candidate; read-only accounts."""
from pathlib import Path
import argparse,json,subprocess,hashlib
root=Path(__file__).resolve().parents[1];p=argparse.ArgumentParser();p.add_argument('--native',type=Path,required=True);p.add_argument('--output',type=Path,default=root/'artifacts/island-war-v3/core/training-receipt.json');a=p.parse_args();rows=[]
for lesson in ['landing','weapons','artillery','airborne','roles','combined_arms']:
 file=root/f'artifacts/island-war-v3/core/training-{lesson}-terminal.json';d=json.loads(file.read_text('utf8'));proc=subprocess.Popen([str(a.native.resolve())],stdin=subprocess.PIPE,stdout=subprocess.PIPE);h=hashlib.sha256();size=0;view=None;saved=None
 try:
  for q in d['commands']:
   proc.stdin.write((json.dumps(q,ensure_ascii=False,separators=(',',':'))+'\n').encode('utf8'));proc.stdin.flush();raw=proc.stdout.readline();h.update(raw);size+=len(raw);r=json.loads(raw);assert r['ok'],r
   if r['data'].get('ships') is not None:view=r['data']
   if q['op']=='save':saved=r['data']
  assert view==d['final'],lesson;assert saved==d['snapshot'],lesson;assert view['result']['success'] and view['littoral']['training']['complete'],lesson;assert view['result']['resources']['credits']==0 and not view['result']['settle_allowed'];rows.append({'lesson':lesson,'tick':view['tick'],'success':True,'all_actual_checks':True,'requests':len(d['commands']),'bytes':size,'raw_sha256':h.hexdigest(),'fixture_sha256':hashlib.sha256(file.read_bytes()).hexdigest()})
 finally:proc.stdin.close();proc.wait(timeout=30)
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps({'passed':True,'native':str(a.native),'native_sha256':hashlib.sha256(a.native.read_bytes()).hexdigest(),'lessons':rows,'scope':'Six actual public command streams re-executed; winning result + all real checks + exact final view/save equality; borrowed exercise zero rewards'},indent=2),'utf8');print(json.dumps({'passed':True,'lessons':len(rows),'output':str(a.output)}))
