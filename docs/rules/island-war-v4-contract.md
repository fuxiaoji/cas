# cas-island-war-v4 公共契约

本模式为用户授权的原创海岛玩法；历史 CAS 规则、舰卡、原 PDF、参考项目和已发布 island-war-v1/v2/v3 均不修改。存档顶层 `version` 为 `cas-island-war-v4`，观察 `island_war.version` 同值，`littoral.version` 保持 `cas-littoral-v4`。

唯一客户端目录由 `island_war_catalogue(version=cas-island-war-v4)` 导出至 `godot/data/island-war-v4.json`，包括27本人、54具体枪型、有限弹匣/备弹/车辆、实际连数。不得把设计台账作为另一份运行时目录。

`island_home_preview` 是无副作用操作，输入 `version,seed,hq_level(1..5),buildings:[{id,kind,cell:{x,y},level,hp}]`，可另带 `candidate:{id,kind,cell}`。输出 `island_war.placement`、`littoral.land.{bounds,polygon,terrain,buildings}`、`construction_grid.{origin,cell_size_m,bounds,buildable_cells}` 及 `candidate.{valid,reason,world_position}`。设施返回 `x,y,world_position,terrain_buildable`；旧占用格即使不再适合新建也保持可观察位置。

建设网格固定原点 `(13880,12460)`、边长120米，格中心 `origin+(cell+0.5)*120`；HQ升级只扩展可用负格/新格，旧地址不漂移。HQ1为3200×4400米，每级宽增1200米、高增1400米，HQ5为8000×10000米。战场 `island_level=HQ等级`、相同 seed 使用同一 `Geometry/Terrain` 生成器；米制原值进入导航、占位、视线和射程。`placement` 仅负责设施归一化，不能压缩世界坐标。v4允许归一化值超出0..1后再以真实岛多边形校验，支持外围新格；旧版0.05..0.95边界不改。

`littoral_vehicle_order/preview` 使用稳定 `vehicle_id`。`move` 移动；`attack` 移动并按真实视野自动选敌；`face` 原地面向指定 `x,y` 并将自动直射限制在该方向120度扇区，空地转向不消耗炮弹；`fire_at` 原地攻击落点65米内的已知有效敌人/设施，目标必须在真实射程内且武器就绪，无目标或装填中拒绝。伤害仍由真实有限库存、弹道、散布、碰撞、护甲和掩护裁决。

022坦克 `min_crew=0/shared_consciousness_control=true`，身体全灭不能删除独立载具；可移动、开火、撤收，按独立耐久/真实回收结算。087连级攻击只移动自行炮至1100米停距，手枪身体原位自卫；显式身体移动、撤收与登载仍允许。

27本人所有女性身体基础HP为既有原创基准的4倍，敌我对称；目录 `body_stats.baseline_hp/health_scale/hp` 如实导出，成长及初始整备百分比随后作用。不改变舰船、塔、载具HP。022/103/304/305在手动状态也按已知威胁逐身体走到车后，最多两名侧探，受击回撤；玩家身体hold约8秒、其他独立身体命令约15秒接管。真实车体截挡直射，范围炮击仍可伤及后方人员。

普通艇只在真实海岸外8米卸载，再由身体上岸步行至内陆rally；回收艇同样在岸外接应。两栖车可自行进入内陆，103/304/305水速32/40/24米每秒，陆速72/105/76米每秒，再乘当前真实地形倍率。外海及非ford/road的河流均按水域速度；桥与道路按陆地速度，`movement_domain`使用相同判定。航空仍受9000米真实投送航程约束。地形包括海滩、悬崖、森林、灌木、沼泽、曲折河流、三处登记渡口、低地、双高地、坡道、24米跨河道路，参与原核移动/视线/掩护。

`terrain.features[*].polygon`、`terrain.elevation_zones[*].polygon`、`terrain.ramps[*].polygon` 均为闭合区域；ramp的兼容`width=180`不是给轮廓每条边再扩180米。只有`terrain.roads[*].points`为路径折线，按`width=24`解释道路宽度。高地提供区域高度及掩护、悬崖阻挡直射，连续高度剖面弹道仍见source notes边界。

入战可一键 `island_autonomy(enabled=true)` 覆盖实际海陆空部署、火力与撤收，并解除旧载具手动接管。新v4航母初始化为 `cas-carrier-ops-v3/high`。7艘尚属 `source_only` 的原页新增舰仍不能被伪造为可用编成。

六训练使用独立 `tactical-training-v4.json`；登陆准备期60秒、其余40秒，敌岸防伤害按登陆0.35、武器/炮兵0.55、后续0.7递进。只有真实终局和真实机制checks均完成才可记课程成功；借用演习不写账户、不发奖励。
