# CAS 接手说明

交接基线为 2026-11-06 的 `D:/desktop/cas`，主分支代码基线 `d3f907a`。本次因当前会话额度接近上限而移交，完整项目仍在开发。先读根目录 `AGENTS.md`、`agent.md`、`plan.md`、`havedone.md`，再按[后续实施与验收计划](implementation-roadmap.md)继续。`havedone.md` 现有未提交改动是此前的缓存清理记录，接手时保留。`stash@{0}` 的两份笔记已经回填，勿直接再次套用。

## 用户要交付什么

交付 Windows 与 Android 版独立 CAS 游戏。打开先登录，再进入从铁底湾手游代码迁入的母港。原手游的大厅、模式、活动、征募、商店、邮件、角色、舰队编组、竞技、剧情、战役关位和地图背景都要逐项恢复。玩家进入战斗时使用同一套 CAS 实时内核。原剧本有同一次 CAS 交战就采用 CAS 部署、舰型和胜负。有五场无对应或只有不同作战形态的近似对应，照搬旧剧本的地图、位置关系、编队和任务，以 CAS 舰表与规则运行并标明架空或改编。全部玩家可见关名、舰名、任务、战报和操作用中文，原文与稳定 ID 留在资料层。

CAS 五版规则、适用玩家表、扩展临界表、想定特例和时期舰表是裁决基线。即时化只改变下令、时间分配与表现。须有两种编队机动、多航点、连续转弯、逐座炮塔旋转和装填、可见炮弹与鱼雷实体、射程圈、关键事件弹窗、带舰娘立绘的舰况图。序章保留原剧情，在真实大舰队交战海图上推近第五驱逐小队，叠加视觉小说式对白，沿固定步骤引导操作。雷达和夜战另有固定剧本与教官状态机，按真实引擎事件过关。规则、剧本、端上体验和线上功能都达到验收门槛后才算完成。

## 一小时内恢复开发

1. 在主仓运行 `git status --short`、`git log -12 --oneline`。另查下表三份工作区，保存各自的当前差异再合并。它们在本次交接时已中断，未提交代码仍留在原工作区。两个分支都改了 `server/accounts.py`，应逐块合并账户入口与导入，避免相互覆盖。
2. 先修已复现的 `client/src/main.tsx` 类型错误。`cloud.current` 现在可以是联机战役或双席约战，`endingKey` 直接取 `.battle_id` 会使 `tsc` 失败。将云端分支改成 `cloud.current ? onlineBattlePath(cloud.current) : (campaignId.current ?? 'session-' + session)`，保留同一局的稳定 key，避免回港、重连或回看重复播放结局。先跑 `tsc`，再跑结局与双席浏览器回归。
3. 完成并合入排位后端、线上征募和塔萨法隆格。对所有新提交重新跑主仓验收，隔离分支的通过记录不能替代主仓测试。保持 v8 固定约战和 v9 个人舰队同时可恢复。每次重新发包更新实际启动用的 WASM，确认客户端没有继续加载旧二进制。
4. 完成一条后继续剩余 CAS 规则和关卡。下面的缺项是交付范围，不能用档案占位、预览素材或内部引擎调用替代玩家入口。

## 主仓与并行工作区

| 工作区 | 停点与后续 |
| --- | --- |
| `D:/desktop/cas` | 主仓 `d3f907a`。已合入 v9 定深、分量齐射、两舷防护、固定双席、个人舰队原生接口、库拉湾、结局图与回看、签到图与本机征募。客户端尚有上述 TS 错误。 |
| `F:/CAS-audio-work` | 权威服务。已合入主仓的固定双席服务原提交 `1c54180`，主仓为 `51fc927`。排位未提交差异在 `server/accounts.py`、`battle_pve.py`、`duels.py`、`fleets.py`，新增 `rankings.py`。曾用实际 v9 原生程序和冻结点表启动 3000 分，完整排位流程与集成证据待补。不要把此目录误作音频专用。 |
| `F:/CAS-client-next` | 结局、北卡罗来纳签到预览、本机征募、回看已合入。原分支提交 `8a00978`、`db5d991`、`0c91295`、`6d28263`、`3a9414f`。线上征募尚未提交，查看 `client/src/OnlineSupply.tsx`、`client/src/online.ts`、`client/src/online-recruit/` 和 `server/accounts.py`。 |
| `E:/CAS-rules-next` | 库拉湾提交 `d1deb5e` 已处理共用规则版本与战役结局投影冲突，主仓为 `dcbd9fc`。塔萨法隆格当时还在核原页，交接时该工作区 `git status` 干净。下一批从当前主仓开独立工作区，或者在核对差异后更新旧分支。 |

