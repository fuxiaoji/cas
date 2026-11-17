"""Package generated CGs without modifying source or runtime assets."""
import json,hashlib,shutil,zipfile,html
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/airdrop-failure-20261114'
jobs=json.loads((OUT/'final-prompts.json').read_text(encoding='utf-8'))['jobs']
results={}
for result_file in sorted((OUT/'results').glob('MCP-*.json')):
    r=json.loads(result_file.read_text(encoding='utf-8'))
    if r.get('source'):results[r['id']]=r
(OUT/'generation-results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
records=[]
for job in jobs:
    r=results.get(job['id'])
    if not r:continue
    source=Path(r['source']);dest=OUT/(job['id']+'-'+job['name']+'-空降失败.png')
    shutil.copy2(source,dest)
    with Image.open(dest) as im: size=list(im.size)
    records.append({**job,**r,'file':dest.name,'size':size,'sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'reference_sha256':hashlib.sha256(Path(job['reference']).read_bytes()).hexdigest()})
if not records:raise RuntimeError('No generated output')
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',19)
sheet=Image.new('RGB',(1600,120+len(records)//4*260+260*(len(records)%4>0)),'#f5f1e8')
d=ImageDraw.Draw(sheet);d.text((25,18),'群星协议 · 二十人格独立空降失败CG',font=ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc',36),fill='#193d48')
d.text((25,75),'淡黄色机械油迹 / 同一人格多身体 / 非血腥 / 独立架空情境，不代表实战结果',font=font,fill='#637f80')
for i,r in enumerate(records):
    im=Image.open(OUT/r['file']).convert('RGB');im.thumbnail((386,218))
    x=10+(i%4)*400;y=120+(i//4)*260
    sheet.paste(im,(x+(386-im.width)//2,y));d.text((x+8,y+222),r['id']+' '+r['name'],font=font,fill='#193d48')
sheet.save(OUT/'二十人格空降失败CG总览.jpg',quality=92)
(OUT/'ledger.json').write_text(json.dumps({'mode':'built-in image_gen','count':len(records),'scope':'non-graphic fictional alternate airdrop scene; not a simulation result or runtime capability','records':records},ensure_ascii=False,indent=2),encoding='utf-8')
index='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>空降失败CG集</title><style>body{background:#f5f1e8;color:#193d48;font:18px/1.7 "Microsoft YaHei",sans-serif;margin:25px}main{max-width:1500px;margin:auto}img{width:100%;height:auto;border-radius:12px}article{margin:30px 0}a{color:#287d80}nav{display:flex;flex-wrap:wrap;gap:14px}</style><main><h1>群星协议 · 独立空降失败CG</h1><p>完整衣装、非血腥机械伤损，以淡黄色机油、装备弹痕、伞具和烟尘表现。各图仅出现本人同意识多身体。属于独立架空情境，未改游戏设定或实战裁决。</p><nav>'+''.join(f'<a href="#{r["id"]}">{r["name"]}</a>' for r in records)+'</nav>'+''.join(f'<article id="{r["id"]}"><h2>{r["id"]} {r["name"]}</h2><img src="{html.escape(r["file"])}" alt="{r["name"]}空降失败CG" loading="lazy"></article>' for r in records)+'</main></html>'
(OUT/'查看CG.html').write_text(index,encoding='utf-8')
if len(records)==20:
    with zipfile.ZipFile(OUT/'CAS-二十战术部队-空降失败CG.zip','w',zipfile.ZIP_DEFLATED) as z:
        for p in sorted(OUT.iterdir()):
            if p.is_file() and p.suffix!='.zip':z.write(p,p.name)
    with zipfile.ZipFile(OUT/'CAS-二十战术部队-空降失败CG.zip') as z:assert z.testzip() is None
print(json.dumps({'packaged':len(records),'out':str(OUT)},ensure_ascii=False))
