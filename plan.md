# CAS 开发路线

CAS 独立建仓、发包、存档和账本。二次元成长沿用铁底湾手游思路，战斗采用 CAS 五版水面规则和明确记录的实时改编，参考鱼叉的确定性裁决和双盲架构。

0. Windows 昼战：5 对 5 演习、领舰和同步航路、多航点、炮雷手势、三种 AI、战报、存档重演、桌面包。先交付一场双方自主接敌、还击并能结算的真实对局。
1. Windows＋Android 单机：横屏包、教练、初始舰队、母港、编队、征募、挑战；实体机离线闭环。
2. CAS 夜战、双阵营战役、照明和雷达、剧情、评级与挑战周本。以已核验历史想定逐批扩充。
3. 跨端权威线上 PvE 和约战；3000/10000 分编制，独立账号与经济；非排位、排位、支付分批上线。

本批四路并行：资料核页、内核/AI、客户端、运行和包。阶段验收须以同一 Rust 内核、真实界面和实际交火为依据。范围逐项见 havedone.md 和规则台账。

## 当前批：军需处与军港征募（2026-11-09）

0. **口径**：`Harbor` 的 `recruit` section 改为「军需处」，内设舰船 / 补给配给 / AI 战术 / 礼包与兑换四个柜台；「军港征募」是独立全屏 overlay，从舰船柜台进入。抽卡概率与接口、服务端经济、`ai-shop.ts`、`data/ai`、`server/catalog`、舰卡、音频与 challenge/ranked 点价均不改，不新增货币。
1. **军需处**：新 [Quartermaster.tsx](client/src/screens/quartermaster/Quartermaster.tsx) 与 CSS；钱包显示信用点 / 舰队勋章 / 常驻券；周券、实战补给、AI 采购与 6 勋章炮战 AI 分别调用 `buyWeeklyTicket` / `claimWeeklySupply` / `buyAiShopEntry` / `getGunnery`。740×360 为顶部横向柜台、单列卡与底部采购条。
2. **军港征募**：新 [RecruitScreen.tsx](client/src/screens/recruit/RecruitScreen.tsx) 与 CSS；左侧卡池、中央夜间主视觉、右侧 UP / 概率 / 保底 / 兑换、底部征募 1/10。本地抽卡仍走 `port.drawRecruit`，概率、保底和到港回执沿用既有口径；概率 / 记录 / 兑换为抽屉，Esc 先关抽屉再关全屏。
3. **共享组件与视觉**：[widgets/economy.tsx](client/src/widgets/economy.tsx) 提供钱包、商品卡、抽屉、按钮与保底条；军需处为白天干船坞纸卡/黄铜/盖章，征募为夜间军港/探照灯/信号灯，两场景共享 `--cas-*` token。
4. **AI 战术**：读 [ai-shop.ts](client/src/ai-shop.ts) 的 6 条投影（当前 6 / 6，另一 agent 已落入），防御式渲染 `role / axes / fit / risk`；三轴支持 near/mid/far、brawl/screen/kite、direct/deny/support 枚举与数值两种形态。
5. **验收**：`tsc --noEmit`、`vite build`；新增 `browser-shop`（四柜台、钱包、周券/周补给、AI 6 卡购买、6 勋章 AI、刷新持久化、740 overflow=0）与 `browser-recruit`（双卡池、85/15 概率、十抽保底、1/10 连、记录/概率/兑换抽屉、Esc/返回、740 overflow=0）；保留 `browser-ai-shop`（6 卡）、`browser-lobby`、`browser-esperance` 回归通过。证据见 havedone.md。
6. **边界**：母港到军港征募为「母港 → 军需处 → 舰船 → 进入军港征募」，未新增第五个母港 dock，保持既有 4-dock 与路由 key；联机征募仍走 `OnlineSupply`，本次未改；AI 6 条的 `fit` 是验证均值，不是平衡承诺。

## 当前批：六套 evolved doctrine 与商店扩至 6（2026-11-09，AI 线）

