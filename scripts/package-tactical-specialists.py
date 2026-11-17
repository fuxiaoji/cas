import json, hashlib, shutil, html, zipfile
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[1]
TAG='tactical-specialists-20261116'
OUT=ROOT/'output'/TAG
ART=ROOT/'docs/art'/TAG
ASSETS=ROOT/'godot/assets/tactical'/TAG
for p in (OUT/'images',ART/'references',ASSETS): p.mkdir(parents=True,exist_ok=True)
def dump(p,v): p.write_text(json.dumps(v,ensure_ascii=False,indent=2),encoding='utf-8')
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()

# All numbers are ORIGINAL DESIGN in the frozen v4 accelerated comparison scale.
# This file is deliberately not a runtime catalogue or import script.
weapons={}
def weapon(id,name,damage,reach,burst,gap,pause,mag,total,reload,accuracy,movement=.65,mults=None):
    weapons[id]=dict(id=id,name=name,damage=damage,max_range_m=reach,burst=burst,shot_gap_s=gap,burst_gap_s=pause,magazine=mag,total_including_magazine=total,reload_s=reload,accuracy_anchors=accuracy,moving_accuracy_multiplier=movement,target_multipliers=mults or dict(personnel=1,light_vehicle=.08,heavy_vehicle=.015,structure=.06,aircraft=.02),ammo_per_projectile=1)
weapon('N311','N311海勤卡宾枪',9,650,1,.1,.7,12,96,2.4,[[0,.8],[180,.82],[400,.6],[650,.22]])
weapon('S312','S312鼓匣冲锋枪',5,430,4,.1,.5,32,192,3,[[0,.88],[100,.85],[250,.52],[430,.12]])
weapon('C313','C313警戒卡宾枪',7,600,2,.2,.9,16,96,2.6,[[0,.75],[160,.78],[350,.54],[600,.18]])
weapon('A313','A313单发反器材枪',72,1300,1,.1,0,1,18,4.8,[[0,.35],[250,.78],[700,.7],[1300,.25]],0,dict(personnel=.65,light_vehicle=1.35,heavy_vehicle=.12,structure=.5,aircraft=.02))
weapon('P314','P314观测员手枪',6,220,1,.1,.6,10,40,2,[[0,.8],[80,.72],[220,.18]])
weapon('C314','C314轻便卡宾枪',7,620,1,.1,.8,10,70,2.5,[[0,.75],[180,.8],[400,.5],[620,.18]])
weapon('G315','G315水冷机枪',6,1150,8,.1,.6,80,400,6,[[0,.68],[200,.82],[650,.58],[1150,.2]],0,dict(personnel=1,light_vehicle=.12,heavy_vehicle=.02,structure=.08,aircraft=.02))
weapon('P315','P315机枪手副枪',6,200,1,.1,.6,10,50,2,[[0,.78],[80,.68],[200,.18]])
weapon('C316','C316撤运短卡宾枪',7,550,1,.1,.9,10,60,2.6,[[0,.76],[150,.75],[350,.45],[550,.16]])

units=[]
def unit(n,name,designation,companies,count,hp,armor,speed,vision,loadout,role,counter,skill,passive,refs):
    units.append(dict(id=f'MCP-{n}',name=name,designation=designation,company_count=companies,bodies_per_company=count,total_bodies=companies*count,body_stats=dict(baseline_hp=hp/4,health_scale=4,hp=hp,personnel_damage_multiplier=armor,speed_m_s=speed,vision_m=vision),loadout=loadout,transport=dict(kind='ordinary_landing_craft',per_company=1,personnel_capacity=count,rule='复用当前已发布普通艇数据；合法沙岸卸载；船体与身体独立；不因立绘绳索获得登舰功能'),role=role,counters=counter,active=skill,passive=passive,reference_images=refs))

