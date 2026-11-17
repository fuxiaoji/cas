"""Preserve ten generated CGs and make a paired offline gallery."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json,hashlib,shutil,html

ROOT=Path(__file__).resolve().parents[1]
DOC=ROOT/'docs/art/tactical-cg-pairs-20261115'
DEST=ROOT/'godot/assets/tactical/cg-pairs-20261115'
OUT=ROOT/'output/tactical-cg-pairs-20261115'
jobs=json.loads((DOC/'generation-input.json').read_text(encoding='utf-8'))
assert len(jobs)==10
for directory in (DEST,OUT/'images',DOC/'references'):directory.mkdir(parents=True,exist_ok=True)
ref=Path(jobs[0]['density_reference'])
shutil.copyfile(ref,DOC/'references/user-density-reference.png')
ledger={'version':'tactical-cg-pairs-v1','generator':'built-in image_gen','fictional_staged_art':True,'battle_evidence':False,'runtime_binding':False,'original_pixels_modified':False,'images':[]}
for job in jobs:
    source=Path(job['source']);target=DEST/f'{job["id"]}-{job["kind"]}.png'
    shutil.copyfile(source,target);shutil.copyfile(source,OUT/'images'/target.name)
    im=Image.open(target);im.load()
    sha=hashlib.sha256(source.read_bytes()).hexdigest()
    assert sha==hashlib.sha256(target.read_bytes()).hexdigest()
    row=dict(job,path='res://assets/tactical/cg-pairs-20261115/'+target.name,sha256=sha,size=list(im.size),mode=im.mode,source_bytes_preserved=True)
    row['reference_sha256']={r:hashlib.sha256(Path(r).read_bytes()).hexdigest() for r in job['references']}
    ledger['images'].append(row)
(DOC/'asset-ledger.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2),encoding='utf-8')
shutil.copyfile(DOC/'asset-ledger.json',OUT/'asset-ledger.json')
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',28)
title=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',38)
for kind,label in [('battle','抢滩进攻失败'),('cleanup','战后清理与物资回收')]:
    board=Image.new('RGB',(1600,1780),'#e9e6dc');draw=ImageDraw.Draw(board)
    draw.text((30,20),'CAS / '+label+' · 五部队CG',fill='#293d40',font=title)
    group=[j for j in jobs if j['kind']==kind]
    for i,j in enumerate(group):
        x=20+(i%2)*790;y=90+(i//2)*560
        draw.rounded_rectangle((x,y,x+770,y+540),radius=10,fill='#faf8ef')
        im=Image.open(DEST/f'{j["id"]}-{kind}.png').convert('RGB');im.thumbnail((746,470),Image.Resampling.LANCZOS)
        board.paste(im,(x+(770-im.width)//2,y+12+(470-im.height)//2))
        draw.text((x+16,y+488),j['name']+' / '+j['id'],fill='#293d40',font=font)
    board.save(OUT/f'{kind}-overview.jpg',quality=94)
cards=[]
for uid in dict.fromkeys(j['id'] for j in jobs):
    group=[j for j in jobs if j['id']==uid]
    figures=[]
    for j in group:
        file=f'images/{uid}-{j["kind"]}.png'
        label='进攻失败' if j['kind']=='battle' else '战后清理'
        figures.append(f'<figure><a href="{file}"><img src="{file}" alt="{html.escape(j["name"]+label)}"></a><figcaption>{label} · <a download href="{file}">保存原图</a></figcaption></figure>')
    cards.append('<section><h2>'+html.escape(group[0]['name'])+'<small>'+uid+'</small></h2><div class="pair">'+''.join(figures)+'</div></section>')
page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>CAS · 失败与战后清理CG</title><style>*{box-sizing:border-box}body{margin:0;background:#e9e6dc;color:#293d40;font:17px/1.7 "Microsoft YaHei",sans-serif}header{padding:35px 5vw;background:#293e43;color:#fff8e7}h1{margin:0;font-size:clamp(26px,4vw,40px)}header p{color:#d7dfd5;max-width:1100px}main{max-width:1700px;margin:25px auto;padding:0 22px}section{background:#fffdf5;border-radius:12px;margin-bottom:24px;padding:20px}h2{margin:0 0 16px;font-size:27px}small{font-size:15px;color:#788274;font-weight:400;margin-left:15px}.pair{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}figure{margin:0;min-width:0}img{display:block;width:100%;height:auto}figcaption{padding-top:10px}a{color:#40736d}footer{padding:22px 5vw;color:#68716b}@media(max-width:850px){.pair{grid-template-columns:1fr}main{padding:0 12px}section{padding:12px}}</style><header><h1>抢滩失败与战后清理</h1><p>五名部队各一组：镜头拉近的俯视进攻失败场景，以及战斗结束后仍在进行的遗体整理、外层装备与物资回收。战后图前景各有6具整理成短列，周边仍有大量未整理遗体与局部堆叠；人物保留完整身体和内层衣装。</p></header><main>'''+''.join(cards)+'''</main><footer>原创架空美术叙事，不代表真实对局或精确伤亡统计；尚未绑定游戏失败事件。点击图片可查看完整原图。</footer></html>'''
(OUT/'index.html').write_text(page,encoding='utf-8')
print(json.dumps({'cg_count':10,'identities':5,'original_bytes_preserved':True,'output':str(OUT)},ensure_ascii=False))

