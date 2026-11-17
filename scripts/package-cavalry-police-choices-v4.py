"""Package the two requested C1 revisions and a before/after viewer."""
from pathlib import Path
import json,hashlib,shutil,zipfile,sys
from PIL import Image
R=Path(__file__).resolve().parents[1]
D=R/'docs/art/cavalry-police-choices-v4-20261116'
O=R/'output/cavalry-police-choices-v4-20261116'
jobs=json.loads((D/'generation-input.json').read_text('utf8'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for job in jobs['jobs']:
    shutil.copyfile(job['refs'][0],O/('骑兵C1.png' if job['id'].startswith('骑兵') else '警察C1.png'))
(O/'index.html').write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>C1立绘修订</title><style>
*{box-sizing:border-box}body{margin:0;background:#eee9de;color:#233b3a;font:16px/1.7 'Microsoft YaHei',sans-serif}main{max-width:1280px;margin:auto;padding:28px}h1{font:600 36px SimSun,serif}h2{font:600 27px SimSun,serif;margin-top:36px}.pair{display:grid;grid-template-columns:1fr 1fr;gap:28px}figure{margin:0;border-top:1px solid #81958a;padding-top:12px}img{width:100%;height:680px;object-fit:contain}a{color:inherit}button{font:inherit;padding:9px 15px;min-height:44px;background:#faf7f0;color:inherit;border:1px solid #71877e;cursor:pointer}button:focus-visible,a:focus-visible{outline:3px solid #aa634c;outline-offset:3px}.dark{background:#21343b;color:#f4efe4}.dark button{background:#31464b}figcaption{padding:10px}p{max-width:72ch}@media(max-width:650px){main{padding:18px}.pair{grid-template-columns:1fr}img{height:500px}}
</style><main><h1>C1立绘修订</h1><p>点击图片查看原尺寸，左侧为C1原图，右侧为本次修订。</p><button id="background">切换深浅背景</button><h2>岚缨 · 第2骑兵团</h2><p>沿用海军蓝与银灰配色，增加短披风、肩披和围巾，以银饰与刺绣增加层次。</p><section class="pair"><figure><a href="骑兵C1.png"><img src="骑兵C1.png" alt="骑兵C1原图"></a><figcaption>C1 · 原图</figcaption></figure><figure><a href="骑兵D1.png"><img src="骑兵D1.png" alt="骑兵D1短披风肩披围巾修订"></a><figcaption>D1 · 本次修订</figcaption></figure></section><h2>青巡 · 第17特种警察团</h2><p>沿用C1警服，袖口卷到肘下露出小臂，保留短手套与过膝靴。</p><section class="pair"><figure><a href="警察C1.png"><img src="警察C1.png" alt="警察C1原图"></a><figcaption>C1 · 原图</figcaption></figure><figure><a href="警察D1.png"><img src="警察D1.png" alt="警察D1卷袖露小臂修订"></a><figcaption>D1 · 本次修订</figcaption></figure></section></main><script>document.querySelector('#background').onclick=()=>document.body.classList.toggle('dark');</script></html>''','utf8')
if '--gallery-only' in sys.argv:raise SystemExit(0)
assets=[]
for job in jobs['jobs']:
    p=O/(job['id']+'.png');source=Path((O/(job['id']+'-source.txt')).read_text('utf-8-sig').strip())
    im=Image.open(p);im.verify();im=Image.open(p)
    assert im.mode=='RGBA' and im.getchannel('A').getextrema()[0]==0
    assert sha(p)==sha(source)
    assets.append({'id':job['id'],'label':job['label'],'path':str(p),'source':str(source),'sha256':sha(p),'size':list(im.size),'genuine_alpha':True,'source_bytes_preserved':True,'reference':{'path':job['refs'][0],'sha256':sha(Path(job['refs'][0]))}})
assert len(assets)==2 and assets[0]['sha256']!=assets[1]['sha256']
receipt={'status':'c1_requested_revisions_for_review','generator':'built-in image_gen','runtime_modified':False,'assets':assets,'visual_review':'Cavalry keeps C1 navy/silver, selected feather hat, white horse four legs and saber; layered short cape/shawl/scarf with silver trim. Police has both forearms exposed by rolled sleeves, short full-finger gloves and over-knee boots.'}
for p in [D/'asset-ledger.json',O/'asset-ledger.json']:p.write_text(json.dumps(receipt,ensure_ascii=False,indent=2),'utf8')
shutil.copyfile(D/'generation-input.json',O/'generation-input.json')
with zipfile.ZipFile(O.with_suffix('.zip'),'w',zipfile.ZIP_DEFLATED) as z:
    for p in O.iterdir():
        if p.is_file() and not p.name.endswith('-source.txt'):z.write(p,p.name)
print(json.dumps({'revisions':2,'genuine_alpha':2,'source_bytes_preserved':2,'zip':str(O.with_suffix('.zip'))},ensure_ascii=False))
