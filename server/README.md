# CAS 账号与免费经济测试服务

直接迁自铁底湾手游 0.6.9 固定快照 `48385c8337d3f5a08e3ebc5676d68309df87542d` 的 `backend/src/iron_bottom_sound/mobile_account_service.py`。保留原账号、免费经济、邮件、抽卡保底及事务结构，替换应用标识和库存目录；不运行铁底湾旧战斗引擎。

从 CAS 仓库根目录运行：

```powershell
python -m pip install -r server/requirements.txt
python -m uvicorn server.accounts:app --host 127.0.0.1 --port 8021
```

访问 `http://127.0.0.1:8021/docs` 查看接口。数据库默认独立存放在 `server/data/cas-accounts.sqlite3`。`CAS_ACCOUNT_DB` 可指定另一个 CAS 数据库。应用标识和版本门会拒绝其他项目数据库，旧版 CAS 库会保留资产并迁入战局表。此服务用于本机回环测试。

| 方法 | 路径 | 请求与结果 |
|---|---|---|
| GET | `/health`、`/catalog` | 服务能力与冻结经济目录，可匿名读取。 |
| POST | `/auth/register`、`/auth/login` | `{username,password}` → `{account_id,username,token,token_type,expires_in}`；独立 CAS 账号。 |
| POST | `/auth/logout` | 作废当前令牌。 |
| GET | `/me`、`/me/ledger` | 本席权威钱包、收藏、保底进度、已领奖与最近 100 笔变动。 |
| GET | `/mail` | 当前账号的邮件、附件与领取时间。 |
| POST | `/mail/{id}/claim` | 可带 `request_id`；按收件账号和邮件 ID 去重，返回 `{mail,meta}`。 |
| POST | `/starter-gifts/claim`、`/prologue/claim` | `{request_id,course}` 或 `{request_id,leader_id}`；固定新手礼，不验证教学，也不会自动创建可出战编队。 |
| POST | `/recruit` | `{request_id,count,pool_id}`；一次 1–10 抽，返回 `{receipts,pool_id,meta}`。 |
| POST | `/shop/purchase` | `{request_id,kind,item_id,currency,pool_id?}`；支持普通舰、勋章兑换、进度兑换、舰船礼包、AI 和周券。 |
| GET / POST | `/missions/weekly-pve` / `/missions/weekly-pve/claim` | 查询或领取原手游「每周实战补给」。圣乔治角在服务端完成主目标时计一场，使用北京时间周界限；客户端不能自报胜场。和离线挑战的「每周三次复战、每次两券」分别结算。 |
| GET / POST | `/missions/check-in` / `/missions/check-in/claim` | 查询七日签到或以 `{request_id}` 领取下一档；使用服务器北京时间日期。 |
| GET | `/progression` | 查询本人收藏舰数、已解锁 AI、权威战役档位及主目标胜场、赠礼和签到。 |
| GET | `/fleets`、`/fleets/{id}` | 查询本账号的编队草案、当前预设及出战门控。 |
| POST | `/fleets` | `{request_id,fleet}` 创建或更新本账号的草案，成功保存后设为当前预设。 |

除健康、目录、注册、登录外，必须发送 `Authorization: Bearer <token>`。用户名为 3–40 位英文字母、数字、点、短横线或下划线，忽略大小写；密码 10–128 字符。密码和会话在数据库里分别保存带随机盐的 PBKDF2-HMAC-SHA256 摘要与 SHA-256 摘要。令牌有效期 30 天。允许本地开发浏览器、CAS Windows WebView 和 Android 应用资源来源；可用 `CAS_ACCOUNT_ORIGINS` 添加明确来源。浏览器跨域许可不能代替账号鉴权。

### 原经济规则

目录由旧手游的两个固定 Git 文件投影生成，收录 210 个稳定身份、167 个可征募收藏、两池和三种礼包。旧竞技点没有进入新目录；普通舰的原测试价按投影出的 `credits_price` 保存为纯经济字段。除第七日签到的北卡罗来纳外，所有舰均标为 `combat_ready=false`，不带旧规则数值或舰卡引用；该舰的 `combat_ready=true` 必须携带 `combat_source` 出处登记（服务启动时强制校验），指向已核验的同稳定 ID 时期舰卡。目录本体只承诺可收藏，不迁移任何旧引擎数值。可征募范围由 `server/scenario-recruitable.json` 决定：剧本交叉表登记的 164 个身份全部入池（含已移除第 15 关仍保留在收藏目录的纸面舰），另有北卡罗来纳 UP 与 2 个原商店身份；立绘由 `scripts/import-scenario-portraits.py` 从固定手游 manifest 投影并登记哈希。注册即投递一封含 20 张常驻券的“内测启航补给”邮件；UP 池旗舰改为已核验战列舰北卡罗来纳。