## 资料与工程入口

| 资料或代码 | 用途 |
| --- | --- |
| `D:/desktop/cas/CAS带翻译/CAS带翻译` | 原始 PDF 只读。五版主规则、玩家手册、扩展临界表和《旭日》等剧本在此，`船表` 下有各国舰表和具名 Form 10。页码以 PDF 从 1 起和书上印刷页同时登记。先提取定位，再目视原页、图示和表列。 |
| `F:/Codex/worktrees/android-mobile/铁底湾` | 参考仓只读。0.6.11 离线交付固定 `6601bddde1b4f0817ebbb6864ee80137647e1d88`。0.6.9 的外层与战役资料基线 `48385c8`。0.6.7 实际联机基线 `9b5b2b2:mobile/mobile_pvp.py`。按版本读 Git 内容，当前工作树可能有其他改动。 |
| `D:/desktop/鱼叉` | 参考固定时钟、双盲、权威校验、状态机接管与重演。现代武器、传感器和界面无须移植。 |
| `src/world.rs`、`model.rs`、`movement.rs`、`combat.rs`、`realtime.rs`、`damage.rs` | Rust 战斗规则与固定一秒步长。`projectile.rs` 决定空中炮弹和弹着，`radar.rs`、`sighting.rs`、`night.rs`、`illumination.rs` 处理观察和照明。 |
| `src/campaign.rs`、`src/campaign/live.rs`、`data/campaign/` | 战役档案和运行分流、时期包、中文词表与稳定身份对照。关卡流程从 [32 关对照表](campaign/source-crosswalk.md) 和 [CAS 规则覆盖台账](rules/coverage.md)接着做。 |
| `client/src/main.tsx`、`BattleMap.tsx`、`BattlePresentation.tsx` | 战局入口、共用海图、拖放火力、射程圈、弹道、弹窗、舰况。`client/src/prologue/`、`tutorial/`、`audio/` 接剧情与战斗事件。 |
| `src/match_host.rs`、`src/ranked_fleets.rs`、`server/duels.py` | 原生私有 `match_*`、两个席位共享同一世界、CAS 舰卡组队及双席 HTTP。线上服务验证账号和席位，浏览器只收本席观察、预览、战果和战报。 |

