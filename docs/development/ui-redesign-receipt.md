# CAS 动漫云海 UI 重构验收

日期：2026-11-11。用户批准设计实施后完成，运行目标为 Godot 4.7.2 / Windows。本文记录本轮界面与表现层的交付，不替代规则核验、长期迁移清单或发行验收。

## 已落实的设计

**母港看角色，编队做选择，战场看海域与威胁，剧情看人物与故事。** 原则已登记至 `agent.md` 与 [设计文档](../design/anime-ui-reconstruction.md)，后续页面继续遵守。

| 页面 | 本轮可运行变化 |
| --- | --- |
| 母港 | 原创晴日港湾、大角色、单一主要出航按钮；底部四个主要入口。减少欢迎长文、重复统计和等重面板。 |
| 舰娘与编队 | 舰娘卡使用清晰上半身裁切；三舰编队直接点角色换人。常驻货舱、搜索和弹药，风险与详细编成展开查看，保留整备及借用舰入口。 |
| 航程与战役 | 剧情、战役、教学和挑战采用图像入口；战役保留原航图和真实目录。历史编成保留逐舰身份、时期、预算、预设及导入导出，候选用角色卡表达。 |
| 战斗 | 自动全屏、默认收起详细四标签面板、底部头像舰队条、按选择出现情境指令、暂停菜单及视图选项。炮雷按住锁定/微调/取消、多航点、同步/跟随、战术 AI、舰况、照明/雷达/烟幕和重演继续可用。 |
| 海域 | 青蓝水面、近岛浅水和白浪、轻焦散/日光碎光、柔软动漫云及云影；原岛岸内部增加林地、岩壁和受光平台。云避让只依赖本席已知单位，单位及威胁标记绘制在云层上方。 |
| 剧情 | 独立全屏月夜/晴日背景和人物对白，无母港导航、钱包。对白回顾、自动播放、跳过本段；跳过不越过选择、实操、奖励。三段真实实操保持同一战局与全屏切换。 |
| 征募 | 独立主视觉，海上信号→高清面部镜头→完整背景立绘→到港清册；可跳过或复看，沿用先保存结果再演出的规则，不因跳过重抽。 |
| 经济与战果 | 物资插画、成套图标、七日奖励格与较简洁的战果。完整损耗和结算详情可打开；库存、收费、奖励、维修、训练与重复领取约束保持原行为。 |

公共表现集中于 `godot/scripts/ui_design.gd`：象牙白、海军墨蓝、海水青与暖金；按钮、焦点、输入框和成套矢量图标统一。图标按 192 像素栅格化，角色卡裁切不修改原立绘文件。除母港外不再堆叠全局底栏；战斗、剧情和征募各自组织页面。

## 原创素材与来源

本轮通过内置图片生成功能生成并接入五张素材：

- `godot/assets/backgrounds/harbor-day-v2.png`：晴日动漫港湾。
- `godot/assets/backgrounds/night-sea-v2.png`：月夜海域对白背景。
- `godot/assets/environment/anime-cloud-v2.png`：透明柔云。
- `godot/assets/environment/anime-island-v2.png`：岩岸林地材质。
- `godot/assets/recruit/missouri-closeup-v2.png`：密苏里高清近景。

背景与角色近景的来源、提示词及 SHA256 在同名 JSON；环境素材见 `godot/assets/environment/anime-style-ledger.json`，征募登记在 `godot/assets/recruit/ledger.json`。设计学习来源见设计文档；其他游戏截图未作为游戏资产复制。小人生成与改动继续暂停，已有角色投影及原舰影开关保留。

## 验证结果

| 检查 | 结果 | 凭证目录（项目根目录下） |
| --- | --- | --- |
| 九类港口页面、换舰、图标及尺寸变化 | 23/23 | `artifacts/godot/ui-reconstruction/` |
| 单人完整闭环与历史战役 | 111/111 | `artifacts/godot/ui-reconstruction-integration/` |
| 原版战斗指挥与手势迁移 | 121/121 | `artifacts/godot/immersive-battle/receipt.json` |
| 战斗 1280×720、960×540、1600×720 | 16/16 | `artifacts/godot/immersive-battle/responsive-receipt.json` |
| 历史编成、身份与出航 | 68/68 | `artifacts/godot/deployment/` |
| 序章、三段同局实操、回放与防重奖励 | 99/99 | `artifacts/godot/prologue-migration/` |
| 剧情、征募、模式与经济页目视检查 | 23/23 | `artifacts/godot/presentation-redesign/` |
| 既有模式界面回归 | 26/26 | `artifacts/godot/full-modes/ui-receipt.json` |
| 既有模式与经济回归 | 95/95 | `artifacts/godot/full-modes/economy-receipt.json` |
| 海域观察不变、坐标投影与五个视角 | 无失败，5 张截图 | `artifacts/godot/anime-sea/` |
| 双击入口准备检查 | 退出码 0 | `artifacts/godot-launch-build.log`、`artifacts/godot-launch-import.log` |

合计 582 项有计数的断言通过，另有海域观察/投影检查。不同测试间有覆盖重叠，不表示 582 个独立功能。

完整闭环调用真实 Rust 进程：征募、编队、出航、打捞、保存暂离、跨场景恢复原样 64 位快照、撤离、实际结算、卖出三份废料换取 75 硬币、补给、训练、再次出航并真实失败，最后运行历史战役至 3287 秒。没有手写胜负回执。该轮使用 96 次 Godot 内部鼠标事件注入；战斗回归 132 次，序章 243 次。它们是实际窗口的内部输入，不宣称为操作系统鼠标测试。

序章保留原 92 项断言，并增加抽屉导航及三段实操的原生全屏检查。确认对白转战斗不被窗口恢复逻辑意外退出全屏。历史原核内容未修改，未把本次 UI 回归重新登记成原页/WASM/浏览器全部核验。

最后统一导入后刷新母港/编队/仓库/模式等页面、剧情/征募九张图、海域五张图；主代理目视母港、编队、战役、战斗、云海、剧情和征募。最终运行日志无脚本、资源或岸线三角化错误。

## 查看与启动

双击项目根目录 `CAS-Godot.cmd`。进入编辑器则导入 `godot/project.godot` 并按 F5。启动器的 `--check` 本轮再次验证通过。

- [母港实际画面](../../artifacts/godot/ui-reconstruction/harbor.png)
- [三舰编队实际画面](../../artifacts/godot/ui-reconstruction/formation.png)
- [战斗实际画面](../../artifacts/godot/ui-reconstruction-integration/04-salvage-sea.png)
- [最终云海总览](../../artifacts/godot/anime-sea/day-overview.png)
- [剧情实际画面](../../artifacts/godot/presentation-redesign/02-story-dialogue.png)
- [征募面部镜头](../../artifacts/godot/presentation-redesign/recruit-face.png)

## 交付边界

海域采用 2.5D 图像与着色表现，当前一个岩岸林地材质家族，不是完整三维水体/地形或新增水深规则。原岸线、历史阵位、探测、碰撞和 CAS 裁决保留。剧情复用既有角色立绘，未加入表情/Live2D，对白回顾仅存本次运行。小人方向与动画、Android 实机包、多人、商业发行和未实现剧情仍不在本轮完成范围内。原始 PDF、参考项目与既有用户改动保留。
