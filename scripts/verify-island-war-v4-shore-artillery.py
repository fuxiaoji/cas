"""Public-command shore and SPG audit, with initial conditions only."""
from pathlib import Path
import argparse, hashlib, json, math, subprocess

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--native', type=Path, required=True)
p.add_argument('--out', type=Path, default=ROOT/'artifacts/island-war-v4/core')
args = p.parse_args()
args.out.mkdir(parents=True, exist_ok=True)
proc = subprocess.Popen([str(args.native.resolve())], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
commands = []
def call(q):
    commands.append(q)
    proc.stdin.write((json.dumps(q, ensure_ascii=False)+'\n').encode('utf8'))
    proc.stdin.flush()
    reply = json.loads(proc.stdout.readline())
    assert reply['ok'], (q, reply)
    return reply['data']
def distance(a, b):
    return math.hypot(a['x']-b['x'], a['y']-b['y'])
def inside(p, polygon):
    result = False
    for a,b in zip(polygon, polygon[1:]+polygon[:1]):
        if (a['y']>p['y']) != (b['y']>p['y']) and p['x'] < (b['x']-a['x'])*(p['y']-a['y'])/(b['y']-a['y'])+a['x']:
            result = not result
    return result
try:
    q = json.loads((ROOT/'artifacts/island-war-v4/core/manual-default-cover.json').read_text('utf8'))['commands'][0]
    q['roster'] = ['MCP-087','MCP-301']
    view = call(q)
    ids = ['MCP-087-C01', 'MCP-301-C01']
    for cid in ids:
        view = call({'op':'littoral_deploy','company_id':cid,'beach':2,'x':14000,'y':13000})
    shore_sample = None
    artillery_before = None
    artillery_after = None
    boat_samples = 0
    for _ in range(180):
        view = call({'op':'step','seconds':1})
        land = view['littoral']['land']
        for boat in view['littoral']['transports']:
            if not boat['air'] and boat['status']=='sailing':
                assert not inside(boat, land['polygon']), ('ordinary boat entered inland', boat)
                assert not inside(boat['goal'], land['polygon']), ('boat goal entered inland', boat)
                boat_samples += 1
        groups = {g['company_id']:g for g in view['littoral']['groups']}
        if shore_sample is None and groups['MCP-301-C01']['stage']=='ground':
            g=groups['MCP-301-C01']
            assert distance(g,g['goal'])>300, 'Infantry must have a real inland walk after shore unloading'
            shore_sample={'tick':view['tick'],'group':g,'transports':view['littoral']['transports']}
        active_gunners=[b for b in land['entities'] if b['company_id']==ids[0] and b['hp']>0 and b.get('render_as_infantry')]
        if artillery_before is None and groups['MCP-087-C01']['stage']=='ground' and len(active_gunners)==6:
            artillery_before={'tick':view['tick'],'bodies':{str(b['id']):b for b in active_gunners},
                              'vehicle':next(v for v in land['combat_vehicles'] if v['company_id']==ids[0])}
            assert len(artillery_before['bodies'])==6
            assert all(b['weapon_family_id']=='pistol' for b in artillery_before['bodies'].values())
            view=call({'op':'littoral_order','company_id':ids[0],'action':'attack','x':15000,'y':13000})
        elif artillery_before is not None and view['tick']>=artillery_before['tick']+8:
            bodies={str(b['id']):b for b in active_gunners}
            displacements=[distance(b,bodies[k]) for k,b in artillery_before['bodies'].items() if k in bodies]
            vehicle=next(v for v in land['combat_vehicles'] if v['company_id']==ids[0])
            artillery_after={'tick':view['tick'],'body_displacements_m':displacements,'vehicle_displacement_m':distance(vehicle,artillery_before['vehicle']),'vehicle':vehicle}
            # Physical unloading/avoidance may move a gunner locally; they must
            # never advance with their independently moving SPG.
            assert len(displacements)==6 and max(displacements)<50, artillery_after
            assert artillery_after['vehicle_displacement_m']>50, artillery_after
            assert max(displacements)<artillery_after['vehicle_displacement_m']*0.1, artillery_after
        if shore_sample and artillery_after:
            break
    assert shore_sample and artillery_after and boat_samples>0
    save=call({'op':'save'})
    (args.out/'shore-and-artillery.json').write_text(json.dumps({'commands':commands,'view':view,'save':save,'shore_sample':shore_sample,'artillery_before':artillery_before,'artillery_after':artillery_after,'boat_samples':boat_samples},ensure_ascii=False),encoding='utf8')
    receipt={'passed':True,'native_sha256':hashlib.sha256(args.native.read_bytes()).hexdigest(),'boat_samples_outside_island':boat_samples,'shore_unload_tick':shore_sample['tick'],'artillery':artillery_after,'scope':'Unedited public-command simulation: boats and their goals stay outside island polygon; inland rally continues on foot; 087 pistol bodies remain while SPG actually advances on attack.'}
    (args.out/'shore-artillery-receipt.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps(receipt,ensure_ascii=False))
finally:
    proc.stdin.close()
    proc.wait(timeout=30)
