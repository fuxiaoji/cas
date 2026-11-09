# 验证记录

## 2026-11-09｜军需处四柜台与军港征募全屏页

- 结论：`Harbor` 的 `recruit` section 已改为「军需处」，四柜台可用；「军港征募」是独立全屏 overlay，左卡池 / 中主视觉 / 右 UP·概率·保底·兑换 / 底部征募 1/10 全部接入。抽卡概率与接口、服务端经济、舰卡、音频与 challenge/ranked 点价均未改，未新增货币，未提交；本批实现也未编辑 `ai-shop.ts` / `data/ai` / `server/catalog`（6 条 AI 数据由并行 agent 落地）。
- 军需处：[Quartermaster.tsx](client/src/screens/quartermaster/Quartermaster.tsx) + [quartermaster.css](client/src/screens/quartermaster/quartermaster.css)。舰船柜台提供军港征募入口与 4 舰型图鉴；补给配给调用既有 `buyWeeklyTicket` / `claimWeeklySupply`；AI 战术读 `AI_SHOP` 的 6 / 6 条投影并防御式渲染 `role / axes / fit / risk`；礼包与兑换调用既有 `getGunnery`（6 舰队勋章），联机礼包/舰船兑换只作只读说明。钱包显示信用点 / 舰队勋章 / 常驻券。
- 军港征募：[RecruitScreen.tsx](client/src/screens/recruit/RecruitScreen.tsx) + [recruit-screen.css](client/src/screens/recruit/recruit-screen.css)。本地抽卡仍走 `port.drawRecruit`，双池独立、85/15、十抽轻巡保底、重复转勋章与 `RecruitArrival` 到港均沿用旧逻辑；概率、记录、兑换为抽屉，底部固定征募栏，Esc 先关抽屉再关全屏，返回按钮回军需处。
- 共享层：[economy.tsx](client/src/widgets/economy.tsx) + [economy.css](client/src/widgets/economy.css) 提供 WalletBar、ShopCard、Drawer、PityMeter 与 `cas-btn`，Harbor 头部钱包也改用 WalletBar；军需处为白天干船坞纸卡/黄铜/盖章，征募为夜间军港/探照灯/信号灯，均使用 `--cas-*` token。本机 `GrowthPort` dock 与 `Mailbox` 文案同步为「军需处」，联机 dock 保留「征募与补给」以对应未改的 `OnlineSupply`。
- AI 6 卡状态：另一 agent 已把 [ai-shop.ts](client/src/ai-shop.ts) 扩到 6 条（evo-screen / evo-torpedo / evo-gunnery / evo-brawler / evo-kiter / evo-denial，全部 provisional）；本次只读该文件，未编辑。三轴枚举（range: near/mid/far、maneuver: brawl/screen/kite、torpedo: direct/deny/support）已显示为相对刻度与「近距/中距/远距、乱战/屏护/风筝、直击/封路/支援」文字。
- 验收：
  - `node node_modules/typescript/bin/tsc --noEmit -p .` 通过；`node node_modules/vite/bin/vite.js build` exit 0（仅既有 chunk-size 警告）。
  - 新增 `node tests/browser-shop.mjs` 通过：四柜台、钱包三项、周券（500 信用点 → 常驻券 5001）与周补给（+500 / +3 券）、AI 6 卡全部显示价格/解锁/provisional/三轴/定位/适配/风险，采购 evo-screen 扣 800、6 勋章兑换炮战 AI 后勋章 14、刷新后钱包 4204 / 勋章 14 / 已拥有保持；券不足时按钮显示「常驻券不足」并禁用；740×360 `overflow=false` 且底部采购条可见、采购单为底部 sheet。凭证 [browser-receipt.json](client/artifacts/client/shop/browser-receipt.json)，截图同目录（`quartermaster-1360.png`、`quartermaster-ai.png`、`quartermaster-740.png` 等）。
  - 新增 `node tests/browser-recruit.mjs` 通过：双卡池、标准池 85/15、pity 9 的单抽保底到港（pity 归零、history 1）、记录回看不重抽、UP 池切换（轴心舰队 · UP）、概率/记录/兑换抽屉、十连（常驻券 20 → 9、history 11、batchSize 10）、Esc/返回关闭、740×360 `overflow=false` 且抽屉为底部 sheet。凭证 [browser-receipt.json](client/artifacts/client/recruit/browser-receipt.json)，截图同目录。
  - 回归 `browser-ai-shop` 通过（6 卡、解锁/扣券/重载/演习与战役进战斗）；`browser-lobby` 通过（4 dock、11 关、编成、剧情/序章）；`browser-esperance` 通过（CAMP-ALLIES-02 9 舰/1 编队/决定性胜利）。
- 边界：母港到军港征募为「母港 → 军需处 → 舰船 → 进入军港征募」，未新增第五个母港 dock；联机征募仍走 `OnlineSupply`，本次未改；新 AI 的 `fit` 是真实 headless 验证均值，不是平衡承诺；`browser-offline.mjs` 仍使用旧的 Harbor 征募按钮，属旧脚本，未纳入本批回归。

## 2026-11-09｜六套 evolved doctrine：近战 / 风筝 / 雷网与商店扩至 6

- 结论：[evolved.json](data/ai/evolved.json) 已从 3 条扩到 6 条，新增 `evo-brawler`（绞肉 · 近战乱斗）、`evo-kiter`（拖刀 · 远距风筝）、`evo-denial`（雷网 · 封走位），全部 provisional、常驻征募券、真实 headless fitness；内置 `coord`/`gunnery`/`torpedo` 出招路径、`builtin-orders` 与 full-match hash 逐字节不变，三条旧 evolved 的基因/fitness 保持基线。未改舰船卡、`data/ships`、portraits、audio、challenge/ranked 点价，未提交。
- 目标与 fitness：[ai_evolve.rs](src/ai_evolve.rs) 新增 Brawler/Kiter/Denial objective 和 `play_traced` 实时指标。Brawler 用 3 km 内实伤（每次 `damage` 事件按着弹点与最近本舰距离归因）+ 3 km 内接敌秒 + 击杀；Kiter 用 6 km 外实伤 + 6 km 射程维持舰秒比 + 存活/巡洋存活；Denial 用鱼雷直航轨迹对敌当前航向投影的 450 m 扇面覆盖（CPA 必须为正、在鱼雷剩余航程内）+ 被覆盖敌舰数 + 威胁后 90 秒实际转向度 + 扇面宽度 + 小权重命中。三条 objective 的 fitness 均由 `play_traced` 的真实 `World::advance` 对局算出，`basis=ga`；Denial 指标本轮可用，未使用 `hand_authored` 回退，ai-report 仍逐条记录 basis。
- 训练：population 6、generations 3、elitism 2、mutation 0.35、crossover 0.6、rng_seed 6106、train seeds 6106 coord / 6107 gunnery、validation seeds 6111 torpedo / 6112 coord / 6113 gunnery、seats 0/1；Brawler/Kiter 在 doctrine envelope 内搜索（brawler 射程 2600–3200、航速 29–32、撤退 0.08–0.12；kiter 射程 7400–8000、航速 29–32、撤退 0.32–0.40、T 头 0.6–1.0），避免 GA 产出与商店描述相反的风格。三条旧 objective 的 RNG 流与结果未变。
- 产出：6 profiles 的验证均值（同 objective 6 场）为 screen 282.57 / torpedo 217.56 / gunnery 1692.16 / brawler 822.03（内置 torpedo 656.03）/ kiter 846.64（内置 gunnery 234.30）/ denial 1200.32（内置 torpedo 831.06）；brawler 最终射程 3030 m、航速 30、撤退 0.12；kiter 射程 7630 m、航速 32、撤退 0.36、T 头 0.70；denial 雷击占比 0.95、torp_angle 143、coordination 0.87、screen 0.75。training-log 与 ai-report 记录 config、seeds、history、每场 match 和 doctrine 指标均值；shop-merge 6 条。
- 商店/服务端：[ai-shop.ts](client/src/ai-shop.ts) 的 `AiShopEntry` 增加可选 `role/fit/risk/axes`（near/mid/far、brawl/screen/kite、direct/deny/support），旧三条补齐，新三条 900/1100/1200 常驻券，unlock `CAMP-ALLIES-05` / `CAMP-ALLIES-11` / `CAMP-ALLIES-10`；`CAMP-ALLIES-06` 仅有 crosswalk 档案、无可运行关，按约定把 kiter 改用可通关的 `CAMP-ALLIES-11` 并在 ai-report 登记。[server/catalog.json](server/catalog.json) 的 `ai_profiles` 改为严格 6 条（3 旧 evolved + 3 新，不再并列旧手游 6 条 AI），[import_catalog.py](server/import_catalog.py) 从 shop-merge 投影 6 条。[battle_pve.py](server/battle_pve.py) profile 枚举与 `AI_UNLOCK` 同步 6 条（内置 coord/gunnery/torpedo 不再依赖旧手游 AI 商品）。
- 验收：
  - `cargo test --release --locked` 123 passed / 0 failed，含新 objective 的 doctrine 指标测试、六 profile 训练测试、旧三 profile 基因基线断言；`builtin_orders_stay_identical_to_the_recorded_baseline` 与 `builtin_full_matches_stay_frozen` 均通过。
  - 服务端 34 项全过（`test_accounts` 9、`test_account_progression`、`test_battle_pve`、`test_fleets`、`test_ranked`、`test_duels`）；`test_accounts` 覆盖 6 条逐条解锁/扣券 6000→100、错误币种、重复购买、request_id 幂等、重启、重登；`test_battle_pve` 以 evo-torpedo + 种子 6150 在标准/挑战均取决定性，并覆盖未解锁 403。
  - `tsc --noEmit` 通过；`vite build` 通过（仅既有 chunk-size 警告）；`scripts/check-ai-shop.py` 校验 client 6 条与 catalog/ai-report 的 id/name/description/unlock/cost/currency/provisional 一致。
  - `cas-sim` 三条新 doctrine 各一场 evolved vs builtin 的 save+replay：brawler 6106 vs coord 5:3（tick 2168）、kiter 6112 vs gunnery 3:0（tick 2708）、denial 6111 vs torpedo 5:2（tick 2359），均 `replayMatches=true`；证据在 [evidence](data/ai/evidence/)。
  - WASM 重建（`27406A90C5CA8AFFE5BE9C55AE4A6778303D36B1B4D69CF71F591A266E696C5C`，3,602,934 bytes），24 组原生/WASM parity 全过（含 3 条新 doctrine），`nativeWasmCanonicalMatch=true`、`replayMatch=true`。
- 边界：Denial 覆盖的是敌当前航向投影，不是完整意图；Brawler/Kiter 多舰同秒命中用最近本舰距离归因；Kiter 可能保持 6 km 外纯炮战、不发射鱼雷；新三条未接入排位/双席白名单；`server/battle_pve` 可出航 Stage 仍为 02/03/11，05/10 的解锁进度本轮由测试种子与本地战役覆盖，线上 PvE 注册这两关留作后续；UI 页面由并行 agent 做，本批只提供共享 6 条数据；未 commit。

## 2026-11-09｜evolved AI 商店上架、购买持久化与战斗接线

- 结论：[shop-merge.json](data/ai/shop-merge.json) 的三条 provisional evolved 战术（evo-screen 800 / evo-torpedo 900 / evo-gunnery 1000 常驻征募券）已真正接入商店、账号与战斗，不再只是清单。舰船卡、portraits、audio、AI 训练/evolved 权重、challenge/ranked 点价均未改，未新增货币，未提交。
- 服务端：[catalog.json](server/catalog.json) 的 `ai_profiles` 由 6 条增至 9 条，新增三条带 `currency:"recruit_ticket"`、`unlock:"campaign:CAMP-ALLIES-02/03/11"`、`provisional:true` 与中文描述；[import_catalog.py](server/import_catalog.py) 从 shop-merge 投影同样字段。[accounts.py](server/accounts.py) 的 `/shop/purchase` `kind:"ai"` 按服务端目录币种扣 `standard_tickets`，校验 `campaign_progress` 至少一胜（0 星不解锁），已拥有/重复购买 400，同一 request_id 幂等；资产写 SQLite，重开服务与重新登录均保留。新增 `test_evolved_ai_profiles_are_catalogued_and_purchased_with_tickets` 覆盖锁定拒绝、错误币种、800+900+1000 扣券、防重、幂等、重启与重登。
- 客户端：[ai-shop.ts](client/src/ai-shop.ts) 提供三条商店投影与本地购买；[Harbor.tsx](client/src/Harbor.tsx) AI 战术室显示价格/解锁条件/provisional/征募券不足与未解锁原因，购买即时同步本机 `PortState.profiles`。[engine.ts](client/src/engine.ts) 把 evolved id 纳入 `Profile`/`profileNames`；战斗、演习设置、关前编成、特混与母港预设下拉按已拥有过滤，未拥有项禁用并标“（未拥有）”。联机 [OnlineSupply.tsx](client/src/OnlineSupply.tsx) 同步展示三条 evolved，价格走常驻征募券、解锁读 `/me` 的 campaign_progress，购买用返回 meta 刷新。
- 战斗：本地演习经 `new` 传 `profile:evo-screen` 与 `profile:evo-torpedo`，战役经 `new_campaign` 传 `profile:evo-gunnery`，三次均进入真实海图并在 AI 面板选中；存档 JSON 的 `profile` 分别为 evo-screen / evo-gunnery，刷新重载后从进行中战局恢复仍保持。`Ai::validate` 未改。
- 验收：
  - `cargo test --release --locked` 121 passed / 0 failed（Rust 未改）。
  - 服务端 34 项全部通过（`test_accounts` 9、`test_account_progression`、`test_battle_pve`、`test_fleets`、`test_ranked`、`test_duels`），`CAS_TEST_DUEL_SIM_PATH=target/release/cas-sim.exe`。
  - `node node_modules/typescript/bin/tsc --noEmit -p .` 通过；`node node_modules/vite/bin/vite.js build` 通过（仅既有 chunk-size 警告）。
  - 新增 `browser-ai-shop` 通过：母港 → 征募与补给 → AI 战术（3 卡、价格、provisional、关闭的 gunnery 未解锁原因），740×360 `overflow=false`；购买 evo-screen 扣 800 → 4200，刷新后仍在且不重复；通关 CAMP-ALLIES-11 后购买 evo-gunnery → 3200；母港预设选 evo-screen 出航，战斗 AI 面板选中且 evo-torpedo 选项禁用；存档重载保持 evo-screen；战役 CAMP-ALLIES-02 编成选 evo-gunnery 出航并通过 `new_campaign` 生效、重载保持；最后购买 evo-torpedo（→2300）并以它出航演习。凭证 [browser-receipt.json](client/artifacts/client/ai-shop/browser-receipt.json)，截图同目录，740 截图 `ai-shop-740.png`。
  - 回归 `browser-lobby` 与 `browser-esperance` 通过（母港/战役大厅/编成屏/740 与 CAMP-ALLIES-02 决定性胜利）。