0. **口径**：内置 `coord`/`gunnery`/`torpedo` 出招路径、`builtin-orders` 与 full-match hash 保持逐字节不变；三条旧 evolved（screen/torpedo/gunnery）的基因与真实 fitness 保持基线。新增 `evo-brawler`/`evo-kiter`/`evo-denial` 只走 `Style.evolved` 路径，商店从 3 条扩到 6 条，未改舰船卡、`data/ships`、portraits、audio、challenge/ranked 点价，未提交。
1. **目标与真实 fitness**：[ai_evolve.rs](src/ai_evolve.rs) 增加三个 objective：Brawler 以 3 km 内实伤、3 km 内接敌秒和击杀为主；Kiter 以 6 km 外实伤、6 km 射程维持率、存活与巡洋存活为主；Denial 以鱼雷直航轨迹覆盖敌当前航向投影（450 m 扇面走廊）、被覆盖敌舰数、威胁后 90 秒实际转向度与扇面宽度为主，命中只作小权重，不再只算命中。三个 objective 的 fitness 全部来自 `play_traced` 的真实 headless `World::advance` 对局，`basis=ga`，没有手写分数；Denial 的指标本轮已可用，因此未使用 `hand_authored` 回退。
2. **训练**：population 6、generations 3、rng_seed 6106、train seeds 6106/6107、validation seeds 6111/6112/6113、seats 0/1；Brawler/Kiter 在 doctrine envelope 内搜索射程、航速、雷击占比、T 头、屏护与撤退阈值，避免 GA 产出与商店描述相反的风格。产出 [evolved.json](data/ai/evolved.json) 6 profiles、[training-log.json](data/ai/training-log.json) 和 [ai-report.json](data/ai/ai-report.json)；[shop-merge.json](data/ai/shop-merge.json) 6 条。
3. **商店与服务端**：`AiShopEntry` 增加可选 `role/fit/risk/axes`（range near/mid/far、maneuver brawl/screen/kite、torpedo direct/deny/support），现有三条也补齐；新三条价格 900/1100/1200 常驻券，unlock 用 `CAMP-ALLIES-05`、`CAMP-ALLIES-11`、`CAMP-ALLIES-10`。要求的 `CAMP-ALLIES-06` 只存在于 crosswalk 档案、无运行时，按本批约定改用可通关的 `CAMP-ALLIES-11` 并在 ai-report 登记。`server/catalog.json` 的 `ai_profiles` 从 9 条改为 6 条（三条旧 evolved + 三条新），不再并列旧手游 6 条 AI；[import_catalog.py](server/import_catalog.py) 从 shop-merge 投影同样 6 条。
4. **服务端购买/解锁/重登**：`test_accounts` 覆盖 6 条逐条解锁与扣券（6000→100）、错误币种、重复购买、同 request_id 幂等、重启与重登；`test_battle_pve` 改为购买 `evo-torpedo` 并以种子 6150 取标准/挑战决定性，`battle_pve` 的 profile 枚举与解锁表同步 6 条。
5. **验收**：`cargo test --release --locked` 123 项全绿（含三条新 objective 测试）；服务端 34 项全绿；`tsc --noEmit` 与 `vite build` 通过；`cas-sim` 三条新 doctrine 各一场 evolved vs builtin 存档+重演；WASM 重建并跑 24 组原生/WASM parity（含三条新 doctrine，`nativeWasmCanonicalMatch=true`）。
6. **边界**：Denial 覆盖的是敌当前航向投影而非完整意图；Brawler/Kiter 的多舰同秒命中用最近本舰距离归因；新三条未接入排位/双席白名单；服务端 `battle_pve` 可出航 Stage 仍为 02/03/11，05/10 的解锁进度本轮由测试种子与本地战役覆盖，线上 PvE 注册这两关留作后续；UI 页面由并行 agent 做，本批只提供 6 条共享数据。

## 当前批：evolved AI 商店上架与战斗接线（2026-11-09）

0. **口径**：[evolved.json](data/ai/evolved.json) 的三条真实 fitness 战术（evo-screen / evo-torpedo / evo-gunnery）保持 provisional；只把它们接到既有免费经济，不改舰船卡、立绘、音频、AI 训练、evolved 基因/权重、challenge/ranked 点价，也不新增货币。
1. **服务端**：[catalog.json](server/catalog.json) 投影三条 `{cost, currency:"recruit_ticket", unlock:"campaign:CAMP-ALLIES-XX", provisional:true}`；[import_catalog.py](server/import_catalog.py) 从 [shop-merge.json](data/ai/shop-merge.json) 生成同一投影。`/shop/purchase` 的 `kind:"ai"` 按目录币种扣常驻征募券、校验战役通关解锁、拒绝重复购买；同一 request_id 幂等，资产落 SQLite，重登可读。
2. **客户端**：[Harbor.tsx](client/src/Harbor.tsx) 的 AI 战术室展示三卡（价格/解锁条件/provisional/禁用原因），本地购买扣常驻券并写入 `PortState.profiles`；联机侧 [OnlineSupply.tsx](client/src/OnlineSupply.tsx) 走服务端目录与 `/shop/purchase`，购买后用返回 meta 刷新。战斗内、演习设置、关前编成/特混/母港预设的 AI 风格下拉统一按已拥有过滤，未拥有选项禁用并标注原因。
3. **战斗**：`new` / `new_campaign` / exercise 的 `profile` 透传 evolved id；`Ai::validate` 既有支持；本地存档保存 `profile` 并在重载后恢复。
4. **验收**：`cargo test --release --locked` 121 全过；服务端 34 项（含 `test_accounts` 9 项）；`tsc --noEmit -p client`、`vite build`；`node tests/browser-ai-shop.mjs` 通过购买、重载、演习与战役进战斗、740×360 overflow=0。
5. **边界**：evolved 仍是 provisional 强度；服务端/客户端的在线 AI 商店浏览器购买未单列脚本（服务端购买由 unittest 覆盖）；未接排位/双席 AI 的 evolved 白名单。

