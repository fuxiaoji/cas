# 两栖拖动教学与战术类型兵牌

教学围绕一条可玩的动作链：把一支部队真正送上岛，学会移动、接敌、海陆炮援、搜索，再把人和物资接回来。每次只显示一句动作提示、一个明确落点和循环手势。没有“下一步”按钮，不通过等待计时器伪造靠岸、开炮、搜索或回收。帮助遮罩只改变视觉，卡牌和地图仍处理玩家的真实输入。

## 研究与取舍

- [海岛奇兵官方战斗画面](https://supercell.com/images/3eb6932d042109b6cbe3648aac122caa/bg_intro_boombeach.d95b42c4.webp)已经目检：海岛占主要面积、部队肖像卡在下缘、炮艇支援以物件图标呈现、撤退独立在角落。CAS 借鉴“看见对象→拖向世界”的布局关系，保留真实载舰、舰炮、运输和搜索裁决；此图片仅是设计研究，没有放入游戏素材。
- [皇室战争官方战斗画面](https://supercell.com/images/ec0b5871a0476c6ff55c0719fda231d9/bg_intro_clashroyale.ebe0a281.webp)已经目检：战场、单位轮廓、少量即时数字形成明确主次。官方[2022 更新说明](https://supercell.com/en/games/clashroyale/blog/release-notes/new-update-october-2022/)还记录连续放卡失败的 Drag Glitch 修复。CAS 的设计推论是：拖动必须有可靠的接受/拒绝回执，不能只播放一个漂亮手势就当作下令成功。
- 海岛奇兵[2024 年更新](https://boombeach.supercell.com/en/news/updates/the-calm-before-the-storm/)区分下一名部队就绪和全员就绪，并修复支援图标过早可用的误导；[2026 年更新](https://supercell.com/en/games/boombeach/blog/blog/frontline-improvements/)明确更新首次体验、把教学入口搬到可发现的 HUD。CAS 据此把“已排队”“正在靠岸”“真实上岸”分开，并提供随时收起/重看帮助，而不是常驻说明书。
- 兵牌参考美国陆军原始手册 [FM 1-02.2（2025，含 C1）表 1-5](https://rdl.train.army.mil/catalog-ws/view/100.ATSC/CD4DFE54-1C0B-43D9-B8BA-B869F10E6561-1739243205786/FM_1_02x2wc1.pdf)的“阵营外框→主要功能→必要修饰”构造语法。本轮是面向小尺寸游戏的原创简化符号，**不是 APP-6 合规渲染器**，不复制手册图像、不声称实现完整标准。

以上布局与文字量是设计观察，不能据此推出海岛奇兵具有 CAS 相同的自由移动、实际运输或炮位机制。

## 组件与接线

- `res://scenes/ui/littoral_drag_tutorial.tscn`：全屏 Control，场景内 Hint/Instruction/Close 可编辑；Inspector 可改遮罩浓度、手势周期、安全边距、减少动态。
- `res://scripts/littoral_drag_tutorial.gd`：只接收控制器事件与本席公开观察，不发战斗命令、不读写账户、不发放资源。
- `start_tutorial(progress={})` 后必须调用一次 `observe_state(app.core.view)`。开始时清除上轮缓存，避免上轮已回收的画面误完成新航次。之后只在收到新公开 view 时调用；动画过程不轮询游戏服务。
- `set_targets(rects)` 接 viewport 坐标 `Rect2` 字典；主/小地图交换、缩放与布局变化后更新。找不到目标就不画假落点。遮罩和手势鼠标穿透，仅“稍后”按钮接受关闭输入。
- `observe_focus(map_focus)` 接当前实际主图（sea/land）。恢复或重新教学时已经处在所需主图，就直接练下一动作，避免要求无意义地切走再切回来。
- `notify_event(kind,data)` 只接受 `accepted=true` 的实际交互回执；`drag_rejected`、拒绝事件和重复 `event_id` 不推进。
- 信号：`step_changed(step_id,index)`、`action_complete(step_id,proof)`、`progress_changed(snapshot)`、`completed()`、`help_closed()`。

事件数据：`event_id` 唯一；部队命令带 `unit_id/action/target_id`；炮援带 `ship` 或 `ship_id` 及 `world`（Vector2 或 `{x,y}`）；转图带 `focus="sea"/"land"`。`unit_ordered` 的 action 是 move、attack、search；撤收使用 `withdraw_ordered`。同一轮教学跟随首次实际部署的部队，不借另一支部队的移动完成此队提示。

| step_id | 玩家或等待动作 | 推进依据 | 目标 key |
| --- | --- | --- | --- |
| deploy | 拖卡上岛 | accepted deploy_queued 或公开 pending_deploy | deploy_card → landing_zone |
| approach | 载舰驶近 | group.stage 真实进入 transit/ground | transport |
| land | 登陆艇上岸 | group.stage=ground | landing_zone |
| focus_land | 点陆地图缩略图 | accepted focus_changed(land) | land_minimap |
| move | 拖队卡到空地 | accepted move 后此队真实位移≥4世界单位 | squad_card → land_move_zone |
| attack | 拖队卡到敌人 | accepted attack 且公开 group.order=attack；不声称命中 | squad_card → land_enemy |
| focus_sea | 点海图缩略图 | accepted focus_changed(sea) | sea_minimap |
| aim | 海图舰艇拖向岛屿 | accepted naval_aimed（实际朝向命令） | naval_support_card → naval_target |
| focus_land_support | 切回陆图 | accepted focus_changed(land) | land_minimap |
| support | 拖舰炮卡落点 | 队列受理后出现新的匹配舰艇/落点 shot；不冒报命中 | land_support_card → support_zone |
| search | 拖队卡到遗迹 | 指定遗迹 searched=true；部分进度不算完成 | squad_card → search_zone |
| withdraw | 拖撤收卡到部队 | accepted withdraw_ordered 且真实 retreat/returning | withdraw_card → withdraw_zone |
| recover | 等待接回载舰 | stage=recovered、其余存活部队也已归舰，且已有真实已搜索遗迹 | transport |
| focus_sea_return | 切回海图 | accepted focus_changed(sea) 或当前已是海图 | sea_minimap |
| return | 拖返航卡到撤离圈 | accepted return_ordered（实际 route） | return_card → return_zone |
| sail_home | 舰队实际驶返撤离区 | 所有存活舰艇入公开 exit 圈，存活部队已归舰 | return_zone |
| extract | 在圈内再次拖返航卡 | 真实 littoral.outcome.success；受理/失败/放弃均不算 | return_card → return_zone |

## 保存、恢复和重学

`snapshot_progress()` 返回 version=1、step_id、unit_id、proofs、help_open、review_only。proofs 用于审查与定位，不是权威完成凭据。Root 将其保存到 active_run.ui_state；账户仅在正常 completed 时设置 home_v1.drag_tutorial_completed。组件不解锁岛屿，也不发奖励。

恢复时先等待新 core 公开观察：embarked 回 deploy；pending_deploy 回 approach；transit 回 land；ground 回 focus_land；returning/recovered 回 recover；已在撤离圈且部队归舰回 extract。故意采用少量重复提示，避免把可编辑的 UI 存档当作已完成事实。真实 recovered 且真实 searched 可以确认回收；lost、inactive 和 returning 不算。回收后仍须真实返航、进入撤离圈、真实成功结算，才完成全部 17 阶段。`replay()` 是 review_only，不发新的 completed，不能重复领奖。`close_help()` 只关闭帮助；旧有岛账户从帮助重学，新 v2 首次流程自动展示由调用方决定。普通 raid/旧 v1 不由组件自行套用教学。

当前真态会调整练习：岸上实体与设施的完整公开列表证明敌人已清空，攻击步记录 enemy_already_cleared，并明确告知不再攻击死人；所有遗迹真实 searched，或公开 search_ruin 目标已完成且确有已搜索遗迹时，记录 already_searched 转撤收；公开舰炮已无存活可用火炮/余弹时记录 naval_unavailable，不能声称支援发射。仍有舰炮但没有存活敌人时，UI 提供合法空地试射落点，新实际 kind=naval 的 shots 才证明开火。没有弹药、提前清场或已经搜索本身均不能完成教学，仍要完成真实撤离。多支部队中尚有存活者在岸上时，回收提示会要求先接回其余队伍。

## 类型兵牌规范

`res://scripts/tactical_type_token.gd` 可作为 Control（对应 `scenes/ui/tactical_type_token.tscn`），也可在 CanvasItem 的 `_draw()` 内调用静态 `paint(canvas,rect,role,affiliation="friendly",selected=false)`。Control 提供 `configure(role,affiliation,selected)`、`set_role()`、role/nato_type/affiliation/selected 属性；静态 `canonical_role()` 和 `role_name()` 提供别名与短标签。

20 编制有 19 个唯一 role，加通用 infantry 共 20 个符号。支持 air_assault、marine、airborne、engineer、armor、recon、gunship、electronic、medic、antiarmor、artillery、transport、logistics、sniper、airdefense、riverine、breacher、command、rescue、infantry。外框区分己方矩形/敌方菱形，功能符号不只靠颜色；河岸部队有船底修饰、陆战队有海浪，避免两者完全一样。未知类型显示问号，不借另一名人格的图像。

优先传 core profile.role 保留游戏专长。只有 nato_type 时也接受 airmobile_infantry、mechanized_infantry、naval_infantry、airborne_infantry、assault_infantry、aviation、electronic_warfare、medical、anti_tank、air_defense、supply 等别名；这些是粗类型映射，不能取代完整角色身份。新 15 编制缺本人 SD 时由调用方显示**本人肖像+类型牌**，本组件不选择人物立绘。

## 验证与边界

独立组件测试 `godot/tests/littoral_drag_tutorial_review.gd` 101/101，通过 9 个真实 GUI Input 事件检查聚光洞/遮罩都可穿透，以及“稍后”关闭而不完成。状态推进部分使用隔离公开观察夹具，覆盖误拖、重复回执、真实阶段区别、旧炮弹/异舰/错落点、搜索部分进度、错误遗迹、returning/lost、伪造 UI 存档与跨航次缓存，以及敌人提前清空、无弹、已搜索、跨编队跟随、其余部队未回收、真实全舰返航与失败/成功终局。真实 Noto 主题下增加容器回归：Hint 保持 72–90 高、最多两行，“稍后”保持约 48 高；初次自动换行不能把面板遗留成 382 高。**这不等于实战拖卡全流程验收**；实战由 UI/原核整合套件另行给出。

GPU 独立渲染已在 1280×720、960×540 目检：提示只占上缘、两个清晰落点、手势横向移动、兵牌细线可读。组件视觉证据与测试回执在 `artifacts/littoral-tutorial-20261113/`；图中是组件排版样台，不伪称真实海岛战斗截图。本轮不修改历史规则、原核或 UI owner 文件。

正式整合已由 UI 套件给出：`artifacts/littoral-drag/guide-player/receipt.json` 23/23、98 个真实 Input 事件、无原核覆盖，`followed-hands.json` 只按教学实际 `_targets` 中心拖放/点击。公开时钟 27.1 秒上岸、53.9 秒搜完开始撤收、96.5 秒部队真实回舰、150.7 秒全舰到圈后成功撤离，guide completed=true；这些是模拟时钟，不把自动测试运行耗时冒称玩家游玩时长。已目检 `hand-move.png` 与 `hand-support.png`：Hint 维持紧凑上缘，手势的卡牌和目标与实际 SD/设施对应，中心战场没有再被提示框遮住。真实一倍速主循环长局与更多边界由总整合回执继续记录。
