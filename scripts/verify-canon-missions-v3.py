"""Play registered story missions through accepted public commands only."""
from pathlib import Path
import json, os, subprocess, hashlib, math
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/story-modernization-v3'
NATIVE=Path(os.environ.get('CAS_SIM_PATH',ROOT/'target/godot-core-build/release/cas-sim.exe'))
STAGES=['c1-breakout','c1-salvage','c1-boss','c2-convoy','c2-relay','c2-warden','c3-crossing','c3-core','c3-breaker']

class Player:
    def __init__(self,stage):
        self.stage=stage;self.commands=[];self.replies=[];self.dodged=set()
        self.p=subprocess.Popen([str(NATIVE)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,encoding='utf-8')
    def ask(self,q,required=True):
        self.commands.append(q);self.p.stdin.write(json.dumps(q,ensure_ascii=False)+'\n');self.p.stdin.flush()
        line=self.p.stdout.readline();r=json.loads(line);self.replies.append(line)
        if required and not r['ok']:raise AssertionError((self.stage,q,r))
        if r['ok'] and isinstance(r.get('data'),dict) and 'ships' in r['data']:self.v=r['data']
        return r
    def step(self,n=1):self.ask({'op':'step','seconds':n})
    def evade(self):
        for warning in self.v['salvage'].get('telegraphs',[]):
            for fleet in list(self.v['fleets']):
                key=(warning['id'],fleet['id'])
                ships=[s for s in self.v['ships'] if s['fleet']==fleet['id']]
                if not ships or key in self.dodged:continue
                radius=warning['radius']+250
                if not any((s['x']-warning['x'])**2+(s['y']-warning['y'])**2<radius**2 for s in ships):continue
                lead=next((s for s in ships if s['id']==fleet['leader']),ships[0]);speed=min(24,min(s['systems']['maxSpeed'] for s in ships))
                targets=[{'x':x,'y':y} for y in [700,1600,2700] for x in [lead['x']+3500,lead['x']-3500,lead['x']+5000,lead['x']-5000] if 2200<x<21000]
                for target in targets:
                    q={'op':'preview_route','fleet':fleet['id'],'mode':'follow','speed':speed,'points':[target]}
                    r=self.ask(q,False)
                    if r.get('ok') and r.get('data',{}).get('valid'):
                        q['op']='route';self.ask(q);self.dodged.add(key);break
    def route(self,fleet,point,speed=18):
        ship=next(s for s in self.v['ships'] if s['fleet']==fleet)
        speed=min(speed,min(s['systems']['maxSpeed'] for s in self.v['ships'] if s['fleet']==fleet))
        candidates=[[point]]
        for x in [ship['x']-3500,ship['x']+3500,3500,6500,11000,15500,19500]:
            for y in [650,1400,2600]:
                if 300<x<23500:candidates.append([{'x':x,'y':y},point])
        for mode in ['follow','sync']:
            for points in candidates:
                q={'op':'preview_route','fleet':fleet,'mode':mode,'speed':speed,'points':points}
                r=self.ask(q,False)
                if r.get('ok') and r.get('data',{}).get('valid'):
                    q['op']='route';self.ask(q);return
        raise AssertionError((self.stage,'no legal turning route',fleet,point,r))
    def dump(self):
        (OUT/f'{self.stage}-commands.json').write_text(json.dumps(self.commands,ensure_ascii=False,indent=2),'utf-8')
        (OUT/f'{self.stage}-terminal.json').write_text(json.dumps(self.v,ensure_ascii=False,indent=2),'utf-8')
    def close(self):self.p.stdin.close();self.p.wait(timeout=15)

def inside(s,b):return b['min_x']<=s['x']<=b['max_x'] and b['min_y']<=s['y']<=b['max_y']
def play(stage):
    p=Player(stage)
    try:
        p.ask({'op':'new_chapter','id':stage,'seed':6109,'chapter_profile':'canon-missions-v3'})
        v=p.v;goal=v['chapter']['objective']['kind'];point=v['salvage']['ruins'][0]['p'];bbox=v['salvage']['exits'][0]['bounds'];exit=v['salvage']['exits'][0]
        # Public preflight and real three-fleet routes, not direct hull mutation.
        for f in v['fleets']:p.route(f['id'],{'x':point['x']+600,'y':1200+(f['id']-1)*1000})
        if goal=='defeat_boss_and_extract':
            for f in v['fleets']:p.ask({'op':'ai','fleet':f['id'],'profile':'coord','mode':'auto','move':False,'gun':True,'torpedo':True})
        if goal=='search_stow_extract':
            for _ in range(500):
                if any(((s['x']-point['x'])**2+(s['y']-point['y'])**2)**.5<600 for s in p.v['ships']):break
                p.step()
            for f in p.v['fleets']:p.ask({'op':'speed','fleet':f['id'],'speed':0})
            p.step(8)
            item=None
            for _ in range(12):
                p.ask({'op':'search_salvage','ruin':1});p.step(8)
                grid=p.v['salvage']['cargo_grid'];item=next((i for i in grid['items'] if i['kind']=='archive'),None)
                if item:break
            assert item is not None,(stage,'search never revealed its real archive')
            rejected=p.ask({'op':'salvage_extract','exit':0},False);assert not rejected['ok'],'revealed archive must not count as carried'
            p.ask({'op':'cargo_place','item':item['id'],'x':0,'y':0,'rotation':0});p.step()
            assert 'archive_recovered' in p.v['chapter']['events']
        elif goal=='defeat_boss_and_extract':
            for _ in range(1400):
                if 'boss_defeated' in p.v['chapter']['events']:break
                if p.v.get('result'):break
                if stage!='c3-breaker':p.evade()
                p.step()
            assert 'boss_defeated' in p.v['chapter']['events'],(stage,'boss alive',p.v['tick'])
        else:
            for _ in range(500):
                if 'beacon_reached' in p.v['chapter']['events']:break
                p.step()
            assert 'beacon_reached' in p.v['chapter']['events']
        # Replay an actual in-progress mission, then continue the same voyage.
        saved=p.ask({'op':'save'})['data'];before=p.ask({'op':'observe'})['data']
        assert p.ask({'op':'load','save':saved})['data']==before
        assert p.ask({'op':'replay','save':saved})['data']==before
        for f in p.v['fleets']:p.route(f['id'],{'x':exit['x'],'y':1200+(f['id']-1)*1000})
        for _ in range(600):
            if p.v.get('result'):break
            if all(inside(s,bbox) for s in p.v['ships']):
                for f in p.v['fleets']:p.ask({'op':'speed','fleet':f['id'],'speed':0})
                p.ask({'op':'salvage_extract','exit':0});p.step(12);break
            p.step()
        assert p.v.get('result',{}).get('primary') is True,(stage,'not an actual victory',p.v['tick'])
        p.dump();return {'stage':stage,'tick':p.v['tick'],'requests':len(p.commands),'success':True,'replay':True,'fleets':len(p.v['fleets']),'escort':p.v['chapter']['escortShipIds'],'events':p.v['chapter']['events']}
    except Exception:
        p.dump();raise
    finally:p.close()

if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True);rows=[]
    for stage in STAGES:
        result=play(stage);rows.append(result);print(json.dumps(result,ensure_ascii=False),flush=True)
    (OUT/'native-playthrough.json').write_text(json.dumps({'passed':True,'native':str(NATIVE),'sha256':hashlib.sha256(NATIVE.read_bytes()).hexdigest(),'rows':rows},ensure_ascii=False,indent=2),'utf-8')
