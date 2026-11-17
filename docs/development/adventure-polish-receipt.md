# 冒险节奏、货舱拖拽与搜打撤行动系统交付

日期：2026-11-12。此页整合先前六项打磨与随后追加的五项搜打撤要求；历史战役和旧航次保持原版本，原始PDF及迁移参考工程只读。

## 如何试玩

双击 `D:/desktop/cas/CAS-Godot.cmd`。编辑工程导入 `D:/desktop/cas/godot/project.godot`，按F5。已有旧窗口可正常保存退出，再打开新窗口；运行程序按哈希隔离，不强关玩家游戏。

母港出航 → 打捞远征：选择风险、行动场景、地貌、天气 → 编成一个或多个舰队 → “装载与货舱”调整弹药携带量/鱼雷卸载 → “弹种与备雷”配置弹种与0–2轮备用鱼雷 → 确认出航。

战场“行动”查看三项可选任务并接取/定位/交互/放弃；“自动打捞”选择谨慎、均衡或大胆，再明确启动。手动下令即接管。打捞物逐件搜索后可直接拖入格子，R旋转，双击快速装入；红色不能放，灰色交叉是备雷等占用的不可用尾格。只有实际入舱并撤离的物资可带回，在仓库兑换银币或拆包。

新搜打撤显式 `cas-adventure-v2`；剧情实战保持 `cas-adventure-v1`。旧存档继续原航次，返港新开才启用新规则。建议1×模拟时钟观察；舰队航行本身已10倍提速，并提高加速和制动。

## 已实现内容

- 五场景：溺城街区、拜教中继、风暴船冢、热泉裂谷、流民堤道。与四地貌/三档风险/天气组合使用，种子决定地图与物件布局；水波、云、岸线、植被及场景建筑以程序表现。
- 每航次三项可选任务，来自中继、测绘、救援、信标、密藏五类。任务产生真实局内效果或可搜索实物箱。Boss先预告后进入海域，每航次最多一次，可以挑战或带货撤离。
- 按部署分数预算加入拜教遥控巡逻舰；七类原创怪物统一90度俯视，每类六姿态。蓄力、打击、受伤、确认死亡依本席公开状态播放，失联不冒充死亡。
- 均衡/穿甲/高爆三种炮弹，标准/疾行/重型三种鱼雷；有限备雷20秒装填，重型30秒。备雷每轮实际占2格，原核和UI都拒绝不可用格。
- 16种世界观打捞物，独立物件图、形状、重量和售价。净水滤芯、医疗箱、旧世相机、记忆匣、教团运算棱镜等可换银币；封存舰装箱和水手档案才拆包。
- 原核专用自动指挥，评估血量、弹药、载货、可见威胁与Boss，再实际航行/搜索/入舱/挑战/撤离；支持多编队、接管、保存与重演，不做菜单发奖。

设计参考及CAS取舍见 [行动系统设计](../design/extraction-operations-v2.md)。数值、任务、预算与版本边界以原核规则记录为准。

## 同批完成的界面和剧情打磨

标题采用灯塔晨光、留白与中文衬线“归航”，保留开始/继续/设置/退出的真实操作；环境微动和减少动画选项同步。军需处恢复迁移前六名AI原立绘的完全相同文件字节，并映射九种现有方案；沿用既有解锁、购买及切换事务，没有另造替代角色。

货舱支持保留抓取偏移的真实拖放、完整绿色/红色落位预览、旋转、取消、双击快速放置及旧点击方式。全部第一章实战补充逐步引导与对应实体攻击教学，消除自动重复情报卡和对免疫旗舰的错误威胁提示。

v1阶段独立证据：

| 实测 | 结果 | 记录 |
| --- | --- | --- |
| 三场剧情真实窗口、胜利和首次奖励 | 412/412，68/65/109模拟秒 | `artifacts/godot/adventure-presentation/receipt.json` |
| 四地貌×三难度程序海域 | 120/120 | `artifacts/godot/adventure-environment/` |
| 旧v4/新冒险实际拖放、搜索、装载和撤离 | 83/83、86/86 | `docs/development/cargo-drag-receipt.md` |
| 标题多窗口/旧AI肖像精确哈希/真实交易 | 81/81 | `artifacts/godot/adventure-title-ai/report.json` |
| v1原生/WASM/存档重放 | 17/17；旧28请求冻结一致 | `docs/development/adventure-core-receipt.md` |
| 独立集成与Edge兼容 | 10/10、12/12，0页面错误 | `artifacts/adventure-integration-audit/`、`artifacts/browser-adventure-wasm-smoke/` |

## 美术与可编辑入口

