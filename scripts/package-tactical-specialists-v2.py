from pathlib import Path
import json,hashlib,shutil,zipfile,html
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]; TAG='tactical-specialists-v2-20261116'
ART=ROOT/'docs/art'/TAG; OUT=ROOT/'output'/TAG; PROJECT=ROOT/'godot/assets/tactical'/TAG
for p in (ART/'references',OUT/'images',PROJECT):p.mkdir(parents=True,exist_ok=True)
def dump(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2),encoding='utf-8')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
design=json.loads((ROOT/'docs/design/tactical-specialists-20261116.json').read_text(encoding='utf-8'))
design['version']='tactical-specialists-design-v2'; design['revision']='311–316仅外观修订，六人旧数值技能不变；新增317–319。全部设计候选。'
weapons=design['weapons']
def gun(id,name,damage,reach,burst,gap,pause,mag,total,reload,anchors,moving=.65,mults=None):
    w=dict(id=id,name=name,damage=damage,max_range_m=reach,burst=burst,shot_gap_s=gap,burst_gap_s=pause,magazine=mag,total_including_magazine=total,reload_s=reload,accuracy_anchors=anchors,moving_accuracy_multiplier=moving,target_multipliers=mults or dict(personnel=1,light_vehicle=.08,heavy_vehicle=.015,structure=.06,aircraft=.02),ammo_per_projectile=1);weapons.append(w)
gun('L317','L317短联络步枪',10,760,1,.1,1.1,8,64,2.8,[[0,.7],[200,.83],[450,.65],[760,.24]])
gun('R318','R318骑兵卡宾枪',8,700,2,.2,.9,12,84,2.8,[[0,.74],[180,.8],[420,.57],[700,.18]],.45)
gun('P319','P319突袭左轮',18,320,1,.1,.8,6,48,3,[[0,.88],[80,.82],[180,.58],[320,.15]])
gun('C319','C319短突击枪',5.5,450,3,.1,.6,24,144,2.7,[[0,.85],[120,.81],[280,.48],[450,.14]])
gun('M319','M319壕沟短锤',46,10,1,.1,1.4,1,1,0,[[0,1],[10,1]],0,dict(personnel=1,light_vehicle=.03,heavy_vehicle=.01,structure=.02,aircraft=0))
weapons[-1]['ammo_mode']='melee_no_ammo';weapons[-1]['ammo_per_projectile']=0
def unit(id,name,title,companies,count,hp,armor,speed,vision,loadout,role,counters,active,passive):
    return dict(id=id,name=name,designation=title,company_count=companies,bodies_per_company=count,total_bodies=companies*count,body_stats=dict(baseline_hp=hp/4,health_scale=4,hp=hp,personnel_damage_multiplier=armor,speed_m_s=speed,vision_m=vision),loadout=loadout,role=role,counters=counters,active=active,passive=passive,transport=dict(kind='ordinary_landing_craft',per_company=1,personnel_capacity=count,rule='复用普通艇真实数据、合法岸段和既有身体容量；不增加免费人员或库存'))