## 当前批：91 张已核验舰卡并入排位注册表（111 → 202 可出战，2026-11-08）

0. **口径**：210 个稳定身份里，111 张已在排位注册表；本批把 `data/ships` 下 8 个来源包中已核验的 91 张并入：pdf Form 10 逐舰卡 12、APD 8、同型卡 13、CAS 同盟源表卡 21、CAS 轴心完整卡 10 + 历史轴心 7、ERMA USN 12（8 艘用 C-3 exact 炮表行闭合）、ERMA IJN 8。6 艘纸面/未建成（天城/赤城/尾张、伊吹/鞍马/五濑）、Midway(CV) 与夕风（无 CAS 表）保持收藏，**202/210**，不硬凑 208。
1. **数据**：新增 `data/ships/merged-cards.json`（91 条 `{identity,name,side,type,class_profile,source_file,source_kind,stat_verified,stat_source,conflicts,ship}`）。71 张直接复制源包里已登记的完整 ShipDef；12 张 pdf 卡按 Form 10 个体页 profile 的炮座/弹种/损伤-航速行重建；8 艘 ERMA USN 只补 `data/rules/gun-rows-erma.json` 的 Mk7/Mk8/Mk16 exact 行与 CAS 5e p.23（印刷 3-2）未印运动默认行。生成器 `scripts/build-merged-cards.py` 可重跑；源卡不改。
2. **内核**：`ranked_fleets` 的 `profiles()` 由 111 条手写 `LEGACY_PROFILES` + 91 条生成的 `MERGED_PROFILES`（`src/ranked_profiles_merged.inc`）组成，`PROFILES` 语义保持单一注册表；`data()` 新增 merged 解析路径并跳过 `stat_verified=false`；`card_ref` 增加 `cas-merged-cards-v1#<identity>`；`roster()` 接受 CB/BC/AV 并拒绝全部 8 个收藏 id。`realtime.rs` 为 50 个新 class profile 登记炮座时序（沿用同炮族已有记录）。
3. **点表**：`cas-competitive-points-v1.json` 补 91 行（`profile_id = cas-merged-cards-v1#<identity>`，全部标 provisional 待平衡复核），点值由现有 `point_value` 现算。历史战役预算不动。
4. **验收**：引擎 103 项全过（新增 3 项：91 张 merged 全部过 `init_realtime`、6 艘 merged 驱逐舰 3000 分对局、202/8 与收藏 id 拒绝）；`server.test_ranked` 12 项全过（含 4 项原生 sim 流程）；其余服务端 21 项全过；`tsc --noEmit`、`vite build` 通过；WASM 重建并跑 21 组原生/WASM parity（`nativeWasmCanonicalMatch=true`）。覆盖、来源、排除名单与缺口见 `data/ships/merge-report.json`。
5. **边界**：8 个收藏身份不合并；Hiei/Kirishima 的 12.7cm/40 DP 未并入单一 `secondary`、pdf/ERMA 未印 `torpedo_protection_dp`、Des Moines/Salem 1948 配置放进 1944 架空想定、Walke p309 极远段 25.9 千码印刷异常均逐条登记；91 行点价待平衡复核；未改 `server/catalog`、立绘、音频、AI、`data/campaign` 与源卡，未提交。

## 当前批：23 张 period 逐舰卡接入排位注册表（2026-11-08）

