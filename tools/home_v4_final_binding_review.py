"""Read-only final native binding proof; full GUI execution provenance remains separate."""
from pathlib import Path
import subprocess,json,hashlib,copy
ROOT=Path(__file__).resolve().parents[1]
OLD=ROOT/'artifacts/island-war-v4/core/frozen-final-211d162d832f0ce6/cas-sim.exe'
FINAL=ROOT/'artifacts/island-war-v4/core/frozen-final-5edacf8b5da2a12d/cas-sim.exe'
OUT=ROOT/'artifacts/island-war-v4/home/final-binding-proof.json'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
class Engine:
 def __init__(self,path):self.p=subprocess.Popen([str(path)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,encoding='utf-8')
 def ask(self,r):
  self.p.stdin.write(json.dumps(r,ensure_ascii=False,separators=(',',':'))+'\n');self.p.stdin.flush();raw=self.p.stdout.readline().strip();v=json.loads(raw)
  if not v.get('ok'):raise RuntimeError(str(v))
  return raw,v
 def close(self):self.p.terminate();self.p.wait(timeout=5)
def main():
 assert sha(FINAL)=='5edacf8b5da2a12d0690dd48a1ae698e5981b4204a535d2e3f763b9e95e92295'
 source=ROOT/'godot/data/island-war-v4-published.json';baseline=json.loads(source.read_text(encoding='utf-8'))
 assert sha(source)=='93b93830df79949bb676a2bea447c23514438b306d313f9da97d460bfafb5583'
 assert len(baseline['cards'])==27 and len(baseline['weapons'])==54
 old,new=Engine(OLD),Engine(FINAL);rows=[]
 def same(label,r):
  a,av=old.ask(r);b,bv=new.ask(r);equal=a==b;rows.append({'label':label,'request_sha256':hashlib.sha256(json.dumps(r,ensure_ascii=False,sort_keys=True).encode()).hexdigest(),'raw_response_equal':equal,'old_sha256':hashlib.sha256(a.encode()).hexdigest(),'final_sha256':hashlib.sha256(b.encode()).hexdigest(),'response_bytes':len(b.encode())})
  if not equal:raise AssertionError(label+' differs')
  return bv
 try:
  cat=same('native27 catalogue',{'op':'island_war_catalogue','version':'cas-island-war-v4'});assert cat['data']==baseline
  for level in [1,3,5]:same('native home HQ'+str(level),{'op':'island_home_preview','version':'cas-island-war-v4','seed':1387249,'hq_level':level,'buildings':[{'id':'same-hq','kind':'hq','level':level,'cell':{'x':6,'y':4}}]})
  request=json.loads((ROOT/'artifacts/island-war-v4/home/exercise-request.json').read_text(encoding='utf-8-sig'))
  for version in ['cas-island-war-v3','cas-island-war-v4']:
   r=copy.deepcopy(request);r['version']=version;same('real own exercise '+version,r);same('own observe '+version,{'op':'observe'})
   saved=same('own exact save '+version,{'op':'save','serialized':True})['serialized'];same('own same save load '+version,{'op':'load','serialized':saved});same('own small real step '+version,{'op':'step','seconds':.3});same('own abandoned terminal '+version,{'op':'littoral_abandon'});same('own terminal save '+version,{'op':'save','serialized':True})
  training=json.loads((ROOT/'godot/data/tactical-training-v4.json').read_text(encoding='utf-8'))
  for key,row in training['lessons'].items():
   same('borrowed lesson '+key,row['request']);same('borrowed actual step '+key,{'op':'step','seconds':.1});same('borrowed snapshot '+key,{'op':'save','serialized':True})
 finally:old.close();new.close()
 result={'passed':True,'final_core_sha256':sha(FINAL),'actual_full_gui_core_sha256':sha(OLD),'full_gui_reexecuted_on_final_core':False,'verification_origin':'Full901 UI/170 real InputEvents and legacy224 executed on211d. Final5ed only changes v4 amphibious river movement/domain. This read-only targeted proof compares exact native catalogue, same-island home geometry, real own exercise construction/save/load/step/terminal for v3/v4, and all six borrowed lesson initial steps/snapshots. It does not claim to retest river movement, which belongs to the core owner.','catalogue_sha256':sha(source),'published_catalogue':'godot/data/island-war-v4-published.json','offline_baseline_bytes_equal':source.read_bytes()==(ROOT/'output/tactical-codex-v4-20261115/baseline-native.json').read_bytes(),'shared_draft_excluded':True,'comparisons':rows,'response_count':len(rows),'differences':0,'training_sha256':sha(ROOT/'godot/data/tactical-training-v4.json')}
 OUT.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps({k:v for k,v in result.items() if k!='comparisons'},ensure_ascii=False))
if __name__=='__main__':main()
