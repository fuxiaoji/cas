# 潮汐活动场景可编辑性与窗口验收

2026-11-12。仅修改 `tide_event_hub`、`tide_story`、`tide_battle_hud` 三套 `.tscn` / `.gd`；账户、服务、主应用和战斗控制器由主代理维护。本回执使用显式最终联调核心 `9c2557bb6cc9736069e53209112aaf15f157a62d3064fc8d8dd8cf3314c6692e`，用户档案不参与测试。

## Godot Inspector 入口

三个原生场景均保留 `@tool`，新增 `Presentation / use_default_styles`。先关闭此开关，再编辑节点的 Theme Overrides 或根 Theme：自定字体、字号、颜色、面板和按钮不会在 `_ready` / 重新绑定 / 保存重载时被脚本强行套回默认值。游戏实时耐久、时钟和升级内容仍由控制器更新。

| 场景 | 可编辑内容与预览 |
| --- | --- |
| `godot/scenes/ui/tide_event_hub.tscn` | `content_path` 指向活动JSON；`use_content_headings` / `use_content_artwork` 关闭后保留场景手工标题、说明、插画；`preview_tab` 即时预览三页；`responsive_shop_columns` 可关闭以保留手工列数。 |
| `godot/scenes/ui/tide_story.tscn` | `content_path`、文字/插画开关、`show_cast`；`preview_ending` 与 `preview_line` 在编辑器即时切换背景和对白。 |
| `godot/scenes/ui/tide_battle_hud.tscn` | 原生 Status / Hp / Xp / Clock / Pause / Menu / Hint / Upgrades 节点；`show_control_hint`；`preview_show_upgrades` 和 `preview_choices` 在编辑器预览升级面板，预览按钮不进入真实战斗逻辑。 |

活动Hero与剧情Backdrop已有原生Texture资源，关闭内容插画开关后可直接更换。概要内容改放 `BriefScroll/Body`，内容过长可滚动；代码中唯一 `body` getter指向该节点，外部活动入口没有依赖旧Body路径。商店在独立逻辑宽度1280时为2列，1600／1920时为3列，保留竖向滚动，不挤出横向屏幕。

## 真实验证

测试：`godot/tests/tide_scene_editability_review.gd`。最终 **144/144**，0 ERROR、0 SCRIPT ERROR，21张GPU截图。

- 三场景分别制作隔离副本，编辑字号31、自定颜色、自定StyleBox、自定Theme、自定文字与插画、位置偏移和提示开关；实际保存、重新加载、执行 `_ready`，活动与剧情再次绑定真实应用后核对保留。源场景SHA均未被测试改写。
- 1280×720、1600×900、1920×1080实际窗口：活动概要、故事入口、商店、全屏旁白、真实活动战斗HUD、真实升级三选一，共18张。检查非滚动按钮可达、商店横向边界、旁白完整高度、状态栏和时钟分离。
- 额外把原生活动场景直接挂到三种相同尺寸的独立逻辑画布，验证2／3列响应与网格宽度，共3张；区别于正常游戏1600×900设计画布随窗口缩放。
- 升级面板来自真实原核：以实际公开掉落导航并拾取，19秒触发共鸣Lv.2的真实三选一，不直接写升级状态。截图已包含主代理加入的升级期间 `cinematic` 情境情报抑制，标题后面不再叠怪物提示。

机器回执：`artifacts/godot/tide-scene-editability/receipt.json`。最终日志：`artifacts/tide-scene-editability-final.txt`。隔离可编辑副本：同目录 `*-custom-copy.tscn`。该回执记录的账户是PID专用测试档，未充值或改写玩家当前账户。

建议目视：`1280x720-event-overview.png`、`1280x720-event-shop.png`、`1280x720-story.png`、`1920x1080-upgrade.png`、`1280x720-native-canvas-shop.png`，均在 `artifacts/godot/tide-scene-editability/`。