0. **口径**：`data/ships/playable-cards.json` 的 56 个 collection-only 身份里，28 个带 period 逐舰卡；其中 5 艘 APD/运输按非战斗保持收藏，**23 艘战斗舰**接入排位。它们原先不可出战，原因是排位注册表只加载 stage0/序章 25 张类卡，而不是没有舰表。排名注册表 88 → 111。
1. **数据**：新增 `data/ships/period-cards.json`（23 条，逐条 `{identity,name,side,type,source_file,period_ship_id,period_profile,form10_page,stat_verified,stat_source,stat_conflicts,resolved_from,also_recorded,ship}`）。`ship` 是 period 包里的完整 ShipDef，原样复制后可战，只手写 id/name 为稳定身份与中文名；不换算、不补默认值、不跨级。生成器 `scripts/build-period-cards.py`。Cape Esperance 包以 `profile_ref` 指向 Tassafaronga 包时按该包已编译运行时卡取完整定义（与 `build_esperance_cards.py` 同一解析路径）；Buchanan/Honolulu 各两张 period 卡，取剧本运行时逐舰卡（`us_bristol_dd` / `brooklyn_1`），另一张记入 `also_recorded`。**修正轮**：鸟海（p.49）9 管/5 座、8 雷管、471 DP；威尔逊（p.317）4 门单装、16 雷管、118/38；蒙森（p.303）4 门单装、10 雷管/2 座、128/35；布坎南（p.292/293）4 门单装、10 雷管/2 座；圣胡安（p.262）8 座双联 16 管、8 雷管；赫尔(I)（AF A-19）size D/Small、200 码/1 节、损伤行 26/27。差额与冲突逐条写 `stat_conflicts`。
2. **内核**：`ranked_fleets::data()` 解析 `include_str!("../data/ships/period-cards.json")` 并把 23 条完整 ShipDef 并入 ships；`PROFILES` 增加 23 个 Profile（`source = "period exact · <file> · <form10>"`，`source_class = period profile`）。`src/realtime.rs` 为 15 个 period profile 登记 `timings`（沿用同型已核炮座节奏）。`stat_verified=false` 的 period 卡不会上场（`data()` 跳过、`roster()` 拒绝）。不依赖 prologue 类卡，不改 88 个既有 Profile 的 id/source_class。
3. **点表**：`data/rules/cas-competitive-points-v1.json` 补 23 行，用现有 `point_value` 由完整 ShipDef 计算（修正后：鸟海 1375、蒙森/布坎南 425、威尔逊 475、圣胡安 1025、赫尔(I) 425、Boise/Honolulu 1050、Australia/Canberra 1250、Uzuki 250 等），`profile_id = cas-period-cards-v1#<period_ship_id>`，行内标 provisional 待平衡复核。历史战役预算不动。
4. **验收**：引擎 100 项（新增 3 项 ranked 测试，含逐张断言 6 张修正卡）；`server.test_ranked` 12 项全过（含原生 sim 的 4 项流程）；`tsc --noEmit`、`vite build` 通过。来源、哈希、完整性与缺口见 `data/ships/period-cards-report.json`。
5. **边界**：WASM 未重建（只增 ranked 数据与炮座时序，未改剧本/裁决；ranked 由原生服务端权威执行）。剩余收藏 99 = 28 张无 period 卡 + 5 艘 APD + 66 个不在当前 11 剧本交叉表内的身份；`server/catalog`、立绘、音频、AI、`runtime-identities`、`campaign/live.rs` 未动。

## 当前批：特混编成（自定义任务编队，2026-11-08）

0. **规则口径**：历史编制仍是战役星级与史实编成的唯一口径；新增“特混编成”作为独立架空部署模式。位置数 = 剧本已有的玩家编队数（1–3），最多一位置一个编队，可少派、可空置、可单舰，总点价不超历史玩家兵力。锚点、航向、航速取运行时历史玩家 fleet，不新增坐标；列距沿用剧本 500 码默认值。登记见 [特混编成](docs/rules/task-force.md)。
1. **内核**：`Start.groups` / `GroupPick`；`campaign_fleet` 返回 `positions` / `taskForceSupported`；`fleet::spawn_groups` 校验位置、空编队、同阵营与点价，并在 Esperance/Empress 的 `fill` 中替换玩家历史编队；敌方编制与目标不动。特混不计历史星级，客户端跳过 `recordCampaignResult`。
2. **前端**：关前编成增加“历史编制 / 特混编成”页签；特混页为初设位置卡 + 编队卡 + 舰船选择 + 点价/校验/出航；空位置显示“空置”；特混出航按钮明确“不计历史星级”。
3. **范围**：本批只接入埃斯佩兰斯角（1 位置 / 6,850）与奥古斯塔皇后湾（3 位置 / 7,500）。圣乔治角、塔萨法隆格、库拉湾、萨沃岛继续历史编制，`taskForceSupported=false`，前端禁用页签，不伪造位置。
4. 验收：引擎 91 项（含 7 项特混舰队测试）；WASM 重建；`browser-taskforce`（皇后湾 3 位置/2 编队/空位/双锚点）与 `browser-taskforce-esperance`（1 位置/单舰）通过；历史四项浏览器验收继续通过；`tsc` 与 `vite build` 通过。
5. 边界：历史舰位候选使用 class card，战斗舰名可能显示舰级名，身份级舰名载荷另批；特混结果页的浏览器断言待补。

## 当前批：P1 战役大厅与关卡前编成（2026-11-08）

0. **新战役大厅**：`CampaignLobby` 三栏（关卡列表 / 战区海图 / 关卡详情）；主路径只显示可出击与已完成关卡，资料核验与未开放档案收进「史料馆」（保留原 `CampaignArchive` 全屏视图，旧验收可回退）。
1. **关卡前编成**：故事难度新增 `DeploymentScreen`；历史舰位逐位换同阵营已登记舰卡，点价不超历史兵力；候选面板、预算条、校验、战术风格、草稿与预设。标准/挑战仍按历史编制直接出击。
2. **按出击选战术风格**：`CampaignLaunch` 增加 `profile`，战役出航可用编成屏选择的协同/炮战/雷击，不再强制沿用母港预设。
3. **实现边界**：不改 `src/` 内核、CAS 舰卡、点表与历史阵位；新样式只挂 `.campaign-lobby` / `.deployment-screen`；740×360 无横向滚动。
4. 验收：`npm run build`；`browser-esperance`（故事编成出航）、`browser-deployment`（换舰/预设/草稿/740 参谋抽屉）、`browser-campaign-modes`（史料馆/未开放禁用/标准直出）、`browser-lobby`（大厅/剧情/740 无横向滚动）；证据写入 `artifacts/client/{deployment,campaign-modes,lobby}/` 与 `havedone.md`。