u=unit('MCP-317','褐燕','第317潜入联络营',2,6,320,.98,88,1550,{'L317':6},'沿视线死角接近通信设施，短时切断局部联络','人数少、正面火力低；潜行降低速度且不降低光学可见度；切断不影响敌方本地射击',dict(name='切断联络',charges_per_company=2,cooldown_s=40,range_m=8,duration_s=16,description='本人1身体必须实际到已发现且登记为可交互的敌通信设备8米内，有交互通路，连续操作4秒。完成时扣1工具额度，使该设备的联络输出暂停16秒；仅阻止依赖该设备的跨队接触共享和新的支援请求。敌方本地视觉、武器、既有命令和已发射炮弹照常；没有通信依赖图时禁用，不以全图沉默代替。操作受击/移动中断，完成前不扣；完成后退出不退工具，不可叠加时长，同设备再次成功只取较晚到期时刻。'),dict(name='低声潜行',description='切换潜行时步速×0.55，仅脚步声发现半径×0.5；视线、光照、植被等真实光学发现规则不变。开火/操作设备恢复正常声源，2秒后才可重新潜行；不隐身、不穿墙、不窥读敌真态。未实现声学探测前此模式阻断。'))
u['rifle_grenade']=dict(operators_per_company=1,total_grenades_per_company=3,base_damage=65,range_min_m=100,range_max_m=850,radius_m=12,scatter_radius_m=[10,30],prepare_s=2,reload_s=6,projectile_speed_m_s=220,target_multipliers=dict(personnel=1,light_vehicle=.25,heavy_vehicle=.05,structure=.45),rules='本连指定1名L317手，枪榴弹为独立弹仓且不能同时发射步枪。停稳2秒、发射扣1榴弹；散布半径随实际射程100→850线性10→30米，落点在均匀面积圆盘内带种子抽样；友伤同规则，伤害65×max(0,1-d/12)，无第二命中骰。飞行水平距离/220秒向上取0.1，完整弹道与高差/障碍相交检查，不能穿山/屋。近距死区，不给额外狙击精度。')
design['units'].append(u)
u=unit('MCP-318','沙翎','第318骑乘侦击营',3,6,340,.94,80,1700,{'R318':6},'骑乘机动、侧翼观察、停骑射击和迅速脱离','无冲锋瞬杀；轻防护与马匹目标大；骑行射击精度低，墙/崖/沼泽限制机动',dict(name='疾驰脱离',charges_per_company=None,cooldown_s=35,duration_s=4,description='仅已骑乘身体，沿真实可通行地面路线最多4秒提速到165米/秒，期间禁用枪与刀。不能跨海、墙、崖；转弯/坡度/泥地仍受共享地理限制。结束后2秒骑速上限90且不能开火，35秒冷却从结束计。无冲击伤害、瞬杀、减伤或无敌。下马/坐骑失能/被压制即结束，未实际开始不耗冷却。'),dict(name='停骑射击',description='骑乘常速135米/秒，地面步速80。马停止0.8秒后可开枪，静止骑射精度×0.75，行进骑射×0.45且不再重复乘步行系数；下马静止使用枪型原精度。刀仅接触自卫14伤害/1.4秒、10米，不附加冲锋倍率；与枪互斥切换0.6秒，有实体遮挡则拒绝。'))
u['mount']=dict(kind='independent_mechanical_horse',per_company=6,hp=420,damage_multiplier=.9,target_class='light_vehicle',mounted_speed_m_s=135,collision_radius_m=1.2,occupancy_spacing_m=3.2,weapon=None,boarding=dict(rider_slots=1,mount_slots=3,equivalent_slots_per_pair=4),rules='马与身体独立HP、位置、实体ID和归属。下马后可留马或命马沿合法路径跟随，但无骑手不得开火/完成搜索。骑手在4米内上马2秒，下马2.5秒且需相邻合法空位；同一身体只能处于骑乘或地面之一。马毁损时骑手HP不刷新、不复活；在当前锚点进入被迫下马流程，无合法相邻点则保留受限状态，不能传送出包围。骑手死亡不把马计为人员死亡；分别回收/毁损结算，不能重复返库。坐骑不游海、不得由316担架搬运。')
u['transport']=dict(kind='heavy_landing_craft',per_company=1,personnel_capacity=6,mount_capacity=6,equivalent_body_slots_required=24,rule='每对骑手/马分别1+3等效舱位，单连需要24等效位且同时容纳6身体6马的真实运输合同；重艇容量/载重/骑乘舱位消费者未核定前阻断部署，不挪用普通艇6人位。')
design['units'].append(u)
u=unit('MCP-319','蓝棘','第319战壕突袭营',3,6,440,.8,76,1150,{'P319':2,'C319':4},'弯折壕沟近距交战，投弹后短促接触突入','交战距离短、反甲弱；非方向盾，不享开阔地冲锋收益；投弹有友伤',dict(name='壕口投弹',charges_per_company=3,cooldown_s=26,range_m=240,radius_m=16,description='指定真实可投射落点，0.8秒准备，出手扣1手雷，飞行1秒、落地后1.2秒引爆。基础90伤害，按max(0,1-d/16)线性衰减，人员/轻车/重车/工事倍率1/0.2/0.04/0.45；友方相同。落点均匀面积圆盘散布半径8米，带种子确定；弹道/爆点到身体都做实体遮挡，不能隔墙全伤。地形阻挡则按真实碰撞落点，不静默吸到目标。'),dict(name='壕沟短兵',description='每连两名左轮手另有M319，目标≤10米且真实接触通路可用时收枪0.6秒改近战，离开14米或障碍隔断则切回左轮；普通人员46伤害/1.4秒，车辆几乎无效；不能瞬杀。切换不补弹、近战不耗虚构枪弹。四名突击枪手保持短枪警戒，不全队冲去挥锤。'))
u['secondary_loadout']={'primary_weapon':'P319','secondary_weapon':'M319','bodies_per_company':2}
design['units'].append(u)
design['blockers'] += ['317声源发现/真实通信设备依赖图及单兵枪榴弹曲射','318独立坐骑/上下马/占位/死亡/回收和24等效艇位合同','319手雷弹道遮挡/友伤、接触近战/枪锤切换','新三人岗位SD与骑乘本人/独立马动作资源尚未制作']
dump(ROOT/'docs/design'/f'{TAG}.json',design);dump(OUT/'design.json',design)