unit(311,'汐缆','第311登舰夺控营',3,6,400,.9,78,1350,{'N311':6},'短通路登舰、夺控设备，适合有限步兵位的港口任务','反重甲弱；登临单列暴露；普通陆战火力低于主力团',dict(name='搭缆登临',charges_per_company=2,cooldown_s=35,range_m=45,description='仅本席已发现、登记为可登临且相对速度≤2米/秒的友军或任务目标船，最近可达船边到合法甲板锚点≤45米且高差≤8米。3秒设缆，逐身体沿真实绳路以3米/秒攀行，单绳只容1身体，末端2秒翻越。每次连接耗1绳索额度，保留到双方脱离或取消；拒绝非法路径不扣，设缆完成即扣。不可跨岛悬崖、普通建筑或历史舰；不改海战舰HP或自动夺船。途中不能开火；目标移速/距离失格则在当前合法点暂停并优先沿绳撤回，不能瞬移。无甲板/攀行/中断消费者时整项阻断。'),dict(name='设备夺控',description='仅本人身体在任务设备交互半径内且有真实交互通路时，任务定义的夺控累计速率×1.25；同设备只取最高倍率，不与多人倍率重复计算。不增加遗迹收益、不减少战斗占点所需敌情条件。'),[1,10,12])
unit(312,'雾芥','第312烟幕突击营',3,8,420,.82,72,1200,{'S312':8},'遮断长射线，协助友军穿越滩头空地','冲锋枪远距弱；烟中自己也看不见；范围炮火不被烟减伤',dict(name='折线烟幕',charges_per_company=4,cooldown_s=24,range_m=280,radius_m=55,duration_s=14,description='每次向合法落点投1烟罐，投掷准备0.8秒、飞行1秒、1.5秒成烟；出手扣1技能额度。烟半径55米、高12米；取真实视线段与烟体相交长度≥12米时阻断双方光学发现与新的直射锁定。已有弹丸继续飞行，间射不减伤，不能清除敌人最后已知点。重叠取并集、不得叠减伤；按共享风矢量漂移，无风静止。无烟体视线消费者时禁用，不能只画烟。'),dict(name='突击互护',description='普通移动中不额外加速或减伤；AI只从本席公开观察选择烟后可达掩体，烟内不透视索敌。特色来自烟路与短枪，而非无条件属性光环。'),[3,8,9])
unit(313,'砾隼','第313反器材猎兵营',2,6,340,.98,70,1650,{'A313':2,'C313':4},'远距离伏击轻装甲和外露武器设施','重坦正面几乎无效；每连仅2重枪，移动与近距脆弱',dict(name='稳固伏击',charges_per_company=None,cooldown_s=12,duration_s=10,description='切换架枪姿态，A313手需停稳2.5秒且有合法地面；接下来最多10秒静止射击精度×1.18，上限0.9，转动射界正前±35度。每枪仍消耗1普通枪弹、正常装填，无免费技能弹。移动/压制/主动转向取消；持续结束后12秒才能重启；无命中或伤害保证。'),dict(name='轻甲破坏',description='A313使用人员/轻车/重车/工事0.65/1.35/0.12/0.5的独立倍率，先算基础伤害×目标倍率再算目标防护；不穿透两目标，不附加熄火或乘员即死。A313普通架设1.8秒、收枪1.2秒，移动禁射；稳定技能准备替代普通架设而非叠加。'),[2,4,15])
unit(314,'灯穗','第314光学观测连队',2,6,300,1,90,1900,{'P314':2,'C314':4},'在高地用光学器材延伸可靠观察，帮助指挥判断路线','火力与耐久低；受烟/山体遮挡；不提供免费舰炮或雷达全图透视',dict(name='定向观测',charges_per_company=None,cooldown_s=8,range_m=2400,duration_s=12,description='2名P314观测员可各架1组光学镜但共用连指令；3秒架设，在指定±25度扇区连续观察12秒，范围2400米，仍逐射线检查地形/建筑/植被与烟。只延长本席探测，不提升武器射程、伤害或舰炮命中。移动/压制/收镜即中断并进入8秒冷却，取消前未架好不耗冷却。已失视目标仅保留5秒带时间戳的最后已知位置，不跟踪真态。'),dict(name='观测接力',description='无线电仅传递本席已观察接触，不能复原被遮挡目标。AI优先已有可达高地，不能凭装备赋予攀崖；不替代128有限舰炮航空标记。'),[7,14])
unit(315,'铎垒','第315装甲机枪营',2,8,480,.72,56,1350,{'G315':2,'C313':6},'架枪控制通道与防守展开面','沉重，转移慢；两机枪弹药有限，侧后与迫击炮反制',dict(name='扇区封锁',charges_per_company=None,cooldown_s=8,duration_s=12,description='本连两机枪架设3秒，选定120度扇区，最多12秒仅在扇区内按真实命中曲线与有限弹药射击。有效压制定义为同一目标3秒内实际命中≥3发，则目标下次射击时间推迟0.8秒；同一目标4秒内最多触发1次，对车/塔无效。每发扣普通弹，不扣虚构技能库存，不穿墙。移动/压制/改向取消；收枪2秒；冷却8秒从结束计。'),dict(name='定置支撑',description='普通G315也必须架设3秒、收枪2秒，移动禁射，机枪手携P315各1把且不能同时开火。护甲仅×0.72人员承伤，不视为车辆或盾牌；不额外方向免疫。'),[11,13])
unit(316,'栖禾','第316战地撤运营',3,6,360,.94,82,1300,{'C316':6},'维持后撤通路、把尚存活重伤身体送回艇位','两人担架组不能射击；搬运慢、额外占舱；不复活、不补血',dict(name='担架撤运',charges_per_company=None,cooldown_s=0,range_m=12,description='每连最多2副担架，每副占本人2名搬运身体；只选本席已知、HP>0且≤自身最大HP25%的友军人员。两搬运员到目标12米内准备3秒，目标停止射击/自行移动，位置由真实担架锚点连续更新，以36米/秒沿合法地面通路撤运。三身体都有独立HP与碰撞，搬运不提供无敌或减伤；任一搬运员倒下原地放下，另一人不得瞬移回队。不搬运坐骑/车辆。治疗超过25%后可原地放下；死亡记死亡不能登艇冒充回收。艇上按三真实身体占3位，患者仍归原unit/company，结算只计一次，身体与担架/载舰状态随存读保留。'),dict(name='撤离分工',description='托管先找可达安全会合点与真实空艇位，再指派担架组，其余两名警戒。没有可达路线/空位则给公开原因等待；不免费生成艇或突破普通艇岸型。不同于052的生命恢复和116保障增益；本单位只改变运输状态。'),[5,6,9,12,15])

