"""Generate readable source notes from the one exported native v3 catalogue."""
from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]
d = json.loads((root / 'godot/data/island-war-v3.json').read_text('utf8'))
models = {w['id']: w for w in d['weapons']}
lines = ['# 战术武器与海岛攻防 v3：原创数值和实现边界', '',
'仅显式 `cas-island-war-v3`。以下为原创加速游戏数值，不是历史武器试验结果、CAS原表或现实编制。已发布v2、littoral v1–v4和历史阵位/原PDF继续冻结。人员身份及原连数不变；训练临时借用不发永久部队。', '',
'唯一运行目录是原核 `island_war_catalogue(version=cas-island-war-v3)` 导出的 `godot/data/island-war-v3.json`。22角色与43型号实施设计输入分别是 `docs/design/tactical-v3-role-brief.json` 和 `tactical-v3-weapon-models.json`，不是第二运行目录。导出器 `scripts/export-island-war-v3.py` 同时真实构造校验六课请求；完整接口见 `docs/rules/island-war-v3-contract.md`。本页表格由 `scripts/write-island-war-v3-source-notes.py` 直接从目录生成。', '',
'## 身体与固定投送', '',
'所有22本人采用固定投送方式，非法覆盖由原核拒绝。011为多条真实2座皮划艇（180米/秒为本原创模式的加速游戏尺度，无甲且乘员暴露）；034普通登陆艇。022/103/087的装甲运输资格与027/006的航空舰搭载资格独立于身体的步兵分类。088仍五连各十身体，飞机真实抵达后伞降，下降时脆弱且不能开火，艇撤收。', '',
'人员轻重防护是承伤乘数，越小承伤越少，目标仍为unarmored；不能把防弹衣当坦克甲。独立平台按车辆甲类矩阵再乘车辆自身承伤系数。身体与车辆各有HP/武器/速度/弹匣，镜像只供既有裁决命中同一实体，不重复扣血。', '',
'|本人/番号|连×身体|每体HP/承伤倍率/速度m/s|固定投送|每连实际身体武器|真实技能|',
'|---|---:|---|---|---|---|']
for c in d['cards']:
    s = c['body_stats']
    composition = []
    for row in c['weapon_composition']:
        text = row.get('weapon_id', '?')
        if row.get('secondary_weapon_id'): text += '+' + row['secondary_weapon_id']
        if composition and composition[-1][0] == text: composition[-1][1] += 1
        else: composition.append([text, 1])
    weapons = '、'.join(f'{n}×{w}' for w, n in composition)
    lines.append(f"|{c['id']} {c['name']} · {c['designation']}|{c['company_count']}×{c['personnel_per_company']}|{s.get('hp',s.get('max_hp','?'))}/{s.get('armor_multiplier','?')}/{s.get('speed_mps',s.get('speed',c.get('speed','?')))}|{c['default_transport']}|{weapons}|{c['ability']['name']}|")
lines += ['', '## 独立作战平台', '',
'全部为同人格远控，min_crew=0，不赠送额外驾驶员。022坦克零座，六个原有步枪身体始终独立；重艇同时装一车和六身体。103/027/006用同一实体投送与作战，087经重艇运输后独立展开；除坦克外可实际走近登载/合法卸载自己的原身体。车辆弃置不能下次免费复活，按(unit,company)独立车况维修。未投送但还在存活本舰内的车辆安全保留；载舰沉没则实际损失。', '',
'|本人|每连车/机|HP|甲类/承伤倍率|速度m/s|半径m|乘员座位|实际型号|',
'|---|---|---:|---|---:|---:|---:|---|']
for c in d['cards']:
    for v in c['combat_vehicles']:
        lines.append(f"|{c['id']}|{v['count_per_company']}×{v['kind']}|{v['hp']}|{v['armor_class']}/{v['armor_multiplier']}|{v['speed']}|{v['collision_radius_m']}|{v['passenger_seats']}|{v['weapon_id']}|")
lines += ['', '## 型号与有限射击', '',
'型号ID表示具体枪型；family只是共享机制/美术类别。所有射击间隔、组间歇与换弹时间为0.1秒整数帧，冲锋枪三发短连射、DMR单点射。单发burst_size=1且两间隔一致。组间歇从前组末发算到下组首发，弹匣空后自动换弹，最终发射时刻受组间歇与换弹完成两者约束。总携弹含初始弹匣；magazine+reserve始终等于总余弹，未命中也扣一发，每身体每帧至多一条弹道。副枪/载具独立库存，技能真实发射也受弹匣约束。平均间隔是整匣持续射击估计，不是换弹时间；不足一组的尾库存按真实余弹耗尽。', '',
'|具体型号|类别|命中基础伤害|最大射程m|每组发数|发内s/组间s|弹匣/换弹s|总携弹|爆炸半径m|',
'|---|---|---:|---:|---:|---|---|---:|---:|']
for w in d['weapons']:
    lines.append(f"|{w['id']} {w['name']}|{w['family_id']}|{w['damage']}|{w['range_m']}|{w['burst_size']}|{w['fire_interval_s']}/{w['burst_interval_s']}|{w['magazine_capacity']}/{w['magazine_reload_s']}|{w['ammo_capacity']}|{w['blast_radius_m']}|")
