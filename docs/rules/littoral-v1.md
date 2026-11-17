# 原创两栖行动 cas-littoral-v1

本模式是独立架空的本地人机海陆空协同行动，不是历史战役裁决，也不是联网互袭。原始资料、历史世界、旧搜打撤和两版潮汐活动保持冻结。所有机器人身体均为女性化外表，身体实体以所属 MCP 身份关联本人表现，不使用无脸金属大兵替代；数值由原核决定。

## 创建与装载

```json
{"op":"new_littoral","version":"cas-littoral-v1","seed":42,"mode":"tutorial","ships":[{"id":"IBS-U-USN-FLETCHER","hp":100,"ammo":100}],"roster":["MCP-034"],"unit_condition":[{"id":"MCP-034","hp":100}],"transport_preset":"balanced","defense":[]}
```

mode 为 tutorial/raid/defense/salvage，舰 1–6 艘且实际登记身份唯一，MCP 1–5 支且唯一。hp 是未损伤基础耐久的绝对百分比。unit_condition 非空时必须与 roster 身份集精确对应且各至少 10%；省略仅用于直接原核调用，默认 100。账户服务负责拥有与整备率验证，教学借用 MCP-034 不等于已经拥有。

`transport_preset` 为 combat/balanced/transport，对应装载弹药上限 100/70/40%。实际 loaded 为 min(传入 ammo,预设上限)，不凭空添加弹药。普通舰运输基础槽 DD等2、CA/CL/CV4、BB/BC6；真实登记 AP/APA/LST/LSI/LSD 为20，AK/AKA/TR/transport/AV为16，再加 floor((100-loaded)/20)。不接受客户端自行声明舰种。优先使用有足够空槽的真实运输支援舰装载，再使用普通战舰。减弹立即换实际舱位，未装弹留在账户，已装弹在海上真实消耗。防守模式的驻岛部队原已在家园，不占出航运输舱。

| 编号 | 名称 | 槽 | 地面/空中实体与实际分工 |
|---|---|---:|---|
| MCP-001 | 第1空中特勤旅·云隼 | 2 | 两名特勤步兵、一架武装直升机，可空插 |
| MCP-034 | 第34海军派遣团·礁刃 | 3 | 三名陆战步兵、一辆步战车 |
| MCP-076 | 第76近卫空降群·冬鸢 | 3 | 三名空降兵、一架火力支援机，可空插 |
| MCP-009 | 第9滨海工兵营·汐锚 | 2 | 四名工兵，双倍搜索、有限工具排雷/修设施 |
| MCP-022 | 第22远征装甲连·铁潮 | 4 | 两辆装甲战车、一名护卫；抗轻武器、怕反坦克火力 |

配置 `defense` 为 0–16 个 `{id,kind,x,y,level,hp}`，kind 是 hq/turret/aa/depot，位置 x/y 为 0..1 岛内归一化，level1..3，hp缺省100。必须恰有一个指挥部；空列表由原核生成三座设施。raid/tutorial/salvage 是敌设施，defense 是己设施。建筑损坏保留身份，不从账户静默删除。未来本地玩家快照可携带该冻结配置，但本版不实现网络。

## 时钟与真实世界

10Hz 确定性微步，`frame` 整数、`tick=frame/10` 秒。step.seconds 接受0..2700内0.1倍数，非法输入原子拒绝。一局上限480模拟秒；守岛主阶段180秒。海图24000×16000米，大岛程序岸线随种子微变，陆图只是同一世界的局部窗口，不另造坐标或战果。实际陆地判定、山地障碍与水面航路均由原核校验。海军活动位移为正常节转米/秒×8；陆军与载具使用本模式公开的独立速度，不反写历史舰表。

守舰开始锚泊，来袭进入范围或警报时开始6秒起锚，再由正常水面航路出港迎战。舰艇真实位置、航向、登记炮程与炮座射界、余弹、装填和存活共同限制舰炮。海战和地面炮弹实际飞行到落点后才判伤，移动可造成落空。海军伤害与地面数值是本原创活动参数，不冒称重做完整 CAS 海陆规则。

陆战基础参数如下；这些只属于本活动，不覆盖任何历史舰卡。每个身体有自己的耐久、有限弹药、装填与攻击位置，共用部队移动指令而不共用虚构伤害。

| 身体类型 | 基础HP | 单发伤害 | 射程米 | 装填秒 |
|---|---:|---:|---:|---:|
| 陆战步兵 | 100 | 22 | 700 | 1.5 |
| 空降兵 | 95 | 30 | 850 | 1.8 |
| 工兵 | 95 | 16 | 600 | 1.8 |
| 步战车 | 260 | 42 | 1100 | 2 |
| 装甲战车 | 420 | 100 | 1600 | 4 |
| 火力支援机 | 180 | 55 | 1400 | 1.8 |
| 武装直升机 | 150 | 32 | 1200 | 1.5 |
| 敌反坦克组 | 110 | 80 | 900 | 3.5 |
| 敌普通步兵 | 90 | 15 | 650 | 2 |

