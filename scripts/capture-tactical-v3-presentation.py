"""Capture genuine in-flight public-command saves; never opens an account."""
import argparse, hashlib, json, subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--native',type=Path,required=True);args=p.parse_args()
out=root/'artifacts/island-war-v3/presentation';out.mkdir(parents=True,exist_ok=True)
courses=json.loads((root/'godot/data/tactical-training-v3.json').read_text('utf-8'))['lessons']
rows=[]
def family(row):
    return row.get('weapon_family_id',row.get('weapon',{}).get('family_id',row.get('weapon_id','')))
for label, lesson in [(name, name) for name in ['landing','weapons','airborne','artillery']] + [
        ('role-command_network', 'roles'), ('role-grenade', 'roles'),
        ('role-deploy_aa_turret', 'roles'), ('role-support_designation', 'roles'),
        ('role-demolition_charge','roles'),('role-supply_network','roles'),
        ('cadence-smg','roles'),('cadence-dmr','roles'),('magazine-reload','roles')]:
    proc=subprocess.Popen([str(args.native.resolve())],stdin=subprocess.PIPE,stdout=subprocess.PIPE)
    commands=[]
    def ask(command):
        commands.append(command)
        proc.stdin.write((json.dumps(command,ensure_ascii=False,separators=(',',':'))+'\n').encode());proc.stdin.flush()
        reply=json.loads(proc.stdout.readline());assert reply['ok'],reply
        return reply['data']
    try:
        view=ask(courses[lesson]['request']);view=ask({'op':'island_autonomy','enabled':True})
        found=False;focus={}
        cadence = label.startswith('cadence-') or label == 'magazine-reload'
        for second in range(1,5000 if cadence else 500):
            view=ask({'op':'step','seconds':.1 if cadence else 1});land=view['littoral']['land']
            bodies=land['entities'];shots=view['littoral'].get('shots',[])
            if lesson=='landing':found=any(t.get('kind')=='kayak' and t.get('stage') not in ['embarked','recovered','lost'] for t in view['littoral'].get('transports',[]))
            elif lesson=='weapons':found=any(b.get('unit_id')=='MCP-063' and family(b)=='rocket' and b.get('active',True) and b.get('hp',0)>0 for b in bodies)
            elif lesson=='airborne':found=any(b.get('unit_id')=='MCP-088' and b.get('phase')=='parachuting' for b in bodies)
            elif lesson=='artillery':
                recent=next((s for s in reversed(shots) if family(s)=='howitzer'),{})
                focus=next((b for b in bodies if recent.get('operator_id')==b['id'] and b.get('hp',0)>0 and b.get('carried_by') is None),{})
                found=bool(focus)
            elif label=='role-grenade':found=any(family(s)=='grenade' for s in shots)
            elif label=='role-demolition_charge':found=any(family(s)=='demolition_charge' for s in shots)
            elif label=='role-deploy_aa_turret':found=any(d.get('kind')=='aa_turret' and d.get('active',True) and d.get('hp',0)>0 for d in view['island_war'].get('deployables',[]))
            elif label in ['cadence-smg','cadence-dmr']:
                wanted=label.removeprefix('cadence-')
                recent=next((s for s in reversed(shots) if family(s)==wanted and view['tick']-s.get('tick',-100)<=.11 and s.get('side')=='allies'),{})
                focus=next((b for b in bodies if (recent.get('operator_id')==b['id'] or recent.get('source')=='body:'+str(b['id'])) and b.get('hp',0)>0),{})
                found=bool(focus)
            elif label=='magazine-reload':
                focus=next((b for b in bodies if family(b)=='smg' and b.get('side')=='allies' and b.get('active',True) and b.get('hp',0)>0 and b.get('reloading_in',0)>0),{})
                found=bool(focus)
            else:found=any(e.get('kind')==label.removeprefix('role-') and e.get('remaining_s',0)>0 for e in land.get('effects',[]))
            if found:break
            if view.get('result'):break
        assert found,(label,view['tick'],list(view['littoral'].keys()))
        snap=ask({'op':'save'})
        file=out/f'actual-{label}.json';file.write_text(json.dumps({'serialized':json.dumps(snap,ensure_ascii=False,separators=(',',':')),'view':view,'commands':commands,'focus':focus.get('id')},ensure_ascii=False),'utf-8')
        rows.append({'lesson':lesson,'event':label,'tick':view['tick'],'file':str(file.relative_to(root)),'sha256':hashlib.sha256(file.read_bytes()).hexdigest()})
    finally:
        proc.stdin.close();proc.wait(timeout=30)
receipt={'ok':True,'native':str(args.native),'native_sha256':hashlib.sha256(args.native.read_bytes()).hexdigest(),'captures':rows,'scope':'Actual requests, simulation steps and native saves. No edited observations or account access.'}
(out/'capture-receipt.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),'utf-8');print(json.dumps(receipt,ensure_ascii=False))
