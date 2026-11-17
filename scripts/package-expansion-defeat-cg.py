"""Preserve generated CG originals and build a local review gallery."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json, shutil, hashlib, html

ROOT=Path(__file__).resolve().parents[1]
DOC=ROOT/'docs/art/tactical-expansion-defeat-cg-20261115'
DEST=ROOT/'godot/assets/tactical/expansion-defeat-cg-20261115'
OUT=ROOT/'output/tactical-expansion-defeat-cg-20261115'
jobs=json.loads((DOC/'generation-input.json').read_text(encoding='utf-8'))
assert len(jobs)==5 and len({j['id'] for j in jobs})==5
for directory in (DEST,OUT/'images'): directory.mkdir(parents=True,exist_ok=True)
ledger={'version':'tactical-expansion-defeat-cg-v1','generator':'built-in image_gen',
        'fictional_staged_illustration':True,'actual_battle_evidence':False,
        'runtime_binding':False,'original_pixels_modified':False,'images':[]}
board=Image.new('RGB',(1600,1780),'#e9e6dc')
draw=ImageDraw.Draw(board)
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',26)
title=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',38)
draw.text((30,20),'CAS / 抢滩失败 · 五部队独立CG',fill='#293d40',font=title)
cards=[]
for i,job in enumerate(jobs):
    source=Path(job['source']); target=DEST/(job['id']+'-beach-defeat.png')
    shutil.copyfile(source,target); shutil.copyfile(source,OUT/'images'/target.name)
    im=Image.open(target);im.load()
    sha=hashlib.sha256(source.read_bytes()).hexdigest()
    assert sha==hashlib.sha256(target.read_bytes()).hexdigest()
    row=dict(job,path='res://assets/tactical/expansion-defeat-cg-20261115/'+target.name,
             sha256=sha,size=list(im.size),source_bytes_preserved=True,
             review='High-angle staged defeat illustration, same-person bodies, intact clothed figures, non-graphic blood marks; no runtime casualty-count assertion.')
    row['reference_sha256']={ref:hashlib.sha256(Path(ref).read_bytes()).hexdigest() for ref in job['references']}
    ledger['images'].append(row)
    x=20+(i%2)*790;y=90+(i//2)*560
    draw.rounded_rectangle((x,y,x+770,y+540),radius=10,fill='#faf8ef')
    thumb=im.convert('RGB');thumb.thumbnail((746,470),Image.Resampling.LANCZOS)
    board.paste(thumb,(x+(770-thumb.width)//2,y+12+(470-thumb.height)//2))
    draw.text((x+16,y+488),job['name']+' / '+job['title'],fill='#293d40',font=font)
    cards.append('<article><h2>'+html.escape(job['name'])+'<small>'+html.escape(job['title'])+'</small></h2><a href="images/'+target.name+'"><img src="images/'+target.name+'" alt="'+html.escape(job['name']+'抢滩失败场景')+'"></a><p>'+html.escape(job['description'])+'</p><a download href="images/'+target.name+'">保存原图</a></article>')
board.save(OUT/'five-cg-overview.jpg',quality=94)
(DOC/'asset-ledger.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2),encoding='utf-8')
shutil.copyfile(DOC/'asset-ledger.json',OUT/'asset-ledger.json')
page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>CAS · 抢滩失败CG</title><style>*{box-sizing:border-box}body{margin:0;background:#e9e6dc;color:#293d40;font:17px/1.7 "Microsoft YaHei",sans-serif}header{padding:35px 5vw;background:#293e43;color:#fff8e7}h1{margin:0;font-size:clamp(26px,4vw,40px)}header p{color:#d7dfd5}main{max-width:1600px;margin:25px auto;padding:0 22px;display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px}article{min-width:0;background:#fffdf5;border-radius:12px;padding:18px}article:last-child{grid-column:1/-1}h2{margin:0 0 12px;font-size:27px}small{display:block;color:#788274;font-size:16px;font-weight:400}img{display:block;width:100%;height:auto}a{color:#40736d}p{margin:12px 0}footer{padding:22px 5vw;color:#68716b}@media(max-width:800px){main{grid-template-columns:1fr;padding:0 12px}article{padding:12px}article:last-child{grid-column:auto}}</style><header><h1>抢滩失败 · 五部队独立CG</h1><p>高视角滩头进攻，分别表现开阔滩面、碎石滩、交叉火力与两栖战车受阻。大量倒地与持续冲锋构成失败叙事。</p></header><main>'''+''.join(cards)+'''</main><footer>原创架空美术场景，角色均为成年女性化人格的多个身体。画面不作为真实对局、伤亡统计或原书战例证据。点击图片查看完整原图。</footer></html>'''
(OUT/'index.html').write_text(page,encoding='utf-8')
print(json.dumps({'cg_count':len(jobs),'originals_preserved':True,'output':str(OUT)},ensure_ascii=False))