## 当前批：删第 15 关、UP 战列舰、活动邮箱、周本分档与基础难度编队（2026-11-08）

0. **剧本清理**：第 15 关（菲律宾海舰载机追击）从战役目录、席位、奖励和星数中移除；保留 11 个水面 CAS 想定，当前可出航 6 关（新增 05 塔萨法隆格、10 萨沃岛）。其余 7 关仍是资料层：塔萨法隆格缺补给点/卸载计分，萨沃缺海图与运输/照明裁决，霍腊纽有几何与艇型冲突，瓜达卡纳尔一/二、科隆班加拉、韦拉拉韦拉缺时期舰卡与海图。按规范不得用近似坐标或默认值填空。
1. **UP 池**：北卡罗来纳（`IBS-U-USN-UNNAMED-T01-R03`，已核验战列舰舰卡）升为 UR 并成为 UP 池旗舰；UP 描述、兑换列表和立绘同步。卡池 167 个可征募身份。
2. **活动与邮箱**：母港顶部新增“活动/邮箱”。七日签到接入活动页；邮箱为独立页，注册即获“内测启航补给”20 抽（20 张常驻券），线上由服务端注册事务投递，单机由本机邮箱领取。
3. **周本/排位分档**：点表开放 3000 与 10000 两档，新增 7 个同型驱逐舰身份；3000 分可编 6 艘驱逐舰（最便宜 6 艘 2675 分），10000 分可编 1–2 艘战列舰与护航舰。服务端与内核点表同步，北卡罗来纳 3000、大和 4000。
4. **基础难度编队**：战役 `story` 难度读取历史玩家兵力的点价预算；简报内按历史舰位逐位换舰，历史舰可临时体验，也可换同阵营已登记舰卡；出航时内核按原舰位、航向、航速、编队和领舰一一替换。标准/挑战难度继续使用原历史兵力。
5. **卫星海图底层**：铁底湾三场共用 3072×2304 实拍马赛克，按数字化 Savo 地标锚定场 origin；海岸线多边形重制（Guadalcanal 503 点）供碰撞，渲染不再画多边形。
6. **测试体验修复**：免登录固定测试指挥官；教学固定流程继续按钮；探照灯/照明弹按目标坐标绘制；舰况炮管随炮座旋转；编队航速显示实时/目标/上限；领舰航行中可交接且各舰保留航迹。
7. 待办：7 个资料层剧本的舰卡/海图/特例；战役编队目前只允许与历史舰位同数，尚未做“减舰/增舰”与个人收藏过滤。

## 当前批：剧本对应、母港单页、战役大厅与剧情模式（2026-11-08）

0. **战役目录只保留有 CAS 对应剧本的想定**：12 个保留（埃斯佩兰斯角、库拉湾、圣乔治角、塔萨法隆格、瓜达卡纳尔一/二、科隆班加拉、萨沃、奥古斯塔皇后湾、韦拉拉韦拉、霍腊纽、菲律宾海夜战追击）；通道行动、1928 所罗门、1928 布干维尔与《铁底湾的回响》从目录、席位和奖励表移除，交叉表与数据文件保留以便将来恢复。当前可出航 4 关：03 圣乔治角、04 库拉湾、11 皇后湾、02 埃斯佩兰斯角。
1. **卡池与立绘**：12 个保留剧本登记的 164 个稳定身份全部进入手游同款免费经济（166 个可征募，含 2 个原商店身份）；`scripts/import-scenario-portraits.py` 从固定手游 manifest 投影 166 张立绘并逐张登记哈希，征募、收藏、到货与值更舰共用。概率、保底、重复勋章、价格与礼包继续由 `server/import_catalog.py` 按手游固定快照投影，不改经济数值。
2. **母港只保留图一这一页**：钱包收敛为补给币/征募券/舰队勋章；dock 固定“舰库与编队 / 征募与补给 / 教学复习 / 线上舰桥”；值更舰改为“换班”；旧的多标签母港改为单功能子页（无标签栏）。
3. **战役大厅按图二重排**：顶部返回港口/战役航图/双方战线/星数；左侧战区和世界航图，右侧关卡列表；底部难度页签与“作战简报”，简报内保留 CAS 原页编制、目标、特例、奖励与出航。星数分母按保留关卡动态计算（当前单线 36）。
4. **序章改为剧情模式**：新增独立 `StoryMode` 章节页，明确标注“架空剧情、不属于历史战役档案”；序章为第一章，后续章节在 `storyChapters` 追加，进度独立存档。
5. 验收：引擎 79 项、服务端 33 项、parity 重跑、`browser-lobby` 与 `browser-esperance` 真实点击通过；WASM 与原生同源重建。

## 当前批：战斗反馈、CAS 全书覆盖与战役对照