- 边界：三条 evolved 仍标 provisional；联机 AI 商店已有页面与接口但本批浏览器凭证为离线本机商店（服务端购买由 unittest 覆盖）；排位/双席的 evolved AI 白名单未开放；未改 `server/rankings`、`data/ships`、portraits、audio、`src/ai.rs`/`ai_evolve.rs`，未 commit。

## 2026-11-09｜AI 恢复：builtin-safe 基线 + 三条 evolved 风格

- 结论：HEAD `src/ai.rs` 的内置 `coord`/`gunnery`/`torpedo` 出招路径原样保留；协同、交叉火力、T 头、屏护与雷击角色只走 `Style.evolved` 的 `suggestions_evolved` 路线。内置路径与 HEAD `5fc981b` 在 detached worktree 的五场 full-match hash 完全一致；`data/ai/baseline-orders.json` 的 coord tick-0 出招逐值复现（含数字文本一致，`serde_json` 非 bit-exact 解析只在 1 ULP 内且要求记录文本命中）。扩展快照 [builtin-orders.json](data/ai/builtin-orders.json) 由 HEAD 生成，覆盖三套内置风格的 day/night 共 11 例。
- 训练：[ai-trainer.rs](src/bin/ai-trainer.rs) population 6、generations 3、rng_seed 6106；训练 2 seeds（6106 coord、6107 gunnery）、验证 3 seeds（6111 torpedo、6112 coord、6113 gunnery），席位 0/1 都跑，全部 fitness 来自 [ai_evolve.rs](src/ai_evolve.rs) 的真实 headless 对局，无脚本分数。
- 产出：[evolved.json](data/ai/evolved.json) 三条 profile（evo-screen / evo-torpedo / evo-gunnery），验证均值 282.57 / 217.56 / 1692.16，对内置 coord 50.17 / torpedo 181.35 / gunnery 1094.89 均有真实优势；[training-log.json](data/ai/training-log.json) 记录 seeds、配置、history 和每场 match；[ai-report.json](data/ai/ai-report.json) 汇总基线、训练、测试、证据与边界；[shop-merge.json](data/ai/shop-merge.json) 给出 id/name/description/unlock/cost 合并清单（provisional，未改 catalog/Harbor）。
- 验收：主工作区 `cargo test --release --locked` 121 passed / 0 failed；AI 专项 10/10；`cas-sim` host 协议实跑 evolved vs builtin 三场（evo-screen vs torpedo 5-1、evo-torpedo vs coord 5-4、evo-gunnery vs coord 5-2，均 replay 一致，见 [evidence](data/ai/evidence/)）；WASM 重建并跑 21 组原生/WASM parity（`nativeWasmCanonicalMatch=true`，[parity](data/ai/evidence/native-wasm-parity.json)）。
- 边界：`friendly_margin` 保留在 schema/基因与单测里，但当前 evolved 火力基底沿用内置引擎保护，尚未用该基因扣分；`side_gun_plan`/`side_torp_plan` 保留为未接线原型；`spread` 只作为小权重的队形分散项；商店合并未接 catalog/Harbor/前端入口；旧 `builtin-baseline.json` 的 full-match hash 在 HEAD 上不可复现，已重录并把旧值留在 `previousHashes` 供审计。

## 2026-11-08｜91 张已核验舰卡并入排位注册表（111 → 202 可出战）

- 结论：210 个稳定身份中 202 可出战、8 收藏。新增 91 = pdf Form 10 逐舰卡 12 + APD 8 + 同型卡 13 + CAS 同盟源表卡 21 + CAS 轴心完整卡 10 + 历史轴心 7 + ERMA USN 12（8 艘用 C-3 炮表闭合成完整 ship）+ ERMA IJN 8。收藏 8 = 纸面/未建成 6（天城/赤城/尾张、伊吹/鞍马/五濑）+ Midway(CV) + 夕风（无 CAS 表）；不硬凑 208。
- 数据：[merged-cards.json](data/ships/merged-cards.json) 91 条（identity/name/side/type/class_profile/source_file/source_kind/stat_verified/stat_source/conflicts/ship）。71 张直接复制源包里已登记的完整 ShipDef（APD/同型/同盟/轴心/ERMA 完整/历史轴心）；12 张 pdf 卡按 Form 10 个体页 profile 原样重建（炮座行、弹种行、损伤-航速行、装甲/转向/雷座）；8 艘 ERMA USN 只补 `data/rules/gun-rows-erma.json` 的 Mk7/Mk8/Mk16 exact 行与 CAS 5e p.23（印刷 3-2）未印运动默认行。生成器 [build-merged-cards.py](scripts/build-merged-cards.py) 可重跑；源卡未改。
- 内核：`ranked_fleets` 改为 `profiles()` = 111 条手写 `LEGACY_PROFILES` + 91 条生成的 `MERGED_PROFILES`（[ranked_profiles_merged.inc](src/ranked_profiles_merged.inc)）；`data()` 增加 merged 解析路径并跳过 `stat_verified=false`；`card_ref` 增加 `cas-merged-cards-v1#<identity>`；`catalogue()`/`display_name()`/`class_for()` 全量 202；`roster()` 接受 CB/BC/AV（CB/AV 计巡洋位，BC 计主力位），仍拒绝全部收藏 id。`realtime.rs` 为 50 个新 class profile 登记炮座时序（沿用同炮族已有记录：16in 30/4、Yamato 40/2、8in 20/4、Des Moines 10/10、5in/38 4/28.7、12.7cm 12/6、12cm 12/8、14cm 8/10 等）。
- 点表：[cas-competitive-points-v1.json](data/rules/cas-competitive-points-v1.json) 补 91 行，`profile_id = cas-merged-cards-v1#<identity>`，点值由现有 `point_value` 现算并全部标 provisional（平衡 agent 复核）。历史战役预算未动。
- 身份元数据：[cards.json](data/ships/cards.json) 210 张更新为 202 playable / 8 collection；`cas_source_class` 与 202 个注册 Profile 的 class 一一对应；`playable_by_source` 记录 ranked-profile 202 / merged-card 91 / period-card 23；`gaps.identity_ids` 列出 8 个收藏 id；派生 [non-scenario-identities.json](data/ships/non-scenario-identities.json) 同步为 71 行（63 playable / 8 collection）。
- 验收：
  - `cargo test --release --locked` 103 项全过。新增 3 项：`every_merged_hull_has_a_realtime_gun_cadence`（91 张全部过 `init_realtime`）、`merged_destroyers_form_a_lawful_3000_point_duel`（6 艘 merged 驱逐舰 3000 分对局）、`registry_holds_202_playable_hulls_and_eight_collection_identities`（202/8、8 个收藏 id 被 roster 拒绝）；`frozen_manifest_matches_the_runtime_point_formula` 断言 `profiles().len()==202` 且 202 行点价/来源逐条一致。
  - `CAS_TEST_DUEL_SIM_PATH=target/release/cas-sim.exe python -m unittest server.test_ranked` 12 项全过（含 4 项原生 sim 流程）；其余服务端 `test_accounts/test_account_progression/test_battle_pve/test_duels/test_fleets` 21 项全过。
  - `node node_modules/typescript/bin/tsc --noEmit` 与 `node node_modules/vite/bin/vite.js build` 通过（仅既有 chunk-size 警告）。
  - WASM 重建：`cargo build --target wasm32-unknown-unknown --release --locked --lib` → `client/public/cas_core.wasm`，SHA-256 `B07C44920FE1AD8E09BB698177F9C30C4575745870FD4FE6BB5F5517A8A68F27`（3,300,353 bytes）；`node scripts/build-parity.mjs` 21 组原生/WASM 对照 `nativeWasmCanonicalMatch=true`、`replayMatch=true`。
  - 报告：[merge-report.json](data/ships/merge-report.json)（202/8 覆盖、每类新增数、来源哈希、排除名单、测试/WASM、仍缺）。
- 边界：8 个收藏身份不合并；Hiei/Kirishima 的 12.7cm/40 DP 未并入单一 `secondary`（只收 15cm/50 舷炮，登记为未建模差额）；pdf 12 张与 ERMA 8 艘的 profile 未印 `torpedo_protection_dp`，ShipDef 记 0；Des Moines/Salem 1948 配置放进 1944 年 ERMA 架空想定，保留 source note；Walke p309 COM 极远段印 25.9 千码（SpCOM 14.7、同级正常 18.2），按原页保留并登记为印刷异常；CAS 5e p.23 运动默认行只用于原页未印转向/加速的 8 艘 ERMA USN；91 行点价待平衡复核。未改 `server/catalog`、立绘、音频、AI、`data/campaign`、portraits 与 8 个来源卡；未提交。

## 2026-11-08｜23 张 period 逐舰卡接入排位注册表（88 → 111 可出战）

- 结论：`playable-cards.json` 的 56 个 collection-only 中，28 个有 period 逐舰卡；5 艘 APD 维持收藏，其余 **23 艘战斗舰**按剧本包里的完整 ShipDef 接入排位。此前不可出战是排位只加载 stage0/序章 25 张类卡所致，不是缺舰表。
- 数据：[period-cards.json](data/ships/period-cards.json) 23 条（identity/name/side/type/source_file/period_ship_id/period_profile/form10_page/stat_verified/stat_source/stat_conflicts/resolved_from/also_recorded/ship）。`ship` 原样取自 `savo-runtime.json`（16 条 ships 行）、`kula-runtime.json`（Honolulu，profiles.brooklyn_1）、`cape-runtime.json`（Uzuki）；Boise 与 Farenholt/Duncan/Laffey/McCalla 的 Cape Esperance 卡以 `profile_ref` 指向 Tassafaronga 包，按该包已编译运行时行（`tass_honolulu`、`tass_lardner`）取完整定义。生成器 [build-period-cards.py](scripts/build-period-cards.py) 可重跑；只手写稳定身份与中文名与下方 5 张的原页炮雷行，其余零改写。
- 6 张源卡按**本舰 Form 10 个体页**重录炮座/雷管（Hull 无本舰页，按 AF A-19 class 行；class 表只作未印项兜底），不再沿用 runtime 把「座数×管数」算错的旧值；个体页与 class 行的差额逐条写进 `stat_conflicts`：
  - 鸟海（Form 10 p.49，Aug 42）：20 管/4 座 → **9 管/5 座**（Fwd 单装 1＋Fwd 2＋P&S 2＋Aft 2＋Aft 2）；16 雷管/4 座 → **8 雷管/2 座×4**；DP 401 → **471**（0/118/236/353/424/471 → 33/25/16/8/0）。Takao/Atago 仍按 p.52 的 10 管/16 雷管。
  - 威尔逊（Form 10 p.317，Dec 41）：8 管/2 座 → **4 门单装/4 座**；8 雷管 → **16 雷管/4 座×4**；DP/航速 124/35 → **118/38**（0/30/59/89/106/118 → 38/28/19/10/0）。
  - 蒙森（Form 10 p.303，May 42）：8 管/2 座、无鱼雷 → **4 门单装/4 座、10 雷管/2 座×5**（Port & Stbd (5)×2，同型 Gwin p.301 口径；Mk15 同页表 6.0 kyds/45 kts/87 DP）；DP/航速 144/37 → **128/35**（0/32/64/96/115/128 → 35/26/18/9/0）。
  - 布坎南（Form 10 p.292/p.293，Mar 42）：8 管/2 座 → **4 门单装/4 座**；8 雷管/2 座×4 → **10 雷管/2 座×5**（同型 Barton p.291 口径）。
  - 圣胡安（Form 10 p.262，May 42）：10 管/5 座 → **16 管/8 座×2**（3F＋Port＋Stbd＋3A）；4 雷管/2 座×2 → **8 雷管/2 座×4**；DP 304/33 与 class 行一致。
  - 赫尔(I)（AF A-19，Farragut；无本舰 Form 10）：size C→**D/Small**、turn 300→**200 码(1 节)**、损伤行 36/26→**26/27**（0/26/53/79/95/105 → 36/27/18/9/0）；5 门单装/8 雷管不变；A-19 的「1942 P&S 5in removed」与 ASW w/7 未落卡，登记在 `stat_conflicts`。与同盟 source card 的 us_farragut_dd 修正对齐。
  - 23 张 `stat_verified` 全为 true，全部仍可出战，无 blocker。`data()` 会跳过 `stat_verified=false` 的 period 卡（`roster()` 也拒绝该 id），因此将来若发现无法重建的卡，不会带着错值可出战。
- 来源：10 条有已核 Form 10 页（Boise 265、Farenholt 296、Duncan 295、Laffey 297、McCalla 299、Honolulu 267、Uzuki 183、San Juan 262、Tenryu 81、Yubari 75），13 条源包登记为未核（null），不补默认值。Buchanan/Honolulu 的第二张 period 卡记入 `also_recorded`；Boise/Honolulu/Uzuki 源页无鱼雷行，`torpedo` 保持 null（蒙森原为 null，本轮按 p.303 的 Mk15 单座 5 管补齐）。
- 内核：`ranked_fleets::data()` 解析 `include_str!("../data/ships/period-cards.json")` 并入 ships；`PROFILES` 增至 111（新增 23 条 `source = "period exact · <file> · <form10>"`、`source_class = period profile`）；`src/realtime.rs` 为 15 个 period profile 登记 `timings`（沿用同型已核炮座节奏，仅 v10 生效）。88 个既有 Profile 的 id/source_class、历史战役预算、`campaign/live.rs` 均未动。
- 点表：[cas-competitive-points-v1.json](data/rules/cas-competitive-points-v1.json) 补 23 行（`profile_id = cas-period-cards-v1#<period_ship_id>`，行内标 provisional 待平衡复核）。数值由现有 `point_value` 从完整 ShipDef 现算；修正后重算：鸟海 1800→**1375**、威尔逊 500→**475**、蒙森 475→**425**、布坎南 500→**425**、圣胡安 850→**1025**、赫尔(I) 425 不变；其余 Australia/Canberra 1250、Boise/Honolulu 1050、Yubari 550、Bristol 四舰 525、Bagley 级 500、Uzuki 250 不变。
- 验收：
  - `cargo test --release --locked` 100 项全过，含新增 `period_cards_carry_complete_hulls_into_a_ranked_duel`（6 艘 period 驱逐舰组成合法 3000 分编队并进入 ranked 世界）、`period_card_stats_follow_the_printed_hull_pages`（逐张断言 5 张的管数/座数/DP/航速/雷管）与 `every_period_hull_has_a_realtime_gun_cadence`（23 艘全部通过 `init_realtime`）；`frozen_manifest_matches_the_runtime_point_formula` 断言 PROFILES=111、111 张全部上场且点价/来源逐条一致。
  - `server.test_ranked` 12 项全过（`CAS_TEST_DUEL_SIM_PATH=target/release/cas-sim.exe`，含 4 项双席流程）；点表 111 行全部落在 `server/catalog.json` 身份内。顺手修正两处只在原生 sim 下才执行的过期断言：免费编队 1875→1375、budgets [3000]→[3000,10000]。
  - 其余服务端 5 套件 21 项全过；`tsc --noEmit`、`vite build` 通过（仅既有 chunk-size 警告）。
  - 报告：[period-cards-report.json](data/ships/period-cards-report.json)（23 条来源/哈希/完整性 + 111/99 覆盖 + 测试结果 + 缺口名单）。