双池为 `missouri-up` 与 `standard-v2`，基础概率为普通 75%、精锐 20%、稀有 3%、UR 2%；分别在连续 10／40／80 抽触发相应保底。UP 池 UR 首次 50% 命中密苏里，歪后下一次 UR 必中。两池的计数、兑换进度和专用券互不混用，原兼容通用券为不足部分补齐。每抽 1 进度，80 点兑换本池指定 UR；重复普通／精锐／稀有／UR 转为 1／5／20／50 勋章。省略池号时保留旧版无 UR 的常驻规则，标准新客户端应显式选择 `standard-v2`。每周 500 补给币兑换一张常驻券，以北京时间周一切换。竞技点表同时开放 3000 与 10000 两档：3000 分可编 6 艘驱逐舰，10000 分可编入 1–2 艘战列舰与护航舰。

资产类请求使用 8–120 位的稳定 `request_id`。相同账号、操作与参数重试返回首次响应；同编号不同内容返回 409。响应的 `meta` 是首次入账快照，客户端可调用 `/me` 刷新；邮件领取按邮件 ID 去重并返回当前余额。SQLite WAL + `BEGIN IMMEDIATE` 保证同一事务内扣券、定抽、增发、记账和记忆响应。支付资源始终为 0；没有充值或回调路由。

运营方只能从本机服务器代码投递邮件，例如 `AccountService(db).deliver_mail(account_id, "test-001", title="试验补给", body="内测", attachments={"up_tickets": 10, "standard_tickets": 10})`，重复使用相同邮件编号和内容不会再次投递。没有客户端投递接口。

### 本机权威圣乔治角战役

默认启动只有账号与经济。要开启战役，先编译仓内 CAS 原生程序，再显式指定二进制路径：

```powershell
cargo build --release --locked --bin cas-sim
$env:CAS_SIM_PATH = (Resolve-Path '.\target\release\cas-sim.exe').Path
python -m uvicorn server.accounts:app --host 127.0.0.1 --port 8021
```

`/health` 返回 `pve_available: true` 表示启动时已经用实际内核验证了同盟和轴心的初始观察。仅开放 `CAMP-ALLIES-03` 与 `CAMP-AXIS-03` 的故事／标准／挑战三档 (`story`, `standard`, `challenge`)。每账号最多 4 场进行中；开局使用想定借舰，不读取云端收藏数值。其余关卡的开放和前置条件未接本机在线测试。

| 方法 | 路径 | 行为 |
|---|---|---|
| POST | `/battles` | `{request_id,stage_id,difficulty}` 开局；服务器决定种子，并按关卡 ID 确定席位。 |
| GET | `/battles` | 最多 50 条本账号摘要，未结束的对局优先。 |
| GET | `/battles/{battle_id}` | 查询或重连，返回摘要和本席 `view`。 |
| POST | `/battles/{battle_id}/commands` | `{request_id,revision,command}` 提交本席命令。成功后修订号加一；过期修订号返回 409，刷新后再决定是否重发。相同请求编号和内容重复提交返回原答复。 |
| POST | `/battles/{battle_id}/inspect` | `{command}` 查询本席的航路、整列、瞄准、照明预览或 AI 建议。 |
| GET | `/battles/{battle_id}/report` | 返回 `{result,events}`，只包含该席可见战报。 |
| POST | `/battles/{battle_id}/claim` | `{request_id}` 领取服务器裁决对应的奖励；未结束返回 409。 |

查询、指令和领取可按服务端时钟追赶：每 250 毫秒最多欠一模拟秒，每次请求最多推进 120 模拟秒，无常驻仿真子进程。断开后重新查询会逐批追赶。启动、推进和指令均使用有四秒上限的原生调用，超时不提交该批。存档只保存在 CAS 数据库，冻结开局所用原生二进制的 SHA-256；更换引擎后，未结束的旧局要用原二进制继续。客户端不能暂停、改速、指定种子/席位、载入自备存档、调用原生推进或读取对手未观察到的数据。