原对话参考 [铁底湾手游开发与并行方案](codex://threads/01a1a6d6-24fc-7cf1-ba7b-73ef067f6d3d) 和 [鱼叉 RTS 接手任务](codex://threads/01a19c30-7258-7560-be1d-c4c6e768136d)。用户最后指定直接迁移原手游相关代码，所给截图仅是指认母港页面的材料。

## 可用二进制与验证凭证

- 最后有发包及校验记录的是 `C:/Users/fwj/AppData/Local/CAS-builds/20261106-v8/` 的 Windows ZIP 与 Android APK。v8 Windows 有启动、保存、重演证据，Android 有构建、验签和共同文件校验，**v8 APK 未完成装机验收**。已有 Android 模拟器旧版记录，仍需当前 APK 的实体机横屏与跨端对战。证据在 `D:/desktop/cas/artifacts/v8-acceptance/`。
- v9 原生为 `E:/CAS-v9-native/release/cas-sim.exe`，WASM 为 `F:/CAS-v9-wasm/wasm32-unknown-unknown/release/cas_core.wasm`。主仓合入库拉湾时 **59 项 Rust 通过**。主仓 v9 最终客户端、完整双端发行和最终旧档差分尚未验收。固定约战另有 `E:/CAS-match-core/release/cas-sim.exe` 可复现旧验收。新服务应使用本次重新构建的原生程序，旧对局按开局固定的核心哈希继续。
- 固定非排位已过 14 项原服务回归及 2 项双席服务测试。种子 6107 两席炮击、放雷，真实中雷后同盟 2 比 1，只有一次结算。两个浏览器账号还验证了邀请码的大小写、服务器时钟、740×360 重连和投降后的两席终局。用 `client/tests/browser-online-duel.mjs` 重跑。[HTTP 回环凭证](F:/CAS-authoritative-duel-loopback.json)
- 库拉湾独立分支过 17 场原生／WASM 对照与双席浏览器。主仓库拉湾内核测试也通过，原 v9 总验收仍要重跑。同盟标准种子 6106，轴心挑战种子 2。轴心第 30 模拟分钟达成卸载，并有真实雷击。证据在 `E:/CAS-rules-next/artifacts/kula-native-wasm.json` 和 `E:/CAS-rules-next/artifacts/client/kula/browser-receipt.json`。
- 原结局图八张及手动回看覆盖 01、03 的双线胜败。实际平局进入普通战果，回看不重发奖励。本机实测初始舰队、UP 单抽、常驻十连、两池独立、回看不扣券及第七天锁定。证据在 `F:/CAS-client-next/artifacts/client/` 下的 `campaign-endings/`、`campaign-ending-regression/` 和 `local-recruit-and-activity/`。库拉湾的原版结局图仍需补。

## 开发和验收命令

在 PowerShell 中从主仓运行，先检查实际工具路径。回环测试用新数据库，排位开发同时换账号库和它派生的双席库。`8031` 与 `5184` 是上次临时测试端口，启动前检查是否仍在使用。

```powershell
Set-Location 'D:/desktop/cas'
$casCargo = Join-Path $env:USERPROFILE '.cargo/bin/cargo.exe'
$casPython = Join-Path $env:LOCALAPPDATA 'Programs/Python/Python313/python.exe'
$env:CARGO_INCREMENTAL = '0'
& $casCargo test --locked --lib
& $casCargo build --locked --release --bin cas-sim
& $casCargo build --locked --release --target wasm32-unknown-unknown --lib
node scripts/build-parity.mjs target/release/cas-sim.exe target/wasm32-unknown-unknown/release/cas_core.wasm artifacts/cas-integration-native-wasm.json
& $casPython scripts/check-campaign.py --ibs-worktree 'F:/Codex/worktrees/android-mobile/铁底湾'
& $casPython -m unittest discover -s server -t .
& .\scripts\build.ps1 -WebOnly -ReuseNodeModules
```

双席服务用 `CAS_ENABLE_DUELS=1`、`CAS_SIM_PATH`、`CAS_ACCOUNT_DB`、`CAS_ACCOUNT_ORIGINS` 后运行 `python -m uvicorn server.accounts:app --host 127.0.0.1 --port 8031`。排位分支合入后另用 `CAS_ENABLE_RANKED=1`、`CAS_RANKED_POINTS=D:/desktop/cas/data/rules/cas-competitive-points-v1.json`。客户端在 `client/` 用 `VITE_CAS_ACCOUNT_URL=http://127.0.0.1:8031` 启动 Vite，先核对 `/health`。本机浏览器测试可设 `CAS_PLAYWRIGHT_MODULE=F:/Codex/worktrees/android-mobile/铁底湾/mobile/node_modules/playwright` 和 `CAS_BROWSER_PATH=C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe`。打包用 `scripts/build.ps1`、`scripts/build-android.ps1`，本机 Android 工具链需 API 35 和 Gradle 8.11.1。Android 烟测用 `node scripts/build-android-smoke.mjs <adb.exe> <设备序列号> <凭证.json>`。产物、测试库和证据均保留版本名，勿覆盖旧包或真实账号库。