- `godot/scenes/ui/title_screen.tscn`、`tactical_ai_card.tscn`：标题与军需AI卡片。
- `expedition_select.tscn`、`expedition_card.tscn`、`godot/data/expedition-design.tres`：风险、场景、地貌和天气。
- `munition_setup.tscn`、`munition_row.tscn`：航前弹药配置。
- `expedition_operations.tscn`、`expedition_board.tscn`、`expedition_task_card.tscn`：战场入口、任务和自动指挥。
- `cargo_hold.tscn`、`cargo_loadout.tscn`、`cargo_search.tscn`：货舱、装载与搜索。
- `godot/data/loot-v2.json` 镜像 `data/salvage/loot-v2.json`；规则目录为权威来源，新增物品同步两份并通过校验。
- 新标题/字体许可见 `docs/art/generated-assets-2026-11-12-v6.json`；旧AI来源和完整提示词见 `godot/data/ai-art.json`；七张俯视六姿态原图及完整提示词见 `docs/art/generated-enemies-topdown-v2.json`；22个原创物件/弹药SVG及哈希见 `docs/art/expedition-object-icons-v2.json`。

这些是可修改并重新保存的真实场景、资源、Atlas和节点。对象插画不是固定战场背景。

## v2 最终集成与验证

| 验收 | 结果 | 证据 |
| --- | --- | --- |
| Godot真实新玩家流程、弹种弹窗键鼠、任务/接管/精确保存恢复、实物结算/准确物件图与售卖 | **152/152**。默认三舰第29秒实际带回4件；售卖1件后，重启账户保留银币与3件实物 | `artifacts/godot/expedition-v2/receipt.json`，7张窗口图 |
| 五程序场景、俯视动作、真实受击/确认死亡/Boss公告与隐私 | **200/200**，39图 | `artifacts/godot/expedition-presentation/receipt.json` |
| 实际场景修改、保存重载与39组页面布局 | **177/177** | `artifacts/godot/scene-editability/` |
| 无环境变量默认F5/运行绑定、实际出航/保存/恢复 | **14/14** | `artifacts/godot/runtime-binding/report.json` |
| 原核全量 | **206/206** | `artifacts/expedition-v2-core/rust-tests.log` |
| 新规则原生/WASM/任务/装填/物理格位 | **22/22**，旧40请求冻结一致 | `artifacts/expedition-v2-core/parity.json` |
| 自动指挥真实航次与控制权 | **11/11**：10真实航次，7带货/3因风险空载返航，另16控制边界 | `artifacts/extraction-autopilot/report.json` |
| 自动指挥原生/WASM长航次 | **461个请求逐响应一致**；15项纯观察单测 | `artifacts/extraction-autopilot/receipt.json` |
| 启动器实际分发核与审计核/WASM | **35组749请求**，两native原始输出字节一致；旧40请求602118字节完全相同 | `artifacts/expedition-v2-launcher/receipt.json`、`frozen-byte-receipt.json` |
| 最终WASM实际Edge历史UI进入/步进/保存/整页刷新恢复 | **12/12，0运行错误**；测试进程已退出 | `artifacts/browser-adventure-wasm-smoke/receipt.json` |
| 双击启动器检查 | `CAS-Godot.cmd --check` **退出0** | `artifacts/godot-launch-build.log`、`artifacts/godot-launch-import.log` |

专项说明：[原核规则与凭证](expedition-v2-core-receipt.md)、[自动指挥](extraction-autopilot-receipt.md)、[俯视表现](expedition-presentation-receipt.md)。Browser是旧Web客户端兼容验收，不是Godot网页移植，也不替代Godot真实窗口。

审计原核SHA-256：`4786d5c707db7534cbe512c33a55474199fb3f506eb5d7100e49f7bd4e846b16`；最终WASM及client/public一致：`dd929d91632a2417268d2aef7c99557be6b3631cf540f9a48872f90acf3d1a79`。

启动器从同一源码在独立构建目录生成的实际运行文件SHA-256：`2ce63ce7c0afdc046d802917611541b7f7d2f0923db36e6e4b22755965dd32d2`。当前清单指向 `godot/bin/runtime/2ce63ce7c0afdc04/cas-sim.exe`，上述默认14项与完整152项均实际使用此文件；程序副本哈希匹配才加载，旧游戏进程继续自己的副本。已解析PE并证明两个原生构建仅20字节时间戳/PDB指纹差异，代码节一致；见 `artifacts/expedition-v2-core/pe-fingerprints.json`，不能仅凭猜测认定构建等价。

边界：这是已可玩的有限任务池和第一版风险/收益参数。自动AI的Boss/满格/任务取舍有受控公开观察测试，并不宣称自动通关Boss。历史兼容通过不冒充逐页重新认证全部原书想定；旧Web标题偏差按原blocker保留。后续章节、支付与联机服务不在这轮新增范围。
