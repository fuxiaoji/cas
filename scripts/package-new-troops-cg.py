from pathlib import Path
import json,hashlib,html,zipfile
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
NAME='new-troops-defeat-cleanup-20261116'
DOC=ROOT/'docs/art'/NAME
OUT=ROOT/'output'/NAME
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def archive():
    ledger=json.loads((OUT/'asset-ledger.json').read_text(encoding='utf-8'))['images']
    with zipfile.ZipFile(OUT.with_suffix('.zip'),'w',zipfile.ZIP_DEFLATED) as z:
        for p in [OUT/'index.html',OUT/'overview.jpg',OUT/'generation-input.json',OUT/'asset-ledger.json',OUT/'verification.json',*[OUT/r['file'] for r in ledger]]: z.write(p,p.relative_to(OUT))
    with zipfile.ZipFile(OUT.with_suffix('.zip')) as z:
        assert z.testzip() is None
        for r in ledger: assert hashlib.sha256(z.read(r['file'])).hexdigest()==r['sha256']
def main():
    data=json.loads((DOC/'generation-input.json').read_text(encoding='utf-8'));jobs=data['jobs'];assert len(jobs)==6
    ledger=[];cards=[];nav=[]
    board=Image.new('RGB',(1600,1530),'#e8e5dd');draw=ImageDraw.Draw(board);font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',25)
    for i,j in enumerate(jobs):
        record=json.loads((DOC/'results'/f'{j["id"]}.json').read_text(encoding='utf-8-sig'))
        if 'prompt' in record:
            j=dict(j,parent_generation=dict(j),prompt=record['prompt'],references=record['references'])
        src=Path(record['source']);dst=Path(record['destination']);assert sha(src)==sha(dst)
        with Image.open(dst) as im:
            im.load();size=list(im.size);thumb=im.convert('RGB');thumb.thumbnail((770,435))
        x=20+(i%2)*790;y=20+(i//2)*505;board.paste(thumb,(x,y));draw.text((x,y+440),j['title'],font=font,fill='#233d43')
        file='images/'+dst.name
        ledger.append(dict(j,source=str(src),file=file,size=size,sha256=sha(dst),reference_sha256={p:sha(p) for p in j['references']}))
        title=html.escape(j['title']);designation=html.escape(j['designation'])
        nav.append(f'<a href="#{j["id"]}">{title}</a>')
        cards.append(f'<article id="{j["id"]}"><h2>{title}<small>{designation} · {j["unit_id"]}</small></h2><a href="{file}"><img src="{file}" alt="{title}"></a><p><a download href="{file}">保存原始 PNG</a><a href="#top">返回目录 ↑</a></p></article>')
    board.save(OUT/'overview.jpg',quality=94)
    metadata={'generator':'built-in image_gen','model_seed_control':False,'fictional_art':True,'runtime_binding':False,'source_bytes_preserved':True,'images':ledger}
    for p in (DOC/'asset-ledger.json',OUT/'asset-ledger.json'):p.write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
    data['jobs']=ledger
    for p in (DOC/'final-prompt-set.json',OUT/'generation-input.json'):p.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>三新部队 · 战败与战后清理</title><style>*{box-sizing:border-box}body{margin:0;background:#e8e5dd;color:#233d43;font:16px/1.65 "Microsoft YaHei",sans-serif}header,footer{padding:28px 4vw}header{background:#233d43;color:#fffdf3}h1{font-size:clamp(24px,4vw,40px);margin:0}nav{display:flex;flex-wrap:wrap;gap:8px}nav a{color:#fffdf3;border:1px solid #7f9695;padding:4px 10px;border-radius:5px;text-decoration:none}main{max-width:1500px;margin:auto;padding:24px;display:grid;gap:24px;grid-template-columns:minmax(0,1fr)}article{min-width:0;background:#fffdf3;padding:16px;border-radius:12px}h2{margin:0 0 12px;font-size:24px}small{display:block;font-size:14px;font-weight:400;color:#607a7d}img{display:block;width:100%;height:auto}a{color:#35747b}article p{display:flex;justify-content:space-between;gap:12px}footer{font-size:14px}@media(max-width:600px){header,footer{padding:22px 16px}main{padding:12px;gap:15px}article{padding:10px}}</style><header id="top"><h1>三新部队 · 战败与战后清理</h1><p>第2骑兵团、第30山地突击旅、第17特种警察团，各一张战败、一张战后清理。以本轮所给造型为准，分别设计堤道、海崖和港口街区；完整衣装、非血腥。</p><nav>'''+''.join(nav)+'''</nav></header><main>'''+''.join(cards)+'''</main><footer>原创架空美术，不代表真实战报或精确伤亡统计。点击图片查看完整原图。</footer></html>'''
    (OUT/'index.html').write_text(page,encoding='utf-8')
    report={'image_count':6,'decoded':True,'source_hashes_match':True,'html_image_links':6,'browser_check_performed':False,'visual_review':None}
    for folder in (DOC,OUT):(folder/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    archive();print(json.dumps({'images':6,'source_hashes_match':True,'zip_crc':True}))
if __name__=='__main__':main()