units[4]['secondary_loadout']={'primary_weapon':'G315','secondary_weapon':'P315','bodies_per_company':2}
design=dict(version='tactical-specialists-design-v1',status='design_only_not_runtime',date='2026-11-16',scale='旧v4加速陆战比较尺度；HP沿用基准×4；速度与射程不是现实军事数据。720m新海岸需要全兵种统一重定标，禁止将本表直接导入。',common=dict(consciousness='每MCP全部女性身体属于同一成年人格；不同岗位不额外增员',time='10Hz，0.1秒粒度；组间隔从末发至下一组首发，空匣换弹替代组间隔。副武器独立。',accuracy='锚点线性插值，射程外0，静止无掩体同高地基准；移动乘武器系数，实际仍算遮挡/高差/护具。',inventory='总弹含首匣；无召回补弹或取消装填复制；每实际发射扣1；技能次数在明确提交点扣；双方同身份对称。',transport='普通艇复用已发布原核数据；容量按真实身体守恒；无额外战斗车/马/飞机。'),weapons=list(weapons.values()),units=units,blockers=['未写原核目录、招募、账户、教学或战斗代码','连续登临甲板锚点/绳路/动态中断与死亡处理','三维烟体视线与风场及双方对称','持续光学扇区与公开接触时间戳','压制去重与枪械架设/转向/存读','跨连患者归属/担架碰撞/艇位/回收结算','新720m地理全兵种统一速度、射程、战斗时长预算','具体枪型图与岗位动作SD未生成；立绘代表主岗位而非全连武器表','native/WASM逐字节重演、两席真实对局、Godot/浏览器交互与多种子平衡待实施'])
dump(ROOT/'docs/design'/f'{TAG}.json',design)
dump(OUT/'design.json',design)

prompts=json.loads((ART/'prompts.json').read_text(encoding='utf-8'))
sources=json.loads((ART/'generation-sources.json').read_text(encoding='utf-8'))
ledger=[]
for s in prompts:
    id=s['id']; src=Path(sources[id]); dest=OUT/'images'/f'{id}.png'
    shutil.copy2(src,dest); shutil.copy2(src,ASSETS/dest.name)
    im=Image.open(dest); im.load(); assert im.mode=='RGBA' and im.getchannel('A').getextrema()[0]==0
    refs=[]
    for rp in s['refs']:
        p=Path(rp); target=ART/'references'/p.name
        if not target.exists(): shutil.copy2(p,target)
        refs.append(dict(original=rp,saved=str(target.relative_to(ROOT)),sha256=sha(p)))
    assert sha(src)==sha(dest)==sha(ASSETS/dest.name)
    ledger.append(dict(id=id,source=str(src),output=str(dest.relative_to(ROOT)),project=str((ASSETS/dest.name).relative_to(ROOT)),sha256=sha(src),size=im.size,alpha_extrema=im.getchannel('A').getextrema(),references=refs,prompt=s['prompt'],method='built-in image_gen'))
