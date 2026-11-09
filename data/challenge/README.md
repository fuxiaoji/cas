# 挑战模式关卡数据

`stages.json` 是挑战模式（架空内容）的唯一关卡源。客户端不直接读取它：
`scripts/challenge-stages.py --write` 校验后生成
`client/src/activities/challenge-stages.ts`，Harbor 的挑战页只使用生成文件。
改动 JSON 后必须重跑脚本并提交生成结果；`--check` 会拦截漂移。

## 边界

- 挑战模式是**架空**内容，不映射历史战役的编制、阵位、航速、胜负条件或史实预算，也不计历史星级、不进入战役目录。
- 现有引擎的 `challenge` 变体固定玩家 3 舰（2 DD + 1 CL）对敌方 5 舰，并冻结在 v9 时序。
- 本批只开放 1–3 关（仅 DD/CL）。第 4–5 关包含战列舰，登记为 `blocked`，
  不进入可出航列表；未实现项不得用近似编制冒充。
- 关卡奖励沿用现有挑战首通/周复战规则；关卡进度只记录通关，不新增货币。

## 字段

| 字段 | 说明 |
|---|---|
| `engine.variant` | 必须为 `challenge`；当前引擎没有别的 3 对 5 入口 |
| `engine.player_slots` / `enemy_slots` | 当前引擎固定编制；数据只作展示与校验 |
| `stages[].status` | `playable` 或 `blocked` |
| `stages[].leader_slot` | 0–2；对应玩家三舰位，决定开局领舰 |
| `stages[].profile` | `coord` / `gunnery` / `torpedo`；作为出击时的本席 AI 风格 |
| `stages[].unlock_after` | 前置关卡 id；首关为 `null` |
| `stages[].composition` | 目标编制；可玩关卡必须与当前引擎槽位一致 |
| `stages[].blocker` | `blocked` 关卡必填；写明缺的引擎能力 |
| `stages[].evidence` | 可玩关卡的实测种子、敌方 AI 与结果，供回归复核 |

## 后续接入战列舰关

需要引擎先提供：

1. `challenge-roster-v1`：`new` 命令接受本席舰船列表/槽位，而不是固定取演习前 3 舰。
2. `challenge-enemy-template-v1`：逐关敌方编制与 AI，而不是固定 5 舰。
3. `challenge-field-v1`：按关卡指定海图尺寸/初始距离（主力决战需要更大接敌距离）。

在这些能力落地前，`challenge-04` / `challenge-05` 保持 `blocked`，前端只显示原因。

### 可执行实施顺序（需其他 agent/scope 接手）

1. **内核**：在 `src/world.rs` 的 `challenge` 分支把固定的
   `["fletcher","cleveland","fletcher"]` / 敌方五舰改为从 `Start`（或新的
   `ChallengeSpec`）读取玩家/敌方 identity 列表；保留 `realtime.rs` 中 challenge
   的 v9 冻结，先只加“选舰不选时序”。
2. **命令**：`src/lib.rs` 的 `new` 接受 `challenge: {ships:[...], enemy:[...], field?}`；
   校验同阵营、点数/槽位、舰种（前 3 关仍禁止 BB，4–5 关才允许）。
3. **客户端**：`client/src/port.ts` 的 `PortLaunch` 增加 challenge 载荷；
   `client/src/main.tsx` 的 `launchFromHarbor` 原样透传（该文件不在本 agent scope，
   必须先写建议再改）；`ChallengeLadder` 从 stage data 生成载荷。
4. **数据**：`stages.json` 为 4–5 关补 `player_slots` / `enemy_slots` / `field`，
   把 `status` 改为 `playable` 前必须先在 `evidence` 里记录真实种子和战果。
5. **验收**：新增引擎单测（BB 槽位、点数/阵营拒绝、v9 重演）、WASM parity、
   `browser-challenge-stages` 扩展第 4–5 关，并重跑历史浏览器回归。
6. **不做**：不得用 `new_campaign` 的历史关或特混编成冒充挑战 BB 关；不得改
   `server/catalog.json`、立绘或历史预算来让 BB 关“看起来能打”。
