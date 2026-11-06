# CAS 账号与免费经济测试服务

直接迁自铁底湾手游 0.6.9 固定快照 `48385c8337d3f5a08e3ebc5676d68309df87542d` 的 `backend/src/iron_bottom_sound/mobile_account_service.py`。保留原账号、免费经济、邮件、抽卡保底及事务结构，替换应用标识和库存目录；不运行铁底湾旧战斗引擎。

从 CAS 仓库根目录运行：

```powershell
python -m pip install -r server/requirements.txt
python -m uvicorn server.accounts:app --host 127.0.0.1 --port 8021
```

访问 `http://127.0.0.1:8021/docs` 查看接口。数据库默认独立存放在 `server/data/cas-accounts.sqlite3`；`CAS_ACCOUNT_DB` 可指定另一个 CAS 数据库。应用标识和版本门会拒绝已有的其他项目数据库，旧版 CAS 库会保留资产并迁入战局表。服务只用于本机回环测试，无公开账号服务、对战匹配或支付。

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

除健康、目录、注册、登录外，必须发送 `Authorization: Bearer <token>`。用户名为 3–40 位英文字母、数字、点、短横线或下划线，忽略大小写；密码 10–128 字符。密码和会话在数据库里分别保存带随机盐的 PBKDF2-HMAC-SHA256 摘要与 SHA-256 摘要。令牌有效期 30 天。允许本地开发浏览器、CAS Windows WebView 和 Android 应用资源来源；可用 `CAS_ACCOUNT_ORIGINS` 添加明确来源。浏览器跨域许可不能代替账号鉴权。

### 原经济规则

目录由旧手游的两个固定 Git 文件投影生成，收录 210 个稳定身份、22 个可征募收藏、两池和三种礼包。旧竞技点没有进入新目录；普通舰的原测试价按投影出的 `credits_price` 保存为纯经济字段。所有舰均标为 `combat_ready=false`，不带旧规则数值或舰卡引用。当前目录只承诺可收藏，不提供战斗能力。

双池为 `missouri-up` 与 `standard-v2`，基础概率为普通 75%、精锐 20%、稀有 3%、UR 2%；分别在连续 10／40／80 抽触发相应保底。UP 池 UR 首次 50% 命中密苏里，歪后下一次 UR 必中。两池的计数、兑换进度和专用券互不混用，原兼容通用券为不足部分补齐。每抽 1 进度，80 点兑换本池指定 UR；重复普通／精锐／稀有／UR 转为 1／5／20／50 勋章。省略池号时保留旧版无 UR 的常驻规则，标准新客户端应显式选择 `standard-v2`。每周 500 补给币兑换一张常驻券，以北京时间周一切换。

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
| 7 | 北卡罗来纳；对应 CAS 舰卡尚未就绪，暂不发放，保留前六次进度 |

每个北京时间日期最多一次。漏签时下次继续原档；服务器日期落在上次签到之前时暂停发放。稳定奖励键为 `rookie-check-in-v1:1` 至 `rookie-check-in-v1:7`，通过账号事务一起保存签到日期、固定奖励、钱包与入账记录。失败或重复领取不会新增账本行。接口没有日期、奖励量、舰 ID 或导入离线签到的字段。`POST` 返回 `{claimed,rewards,check_in,meta}`，资格不足返回 `claimed:false` 和状态（例如第七天的 `ship_pending:true`）。首次请求的幂等答复可能比当前日期旧，界面可再读 `GET` 刷新。

`/progression` 只汇总已有可信进度：固定新手赠礼仍标 `practice_verified:false`，战役胜场和分档来自真实 CAS 终局。此接口没有写入途径，不虚构账号经验或等级，也不把收藏当作出战资格。

### 验证

```powershell
python -m pip install -r server/requirements-test.txt
python -m unittest -v server.test_accounts server.test_battle_pve server.test_account_progression
python -m server.smoke_http --sim .\target\release\cas-sim.exe
python -m server.import_catalog 'F:/Codex/worktrees/android-mobile/铁底湾'
```

HTTP 冒烟在临时 SQLite 中实际启动回环 Uvicorn，覆盖注册、发信领取、扣券、签到领取与隔离、同请求重试、账本、退出，以及轴心标准档圣乔治角开局、自动推进、命令重试和其他账号拒绝。完整测试另以注入的服务器时钟和种子跑到真实 CAS 战术／决定性胜利、五路并发领取、差额补领、账号隔离和重启恢复；签到测试跨北京时间午夜、漏签、日期回退和第七日冻结。时钟和种子注入仅在测试代码内，实际 HTTP 不接收这些字段。没有编译原生程序时，权威 PvE 测试会跳过，经济和签到仍可独立运行。目录验证只读取旧仓的固定 Git 对象。