0. **本批已完成探照灯与烟幕的 v10 实时改编并接到客户端**（RTS-LIGHT-02 / RTS-SMOKE-01，见 havedone.md 2026-11-07 条目）：夜战探照灯命令（照距骰、照明修正、源距暴露）与驱逐舰烟幕（60 秒一烟团、四窗燃尽、昼 1,000／夜 500 码目视上限与射线遮挡）；指挥面板两节按钮与海图烟团／光锥渲染已接入并有浏览器交互验收。经济与舰库、音频、立绘迁移两个工作区等配额重置（2026-11-08 01:22）后重试；关卡序章战役内容在其后。
1. 海图优先补四项：不中断指挥的命中／受损／沉没提示；引擎生成炮弹与鱼雷实体，弹着时才显示结果；可开关的本舰炮雷射程圈；炮位、发射管、火控、推进、火灾进水状态图。炮弹飞行属于实时化表现和时序改编，五版命中及损伤表仍负责裁决。已开的 v1 对局沿用原来的裁决时序。
2. 规则线建立全书章节覆盖与启用门：原页／图表、结构化数据、裁决消费者、剧本实跑和边界用例。下一批优先夜战目视、照明及在途鱼雷识别；未核机制明确留在待办。
3. 战役线先以铁底湾手游实际航图为分母，逐条找本地 CAS 剧本册。历史同一战斗、同一行动的其他阶段、铁底湾原创／未找到分别登记。精确对照也按 CAS 重新录入舰型、编制、部署、环境、目标和特例，不迁入旧引擎数值。
4. 最终用同一内核实测 Windows 和 Android；分开报告战役已索引、资料已录入、关卡已可打的数量。

## 产品口径：铁底湾手游外层、CAS 战斗内核

大厅、母港、编队、双线战役、挑战、约战、3000／10000 分、AI 解锁和经济继续以铁底湾手游实际交付的 0.6.9 为对照。剧情及成长仍按旧关卡和角色 ID 串联；出战舰只绑定经过版本和服役时期核验的 CAS 舰卡。航速、舰炮、鱼雷、判定和历史胜利条件都从 CAS 录入。核验不到的舰与关卡保持锁定。实时炮塔转向、装填、按射程和弹速计算的飞行、两种编队航路及实时手势的差异逐项登记为 RTS 改编，不把改编值写进舰卡。

迁移按 [手游内容与指挥官接线](docs/mobile-migration.md) 执行。优先补圣乔治角要求的时期舰卡、搜索与火控雷达、历史阵位和双方目标；夜战教学另等照明和真实炮雷事件；开场序章复用角色、台词和叙事选择，用实际 CAS 对局录制舰队演出。指挥官继续使用原作角色／风格，语音从本方真实事件触发。历史档案与实际可玩的关卡分别验收。

水面雷达先按每舰、每台设备、每个探测窗口处理搜索和保持；首次位置须隔一窗口才能由其他友舰使用。用独立的试验版本验证座席过滤、搜索雷达炮击及旧存档不变，再挂接核准的圣乔治角舰载设备。

## 登录首屏和母港还原

程序先显示登录，成功后直接进入母港。直接从铁底湾手游复制母港组件和样式、底图、现成剧情与可复用模块；用 CAS 适配层连接账号、出击和真实库存，原项目保持只读。离线试玩先有独立本机指挥官，原离线档只迁给第一位本机账号；正式账号服务和跨端资产另验，不能用本机登录冒充线上验证。序章保留原剧情顺序、人物与选择，教学由 CAS 航点、尾随／同步、目标接触和实际火力事件过关。并行录入旧关及舰船、核对 CAS 规则并逐项接入；标明可玩、仅录入、未实现，保持旧对局重演版本。

当前两条线的 32 个原关已挂接档案，11 场历史原页已录入。先让圣乔治角从档案进入实战：补齐运输与撤离、夕雾实装和阵位／结束口径，接上火控和相应夜战机制，验证双边目标及本席重演。战役难度、评级及奖励接入首个通过验收的历史关后再批量开放。完整舰表、全书机制和线上服务按各自的缺项继续推进。

## 实时主炮与缺对应剧本的迁移口径

原 16 个想定中，只有 12 个有 CAS 对应剧本。其余 4 个（通道行动、1928 所罗门、1928 布干维尔、午夜舰队）已从战役目录移除；交叉表和资料保留，不再按旧作布置移植。保留剧本的旧作布置仅作对照，武器、舰体、伤害和探测数值不能进入 CAS 舰表。相对阵位、任务及战斗可运行状态分别验证。

为新局引入逐秒主炮版本。玩家随时点射或撤销尚未发出的炮座；内核用合法射界、转速和装填判定各炮座的发射时点，以 CAS 炮表为每战术回合的火力预算。炮弹飞行随距离、弹速和弧线变化，入水、命中与鱼雷尾迹都跟随权威实体。旧版读档保持原规则。确定性回放、双方同秒裁决、舰况读数和敌情过滤为共同验收要求。

