# cas-island-war-v2 并行接口

本文件登记本轮原创新版本接口。旧v1/v4均冻结。字段单位为米、秒、HP；坐标均为原核世界坐标。

新局沿 `new_island_battle`，显式 `version:cas-island-war-v2`。原平铺 ships/roster/unit_condition/transport_preset/company_layout/company_transports 保留；mode=raid/defense/exercise。island沿v1的npc_id/island_level/forts/storage/unit_growth，并增加deployables数组。exercise必须另传真实 `defender:{ships,roster,unit_condition:[],unit_growth:[],company_transports:[]}`，不回退NPC模板；该模式全部资源／整备／修复与奖励只在隔离模拟中存在，不写账户。

目录：`{op:island_war_catalogue,version:cas-island-war-v2}`；不带版本仍返回冻结v1。Rust导出 `godot/data/island-war-v2.json`。每card保留id/name/role/nato_type/company_count等，新增designation/personnel_per_company/combat/transport/transport_options/ability。22本人包括088霜铃（近卫第88伞降旅，5×10）和006夜枭（第6海上空中突击营，1×6，六身体各驾驶一机，不额外复制人员）。

`island.deployables:[{id,kind,x,y}]` 的初始位置采用与forts相同的归一化岛屿包围框坐标，允许海区范围−0.6至1.2；kind为land_mine/beach_position/sea_mine，必须分别落在合法地面／近岸陆地／海水。raid/exercise归守方，defense归玩家。临场布设使用 `{op:island_place,company_id,kind,x,y}`，这里x/y是实际世界米制坐标，消耗真实有限工程工具、检验距离和通行。

观察保持 `littoral.version:cas-littoral-v4`、`naval_world:true`；顶层version与island_war.version是v2。`island_war.exercise`标记隔离演习。保存版本v2，config保留完整双方；录像仍 `{op:replay,save|serialized,tick}`，独立只读游标，不改live、不结算。

## 原核地形

`littoral.land.terrain` 保留v1的真实bounds/连续height描述，并追加：

```
version: tactical-terrain-v2
features:[{
 id,kind,polygon:[{x,y},...], elevation_m,
 movement:{infantry,armor,amphibious,air},
 vision_multiplier, cover_multiplier
}]
```

kind为beach/cliff/swamp/landing_zone/river/ford/forest/bush。movement是实际速度系数，0表示该类不可通行；重叠区域取最严格限制，ford覆盖river以允许实际涉渡。air忽略地面通行。polygon已是实际世界米制多边形，Root只投影此数据，不另随机一套。沙滩／登陆场留出合法岸点与展开空间；悬崖必有绕行通道。灌木森林影响实际探测、锁定与直射范围。open-intel可查看已发现敌人数据，不代表无视遮蔽自动开火。

## 实体与动画

land.entities沿 id/unit_id/company_id/side/kind/x/y/hp/max_hp，追加：physical_class、vehicle_id（有实际作战载具时）、heading、velocity、phase、altitude_m、visible、knockback。phase含embarked/inserting/parachuting/active/returning/recovered/dead。006的六个actor就是六个驾驶身体及对应作战机，不能在旁边另画六个免费地面人。普通步兵的transport在littoral.transports，登陆后不留下免费作战车；两栖车／武直使用同一actor跨水陆或空中。

每身体另外公开 `collision_radius_m`（步兵0.45／车3／武直6米）、`avoidance_radius_m`、`steering_wait_frames`。原核按实际身体中心处理本帧前后轨迹及相对速度最近距离，敌我同层互阻；空地分层。不可用屏幕五列或挪位替代。088的空降身体保守预约实际落点，横向间隔约8米，下降8–11秒分层；其落地预约与武直空中占位分开。回收逐身体检查：到岸90米内才可登艇，武直／两栖到载舰120米内才回收，未到者留在现场，不按连质心整连收回。撤收时取消进攻散开偏移。

新目录 `limits` 给出舰数／人格／身体／连／弹药实体／时长上限；技能 `radius` 与 `duration_s` 为实际作用范围和持续时间，不沿用通用350米。人格编制符号旅X／团III／营II；场内行动连的group符号I。

运输观察有id/company_id/unit_id/side/kind/vehicle_id/x/y/goal/heading/velocity/hp/max_hp/phase/personnel_count/capacity，明确transport_role=insertion_only/recovery_only/both/combat_same_actor。088落地途中phase=parachuting、真实高度下降、无法开火且易受防空打击，撤离只能艇。

真实舰炮shots/projectiles提供：caliber_mm、mount、barrel、shell_count、launch_point、impact_point、flight_seconds、blast_radius_m、damage、knockback_m。每个真实炮管一枚；不同口径原创陆战爆炸差异不改海战原表。实际impact事件附affected_bodies和knockback状态，renderer不猜伤害或自行生成战果。

`island_war.deployables` 返回实际位置、side、kind、hp、active、charges或剩余触发数；地雷与水雷由真实实体接近触发，滩头阵地具有真实HP与掩护范围。

现有海军route/fire/ai/radar/air中队命令复用。地面仍用littoral_deploy/littoral_order/littoral_ability；新公司使用稳定`MCP-xxx-Cnn`，defender公司观察用`D-MCP-xxx-Cnn`避免自攻自守同人格混淆，unit_id仍同一本人。玩家只能指挥攻击方；防守AI使用守方观察，不能经敌方UI命令控制。
