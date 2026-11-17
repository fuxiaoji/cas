# 家园账户与原生界面接线

版本：`home_v1.version=cas-home-v1`。海陆实战另用 `cas-littoral-v1`，不修改历史舰表与旧存档规则。只做本地 NPC 行动，不假装联网。

## 主程序入口

`home = preload("res://scripts/home_service.gd").new(economy)`。主程序在账户载入后实例化，`ensure()` 只补缺字段，不主动写盘，也不覆盖现有家园、故事或其他账户字段。

- `home` 页面实例化 `res://scenes/ui/home_island.tscn` 后 `bind(app)`。
- `home_recruit` 页面实例化 `res://scenes/ui/tactical_recruit.tscn` 后 `bind(app)`。
- 初次家园按钮进入 Root 提供的 `home_story`，剧情玩家调用 `app.launch_littoral(prepared.request)`。
- `littoral_battle.gd` 继承原有控制器，`new(app)`、`build()`、`update()`。它拥有独立 `littoral_battle.tscn` 和海陆两个观察视窗；海图提供 `planned/selected_ship/focus_fleet/cancel_pending` 兼容接口。
- 结果页实例化 `littoral_result.tscn` 后 `bind(app,receipt,back_callable)`。胜利教学继续 `home_story`，普通返回 `home`。使用自有舰弹药与战损，不显示“免费无损”。

## 公开账户接口

`state()` 返回当前家园子字典；`overview()` 给 UI 拷贝，包含只读自然恢复进度、待领生产、小时产量和二十编制目录。`unit(id)`、`released()` 查询本人身份。

`collect(now=-1)` 收取生产；`place(kind,Vector2i)` 落建筑；`upgrade(id)`、`repair_building(id)`；`set_garrison([owned_ship_id])`；`care(unit_id)` 护理；`draw_units(1|10,request_id)` 招募；`unlock_test_units()` 仅允许已明确标记的测试档。所有持久操作使用原账户 `_commit`，真实保存失败回滚。

```gdscript
var prepared = home.prepare_littoral(
    "tutorial", 42, ["MCP-034"], ["IBS-U-USN-FLETCHER"], "balanced")
# {ok, request, loaded_ammo, borrowed_tutorial}
var created = core.request(prepared.request)
var saved = core.request({"op":"save","serialized":true})
var active = home.begin(prepared.request, saved.serialized)
# active: mode=littoral, ruleset, run_id, request, snapshot, fleet,
# home_frozen={units, ships, resources, loaded_ammo, borrowed_tutorial}
```

请求冻结：`op,new_littoral/version,seed,mode,ships[{id,hp,ammo}],roster[unitID],unit_condition[{id,hp}],transport_preset,defense[{id,kind,x,y,level,hp}]`。`ships=[]` 默认驻舰，否则当前旗舰；`units=[]` 默认可用已拥有队伍，首次教学只借礁刃。UI 显式选择随行队，不能部署目录中十五支整编中编制。

出航界面以本人肖像实际选择 1–6 艘已拥有舰娘，并单独选择战术人格与装弹预设，不被驻防名单锁死。新海陆规则的 AV 水上机母舰兼运输支援：日进、千岁基础16槽，原本人 HP/炮表与历史规则不改。未拥有时只提供真实舰娘招募入口。正常标准招募可以获得这两艘；验收副本40次真实招募获得日进后，实际选择并承载五支编制出航，没有直接伪造拥有。

`NPC_ISLANDS` 登记三座本地人机岛：碎波哨岛（18031，4设施）、旧港仓岛（29143，5设施）、长云堡礁（37057，6设施）。`npc_layout(seed)` 仅用于 `raid`，保存真实中枢/岸炮/AA/仓库配置；`begin` 根据登记种子重新计算，拒绝客户端替换布防。教学42及其他模式不套 NPC 布防。奖励沿用真实原核回收量，不给不同岛伪造额外收益。远征的 `home_battle_mode=salvage` 来源会将家园主按钮与出航首选聚焦到遗迹搜索。

`begin(request,serialized)` 独立原核重演开局并核对精确配置、种子、tick0及身份。自然恢复在预览后略有增加时允许冻结更早的低整备率，不能添加未获得的健康。弹药只扣实际装载部分，未装部分留在原库存。

`settle(view,serialized,abandon=false)` 独立桥接重演，逐字段核对 `littoral/ships/result/tick` 与出航配置；只接受真实终局。返回 `{ok,receipt}`，重复请求返回已有回执，不重复奖励。主动退出先执行 `littoral_abandon`，不能以客户端标志抹去损耗。