地面身体90发、空中45发。装甲战车/步战车对轻武器的伤害系数为0.28/0.45，反坦克与舰炮不会沿用该轻武器减伤。舰炮伤害为 clamp(口径毫米×0.35+炮管数×4,35,250)，爆炸半径 clamp(口径毫米×0.65,100,300)；300毫米以上每次齐射耗3%弹、装填10秒，180毫米以上耗2%，其余耗1%，非重炮装填7秒，余弹不足完整齐射会拒绝。舰炮射程及炮座射界来自本人登记舰卡。舰艇基础HP为 max(登记DP×5,300)，出航实际HP再乘账户整备率。防空设施射程2600米、每3秒发射45×等级伤害；普通炮塔射程1700米、伤害28。登陆载具220HP/95米每秒，空插载具130HP/220米每秒；运输损伤会实际带入所载身体。

## 命令

- `route {fleet:1,points:[{x,y}],speed:4..40}`，最多12点，真实水面路径；`speed {fleet:1,speed:0..40}`。
- `preview_route` 同形，纯读返回valid/paths/error。
- `littoral_ship_order {ship,action:"move",x,y}` 单舰移动；action hold/anchor 停航或锚泊；action face 搭配 heading 下达转向目标，每0.1秒最多转6°，不会瞬间旋转绕过射界。ship 为观察中的整数舰艇ID。
- `littoral_deploy {unit_id,beach:1..3,insertion:"landing"|"air"}`。普通登陆须载舰实际在滩头 sea 点900米内；空插只001/076可用，须距land点6000米内。实际运输载具走到/飞到land点才生成地面实体，运输途中可损失。每支部队本版只登陆一次。
- `littoral_order {unit_id,action:"move"|"attack"|"defend",x,y}` 下达陆地指令；hold停留；retreat真实回原滩头、载具返舰。
- `littoral_order {unit_id,action:"search",target:整数遗迹ID}` 真实接近并搜索；普通8秒、工兵4秒，敌人在近处会中断推进。物资归携带部队，未撤回不能当到账。
- `littoral_order {unit_id:"MCP-009",action:"repair",target:字符串设施ID}` 仅修己设施，实际工具有限；不治疗账户舰娘或MCP整备率。
- `littoral_support {kind:"naval",ship,x,y}` 正常立即舰炮支援；舰沉、没弹、锚泊、装填或射界/距离不符均拒绝。追加 queue:true 可登记每舰最多一条真实岸援待发，最多保留90秒；新目标替换旧目标，真实装填完成且当前射界/炮程允许时优先于自动海战开炮，仍扣足额弹药。support.naval 的 pending_target/pending_expires_tick 公示真实队列；littoral_ship_order 的 action:cancel_support 可取消。舰损、弹药不足或过期清除待发，保存重演保留这一状态。
- `littoral_support {kind:"helicopter",unit_id,x,y}` 必须有真实活着的在场直升机、有弹且在其火力范围；AA会真实打击空中实体与空插运输。
- `littoral_extract` 主要目标已成、所有存活部署部队真实返舰、所有存活舰进入出口才可结算。守岛完成后在己岛回收，不要求驻地部队重新登船。
- `littoral_abandon` 主动退出不发新资源；真实弹药消耗、伤亡和未回收部队仍留证明，不能重开抹账。

raid 要地面实体实际占领指挥部80微步，附近敌军会争夺；salvage/tutorial 至少真实搜索一处遗迹再返舰撤离；defense 须守住指挥部180秒。耐久归零、失去全部撤收舰或超时会产生真实失败；守岛允许舰艇牺牲后地面继续守卫。失去原载舰后只可使用实际还有空舱的存活舰撤收，不能凭UI造救援。

## 公开观察

顶层 version/tick/limit/width/height/side/intel_profile/ships/fleets/contacts/islands/shells/torpedoes/events/result 兼容海图；islands 为 polygon 数组，海上敌舰在 contacts，陆地实体在下述 land。舰娘 ships.characterId 使用本人登记身份。

`littoral` 字段：

- version/mode/frame/simulation_hz/phase/outcome；phase 为 embarked/landing/ground/extracting/finished。
- beaches `[{id,name,sea:{x,y},land:{x,y}}]`；exit `{x,y,radius}`。
- groups `[{id,name,role,carrier,insertion,stage,position:{x,y},hp_percent,initial_hp_percent,order,target,transport_slots,supplies,beach,status_reason}]`，stage 为 embarked/transit/ground/returning/recovered/lost。
- transports `[{id,unit_id,carrier,kind,x,y,target,hp,max_hp,returning}]`。
- land `{bounds:{x,y,width,height},polygon,obstacles,entities,buildings,ruins,mines}`。entities 带整数id、unit_id、side、kind、presentation、x/y、hp/max_hp、ammo、airborne、range/damage/reload_seconds/order；所有身体 presentation 为 female_android。舰艇的 target_heading 表示尚在完成的转向目标。载舰损失且备用舱不足时 status_reason 明示等待原因，不凭空生成救援容量。
- buildings `[{id,side,kind,x,y,hp,max_hp,level,ammo}]`；ruins `[{id,x,y,progress,searched,loot}]`。
- objectives `[{id,kind,x,y,progress,complete}]`，cargo `[{id,kind,amount,holder}]`，support.naval/helicopter 公示实际舰与空中支援状态。
- shots/impacts 带单调ID、frame/tick、真实source、落点、伤害/命中；不以演出反推命中。

