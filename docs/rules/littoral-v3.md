# 海陆协同 v3 合同（2026-11-14）

`cas-littoral-v3` 只用于架空本地人机两栖行动。历史战役、v1/v2创建、阵位、表值、命令、存档和拒绝响应冻结；缺省catalogue仍为v1。新局须显式version。10Hz，frame为整数，tick=frame/10，0.1秒合法，480秒上限。load/replay只从seed/config/命令日志重建，不收客户端血量、命中或奖励注入。

## 创建及唯一数值源

`new_littoral {version,seed,mode,ships,roster,unit_condition,transport_preset,defense,company_transports?,lesson?}`。原六个config字段及本人身份/HP/弹药约束不变。v3每场2–5个不同连队，每连6–10个真实女性化机器人身体，友方最多50、敌方最多64、总身体128、弹体384、运输体5、近期记录96。旧v2最多6队/32预算、v1原五队不变。

`company_transports:[{id,kind}]` 非空时必须与roster身份全集相同且唯一；kind为landing_craft/amphibious_vehicle/helicopter。空或缺省按每队默认。直升机只对登记可空运队伍开放；重装单位不能任意改成直升机。`lesson` 仅v3 tutorial，取sea_control/landing/combined，缺省landing。其他模式不收非空lesson。

`littoral_catalogue {version:"cas-littoral-v3"}` 与 `godot/data/tactical-profiles-v3.json` 是同一原核导出的唯一UI数值源。cards[].transport_options每项公开实际人员数、身体数值、舱位、载具HP/伤害倍率armor/速度/模型身份/有限武器。Rust逐体对照spawn，字段舍入与真实装填一致。body里的坦克、步战车、火炮和旋翼机是本连机器人操作的装备身体，人员总数已包含其驾驶员，不额外虚增全编制人数。

船容量直接用catalogue.ships[].slots_combat/slots_balanced/slots_transport，舰种取登记本人，不信客户端type。一个连队完整占一艘存活载舰舱位，不拆分或只看总舱位；不足拒绝。载弹preset仍100/70/40，少装的弹药仍在基地，装载/剩余/消耗严格守恒。防守为已驻岛部队，不占出航运力，但仍2–5连。

## 三类运输的真实取舍

同一部队船艇通常8–10人，两栖战车6–8人，直升机6人。需求舱位=原队基础槽+船艇2/战车3/直升机1。基础载具为艇300HP/90m每秒/伤害倍率1，战车460HP/150m每秒/0.42，直升机160HP/320m每秒/0.9；每队有固定公开型号修正，不能把基础值当每队最终值。armor为乘入伤害的倍率，越低越抗打，穿甲和舰炮对装甲最低倍率0.8。每队自己的默认vehicle_id/visual_id/vehicle_name/art_variant固定；备用family仍使用本人ID，不借他队载具。

MCP-027赤隼默认武装直升机。运输飞行期间确实索敌：1400m、12发、每1.2秒一发、60伤/120m爆炸范围；真实弹体kind=transport_gunship，发射成功扣1弹，0弹停火，返航不补弹。所有载具实际受火，击毁使其所载连队失能；到岸前受损按剩余载具HP比例影响乘员整备，返程受损同样作用于真实幸存身体。搜索物资必须随本人真实返舰，不因UI显示获得奖励。

## 拖动与公开状态

复用v2 deploy/queue/aim/order/ability协议。v3的insertion仅旧命令兼容提示，不能覆盖冻结的transport_kind。拖岛通过最近合法滩头，真实载舰航路靠近，接驳范围船艇/装甲900m、直升机距陆点6000m，运输实体实际到达才landed。所有新字段只加在v3观察。

- groups：company_id、company_count=1、personnel_count、surviving_personnel、transport_kind、transport_stats、vehicle_id、vehicle_ammo。
- entities：company_id=unit_id、equipment_kind=kind，原真实id/position/hp/ammo保留；presentation=female_android。
- transports：kind为实际family、personnel_count、armor、speed、vehicle_id/visual_id/name/art_variant/ammo；运输stage/returning由原核裁决。
- `littoral_preview {kind:"ship_move",ship,x,y}`：纯读真实水路规划，valid/path/reason；不下命令、不写日志。deploy/aim_land/naval预览仍可用。
- 舰炮aim_land逐步转向、queue等待真实射界/装填/弹药；实际shots/impacts才是开火和命中，不以客户端flag判定。

