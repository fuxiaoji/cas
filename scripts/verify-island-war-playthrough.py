import argparse,json,subprocess,pathlib,time,hashlib
ap=argparse.ArgumentParser();ap.add_argument('--native',default='target/island-war-build/release/cas-sim.exe');ap.add_argument('--mode',default='raid');ap.add_argument('--npc',default='shoal_watch');ap.add_argument('--seconds',type=int,default=700);ap.add_argument('--weak',action='store_true');args=ap.parse_args()
out=pathlib.Path('artifacts/island-war-v1/playthrough');out.mkdir(parents=True,exist_ok=True)
q=json.loads(pathlib.Path('artifacts/island-war-v1/initial-raid.json').read_text(encoding='utf-8'));q['mode']=args.mode;q['island']['npc_id']=args.npc;q['island']['island_level']={'shoal_watch':1,'rust_quay':2,'cloudbreak':3,'iron_citadel':5,'storm_relay':7,'old_arsenal':10}[args.npc]
if args.weak:
 q['ships']=[{'id':'CAS-O-APV-TIDEBRIDGE','hp':10,'ammo':0}];q['roster']=['MCP-034','MCP-009'];q['unit_condition']=[{'id':i,'hp':10} for i in q['roster']];q['island']['forts']=[{'id':'hq','kind':'hq','level':1,'x':.8,'y':.5,'hp':100},{'id':'warehouse','kind':'warehouse','level':1,'x':.5,'y':.5,'hp':100}];q['island']['storage']={'credits':100,'scrap':40,'alloy':20,'protocols':1}
proc=subprocess.Popen([args.native],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True,encoding='utf-8');requests=[];responses=[];started=time.monotonic()
def ask(q,ok=True):
 requests.append(q);proc.stdin.write(json.dumps(q,ensure_ascii=False)+'\n');proc.stdin.flush();line=proc.stdout.readline()
 if not line:raise RuntimeError('native terminated')
 v=json.loads(line);responses.append(v)
 if ok and not v['ok']:raise Exception(v)
 return v.get('data')
try:
 v=ask(q);v=ask({'op':'littoral_autonomy','version':'cas-island-war-v1','enabled':True})
 for i in range(args.seconds//10):
  v=ask({'op':'step','seconds':10})
  if i%3==0 or v['result']:
   print(v['tick'],'result',v['result'] and v['result']['success'],'capture',v['island_war']['hq_capture'],'wh',sum(w['captured'] for w in v['island_war']['warehouses']),'enemy',len(v['contacts']),'land',len([b for b in v['littoral']['land']['entities'] if b['side']=='axis']),'status',v['littoral'].get('autonomy',{}).get('status'),flush=True)
  if v['result']:break
 save=ask({'op':'save'});roundtrip=ask({'op':'load','save':save});assert roundtrip==v,'load differs'
 for tick in [0,min(25,save['tick']),min(40,save['tick']),min(12,save['tick']),save['tick']]:
  replay=ask({'op':'replay','save':save,'tick':tick})
  if tick==save['tick']:assert replay==v,'final replay differs'
 prefix=out/(f'{args.mode}-{args.npc}'+('-weak' if args.weak else ''))
 prefix.with_suffix('.commands.json').write_text(json.dumps(requests,ensure_ascii=False,indent=2),encoding='utf-8')
 prefix.with_suffix('.final.json').write_text(json.dumps(v,ensure_ascii=False,indent=2),encoding='utf-8')
 prefix.with_suffix('.save.json').write_text(json.dumps(save,ensure_ascii=False,indent=2),encoding='utf-8')
 print(json.dumps({'tick':save['tick'],'success':v['result'] and v['result']['success'],'wall_seconds':round(time.monotonic()-started,2),'commands':len(requests),'native_sha':hashlib.sha256(pathlib.Path(args.native).read_bytes()).hexdigest()},ensure_ascii=False),flush=True)
finally:proc.terminate()
