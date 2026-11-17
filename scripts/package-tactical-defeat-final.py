"""Package the final two airborne and eighteen beach-defeat illustrations."""
import json,hashlib,shutil,zipfile,html
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/tactical-defeat-final-20261114'
units=json.loads((ROOT/'godot/data/tactical-units-v1.json').read_text(encoding='utf-8-sig'))['units']
air={'MCP-001','MCP-076'}
records=[]
for u in units:
    p=OUT/'results'/f'{u["id"]}.json'
    if not p.exists():continue
    r=json.loads(p.read_text(encoding='utf-8'))
    label='空降失败' if u['id'] in air else '抢滩失败'
    target=OUT/f'{u["id"]}-{u["name"]}-{label}.png'
    shutil.copy2(Path(r['source']),target)
    with Image.open(target) as im:im.verify()
    with Image.open(target) as im:size=list(im.size)
    records.append({**r,'name':u['name'],'designation':u['designation'],'scene_type':'airborne' if u['id'] in air else 'beach_landing','label':label,'file':target.name,'size':size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'reference_sha256':hashlib.sha256(Path(r['reference']).read_bytes()).hexdigest()})
assert len({r['id'] for r in records})==len(records)
assert len({r['sha256'] for r in records})==len(records)
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',19)
sheet=Image.new('RGB',(1800,140+((len(records)+3)//4)*292),'#f5f1e8')
d=ImageDraw.Draw(sheet);d.text((25,18),'群星协议 · 二十战术部队独立战败CG',font=ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc',38),fill='#193d48')
d.text((25,78),'云隼／冬鸢：空降失败 · 其余：抢滩失败 | 弹痕、淡黄色机油、衣装油湿 | 非血腥',font=font,fill='#637f80')
for i,r in enumerate(records):
    im=Image.open(OUT/r['file']).convert('RGB');im.thumbnail((434,245))
    x=8+(i%4)*450;y=140+(i//4)*292
    sheet.paste(im,(x+(434-im.width)//2,y));d.text((x+8,y+248),r['id']+' '+r['name']+' · '+r['label'],font=font,fill='#193d48')
sheet.save(OUT/'二十战术部队战败CG总览.jpg',quality=94)
ledger={'mode':'built-in image_gen','count':len(records),'classification':{'airborne':sorted(air),'beach_landing':[r['id'] for r in records if r['id'] not in air]},'records':records,'runtime_assets_modified':False,'review':'pending visual review'}
(OUT/'ledger.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2),encoding='utf-8')
index='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>二十战术部队战败CG集</title><style>body{background:#f5f1e8;color:#193d48;font:18px/1.7 "Microsoft YaHei",sans-serif;margin:25px}main{max-width:1500px;margin:auto}img{width:100%;height:auto;border-radius:12px}article{margin:30px 0}a{color:#287d80}nav{display:flex;flex-wrap:wrap;gap:14px}</style><main><h1>群星协议 · 二十战术部队独立战败CG</h1><p>云隼、冬鸢为空降／机降失败；其余十八支为抢滩登陆失败，赤隼和雨燕保留滩头直升机装备。每张只出现本人多个成年女性机器人身体，保留本人衣装。淡黄色机油、衣装弹孔焦痕和油湿深色斑块表现非血腥损伤。</p><nav>'+''.join(f'<a href="#{r["id"]}">{r["name"]}</a>' for r in records)+'</nav>'+''.join(f'<article id="{r["id"]}"><h2>{r["id"]} {r["name"]} · {r["label"]}</h2><p>{r["designation"]}</p><img src="{html.escape(r["file"])}" alt="{r["name"]}{r["label"]}CG" loading="lazy"></article>' for r in records)+'</main></html>'
(OUT/'查看全部CG.html').write_text(index,encoding='utf-8')
(OUT/'说明.txt').write_text('CAS 二十战术部队独立战败CG\n云隼/冬鸢：空降失败。其余十八支：抢滩失败。\n原图为内置图像生成工具逐张生成；参考与实际提示见ledger.json。\n仅独立美术交付，不是实际对局战报，不改运行时资源、规则或账户。\n旧全员空降候选未收入本包。\n',encoding='utf-8')
if len(records)==20:
    archive=OUT/'CAS-二十战术部队-战败CG.zip'
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
        for p in sorted(OUT.iterdir()):
            if p.is_file() and p.suffix!='.zip':z.write(p,p.name)
    with zipfile.ZipFile(archive) as z:assert z.testzip() is None
print(json.dumps({'count':len(records),'airborne':sum(r['id'] in air for r in records),'beach':sum(r['id'] not in air for r in records),'out':str(OUT)},ensure_ascii=False))