战役出航的下一道门是把原页阵位接进可变海图与编队初始化，按舰绑定时期舰卡、设备和雷装，再接可在对局中触发的胜负条件。首个同一历史剧本继续以圣乔治角为验收目标；首个保留旧布置的关以通道行动为目标。1928 想定核对《Bywater’s War》同期架空舰卡，不能借同名二战舰；第 15、16 关的假想提前服役和计划舰需逐一明确配置。双边能启动、完成任务、核对评级并保存重演后，才把相应关位改为可出航。

## 战役实战与原手游服务接线

先将圣乔治角接到可变海图、历史编队和独立战役存档，保留双方独立达成胜利等级的原规则。出战版本标明 RTS 改编：原页未定的地图边界和撤离线单独登记，未核定装载及武器不以默认值填补；档案仍标注原想定的缺项。双线大厅接出航、分级奖励和重演，三个难度先用不同敌方指挥风格。继续处理其他想定、规则和舰表的可运行缺项。

移植铁底湾原账号、双池、保底、邮箱和免费商店作为 CAS 独立免费测试服务。CAS 独立数据库，每笔领取、征募和购买同事务去重；禁止接入旧库或接收客户端自报的资产，权威战局和周任务资格随后接线。参考项目与原始 PDF 仅供读取。

先在本机回环接通线上账号、母港钱包和征募。权威 PvE 使用原生 CAS 内核，服务端决定时钟和种子，只返回本席观察；同局、同星级奖励和每周资格分别去重。发布包由明确配置启用测试服务，默认仍可离线启动。

依主规则 §6.3（PDF 66）补齐圣乔治角直接雷达接触的直航雷瞄准：本舰同一设备连续取得两次战术窗口位置后才生成航向／航速估计。只使用本舰雷达位置，队友转发的点位和丢失、关停后的旧点不能解算，已发出的鱼雷保持直航。继续保留反应火力窗口的限制。

圣乔治角舰况接入原手游固定快照中的十张具名立绘，按舰艇与角色双 ID 匹配。卯月使用与 1943 年关卡对应的旧身份图，不把异时期版本或同级代表图套给历史舰。

找不到 CAS 同一剧本的「通道行动」作为第二个可玩目标：沿用原手游八舰格位换算的连续坐标、航向和初速，按原页四回合及追击任务收官。德舰是否被打到原任务的速度阈值，取 CAS 舰卡当前损伤后的最大航速；玩家主动停船不会满足击伤任务。武器、损伤和实际航速上限以核准的 CAS 同期舰卡为准。先验证双席可玩和重演；线上仍限定已验收的圣乔治角。免费内测签到复用已交付的七日奖励，采用服务器北京时间，第七天继续由 CAS 舰卡准入。

按《Home Fleet》A-36 给已核定 J/K 配置登记轮机共舱特例。它只放大工程临界的航速档损失，不改 DP、起火或锅炉爆炸概率；其他舰卡默认沿用原裁决。后续历史关先核部署、舰卡、特例及可执行胜负；同步核对霍腊纽与韦拉拉韦拉撤离战的最小完整范围。

## 弗莱彻战败 CG（独立美术素材）
沿用项目弗莱彻全身立绘，绘制十张横版海战失利插画，逐张核对动作、视线、表情及造型。候选图保存在 artifacts，不接入发行包。

## 实时装填史料复核
按炮座核对技术资料，用有出处的射速换算新局的代表性射击间隔。CAS 五版继续决定火力组命中、射程、穿深和伤害。射速只用于发射调度和分摊原表火力，未经证实的参数标注为暂定。冻结旧版时序用于读档和重演。

## 炮击临界损伤即时化
用 CAS 五版 §8.1.2 的累计伤害比、每舰每窗一次 D6 和原部位表，按实际弹着逐步触发新增临界伤。炮位失效后退出后续发射，已经离膛的炮弹继续飞行。同秒弹着一起扣伤，普通炮击与鱼雷分别裁决。测试火力中断、装甲、随机次数、跨窗重置和旧档重演。

## 工作区缓存清理

按白名单清理可重建的编译中间产物、临时核页和调试文件。旧 Windows 解包目录只在与发行 ZIP 逐文件一致且未被使用时移除。保留运行中的开发预览、测试服务和模拟器所需文件，以及原始资料、用户数据、交付包、素材与验收凭证。

## 完整迁移与序章重制

以最新可验证的铁底湾手游交付快照为基线，逐项核对原界面、活动、征募、编成、排位、地图背景、剧本、立绘和音频。先记录版本、代码和素材来源，再接 CAS 权威战斗，保留双方独立的账号和数据。

核对五版 §3.1.4 和舰卡转向前进距离，以可重演的连续曲线实现舰首过弯，预览、编队执行和避障使用同一航迹。旧版存档继续按冻结逻辑回放。登记 §6.3 的直航鱼雷改编和各炮座横转史料，严格区分已核数值与暂定数据。

用真实对局演出舰队交火，镜头推近第五驱逐小队后，在实时战图上叠加对话。序章、雷达和夜战用固定状态、指定按钮与真实战斗事件推进。每个关位核对原部署、中文舰名、地图、胜利条件和阵营重演，只有实跑通过的关位计入可玩。

## 库拉湾历史水面关

