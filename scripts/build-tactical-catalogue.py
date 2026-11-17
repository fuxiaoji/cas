"""Read-only illustrated snapshot of the current tactical roster."""
import sys, json, math, io, base64, hashlib, html
from pathlib import Path
sys.path.append(r'C:\Program Files\WindowsApps\OpenAI.CodexPrimaryRuntime.v26-1112-611-0_26.1112.611.0_x64__3k8sg7r9htsxt\dependencies\python\Lib\site-packages')
from PIL import Image, ImageDraw, ImageFont
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.utils import ImageReader
import fitz

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/pdf/tactical-catalogue-20261114'
OUT.mkdir(parents=True,exist_ok=True)
TMP=ROOT/'tmp/pdfs/tactical-catalogue-20261114'
TMP.mkdir(parents=True,exist_ok=True)
units=json.loads((ROOT/'godot/data/tactical-units-v1.json').read_text(encoding='utf-8-sig'))['units']
profiles={x['id']:x for x in json.loads((ROOT/'godot/data/tactical-profiles-v4.json').read_text(encoding='utf-8-sig'))['cards']}
pdfmetrics.registerFont(TTFont('CN',r'C:\Windows\Fonts\msyh.ttc',subfontIndex=0))
pdfmetrics.registerFont(TTFont('CNB',r'C:\Windows\Fonts\msyhbd.ttc',subfontIndex=0))
INK='#193d48'; TEAL='#287d80'; MUTED='#647b81'; PAPER='#f6f3eb'; GOLD='#bb8546'
W,H=960,680

def echelon(u):
    for k,s in [('师','XX'),('旅','X'),('团','III'),('营','II'),('连','I')]:
        if k in u['designation']:return s,k
    return '', '未登记级别'