- 边界：WASM 未重建（仅 ranked 注册表数据与炮座时序，未改剧本/裁决；ranked 由原生服务端权威执行）。收藏侧仍 99 = 28 张无 period 卡 + 5 艘 APD（望月/三日月/长月/皋月/夕凪）+ 66 个不在当前 11 剧本交叉表内的 identity。未改 `server/catalog`、立绘、音频、AI、`data/ships/runtime-identities`；未提交。

## 2026-11-08｜特混编成（自定义任务编队）

- 镜头前的规则：历史编制仍是星级与史实编成的唯一口径；新增独立“特混编成”页签。位置数 = 剧本已有玩家编队数（埃斯佩兰斯角 1、皇后湾 3）；最多一位置一个编队，可少派、空位置、单舰，总点价不超历史玩家兵力；锚点/航向/航速/领舰取运行时历史玩家 fleet，不新增坐标。
- 内核：新增 `campaign::live::GroupPick` 与 `Start.groups`；`campaign_fleet` 返回 `positions`/`taskForceSupported`；`campaign::fleet::spawn_groups` 校验位置唯一、非空编队、同阵营、点到点价预算，并按剧本列距（500 码）在锚点后列队；Esperance/Empress 的 `fill` 跳过历史玩家编队后调用；敌方编制、阵位、目标不动。`fleet::options` 暴露玩家锚点。
- 前端：关前编成新增“历史编制 / 特混编成”页签；特混页为初设位置卡 + 编队卡 + 舰船选择 + 点价/校验/出航；空位显示“空置”，可只派一个编队；单舰北卡罗来纳可独立出航。
- 不计历史星级：`CampaignLaunch.groups/taskForce` 透传 `new_campaign`；客户端 `campaignTaskForce` 跳过 `recordCampaignResult`、跳过历史结尾演出与星级奖励；结果页显示“特混编成 · 不计历史星级”。
- 范围：本批只接入 `CAMP-ALLIES/AXIS-02`（1 位置 / 6,850）与 `CAMP-ALLIES/AXIS-11`（3 位置 / 7,500）。其余关卡 `taskForceSupported=false`，页签禁用，不伪造位置。规则登记见 [docs/rules/task-force.md](docs/rules/task-force.md)。
- 验收：
  - 引擎全量 91 项通过，含 7 项舰队测试：单编队锚点、单舰战列舰、空位置、重复位置拒绝、超预算拒绝、未接入关卡拒绝、位置/支持标志。
  - WAsm 重建并复制到 `client/public/cas_core.wasm`；浏览器使用同一内核。
  - 新增 `browser-taskforce` 通过：皇后湾 3 位置、第 1 位北卡罗来纳、第 2 位空置、第 3 位弗莱彻；出航观察 2 舰/2 编队，首舰落在 39,374.25/25,181.66，第二舰落在 36,071.65/17,521.64。凭证 `artifacts/client/taskforce/receipt.json`。
  - 新增 `browser-taskforce-esperance` 通过：1 位置、单舰北卡罗来纳；观察 1 舰/1 编队，锚点 32,187.546/12,954.984。凭证 `artifacts/client/taskforce-esperance/receipt.json`。
  - 历史回归：`browser-esperance`（故事 9 舰/决定性）、`browser-deployment`（换舰/预设/草稿/参谋）、`browser-campaign-modes`（史料馆/标准直出）、`browser-lobby` 全部继续通过。
  - `tsc --noEmit` 与 `vite build` 通过（仅既有 chunk-size 警告）。
- 边界：
  - 圣乔治角（2 编队 / 2,375）、塔萨法隆格（3 / 9,300）、库拉湾（1 / 5,100）与萨沃岛（多编队）未接入；不得在前端或数据层伪造初设位置。
  - 历史舰位候选使用剧本 class card；战斗舰名可能显示舰级名（如“弗莱彻级”），身份级舰名需要扩展 `GroupPick` 舰名载荷，另批处理。
  - 特混结果页的浏览器断言尚未补；引擎/页面已跳过历史星级与结尾演出。
  - 单舰 6,000 分不在现有点表：北卡罗来纳 3,000、大和 4,000；本批按现有点价执行，不新增舰卡或点价。
  - 未提交；工作区仍有 `src/campaign/savo.rs` 的既有改动，本批未触碰。

## 2026-11-08｜P1 战役大厅与关卡前编成

- 新增 `client/src/screens/campaign/CampaignLobby.tsx`：三栏战役大厅（年份关卡列表 / 战区海图 / 关卡详情）。默认全战线，可切铁底湾等战区；主列表只列可出击关卡，未开放档案折叠进「档案整理中」。
- 新增 `client/src/screens/formation/DeploymentScreen.tsx`：故事难度历史舰位编成。9 个历史舰位不可增减，逐位换同阵营已登记舰卡；候选面板显示立绘、舰种、点价与 delta，超预算禁用并给原因；右栏点价预算、校验、战术、预设、出航。
- 草稿与预设存 `cas.deployment.v1:<profileId>` / `cas.fleetPresets.v1:<profileId>`；刷新后草稿恢复。出航仍由 `src/campaign/fleet.rs` 二次校验。
- 新领域组件 `client/src/widgets/{ship-thumb,formation}.tsx` 与 tokens `client/src/ui/tokens.css`；`shipPortraits.ts` 增加按中文舰名查立绘，覆盖历史舰卡在 ledger 中没有 CAS class 映射的情况。
- `CampaignLaunch` 增加 `profile`；`main.tsx` 的 `new_campaign` 透传出击编成选择的战术风格。标准/挑战难度不进编成屏，仍按历史编制直接出击。
- 旧 `CampaignArchive` 保留为「史料馆」全屏视图；原来源/核验路径可进入，不再占据主出击流程。
- 移动端收尾：编成屏在 ≤900px 改为“底部指挥条 + 参谋抽屉”。底部条固定显示点价/预算状态、参谋、出航；参谋抽屉内放预算、校验、战术、预设，正文可滚，出航常驻。740×360 下舰位列表可显示 4–5 行，主按钮不再占用列表高度。
- 验收：
  - `node node_modules/typescript/bin/tsc --noEmit` 通过；`node node_modules/vite/bin/vite.js build` 通过（仅既有 chunk-size 警告）。
  - `node tests/browser-esperance.mjs`（`CAS_BROWSER_PATH` 指向 Edge）通过：新大厅 → 编成 → 出航 9 舰/1 编队/夜战 10% → 决定性胜利。
  - 新增 `node tests/browser-deployment.mjs` 通过：9 舰位、6,850 预算；第 1 舰位换拉姆森后 6,825；保存预设 → 按历史编制恢复 → 载入预设再恢复拉姆森；刷新后草稿保留；740×360 打开参谋抽屉并关闭；出航观察 `CAMP-ALLIES-02`、9 舰、首舰拉姆森。凭证 `artifacts/client/deployment/receipt.json`，截图 `deployment-1360/740/740-staff/swapped/launch.png`。
  - 新增 `node tests/browser-campaign-modes.mjs` 通过：史料馆 11 行档案；未开放关卡按钮禁用且文案“档案整理中”；标准难度不经过编成屏直接出航，观察 `CAMP-ALLIES-02`、`standard`、9 舰。
  - `node tests/browser-lobby.mjs` 通过：母港 4 入口、新大厅 11 关/0-33 星、编成屏、剧情模式与序章；740×360 大厅无横向滚动，截图 `campaign-lobby-740.png`。
- 边界：
  - 未改 `src/` 内核、CAS 舰卡、点表、历史阵位/航向/航速；`src/campaign/savo.rs` 的既有改动未触碰。
  - `campaignStars` 的 0/2/3 语义仍保留：把 1 星定义为“完成作战”会把败局也算首通，需内核提供胜负/完成标记后再改；当前 1 星奖励实际由战术胜利起承接，是已知语义债，单批处理。
  - `client/tests/browser-campaign.mjs` 是旧 `.archive-list` 版本，早于当前 `.war-*` 档案页，本批未修；当前战役验收走 `browser-esperance` / `browser-deployment` / `browser-campaign-modes` / `browser-lobby`。
  - 740×360 参谋抽屉的战术/预设位于抽屉下半部，需要滚动；这是短屏取舍，主按钮始终可见。
  - `vite.config.ts` 的 `server.watch.ignored` 是防止 harness 临时目录触发 chokidar EBUSY 的开发稳定性修复。

## 2026-11-08｜卫星实拍海图底层与海岸线重制

- 用户反馈岛屿轮廓粗糙（旧投影每岛仅 36 点且地理错位约 25 km）。重写 `scripts/refine-basemap-coastlines.py`：numpy 分类水体/植被（蓝≥绿为水），形态学闭运算弥合岛内阴影，scipy 标记连通块并按角度排序轮廓，Douglas-Peucker 220 m 简化——Guadalcanal 503 点、Florida 314 点、Savo 12 点。
- 海图锚点改用数字化 Savo 地标（159.82320, −9.13042）作为各场 origin 的实测依据：esperance (159.5894, −8.8898)、tassafaronga (159.6902, −8.9029)、savo (159.5834, −8.8969)；y 从场南边向北增长（与数字化海图/引擎同约定）。
- 新增 `scripts/build-map-mosaics.py`：把 48 张缓存卫星瓦片拼成 3072×2304 ironbottom.jpg（365 KB）供三个剧本共用，manifest 记录地理范围。
- 客户端 `basemaps.ts` 按 variant 注册卫星底层与场锚点；BattleMap 在场裁剪内先画实拍图（brightness 1.3、12% 夜色叠加），有底层时不再绘制多边形岛屿（多边形仍由引擎用于碰撞/航线）；photoImg 进入主绘制依赖。
- 验收：引擎 86 项、服务端 33 项、parity 21 场全过；browser 五项回归通过；萨沃截图确认 Guadalcanal/Florida/Savo 与舰位对齐。

## 2026-11-08｜萨沃岛数据闭合与运行时

- 数字化海图接入：`savo-chart-digitized.json`（32 刻度点、仿射 RMS 1.48 px）→ `chart-savo.json` 引擎米制坐标；6 巡逻线、18 舰影、2 运输区、7 地标、日军箭头全部保留，未加图外舰位。
- 舰卡：59 张（savo-runtime.json）。作战舰用已核炮行＋显式炮座表（New Orleans 4×3、Takao 4×5、Kent 2×4、Atlanta 5×2 等）；运输/DMS/APD 用 AF A-42–A-47 与 Form 10s 的 DP/掉速行。Yunagi 的 Type 96 鱼雷无 Annex F 行，登记省略；Henley 的 Gridley/Bagley 冲突保留。
- 运行时：`campaign::savo`，57 艘实例。日军 8 舰 135°/28 节（Chokai 自 Blue 345°/12,000 码，巡洋舰 1,300 码；轻兵 500 码登记默认）；盟军巡逻舰按图落位，运输区按 4×800 米网格。D6/3 禁火特例实现（掷一次、进 RNG 流）。月相 New Moon，照明命令按原页不开放。
- 评级：美方 3:1/1:1＋运输舰受损上限；日方 2:1＝战术；五艘运输舰决定胜条件因原页无锚点登记受限。
- 验收：引擎 86 项、parity 21 场（含萨沃同盟席）、`browser-savo` 出航通过（49 艘本席舰/8 编队/海况 3/雷暴）。

## 2026-11-08｜手把手固定流程教学

- 舰桥学堂昼间课改为 `GuidedTutorial`：教官只高亮一个控件，玩家点击高亮处才进入下一步；其他点击被拦截，不能自由发挥。
- 九步固定流程：编队 → 选第二艘舰 → 设为领舰 → 领舰移动 → 海图两个航点 → 下达航线 → 开始演习 → 结束。航点由教学脚本放置，路线命令由教学脚本下达。
- 透明代理层处理禁用按钮（如下达航线在预览前禁用），点击仍可推进；目标不在视口时自动滚入。
- 完成时强制标记 7 项入门实操与昼间课程，返回教学页显示 7/7，不再卡在未完成。
- 验收：`browser-guided-tutorial` 九步全部点击通过、无页面错误、返回后 7/7。

## 2026-11-08｜塔萨法隆格数据闭合与运行时

- 新增 `scripts/compile-tassafaronga-runtime.py` 与 `data/campaign/period/tassafaronga-runtime.json`：19 艘具名舰逐舰炮座、鱼雷、备雷、DP/掉速/转向；六个载桶舰备雷为 0，长波/高波保留 8 枚备雷；Gridley 四座单装读法与弹种选择写入舰卡注记。
- 新增 `campaign::tassafaronga`：三列美军（5 巡洋舰 + 4 前卫 + 2 后卫）、日军警戒队/两运输队/高波哨舰；三处补给圈、每窗每舰一串、每点 3 舰、≤2 节、每串 20 分；日方总分含对美舰 DP，美方按 120/240 已卸分与重巡损伤/沉没评级。
- 战役 05 接入 `CAMP-ALLIES-05`/`CAMP-AXIS-05`，海图 76k×75k，客户端显示补给圈与已卸分；基础难度编队预算 9300 分，标准/挑战用历史兵力。
- 验收：引擎 84 项（新增补给卸货测试）、`browser-tassafaronga` 出航 11 艘本席舰/3 编队/3 补给圈通过。

## 2026-11-08｜测试免登录、固定流程教学、探照灯/照明目标、炮塔转向与航速接管