jobs=json.loads((ART/'prompts.json').read_text(encoding='utf-8')); sources=json.loads((ART/'generation-sources.json').read_text(encoding='utf-8'));ledger=[]
for j in jobs:
    src=Path(sources[j['id']]); name=j['id']+'.png'; dst=OUT/'images'/name
    shutil.copy2(src,dst);shutil.copy2(src,PROJECT/name)
    im=Image.open(dst);im.load();assert im.mode=='RGBA' and im.getchannel('A').getextrema()[0]==0
    refs=[]
    for i,r in enumerate(j['refs']):
        r=Path(r);saved=ART/'references'/f"{j['id']}-{i}-{r.name}";shutil.copy2(r,saved)
        refs.append(dict(source=str(r),saved=str(saved.relative_to(ROOT)),sha256=sha(r)))
    assert sha(src)==sha(dst)==sha(PROJECT/name)
    ledger.append(dict(id=j['id'],kind=j['kind'],source=str(src),output=str(dst.relative_to(ROOT)),project=str((PROJECT/name).relative_to(ROOT)),sha256=sha(src),size=im.size,alpha=im.getchannel('A').getextrema(),prompt=j['prompt'],references=refs,method='built-in image_gen'))
dump(ART/'asset-ledger.json',ledger)
for name in ('prompts.json','asset-ledger.json'):shutil.copy2(ART/name,OUT/name)

font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',23)
def board(ids,name,columns):
    cw,ch=390,660; rows=(len(ids)+columns-1)//columns
    b=Image.new('RGB',(cw*columns,ch*rows),'#eaf0eb');d=ImageDraw.Draw(b)
    for i,id in enumerate(ids):
        u=next(u for u in design['units'] if u['id']==id);im=Image.open(OUT/'images'/f'{id}.png');im.thumbnail((cw-20,535))
        x=(i%columns)*cw+(cw-im.width)//2;y=(i//columns)*ch
        b.paste(im,(x,y+15+(535-im.height)),im);d.text(((i%columns)*cw+18,y+568),id+' '+u['name'],font=font,fill='#243c42');d.text(((i%columns)*cw+18,y+604),u['designation'],font=font,fill='#243c42')
    b.save(OUT/name,quality=94)
