# 海陆空协同 v4 原核合同

仅显式 `cas-littoral-v4` 使用本模块。历史与 v1/v2/v3 保持原始创建、观察、保存和重演。航空为有来源舰体上的原创近场原型，未实现完整 CAS 航空，来源和缺口见 littoral-v4-source-notes.md。

## 创建与真实海战

`new_littoral` 沿用 v3 的 seed、mode、ships、roster、unit_condition、transport_preset、defense、company_transports、lesson 配置，version 改为 v4。未传 `company_layout` 的旧教学保留2–5个MCP、每MCP一连、每连6–10真实身体。普通出航显式 `company_layout:'multi-company-v1'`：选择2–5个MCP，每人格按唯一数值源展开2–5个独立先遣行动连，每连6–10身体；不是把9人冒称现实完整百人连。当前合法五人格组合最多21连181人，安全上限25连250友方身体；加敌方的总身体预算320、地面弹丸预算512。安全预算不等于实测出动人数。同一连不拆给不合格载舰。

普通步兵/工兵可用任何有舱位军舰；装甲与两栖战车仅 CV/LHA/APV；空输/空降/直升机仅 CV/LHA。普通艇须载舰实际距滩头海侧900m内才出发；直升机本人登记航程6–10km，可直接出发。空中与海上载具均有限HP、真实运动、毁损和人员损失。

新增船：CAS-H-USN-ENTERPRISE-1942 企业、CAS-H-IJN-SHOKAKU-1942 翔鹤；CAS-O-LHA-RETURNLIGHT 返航灯、CAS-O-APV-TIDEBRIDGE 潮桥为原创。唯一导出数值源是 tactical-profiles-v4.json，与 `littoral_catalogue(version)` 同源。容量 combat 基值 CV24/LHA28/APV30/BB16/CA12/CL10/AV14/其他8，少装20%弹药换1槽；最终以原核 catalogue 为准。

海军为真实 World，不是仿造 systems。原 route/speed/lead/detach/reform/fire/gun_cancel/aim/radar_set/searchlight/smoke 等实际执行。原炮座/炮雷装填/射界/舰体航行约束不跳过。`presentation` 返回原 projectile-fx-v1，实际多炮管与副炮仍由原 World 产生。

所有v4公开观察直接附同一次真实World的 `presentation`，桥接无需再往返请求；历史及v1–3观察不新增字段。

## 多连身份、运力与驻防

唯一表 `tactical-profiles-v4.json` / `littoral_catalogue` 记录 `company_count`、`personnel_per_company`、完整编制名及身体舱位成本。001为3×8，034为5×9，076为3×8，009为2×6，022为3×6；其余15项同源导出，不由界面复制一份表。

`company_id:'MCP-034-C01'` 至C05为稳定独立行动键，`unit_id:'MCP-034'` 始终是本人。groups.id沿用company_id，另公开company_id、unit_id、company_name；entities、transports、corpses公开所属company_id。部署、移动、攻击、搜索、技能和回收命令选择具体company_id；存在多个连时只传父unit_id拒绝歧义，同时传的unit_id必须与company_id一致。每连独立身体、弹药、载舰、目标、伤亡和回收，同人格不同连可用不同合法载舰。

仅新flag把旧容量乘6换为身体舱位：满弹DD48、BB96、CV144、LHA168、APV180；少装弹仍按原容量规则加成后乘6。每个普通陆战身体占1、装甲占4、空输占3，同一连完整分配到一艘兼容载舰；完整多连分配用有界回溯验证，不能因贪心顺序误拒合法编成。无flag容量与旧槽位冻结。

defense是真驻岸，开局地面连不占军舰投送舱、不检查停泊舰是否适合运载其军种。普通DD可以保护已驻岛的034/001，且181身体可独立驻防；不因一艘船运不下全部驻军而锁死防守。后续实际撤收逐连检查存活载舰、军种资格和真实剩余舱位，returning/recovered立即预占，不能从DD免费回收空降连或超载。正常出航已分配但仍在岸上的连保留其原运输舱预约。

终局 `result.companies` 保留每连真实HP、初始/存活身体数、回收/失踪与载舰；`result.units` 按本人汇总一次，HP按各连初始身体数加权，附companies明细。奖励只取实际回收物，不因五个连复制五份。保存仍使用原配置及带company_id的命令重建，不接受自由身体/奖励注入。

`littoral_ship_order {ship,action:'move',x,y}` 转为原 follow 航线；`aim_land` 训练真实合法炮座、不扣弹、不瞬间转舰。`littoral_support {kind:'naval',ship,x,y,queue:true}` 等同一炮座实际训练和装填后发射、与海战共享弹药。public support.naval 有 mounts、aim_state、ready_for_target、reason 和 pending_target。

## 航空