战果与终局快照一次提交。战术胜利开放首通与二星（共 600 补给币、2 常驻券）；决定性胜利另开放三星（2 常驻券、10 勋章）。每项奖励按账号和关卡固定 ID 去重，同关换难度或重打只补尚未领的档位；所有奖励金额从旧手游固定目录核对。服务端主目标胜场按局号另外去重；同一已胜对局重连或多次领奖不会累加周进度。

### 七日签到与账号成长

铁底湾 0.6.9 固定快照的账号服务和 `MetaState` 没有七日签到接口或指挥官等级／经验。其离线内测 0.6.10 提交 `1012f540c454f251a9c80292a166c001f444f090` 在 `mobile/src/activities/check-in.ts` 增加签到规则；CAS 当前单机版已采用同一表。服务器把该表接到独立云账号，仍为本机测试，无每日额外发放或七日循环。

| 次数 | 奖励 |
|---:|---|
| 1 | 500 补给币、2 常驻券 |
| 2 | 2 UP 券 |
| 3 | 800 补给币、3 常驻券 |
| 4 | 3 UP 券 |
| 5 | 1200 补给币、5 常驻券 |
| 6 | 5 UP 券 |
| 7 | 北卡罗来纳（`IBS-U-USN-UNNAMED-T01-R03`）；同一稳定 ID 的时期舰卡已在 `src/ranked_fleets.rs` PROFILES（序章时期包 `cas-prologue-runtime-v1#north-carolina`，美国舰表 PDF 8、109）与点表 `cas-points-surface-v1` 登记，按已核卡片实际发放；重复获得转为勋章 |

每个北京时间日期最多一次。漏签时下次继续原档；服务器日期落在上次签到之前时暂停发放。稳定奖励键为 `rookie-check-in-v1:1` 至 `rookie-check-in-v1:7`，通过账号事务一起保存签到日期、固定奖励、钱包与入账记录。失败或重复领取不会新增账本行。接口没有日期、奖励量、舰 ID 或导入离线签到的字段。`POST` 返回 `{claimed,rewards,check_in,meta}`，资格不足返回 `claimed:false` 和状态（舰卡未核验时第七天的 `ship_pending:true` 仍会锁住发放）。第七天奖励额外携带 `ship_source` 出处说明。首次请求的幂等答复可能比当前日期旧，界面可再读 `GET` 刷新。

`/progression` 只汇总已有可信进度：固定新手赠礼仍标 `practice_verified:false`，战役胜场和分档来自真实 CAS 终局。此接口没有写入途径，不虚构账号经验或等级，也不把收藏当作出战资格。

### 个人编队与排位结构

沿用铁底湾账号服务的 `fleet` 对象和编队身份。0.6.11 源码 `6601bddde1b4f0817ebbb6864ee80137647e1d88` 的 `mobile/progression.py` 与 `mobile/src/fleet/ranked.ts` 提供编制依据。CAS 服务验证舰船稳定 ID、当前账号实际库存、同阵营、具体舰不重复、已拥有 AI，以及领舰属于该预设。省略领舰时使用名单第一艘。可保存 32 个草案，修改时复用预设 ID。相同请求编号与内容会重放原答复，编号复用为不同内容会返回 409。

| 档位 | 结构检查 |
|---:|---|
| 3000 | 3 至 6 艘，至少 2 艘驱逐舰，轻巡与重巡合计最多 2 艘。 |
| 10000 | 3 至 8 艘，1 至 2 艘战列舰，至少 2 艘驱逐舰或轻重巡护航，最多 4 艘驱逐舰。 |

输入 `fleet` 含 `id`、`name`、`side`、`budget`、`ship_ids`、`ai_profile`，可选 `leader_id`。`cost_version` 可省略或传 `null`。保存响应为 `{fleet,validation,active_fleet_id,meta}`。查询单份返回 `{fleet,validation}`，列表的 `fleets` 包含这些条目。结构检查通过后，`validation.structure_valid` 为真，`cost` 和 `point_table_version` 仍为 `null`，并以 `unavailable_ship_ids` 列出尚无个人出战配置的船。

云目录目前仅供收藏与草案编辑。演习的通用舰型和战役借舰由各自想定加载。CAS 个人出战配置和点表尚待建立，因此 `combat_ready`、`ranked_ready` 和列表的 `ranked_available` 均为 `false`。旧作舰价没有参与任何预算判断。