def token(u):
    im=Image.new('RGBA',(360,280),(0,0,0,0)); d=ImageDraw.Draw(im)
    fill='#183f48'; ink='#d7f1e9'; stroke=7
    mark,_=echelon(u)
    if mark:d.text((180,32),mark,font=ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc',48),fill=fill,anchor='mm')
    d.rectangle((10,76,350,260),fill=fill,outline=ink,width=stroke)
    # Same normalized internal marks as tactical_type_token.gd.
    ax,ay,aw,ah=85,116,190,103
    def line(points,w=stroke): d.line([(ax+x*aw,ay+y*ah) for x,y in points],fill=ink,width=w,joint='curve')
    def circle(x,y,r,filled=False):
        box=(ax+x*aw-r,ay+y*ah-r,ax+x*aw+r,ay+y*ah+r)
        d.ellipse(box,fill=ink if filled else None,outline=ink,width=stroke)
    role=u['role']
    if role in ['marine','airborne','riverine','infantry']:
        line([(.05,.1),(.95,.9)]);line([(.05,.9),(.95,.1)])
        if role=='marine':line([(0,1),(.25,.88),(.5,1),(.75,.88),(1,1)])
        if role=='riverine':line([(-.1,.7),(.1,1.1),(.9,1.1),(1.1,.7)])
        if role=='airborne':line([(0,.18),(.2,-.1),(.5,-.22),(.8,-.1),(1,.18)])
    elif role=='armor':circle(.5,.5,ah*.4);line([(.35,.5),(1,.5)])
    elif role in ['air_assault','gunship']:
        line([(0,.18),(1,.18)]);line([(.5,.05),(.5,.72),(.22,.94)]);line([(.5,.72),(.78,.94)])
        if role=='gunship':line([(.16,.62),(.84,.62)])
    elif role in ['recon','sniper']:
        line([(.1,.9),(.9,.1)])
        circle(.5,.5,min(aw,ah)*.34) if role=='sniper' else circle(.72,.7,stroke*1.3,True)
    elif role in ['engineer','breacher']:
        line([(.1,.95),(.1,.2),(.9,.2),(.9,.95)]);line([(.1,.55),(.9,.55)])
        if role=='breacher':line([(.5,.2),(.38,.5),(.63,.5),(.42,.85)])
    elif role in ['medic','rescue']:
        line([(.5,.1),(.5,.9)],11);line([(.1,.5),(.9,.5)],11)
        if role=='rescue':circle(.5,.5,min(aw,ah)*.58)
    elif role=='artillery':circle(.5,.5,stroke*1.8,True)
    elif role=='antiarmor':line([(.05,.9),(.5,.08),(.95,.9),(.05,.9)])
    elif role=='airdefense':
        line([(.5+.75*ah/aw*math.cos(t),.9+.75*math.sin(t)) for t in [math.pi+i*math.pi/24 for i in range(25)]]);line([(.5,.9),(.5,.05)])
    elif role=='electronic':line([(.1,.55),(.3,.55),(.44,.1),(.6,.9),(.74,.4),(.92,.4)])
    elif role in ['transport','logistics']:
        line([(.05,.2),(.95,.2),(.95,.78),(.05,.78),(.05,.2)])
        if role=='transport':circle(.25,.95,stroke*1.2,True);circle(.75,.95,stroke*1.2,True)
        else:line([(.5,.2),(.5,.78)])
    elif role=='command':line([(.2,1),(.2,0),(.9,.15),(.2,.5)])
    return im

def portrait(u):
    im=Image.open(ROOT/'godot'/u['portrait'].removeprefix('res://')).convert('RGBA')
    box=im.getbbox(); return im.crop(box) if box else im

def sprite(u,frame=0):
    if not u.get('sprite_sheet'):return None
    im=Image.open(ROOT/'godot'/u['sprite_sheet'].removeprefix('res://')).convert('RGBA')
    cw,ch=im.width//4,im.height//3
    cell=im.crop((frame%4*cw,frame//4*ch,(frame%4+1)*cw,(frame//4+1)*ch))
    return cell.crop(cell.getbbox())

def image(c,im,x,y,w,h):
    im=im.copy();im.thumbnail((max(1,int(w*2.5)),max(1,int(h*2.5))),Image.Resampling.LANCZOS)
    ratio=min(w/im.width,h/im.height);iw,ih=im.width*ratio,im.height*ratio
    c.drawImage(ImageReader(im),x+(w-iw)/2,y+(h-ih)/2,iw,ih,mask='auto')

def text(c,s,x,y,size=12,color=INK,bold=False):
    c.setFillColor(color); c.setFont('CNB' if bold else 'CN',size); c.drawString(x,y,str(s))

def para(c,s,x,y,width,size=12,leading=20,color=INK):
    line=''
    for char in s:
        if char=='\n' or pdfmetrics.stringWidth(line+char,'CN',size)>width:
            text(c,line,x,y,size,color);y-=leading;line='' if char=='\n' else char
        else:line+=char
    if line:text(c,line,x,y,size,color);y-=leading
    return y

def base(c,page,label):
    c.setFillColor(PAPER);c.rect(0,0,W,H,fill=1,stroke=0)
    c.setStrokeColor('#cdd9d5');c.line(30,43,930,43)
    text(c,'CAS / 群星协议 / 战术人格档案',30,25,9,MUTED)
    text(c,'2026.11.14  ·  当前项目快照',675,25,9,MUTED)
    text(c,f'{page:02}',911,25,10,TEAL,True)
    c.bookmarkPage(label)

def cap(u,p):
    a=p['company_layout'];return f"{a['company_count']}连 × {a['personnel_per_company']}具 = {a['total_personnel']}具身体"

def specialty(p):
    s=p['brief'];return s.split('；',1)[-1]

pdf=OUT/'CAS-20战术部队图鉴.pdf'
c=canvas.Canvas(str(pdf),pagesize=(W,H));c.setTitle('CAS 二十战术部队图鉴');c.setAuthor('CAS 项目档案')
base(c,1,'cover')
text(c,'群星协议',34,613,20,TEAL,True);text(c,'20 位战术人格',32,559,43,INK,True)
text(c,'本人立绘 / 现有小人 / 兵种特点 / 北约风格兵牌 / 编制设定',34,525,15,MUTED)
for i,u in enumerate(units):
    x=34+(i%10)*90;y=302-(i//10)*153
    image(c,portrait(u),x,y,80,140);text(c,u['name'],x+20,y-16,11,INK,True)
para(c,'一个 MCP 是一位人格。她可以同时操作多个女性化机器人身体；车辆与旋翼机属于装备。全编制上限、实际行动连和当前拥有身体数量是不同概念。',34,111,875,12,19)
text(c,'来源：tactical-units-v1.json / tactical-profiles-v4.json（company_layout）/ tactical_type_token.gd / tactical_formation_mark.gd',34,60,8,MUTED)
c.showPage()
for batch in range(2):
    base(c,2+batch,'index'+str(batch));text(c,'编制速查',32,615,28,INK,True)
    text(c,'父编制军牌保留原番号；行动连人数采用 v4 的 multi-company-v1 表。',34,584,12,MUTED)
    for i,label in enumerate(['人格 / 番号','专长','全编制上限','本次多连配置','SD 状态']):text(c,label,[34,340,465,585,810][i],548,11,TEAL,True)
    for j,u in enumerate(units[batch*10:batch*10+10]):
        p=profiles[u['id']];y=508-j*40
        text(c,u['id']+' '+u['name'],34,y,12,INK,True);text(c,u['designation'],34,y-16,10,MUTED)
        text(c,p['role_label'],340,y,11);text(c,f"{u['personnel_cap']:,}具",465,y,11)
        text(c,cap(u,p),585,y,10);text(c,'独立SD' if u.get('sprite_sheet') else '本人肖像回退',810,y,10)
        c.linkRect('',u['id'],(30,y-19,930,y+15),relative=0,thickness=0)
    para(c,'兵牌读法：X 旅 / XX 师 / III 团 / II 营 / I 连。群、队、处、司令部等未登记层级的番号保持无上标，不猜测等同旅或师。符号按项目现用组件转绘，属于 NATO 风格游戏兵牌。',34,83,890,10,15,MUTED)
    c.showPage()

records=[]
for idx,u in enumerate(units):
    p=profiles[u['id']];a=p['company_layout'];mark,level=echelon(u)
    base(c,idx+4,u['id']);c.addOutlineEntry(u['name']+' / '+u['id'],u['id'],0)
    text(c,f"{u['id']}   /   {u['rarity']}",34,621,14,TEAL,True)
    text(c,u['name'],32,567,40,INK,True);text(c,u['designation'],35,537,18)
    c.setFillColor('#e7ece6');c.roundRect(30,78,335,438,18,fill=1,stroke=0)
    image(c,portrait(u),38,84,319,425)
    text(c,'本人完整立绘',136,61,10,MUTED)
    image(c,token(u),770,421,145,122)
    text(c,p['role_label'],784,407,12,TEAL,True)
    text(c,(mark+' / '+level) if mark else '层级未登记',784,389,10,MUTED)
    sp=sprite(u)
    if sp:
        image(c,sp,407,391,126,139)
        image(c,sprite(u,3),541,407,85,107);image(c,sprite(u,7),638,407,85,107)
        text(c,'独立SD · 待机 / 行走 / 开火',414,375,10,MUTED)
    else:
        image(c,portrait(u),417,401,100,122)
        text(c,'当前小人位：本人肖像回退',539,471,12,TEAL,True)
        para(c,'尚无独立两头身SD动作图；此处展示本人立绘缩影，未冒充已完成的小人。',539,446,208,10,17,MUTED)
    y=344
    for title,s in [
        ('作战特点',u['description']),
        ('当前能力',specialty(p)),
        ('战术技能',f"{p['ability']['name']} · {p['ability']['charges']}次 · 冷却{p['ability']['cooldown']:g}秒"),
        ('默认载具',p['vehicle_name']),
        ('编制设定',f"协议全编制上限 {u['personnel_cap']:,} 具；本次 {cap(u,p)}。"),
        ('人格侧写',u['personality'])]:
        text(c,title,398,y,11,TEAL,True);y=para(c,s,473,y,447,12,19)-13
    para(c,'行动连为本次先遣编组，每连独立指挥、搭载与结算伤亡；人数不是现实满员连。上限不代表现有库存或免费增援。',398,95,520,10,16,MUTED)
    c.showPage()
    records.append({'id':u['id'],'name':u['name'],'designation':u['designation'],'cap':u['personnel_cap'],'layout':a,'sd':bool(sp),'page':idx+4})
c.save()

# Render every page for visual QA and produce a portable browser edition.
doc=fitz.open(pdf); rendered=[]
for i,page in enumerate(doc):
    pix=page.get_pixmap(matrix=fitz.Matrix(1.4,1.4),alpha=False)
    path=TMP/f'page-{i+1:02}.png';pix.save(path);rendered.append(path)
def data_image(im,maxsize=(620,780)):
    im=im.copy();im.thumbnail(maxsize,Image.Resampling.LANCZOS);b=io.BytesIO();im.save(b,format='PNG');return 'data:image/png;base64,'+base64.b64encode(b.getvalue()).decode()
cards=[]
for u in units:
    p=profiles[u['id']];sp=sprite(u);mark,level=echelon(u)
    cards.append(f'''<article id="{u['id']}" data-search="{html.escape(u['id']+u['name']+u['designation']+p['role_label'])}">
    <header><small>{u['id']} / {u['rarity']}</small><h2>{u['name']}</h2><p>{u['designation']}</p></header>
    <div class="body"><img class="portrait" alt="{u['name']}本人立绘" src="{data_image(portrait(u))}"><div class="details">
    <div class="figures"><figure><img src="{data_image(sp if sp else portrait(u),(230,230))}" alt="{'本人独立SD' if sp else '本人肖像回退'}"><figcaption>{'本人独立SD' if sp else '本人肖像回退 · 独立SD待补'}</figcaption></figure>
    <figure><img src="{data_image(token(u))}" alt="{p['role_label']}兵牌"><figcaption>{p['role_label']} · {mark+' '+level if mark else '层级未登记'}</figcaption></figure></div>
    <dl><dt>作战特点</dt><dd>{u['description']}</dd><dt>当前能力</dt><dd>{specialty(p)}</dd>
    <dt>战术技能</dt><dd>{p['ability']['name']} / {p['ability']['charges']}次 / 冷却{p['ability']['cooldown']:g}秒</dd>
    <dt>默认载具</dt><dd>{p['vehicle_name']}</dd><dt>协议上限</dt><dd>{u['personnel_cap']:,}具身体</dd>
    <dt>行动编制</dt><dd>{cap(u,p)}</dd><dt>人格侧写</dt><dd>{u['personality']}</dd></dl></div></div></article>''')
style='''*{box-sizing:border-box}body{margin:0;background:#f6f3eb;color:#193d48;font:16px/1.7 "Microsoft YaHei",sans-serif}main{max-width:1100px;margin:auto;padding:36px 22px}h1{font-size:48px;margin:8px 0}h2{font-size:36px;margin:0}small,dt{color:#287d80;font-weight:bold}nav{display:flex;gap:8px;flex-wrap:wrap;margin:20px 0}a{color:#287d80;text-decoration:none;padding:4px 9px;border:1px solid #b7cfcb;border-radius:4px}input{font:inherit;padding:12px;width:100%;border:1px solid #9cbcb8;border-radius:8px;background:white}article{background:#fffdf8;border:1px solid #d5dfd9;border-radius:20px;margin:28px 0;padding:28px;break-inside:avoid}header p{margin-top:0}.body{display:grid;grid-template-columns:36% 1fr;gap:30px}.portrait{width:100%;height:530px;object-fit:contain;background:#e7ece6;border-radius:15px}.figures{display:flex;justify-content:space-around;text-align:center}figure{margin:0}figure img{height:145px;width:170px;object-fit:contain}figcaption{font-size:12px;color:#647b81}dl{display:grid;grid-template-columns:80px 1fr;gap:11px 12px;font-size:15px}dd{margin:0}footer{font-size:13px;color:#647b81;padding:20px 0} @media(max-width:700px){h1{font-size:32px}.body{grid-template-columns:1fr}.portrait{height:420px}article{padding:18px}.figures img{width:130px}dl{grid-template-columns:70px 1fr}} @media print{nav,input{display:none}article{break-before:page}}'''
htmlfile=OUT/'CAS-20战术部队图鉴.html'
htmlfile.write_text('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>CAS 二十战术部队图鉴</title><style>'+style+'</style><main><small>CAS / 2026.11.14 / 当前项目快照</small><h1>20 位战术人格</h1><p>本人立绘 · 现有小人 · 作战特点 · 北约风格兵牌 · 编制设定</p><p>一个 MCP 是一位人格，多个女性化身体共享同一意识。全编制上限不是当前库存或免费增援；本次出动按独立先遣行动连登记。</p><p>当前共有20张立绘、5套独立SD。其余15名使用本人肖像回退。军牌：X旅 / XX师 / III团 / II营 / I连；未登记层级的番号不推定级别。符号采用项目现用NATO风格，不宣称标准认证。</p><nav>'+''.join(f'<a href="#{u["id"]}">{u["name"]}</a>' for u in units)+'</nav><input id="search" placeholder="搜索人格名、MCP编号、番号或专长" aria-label="搜索战术部队">'+''.join(cards)+'<footer>来源：tactical-units-v1.json（身份/美术/协议上限）；tactical-profiles-v4.json 的 company_layout（多连人数/技能/默认载具）；tactical_type_token.gd、tactical_formation_mark.gd（现用符号与层级）。旧brief里的单连人数不作为新版编制。原始图片、引擎与账户均未修改。</footer></main><script>document.querySelector("#search").addEventListener("input",e=>{let q=e.target.value.trim().toLowerCase();document.querySelectorAll("article").forEach(a=>a.hidden=!a.dataset.search.toLowerCase().includes(q))})</script></html>',encoding='utf-8')

# A single image for a quick visual overview, using original registered art.
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20); bold=ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc',25)
overview=Image.new('RGB',(1800,1650),PAPER);draw=ImageDraw.Draw(overview)
draw.text((35,20),'群星协议 · 20位战术人格',font=ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc',44),fill=INK)
draw.text((37,85),'现有立绘 / 本人SD或肖像回退 / 现用兵牌 / v4行动编制 · 2026.11.14',font=font,fill=MUTED)
for i,u in enumerate(units):
    x=25+i%5*355;y=140+i//5*370;p=profiles[u['id']]
    draw.rounded_rectangle((x,y,x+335,y+350),radius=12,fill='#fffdf8')
    im=portrait(u);im.thumbnail((170,245));overview.paste(im,(x+10+(170-im.width)//2,y+12+(245-im.height)//2),im)
    ico=token(u);ico.thumbnail((130,105));overview.paste(ico,(x+190,y+24),ico)
    sp=sprite(u)
    if sp:sp.thumbnail((105,105));overview.paste(sp,(x+200,y+132),sp)
    else:draw.text((x+186,y+155),'本人肖像回退',font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',16),fill=MUTED)
    draw.text((x+15,y+263),u['id']+' '+u['name'],font=bold,fill=INK)
    draw.text((x+15,y+300),p['role_label']+' / '+cap(u,p).replace('具身体','人'),font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',17),fill=TEAL)
overview.save(OUT/'CAS-20战术部队总览.png')

# Verify the complete roster and all page text, not just file creation.
assert len(units)==20 and len(profiles)==20 and len(doc)==23
for r in records:
    txt=doc[r['page']-1].get_text();assert r['id'] in txt and r['name'] in txt
    assert r['layout']['total_personnel']==r['layout']['company_count']*r['layout']['personnel_per_company']
assert sum(r['sd'] for r in records)==5
sources=['godot/data/tactical-units-v1.json','godot/data/tactical-profiles-v4.json','godot/scripts/tactical_type_token.gd','godot/scripts/tactical_formation_mark.gd']
receipt={'date':'2026-11-14','pages':len(doc),'portraits':20,'independent_sd':5,'portrait_fallbacks':15,'records':records,'sources':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in sources},'outputs':[pdf.name,htmlfile.name,'CAS-20战术部队总览.png'],'all_pages_rendered':True}
(OUT/'verification.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'pages':len(doc),'output':str(OUT),'pdf_bytes':pdf.stat().st_size,'html_bytes':htmlfile.stat().st_size},ensure_ascii=False))
