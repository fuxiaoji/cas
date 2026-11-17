# 海陆协同 v2 合同（2026-11-13）

显式版本 `cas-littoral-v2`，`cas-littoral-v1` 的阵位、五队数值、命令、输出和存档均冻结。历史战役不进入本模块。10Hz、0.1秒步长，480秒上限；保存 version/seed/config/frame/tick/commands，load 和 replay 从真实日志重建。

## 创建和数值唯一来源

new_littoral 配置仍为 mode、ships、roster、unit_condition、transport_preset、defense。v2 最多6支唯一队伍、6艘真实舰，满6队最多24身体，身体预算32不变；真实运输舱不足即拒绝，不绕过本人拥有或条件。所有20队实装，每队不同编成/数值/能力。原五队基础属性仍使用原数值，仅v2新增有限主动技能。

`littoral_catalogue` 带version导出本版本。`godot/data/tactical-profiles-v2.json` 是从同一原核导出的UI来源，Rust测试逐体检查；不复制另一套平衡表。cards 包含 id/name/role/role_label/nato_type/transport_slots/entity_count/speed/air_insertion/brief/bodies/ability。body 的 hp/damage/range/reload_seconds/ammo/speed/armor/airborne 为真实满整备值；受伤条件按原规则缩放初始HP。

## 拖动登陆

`littoral_preview {kind:"deploy",unit_id,x,y,insertion}` 或 beach，返回 `{ok:true,data:{valid,reason,...}}`，纯读、不耗资源。拖陆点会选真实最近滩头；data 含 beach、sea、land、carrier、path、distance、range_limit、can_launch_now。

`littoral_deploy {unit_id,x,y,insertion,queue:true}` 或 beach：部队在原载舰保持embarked，只有该载舰沿合法水路航行。达到接驳点900米以内（空插为陆点6000米）才发真实舟艇/直升机。到达才ground。相同载舰不能同时接近不同滩头；冲突拒绝且不改状态。手动舰艇移动/停船/转向或全队航令取消对应未开始队列；`littoral_cancel_deploy {unit_id}` 显式取消。不得把队列当成功上岸。

公开 group.pending_deploy 为null或 {beach,insertion,status:"approaching",distance,range_limit,reason}。事件 deploy_queued → deploy → landed，运输损失仍损失本人。

## 真实炮援

`littoral_preview {kind:"aim_land"|"naval",ship,x,y}`。`littoral_ship_order {ship,action:"aim_land",x,y}` 选择实际枪炮射界中最短转向，最多每0.1秒6度，停船起锚；不瞬转、不授弹。

随后 `littoral_support {kind:"naval",ship,x,y,queue:true}` 可在同一个已接受aim_target转向中排队；没有匹配目标且当前射界非法则拒绝。真实炮程/射界/装填/弹药达到才发一次弹体并精确扣弹，90秒过期，cancel_support可取消。可对合法空地试射，不伪造命中。support.naval公开 aim_target/aim_state/ready_for_target/reason/ready_in/pending_target；ready仅物理条件实际满足。

## 能力

`littoral_ability {unit_id,x?,y?}`，须存活ground、有限次数及冷却；range=0只作用本人所在区域。公开group.ability含 id/name/charges/ready_in/available/range/radius/active_seconds/reserve_ammo。拒绝不扣次数、不写日志。范围、次数与冷却见唯一数值JSON。

- 云隼/冬鸢/赤隼：实际旋翼机消耗1弹的区域火箭。
- 礁刃：实际步战车消耗1弹的压制齐射。
- 汐锚：2工具补给维修附近己设施；被毁不复活。原排雷/双倍搜索保留。
- 铁潮：8秒650米防护，入射伤害×0.6。
- 灯鲨/苇影：8秒烟幕伤害×0.7，覆盖不叠乘；灯鲨夺点速度×2。
- 苔原：搜索×2；10秒标定区友方落点伤害×1.25，不叠乘。
- 雾雀：区域敌炮塔/防空真实装填延后8秒。
- 白鹭/雨燕：只治疗存活身体，不超过出航整备与运输伤损上限、不复活；雨燕10秒加速撤收。
- 断浪：实际反装甲组1弹穿甲弹，对装甲按反坦克修正。
- 砾火：实际火箭炮3弹/3发区域弹幕；普通炮500米内不能射击，远程越障。
- 潮梭：舟艇×1.35；10秒附近行军×1.6。
- 银脉：出航携120发独立地面储备，每次最多转60、每身体最多20，不生成舰炮弹药。
- 夜莺：8秒本人伤害×1.6、射程×1.15。
- 苍穹：实际防空组1弹防空弹幕，普通攻击也可对空。
- 苇影：舟艇×1.5，以较低HP换速度。
- 烬羽：实际工兵1弹近程爆破。
- 星桅：10秒附近装填间隔×0.65、行军×1.2，夺点速度×2。
- 雨燕：返程运输×1.4；技能急救与10秒撤收加速。

所有能力不消耗永久资源、不引入永久成长、不通过治疗获得超出初始condition的结算回血。普通自动攻击/技能都用真实弹体、实际身体弹药与命中。

## 新教学节奏

仅v2 tutorial舰队初始合法海侧位置(12000+220i,12200+180i)，敌守舰前60秒保持锚泊且不海军开火；岸敌/炮塔仍有真实射程，非无敌。实际034+Fletcher拖滩2验证27.1秒真实上岸。船速仍原该架空模式8倍航行尺度，不传送；其他模式阵位不变。重复教学借用034由账户层明确处理，不把本人治满或凭空永久授予。

教程按上岸→地面移动/攻击→舰炮实射→遗迹真搜→退滩接驳→载舰驶入撤离区→extract真实结算。失败/放弃保留耗弹和伤损，不伪造资源。


非教学新v2行动在120秒有一架真实敌旋翼机进入，使用有限45发弹药；v2空中单位不能阻挡地面HQ占领，避免空弹悬停导致无法结局。此分支完全不进入v1。

## 最终原核验收

正式默认 `godot/bin/runtime/db75a0459d23c3c8/cas-sim.exe`，SHA `db75a0459d23c3c814009d3de07de590003bc2a38508438efb84bd00f395121d`。

- Rust 286/286，含18个新v2检查：20队逐体真值与真实开火、6队运力、实际登陆队列/取消/冲突不变、真实炮援耗弹与重演、有限技能弹药/减伤/医疗上限/后勤守恒/标定/电子压制/协同装填/行军。
- 正式默认6场：教程152.5秒胜，首上岸27.5秒；六队打捞198.5秒胜；无工兵强攻480秒真败零奖；原五队夺岛316.5秒胜；另一六队打捞193.5秒胜；守岛180秒胜。覆盖全部20身份真实部署；每队真实开火另有独立Rust门。模拟推进不是1×墙钟的UI验收。
- 8个旧v1夹具4612请求、80,061,042字节与正式7134核逐字节相同。
- 新旧14夹具8729请求、181,031,363字节native/WASM完全同；最终WASM SHA `67ab469d6d476e2a33d9a64fd79ded17f2b511acf2fc44cf756abe2a86c59e50`。
- 实际Edge旧历史网页兼容17/17、零错误：历史出击、推进、保存、整页刷新恢复、竞技创建和重演。不是网页两栖UI；旧网页固定白昼标题差异仍登记。临时浏览器与服务已退出。

总回执 `artifacts/littoral-v2/final-index.json`；真实航次/原始命令/逐字节门见同目录default-receipt.json、v2-*-commands.json及原生战况。Godot拖拽、三尺寸、1×教学验收由UI专项记录，不以原核日志代替。