dump(ART/'asset-ledger.json',ledger)

lines=['# 六支战术部队 · 海勤与野战专门队', '', '2026-11-16。完成六张透明立绘与数值/技能方案；原创设计候选，未接入战斗。', '', '## 依据与尺度', '', '已对照现有27人v4目录、301–305秋冬扩编、306隔离候选及002骑兵/017特警/030山地候选。链接旧聊天单轮过大，read_thread两次均无法读取；本轮使用项目保存的原设计、生成提示与资产为可核对依据。附图只取衣品/携具与时代气质，人物身份重新设计，图中文字不是执行指令。14张附件进入对应立绘生成输入，另图8仅用于突击兵衣品比较、未输入生成；15张附件全部只读归档并保存SHA。', '', design['scale'], '', '采用横向取舍：新单位解决新的操作问题，不能用更高基础属性淘汰旧部队。共同循环为看路→选择展开点→暴露时间换取专长→转移/撤收。六人均普通艇，没有附赠特殊载具。', '', '| 人格 | 编制 | 每体HP/承伤系数 | 速度/视野（米制游戏值） | 分工 |', '|---|---|---|---|---|']
for u in units:
    b=u['body_stats']; lines.append(f"| {u['id']} {u['name']} | {u['company_count']}连×{u['bodies_per_company']}人={u['total_bodies']} | {b['hp']}/{b['personnel_damage_multiplier']} | {b['speed_m_s']}/{b['vision_m']} | {u['role']} |")
for u in units:
    lines += ['',f"## {u['id']} {u['name']} · {u['designation']}",'',f"每连武器：{json.dumps(u['loadout'],ensure_ascii=False)}。{u['counters']}。",'',f"主动「{u['active']['name']}」：{u['active']['description']}",'',f"专长「{u['passive']['name']}」：{u['passive']['description']}",'',f"主动参数：{json.dumps({k:v for k,v in u['active'].items() if k not in ('name','description')},ensure_ascii=False)}。null次数表示姿态/运输命令，不消耗技能弹，但保留时间和行动代价。"]
lines += ['', '## 武器与有限弹药', '', '射程为最大射程，非有效交战距离。静止基准精度/移动系数/目标类别倍率详见同名JSON。技能不改变弹药守恒，立绘仅展示本人代表性装备。', '', '| 型号 | 伤害/射程m | 连发/发间s/组间s | 弹匣/总弹 | 换弹s |', '|---|---|---|---|---|']
for w in weapons.values(): lines.append(f"| {w['id']} {w['name']} | {w['damage']}/{w['max_range_m']} | {w['burst']}/{w['shot_gap_s']}/{w['burst_gap_s']} | {w['magazine']}/{w['total_including_magazine']} | {w['reload_s']} |")
lines += ['', 'G315两名机枪手每人另携P315（10/50弹）；其余专职反器材枪手本轮无副枪，近距保护由卡宾手承担。每次射击只用当时持用的一把武器。', '', '## 差异与反制', '', '311对比017：绳路与设备交互，不带盾/闪光。312对比184/009：烟遮双向视线，无爆破/伤害手雷。313对比反坦克筒与狙击：高射程低频、偏轻甲，不能替代重反坦克。314对比128：主动观察，不授予舰炮航空库存。315对比302/压制单位：固定扇区与逐发命中触发，小人数慢转移。316对比052/116：真实撤运而非治疗/补给。不会免费增加胜利奖励。', '', '## 后续验收门与未实现项', '']+['- '+b for b in design['blockers']]
lines += ['', '不得按立绘宣称具备运行能力；本轮不做原生/WASM实战声明。历史CAS表值、舰队阵位、原PDF、参考项目、已发布核心、账号与旧资产均未修改。']
text='\n'.join(lines)+'\n'
(ROOT/'docs/design'/f'{TAG}.md').write_text(text,encoding='utf-8'); (OUT/'设计说明.md').write_text(text,encoding='utf-8')