每队本场只能登陆一次，已回收者不能反复下船复制身体或补满弹药；旧版已有此限制。指令拒绝无账户扣费、无原核状态改动。保存config省略空company_transports及空lesson；账户v3创建应传完整company_transports、tutorial显式lesson，其他mode省略lesson，使保存config可精确核验。

## 地面节奏与三堂训练

v3地面行军速度×2.5，装填ticks在原角色修正后÷1.8四舍五入、至少1tick；遗迹搜索/夺点进度×2。舰艇历史卡参数不改；原架空模式公开8倍海上航行尺度保留。非教程18个初始守军、120秒有限敌旋翼机增援；不是提高永久养成数值。教学合法近岸初始海位继承v2、敌舰前60秒不主动开火，岸防仍真实可伤人。

training公开lesson/enemies_afloat/landed_company_ids/shore_support_hits/searched_ruins/complete：

1. sea_control：真实击沉所有敌舰，存活己舰进入出口后extract；两连可保持舰上，不假登陆。
2. landing：真实搜索至少一遗迹，存活已部署连队实际返舰、存活舰驶入出口后extract。
3. combined：至少两个不同连队实际登陆、舰炮至少一次实际命中敌岸上身体或设施、至少一遗迹searched；其后真实返舰/出口撤收。海上命中不能冒充岸援。推荐借034/001/022，本人借用和首通奖励由账户层按真实outcome处理。

Outcome只在权威终局产生，额外有lesson/landed_company_ids/shore_support_hits及每队company_id/transport_kind；原真实伤损、回收、未回收、舰炮弹药和资源明细继续有效。胜利允许有真实伤亡，放弃零新资源，不能将测试路线失败改写成全员生还。

## 验收记录

本轮测试及最终native/WASM、旧两版本逐字节对拍和历史浏览器证据登记在 artifacts/littoral-v3 下。候选路径和最终默认路径分开记录，不把候选当默认；完整运行结束后追加最终回执。

### 冻结候选实测

不可变native候选bd9a4be323a93260d8c829f417bd6ca1316c5e9f264f0d9ecb05823ec3abf238，WASM b7791acdd1dad31be9241705eaf94ecc007aae6d56c9e4bb866aacd276b031bd。完整Rust300/300，其中新v3规则14项，littoral合计53项。旧v1/v2共14夹具8729请求、181031363响应字节对旧db75原核完全相同；新旧合计22夹具12377请求、296497832响应字节native/WASM全同。真实Edge历史Web兼容17/17（新两栖UI属于Godot，不声称网页有该界面）。

七个真航次：landing131s、sea_control80.5s、combined131s、salvage187s、raid234.5s、混合defense180s成功；50人偏步兵驻防107.8s真实失守、零奖励。salvage实际生成全部50个不同友方身体，驻防50人同时在场。027在raid运输阶段真实发6次后损失；独立武器规则夹具验证精确12发耗尽、随后不再开火，不能将后者冒称完整实战射击记录。运输击毁无上岸身体、受损乘员、三family速度/防护/人数、3连途中/到岸保存重演均有规则门。

50人性能：100秒1000次真实0.1秒推进，原生进程IPC+观测序列化/解析p50=1.32ms/p95=1.80ms/max2.50ms，峰值55身体/12弹体；80秒存档重载11.1ms。不是GPU帧耗，也不是单独核心CPU微基准。完整实际值和默认部署复验见 artifacts/littoral-v3 的最终回执。

### 正式默认复验

正常prepare脚本最终部署native `godot/bin/runtime/696ed97942e17473/cas-sim.exe`，完整SHA为696ed97942e1747357cfc56e376d8124f9d34f88082d665a20fe61387c1900ed。使用该实际默认二进制重跑全部七航次、22夹具12377条native/WASM逐字节、14旧夹具8729条旧版本冻结，全部通过；不是仅测候选。最终聚合回执为 artifacts/littoral-v3/core-receipt.json，完整default-receipt.json，候选记录另存candidate-*。性能回执保持原bd9候选实测身份，不冒充GPU或正式二进制的另外一次计时。源代码冻结后没有数值/规则修改。
