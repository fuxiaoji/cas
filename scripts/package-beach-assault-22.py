"""Package the standalone twenty-two-personality active assault art series."""
from pathlib import Path
import json,hashlib,shutil,zipfile,html,math
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/beach-assault-22-20261115'
inputs=json.loads((OUT/'inputs.json').read_text(encoding='utf-8'))
records=[]
for u in inputs:
    result=OUT/'results'/f'{u["id"]}.json'
    if not result.exists():continue
    r=json.loads(result.read_text(encoding='utf-8'))
    filename=f'{u["id"]}-{u["name"]}-进攻滩头机枪阵地.png'
    target=OUT/filename;shutil.copy2(r['source'],target)
    with Image.open(target) as im:im.verify()
    with Image.open(target) as im:size=list(im.size)
    assert hashlib.sha256(Path(u['reference']).read_bytes()).hexdigest()==u['reference_sha256']
    records.append({**r,'file':filename,'size':size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
if not records:raise RuntimeError('No completed images')
assert len(set(r['id'] for r in records))==len(records)
assert len(set(r['sha256'] for r in records))==len(records)
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)
sheet=Image.new('RGB',(1800,140+math.ceil(len(records)/4)*292),'#f6f1e6');d=ImageDraw.Draw(sheet)
d.text((25,18),'群星协议 · 22战术部队进攻滩头机枪阵地',font=ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc',36),fill='#183c45')
d.text((25,78),'重大机械战损 / 持续推进 / 衣装弹痕与淡黄色机油 / 独立非血腥演出CG',font=font,fill='#657f80')
for i,r in enumerate(records):
    im=Image.open(OUT/r['file']).convert('RGB');im.thumbnail((434,245));x=8+i%4*450;y=140+i//4*292
    sheet.paste(im,(x+(434-im.width)//2,y));d.text((x+8,y+248),r['id']+' '+r['name'],font=font,fill='#183c45')
sheet.save(OUT/'22战术部队进攻滩头总览.jpg',quality=94)
qa=OUT/'review';qa.mkdir(exist_ok=True)
for start in range(0,len(records),6):
    tiles=records[start:start+6];review=Image.new('RGB',(1680,math.ceil(len(tiles)/2)*510),'#eee9df');rd=ImageDraw.Draw(review)
    for j,r in enumerate(tiles):
        im=Image.open(OUT/r['file']).convert('RGB');im.thumbnail((826,465));x=j%2*840;y=j//2*510;review.paste(im,(x+(826-im.width)//2,y));rd.text((x+12,y+470),r['id']+' '+r['name'],font=font,fill='#183c45')
    review.save(qa/f'batch-{start//6+1}.jpg',quality=96)
ledger={'mode':'built-in image_gen','count':len(records),'scope':'Independent fictional active assault illustration; densities do not assert simulation body counts or results. No runtime asset replacement.','review':'pending visual review','records':records}
(OUT/'ledger.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2),encoding='utf-8')
page='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>22部队进攻滩头机枪阵地</title><style>body{background:#f6f1e6;color:#183c45;font:18px/1.7 "Microsoft YaHei",sans-serif;margin:25px}main{max-width:1500px;margin:auto}img{width:100%;height:auto;border-radius:12px}article{margin:35px 0}a{color:#287d80}nav{display:flex;flex-wrap:wrap;gap:14px}</style><main><h1>22战术部队 · 进攻滩头机枪阵地</h1><p>每张独立本人形象：前景密集机械战损，中景持续推进，后景机枪阵地开火。淡黄色机油、衣装护具弹痕与油湿效果，完整身体与衣装、非血腥。新增霜铃、夜枭，白鹭采用护士修女新版。</p><p>独立架空CG演出，画面密度不代表原核实际部署人数或战报。</p><nav>'+''.join(f'<a href="#{r["id"]}">{r["name"]}</a>' for r in records)+'</nav>'+''.join(f'<article id="{r["id"]}"><h2>{r["id"]} {r["name"]}</h2><p>{r["designation"]}</p><img loading="lazy" src="{html.escape(r["file"])}" alt="{r["name"]}进攻滩头机枪阵地CG"></article>' for r in records)+'</main></html>'
(OUT/'查看22部队CG.html').write_text(page,encoding='utf-8')
(OUT/'说明.txt').write_text('22战术部队进攻滩头机枪阵地CG\n内置image_gen逐人生成；本人参考与完整提示见ledger.json、prompts.json。\n独立非血腥演出：机油、衣装弹痕、完整身体，重大损失仍持续推进。\n空降/空突表现已落地后进攻；航空部队保留旋翼协同。\n未替换游戏资源，未更改原核、账户或实际编制人数。\n',encoding='utf-8')
if len(records)==22:
    with zipfile.ZipFile(OUT/'CAS-22战术部队-进攻滩头机枪阵地CG.zip','w',zipfile.ZIP_DEFLATED) as z:
        for p in OUT.iterdir():
            if p.is_file() and p.suffix!='.zip' and p.name!='reference-review.jpg':z.write(p,p.name)
    with zipfile.ZipFile(OUT/'CAS-22战术部队-进攻滩头机枪阵地CG.zip') as z:
        assert z.testzip() is None
        assert len([n for n in z.namelist() if n.endswith('.png')])==22
print(json.dumps({'completed':len(records),'expected':22,'out':str(OUT)},ensure_ascii=False))