将《旭日》五版 PDF 85–86 的 17 艘具名舰、海图锚点、维拉卸载和双阵营原页胜负接入独立 v9 内容。正文优先解决舰尾次序，纸面海图的读数和原书未指定的边界单独登记。验收两席部署、装备、卸载连续计时、战果及重演。随后复用同一组舰卡与输送结算核对科隆班加拉。

## 完整交付的后续工作

继续推进四条线直到原要求逐项验收。原生内核和对战服务先接双席权威执行、座席隔离、存档重连和真实战果，然后验 CAS 个人出战编制与排位。水面规则优先补鱼雷深度、逐架齐射和水下防护，再补满舵、卡舵、撞击及未实现临界；航空、反潜、岸防和水雷按来源台账分组接入。

战役从可核完整的历史水面关逐批开放。每关复核具名舰、部署与胜负条件，在两席实际结束并重演后再开放。客户端先接铁底湾 0.6.11 结局，再补活动、征募、编队和竞技入口，保留已有用户数据和旧存档。阶段验收用于记录增量，完整范围仍按原任务核对。

额度交接时从[接手说明](docs/handoff.md)恢复主仓、分支与验收环境，再按[后续实施与验收计划](docs/implementation-roadmap.md)逐项完成。

## 2026-11-07 恢复进度

排位服务（队列、结算、点表准入、赛季与段位梯）与 0.6.11 线上征募台（主题图、概率页、十连到港、跳过、回看、兑换、旧池）已合入主仓并通过本机实测；排位前端（两档展示、赛季段位、点价校验、排队/取消/作废态）已从 `E:/CAS-ranked-ui` 审查合入并在主仓重验，`server/test_ranked.py` 12 项覆盖互射、平局、作废、重试幂等与重启续局。排位的 3000 分档至此代码已合、本机双席实测通过，等待与线上服务整体联调后再对外开放；10000 分档继续按点表与实战重演结论决定开放时点。

剧本录入推进到三个新原页：塔萨法隆格（PDF 75–76）、埃斯佩兰斯角（PDF 65）、萨沃岛（PDF 52–54）均以 source_only 录入并通过各自检查脚本，未接引擎。按用户指示，剧本录入在萨沃岛后暂停，科隆班加拉岛工作区（`E:/CAS-entry-kolombangara`）已建待后续。

## 实时规则 v10 快照

按用户要求完成并验收（提交 `c427011`、`3b6a9f2`，登记见 `docs/rules/realtime-torpedo-v10.md`）：逐秒鱼雷（下令当秒解算发射、射界未到限时挂起不扣雷）、每发独立 D100（v9 每窗一骰的全有全无消除，整窗期望伤害不变）、AI 射击纪律（命中率 0% 不开火、夜战自行开雷达）；持续炮击（拖到哪艘就持续打哪艘，新拖即转火，AI 重复下令不打断）、拖动途中显示每舰当发命中率、目视圈与雷达圈。挑战想定（3 对 5）刻意冻结在 v9 族保持调平；v9 家族（含库拉湾）按原时序重演。点表 rules_version 随内核升至 v10，服务端 RULE_VERSIONS 接受 cas-campaign-v10。

## 0.6.11 操作点击音效与指挥官录音迁移

操作点击音效按原作 `SoundDirector.uiCue` 的正弦合成参数移植四种（tap 1250Hz；confirm 720→1080Hz；select 900Hz；error 220→170Hz，音量 ×0.11），开关与音量写入本机账号设置；原作没有对应音频文件，台账只登记实现来源，不冒充录音。指挥官专属录音按最小子集迁移：先迁 `al-enterprise` 的六个本席实际战报 cue（battle_start／contact／torpedo_warning／hit／torpedo_hit／damage），沿用 `VITE_CAS_LOCAL_VOICE=1` 本地试玩构建，正式构建不含。其余 31 个碧蓝包与两个阵营包的剩余变体登记为「存在但未迁，待授权核验」。验收以 `client/tests/browser-radio.mjs` 的点击音四类、开关静音、音量持久化、指挥官事件触发与去重、配乐让音，以及正式构建不含音频、本地构建可播为准。

## 2026-11-07｜经济与舰库外层补齐（E:/CAS-econ-ui · econ-ui）

对照铁底湾 0.6.11（`6601bdd`）补齐三项外层：补给商店三舰礼包货架、第七日签到北卡罗来纳实发、舰库全身立绘查看器。经济目录仍由 `server/import_catalog.py` 从固定快照投影生成；CAS 侧只加两处已登记覆盖（礼包描述按原目录保留、北卡罗来纳 `combat_ready` 覆盖带出处），投影校验与 `--write` 结果一致。内核实战、`src/`、`docs/rules` 未改。

下一步：离线单机档第七日仍不发放舰船（本地存档没有舰船所有权与转勋章通道），若要单机同步开放需先接本机收藏；礼包的 `combat_ready` 闸门在 CAS 目录下没有意义（目录舰船一律不可出战），后续若把礼包舰接入个人出战需按点表逐舰核验。