- 测试构建不再显示登录页：`Entry` 自动使用固定本机“测试指挥官”，保留原账号/线上接口但默认直接进母港。
- 教学加“继续（固定流程）”按钮：`completeTrainingStep` 按当前步骤顺序补齐所需信号，不再要求玩家自由操作才能过关；原有“指出操作位置”保留。
- 探照灯观测新增目标坐标，海图光柱按实际目标位置绘制并在目标上画圈；照明弹为下令席位返回瞄准点坐标，海图在目标处画准星，不再只显示偏移的爆点。
- 舰况俯视图的炮座改为可旋转的炮管矩形，按 `bearing - heading` 随舰体/炮座实时转动，损毁炮座保留叉号。
- 编队航速条显示实时航速、目标航速与合法上限；滑块上限取 `fleet.maxSpeed`，不再固定 40 节。
- `lead` 允许航行中任意本队舰接任领舰，不再要求全队停到 0.5 节以下；接任时保留各舰现有航迹，不再清空导致突然停车。解除旧的“必须从队列一端选择”限制。
- 验收：引擎 81 项、客户端 tsc、browser-lobby/activities/esperance 通过；剩余：7 个资料层剧本与登录后的线上回归未完成。

## 2026-11-08｜第 15 关移除、北卡罗来纳 UP、活动/邮箱、3000/10000 分档与基础难度编队

- 第 15 关 `IBS-S-EM-01` 从 `catalogue`、席位、客户端星数与测试移除；战役目录 11 条、22 个关位，继续可出航 `CAMP-ALLIES/AXIS-03`、`-04`、`-11`、`-02`。该关的收藏身份仍留在经济目录。
- UP 池旗舰改为北卡罗来纳（已核验战列舰卡）；北卡罗来纳升 UR、入池，立绘投影到征募台账。可征募 167，服务端注册投递“内测启航补给”邮件 20 张常驻券。
- 母港顶部新增活动与邮箱入口；七日签到走活动页，邮箱独立页支持线上 `/mail` 与本机 `PortState.mail`，两处都能领取 20 抽。
- 点表新增邓拉普、格里德利、白露、夕云、秋月、吹雪、初雪七个驱逐舰身份；3000 分档可编 6 艘驱逐舰，10000 分档开放并可由 1–2 艘战列舰加护航舰组成。服务端 `enabled_budgets`、内核 `match_pool` 与客户端分档页一致。
- 战役 `story` 难度新增分数编队：`campaign_fleet` 返回历史兵力预算、逐舰位历史编制与同阵营已登记舰卡；`new_campaign.fleet` 在保持舰位、航向、航速、编队与领舰的前提下逐位替换舰卡，替换后重建炮座实时状态。标准/挑战仍用历史兵力。
- 验收：引擎 81 项、服务端 33 项（6 skip）、parity 19 场全过；`browser-lobby`（11 关、★0/33）、`browser-activities`（签到 + 邮箱 20 抽、钱包 22 券）、`browser-esperance`（6850 分历史编制、出航、9 舰、决定性胜利、重演）通过。
- 遗留：其余 7 个资料层剧本尚未接运行时；基础难度编队要求与历史舰位同数，未做减舰/增舰与个人收藏过滤；19 艘运输/小艇/航空机制仍未实现。

## 2026-11-08｜剧本对应清理、卡池立绘、母港单页、战役大厅与剧情模式

- 战役目录只保留有 CAS 对应剧本的 12 个想定；通道行动、1928 所罗门、1928 布干维尔与《铁底湾的回响》从 `catalogue`、席位、客户端奖励与测试中移除，交叉表和数据文件保留。当前可出航 `CAMP-ALLIES/AXIS-03`、`-04`、`-11`、`-02`。引擎目录 12 条、24 个关位。
- 卡池：`roster-crosswalk` 中 12 个保留剧本的 164 个稳定身份全部标为 `recruitable`，加 2 个原商店身份共 166 个；`scripts/import-scenario-portraits.py` 从固定手游 manifest 生成 166 张 700×1050 WebP，逐个登记源/输出 SHA-256。`server/import_catalog.py` 改读 `server/scenario-recruitable.json`，概率、保底、重复勋章、价格、礼包仍按手游固定快照投影。立绘在征募、收藏、到货与母港值更舰共用；`shipPortraits` 对战斗立绘缺口回退到经济台账。
- 母港只保留图一单页：钱包改为补给币/征募券/舰队勋章三项；dock 固定四项（舰库与编队、征募与补给、教学复习、线上舰桥）；值更舰按钮改为“换班”；旧多标签母港变为无标签单功能子页。
- 战役大厅改为图二：顶部返回港口/战役航图/双方战线/星数，左侧战区航图，右侧 12 关列表，底部难度页签与“作战简报”；简报内保留 CAS 原页编制、目标、特例、遮蔽项、星级奖励与出航。星数分母按保留关卡计算（单线 36）。
- 序章改为独立“剧情模式”：新增章节页，明示“架空剧情、不属于历史战役档案”，序章为第一章，后续在 `storyChapters` 追加；进度独立保存，不与战役星数/历史核验混用。
- 埃斯佩兰斯角运行时几何在 `offset`/航路端点做毫米取整，消除 native 与 wasm 的 sin/cos 末位差；parity 以 `CAMP-ALLIES-02`/`CAMP-AXIS-02` 替换已移除的通道行动两场。
- 验收：引擎 79 项、服务端 33 项（6 skip）、parity 19 场（含 Esperance 双方）全过；`browser-lobby`（12 关、★0/36、作战简报、剧情模式、序章打开）与 `browser-esperance`（出航、9 艘本席舰、决定性胜利、WASM 重演）真实点击通过。遗留：8 个保留剧本仍为资料层未接运行时；立绘是角色图，不是 CAS 舰卡；本地四舰型征募与联机 166 舰池仍分开。

## 2026-11-08｜实时目视圈与“被目视”圈

- `sightRange` 不再固定为同型静止基准：按本席已发现敌舰的舰级、航速、是否开火/起火逐舰计算并取最大值，随观察实时变化。
- 新增 `seenRange`：用已发现敌舰的舰级作为观察者，按本舰尺寸、航速、开火/起火计算敌舰能看见本舰的基准距离；海图新增红色虚线“被目视”圈。未知敌舰不参与，避免泄漏未发现目标。
- 图例改为“目视 / 被目视”，悬停说明基准含义。
- 验收：引擎 78 项、parity 19 场、browser-visuals/empress 全过。

## 2026-11-08｜20 倍速、固定历史设置、航速滑杆与俯视舰况

- 演习倍速新增 20×。历史想定（empress 演习）固定种子 6100、AI coord、实时主炮；演习设置只保留本席阵营，隐藏编号/AI/实时开关；战役内不再显示“演习设置”。
- 编队航速改为滑杆，直接下 `speed` 命令；舰况面板改为俯视舰体图：舰体随真实航向旋转、炮座按绝对方位指向、鱼雷管/火灾/进水标记，并实时显示航向与坐标。
- 友军相撞/领舰失能导致编队停船时，编队面板显示“编队受阻”，提供“重整队伍”和“脱离接触”；后者用 `resume` 命令让各舰向外展开 1,500 码，脱离后重新下航路。
- 验收：引擎 78 项（新增脱离接触测试）、parity 19 场、browser-visuals/offline/empress 全过。用户列出的第 3 条消息截断，未处理。

## 2026-11-07｜舰况目标命中率与编队航速

- 舰况面板显示本舰当前待发目标的实时命中率（`targetChance`，与 AI 射击门/拖动预览同源）。
- 编队面板新增航速输入，走新 `speed` 命令直接改目标航速，按编队当前最大航速校验；不重下航线。
- 验收：引擎 77 项（新增目标命中率/航速边界测试）、parity 19 场全过；服务端不受影响。

## 2026-11-07｜RTS 改编工程规范与奥古斯塔皇后湾阵位重算

- 新增 [RTS 改编工程规范](docs/rules/rts-adaptation-standards.md)，并在 AGENTS.md 写入硬约束：原书舰队/序列/阵位/方位距离/环境/目标/特例/表值不得删改；未印值只用一个全局登记默认值；海图必须扩到容纳原页距离并落原地标；未实现项显式登记；验收需逐项核对、原生/WASM 重演和浏览器实测。
- 奥古斯塔皇后湾按 PDF 90 原页重算六列阵位（292°/19 nmi、5,000/3,000 码、295°/18 nmi、10,000/5,500 码），扩图至 80,000×55,000 码，加入托罗基纳角岸角多边形；列内间距采用 500 码统一默认并登记。客户端对 80 km 海图使用初始 4× 视野，避免舰队挤在缩略图上。
- 源笔记新增“原页值 → 运行时值 → 状态”核对表，明确 F1M2 未实现与美方雷达火力导致的平衡偏差，不以改阵位/删舰掩盖。
- 验收：引擎 76 项、服务端 33 项、parity 19 场、browser-empress 全过。

## 2026-11-07｜奥古斯塔皇后湾雷达接线与开场几何核对

- 美方按 Form 10 给 12 艘巡洋舰／驱逐舰装 SG＋SC-2 水面搜索雷达并默认开机；`radar_enabled` 接受 empress 想定，AI 可雷达引导炮击（−2 搜索数据修正），玩家视图出现雷达距离圈与 R 接触。
- 日方 Type 21 在《The Emperor's Fleet》Annex J1 为 AS（空搜）行，不能用于水面测距；日舰远程开火是目视／瞭望接触，不是雷达。已登记，不把空搜行冒充水面搜索。
- 开场几何按原页重算并逐项实测：海图 80,000×55,000 码；Ausburne 在托罗基纳角 112°（互反 292°）19.0 nmi；Montpelier→Ausburne 30°/5,000 码（右舷艏）；Denver→Spence 210°/3,000 码（左舷艉）；Myoko←Montpelier 295°/18.0 nmi；Sendai 50°/10,000 码、Agano 230°/5,500 码；列内 500 码（Haguro 320°/500 码）。各舰开局即 20/30 节，不再从静止加速。Cape Torokina 岸角多边形尖端与评级坐标同为 (72,000,12,000)。列内间距为原页未印的 500 码统一默认值，已登记。
- 验收：引擎 76 项、服务端 33 项、parity 19 场全过；浏览器 `browser-empress.mjs` 在扩图后真实点击开局、战役 11 关出航、12 舰/3 列与战果事件通过。已知平衡偏差：美方雷达火力使日方在进入鱼雷射程前大量损失，日方九三式攻击尚未形成原页战果；登记为下一轮 AI 战术/火力节奏项，不得靠改阵位或删舰“修”。

## 2026-11-07｜奥古斯塔皇后湾 11 号关位绑定与岸角评级

- `CAMP-ALLIES-11`／`CAMP-AXIS-11` 接入战役入口：`Start` 识别关位、`empress::open` 使用同一 22 舰编制与 4,200 秒时限（0227–0337），战役视图返回 stageId／难度／任务栏目标。
- 岸角评级按《旭日》PDF 90 双方条件实现：美方击沉三艘且日方重巡未切入美巡与托罗基纳角之间＝决定性，三艘损伤过半且仍在外侧＝战术；日方重创三艘美巡且重巡切入＝决定性，造成损伤超过所受损伤＝战术。`finish_campaign` 写入双方评级与胜负。
- 目录开放：`campaign` 目录把 `cas-rs-empress-augusta-bay` 标为可出航（`localOnly`），客户端战役航图对应「奥古斯塔皇后湾」海域；服务端 `battle_pve.Stage` 接受两个 11 号关位，席位按关位名判定。
- 验收：引擎 76 项（新增战役双席开局与评级）、服务端 33 项（新增 11 号关位原生完成）、parity **19 场**（新增 empress-campaign，种子 6106 得决定性并逐字节重演一致）。
- 客户端实测：`browser-empress.mjs` 扩展战役段——同盟战线航图第 11 关显示可出航，点「出航作战」进入 12 舰／3 列战役海图，stageId＝CAMP-ALLIES-11（[凭证](artifacts/client/empress/browser-receipt.json)）。
- 电脑端构建：`release/CAS-Stage0-win-x64-20261107-224741-887/CAS.exe`（含本次引擎、WASM、战役目录与客户端入口），已启动供试玩。

## 2026-11-07｜副炮、多指挥仪与奥古斯塔皇后湾运行时（RTS-GUN-06/07、RTS-SCEN-01）

- 副炮对海：`ShipDef.secondary` 独立自动火力组，按主炮当前目标（否则最近接触）每 `reload_seconds` 掷 D100，命中使用副炮自身表伤/穿深；不占主炮指令与装填。Cleveland 5in/38、妙高八九式 12.7cm/40、阿贺野九八式 8cm/60 已接入。
- 多指挥仪：`GunDef.director_arc` 单前向指挥仪在目标出扇区时对尾炮施加局地控制 −2；Cleveland/妙高双指挥仪不触发。观察尺寸降一级未建模，登记差额。
- 运行时 `variant:"empress"`：22 艘具名舰、每方三列纵队、能见度 10%、阵雨、海况 1、Haguro 30 节上限；照明弹、探照灯、烟幕、副炮、鱼雷再装填、临界与雷达引导全部启用。
- 新增舰级 `cleveland_empress`、`myoko`、`agano`、`shiratsuyu`、`yugumo`、`akizuki` 进演习数据；实时炮座时序核准（10/10、12/6、10/8、12/6、8/10 秒/度）。
- 验收：引擎 75 项（含 22 舰整场、副炮、再装填、过集中）、服务端 32 项、parity **18 场**（新增 empress）全过；empress 种子 6106 在 1064 秒内打出结果并逐字节重演一致（[对照](artifacts/cas-parity-20261107-empress.json)）。
- 客户端验收：演习设置新增「奥古斯塔皇后湾 · 22 舰夜战」入口；`client/tests/browser-empress.mjs` 真实点击开局，核对本方 12 舰／3 列、夜战 10% 能见度与阵雨、AI 推进至战果，以及副炮／照明弹／炮击／鱼雷事件（[凭证](artifacts/client/empress/browser-receipt.json)）。回归 browser-offline／visuals 通过；顺带修正离线签到文案的旧断言。托罗基纳角几何函数已备，评级待 11 号关位绑定。

## 2026-11-07｜鱼雷再装填与远距过度集中（RTS-TORP-02 / RTS-GUN-05）

