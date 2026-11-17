"""Copy generated originals without editing alpha; make an inspectable album."""
from pathlib import Path
import json,hashlib,shutil,html,os
from PIL import Image
R=Path(__file__).resolve().parents[1]
jobs=json.loads((R/'tools/carrier-art-registration-input.json').read_text(encoding='utf-8'))
out=R/'godot/assets/ships/carrier-20261115';out.mkdir(parents=True,exist_ok=True)
rows=[]
for job in jobs:
 row={k:job[k] for k in ('id','name','key','costume')};row['status']='generated_internal_visual_review';row['source_only']=True
 for kind in ('portrait','chibi'):
  source=Path(job[kind+'_source']);target=out/(job['key']+'-'+kind+'.png');shutil.copyfile(source,target)
  im=Image.open(target);assert im.mode=='RGBA' and im.getextrema()[3][0]==0,(source,im.mode)
  row[kind]='res://'+target.relative_to(R/'godot').as_posix()
  row[kind+'_provenance']={'source':str(source),'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'size':list(im.size),'prompt':job[kind+'_prompt'],'generator':'built-in imagegen','alpha_preserved':True}
 row['chibi_references']=['own portrait identity only','res://assets/characters/chibis-generated/ibs-u-usn-fletcher.png style only','res://assets/characters/chibis/ibs-u-ijn-kagero.png style only']
 rows.append(row)
manifest={'version':'cas-carrier-art-v1','characters':rows,'rejected':'First-wave mature portraits not adopted; see style correction. Existing art unmodified.'}
(R/'godot/data/carrier-art-v1.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(R/'docs/art/carrier-20261115-final-ledger.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
album=R/'output/carrier-20261115';album.mkdir(parents=True,exist_ok=True)
def url(res):return Path(os.path.relpath(R/'godot'/res.removeprefix('res://'),album)).as_posix()
cards=[]
for r in rows:
 cards.append(f'<article><h2>{html.escape(r["name"])}</h2><div class="art"><img class="portrait" src="{url(r["portrait"])}"><div class="sd"><img src="{url(r["chibi"])}"><div class="sizes"><img height="80" src="{url(r["chibi"])}"><img height="160" src="{url(r["chibi"])}"></div></div></div><p>{html.escape(r["costume"])}</p><small>{r["id"]} · 原创立绘与本人SD · 资料收录，尚未开放出战</small></article>')
guide=(R/'docs/development/carrier-player-guide-20261115.md').read_text(encoding='utf-8')
prose=[]
in_table=False
for line in guide.splitlines():
 if line.startswith('|'):
  if not in_table:prose.append('<table>');in_table=True
  cells=[c.strip() for c in line.strip('|').split('|')]
  if all(set(c)<=set('-: ') for c in cells):continue
  prose.append('<tr>'+''.join('<td>'+html.escape(c)+'</td>' for c in cells)+'</tr>');continue
 if in_table:prose.append('</table>');in_table=False
 if line.startswith('# '):continue
 if line.startswith('## '):prose.append('<h3>'+html.escape(line[3:])+'</h3>')
 elif line:prose.append('<p>'+html.escape(line)+'</p>')
source=json.loads((R/'data/carrier/pacific-source-v1.json').read_text(encoding='utf-8'))
table='<table><tr><th>舰机</th><th>原书页码</th><th>记录状态</th></tr>'+''.join(f'<tr><td>{html.escape(r["name"])}</td><td>{html.escape(r["source"]["book"])} · PDF{r["source"]["pdf_page"]} / {r["source"]["printed_page"]}</td><td>source_only · 未开放出战</td></tr>' for r in source['ships']+source['aircraft'])+'</table>'
page='''<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>CAS 太平洋舰载航空 · 立绘与教学</title><style>*{box-sizing:border-box}body{margin:0;background:#edf2ee;color:#163943;font:17px/1.75 "Microsoft YaHei",sans-serif}header{background:#183d4b;color:#fff8e8;padding:48px 6vw}header h1{font-size:38px;margin:0}header p{color:#d5e5df;max-width:900px}nav a{color:#ffe1a5;margin-right:26px}main{max-width:1500px;margin:auto;padding:32px}section{margin-bottom:40px}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px}article{background:#fffcf3;border-radius:16px;padding:24px;box-shadow:0 4px 20px #15353b12}h2{margin:0 0 12px}article p{margin:8px 0}small{color:#667c7e}.art{display:flex;align-items:center;min-height:500px;background:linear-gradient(135deg,#e3ece9,#fff9eb);border-radius:10px}.portrait{width:60%;height:520px;object-fit:contain}.sd{width:40%;text-align:center}.sd>img{width:100%;max-height:240px;object-fit:contain}.sizes{display:flex;align-items:end;justify-content:center;gap:12px}.sizes img{max-width:50%;object-fit:contain}.reading{background:#fffdf6;padding:36px;max-width:1050px;margin:0 auto;border-radius:16px}h3{margin-top:30px;font-size:24px}table{width:100%;border-collapse:collapse;font-size:15px}td,th{text-align:left;padding:12px;border-bottom:1px solid #cbd9d6}th{background:#dbe7e2}@media(max-width:850px){.grid{grid-template-columns:1fr}main{padding:16px}.portrait{height:420px}.art{min-height:420px}}</style><header><h1>太平洋舰载航空</h1><p>清甜灵动的原创舰娘 · 同级家族元素 · 本人立绘对应两头身SD。成熟工装旧稿未采用，本页展示按最新反馈重画的版本。小人附80 / 160像素查看。</p><nav><a href="#art">人物图鉴</a><a href="#source">原书资料</a><a href="#guide">航母教学</a></nav></header><main>'''
page+='<style>article{min-width:0}table{table-layout:fixed}td,th,small{overflow-wrap:anywhere}.sizes img{min-width:0;max-width:calc(50% - 6px)}@media(max-width:850px){header h1{font-size:30px}.reading{padding:22px}.art{min-width:0}}</style>'
page+='<section id="art" class="grid">'+''.join(cards)+'</section><section id="source"><h2>原版数据录入 · 七舰 / 七机</h2>'+table+'</section><section id="guide" class="reading">'+''.join(prose)+'</section></main>'
(album/'index.html').write_text(page,encoding='utf-8');print(f'{len(rows)} portraits + {len(rows)} chibis; {album / "index.html"}')