lines += ['', '## 精度、掩护与实际判定', '',
'直射单目标仅一次确定性随机命中判定，不叠加旧35米几何再判。概率由每型号基础精度×五节点线性距离曲线×实际移动系数×连续近距系数÷指挥散布系数，钳制0–0.99。静止/移动样本和完整公式在目录accuracy；车辆取实际自身速度。冲锋枪远距衰减快、DMR平缓、狙击有近身和跑射代价。范围武器只以质量决定真实二维散布盘，随后用实际位置/半径/距离衰减裁决，不再掷点目标命中币；非制导提前量与导弹跟踪依据实际目标速度。轻武器对飞机/武直低伤，对下降伞兵正常。', '',
'022坦克/103两栖战车的实际3米圆形足迹遮挡直射，双方同样生效：友车挡射界时不发射不耗弹，敌车拦截时真实打车；侧翼可以绕开，范围/高弹道不会获得无条件减伤。托管以已知真实威胁方向让坦克在前，六身体在后10–19米找合法独立位置，最多两人每十秒探侧两秒，真受伤强制两秒回后；实际移动/碰撞决定能否走到，不靠屏幕挪位。仅022/103启用这套协同，087自行炮保持远距支援不冲锋；圆形车体不是完整方向装甲/3D弹道。', '',
'原核v3复制冻结移动调度为独立版本：逐身体连续扫掠占位加入实际车体、窄口避让，撤收时每人独立路径到真实接驳点，不再以连队平均点瞬移。手动hold真停，托管hold允许真实局部掩护移动。载具与人可独立移动；预览调用共用真实命令门且不改随机数/状态。', '',
'## 技能与课程真实性', '',
'009工程炸药为连级三枚，180米内只投实际敌工事；对结构倍率2.8，不是无限维修。116保障网三次、12秒、700米，弹匣换弹×0.8/承伤×0.9，不造弹不转移库存；枪弹0但有次数且能真正支援友军才留场。203指挥网实际改移动/精度/任务速度；184真实有限手雷；145独立可毁有限防空炮台；128真实缩小有限舰炮/航空散布。全部次要武器由目录引用，不凭UI猜型号。', '',
'六课landing/weapons/artillery/airborne/roles/combined_arms均为完整借用exercise，起局手动、可托管。检查依实际登陆、开火命中、技能有用效果、独立上下车和真实回收事件，且必须真实胜利，不能以对白/点击/等待/空地投弹过关。roles同时检009/116与四新角色；combined检查车步共存、实际下车/走近登载、独立开火、回收。最多120秒公开教学准备仅推迟敌人实际开火，不授予进度；普通局没有。未解决1200秒实败。', '',
'## 验收与明确边界', '',
'真实当前回执索引为 `artifacts/island-war-v3/core-verification-index.json`；专项、六课真实命令/终局、native/WASM逐字节、旧版冻结与实际浏览器证据分别保留。Godot生产交互、安装核对与账号边界由主代理/UI代理独立验收，不能把核心单测冒称GPU/账号证明。', '',
'AI仅用同侧已知身体，不把发现一人升级为读取同连隐藏位置。有效站距以所有存活有限主副武器和实际节奏估计，换弹时停火/保持距离，功能队跟随；这是85%峰值估计DPS启发式，不是范围弹道蒙特卡洛最优解，也没有声称完整队友轮换掩护。', '',
'OpenRA仅借鉴公开的占位/等待/重寻路原则，未复制GPL代码；当前实现独立编写。参考 https://github.com/OpenRA/OpenRA/blob/bleed/OpenRA.Mods.Common/Activities/Move/Move.cs 与 https://docs.openra.net/en/playtest/traits/ 。没有更改原始PDF、参考源项目、历史舰表或CAS原始航空规则。', '']
(root / 'docs/rules/island-war-v3-source-notes.md').write_text('\n'.join(lines), 'utf8')
print(json.dumps({'cards':len(d['cards']),'models':len(models),'notes':'docs/rules/island-war-v3-source-notes.md'}))