预算：己方身体最多32，敌方最多64，飞行弹体最多256，运输最多5，事件/发射/命中各最多96。敌军有限波次，微步不遍历历史命令。观察公开的是本新模式的完整本地人机态势，不替换历史双盲。

## 终局与账户证明

只有真实终局才有 result 和 littoral.outcome。outcome 包含 version/mode/success/abandoned/duration/frame、objective_complete/island_secured/searched_ruins/enemy_defeated、resources、ships、units、buildings。

resources `{scrap,alloy,protocols,credits}` 进入独立家园资源。三处遗迹分别60浮材、25合金、1协议，实际携带且回收才结算；raid成功另40浮材80岛屿补给，defense成功30浮材50补给；退出/失败不发新资源。不会重复刷新同一遗迹或重复结算同一局。

ships `[{id,ship_id,hp_percent,initial_hp_percent,ammo_percent,requested_ammo_percent,loaded_ammo_percent,unloaded_ammo_percent,ammo_spent_percent,sunk,recovered}]`。hp_percent 分母为未损伤基础HP，因此初始60%无伤不会冒报100%。ammo_percent 为剩余在舰弹百分数，spent=loaded-remaining，unloaded=requested-loaded从未装船；账户出航扣loaded、只对存活已回收舰返remaining，未装部分不得再退一遍。

units `[{id,hp_percent,initial_hp_percent,incapacitated,recovered,missing,carrier,initial_count,surviving_count}]`，绝对整备率同样用未损伤基础HP。未回收身体标missing并影响实际整备；建筑 `[{id,hp_percent,destroyed}]` 供账户持久修复，不删卡/删建筑。

Saved 严格为 `{version,seed,config,frame,tick,commands:[{frame,request}]}`，config 只含 mode/ships/roster/unit_condition/transport_preset/defense，不重复version/seed/op。load/replay 从种子和实际命令重建，拒绝乱序、未来指令、时钟不匹配和超过真实终局；未知字段拒绝。账户 begin 绑定出航配置和 tick0 原核快照，settle 独立 load 验证终局后幂等应用损失与有限资源；不相信UI填写的结果。

## 原核验收证据

候选原生核 SHA256 `f72f37a7401f8cfae058696128c0e1e3318d4847c8ce5a60fe80516f49f811b3`。268项Rust测试全过，其中21项覆盖本模式身份、容量/条件、地形、真运输、AA、舰损、工程、排队岸援、保存与非法输入等规则。`artifacts/littoral-rust-tests.log`、`artifacts/littoral-core/native-receipt.json`、`protocol-receipt.json`、`native-hz10-receipt.json` 和 `parity-receipt.json` 为本轮原始证据；UI、账户和正式默认部署由整合验收另行记录，不能用本段冒充窗口已过。

最终矩阵四模式成功：教程42种子190秒、突袭42种子305秒、搜物资43种子184秒、守岛44种子180秒；另45种子45秒主动退出零资源，1%舰体/无弹真实88.3秒失败。日进+衣阿华护航46种子322.5秒胜利，全部五卡确实占日进14/16舱、到岸生成18个本人归属身体、各自真实开火、存活部队实际撤回原舰后撤离；有真实部队伤亡，不宣称全员生还。较早 balanced70 舱位不足且载舰沉没的救援失败样本保存在 `artifacts/littoral-core/stage-fb9621-risk`，没有为了测试补舱或补血。

10Hz教程为188.6秒真胜，1886次0.1秒step；与0.5秒控制回路的下令时机不同，所以终局秒数不强行相等。六场0.5秒step往返95分位不超过1.45毫秒，最大约2.14毫秒；完整save/load/replay分开记录，不能拿重演耗时当成单步停顿。实体峰值26、弹体峰值7、运输峰值5，均在预算内。16组8936请求、243887535响应字节的原生与WASM逐字节相同，其中8组旧模式进一步对已发布f38内核冻结（5旧潮汐、混合舰种新潮汐、实际旧v2打捞752请求、竞技）。每份commands夹具都可直接重跑，未用UI合成奖励或战果。

本新模式将已登记可拥有的日进（IBS-U-IJN-NISSHIN）和千岁（IBS-U-IJN-CHITOSE）AV明确作为水上机母舰兼运输支援，基础16槽，三预设分别16/17/19槽；仍用本人实际身份、HP、舰炮与炮座射界，不冒充AP、不改历史舰表。观察和两栖catalog中的 transport_role=transport_support，其他战舰为warship；玩家仍需先拥有该本人舰娘。