炮援操作选择本方支援舰与陆上落点后，控制器根据公开射界发送一次真实 `face` 和一次 `littoral_support{queue:true}`。原核逐步转向、真实装填后优先执行岸援，公开 `pending_target`；相同按钮可取消，90秒原核过期，不在 UI 伪造炮弹或扣弹。立即炮援原义保持。空投和直升机支援仍由真实载舰距离/空中身体/余弹裁决。合法 `Extract` 成功后控制器立即调用结算，即使玩家先暂停也不会等待下一帧而卡住。

复盘保存小数秒及10Hz帧，滑块步长0.1秒；离开只读复盘会重新载入原航次完整日志并保持暂停。复盘不修改账户资源。暂停中真实搜索完成、部队回舰、全舰入区后点击生产撤离按钮已单独验收，立即进入结果、清空当前航次且只结算一次。

## 资源与持久性

家园资源 `scrap/alloy/energy/protocols/credits` 分别显示浮材、合金、能源、协议片、岛屿补给。它们均在 `home_v1.resources`，`credits` 不是母港银币。生产最多累计八小时，每种上限 20000；升级建设消耗岛屿补给，三级建设另消耗协议片。建筑先兑现旧产率再变更，不能追溯获得新设施产量。

首次真实教学胜利授岛权、永久 MCP-034 和十协议券。当前招募只投放五支实装编制，每支 20%；每抽一券，券不足则 160 元词。连续十九次未收录新核心，下次保证未收录；全部收录后正常转重复协议片。重复为十协议片，不叠兵力。持久整数 RNG 与请求 ID 防重复扣付。其余十五支仅图鉴预告，不能付费抽到未实装部队。

人物核心永久保留。整备以绝对基础生命百分比记录，零整备也不删核心；每三十分钟自然恢复 1%，医疗站等级提升自然速度。材料护理最多 +5%，每三十分钟一次，不能付费瞬满。未回收/失能的真实损耗与舰娘 HP 写回账户；只返存活且已回收舰的实际余弹，未装弹不重复退还。侵入失败仅扣家园可掠资源，单项不超 10% / 80；不删建筑或角色，不扣主钱包。

`home_v1.story` 由独立剧情播放器拥有，家园服务不会覆盖。获岛与编制发放以原核教学胜利为准，不由翻页伪造。

## 可编辑性与验收边界

四个 `.tscn` 是原生 Control/Container 场景，公开样式开关、颜色、种子、网格等 Inspector 参数。家园云水海岸和建设网格为程序绘制，不依赖固定地图照片；战斗观察使用原核同一世界坐标。陆军身体采用小巧女性动漫符号并关联 MCP 身份，编制/详情/卡池使用本人画像，不借舰娘立绘冒名。

最终默认原核 `7134b0254ce4ef91317181545eac2844813d8b6b54d95f644a5ec65db9a1a79b` 无环境覆盖：`home_account_review.gd` 271/271、`home_ui_review.gd` 42/42、`home_npc_review.gd` 37/37、真实 GPU `home_visual_review.gd` 33/33。各回执在 `artifacts/home-review/`，含实际 PID 对应可执行路径/SHA 与默认 manifest 校验；无头检查不冒称画面验收。

实际主档只读，账户事务只作用 `artifacts/home-review/isolated-*.json`；普通经济守恒副本会移除测试自动补满标记，避免重载补满掩盖装弹守恒。测试前后主档 SHA `85cb16a9926967dd2187af4a9f4e0e559cdf9b3ff4523d32898671033af18bd5`、备份 `432e24b1356ac7f0f972cbd26bccbeb4f7f95d9342ccddf51f0108f80c8f21fb` 完全未变。

真实教学178秒搜索→返回载舰→进区撤离，含完整关核/账户重载、弹药守恒、防伪/去重/写盘失败回滚。实际具名岛突袭272秒获胜，日进与密苏里存活回收，但云隼/冬鸢损失、工兵约10.26%、礁刃约37.43%整备；按真实损耗持久恢复，未宣称全员无损。三座 NPC 配置均实际生成并核对，完整胜局只实测碎波哨岛，不宣称每座任意配队均通关。

实机截图包括完整海岸与驻舰、本人半身编制卡、舰娘出航选择、海陆联动、真实岸炮与空中支援。卡池在960×540、1280×720、1920×1080核验完整头脸与主操作，主图完整等比容纳源图，不中心裁头；程序海岸内有浅滩/草坡/石簇/树林，低对比动态水纹。首五种人格身体与装甲驾驶员发色按本人区分。仍为轻量程序俯视表现，不宣称完整3D模型、联网互袭或二十支全部可实战。

复跑：使用项目 Godot 可执行文件，`--headless --path D:/desktop/cas/godot --script res://tests/home_account_review.gd`；UI与NPC改用同目录对应测试。画面验收运行 `home_visual_review.gd` 并去掉 `--headless`。清除当前子进程的 `CAS_SIM_PATH`，不改系统环境和主账户。四模式原核完整矩阵、native/WASM与旧冻结详见本轮整合回执。