`littoral_air_order {squadron_id,action:'strike'|'patrol'|'return',x?,y?,target_kind:'ship'|'land'|'aircraft',target_id?}`。舰接触用 C*、空中目标用实际飞机ID；对地打击落点必须在真实岛内。`littoral_preview {kind:'air',...}` 只读核验，不生成飞机或伤害。

`littoral.aviation.squadrons` 是本人可操作中队；aircraft 包含实际己敌飞机。航母各3中队×3架，LHA3架支援直升机，每中队18件武器库存；在空预算24。单机出击携1武器，实际攻击消耗；未投武器返舰才入库。甲板起飞2秒/架、着舰3秒/架、整备20秒，共用串行甲板。返舰保留实际机体损伤，不自动满血。母舰损失只摧毁在甲板飞机；在空机继续存在，直到实际油尽/受击，或整局真实终局。撤离禁止静默删除仍在空己机。

F4F/SBD/TBD/A6M2/D3A2/B5N2/support_helicopter 对应本人独立图。平面速度、HP、近场18km航程、命中/伤害及压缩甲板均原创参数，不能称原书航空表已全实现。巡航只飞往点位再返航，尚非完整CAP。raid有真实NPC翔鹤及有限出击，不能操作敌中队。原始来源、变体与尚未实现表均明确登记。

## 地理、比例与高地

海图30000×25000米，岛约4.8×5.6公里；海图与陆图使用同一物理坐标，无假缩放。西岸三个实际滩头，任务、障碍、驻防、敌人与路线全部在同一岛。城镇为集中约1公里街区，建筑30–80米，街道24米；footprint 也是实际碰撞。设施公开 width_m/length_m，HQ70×50、岸炮12×12、AA14×14、仓库40×24、遗迹40×30米。未核尺寸是本原创模式的设计值，非历史舰卡来源。

仅v4陆地使用岛域局部40米网格；原路径400米不改。建筑线段相交防止70米采样跨楼；身体只在绕障碍时算路，路径缓存6秒及目标显著变化时重算。空中身体不受地面建筑封路。

`land.terrain={height_model:'inset_edge_blend_v1',elevation_zones:[{id,polygon,level,height_m,blend_width_m,cover_multiplier,label}],ramps:[{points,width,from_level,to_level}],height_los:false}`。高地40/80米，zone内边缘120米连续升坡，边界高度0、距各边≥120米为台地；坡道是推荐通行线，不额外覆盖高度。native entities/groups 的 elevation_m 为真值，cover 随真高程线性降到0.9/0.8，实际地面轻重火力伤害乘该值；舰炮、空袭、地雷不享掩护。全边缘是可走缓坡，没有高度LOS或假悬崖墙。

教学仅v4有45秒敌火准备窗，随后有限敌火正常执行；原历史与普通突袭/搜索不受此教学规则影响。

## 死亡、保存与结算

`littoral.corpses` 保存真正HP0身体/载具的稳定ID、本人unit_id、位置、朝向、pose_seed、death_tick及vehicle_id。正常HP>0撤收不算尸体。飞机损失由航空真实计数，本版不冒称飞机残骸已常驻。

Saved={version,seed,config,frame,tick,commands:[{frame,request}]}，10Hz、tick=frame/10。重演只用原配置与日志重建；不接受自由HP/result注入。真实弹药载入、消耗、返还和人员恢复由权威outcome给出。未回收/沉没/失能与零奖励失败不能由UI改成胜利。v4 与新远征 cas-adventure-v3 独立版本，原航次不静默升级。

## 最终原核验收（2026-11-14）

正式默认 `runtime/195322d160a42d32/cas-sim.exe`，完整SHA与总收据见 `artifacts/littoral-v4/final-core-receipt.json`。新WASM为a9451a…；40夹具23,118请求、932,998,654响应字节逐字节相同。旧v1/v2十四夹具8,729请求、旧v3八夹具3,648请求分别对原运行核冻结。真实Edge历史/竞技兼容17项通过；不是声称新增海陆UI运行在网页。

完整Rust库339项与原生桥接1项通过；之后新增“C01真实移动后只受自身爆炸伤、C02不变”单测单独通过1项，未虚报重新跑过完整340+1。独立真实航次包括旧单连5、新多连5、航空3：69/87身体训练完成、123身体遗迹作战真实回收、21连181身体防守180秒成功；10%条件部队确实死亡、失败零奖励；航空有限出击、NPC拦截、受损母舰真实沉没后仍在空飞机不瞬移消失。

DD驻防69身体合法，空降连下撤收后50秒仍实际留岸、公开无兼容舱位原因，保存/重演一致。181身体10Hz管道+JSON请求180样本p95约4.56ms；独立release测量实际模拟+公开观察构造p95约1.96ms（0.1秒推进）/3.54ms（0.8秒推进），JSON序列化单独约0.17/0.25ms。上述不含Godot绘制，不代表GPU60FPS；UI整体开销另由真实窗口测量。
