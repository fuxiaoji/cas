# 战斗接口（本地 v1／v2）

Windows、Android 和测试驱动共享 Rust JSON 接口。Worker 接收 `{id, request}`，回复 `{id, response}`；内核返回 `{ok:true,data}` 或 `{ok:false,error}`。海图以米计，x 向东、y 向北，0° 为北，航向顺时针，速度以节计。

- `info` 返回内容协议版本和步长；`new` 接收阵营、种子、敌方风格、己方领舰位置和 `variant`（空字符串为白昼、`challenge` 为 3 对 5、`night` 为虚构夜航）；`observe` 只返回玩家视角。`campaign` 无需先开局，返回固定版本的历史档案；`playable: false` 不能当作可启动的 `variant`。
- `preview_route/route` 接收编队、机动方式、航速和多个点；`preview_reform/reform` 预览或执行重整。接纳前不能改变路线。路线响应中的实际航迹可能包括预转向直驶段。
- `aim` 接收舰、可见接触、武器及可选射向，返回合法性、炮位或发射扇区。送入 `fire` 的方向在世界坐标下锁定，窗口到期重新核验；接受命令并不等于已经开火。取消的界面手势不调用 `fire`。
- v9 的鱼雷 `aim`／`fire` 可选 `depth`（`shallow`／`deep`）、从零开始的 `mount`、1–6 的 `count`。瞄准返回可用座和实际齐射枚数，舰况提供逐座余雷和本席舰的左右舷防护。省略时使用浅航及合法单座可用枚数。
- `ai` 保存风格与三个委托类别；`suggest` 可查建议。玩家接管一个类别，其他类别不变；AI 使用相同的预览和合法性门。
- `step` 推进整数模拟秒。存档以规则版本、种子、部署、时钟和接受命令重建战局。`replay` 是只读重演；`load` 替换当前本地战局；`report` 输出己方可知事件和结局。
- v2 观测增加本舰 `classId`、`gunRange/torpedoRange`（米）、`systems` 和实际炮座射向，敌方接触无舰况。`shells` 投影授权本席可见的齐射进度和发射时固定的航迹；`torpedoes` 中敌方仅有已发现尾迹的位置及方向，无发射点和准确剩余数量。`settling` 表示演习停止接令、等最后八秒弹着。原 `cas-stage0-v1` 存档按旧瞬时炮击规则重建。
- 战情使用本席连续 `id`，音频适配可消费可选 `voiceCue`。v8 的本方武器实际发射和照明可附 `own_ship`，供引导检查本人操作。隐藏事件不会给对方制造编号空洞。部分事件有本席已知的海图坐标，发射迹象可以无坐标。
- `new` 的 `prologue` 和 `night-radar-training` 使用固定部署。序章仅允许操作第五驱逐小队，固定序幕和实时接管可由同一版本及种子重建。

这批是本地接口，不能直接公开到互联网。线上需要服务端持有权威状态、绑定身份与席位并单独处理重连、比赛版本和持久化。离线存档不是云钱包结算凭证。

## 战役接线补充

`new_campaign` 接收 `id`（通道行动 `CAMP-ALLIES-01`／`CAMP-AXIS-01`，圣乔治角 `CAMP-ALLIES-03`／`CAMP-AXIS-03`）、`difficulty`（`story`／`standard`／`challenge`）与可选本机 `seed`、`profile`。新战役冻结规则版本 `cas-campaign-v9` 和内容版本。v5 至 v8 战役按原时序读档，规则、阵营、想定或内容不匹配时拒绝读档。观察的 `campaign` 只含本席任务、标签、难度和可选公开撤离线。终局的 `result.grade` 和 `result.primary` 是本席胜利等级与说明，演习结果的 `primary` 为布尔值。

部署原生服务时，[服务器接口](../server/README.md)包装同一内核；线上战役内测目前开放圣乔治角双线，不向浏览器返回种子、重演存档或未公开命令。开发浏览器默认回环 8021；正式编译时可以用 `VITE_CAS_ACCOUNT_URL` 指定测试服务。默认内测包不配置线上服务，照常支持离线。

## 排位接线（服务端已合，前端接入中）

以 2026-11-07 合入主仓的 `server/duels.py`、`server/rankings.py`、`server/fleets.py` 为准（提交 `94833f4`）。服务以 `CAS_ENABLE_RANKED=1` 加 `CAS_RANKED_POINTS=<点表>` 启用，必须同时启用双席与 `CAS_SIM_PATH`；`/health` 用 `ranked_pvp`、`fleet_point_table_available`、`ranked_budgets` 上报。

- 点表 `data/rules/cas-competitive-points-v1.json`：`schema_version=1`、版本 `cas-points-surface-v1`、规则版本 `cas-realtime-v9`、`enabled_budgets` 仅 `[3000]`，舰价带 `profile_id`、`points` 与来源注记。服务启动时把点表清单与原生内核 `match_pool` 导出逐字段比对，并用 3000 档合法最小编队实开探针局；不一致拒绝启动。
- 编队预设：档位开放时 `GET/POST /fleets` 的条目附 `validation`（`structure_valid`、`combat_ready`、`ranked_ready`、`unavailable_ship_ids`、`cost`、`point_table_version`、`blocking_reasons`），列表附 `point_table_version` 与 `ranked_available`。入队只接受 `ranked_ready` 的预设。
- `GET /pvp/ranked/status` 返回 `season`（`id`、`start`、`end`、`duration_days=42`）、`ratings`（3000/10000 两档各自的 `rating`、`games`、`wins`、`losses`、`draws`、`rank`）、`historical_ratings`、`queue`（`budget`、`fleet_id`、`season_id`、`queued_at`、`expires_at`）或 null、`matches`（近 50 场排位对局摘要）、`available_budgets`、`point_table_version`。
- `POST /pvp/ranked/queue` 请求 `{request_id,budget,fleet_id}`，回 `{status:'matched', match:<对局摘要>}` 或 `{status:'queued', budget, fleet_id, season_id, point_table_version, queued_at, expires_at}`。匹配只在本档位、本赛季、同点表哈希、同内核哈希之间进行，按积分差与排队时长选对手；对手必须仍拥有其冻结编队且无进行中对局。排队 15 分钟（`WAIT_MS`）过期。入队即冻结编队快照，之后改预设不影响本局。
- `POST /pvp/ranked/queue/cancel` 请求 `{request_id}`，回 `{cancelled}`。
- 排位对局复用 `/pvp/matches/{id}` 全部子路径。摘要附加 `mode='ranked'`、`budget`、`season_id`、`own_fleet`、`fleet_cost`、`rated` 与仅本席的 `rating`（结算后有 `before`/`after`/`delta`/`rank`）。排位开局冻结 AI 风格：`ai` 命令被服务端拒绝，建议仍按本席合法命令生成。
- 结算：`battle` 与 `surrender` 计分（平局允许），Elo K24、400 分尺度，等分胜负 ±12；`server_fault` 作废不计分。每场结果按 `match_id` 幂等（`ranked_outcomes`），投降按排位编队规模数伤。服务故障无法恢复的对局由运维执行 `python -m server.duels --db <双席库> --void-ranked <match_id>` 作废，不发分。
- 赛季按 42 天滚动（`ranked_settings.season_epoch`），旧赛季数据进 `historical_ratings`。旧对局按开局冻结的核心哈希与规则版本继续重演。