- 鱼雷座按 `data/stage0.json` 已有的 `reserve`／`reload_seconds` 再装填：Kagero 级每座 4 枚备雷、360 秒；Sendai 每座 2 枚八年式、900 秒；Fletcher 无备雷。被武器临界击毁的发射管不再装填。仅 v10 家族，v9 家族与库拉湾保持冻结。
- 远距／极远距带按同方同靶舰数施加过集中 −1／艘（CAS 5.1.2／6.1），中近距不受影响；仅 v10。
- 状态经 `systems.tubes` 下发 `reserve`／`reloadingUntil`。
- 验收：引擎 73 项（新增再装填、过集中各 1 项）、服务端 32 项、parity 17 场全过（[对照](artifacts/cas-parity-20261107-reload.json)）。PvE 决定性夹具种子 6117→6133；exercise v10 种子 6106 的胜方随日方再装填改为轴心（无断言，登记为平衡后果）。规则台账更新：realtime-torpedo-v10、coverage。

## 2026-11-07｜雷达引导照明弹与 AI 夜间工具

- 照明弹下令／预览在 v10 家族可回退到本方水面雷达轨迹（CAS 5.4.4.5 允许雷达发现）；目视优先。新增端到端测试：雷达-only 接触下令并实际起亮。
- 非战役实时夜战 AI 新增夜间工具：无照明弹燃烧时先打照明弹；无照明弹剧本在接战且目标 3,000 码内开一座探照灯；撤退不点灯。战役剧本暂不启用（其种子在无 AI 照明下调平），奥古斯塔皇后湾运行时再逐项启用。
- 验收：引擎 71 项（新增雷达照明、AI 探照灯、AI 照明弹 3 项）、服务端 32 项、parity 17 场全过（[对照](artifacts/cas-parity-20261107-ai-night.json)）。规则台账更新：realtime-torpedo-v10（RTS-LIGHT-03／RTS-AI-03）、coverage、night-gap。

## 2026-11-07｜临界结果落地：舰桥、舵机、武器（RTS-CRIT-01）

- `damage.rs` 的 `bridge`、`rudder`、`weapon/other_weapon/secondary_battery` 从空操作改为实际效果，仅 v10 家族生效；v9 家族（含库拉湾）保持原空操作与骰流，Kula 重演测试不变。
- 舰桥：D6 决定向左／向右回旋或保持航向；回旋清除航线并按当前航速持续转向。舵机：D6 决定卡死方向，舰只缓慢回转、拒绝转向与鱼雷命令。武器：水下命中击毁鱼雷管；水面其他武器优先鱼雷管，否则击毁主炮座。状态以 `rudderJam`／`bridgeCircle` 下发。
- 验收：引擎 68 项、服务端 32 项全过；原生 vs WASM parity 17 场逐项一致（[对照](artifacts/cas-parity-20261107-criticals.json)）。平衡偏移：通道行动同盟旧种子 6112 在临界生效后落败，改 6109（决定性）；圣乔治角 PvE 夹具种子 6117 以双队 torpedo 回到决定性。规则台账更新：realtime-torpedo-v10、coverage、night-gap。

## 2026-11-07｜水面规则闭合载体：奥古斯塔皇后湾时期舰卡

- 选定《旭日》PDF 90（印 90）奥古斯塔皇后湾海战作为“全机制中型剧本”：夜间、双方巡洋舰＋驱逐舰、三列纵队，覆盖雷达、照明弹／探照灯、烟雾、鱼雷再装填、巡洋舰副炮与多指挥仪、先验舰损与岸角方位。
- 新建 `data/campaign/period/empress-augusta-bay-1943.json`：22 艘具名舰、9 个舰级（Cleveland、Fletcher、Myoko 1940、Sendai 1943、Agano、Kagero、Shiratsuyu、Yugumo、Akizuki），逐舰 Form 10 页与雷达配置；复用 8 个已核炮雷型号，从《The Emperor's Fleet》C-1/C-2 新录 Type 89 12.7cm/40、41st Yr 15cm/50、Type 98 8cm/60、Type 98 10cm/65 四行。
- `data/campaign/empress-augusta-bay.json` 补 `ships`（22 舰映射）与 `period_records` 链接；`scripts/check-campaign.py` 新增 `verify_empress()`，主仓实跑通过（16 想定／32 关位／22 艘本剧本舰）。
- 未决冲突 7 项按原样登记，不填默认值：Cleveland DP 级表 336 与 Form 10 396、妙高 428/35 与 471/33、Sendai 八年式鱼雷、Sendai 8cm/40 副炮未登记、Agano 346/302、F1M2 侦察机、多纵队与岸角方位。来源与差额见[源笔记](docs/campaign/empress-augusta-bay-source-notes.md)。

## 2026-11-07｜探照灯与烟幕的 v10 实时改编（RTS-LIGHT-02 / RTS-SMOKE-01）

- **探照灯命令**：夜战对已知目视接触下令，当秒掷照距骰、逐秒生效；友方炮击只对照距表范围内的目标给照明修正（`gun_values` 增加距离门），发光舰自身承担 +1 使用修正；**暴露按原书**——源距（无降水为灯具最大距离 5 倍）内敌方逐舰免掷骰自动获得发光舰接触。视图暴露 `searchlight {target, bearing}`。现役四型舰表按阵营 8,000／7,000 码临时档，逐舰实装与射界仍待核。
- **烟幕命令**：仅驱逐舰；每 60 秒落一朵半径 1,000 码烟团、燃烧四窗；烟团内目标与射线穿烟的目标目视上限昼 1,000／夜 500 码（§5.4.5），超出丢接触并发 `RTS-SMOKE-01` 丢失事件（昼间边际路径补上了同一上限与事件，与夜间一致）。无风场，烟团不漂移。
- **探测积分修正**：夜间编队危险率只对尚未保持的舰体掷骰（§5.4.1.7 保持）；此前探照灯改造把已见舰也并入了编队视图，会经共享骰流挪动其他编队的首次接触时点——雷达夜战教学的照明弹射程带断言因此翻转，已在 parity 里暴露并修复（首次接触时点与 HEAD 逐秒一致，照明弹照常起亮）。
- **验收**：引擎测试 66 项全过（新增探照灯命令路径／照距门／暴露再捕获与烟幕遮蔽／丢失事件／四窗燃尽两套白盒测试）；原生 vs WASM parity 17 场逐项一致（[对照](artifacts/cas-parity-20261107-searchlight-smoke.json)）；浏览器 offline／visuals／realtime／story／radio／campaign／original-score 七套回归全绿。规则台账更新：[realtime-torpedo-v10](docs/rules/realtime-torpedo-v10.md)、[night-gap](docs/rules/night-gap.md)、[coverage](docs/rules/coverage.md)、[optical-v2](docs/rules/optical-v2.md)。
- **客户端接线**：指挥面板新增探照灯（夜战 v10 家族、已知接触下令／关闭）与烟幕（仅驱逐舰、施放／停止）两节；海图渲染烟团（1,000 码半径）与本舰探照灯光锥；`searchlight/smoke` 命令接入引擎分发（`lib.rs` 外部命令表）。browser-visuals 夜航演习段新增真实交互验收：开灯后视图暴露 target/bearing、烟团落图、关灯停烟后字段消失（[凭证](artifacts/client/visuals/browser-visual-receipt.json) 的 nightSearchlightBacklight/nightSmokePuff 与 07b-night-tools 截图）。
- 经济舰库立绘与音频两个迁移 agent 因配额中止，2026-11-08 01:22 限额重置后重试。
- **服务端 PvE 夹具随 v10 重定种子**：`test_real_victories_pay_fixed_rewards_once_and_weekly_clears` 的旧决定性夹具（种子 6177、双队 torpedo）在 v10 早接敌后落到战术，改为种子 6117、1 队 coord／2 队 torpedo（标准与挑战档均实测决定性）；服务端 32 项复跑全过。

## 2026-11-06｜Windows 昼战试玩与 Android 单机预览

实现基线：规则与内核 `c611515`，界面及运行包 `5e229ee`。独立仓库、应用名、存档、资源；原 PDF 和参考项目未改动。

- CAS 五版昼间水面裁决子集：四种首发舰型、两种编队机动、多航点预览、射界、计划和反应炮击、直航鱼雷、基本关键损伤、火灾／进水和损管。三种状态机有搜索、接敌、交战和撤离状态，玩家可按任务接管。
- `cargo test --release --locked`：14 项通过。资料检查核对了四份原件 SHA、四种舰型、炮雷射界、159 行鱼雷命中表及来源算例。
- `scripts/verify-duels.py`：六个种子、十二个席位投影。两方在每场均有实际开火、命中和受损，另一席复跑及重演结果相同。种子 6106：同盟 5 比 3，双方 60／52 次炮击；轴心 8 次鱼雷齐射，1 次命中。[对局摘要](artifacts/ai-exchange-20261106.json)。
- Edge 界面走查：同一场两种多航点机动、移动航点、拒绝不合法草稿、拖炮实际射击、取消不下令、推荐鱼雷方向 115° 手调为 113° 后实际发射；740×360 横屏触控可提交航路。[操作记录](artifacts/client/port/browser-receipt.json)。
- 母港预览：实际完成七项教学、一次性初始舰队、UP 征募、领舰预设、AI 解锁和 3 对 5 挑战；刷新恢复舰队、券余额和战局，挑战完成后常驻券与 AI 权益只领取一次。仅发布四种已核验舰型的体验池，未启用真实收费或账号资产。
- 最终 Windows EXE 和 Android 隔离模拟器均渲染实际海图和母港，存档、重演及 360 秒本方观察摘要一致。Android 在飞行模式运行，验证后台中断拖拽不下令、重启恢复；尚未验收实体 Android 手机。原生 Rust 和 WebAssembly 的两场 5 对 5 与一场 3 对 5 完整战报、结局和重演一致。

交付：

| 包 | SHA-256 |
|---|---|
| [Windows x64 试玩 ZIP](release/CAS-Stage0-win-x64-20261106-135611-455.zip) | `a29e305b39550cb10656c6b9cfd6ddea351a2fa95d3f63c38513f4ea752f57a4` |
| [Android 单机预览 APK](release/CAS-Android-0.1.0-preview-20261106-135643-378.apk) | `7f4b08bac530bdd1e2bb95e0b7c6530898c7bae6ee4ff539f0fb3c8395b7531f` |

运行证据：[Windows](artifacts/windows-final-smoke.json)、[Android](artifacts/android-final-smoke.json)、[原生与 WebAssembly 比对](artifacts/native-wasm-final-parity.json)。

阶段 0 可试玩；阶段 1 已有离线闭环预览，待实体机及正式内容验收。完整双线战役、夜战、更多舰娘与 AI 风格、跨端账号／匹配／排位及真实支付仍在后续阶段。CAS 规则未覆盖项见 [规则台账](docs/rules/open_questions.md)。

## 2026-11-06｜战斗反馈、夜航和历史档案 v2

- 本席命中／受损／起火／关键损伤／沉没等提示不拦截手势；炮弹按实体飞行并画弧，鱼雷用真实直航轨迹和尾迹。炮塔在瞄准及实际炮击时按对应炮位的射界转动。选舰显示炮雷最大射程和舰况，四种首发舰型用已核原作 ID 的舰型代表立绘。740×360 横屏仍可看舰况、选舰和取消。见[界面验收](artifacts/client/visuals/browser-visual-receipt.json)及[完整离线流程](artifacts/client/regression-v2/browser-receipt.json)。
- v2 昼夜都按 CAS 五版检定鱼雷发射迹象和尾迹；夜航演习还接入能见度、速度、炮口闪光、起火和夜间炮击修正。发射迹象不揭露发射舰或活跃轨迹。照明数据已录入并通过算例，照明命令、雷达及可选分级识别仍未开放。[光学规则](docs/rules/optical-v2.md)与[覆盖台账](docs/rules/coverage.md)分别列出调用和缺口。
- [水面雷达源数据](docs/rules/radar-source.md)已核 6 份原件、圣乔治角十艘舰的候选实装和 12 个算例。夕雾同期旧舰卡与 Annex A 冲突，保留原写法等待裁决。此批仅录源数据，未接入试玩包。
- 对照原手游 16 个想定／32 个双线关卡；11 个同一历史交战、1 个相关想定、3 个旧作架空或无对应、1 个未定位。圣乔治角、库拉湾、霍腊纽已录入原页数据并列入档案，韦拉拉韦拉原页数据在发包后录入待下一档案版本。未将任一历史场景标为可打。[战役对照](docs/campaign/source-crosswalk.md)；脚本验过铁底湾固定快照、10 个原件哈希与全部 4 份录入文件。
- `cargo test --release --locked` 通过 22 项；7 场完整昼夜对局、14 个席位投影均有双方开火命中并可重演，昼夜均有实际雷击战果。[对局摘要](artifacts/battle-v2/ai-exchange-v2.json)。四场完整对局含夜航、挑战的原生与 WebAssembly 逐项一致：[比对](artifacts/parity-v2-final-20261106.json)。
- 最终 [Windows WebView2](artifacts/windows-smoke-v2-final-20261106.json) 与 [Android 横屏模拟器](artifacts/android-smoke-v2-final-20261106.json) 通过实际离线启动、舰况立绘、夜航、母港、保存恢复和重演，360 秒状态一致。Android 还通过触屏取消和后台中断；实体机未验。当前包用于本地测试。

| v2 本地测试包 | SHA-256 |
|---|---|
| [Windows x64 ZIP](release/CAS-Stage0-win-x64-20261106-144743-162.zip) | `77503eb2752a9ac0386e55020f4ee0e6ba0fb6179dde86f148bdadb04aee4618` |
| [Android APK](release/CAS-Android-0.1.0-preview-20261106-144805-185.apk) | `c2b35d2b8c64e160034b0c6ac46421c910a46fa5dda6f0a96d6693597566a2ec` |

大厅和模式沿用铁底湾手游；夜战教学、开场序章、正式大厅和配音播放待接。当前语音触发键已随本席实际战报输出，未绑定旧音频。接线、规则边界与阻塞见[手游迁移](docs/mobile-migration.md)。

## 2026-11-06｜独立雷达演习的权威内核

- `cas-radar-v3` 独立虚构演习启用已核 1943 弗莱彻水面搜索实装 SG／SC-2。每舰按设备获取和保持接触，迟一探测窗转发冻结位置，支持开关、海岸遮挡、已核传感器失能及搜索雷达炮击。接触编号只在本席有效，画面数据不含敌舰身份、航向、航速或真态弹道。旧 v1/v2 及其安装包保留原版本。
- `cargo test --release --locked radar::` 通过 6 项，包括运行中的实际炮击造成受损、双盲、地平线、杂波、次窗分享、关机重演和 Mk4 计算。`python data/rules/check_radar_source.py` 核过 6 份原件、10 艘圣乔治角舰和 12 条原表算例。原生 `cas-sim demo 6106 allies radar`／`axis radar` 两席跑完整局并重演，均为同盟 4 比 0；同盟 63 次开炮，其中 60 次用直接雷达，轴心 49 次开炮，两边均有受损记录。
- Mk4 火控只实现计算和边界用例；尚不用于对局。雷达演习尚无浏览器大厅入口；现有 Android/Windows 包未更新。历史关、探照灯及其他夜间范围见[夜战裁决差额账本](docs/rules/night-gap.md)。