### 双人非排位演习

双席身份、排队与结算参考铁底湾 0.6.7 的 `mobile/mobile_pvp.py`，战斗使用 CAS 原生内核的 `cas-realtime-v8` 固定昼间 5 对 5。将 `CAS_SIM_PATH` 指向支持原生 `match_*` 的二进制，再设置 `$env:CAS_ENABLE_DUELS = '1'` 后启动回环服务。启动会实际建立双席手动演习检查版本。启用后，`/health` 的 `pvp_available` 为真，`ranked_pvp` 仍为假。

| 方法 | 路径 | 行为 |
|---|---|---|
| GET | `/pvp/status` | 本账号的待用邀请、排队状态、最近对局摘要。 |
| POST | `/pvp/invites` | 创建有效期 15 分钟的邀请。 |
| POST | `/pvp/invites/{code}/join` | 持有效邀请的另一账号加入，邀请方为同盟，加入方为轴心。 |
| POST | `/pvp/invites/{code}/cancel` | 由邀请方取消尚未开局的邀请。 |
| POST | `/pvp/queue`、`/pvp/queue/cancel` | 排队匹配固定 5 对 5 或取消排队。等待最久的有效队列先匹配。 |
| GET | `/pvp/matches/{id}` | 查看或重连本人座席，返回本席观察及修订号。 |
| POST | `/pvp/matches/{id}/commands` | `{request_id,revision,command}`，按本人座席校验及执行命令。 |
| POST | `/pvp/matches/{id}/inspect` | `{command}`，仅查本席预览或 AI 建议。 |
| GET | `/pvp/matches/{id}/report` | 本席可见战报。 |
| POST | `/pvp/matches/{id}/surrender` | 由本人认输，已经结算的对局返回原战果。 |

除预览外，POST 使用 `{request_id}` 去重，重复提交返回同一答复。每个账号同时最多有一场进行中。两席共用服务端 4× 模拟时钟，分别保存本席命令修订号。双方可在同一模拟秒各提交一条合法命令，另一席的修订号不会妨碍本人。查询时每次最多追赶 120 模拟秒，完整快照和双方战报保存在独立的 `*-duels.sqlite3`，当前对局固定原生二进制的 SHA-256。终局结果和双方视图在一笔事务中写入，后到的终局请求不会覆盖战果。

目前开放固定演习的邀请与快速匹配。双方手动下令，可以查看本席建议。个人舰队、3000／10000 点表、排位、MMR、赛季及发奖等待对应出战与平衡验证。结算只记演习战果。客户端每次只收到本席观察或战报，完整命令日志、随机种子与原生快照保存在服务端。

### 验证

```powershell
python -m pip install -r server/requirements-test.txt
python -m unittest -v server.test_accounts server.test_battle_pve server.test_account_progression server.test_fleets
python -m server.smoke_http --sim .\target\release\cas-sim.exe
python -m server.import_catalog 'F:/Codex/worktrees/android-mobile/铁底湾'
```

双人专项可设置 `$env:CAS_TEST_DUEL_SIM_PATH = (Resolve-Path '.\target\release\cas-sim.exe').Path`，然后执行 `python -m unittest -v server.test_duels` 与 `python -m server.smoke_http --sim .\target\release\cas-sim.exe --duels`。专项测试使用隔离的临时账号库和双人库，运行两席实际炮击、放雷与损伤到自然结束，也覆盖并发投降只结算一次。

HTTP 冒烟在临时 SQLite 中实际启动回环 Uvicorn，覆盖注册、发信领取、扣券、签到领取与隔离、同请求重试、账本、退出，以及轴心标准档圣乔治角开局、自动推进、命令重试和其他账号拒绝。完整测试另以注入的服务器时钟和种子跑到真实 CAS 战术／决定性胜利、五路并发领取、差额补领、账号隔离和重启恢复；签到测试跨北京时间午夜、漏签、日期回退、第七日实发北卡罗来纳（含重复转勋章与幂等重放）和舰卡未核验时的第七日锁定。时钟和种子注入仅在测试代码内，实际 HTTP 不接收这些字段。没有编译原生程序时，权威 PvE 测试会跳过，经济和签到仍可独立运行。目录验证只读取旧仓的固定 Git 对象。
