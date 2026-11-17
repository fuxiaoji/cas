# 返航灯岛教学剧情

独立支线 `cas-home-story-v1`，不写回前三章剧情进度。前篇24页、后篇20页，共2132正文汉字。故事阅读约5.3分钟（400汉字/分钟），本轮真实救援178模拟秒；这是约8分钟的入门支线，不宣称一小时章节。人物通过换电池、冷却管、湿毛巾和撤收清单展开分歧：礁刃先要求同救所有身体，而非领取一份可被占有的协议；岛权来自维护护航线的委托，居民保有住地。

入口为原生可编辑 `godot/scenes/ui/home_story.tscn`，文本在 `godot/data/home-story-v1.json`。前篇末调用 `prepare_littoral('tutorial',42,['MCP-034'],[],'balanced')` 与生产入口 `launch_littoral`；保存中的行动使用正常继续入口。仅 `HomeService` 验证真实战斗结算后 `tutorial_complete` 为真，读者才进入后篇。文字演出不直接授岛、授人格、发资源或替代战斗。后篇结束才返回家园建设界面。

进度独立保存在 `home_v1.story`，含版本、phase、pre/post_index 与 pre/post_complete。每次下一页先做账户事务，保存失败保留当前页、回滚完整账户并显示可重试原因；前篇读完但未胜利时保持最后一页，提供继续行动。完成后重看没有额外奖励。

同一原生背景节点与三个原生演员节点持续存在；对白页不重建舞台。宽银幕近景使用既有 `story_actor_layout`，弗莱彻与旧金山复用已登记表情/眨眼，礁刃使用 MCP-034 本人画像，当前没有为她假造新的表情帧。两个原创CG仅用于关键开结场，普通对白使用已登记场景，0.4秒交叉淡变可随减少动态设置关闭。陆海地图依旧程序生成，不以CG替代。音乐分别为原创 story_tension / story，独立对白压低背景音乐。

Inspector 开关 `use_default_styles/use_content_text/use_content_artwork/use_cinematic_layout/show_cast` 支持保留自定义字体、字号、文字、底图及锚点。`@tool` 可预览前后篇及指定页，预览开关不能绕过运行时真实胜利门。当前按钮包括上一级、母港与继续；长对白自动扩展向上的渐隐区域，不缩小字号或遮住按钮。

真实GPU验收：`godot/tests/home_story_review.gd`，回执 `artifacts/home-story/receipt.json`，日志 `artifacts/home-story-gpu.log`。最终正式默认核 `7134b0254ce4ef91317181545eac2844813d8b6b54d95f644a5ec65db9a1a79b`、空 `CAS_SIM_PATH` 下120/120通过，覆盖实际主入口、前后篇逐页事务、真实保存失败、完整关闭重启、保存中救援继续、原核运输/搜索/撤收胜利、生产结算与胜利音乐及结果主按钮、重复阅读不领奖、前三章独立保存、960×540/1280×720/1920×1080/1600×720长文本与同框CG，以及编辑自定义保持。前一轮不可变候选证据另保存在 `receipt-stage-fb9621.json`。所有操作仅在只读43舰源文件的隔离副本，正常主账户及备份SHA未变。截图在 `artifacts/home-story/`，960/1280多人及CG已经目检。

独立生产主路由声音检查 `godot/tests/scene_music_routing_review.gd` 同一默认核59/59通过，回执 `artifacts/scene-music-routing/receipt.json`。标题、家园、协议招募、遗迹前篇、前三章实际对白回顾、海陆与肉鸽实战及更新、失败结算，均验证原创曲目、真实OGG与对白duck。战斗刻意从暂停开始，测试通过正常开始按钮再检查播放；原43舰账户当前在剧情guide节点，测试用既有只读回顾进入对白。初版误将guide当对白、暂停解码当停止的夹具失败保存在 `receipt-initial-fixture.json`，没有因此修改产品或放松真实播放检查。
