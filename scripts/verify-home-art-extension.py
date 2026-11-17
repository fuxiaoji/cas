"""Verify this art delivery, without touching an account or combat core."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
PROJECT=ROOT/'demos/land-art-3d'
ART=ROOT/'artifacts/home-design-20261116'
OUT=ROOT/'output/home-design-20261116'
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
checks=[]
def check(label, condition):
    checks.append({'check':label,'passed':bool(condition)})
    if not condition: raise AssertionError(label)

previews=json.loads((ART/'building-previews.json').read_text(encoding='utf-8'))
check('twelve distinct facility previews',len(previews)==12 and len({p['id'] for p in previews})==12)
for row in previews:
    check('scene save: '+row['id'],row['scene_save_error']==0 and (PROJECT/'scenes/facilities'/f"{row['id']}.scn").stat().st_size>100)
for path in sorted((ART/'buildings').glob('*.png'))+sorted((ART/'screenshots').glob('*.png'))+[OUT/'production-board.png',OUT/'defense-board.png',OUT/'home-loop.png']:
    with Image.open(path) as image:
        image.verify()
    check('valid image: '+path.name,True)
vehicles=json.loads((PROJECT/'assets/vehicles3d/vehicle-manifest.json').read_text(encoding='utf-8'))
check('three real GLB vehicles',len(vehicles['models'])==3)
for row in vehicles['models']:
    path=PROJECT/'assets/vehicles3d'/f"{row['id']}.glb"
    check('model SHA: '+row['id'],sha(path)==row['sha256'])
    check('editable Blender source: '+row['id'],(PROJECT/'assets/vehicles3d/source'/f"{row['id']}.blend").exists())
    check('movement matches heading: '+row['id'],row['heading_motion_dot']>0.99)
    check('shared material and two rigid assemblies: '+row['id'],row['materials']==1 and row['mesh_nodes']==2 and row['geometry_surfaces']==2)
for log in ['coast-gpu.log','gallery-gpu.log','editable-scene-final.log']:
    content=(ART/log).read_text(encoding='utf-8')
    check('no runtime/shader errors: '+log,not any(word in content for word in ['SCRIPT ERROR','SHADER ERROR','ERROR:']))
check('refined nature is registered',(PROJECT/'assets/vendor/nature-refine/selected.json').exists())
nature=json.loads((PROJECT/'assets/vendor/nature-refine/source-receipt.json').read_text(encoding='utf-8'))
for row in nature['files']:
    check('tree source SHA: '+row['name'],sha(PROJECT/'assets/vendor/nature-refine'/row['name'])==row['sha256'])
check('saved editable coast',(PROJECT/'scenes/editable_coast.scn').stat().st_size>100000)
manual=json.loads((ART/'manual-interaction.json').read_text(encoding='utf-8'))
check('four actual desktop UI observations',len(manual['observations'])==4 and all(row['passed'] for row in manual['observations']))
check('local design booklet and full outline',(OUT/'index.html').exists() and (ROOT/'docs/design/home-building-economy-defense-outline-20261116.md').exists())
record={'date':'2026-11-16','scope':'isolated art sample and proposed home design; no production account/core changes',
        'checks':checks,'passed':True,'facilities':12,'vehicles':3,'screenshots':len(list((ART/'screenshots').glob('*.png'))),
        'android_or_touch_device_tested':False,'new_economy_or_defense_rules_installed':False,
        'tripo_paid_calls':0,
        'sha256':{str(p.relative_to(ROOT)).replace('\\','/'):sha(p) for p in [PROJECT/'project.godot',PROJECT/'scripts/coast_demo.gd',PROJECT/'scripts/home_architecture.gd',PROJECT/'scripts/coastal_vehicles.gd',PROJECT/'scripts/coastal_nature.gd',OUT/'production-board.png',OUT/'defense-board.png']}}
(ART/'delivery-validation.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'passed':True,'checks':len(checks),'scope':record['scope']},ensure_ascii=False))