font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',24)
board=Image.new('RGB',(1800,650),'#edf0ed'); draw=ImageDraw.Draw(board)
cards=[]
for i,u in enumerate(units):
    im=Image.open(OUT/'images'/f"{u['id']}.png"); im.thumbnail((280,900))
    x=i*300+(300-im.width)//2; board.paste(im,(x,55),im)
    draw.text((i*300+18,530),u['id']+' '+u['name'],font=font,fill='#243a40')
    draw.text((i*300+18,570),u['designation'],font=font,fill='#243a40')
    b=u['body_stats']
    cards.append(f'''<article><a href="images/{u['id']}.png"><img src="images/{u['id']}.png" alt="{u['name']}全身立绘"></a><div><small>{u['id']}</small><h2>{u['name']} · {u['designation']}</h2><p>{u['company_count']}连 × {u['bodies_per_company']}身体 · HP {b['hp']} · 承伤×{b['personnel_damage_multiplier']}</p><p>{html.escape(u['role'])}</p><p><b>{u['active']['name']}</b>：{html.escape(u['active']['description'])}</p><p><b>{u['passive']['name']}</b>：{html.escape(u['passive']['description'])}</p><p class="weak">代价：{html.escape(u['counters'])}</p><a download href="images/{u['id']}.png">下载透明原图</a></div></article>''')
board.save(OUT/'overview.jpg',quality=93)
page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>海勤与野战专门队 · CAS</title><style>*{box-sizing:border-box}body{margin:0;background:#eff0e9;color:#233c40;font:16px/1.75 "Microsoft YaHei",sans-serif}header,main{max-width:1250px;margin:auto;padding:28px}h1{font-size:36px;line-height:1.25}a{color:#176d76}article{display:grid;grid-template-columns:minmax(180px,36%) 1fr;gap:28px;margin:25px 0;padding:24px;background:#fffdf7;border:1px solid #d1d8cb;border-radius:14px}article img{width:100%;max-height:660px;object-fit:contain;background:#dfe5df}small{letter-spacing:3px}.weak{color:#795235}nav{display:flex;flex-wrap:wrap;gap:20px}.notice{padding:16px;background:#dce7df}h2{margin-top:0}@media(max-width:650px){header,main{padding:16px}article{grid-template-columns:1fr;padding:16px;gap:15px}article img{height:460px}h1{font-size:28px}}</style><header><small>CAS / ORIGINAL TACTICAL DESIGN / 2026.11.16</small><h1>海勤与野战专门队</h1><p>六个新的战术分工，六张独立全身立绘。</p><p class="notice">设计候选 · 未接入游戏。数值沿用旧v4加速比较尺度；新720m海岸须全兵种统一重定标。立绘与技能设计不代表实战功能已实现。</p><nav><a href="设计说明.md">完整数值与技能说明</a><a href="design.json" download>下载结构化方案</a><a href="overview.jpg">六人总览</a></nav></header><main>'''+''.join(cards)+'''</main></html>'''
(OUT/'index.html').write_text(page,encoding='utf-8')

checks=[]
assert len({u['id'] for u in units})==6
for u in units:
    assert sum(u['loadout'].values())==u['bodies_per_company']
    assert u['total_bodies']==u['company_count']*u['bodies_per_company']
    assert u['body_stats']['hp']==u['body_stats']['baseline_hp']*4
    assert all(k in weapons for k in u['loadout'])
    checks.append(u['id']+' 编制、HP、枪型、透明PNG与源SHA通过')
for w in weapons.values():
    assert w['total_including_magazine']>=w['magazine']>0
    assert all(0<=p<=1 for _,p in w['accuracy_anchors'])
    assert all(a[0]<b[0] for a,b in zip(w['accuracy_anchors'],w['accuracy_anchors'][1:]))
dump(OUT/'validation.json',dict(checks=checks,weapons=len(weapons),runtime_tested=False,notes='图像逐张目检另记；静态图册无战斗功能，不称原核验收'))
with zipfile.ZipFile(ROOT/'output'/f'{TAG}.zip','w',zipfile.ZIP_DEFLATED) as z:
    for p in OUT.rglob('*'):
        if p.is_file(): z.write(p,p.relative_to(OUT))
with zipfile.ZipFile(ROOT/'output'/f'{TAG}.zip') as z: assert z.testzip() is None
print(json.dumps(dict(output=str(OUT),assets=len(ledger),checks=checks),ensure_ascii=False))
