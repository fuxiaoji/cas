"""Build the eight-option portrait gallery, preserving generated source bytes."""
from pathlib import Path
import hashlib,json,zipfile,re
from PIL import Image

root=Path(__file__).resolve().parents[1]
doc=root/'docs/art/cavalry-police-choices-v3-20261116'
out=root/'output/cavalry-police-choices-v3-20261116'
jobs=json.loads((doc/'generation-input.json').read_text('utf8'))
template=(root/'output/cavalry-police-choices-v2-20261116/index.html').read_text('utf-8-sig')
cavalry=[j['label'] for j in jobs['jobs'] if j['id'].startswith('骑兵')]
police=[j['label'] for j in jobs['jobs'] if j['id'].startswith('警察')]
template=re.sub(r'const cavalry=\[.*?\];const police=\[.*?\];','const cavalry='+json.dumps(cavalry,ensure_ascii=False)+';const police='+json.dumps(police,ensure_ascii=False)+';',template,flags=re.S)
template=template.replace("kind+'B'+(i+1)","kind+'C'+(i+1)")
template=template.replace('第二轮各5张。骑兵：羽毛警帽与遮半身披肩。警察：不同警帽警服，仅修身裤或裙装。点击图片放大。','第三轮：骑兵3套短披肩与新上衣，保留已选羽毛帽；警察5套新警服，靴子全部过膝。点击图片放大。')
template=template.replace('第二轮服装选型','第三轮服装选型').replace('骑兵 · 金发盘发 / 白马 / 马刀','骑兵 · 固定羽毛帽 / 干练短披肩 / 白马马刀')
(out/'index.html').write_text(template,'utf8')
# --gallery-only permits checking layout while generation is still running.
import sys
if '--gallery-only' in sys.argv:
    print('Gallery authored: 3 cavalry + 5 police')
    raise SystemExit(0)
rows=[]
for job in jobs['jobs']:
    p=out/(job['id']+'.png');source=Path((out/(job['id']+'-source.txt')).read_text('utf-8-sig').strip())
    im=Image.open(p);im.verify();im=Image.open(p)
    assert im.mode=='RGBA' and im.getchannel('A').getextrema()[0]==0 and im.getchannel('A').getextrema()[1]>=250,job['id']
    sha=hashlib.sha256(p.read_bytes()).hexdigest()
    assert sha==hashlib.sha256(source.read_bytes()).hexdigest()
    rows.append({'id':job['id'],'label':job['label'],'source':str(source),'path':str(p),'sha256':sha,'size':list(im.size),'genuine_alpha':True,'source_bytes_preserved':True,'selected':False})
assert len(rows)==8 and len({r['sha256'] for r in rows})==8
receipt={'status':'awaiting_user_selection','generator':'built-in image_gen','count':8,'approved_component':'cavalry reference hat only','runtime_or_account_modified':False,'assets':rows,'visual_review':'Cavalry: same accepted feather bowler hat; short half cape at waist/upper hip, new jacket, white horse four legs/hooves. Police: three skirt and two fitted-trouser variants, boot shafts above knees. No final outfit selected.'}
for p in [doc/'asset-ledger.json',out/'asset-ledger.json']:p.write_text(json.dumps(receipt,ensure_ascii=False,indent=2),'utf8')
(out/'generation-input.json').write_text(json.dumps(jobs,ensure_ascii=False,indent=2),'utf8')
with zipfile.ZipFile(out.with_suffix('.zip'),'w',zipfile.ZIP_DEFLATED) as z:
    for p in out.iterdir():
        if p.is_file() and not p.name.endswith('-source.txt'):z.write(p,p.name)
print(json.dumps({'count':8,'unique':8,'transparent':8,'original_bytes_preserved':8,'zip':str(out.with_suffix('.zip'))},ensure_ascii=False))
