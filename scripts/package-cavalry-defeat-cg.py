from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json, hashlib, shutil, zipfile, sys

R=Path(__file__).resolve().parents[1]
D=R/'docs/art/cavalry-defeat-cg-20261116'
O=R/'output/cavalry-defeat-cg-20261116'
A=R/'godot/assets/tactical/cg/cavalry-defeat-cg-20261116'
for p in [O/'images',A]: p.mkdir(parents=True,exist_ok=True)
jobs=json.loads((D/'generation-input.json').read_text(encoding='utf8'))['jobs']
sources=json.loads((D/'source-map.json').read_text(encoding='utf8'))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
ledger=[];cards=[]
board=Image.new('RGB',(1400,1290),'#ede8df');draw=ImageDraw.Draw(board)
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',24)
for i,j in enumerate(jobs):
    source=Path(sources[j['id']]);name=j['id']+'.png';dst=O/'images'/name
    shutil.copyfile(source,dst);shutil.copyfile(source,A/name)
    with Image.open(dst) as im:
        im.load();size=im.size;assert im.format=='PNG'
        thumb=im.convert('RGB');thumb.thumbnail((680,383))
    assert sha(source)==sha(dst)==sha(A/name)
    x=10+i%2*700;y=10+i//2*430
    board.paste(thumb,(x,y));draw.text((x,y+385),j['title'],font=font,fill='#273e48')
    refs=[dict(path=p,sha256=sha(p),role='identity and clothing only') for p in j['referenced_image_paths']]
    ledger.append(dict(id=j['id'],title=j['title'],source=str(source),file='images/'+name,size=size,sha256=sha(dst),references=refs,source_bytes_preserved=True))
    cards.append(f'<article><h2>{j["title"]}</h2><button class="zoom" aria-label="放大{j["title"]}"><img src="images/{name}" alt="{j["title"]}"></button><a href="images/{name}" download>下载原始PNG</a></article>')
board.save(O/'overview.jpg',quality=95)
html='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>骑兵 · 冲锋败局与战后清理</title><style>*{box-sizing:border-box}body{margin:0;background:#ede8df;color:#273e48;font:16px/1.6 system-ui}header,main{max-width:1440px;margin:auto;padding:24px}main{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px}article{background:#fffaf2;border:1px solid #c9c6ba;border-radius:12px;overflow:hidden;padding:14px}h1{font-size:clamp(24px,4vw,38px)}h2{font-size:20px}img{display:block;width:100%;height:auto}button{cursor:pointer;font:inherit;padding:8px;border:1px solid #acbcb4;border-radius:8px;background:#fffaf2;color:#273e48}.zoom{display:block;width:100%;padding:0;border:0}a{color:#236b73}dialog{max-width:96vw;width:1400px;max-height:95vh;padding:12px;border:0;background:#fffaf2}dialog::backdrop{background:#101a21d9}dialog img{max-height:83vh;object-fit:contain}.dark{background:#23333d;color:#e9e4d9}.dark article{background:#304651}header a{margin-left:12px}@media(max-width:750px){header,main{padding:14px}main{grid-template-columns:1fr}article{padding:10px}}</style><header><h1>骑兵 · 冲锋败局与战后清理</h1><p>滩头、阵地、城市三处冲锋败局，以及对应的敌方护士战后清理。沿用红卷短发、布头巾与青蓝银白骑装；部分骑手与白马分开倒下。</p><p>原创剧情CG，完整衣装、非血腥。人数与表情分配是构图目标，未绑定游戏实际战报或死亡事件。</p><button id="theme">切换深浅背景</button><a href="overview.jpg">六图总览</a></header><main>'''+''.join(cards)+'''</main><dialog><button id="close">关闭放大</button><img alt="放大预览"></dialog><script>const d=document.querySelector('dialog');document.querySelector('#theme').onclick=()=>document.body.classList.toggle('dark');for(const b of document.querySelectorAll('.zoom'))b.onclick=()=>{d.querySelector('img').src=b.querySelector('img').src;d.showModal()};document.querySelector('#close').onclick=()=>d.close();d.onclick=e=>{if(e.target===d)d.close()}</script></html>'''
(O/'index.html').write_text(html,encoding='utf8')
(D/'asset-ledger.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2),encoding='utf8')
(D/'qa-inventory.json').write_text(json.dumps(dict(claims=['six PNGs load','six original downloads','identity and distinct settings visually reviewed','desktop/mobile fit'],controls=['six zoom buttons','close button','Escape dismissal','theme toggle'],exploratory=['repeat zoom opening','mobile long title wrapping']),ensure_ascii=False,indent=2),encoding='utf8')
if '--archive' in sys.argv:
    records=O/'records';records.mkdir(exist_ok=True)
    for p in D.iterdir():
        if p.is_file():shutil.copyfile(p,records/p.name)
    zpath=O.with_suffix('.zip')
    with zipfile.ZipFile(zpath,'w',zipfile.ZIP_DEFLATED) as z:
        for p in O.rglob('*'):
            if p.is_file():z.write(p,p.relative_to(O))
    with zipfile.ZipFile(zpath) as z:
        assert z.testzip() is None
        for j in ledger:assert hashlib.sha256(z.read(j['file'])).hexdigest()==j['sha256']
    (D/'archive-validation.json').write_text(json.dumps(dict(crc_valid=True,original_hashes_match=6,bytes=zpath.stat().st_size,sha256=sha(zpath)),indent=2),encoding='utf8')
print(json.dumps(dict(images=len(ledger),sizes=[x['size'] for x in ledger],source_hashes_match=True,output=str(O)),ensure_ascii=False))
