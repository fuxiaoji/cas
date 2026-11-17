# 2026-11-12 新搜打撤远征原核交付

此回执只认证新的架空搜打撤 `cas-adventure-v2`。剧情保持冒险v1，历史阵位/舰表、旧v1–v4航次和旧存档不自动升级。本轮未修改原始PDF或参考项目。

## 实装内容

5种场景的独立种子地形/天气与3个唯一临时任务；5类任务的接取、放弃、现场工作、受损中断、真实效果和有限实物奖励。中继真实降低警戒，并改变敌舰追击持续时间、延后尚未到场Boss；Boss预告30秒后实际生成，最多一次，死亡只产生一个可搜索残骸。普通敌人包含两种有独立数值/读招的新海怪和按部署点数预算生成的真正军舰。

16种有明确目录ID、格形、重量、售价与sell/unpack用途的物资；实体搜索→摆放→撤离→账户校验，任务不直接发银币。弹药配置带真实HE/AP软体/装甲伤害取舍，快/重鱼雷速度/射程/伤害取舍，20/30秒有限备雷装填。每轮备雷扣2个真实可用格和110kg，尾部padding格明确禁放。公开射程圈对应实际鱼雷类型，不展示基础卡的错误射程。

核心接入独立纯观察自动指挥模块，玩家可开关、选择风险策略、手动接管。模块只读取本席公开观察并提交同样合法命令，原核继续判定转弯、碰陆、射界、装载、弹药与任务。保存/重放逐秒重建自动行为，不把内部派生命令重复写日志。只有已确认可见的死亡提供5秒动作证据；接触丢失不提供隐藏HP/炮击冷却。

完整协议与数值登记在 [expedition-v2.md](../rules/expedition-v2.md)。Godot `economy.gd`、`meta_economy.gd` 只为新普通搜打撤冻结新版本和配置；既有航次继续自己的版本。CargoService的账户收据和交互由主集成负责。

## 验证证据

- Rust全库206项。包括新场景/预算、5任务真实效果与有限奖励、20张场景/种子任务点300m净空及BFS连通、损伤中断与放弃不可重领、Boss预告/一次生成/一次残骸、中继实际追击时长与已预告生成延迟、16种货物多样性、快速有限装填和耗尽、备雷实扣4格/220kg、零重量小件也不能放尾格、失联后隐藏HP变化不影响公开观察、纯观察AI15项。
- `scripts/verify-expedition-v2.mjs`：22组native/WASM逐响应一致。15场景×难度、5任务分别真实导航至现场并在34–38秒完成、28秒真实导航/搜索/摆放/撤离、弹药成本与非法枚举拒绝。保存/重放也逐观察一致，操作请求保留在 `artifacts/expedition-v2-core/*-commands.json`。
- 与上一轮710269d3基线对照40条旧请求，覆盖旧v1–v4、三章旧/冒险v1、历史战役，观察和保存序列一致，证据 `artifacts/expedition-v2-core/parity.json`。不是通过修改历史数据换取通过。
- 自动航行独立11项验证：10次真实航次中7次带实际货物撤离，3次根据公开风险/损伤/低弹药空载避险；另16个控制边界。461个请求native/WASM一致，最终client同步后隔离Edge历史Web12/12、零页面错误，已关闭自有浏览器和服务。证据 `artifacts/extraction-autopilot/receipt.json`、`parity.json`、`report.json` 以及 `artifacts/browser-adventure-wasm-smoke/receipt.json`。不把这些边界测试解释为自动AI已实战击杀Boss。
- 主启动器在自己的构建目录编译出分发核2ce63ce7…；为排除构建路径/指纹误判，已独立对35组、749请求核查：两native原始JSON输出字节相同，并与最终WASM同值。覆盖核心22组、旧40、AI461和保留的前版25请求任务案例；证据 `artifacts/expedition-v2-launcher/receipt.json`。另710基线、4786审计核、2ce分发核的旧40请求原始输出602118字节完全相同，见 `frozen-byte-receipt.json`。
- 已解析两个PE的节和Debug目录：.text/.data/.pdata/.reloc完全相同；全部20个不同字节严格限于COFF/Debug时间戳和16字节PDB GUID，见 `artifacts/expedition-v2-core/pe-fingerprints.json`。不是仅凭哈希不同推测同一功能。

## 最终构建

采用独立构建目录，不覆盖玩家正在运行的旧程序。原核最终native SHA-256：

`4786d5c707db7534cbe512c33a55474199fb3f506eb5d7100e49f7bd4e846b16`

可执行文件：`target/expedition-v2-runtime/4786d5c707db7534cbe512c33a55474199fb3f506eb5d7100e49f7bd4e846b16/cas-sim.exe`。

最终WASM SHA-256：

`dd929d91632a2417268d2aef7c99557be6b3631cf540f9a48872f90acf3d1a79`

文件：`target/wasm32-unknown-unknown/release/cas_core.wasm`；主集成/浏览器代理同步 `client/public/cas_core.wasm` 并核验。生产运行清单由主集成切换，旧进程不被强杀。

启动器源编译分发SHA-256：`2ce63ce7c0afdc046d802917611541b7f7d2f0923db36e6e4b22755965dd32d2`，manifest指向 `godot/bin/runtime/2ce63ce7c0afdc04/cas-sim.exe`。已通过上述原始字节与WASM对拍。

边界：本次为有限任务池和首版风险/奖励值，未宣称所有舰型组合与无限种子的长期战斗/经济平衡完成。此前剧情Boss的特定玩家策略失败与新搜打撤分开记录，不把新核单元测试解释为全部剧情已经实玩通关。
