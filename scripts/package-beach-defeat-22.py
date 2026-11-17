"""Package the latest depleted-force beach-defeat illustrations."""
from pathlib import Path
import json,hashlib,shutil,zipfile,html,math,sys
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
AERIAL='--aerial' in sys.argv
CLOSE='--close-aerial' in sys.argv
OUT=ROOT/('output/imagegen/beach-defeat-22-close-aerial-20261115' if CLOSE else ('output/imagegen/beach-defeat-22-aerial-20261115' if AERIAL else 'output/imagegen/beach-defeat-22-final-20261115'))
SUFFIX='近景俯视滩头败局' if CLOSE else ('高空俯视滩头败局' if AERIAL else '滩头败局')
inputs=json.loads((OUT/'inputs.json').read_text(encoding='utf-8'))
records=[]
for u in inputs:
    f=OUT/'results'/f'{u["id"]}.json'
    if not f.exists():continue
    r=json.loads(f.read_text(encoding='utf-8'));name=f'{u["id"]}-{u["name"]}-{SUFFIX}.png'
    target=OUT/name;shutil.copy2(r['source'],target)
    with Image.open(target) as im:im.verify()
    with Image.open(target) as im:size=list(im.size)
    assert hashlib.sha256(Path(u['reference']).read_bytes()).hexdigest()==u['reference_sha256']
    records.append({**r,'file':name,'size':size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
if not records:raise RuntimeError('No completed images')
assert len({r['id'] for r in records})==len(records)
assert len({r['sha256'] for r in records})==len(records)
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)
sheet=Image.new('RGB',(1800,140+math.ceil(len(records)/4)*292),'#f6f1e6');d=ImageDraw.Draw(sheet)
d.text((25,18),'群星协议 · 22战术部队'+SUFFIX,font=ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc',36),fill='#183c45')
d.text((25,78),'密集完整失能身体 / 兵力几近耗尽 / 淡黄色机油与衣装弹痕 / 非血腥',font=font,fill='#657f80')
for i,r in enumerate(records):
    im=Image.open(OUT/r['file']).convert('RGB');im.thumbnail((434,245));x=8+i%4*450;y=140+i//4*292
    sheet.paste(im,(x+(434-im.width)//2,y));d.text((x+8,y+248),r['id']+' '+r['name'],font=font,fill='#183c45')
sheet.save(OUT/('22战术部队'+SUFFIX+'总览.jpg'),quality=94)
qa=OUT/'review';qa.mkdir(exist_ok=True)
for start in range(0,len(records),6):
    tiles=records[start:start+6];review=Image.new('RGB',(1680,math.ceil(len(tiles)/2)*510),'#eee9df');rd=ImageDraw.Draw(review)
    for j,r in enumerate(tiles):
        im=Image.open(OUT/r['file']).convert('RGB');im.thumbnail((826,465));x=j%2*840;y=j//2*510;review.paste(im,(x+(826-im.width)//2,y));rd.text((x+12,y+470),r['id']+' '+r['name'],font=font,fill='#183c45')
    review.save(qa/f'batch-{start//6+1}.jpg',quality=96)
ledger={'mode':'built-in image_gen','count':len(records),'camera':'close elevated oblique; readable front full bodies' if CLOSE else ('high aerial near-top-down' if AERIAL else 'oblique'),'scope':'Independent fictional near-total defeat illustration; body density does not assert simulation deployment counts or results. No runtime asset replacement.','latest_direction':'No mass charge; intact disabled bodies dominate the beach; at most 2-3 barely mobile friendly bodies requested per scene.','review':'pending visual review','records':records}
(OUT/'ledger.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2),encoding='utf-8')
page='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>22部队滩头败局</title><style>body{background:#f6f1e6;color:#183c45;font:18px/1.7 "Microsoft YaHei",sans-serif;margin:25px}main{max-width:1500px;margin:auto}img{width:100%;height:auto;border-radius:12px}article{margin:35px 0}a{color:#287d80}nav{display:flex;flex-wrap:wrap;gap:14px}</style><main><h1>22战术部队 · 滩头败局</h1><p>最新构图：沙滩被密集完整失能身体覆盖，仅少数身体仍勉强活动，机枪工事继续压制。衣装护具弹痕、淡黄色机油与油湿斑块表现非血腥机械伤损。每图只出现本人多个成年女性身体。新增霜铃、夜枭，白鹭采用护士修女新版。</p><p>独立架空CG，画面密度不代表原核实际部署人数或战报。</p><nav>'+''.join(f'<a href="#{r["id"]}">{r["name"]}</a>' for r in records)+'</nav>'+''.join(f'<article id="{r["id"]}"><h2>{r["id"]} {r["name"]}</h2><p>{r["designation"]}</p><img loading="lazy" src="{html.escape(r["file"])}" alt="{r["name"]}滩头败局CG"></article>' for r in records)+'</main></html>'
if AERIAL:page=page.replace('22部队滩头败局','22部队高空俯视滩头败局').replace('22战术部队 · 滩头败局','22战术部队 · 高空俯视滩头败局').replace('最新构图：','最新构图：从空中接近垂直俯视完整海岸与机枪工事；')
if CLOSE:page=page.replace('22部队滩头败局','22部队近景俯视滩头败局').replace('22战术部队 · 滩头败局','22战术部队 · 近景俯视滩头败局').replace('最新构图：','最新构图：近距离斜俯视，人物面部与衣装可辨，不使用过远大海岸全景；')
(OUT/'查看22部队CG.html').write_text(page,encoding='utf-8')
(OUT/'说明.txt').write_text('22战术部队滩头败局CG\n最新要求：密集倒地身体为主，只有极少数残兵，不再成群冲锋。\n内置image_gen逐人生成；本人参考与实际提示见ledger.json、prompts.json。\n淡黄色机油、衣装弹痕、完整身体与衣装，非血腥。\n独立架空演出，不修改游戏、账户、真实编制或历史规则。\n',encoding='utf-8')
if len(records)==22:
    archive=OUT/('CAS-22战术部队-'+SUFFIX+'CG.zip')
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
        for p in OUT.iterdir():
            if p.is_file() and p.suffix!='.zip':z.write(p,p.name)
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        assert len([n for n in z.namelist() if n.endswith('.png')])==22
print(json.dumps({'completed':len(records),'expected':22,'out':str(OUT)},ensure_ascii=False))
