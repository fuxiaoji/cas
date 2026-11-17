"""Package the new non-graphic five-unit CG series without replacing older art."""
from pathlib import Path
import json, shutil, hashlib, zipfile, html
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/tactical-cg-extent-20261115'
DOC=ROOT/'docs/art/tactical-cg-extent-20261115'

def main():
    jobs=json.loads((DOC/'generation-input.json').read_text(encoding='utf-8'))
    assert len(jobs)==10
    (OUT/'images').mkdir(parents=True,exist_ok=True)
    ledger=[]
    for job in jobs:
        src=Path(job['source']); dst=OUT/'images'/f"MCP-{job['id']}-{job['kind']}.png"
        shutil.copyfile(src,dst)
        with Image.open(dst) as im:
            im.load(); size=list(im.size)
        digest=hashlib.sha256(src.read_bytes()).hexdigest()
        assert digest==hashlib.sha256(dst.read_bytes()).hexdigest()
        ledger.append(dict(job,file='images/'+dst.name,size=size,sha256=digest,reference_sha256={r:hashlib.sha256(Path(r).read_bytes()).hexdigest() for r in job['references']}))
    meta={'generator':'built-in image_gen','fictional_art':True,'runtime_binding':False,'original_bytes_preserved':True,'images':ledger}
    for dst in [DOC/'asset-ledger.json',OUT/'asset-ledger.json']:
        dst.write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf-8')
    cards=[]
    for uid in [301,302,303,304,305]:
        rows=[j for j in ledger if j['id']==uid]
        figures=[]
        for j in rows:
            label='抢滩败局' if j['kind']=='battle' else '战后清理'
            figures.append(f'<figure><a href="{j["file"]}"><img src="{j["file"]}" alt="{j["name"]} · {label}"></a><figcaption>{label} · <a download href="{j["file"]}">保存原图</a></figcaption></figure>')
        cards.append(f'<section><h2>{html.escape(rows[0]["name"])} <small>MCP-{uid}</small></h2><div class="pair">'+''.join(figures)+'</div></section>')
    page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>五部队 · 滩头败局与战后清理</title><style>*{box-sizing:border-box}body{margin:0;background:#e8e5dc;color:#273e44;font:17px/1.6 "Microsoft YaHei",sans-serif}header{background:#273e44;color:#faf6e9;padding:32px 5vw}h1{font-size:clamp(24px,4vw,40px);margin:0}main{max-width:1700px;margin:auto;padding:24px}section{padding:20px;background:#fffdf7;margin-bottom:26px;border-radius:12px}h2{margin:0 0 16px}small{font-size:14px;color:#738482}.pair{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:20px}figure{margin:0;min-width:0}img{width:100%;display:block}a{color:#347274}figcaption{padding-top:10px}footer{padding:24px 5vw}@media(max-width:800px){main{padding:12px}.pair{grid-template-columns:1fr}section{padding:12px}}</style><header><h1>五部队 · 滩头败局与战后清理</h1><p>前后景延伸的伤亡、零星幸存者；中等俯角、无毯子的战后整理与分类物资。非血腥版，原有CG保留。</p></header><main>'''+''.join(cards)+'''</main><footer>原创架空美术，非真实战报；画面数量不代表游戏编制或精确伤亡，尚未接入游戏事件。</footer></html>'''
    (OUT/'index.html').write_text(page,encoding='utf-8')
    board=Image.new('RGB',(1600,2550),'#e8e5dc');draw=ImageDraw.Draw(board)
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',27)
    for i,j in enumerate(ledger):
        x=20+(i%2)*790;y=16+(i//2)*507
        with Image.open(OUT/j['file']) as src:
            im=src.convert('RGB');im.thumbnail((770,440));board.paste(im,(x,y))
        draw.text((x,y+447),j['name']+' / '+('抢滩败局' if j['kind']=='battle' else '战后清理'),font=font,fill='#273e44')
    board.save(OUT/'overview.jpg',quality=92)
    with zipfile.ZipFile(OUT.with_suffix('.zip'),'w',zipfile.ZIP_DEFLATED) as z:
        for p in OUT.rglob('*'):
            if p.is_file(): z.write(p,p.relative_to(OUT))
    print(json.dumps({'images':len(ledger),'all_decoded':True,'sha_verified':True,'output':str(OUT)},ensure_ascii=False))

if __name__=='__main__': main()