board([u['id'] for u in design['units']],'overview.jpg',3)
board(['MCP-317','MCP-318','MCP-319'],'new-three.jpg',3)
board(['MCP-'+str(n) for n in range(311,317)],'revised-six.jpg',3)
rows=[]
for n in range(311,317):
    id='MCP-'+str(n);r=Image.open(ROOT/'output/tactical-specialists-20261116/images'/f'{id}.png');v=Image.open(OUT/'images'/f'{id}.png')
    r.thumbnail((200,330));v.thumbnail((200,330));tile=Image.new('RGB',(420,390),'#eef0eb');tile.paste(r,((200-r.width)//2,20),r);tile.paste(v,(220+(200-v.width)//2,20),v);dd=ImageDraw.Draw(tile);dd.text((10,355),id+' 旧版 → 新版',font=font,fill='#243c42');rows.append(tile)
b=Image.new('RGB',(1260,780),'#eef0eb')
for i,tile in enumerate(rows):b.paste(tile,((i%3)*420,(i//3)*390))
b.save(OUT/'before-after.jpg',quality=93)

lines=['# 短裙身形修订与三支追加部队','','2026-11-16；九张独立透明立绘，六修订与三新增。全部为原创设计/美术候选，未接入实战。','','## 美术修改','','311–316保留原身份、发眼、配色和代表装备，改短裙/短外套与自然收腰、肩胯及修长腿部比例；313保留裤装但移除长大衣尾。317参考图一潜入联络装备，318参考图二骑兵骑姿与卡其骑装，319参考图三战壕护甲/短锤/左轮。新角色重新设计脸发和服装细节，附件字样/旗帜不是指令或人物身份。旧六张与数值原稿完整保留。','','## 数值口径','','沿用旧v4加速陆战比较尺度与HP基准×4，非现实物理参数；不能直接导入720m新海岸，须与全部兵种统一定标。311–316全部战斗数值/技能与上一版JSON逐项相同。完整九人/14武器与枪榴弹/马匹/手雷状态见design.json。','','| 新人格 | 编制 | 每体HP/承伤 | 步速/视野（米制游戏值） | 核心取舍 |','|---|---|---|---|---|']
for u in design['units'][-3:]:
    b=u['body_stats'];lines.append(f"| {u['id']} {u['name']} | {u['company_count']}×{u['bodies_per_company']}={u['total_bodies']} | {b['hp']}/{b['personnel_damage_multiplier']} | {b['speed_m_s']}/{b['vision_m']} | {u['role']} |")
for u in design['units'][-3:]:
    lines+=['',f"## {u['id']} {u['name']} · {u['designation']}",'',f"每连武器：{json.dumps(u['loadout'],ensure_ascii=False)}。{u['counters']}。",'',f"主动「{u['active']['name']}」：{u['active']['description']}",'',f"参数：{json.dumps({k:v for k,v in u['active'].items() if k not in ['name','description']},ensure_ascii=False)}。",'',f"专长「{u['passive']['name']}」：{u['passive']['description']}"]
    for key in ['mount','rifle_grenade','transport','secondary_loadout']:
        if key in u:lines+=['',key+'：'+json.dumps(u[key],ensure_ascii=False)]
lines+=['','## 新武器表','','总弹含首匣；匣尽换弹替代末尾组间隔，精度锚点线性插值。架设/切换/移动与实体遮挡另算；M319是无弹药近战，不拿占位magazine字段生成弹药。','','| 型号 | 基础伤害/最大射程m | 连发/发间s/组间s | 匣/总弹 | 换弹s |','|---|---|---|---|---|']
for w in weapons[-5:]:lines.append(f"| {w['id']} {w['name']} | {w['damage']}/{w['max_range_m']} | {w['burst']}/{w['shot_gap_s']}/{w['burst_gap_s']} | {'不耗弹' if w.get('ammo_mode')=='melee_no_ammo' else str(w['magazine'])+'/'+str(w['total_including_magazine'])} | {w['reload_s']} |")
lines+=['','## 与已有单位的区别','','317对比314：接近通信节点冒险切线，非长距持续观测；对比潜入狙击队：近设施行动与枪榴弹，不增加隐身/远狙能力。318对比002岚缨：轻骑射和转移，不用马刀冲锋瞬杀，独立马匹有运输和回收代价。319对比017：无盾/闪光；对比184：少人数、左轮与接触近战，不能取代霰弹/冲锋枪主力。','','## 未实现项与验收门','']+['- '+v for v in design['blockers']]
lines+=['','数值是待实测设计，没有虚报胜率或战斗验收。未改游戏原核、历史/PDF/参考工程、发布或正常账号，未覆盖旧图。']
doc='\n'.join(lines)+'\n';(ROOT/'docs/design'/f'{TAG}.md').write_text(doc,encoding='utf-8');(OUT/'设计说明.md').write_text(doc,encoding='utf-8')
shutil.copy2(ROOT/'docs/design/tactical-specialists-20261116.md',OUT/'前六部队数值说明.md')
cards=[]
for u in design['units']:
    id=u['id'];cards.append(f'''<article><a href="images/{id}.png"><img src="images/{id}.png" alt="{u['name']}立绘"></a><section><small>{id} · {'新增' if int(id[-3:])>=317 else '修订'}</small><h2>{u['name']} · {u['designation']}</h2><p>{u['company_count']}连×{u['bodies_per_company']}身体 · 每体HP {u['body_stats']['hp']}</p><p>{html.escape(u['role'])}</p><p><b>{u['active']['name']}</b>：{html.escape(u['active']['description'])}</p><p><b>{u['passive']['name']}</b>：{html.escape(u['passive']['description'])}</p><p class="weak">{html.escape(u['counters'])}</p><a download href="images/{id}.png">下载透明原图</a></section></article>''')
page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>CAS 九人修订与追加</title><style>*{box-sizing:border-box}body{margin:0;background:#edf0e9;color:#243c42;font:16px/1.8 "Microsoft YaHei",sans-serif}header,main{max-width:1250px;margin:auto;padding:24px}h1{font-size:34px}nav{display:flex;flex-wrap:wrap;gap:18px}a{color:#176d76}article{display:grid;grid-template-columns:minmax(200px,36%) 1fr;gap:24px;background:#fffdf7;padding:24px;border:1px solid #cdd5cb;border-radius:12px;margin-bottom:26px}article img{width:100%;height:620px;object-fit:contain;background:#dfe5df}h2{margin-top:0}.weak{color:#805735}.notice{padding:14px;background:#dce5dc}@media(max-width:650px){header,main{padding:16px}article{grid-template-columns:1fr;padding:16px}article img{height:470px}h1{font-size:27px}}</style><header><small>CAS / 2026.11.16 / v2</small><h1>六人修订 · 三人追加</h1><p>短裙、短外套与自然修长的成年身形；新增潜入联络、骑乘侦击、战壕突袭。</p><p class="notice">美术及设计候选，尚未接入游戏。前六人数值技能不变；新增三人数值为旧v4比较尺度，不直接导入720m海岸。</p><nav><a href="new-three.jpg">新增三人</a><a href="revised-six.jpg">修订六人</a><a href="before-after.jpg">六人前后对照</a><a href="设计说明.md">三人完整数值技能</a><a href="前六部队数值说明.md">前六人数值</a><a download href="design.json">九人JSON</a><a href="prompts.json">实际提示词</a></nav></header><main>'''+''.join(cards)+'''</main></html>'''
(OUT/'index.html').write_text(page,encoding='utf-8')
old=json.loads((ROOT/'docs/design/tactical-specialists-20261116.json').read_text(encoding='utf-8'))
assert design['units'][:6]==old['units'] and design['weapons'][:9]==old['weapons']
assert len(design['units'])==9 and len({u['id'] for u in design['units']})==9
assert len(weapons)==14
for u in design['units']:
    assert sum(u['loadout'].values())==u['bodies_per_company'] and u['total_bodies']==u['company_count']*u['bodies_per_company']
    assert u['body_stats']['hp']==u['body_stats']['baseline_hp']*4
for w in weapons:
    assert w['total_including_magazine']>=w['magazine']>0
    assert all(0<=p<=1 for _,p in w['accuracy_anchors'])
dump(OUT/'validation.json',dict(portraits=len(ledger),old_six_gameplay_unchanged=True,units=9,weapons=14,alpha_and_source_sha=True,runtime_tested=False))
with zipfile.ZipFile(ROOT/'output'/f'{TAG}.zip','w',zipfile.ZIP_DEFLATED) as z:
    for p in OUT.rglob('*'):
        if p.is_file():z.write(p,p.relative_to(OUT))
with zipfile.ZipFile(ROOT/'output'/f'{TAG}.zip') as z:assert z.testzip() is None
print('Nine portraits, unchanged six-unit gameplay, 14 weapons, source SHA and ZIP verified.')