## 2026-11-06｜原手游母港、CAS 序章与夜战教学

- 从铁底湾手游工作树直接迁入母港组件、样式、夜海底图、登录界面、序章脚本及素材、七日签到页面。登录首屏使用独立本机账号，成功后进入原母港；不同本机账号的舰库、活动、战局和序章进度隔离。沿用现有 CAS 四种舰型的体验舰库和招募池。新增补给商店周券与挑战复战：真实完成五局，首通单领，重复四局最多领三次，每次两张常驻券；挑战立即重启恢复、周补给与签到幂等均通过。[离线验收](artifacts/client/final-offline-v3/browser-receipt.json)。
- 保留《未明的海》的剧情分支、领舰选择、人物与结尾 CG。开场当前为真实 CAS 5 对 5，原具名大舰队仍待舰卡与部署。浏览器走通三段实时实操和一次性见面礼；夜战十步完成，模拟第 360 秒取得接触、第 540 秒照明起亮、第 720 秒炮击、第 900 秒鱼雷离管。[序章与夜战验收](artifacts/client/final-story-v3/browser-story-receipt.json)。
- 海图演习可选择 1943 雷达；舰况可开关本舰设备，回波仅显示本席有权知道的数据。炮雷实体、重要事件提示、炮塔旋转、范围圈和舰娘舰况仍通过浏览器复核。照明弹和水面搜索雷达是各自独立的规则版本，旧战局继续按原版本重演。[战斗验收](artifacts/client/final-visuals-v3/browser-visual-receipt.json)。
- 双线 32 个旧关位已可查阅；16 个不同想定中有 11 个与 CAS 原书同一历史交战，均已录入并逐个验证详情显示；其余 5 个保留为相关、原创或未定位。210 个旧舰身份已登记，圣乔治角十艘的时期配置和序章五舰的有日期原页已核。圣乔治角双方胜利规则已写成可测试判定；历史关 **0 个开放出击**。[战役对照](docs/campaign/source-crosswalk.md)。
- Rust 32 项测试通过；原生与 WebAssembly 的六场完整对局与本席重演一致，包括实际照明和雷达炮击。[跨内核验证](artifacts/parity-v3-final-20261106.json)。Windows WebView2 和飞行模式 Android 模拟器验过注册、登录、母港、档案、存档、恢复和重演；Android 另外验证了触屏取消和切后台。两端包内 18 个共用文件逐字节一致。Android 实体机尚未验收。

| 离线试玩包 | SHA-256 |
|---|---|
| [Windows x64 ZIP](release/CAS-Stage0-win-x64-20261106-160346-708.zip) | `f3ead141edf65da3184353c03db192ea23ee8792f3d5996b7df8c945648672a1` |
| [Android 调试 APK](release/CAS-Android-0.1.0-preview-20261106-160408-960.apk) | `20e22656654b022cf357bec24220aa99059d82bc25ed56d4286a60cf8935b68c` |

包体验收：[Windows](artifacts/windows-smoke-campaign-all11-20261106.json)、[Android](artifacts/android-smoke-campaign-all11-20261106.json)。[规则覆盖](docs/rules/coverage.md)和[手游迁移记录](docs/mobile-migration.md)列出尚未启用的完整舰表、机制、原手游经济和在线服务。

## 2026-11-06｜主炮原页与圣乔治角炮表复核

- 核对五版 §2.2.2、§2.3.4、§6.1、玩家表和四型舰卡，记下原书的火力窗口、炮座射界及弹种表。§6.1.5 是轻防空对海；主炮装填、横转和飞行秒数单列为 [RTS-GUN-04 改编](docs/rules/realtime-gunnery-sources.md)，不写入历史舰卡。
- 圣乔治角时期包升级至 `cas-cape-st-george-1943-hulls-v2`。逐列复核七个 Annex C 炮弹数据行，更正美舰 Mk30 高爆弹近／中档伤害为 18／15 DP。[战役资料检查](scripts/check-campaign.py)和首发舰表数据检查通过。此次只验证资料；历史关出击仍受运输雷装、撤离与夜战裁决差额约束。

## 2026-11-06｜Mk4 接入 1943 实时雷达演习

- `cas-realtime-v4` 雷达演习仅给已核实装的弗莱彻启用 Mk4。炮击须有本舰目视、可用前向指挥仪和合法雷达视线；本舰射击时才应用 +2 和低能见度豁免。炮口闪光、共享报告、纯搜索回波、尾向及关机／损伤均不误用这项加成。见[原页、接线与差额](docs/rules/radar-source.md)。
- Rust 38 项通过（雷达专项 7 项）：相同 D100=60 实际开火，开启 Mk4 命中扣伤、关闭落空，标签只出现在开火方战报；开关及 v3 旧局可重演。原生种子 6106 的 v4 雷达演习双方均有受损，双席完成并逐项重演一致，同盟战报 85 次标注 Mk4，轴心 0 次；两席结果均为轴心 2 比 1。资料脚本通过 6 份原件哈希、10 艘历史配置和 12 条算例。上述不含历史关或安装包验收。

## 2026-11-06｜逐秒主炮、旧部署和手游表现

- 新局默认 `cas-realtime-v4`。玩家可随时下令或取消尚未发射的炮座，撤销 AI 的待发炮击会接管炮击任务。炮座有实际转向和装填时钟，已知舰艇可挡住射线。炮弹按距离和有效弹速飞行，到达后处理命中；鱼雷尾迹显示本席确认的航段。[实时手势验收](artifacts/client/final-v4/browser-realtime/browser-receipt.json)中预计和实际首发均为第 247 秒，弹着为第 284 秒，可见鱼雷尾迹超过 1.2 公里。
- 全 16 个原想定／32 个双线关位均有可查看的档案：11 份 CAS 原书记录，5 份旧手游相对阵位和任务，共 159 个开局舰船部署；午夜关另存原版默认整列后的 91 舰。两侧开局与铁底湾 0.6.9 固定快照回放对照通过。[旧部署记录](docs/campaign/legacy-deployment.md)。历史与回退想定依然 **0 个通过出航验收**，未复用旧作武器数据或给未核舰套舰卡。
- 复用原手游征募到港演出，用实际征募凭据展示、跳过及回看，实测不会重复扣券；通过[离线与挑战回归](artifacts/client/final-v4/browser-offline/browser-receipt.json)。[序章与夜战回归](artifacts/client/final-v4/browser-story/browser-story-receipt.json)完成原剧情分支、三段真实手势、一次性奖励及夜战 10 步，照明 540 秒、炮击 543 秒、鱼雷 900 秒。
- [本地舰队电台](artifacts/client/radio/browser-receipt.json)按阵营播本席真实事件，验过后台暂停、回放不重播、音量和关闭。普通生产包含 0 段旧录音；显式本地试玩构建含 16 段与旧文件哈希相同的通用电台录音。指挥官专属录音和 BGM 未迁入。
- Rust 39 项测试通过；[原生与 WebAssembly](artifacts/parity-v4-final-20261106.json)九场对局及同席重演逐项一致，包含实时昼战、照明和 Mk4。旧版炮战和存档继续按各自版本运行。[规则覆盖](docs/rules/coverage.md)和[手游迁移](docs/mobile-migration.md)维护未完成项。
- [Windows WebView2](artifacts/windows-smoke-v4-legacy-radio-20261106-174104.json)与[Android 飞行模式模拟器](artifacts/android-smoke-v4-legacy-radio-20261106-174126.json)实装通过离线登录、母港、战役档案、实时演习、保存与重演。Android 逐项打开 11 份原页与 5 份回退档案，并验证横屏触控和后台取消。两端 360 秒状态一致，[35 个共用包内文件](artifacts/packaged-shared-web-v4-legacy-radio-20261106-174126.json)逐字节相同。Android 实体机未验。

| v4 离线试玩包（含本地电台） | SHA-256 |
|---|---|
| [Windows x64 ZIP](release/CAS-Stage0-win-x64-20261106-174104-420.zip) | `aa30095c1af72a5655407eb1f6ace4f02b964d3a55490bd4273071cc023843dc` |
| [Android APK](release/CAS-Android-0.1.0-preview-20261106-174126-905.apk) | `40911056ea8041882e21629c593dfcbc8a3ffd30d756dd1b877a75c3513582ee` |

## 2026-11-06｜弗莱彻战败 CG
以用户确认的项目原始弗莱彻立绘为参考，内置 imagegen 单独绘制十张 1536×1024 PNG。逐张目检角色、动作、表情与构图；验证十份文件内容互异且 PNG 与 ZIP 可读。[素材包](artifacts/fletcher-defeat-cg-20261106.zip) · [提示词和分镜](artifacts/fletcher-defeat-cg-20261106/prompts.md)。独立美术候选素材，未接入发行包。

## 2026-11-06｜双线战役可玩、具名舰况和独立联机内测

- 新增 `cas-campaign-v5`。[圣乔治角](docs/campaign/cape-runtime-sources.md)按原页放入十艘具名舰和四个纵队，实际雷达炮击、鱼雷命中和撤离均可复盘；同盟种子 6106 击沉目标获得决定性胜利，轴心同种子换两条航路使五舰越线并获得决定性胜利。直航雷可用本舰连续两窗直接雷达观察解算，单点、共享点与关机后的失效样本不通过；无效发射不扣雷。三艘运输舰未核定载荷和雷装，当前禁雷。
- [通道行动](docs/campaign/channel-runtime-sources.md)找不到同一 CAS 想定，保留旧作八舰阵位、航向、开局速度、四回合和任务，使用同期 CAS 舰体、武器和损伤。测试同盟达成战略胜利，轴心三舰全部存活且未降至目标航速、取得战术胜利并有实雷命中。J/K 轮机共舱特例据五版 §8.3（PDF 107）和《Home Fleet》A-36 生效；实测普通轮机临界由一档变两档、锅炉爆炸由两档变四档，直接伤害不加倍。原剧本的逐舰备雷、雷达等未补值。两关开放同盟与轴心共四个关位，其余 14 场／28 个关位仍只显示档案。
- [浏览器战役验收](artifacts/client/campaign-final-v5/browser-receipt.json)走过两关双线、三档选项和存读档重演，逐舰解码 18 张原手游立绘并核验 SHA-256。圣乔治角同盟实战三星奖励到账 600 补给币、4 常驻券、10 勋章，通道行动轴心实战两星奖励到账 600 补给币、2 常驻券；换难度不能重复领，圣乔治角另外验证重启及账号隔离。三档目前对应不同敌方 AI，尚无完整的难度平衡验收。
- [独立账号服务](server/README.md)迁入双池、双券、保底、邮件、免费商店和七日签到（第七日北卡罗来纳仍待核准舰卡）。圣乔治角双线使用原生 CAS 服务权威推进、只发本席观察，并用真实战果计战役及周任务。11 项服务测试通过。[联机浏览器凭证](artifacts/client/online-v5-final/browser-receipt.json)包含签到、重登防重、邮件、征募、兑换和回到同一权威战役。当前只为本机回环内测；个人舰队线上作战、排位、支付和公网部署均未开放。
- Rust 44 项测试通过；[原生与 WASM](artifacts/native-wasm-campaign-v5-final-20261106.json)13 场完整对局和同席重演逐项一致。[Windows](artifacts/windows-campaign-v5-final-20261106.json)与 [Android 飞行模式模拟器](artifacts/android-campaign-v5-final-20261106.json)实装验证离线登录、母港、两关开局及重演，Android 另验证触屏取消与切后台取消。两包 [36 个共用文件](artifacts/packaged-shared-web-v5-final-20261106.json)逐字节一致，均未包含规则 PDF。Android 实体机未验。[序章与夜战教学](artifacts/client/story-campaign-build/browser-story-receipt.json)及[实时主炮、弹道、可见雷迹](artifacts/client/campaign-v5-realtime/browser-receipt.json)也通过回归；序章开场仍是标明的 5 对 5 演示。

| 当前离线试玩包 | SHA-256 |
|---|---|
| [Windows x64 ZIP](release/CAS-Stage0-win-x64-20261106-185902-769.zip) | `05ae4a9538b127ffc54fa8d5f2ba47a9b0f75800534aa816827d6246e2c13359` |
| [Android APK](release/CAS-Android-0.1.0-preview-20261106-185924-381.apk) | `0fbae65cb9cc1adaae3b267f25b44d60204523d10a303c6d0f8c81c3b61df93d` |

霍腊纽已复核五版《Rising Sun》PDF 89（印刷 88），整理[八艘具名驱逐舰](data/campaign/period/horaniu-1943.json)和[两类驳船与小艇裁决表](data/rules/small-craft-source.json)。独立终局函数已验驱逐舰 50% 损伤门槛、运输艇 6／7 艘及两边可同时战术胜利；代码共 46 项 Rust 测试通过。坐标冲突、三类护航艇的时期或型号以及登陆区仍留待处理。该函数没有接到实战，安装包和大厅不将霍腊纽标为可玩。

## 2026-11-06｜实时主炮装填复核

