# 航母：先选自己负责多少

双击项目根目录的 `CAS-Carrier-Academy.cmd`，打开隔离的航母练习。初始暂停，右侧“航母”按钮可选档位；选好后点顶部“继续”。不会修改正常账户。

| 档位 | 你负责 | 航母负责 | 画面中需要用的卡 |
| --- | --- | --- | --- |
| 高自动化 | 继续战斗，必要时召回 | 防空、选择公开敌舰与陆上目标、选机、起降、回收整备 | 每舰一张航空支援卡 |
| 中自动化 | 拖卡指定各舰目标 | 选择兼容飞机、排甲板、执行任务和回收；仍自动防空 | 每舰一张航空支援卡 |
| 低自动化 | 具体中队、波次和在空任务 | 执行命令、自动飞行、盘旋、投弹、返航与着舰 | 联队卡、中队卡、在空卡 |

高档先试：选择高档并继续，观察飞机真实起飞、盘旋或打击。高档不要求先点选中队。

中档只用一张卡：拖“企业 · 航空支援”或“翔鹤 · 航空支援”到公开敌舰，或岛上实际敌人附近（650米区域），或海面。对陆指定的是一片支援区域，航母可优先攻击其中其他敌人，并不保证点杀鼠标下的单个身体。拖海面是盘旋防空，拖岛上敌人是对陆支援。超出航程、无兼容机型、空白陆地会解释并拒绝，不扣资源。友军距离投弹点不足350米时暂缓/取消投弹；没有新生成的免费飞机。指定新目标时旧打击编队先返航，下一波按新目标执行。

点击右上陆图可切换主图；**同一张航空支援卡直接拖到陆图敌人**，不必切回海图。高档优先处理公开的有效航空支援标记、威胁岸上友军的敌人，再处理其他目标。鱼雷机不会参与对陆轰炸。当前陆战的可见范围、身体、建筑、标记和实际伤害仍由陆战核心裁决。

拖航空支援卡回本舰（600米内）即可召回全联队并停止本舰新派遣。回收和整备要等真实完成。重新选择高档，或为本舰指定新目标，可恢复派遣。总撤收期间航空停止出击并返舰；选档、指定航空目标不会关闭陆军托管。档位互换不补充飞机、燃油、血量或武器。

只有需要细调时再选低档：中队卡排下一波，同队再次拖动替换待命；在空卡改变当前波次；联队卡拖回本舰全召回。低档不会自动补派新的中队。切换高、中档会清除旧待命与手动接管，已有飞机继续真实飞行；中档的新目标会召回该舰旧的对舰/对地打击波次。飞机离舰后不能悬停，警戒和等待着舰都盘旋耗油。

卡牌短句显示本舰正在做什么、为什么等待；点击卡牌查看全文。右侧航母按钮始终显示当前档位。没有可见目标、甲板忙、友军过近、整备中、燃油不足或武器耗尽，都可能使飞机暂不出击。

## 独立 agent 操作契约

无需读实现。使用逐行 JSON 的 `target-carrier/release/cas-sim.exe`，每条请求返回一行 JSON。此接口的 `new_littoral` 保留旧版默认，必须在创建后执行第1步选档才出现 `carrier_ops`；桌面练习启动器已代为选择高档。先创建练习：

```json
{"op":"new_littoral","version":"cas-littoral-v4","mode":"raid","seed":42,"ships":[{"id":"CAS-H-USN-ENTERPRISE-1942","hp":100,"ammo":100},{"id":"CAS-H-IJN-SHOKAKU-1942","hp":100,"ammo":100}],"roster":["MCP-034","MCP-001"],"transport_preset":"combat","unit_condition":[],"defense":[]}
```

1. 选档：`{"op":"carrier_automation","version":"cas-carrier-ops-v3","level":"high"}`。`level` 可为 `high`、`medium`、`low`。
2. 观察：`{"op":"observe"}`。查看 `data.littoral.carrier_ops.automation` 中的 `level`、`player_responsibility`、`next_action`、`carriers[].status`；飞机与库存来自同一观察的 `aviation`。`ships` 是本方船，敌舰使用 `contacts` 的公开接触ID；陆地敌人来自 `land.entities` / `land.buildings` 的存活敌方行。
3. 推进：`{"op":"step","seconds":1}`。飞机必须经过真实飞行过程。不要把下令成功等同于已经命中或已回收。
4. 中档目标示例：`{"op":"carrier_mission","carrier":1,"action":"strike","target_kind":"land","x":12080,"y":12280}`。坐标取当前公开目标；本例仅适用于上述固定练习的初始陆上目标。对舰补 `target_kind:"ship",target_id:"公开接触ID"`；防空使用 `action:"patrol"` 和海面坐标。指定目标会自动进入中档。
5. 下令前可用相同字段的 `op:"carrier_mission_preview"` 检查合法性，预览不写指令日志、不产生伤害或扣资源。
6. 召回：`{"op":"carrier_mission","carrier":1,"action":"return"}`，推进直到该舰 `airborne` 为0；本舰保持停止派遣。
7. 低档中队示例：`{"op":"littoral_air_order","queue":true,"squadron_id":"从aviation.squadrons取实际ID","action":"patrol","x":7000,"y":11000}`。先等实际起飞完成，再用 `{"op":"carrier_air_order","scope":"flight","squadron_id":"同一实际ID","action":"patrol","x":7200,"y":11000}` 改在空任务；用 `{"op":"carrier_air_order","scope":"wing","carrier":1,"action":"return"}` 全召回。`flights.mission:"strike"` 也可能是自动防空拦截，应联查 `aviation.aircraft.target_kind` 区分 `aircraft`、`ship` 和 `land`。
8. `save` 后以 `{"op":"load","save":返回的data}` 可恢复；模式、目标和资源通过原指令重演，不伪造完成。

这是显式的新航空控制层，基于当前近场航空续作。完整原版 CAS 的迎风、高度、事故、实际航空队和备用母舰着舰仍未实现。旧v1/v2航母历史不自动升级。
