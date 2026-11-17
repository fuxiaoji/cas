"""Preserve the five overhead revisions and produce an offline gallery."""
from pathlib import Path
import json, shutil, hashlib, zipfile
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[1]
DOC=ROOT/'docs/art/tactical-cg-overhead-20261115'
OUT=ROOT/'output/tactical-cg-overhead-20261115'

def main():
    jobs=json.loads((DOC/'generation-input.json').read_text(encoding='utf-8'))
    assert len(jobs)==5
    (OUT/'images').mkdir(parents=True,exist_ok=True)
    cards=[];ledger=[]
    board=Image.new('RGB',(1600,1710),'#e8e5dc')
    draw=ImageDraw.Draw(board);font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',27)
    for i,job in enumerate(jobs):
        src=Path(job['source']);dst=OUT/'images'/f'MCP-{job["id"]}-cleanup-overhead.png'
        shutil.copyfile(src,dst)
        with Image.open(dst) as im:
            im.load();size=list(im.size);thumb=im.convert('RGB');thumb.thumbnail((770,450))
        sha=hashlib.sha256(src.read_bytes()).hexdigest()
        assert sha==hashlib.sha256(dst.read_bytes()).hexdigest()
        row=dict(job,file='images/'+dst.name,size=size,sha256=sha,reference_sha256={r:hashlib.sha256(Path(r).read_bytes()).hexdigest() for r in job['references']})
        ledger.append(row)
        x=20+(i%2)*790;y=20+(i//2)*560
        board.paste(thumb,(x,y));draw.text((x,y+460),job['name']+' / MCP-'+str(job['id']),font=font,fill='#273e44')
        cards.append(f'<section><h2>{job["name"]} <small>MCP-{job["id"]}</small></h2><a href="{row["file"]}"><img src="{row["file"]}" alt="{job["name"]} 正上方俯拍战后清理"></a><p><a download href="{row["file"]}">保存原图</a></p></section>')
    board.save(OUT/'overview.jpg',quality=93)
    metadata={'generator':'built-in image_gen','fictional_art':True,'runtime_binding':False,'source_bytes_preserved':True,'images':ledger}
    for p in [DOC/'asset-ledger.json',OUT/'asset-ledger.json']:
        p.write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
    page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>五部队 · 垂直俯拍战后清理</title><style>*{box-sizing:border-box}body{margin:0;background:#e8e5dc;color:#273e44;font:17px/1.6 "Microsoft YaHei",sans-serif}header{padding:30px 5vw;background:#273e44;color:#faf6e9}h1{margin:0;font-size:clamp(24px,4vw,40px)}main{max-width:1450px;margin:auto;padding:24px}section{padding:20px;background:#fffdf7;margin-bottom:25px;border-radius:12px}h2{margin:0 0 16px}small{font-size:14px;color:#738482}img{width:100%;height:auto;display:block}a{color:#347274}footer{padding:24px 5vw}@media(max-width:600px){main{padding:12px}section{padding:10px}}</style><header><h1>五部队 · 垂直俯拍战后清理</h1><p>正上方直下的镜头，以中央整理队列和周围不同方向的散落遗体呈现战场回收。非血腥版。</p></header><main>'''+''.join(cards)+'''</main><footer>原创架空美术，非真实战报或精确伤亡统计；旧CG另存保留，未绑定游戏事件。</footer></html>'''
    (OUT/'index.html').write_text(page,encoding='utf-8')
    receipt={'image_count':5,'decoded':True,'source_hashes_match':True,'html_image_links':page.count('<img '),'browser_check_performed':False,'visual_review':'strict overhead; central row and irregular scattered fallen; no gore; proportions and count are artistic targets'}
    assert receipt['html_image_links']==5
    (OUT/'verification.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
    with zipfile.ZipFile(OUT.with_suffix('.zip'),'w',zipfile.ZIP_DEFLATED) as z:
        for p in OUT.rglob('*'):
            if p.is_file():z.write(p,p.relative_to(OUT))
    with zipfile.ZipFile(OUT.with_suffix('.zip')) as z:assert z.testzip() is None
    print(json.dumps(receipt,ensure_ascii=False))

if __name__=='__main__':main()