- 按五版 PDF 17、57–58 复核计划、反应、火力组与 D100。新局 v6 的弗莱彻 Mk30 装填以 4 秒为参考，阳炎、天雾和夕雾以 12 秒及每秒 6° 横转为参考。其他暂定项与史料适用范围登记在[实时主炮台账](docs/rules/realtime-gunnery-sources.md#v6-装填与横转史料复核)。
- 同条件下一窗实际发射 30 批和 45 批，两者累计伤害一致。47 项内核测试、11 项服务测试、13 场原生与 WASM 重演通过。新版重读旧安装包产生的三份演习与战役存档，观察、战报和续战一致。[对局重演](artifacts/native-wasm-gunnery-v6-20261106.json) · [旧档对照](artifacts/gunnery-historical-audit/legacy-replay.json)
- 实时手势与夜战教学通过浏览器回归。Windows 与 Android 飞行模式模拟器验收 v6 开局、保存和重演，两端 360 秒状态哈希一致。Android 尚未测试实体机。[Windows 验收](artifacts/windows-gunnery-v6-final-20261106.json) · [Android 验收](artifacts/android-gunnery-v6-final-20261106.json)

| v6 离线试玩包 | SHA-256 |
|---|---|
| [Windows x64 ZIP](release/CAS-Stage0-win-x64-20261106-201315-311.zip) | `0ec37df612b5b68947b68f0f3d24a9e5a1b4fadd5e1d66ffde0fb672410824cb` |
| [Android APK](release/CAS-Android-0.1.0-preview-20261106-201338-728.apk) | `4f252a386ddc1fc88e447410c8262f21d9160ec6240119822991336d6141d93c` |

## 工作区缓存清理

将 27 个目录和 244 个散文件移入回收站，共 3,627,680,026 字节。范围包括编译中间文件、临时调试及核页文件、空录屏和 14 个旧 Windows 解包目录。每个旧解包目录均先核对 ZIP 的登记 SHA-256，再逐文件核对内容。复查 16 个 ZIP、13 个 APK 和各自的校验文件仍在，当前运行和最新版的 Windows 解包目录均保留。原始资料、素材、验收凭证和现用运行依赖保留，清理未报告失败。


## 2026-11-06｜水面炮击临界损伤即时化

- 演习与战役 v7 的实际弹着累计 180 秒内对本舰的炮击 DP，保留 CAS 五版 §8.1.2 的 D6 数量表和 D20 类型表，只在伤害增加临界名额时当场裁决。实测穿甲弹着时立即停用一座主炮，下一次齐射从两门降到一门，同秒已发的炮弹继续飞行。未穿甲对照保留炮位，旧版等窗口关闭。[原页、时序与两份舰炮战损报告](docs/rules/realtime-gunnery-sources.md#v7-临界损伤的即时裁决)
- 49 项内核和 11 项服务测试通过。13 场原生与 WASM 观察、战报与重演一致。用旧包生成 v4、v5、v6 共六份存档，v7 的重演、读档和续战一致。浏览器验收实时拖拽、两条战役线的真实战果与奖励、序章及夜战教学。[跨端重演](artifacts/gunnery-historical-audit/critical-v7-native-wasm.json) · [旧档](artifacts/gunnery-historical-audit/critical-v7-legacy.json) · [手势](artifacts/gunnery-historical-audit/critical-v7-browser-realtime.json) · [战役](artifacts/gunnery-historical-audit/critical-v7-browser-campaign.json) · [序章与教学](artifacts/gunnery-historical-audit/critical-v7-browser-story.json)
- Windows 离线试玩通过开局、保存、重演和大厅测试。Android 已构建、验签并逐字节核对两个包的 36 个共用文件，本次 APK 尚无安装运行验收。[Windows 凭证](artifacts/gunnery-historical-audit/critical-v7-windows.json) · [安装包哈希](artifacts/gunnery-historical-audit/critical-v7-packages.json)

| v7 试玩包 | SHA-256 |
|---|---|
| [Windows x64 ZIP](E:/CAS-build-v7/CAS-Windows-v7.zip) | `729ba8a50f4f8bb6630e632ed8eda511f3db9f4e0fe0b12d39d6ea0fe3756eca` |
| [Android APK](F:/CAS-wasm-v7/CAS-Android-v7-preview.apk) | `c000c63ea293321f771e299d8f74a760c736e60e665c9d5e13382a27b584364f` |


## 2026-11-06｜连续航线、舰队序章与中文战役地图

- 标准舵 v8 用圆弧连接航段。两种机动均通过实际圆弧及一致预览测试，过短的近掉头航路会被拒绝。浅航直航雷接入 A 级舷向表、A/B 舷侧减伤和 F/G 目标排除。炮座来源与暂定量见[规则台账](docs/rules/continuous-navigation.md)。
- 序章中 15 艘舰和实际炮雷同屏。双方战列舰开火，护航舰的十枚鱼雷在交接前离管。玩家随后接管五艘具名驱逐舰，旧剧情分支和同图对白保留。浏览器以真实手势验证两种机动、撤回草稿、拖炮、调角放雷及一次性领奖。固定夜战实测第 180 秒出现本舰回波、第 720 秒目视、第 900 秒照明实际起亮。[序章与教学凭证](artifacts/v8-acceptance/story-and-night.json)
- 铁底湾 0.6.11 的六张战役地图接入中文档案，双线 32 个关位均通过浏览器检查。圣乔治角和通道行动四个关位通过出航、战果、重演和评级奖励验证。其余 28 个为档案。联机舰库可保存个人舰队草案，3000／10000 分编制由服务验证。CAS 点价、个人舰队出战、排位及第七日签到仍未开放。[战役地图](artifacts/v8-acceptance/chinese-campaign-map.json) · [编队](artifacts/v8-acceptance/fleet-editor.json)
- 52 项 Rust、14 项服务测试和 15 场原生与 WASM 对局对照通过，九份旧档的观察、战报与续战一致。电台和原创配乐均通过浏览器播放验证。Windows 包已实跑启动、保存与重演。Android 构建、验签及 58 个共用文件一致性通过，本轮未装机运行。[原生与 WASM](artifacts/v8-acceptance/native-wasm.json) · [旧档](artifacts/v8-acceptance/legacy.json) · [Windows](artifacts/v8-acceptance/windows.json) · [包内文件](artifacts/v8-acceptance/packages.json)

| v8 本地试玩包 | SHA-256 |
|---|---|
| [Windows x64 ZIP](C:/Users/fwj/AppData/Local/CAS-builds/20261106-v8/CAS-Windows-v8.zip) | `c199122df5373d194782847ff6758e8a9d6578c2da99739c08326af4dac5cefe` |
| [Android APK](C:/Users/fwj/AppData/Local/CAS-builds/20261106-v8/CAS-Android-v8-preview.apk) | `31f9225d21d4cf537c8e5d0c7d250ae11b02824cba729f6d2c04fcc76e193162` |

## 2026-11-06｜库拉湾双线可出航

- 库拉湾本地双线接入五版原页 17 艘具名舰、纸面部署海岸、10% 夜间能见、7 艘运输舰和维拉卸载计时。3 艘须同一段连续满 30 分钟。炮雷命中伤害和轻巡沉没触发两席各自判分，前台保留卸载进度的轴心座席限制。准备及剩余原书差额见[来源记录](docs/campaign/kula-runtime-sources.md)。
- 54 项内核测试通过，17 个原生／WASM 完整场景逐项与同席重演一致。同盟种子 6106 决定胜，轴心种子 2 实雷命中并取得战术胜，且两边可同时达标。浏览器通过两席出航、轴心 30 分钟卸载、保存重演、既有双线档案和领奖防重。新关先在本地运行。

## 2026-11-07｜v10 收尾与持续炮击、命中率显示、目视/雷达圈

- 持续炮击（v10）：炮击命令在首轮齐射后保持，各炮座按自身装填时钟逐次再射同一目标，直至取消、目标丢失或炮座失能；拖到新目标直接转火（停火事件），AI/剧本的重复下令不打断持续射击；持续期间的脱落以「停火」事件代替「未开火」拒绝。时限在每次实际发射后刷新。
- 拖动命中率：炮击拖拽途经每艘敌舰时，手势提示显示该舰的当发命中率（`volley_chance`，与实际掷骰同源）；0% 命中时 AI 持有无浪费弹药的门控。
- 目视/雷达圈：所选舰射程圈新增目视圈（当前环境对同尺寸舰的目视基准距离，CAS §5 概率探测的确定部分）与雷达圈（本舰已开机水面搜索雷达对同尺寸目标的名义距离）；图例与开关文案同步。
- 序章引导修复：v10 即时发射让发射事件先于下令回执到达，引导证据序列丢步导致教练卡在「看到鱼雷真正离管」——fire() 在发令前同步记录手势信号。浏览器 story/offline/online/ranked/visuals/realtime 全部回归通过。
- parity 17 场（cape 6116、channel 17/6107 种子按 v10 平衡重定）与引擎 61 项、服务端 28 项、tsc 通过。

## 2026-11-07｜v10 探测、照明弹实时化与历史转速接源

- **目视探测逐秒化（RTS-DETECT-01）**：印刷探测表对全部 D100 穷举积分成窗内概率（含每观察者的提示/开火修正），再化为逐秒独立危险率；解析恒等式 `(1−p)²¹⁸⁰ = 1−P` 与 2 万次蒙特卡洛测试证明窗末分布与原书一骰一致。确定性部分（已知舰、自动发现带、基准距离内）每秒直接判定。
- **雷达采集逐秒化**：每设备×目标按代次采集概率逐秒掷危险率；实时图逐秒更新，但共享迟一窗、两窗直航雷解算对与修剪保持 180 秒窗界（解算对齐改为最近完成窗界）。夜战教学与直航雷两窗约束全部保留。
- **照明弹实时化（RTS-LIGHT-01）**：下令后炮座转好装填完即射（通常数秒），反应照明天然可用；未对准逐秒重试，窗界过期才拒绝；每窗一座一次与一窗燃烧按 CAS 原值。
- **历史转速接源**：弗莱彻 Mk30 单装横转 18°/秒（暂定）→ **28.7°/秒**（NavWeaps Mk30 GE 电力驱动 28.75°/秒，Ford 34°/秒取低）；克利夫兰 Mk16 10°/秒接 NavWeaps "All: 10 degrees per second" 转为已核；阳炎级 6°/秒获 NavWeaps 第二来源一致。装填值不变（DD-793 炮位记录 / 保守值）。
- **状态面板炮座方位角**：舰况面板每炮座显示当前绝对方位角（与海图炮管条同源）。
- 平衡偏移（平衡后果登记，非 CAS 裁决改变）：圣乔治角同盟决定性→战术（更早接敌，己方驱逐舰损伤超 25% 限额）；通道行动同盟种子 6107→6112、轴心 17 保持决定性；cape 测试种子 6116 战术+实雷。parity 17 场全过（夜训照明流程改为接触驱动动态选靶）。
- 浏览器 7 项回归全绿；引擎 64 项（新增危险率积分、蒙特卡洛、自动带确定性 3 项）。

## 2026-11-07｜接手恢复：排位服务、线上征募与征募台样式

- 按接手说明从 `d3f907a` 恢复主线。修复 `client/src/main.tsx` 双席结局键类型错误：`cloud.current` 改按 `onlineBattlePath` 生成稳定 key，`tsc` 通过；01/03 双线结局（[凭证](artifacts/client/campaign-endings/)）、本机抽卡（[凭证](artifacts/client/port/browser-receipt.json)）、序章夜战与固定约战四项浏览器回归全部通过。
- 合入 F:/CAS-audio-work 排位服务差异，**代码已合**（`94833f4`）：新增 `server/rankings.py`（点表准入、42 天赛季、K24 Elo、按账号×档位独立梯）、`duels.py` 排位队列/结算/作废 CLI、`fleets.py` 点表校验、`battle_pve.py` 补 v9 `torpedoDepths` 视图键与雷深/分量齐射命令字段。16 项服务测试（含原生内核双席 2 项）通过；**本机实测**排位服务启动探针验证冻结点表与内核 `match_pool` 导出一致，`/pvp/ranked/status` 返回 S0001 赛季与 3000/10000 两档 1000 起分；合并后固定约战回归重跑通过。尚未有玩家入口，**未对外开放**。
- 合入 F:/CAS-client-next 线上征募差异，**代码已合**（`d4666d9`）：`OnlineSupply` 接入 0.6.11 征募台组件（主题图、保底计、十连、到港三段演出、跳过、上次到港回看、UR 兑换、旧池与旧通用券），服务端征募回执补 `batch` 批次字段。工作区缺少样式文件导致客户端整体无法启动——按原版 `recruit-desk.css`／`arrival.css` 移植补写 `client/src/online-recruit/online-recruit.css`（含横屏短屏与 reduced-motion 适配）并提交（`600a7e2`）。
- **游戏内实测**：新增 `client/tests/browser-online-recruit.mjs` 专项验收主题图、概率页（各档保底表）、十连到港、逐舰揭示、跳过、上次到港回看、换池、重复请求幂等（同编号重放同回执、改参 409、钱包不变）、刷新重登恢复、指定兑换（进度 91→11）、740×360 短屏到港、重登余额对账，全部通过（[凭证](artifacts/client/online-recruit/browser-receipt.json)）。`browser-online.mjs` 补到港演出关闭步骤后通过（[凭证](artifacts/client/online/browser-receipt.json)）。
- **主仓全套复验**（验收 agent，隔离 target，HEAD `b99c29a`）：Rust 59 项、原生与 WASM 17 场对照逐项一致、服务端 16 项（含模拟器路径实跑）、战役资料检查（16 想定/32 关位/11 登记/210 舰身份）、`tsc` 0 错误，7/7 通过（[台账](artifacts/cas-acceptance-20261107.json)、[对照](artifacts/cas-integration-native-wasm-20261107.json)）。

## 2026-11-07｜排位前端接线与双档验收（ranked-ui-v1 工作区）

- 线上舰桥新增排位赛页签：展示当前赛季（S0001 起止与 42 天时长）、点表版本、3000／10000 两档段位卡（白银起步、战绩与 rank 名；10000 分档按 `available_budgets` 显示未开放并禁选）、历史赛季战绩（`historical_ratings`）与排位战况（含胜负与积分变化）。入队按 `available_budgets` 限制档位，出战预设下拉只列服务端 `ranked_ready` 的预设并显示实际点价；排队显示到期时间并可取消，取消后不再匹配。
- 云端编队页接服务端 `validation`：预设列表与保存回执显示点价、`ranked_ready`、`blocking_reasons`；点表可用时提供「前往排位入队」直达排位页签，未接入时保持「排位未开放」。战局侧：排位战局隐藏 AI 风格与指挥权限选择（显示冻结说明），战术建议保留且须本人确认；战果卡展示档位、赛季、点表、本席舰队与点价，`rated` 时显示积分变化与段位；`status=complete` 且 `rated=false`／引擎 `result=null`（服务故障作废）时停止全部操作并显示「本局作废、积分不变」。
- 协议以实际合入代码对齐：`GET /pvp/ranked/status` 返回 `season/ratings/historical_ratings/queue/matches/available_budgets/point_table_version`；排位 summary 带 `mode='ranked'`、`budget`、`season_id`、`own_fleet`、`fleet_cost`、`rated`、`rating`。与 roadmap 文字的两处差异：点表版本实际为 `cas-points-surface-v1`（文件名才是 cas-competitive-points-v1.json）；`end_reason` 作废时当前代码固定为 `server_fault` 而非 null，前端按 `rated=false` 或 `result=null` 兜底。
- 验收（全部真跑）：服务端 16 项单测含 2 项原生双席测试通过（`CAS_TEST_DUEL_SIM_PATH` 指向本次构建的 cas-sim）；`tsc` 通过；新增 `client/tests/browser-online-ranked.mjs` 两席全新账号序章领舰、1875 分预设、实际匹配、双席各自战局、一席投降、两席排位战果（+12 白银／−12 青铜）、取消入队不再匹配、操作端 CLI 作废后两席停止操作且积分不变，凭证与截图在 artifacts/client/online-ranked/。回归 browser-online-duel.mjs、browser-online-fleet.mjs、browser-online.mjs 全部通过。
- 剩余边界：10000 分档等点表开放后需另行验收；`end_reason=null` 的作废形态当前服务端代码不会产生，前端已兼容但无实测；排位战果的重演入口沿用既有战报，未单独录结局图。
- 分支 `ranked-ui-v1` 已审查合入主仓（`3e51193`），排位服务契约按实际代码登记进 `docs/battle-contract.md`（`1c3847d`）；合入后在主仓重跑 `browser-online-ranked.mjs` 通过：两全新账号实际匹配、投降结算 −12 与积分变动、`--void-ranked` 作废后两席停止操作且积分不变（[主仓凭证](artifacts/client/online-ranked/browser-receipt.json)）。

## 2026-11-07｜塔萨法隆格原页核页与时期录入
- 《旭日》五版 PDF 75–76（印 74–75）逐页目视核验：19 艘具名舰为美方 11（5 巡洋舰＋6 驱逐舰）＋日方 8 驱逐舰，原页无具名驳船单位；三处 Resupply Point、1.5 海里半径、每点三舰、每舰五串每窗一串、卸货限 2 节、未卸串扣分、载桶六舰无备用雷（长波/高波各 8 枚）均按原页登记。
- 500/250 两档原页都印「Decisive」，原样保留；RTS 分级登记采用 500=决定、250=战术并要求用户可见内容标明采用分级，两条门槛随美方 120/240 在 `check-campaign.py` 的 `verify_tassafaronga()` 中分别断言，普通与 `--ibs-worktree` 两种运行方式通过。
- 8in/55（AF C-3 四弹种行）、6in/47（C-2）、5in/38 与 12.7cm/50（对照圣乔治角 v2 逐列一致）、Mk15 TNT（F-1 单档 87 DP）与 Type 93（EF F-1 95 DP）登记进 `data/campaign/period/tassafaronga-1942.json`（source_only_not_runtime_ready）；Mk15 与旧登记的三档速度差异列为未决冲突，未擅自合并。
- 来源与冲突登记在 `docs/campaign/tassafaronga-source-notes.md`：Form 10 索引三处页码错误已目视改正（Maury=320、Kuroshio=106、Oyashio=109），Kagero 已完成 4–5 月反潜改装而 Oyashio/Kuroshio 未改装的 DC 差异分别建档。纵队逐舰座位、补给点坐标、弹种实配等 10 项待裁决留空，未以默认值填补。引擎接线未动。
- 分支 `tassafaronga-entry` 已审查合入主仓：`check-campaign.py` 的 `verify_tassafaronga()` 在主仓实跑通过，档案层偏差与 10 项待裁决见[源笔记](docs/campaign/tassafaronga-source-notes.md)；引擎接线另行验收。

## 2026-11-07｜埃斯佩兰斯角与萨沃岛原页录入、排位服务端验收

- **埃斯佩兰斯角（02）**：分支 `entry-esperance` 合入主仓。《旭日》PDF 65（印 64）单页正文、无海图；14 艘具名舰（美方 9：旧金山/盐湖城/博伊西/海伦娜+Desron 12 五驱逐，日方 5：青叶/古鹰/衣笠/吹雪/初雪）加 1 架 SOC-3；三种开局（2324 标准、2339 海伦娜无线电、2345 目视 5000 码）与 2330 反航记录核出；14 舰雷达逐舰核名（盐湖城显式无雷达）；原页**没有**可选增援与输送/撤离条款，如实登记为「原页没有」；10 项待裁决未以默认值填补（[源笔记](docs/campaign/cape-esperance-source-notes.md)）。`scripts/check-cape-esperance.py` 主仓实跑通过（14 艘、17 页已核 Form 10、0 failures）。
- **萨沃岛（10）**：分支 `entry-savo` 合入主仓。《旭日》PDF 52–54（印 51–53，扫描页逐页目视）；同盟 32 艘舰体+19 艘运输（哨舰/南北队/东屏护/X-Ray/Yoke 屏护/Transdiv 12/运输队）与轴心 8 艘+3 备选（鸟海旗舰，纵队顺序 Aoba→Kako→Kinugasa→Furutaka 与列举顺序差异两处照录）；环境整句（夜 10% 能见、满云 2000 米云底、萨沃 3 海里雷暴带闪电、0611/0633 天光）；「未进战位+被探测后 D6/3 回合禁射」特例登记；美 8in/55、日 20cm/50 No.2、英 8in/50 MkVIII 主炮行及 Type 93 M1 Mod 1/2 等逐行核定；月光相位与照明规则原页未给，10 条冲突 13 项待裁决（[源笔记](docs/campaign/savo-island-source-notes.md)）。`scripts/check-savo-island.py` 主仓实跑通过（40 具名实例、23 辅助舰体、20 profiles、13 炮雷型号）。
- **排位服务端验收**（`d7d453a`，`server/test_ranked.py` 12 项全过）：点表准入门（免费 FLETCHER/PERKINS/MAURY 三舰 1875 分合法、五舰 3050 分超限拒绝、错阵营/未拥有/风格未解锁/风格不支持各拒）；队列重试幂等（同编号同回执、改参 409）；匹配后投降结算 ±12；**真实互射到自然终局**（双方航线接近、逐窗对射、战报含双方炮击事件）；**平局结算**（时限 0:0 draw、双方 delta 0、draws+1）；作废不入账；服务重启后同局恢复；结算幂等（settlements 单行、重放同回执）。全套服务端 28 项通过，Rust 59 项不受数据合入影响。
- 剧本录入按指示在此暂停：科隆班加拉岛（08）工作区 `E:/CAS-entry-kolombangara`（分支 `entry-kolombangara`）已建好待后续启动；03/04 的补核、11 奥古斯塔皇后湾等继续按台账排队。

## 2026-11-07｜操作点击音效与指挥官录音最小子集

参考仓清点（`F:/Codex/worktrees/android-mobile/铁底湾` 提交 `41a1fb9`，只读）：`mobile/public/audio` 共 828 个 m4a、37,278,066 字节。33 个语音包 = 31 个碧蓝角色包（780 文件、26,875,107 字节）+ `wows-jp`／`wows-us` 两个阵营包；另 6 首 BGM（9,770,710 字节）。原作用 `SoundDirector.uiCue` 在运行时用 WebAudio 正弦振荡器合成点击音，**没有**点按／确认／选舰／错误的音频文件，故本批不复制任何录音来冒充。

- 操作点击音效：按原参数实现 `client/src/audio/click/ClickCues.ts`（tap 1250Hz、confirm 720→1080Hz、select 900Hz、error 220→170Hz，音量 `uiVolume×0.11`，静音/后台不播）。接线沿用原作分流：普通控件 tap、主行动 confirm、选舰 select、失败与拒绝 error；开关与音量存于 `{账号}:ui-cues`（默认开、0.35）。台账：[click/ledger.json](client/src/audio/click/ledger.json)。
- 指挥官录音：只迁 `al-enterprise`（碧蓝 · 企业）六个本席真实战报 cue，每个取 `-0` 变体，共 130,741 字节，逐文件 SHA-256 与源路径见 [commander/ledger.json](client/src/audio/commander/ledger.json)。其余 31 个碧蓝包（774 文件、26,744,366 字节）与两个阵营包各余 13 个变体（合计 800 文件、27,109,992 字节，不含既有阵营电台台账已迁的 16 个）登记为「存在但未迁，待授权核验」；碧蓝联动无公开发布许可记录。
- 接线：`BattleVoice` 新增语音包选择，选定的指挥官包只走自身文件、不回退阵营电台；无台账文件不接播放。构建沿用 `VITE_CAS_LOCAL_VOICE=1`：正式构建解析到空实现，本地试玩构建打包六段录音。
- 验证（Edge 无头，dev 5187，Playwright 取参考仓模块）：`client/tests/browser-radio.mjs` 通过——四类点击音、关闭后静音、音量 0.25 跨两次刷新持久化、选舰 select、主行动 confirm；指挥官 `battle_start` 按本席事件触发且只加载一次、配乐让音（0.54×gain×0.29）并在录音结束后回升。正式构建 dist 无任何 m4a、JS 无 `al-enterprise`／`wows-us` 引用；`VITE_CAS_LOCAL_VOICE=1` 构建产出 6 段指挥官录音与阵营电台，并在 `vite preview` 下实际播放。凭证：[browser-receipt.json](artifacts/client/radio/browser-receipt.json)、[local-build-receipt.json](artifacts/client/radio/local-build-receipt.json)、[语音包设置](artifacts/client/radio/settings-voice-pack.png)、[指挥官开战](artifacts/client/radio/commander-battle-start.png)、[本地构建实播](artifacts/client/radio/local-build-commander.png)。
- 回归：`browser-original-score.mjs`（五段配乐、让音、暂停恢复、无重播）、`browser-visuals.mjs`、`browser-offline.mjs` 均通过；`npx tsc --noEmit` 无错误。未迁移的 31 个角色包、碧蓝授权、指挥官包与剧情角色的正式绑定仍待核。

## 2026-11-07｜经济与舰库外层补齐：三舰礼包、第七日北卡罗来纳、全身立绘（econ-ui）

对照铁底湾 0.6.11（`6601bdd`）在 `E:/CAS-econ-ui`（分支 `econ-ui`，基于主仓 `1d3ff73`）补齐三项外层。未改 `src/`、服务端引擎裁决代码、`docs/rules`，未触碰主仓。

- **三舰礼包（服务端）**：`server/accounts.py` 的 `Purchase.kind="ship_bundle"` 已有校验（仅补给币、必须三艘且可征募、全拥有拒绝、余额不足报差额、`shop:ship-bundle:<id>` 一次性领取记录），本次补测试覆盖：未知礼包 404、改币种/带池号 400、差额文案、三舰发放、重复舰按 `DUPLICATE_MEDALS` 转勋章（火奴鲁鲁精锐＝5 勋章）、同 `request_id` 重放返回首次回执、换编号再购 409、已全拥有先行拒绝且不动收藏。礼包描述按 0.6.9 固定快照原样保留进投影（`server/import_catalog.py` 不再丢 `description`）。
- **三舰礼包（客户端）**：新增 `client/src/ShipBundleShelf.tsx`＋`client/src/ship-bundles.css`（移植 0.6.11 `mobile/src/economy/ShipBundleShelf.tsx`、`ship-bundles.css`，含横屏短屏媒体查询），`OnlineSupply` 补给商店页签在「免费兑换」上方挂货架。只渲染服务端 `/catalog` 实际下发且三艘均可征募的礼包；卡片显示阵营、三舰名与立绘（无资产回落剪影）、价格、`可购买/还差N补给币/三舰均已拥有/已购买` 状态。差异：原版船行显示「舰种 · 点数」，CAS 免费目录没有点数，改为「舰种 · 稀有度」。
- **第七日签到北卡罗来纳**：核验 `src/ranked_fleets.rs` PROFILES 的同稳定 ID 时期舰卡（`IBS-U-USN-UNNAMED-T01-R03`，`source_class north-carolina`，出处「序章时期包／美国舰表 PDF 8、109」），并确认 `data/campaign/period/prologue-runtime.json` 有完整可出战数值、`realtime.rs` 有该级装填/转速、点表 `cas-points-surface-v1` 已登记同名 ID（2500 分）。据此把目录该舰 `combat_ready` 置真并附 `combat_source`，`server/accounts.py` 启动时强制「就绪舰必须带出处」；`account_progression.py` 第七日实发该舰并在奖励里带 `ship_source`。已拥有时按稀有＝20 勋章转换，重复领取同请求编号幂等。目录其余 209 舰仍为 `combat_ready=false`。
- **全身立绘查看器**：新增 `client/src/ShipPortraitViewer.tsx`（对照 0.6.11 `FleetPanel.tsx` 的 `fleet-portrait-dialog`），`shipPortraits.ts` 增加按角色稳定 ID 查台账的 `shipPortraitById`。舰船收藏页只对 `client/src/assets/portraits/ledger.json` 实际登记资产的舰显示「查看全身立绘」；dialog 显示完整立绘＋舰种＋舰名，Esc／右上 ×／点击面板外均可关闭，740×360 横屏实测可用。无资产舰（如帕金斯）不出现按钮。
- **验收（全部真跑）**：服务端 32 项（`CAS_TEST_SIM_PATH` / `CAS_TEST_DUEL_SIM_PATH` 指向本次构建的原生程序）31 项通过；唯一失败 `test_battle_pve.AuthorityTest.test_real_victories_pay_fixed_rewards_once_and_weekly_clears`（同盟评级 `tactical`≠`decisive`）在干净 `1d3ff73` worktree 用同一二进制复现同样失败，属既有 v10 平衡偏移，非本次改动引入。`tsc --noEmit` 0 错误；投影校验 `python server/import_catalog.py <ref>` 通过（210 身份／22 可征募／2 池／3 礼包）。
- **浏览器实测**：新增 `client/tests/browser-online-supply.mjs`（真点击、截图、JSON 凭证在 `artifacts/client/online-supply/`）：签到第 1 天 500 补给币并核对第七天奖励已带北卡 ID 与出处、无「尚未就绪」旧文案；礼包货架恰为目录 3 包、每包三舰、价格文案；点「购买同盟巡洋支援包」→ 三回执（火奴鲁鲁重复转 5 勋章／明尼阿波里斯与旧金山入列）→ 钱包 1100 补给币、5 勋章并与 `/me` 逐项对账 → 卡片转「已购买」且按钮禁用；收藏页仅弗莱彻一个「查看全身立绘」，帕金斯无按钮；打开查看器校验 `data-character`、图片真实解码 1024×1536、并对服务端下发的 PNG 计 SHA-256 与台账 `43910f72…3428c` 一致；Esc／×／点外三次关闭；740×360 下 dialog 710×338、立绘 454×320；重登后钱包 1100/5 不变、货架仍「已购买」，换编号直接调 API 再购返回 409 且余额不变。回归 `browser-online.mjs`（PvE 服务 8035＋vite 5189）与 `browser-online-recruit.mjs` 均通过。
- 边界：单机离线档第七日仍锁定（本地存档无舰船所有权与转勋章通道），文案改为「单机档暂不发放签到舰船，联机内测第七天可领取」；礼包舰与签到舰均不进入个人出战队（目录 `combat_ready` 只影响展示与舰队门控说明，点表准入仍按自有舰校验）。
