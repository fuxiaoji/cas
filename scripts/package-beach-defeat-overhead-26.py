"""Package preserved imagegen originals into a reviewable 26-unit gallery."""
from pathlib import Path
import json, hashlib, html, shutil, zipfile
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[1]
NAME='beach-defeat-overhead-26-20261115'
DOC=ROOT/'docs/art'/NAME
OUT=ROOT/'output'/NAME

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main():
    data=json.loads((DOC/'generation-input.json').read_text(encoding='utf-8'))
    jobs=data['jobs']
    assert len(jobs)==26 and len({j['id'] for j in jobs})==26
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',25)
    ledger=[];cards=[];nav=[]
    boards=[]
    for start in range(0,26,6):
        group=jobs[start:start+6]
        board=Image.new('RGB',(1600,((len(group)+1)//2)*515+20),'#e7e5dc')
        boards.append((start,board,ImageDraw.Draw(board)))
    for index,job in enumerate(jobs):
        record=json.loads((DOC/'results-final'/f'{job["id"]}.json').read_text(encoding='utf-8'))
        src=Path(record['source']);dst=Path(record['destination'])
        assert dst.is_file() and sha(src)==sha(dst)
        with Image.open(dst) as im:
            im.load();size=list(im.size);thumb=im.convert('RGB');thumb.thumbnail((770,435))
        file='images/'+dst.name
        row=dict(job,source=str(src),file=file,size=size,sha256=sha(dst),reference_sha256={p:sha(p) for p in job['references']})
        ledger.append(row)
        start,board,draw=boards[index//6];local=index-start
        x=20+(local%2)*790;y=20+(local//2)*515
        board.paste(thumb,(x,y));draw.text((x,y+443),f'{job["id"]}  {job["name"]} · {job["designation"]}',font=font,fill='#233d43')
        label=html.escape(job['name']);designation=html.escape(job['designation'])
        nav.append(f'<a href="#{job["id"]}">{label}</a>')
        cards.append(f'<article id="{job["id"]}"><h2>{label}<small>{job["id"]} · {designation}</small></h2><a href="{file}"><img src="{file}" alt="{label}近距俯拍抢滩败局"></a><p><a download href="{file}">保存原始 PNG</a><a href="#top">返回目录 ↑</a></p></article>')
    for i,(_,board,_) in enumerate(boards):
        board.save(OUT/f'overview-{i+1}.jpg',quality=94)
    metadata={'generator':'built-in image_gen','fictional_art':True,'runtime_binding':False,'source_bytes_preserved':True,'images':ledger}
    (DOC/'asset-ledger.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
    (OUT/'asset-ledger.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
    shutil.copyfile(DOC/'generation-input.json',OUT/'generation-input.json')
    page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>26部队 · 近距俯拍抢滩败局</title><style>*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:#e7e5dc;color:#233d43;font:16px/1.65 "Microsoft YaHei",sans-serif}header,footer{padding:28px 4vw}header{background:#233d43;color:#fbf8ec}h1{font-size:clamp(24px,4vw,42px);margin:0}header p{max-width:900px}nav{display:flex;flex-wrap:wrap;gap:8px}nav a{color:#fbf8ec;border:1px solid #668084;border-radius:5px;padding:3px 10px;text-decoration:none}main{max-width:1500px;margin:auto;padding:24px;display:grid;grid-template-columns:minmax(0,1fr);gap:24px}article{min-width:0;background:#fffdf5;padding:16px;border-radius:12px;scroll-margin-top:12px}h2{font-size:24px;margin:0 0 12px}small{font-size:14px;display:block;font-weight:400;color:#677d7d}img{width:100%;height:auto;display:block}a{color:#35747b}article p{display:flex;justify-content:space-between;gap:12px;margin-bottom:0}footer{font-size:14px}@media(max-width:780px){main{grid-template-columns:minmax(0,1fr);padding:12px;gap:15px}article{padding:10px}header,footer{padding:22px 16px}}</style><header id="top"><h1>26部队 · 近距俯拍抢滩败局</h1><p>原二十支、榛穗等五支及芷宁第6步兵团，各一张独立CG。近距正上方镜头，散落倒姿、受阻的进攻路线与各部队装备。完整制服、非血腥版。</p><nav>'''+''.join(nav)+'''</nav></header><main>'''+''.join(cards)+'''</main><footer>原创架空美术；不代表真实战报或精确伤亡统计。点击图片查看完整原图。</footer></html>'''
    (OUT/'index.html').write_text(page,encoding='utf-8')
    report={'image_count':26,'decoded':True,'source_hashes_match':True,'html_image_links':page.count('<img '),'browser_check_performed':False,'visual_review':None}
    assert report['html_image_links']==26
    for folder in [DOC,OUT]:
        (folder/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    archive()
    print(json.dumps({'images':26,'overview_pages':len(boards),'source_hashes_match':True,'zip_crc':True}))

def archive():
    ledger=json.loads((OUT/'asset-ledger.json').read_text(encoding='utf-8'))['images']
    allowed=[OUT/'index.html',OUT/'generation-input.json',OUT/'asset-ledger.json',OUT/'verification.json',*OUT.glob('overview-*.jpg'),*[OUT/row['file'] for row in ledger]]
    assert len(ledger)==26
    with zipfile.ZipFile(OUT.with_suffix('.zip'),'w',zipfile.ZIP_DEFLATED) as z:
        for p in allowed:z.write(p,p.relative_to(OUT))
    with zipfile.ZipFile(OUT.with_suffix('.zip')) as z:
        assert z.testzip() is None
        for row in json.loads((OUT/'asset-ledger.json').read_text(encoding='utf-8'))['images']:
            assert hashlib.sha256(z.read(row['file'])).hexdigest()==row['sha256']

if __name__=='__main__':main()
