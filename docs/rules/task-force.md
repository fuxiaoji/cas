# 特混编成（自定义任务编队）登记

> 适用：`CAMP-ALLIES-02` / `CAMP-AXIS-02`（埃斯佩兰斯角，1 个玩家初设位置）与
> `CAMP-ALLIES-11` / `CAMP-AXIS-11`（奥古斯塔皇后湾，3 个玩家初设位置）。
> 其他可出航关卡暂未接入；不得用近似坐标补位。

## 口径

- 历史编制（1:1 舰位换舰）仍是战役星级、史实编成与历史档案的唯一口径。
- 特混编成是**独立的架空部署模式**：玩家在剧本已有的玩家编队锚点上，最多派出与该剧本玩家编队数相同（1–3）个自定义编队；可以少派，空位置保持空置。
- 每个位置最多一个编队；编队可 1 艘或多艘；全编队总点价不得超过该剧本历史玩家兵力的点价。
- 初设位置、航向、航速、领舰位置全部取自运行时已有的玩家 fleet，不新增、不近似、不改写原页阵位。
- 编队内列距使用剧本已登记的 500 码默认值（Esperance/Empress 的 `COLUMN_YD = 500`）；不再引入第二种间距。
- 敌方编制、阵位、航向、航速、目标与特例完全不动；只替换玩家侧的历史编队。

## 内核落点

| 项 | 落点 |
| --- | --- |
| 起始载荷 | `campaign::live::Start.groups: Option<Vec<GroupPick>>` |
| 编队组 | `GroupPick { position, ships }`；`position` 为玩家历史编队序号 |
| 锚点 | `campaign::fleet::GroupAnchor`，由 Esperance/Empress 的 `columns()` 生成 |
| 生成 | `campaign::fleet::spawn_groups`：校验位置/空编队/同阵营/点价，按锚点列队 |
| 位置枚举 | `campaign_fleet` 返回 `positions` 与 `taskForceSupported` |
| 记录 | 不计历史星级、星级奖励与史实编成；客户端以 `campaignTaskForce` 跳过 `recordCampaignResult` |
| 回放/存档 | `groups` 随 `Start` 存档；旧存档缺省为空，继续走历史编制 |

## 验收

- 引擎 7 项舰队测试与全量 91 项通过：单编队锚点、单舰战列舰、空位置、重复位置拒绝、超预算拒绝、未接入关卡拒绝、位置与支持标志。
- 浏览器：`browser-taskforce`（皇后湾 3 位置、2 个编队、第 2 位置空置、两处分位锚点）与 `browser-taskforce-esperance`（1 位置、单舰北卡罗来纳）通过；历史 `browser-esperance` / `browser-deployment` / `browser-campaign-modes` / `browser-lobby` 继续通过。
- 原生/WASM 使用同一 `src/campaign/fleet.rs` 与 `Start`；WASM 重建后浏览器对局通过。

## 边界

- 圣乔治角（2 个玩家编队，2,375 分）、塔萨法隆格（3 个，9,300 分）、库拉湾（1 个，5,100 分）与萨沃岛（多编队）尚未接入；未接入关卡 `taskForceSupported=false`，前端页签禁用，不得在前端伪造位置。
- 历史舰位候选使用剧本舰卡（class card），战斗舰名可能显示舰级名（如“弗莱彻级”）；身份级名称传递需要扩展 `GroupPick` 的舰名载荷，另批处理。
- 特混结果页已跳过历史结尾演出与星级奖励；结果页的浏览器断言留待下一批补。
- 未新增任何原页没有的舰、位置、间距或表值；特混编成不改变历史档案的“可出航/已核验”状态。
