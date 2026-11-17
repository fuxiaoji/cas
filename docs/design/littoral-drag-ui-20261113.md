# 两栖拖卡界面与真实玩家闭环

## 操作收敛

`godot/scenes/ui/littoral_battle.tscn` 是原生可编辑布局。主地图占据战场，右上是另一幅同步地图；点击右上小图直接交换海陆主次。底部仅一排卡，最多六支真实部队、一张已指定炮向的实际舰炮，以及当前队的一张情境能力卡。旧的多行指令/下拉控制台隐藏，原接口仅作旧航次兼容。

| 来源 → 落点 | 真正提交的行动 |
| --- | --- |
| 海图部队卡 → 岛上 | `littoral_preview deploy` 纯读合法性；松手 `littoral_deploy queue:true`。只携带该队的真实载舰沿合法水路靠岸，抵达插入范围后才开始运输。 |
| 陆图部队卡 → 空地/敌人/设施/遗迹 | 真实 `littoral_order move/attack/repair/search`；目标命中使用当前显示身体的投影与实际目标ID。 |
| 海图舰艇本人 → 岛上 | `littoral_ship_order aim_land`。不发炮、不假设已转好，观察原核公布的实际炮向/射界/弹药。 |
| 陆图对应舰炮卡 → 岸上落点 | 真实炮向命令及 `littoral_support naval queue:true`，等待真实转向、装填、发射与扣弹。v2未给这艘船指定炮向时不展示卡。 |
| 当前队能力卡 → 合法落点 | `littoral_ability`。卡上显示真实剩余次数/冷却；自体能力明确作用本人，目标能力服从公开距离。 |
| 当前队撤收卡 → 本人 | `littoral_order retreat`，等待实际步行/载具回舰。二次点部队卡可切换专长、旋翼或撤收卡。 |
| 海图返航卡 → 公开撤离圈 | 各存活舰分别接受真实 `littoral_ship_order move`。舰船靠岸后可能已分离，逐舰路线避免把旧编队相对偏移落到陆地。所有活舰真正入圈后再次拖卡才发 `littoral_extract`。 |

无效落点给红色轮廓和具体原因，不只依靠颜色。拖动中显示真实航线预览；结束取消浮动卡和轮廓。最终松手在切换结果页前先释放输入，避免离树的界面残留阻挡。

## 教学和状态

17阶段教学覆盖实际登陆、陆上移动/攻击、海图指炮向、陆图炮援、搜索、回舰、海上返航及最终撤离。手势源卡与落点都由当前世界投影提供。教学在v2教学行动启动；旧v1和普通行动不会因恢复UI而强制套遮罩。帮助可以稍后/重学，明确关闭状态跨重启保存。

教学开启且非拖动时清空底部陈旧指令，只保留顶部短句；拖动时才提示本次合法性。错误落点短暂保留具体原因，随后清空，防止两条陈旧提示互相矛盾。Hint继承真实中文主题后收敛为610×72设计像素，不遮住主战场。

`serialize_ui_state/restore_ui_state` 只保存账户侧的主地图、选中队、实际舰、情境卡和帮助进度，不写入或更改原核物理状态。恢复布局期间不消费暂时新建的教学观察，防止其覆盖磁盘上“稍后”状态。原核保存必须字节相同，能力恢复/复盘不能重复扣次数。授岛、授人和奖励仍由真实胜利结算负责。

## 身份和可编辑性

前五支保留本人十二姿态SD；新十五支目前使用本人肖像加原创军事类型兵牌，不冒用其他人物动作。`littoral_land.gd` 仍只根据真实位置、发射、受击与阶段展示。兵牌组件由独立的 `tactical_type_token.gd` 提供；底栏本人卡传入真实role，非可点击遮挡层。它采用简化军事类型语法，并不声称完整APP-6制式。

主/小图、顶栏、提示、底栏和输入层都可在 `littoral_battle.tscn` 的Godot编辑器中调整。双图实现是 `littoral_sea.gd` / `littoral_land.gd`，拖动组件是 `littoral_drag_layer.gd` / `littoral_drag_card.gd`。原有五人动作预览仍为 `godot/scenes/ui/tactical_sprite_preview.tscn`。所有展示偏移和缩放均不改变真实身体位置、攻击距离、舰艇航路或历史战役。

## 最终正式默认核证据

默认核：`db75a0459d23c3c814009d3de07de590003bc2a38508438efb84bd00f395121d`。以下三套均无 `CAS_SIM_PATH`；总107项、314个真实输入事件，主档/备档未写。汇总：`artifacts/littoral-drag/final-index.json`。

| 实测 | 结果 |
| --- | --- |
| `littoral_guide_player_review.gd` | 23项、98输入，只读教学公开from/to目标中心进行真实鼠标动作；17阶段真正撤离，27.1模拟秒上岸、150.7秒胜利。 |
| 同脚本 `CAS_GUIDE_REALTIME=1` | 正常Main 10Hz主循环、23项/98输入；27.1秒上岸、151.4秒实际终局，教学completed为真。首手势截图到结果截图文件实际写入间隔151.7713728墙钟秒。脚本本次未记秒表，墙钟来源明确是两张PNG的写入时刻，并非模拟秒推算。 |
| `littoral_drag_identity_review.gd` | 61项、118输入，960×540/1280×720/1920×1080真鼠标和触摸拖放、海陆交换、投影往返、无效落点不改核；011/018两名新身份真上岸。烟幕真实3→2次并20秒冷却，关核/账户重启原始快照完全相同、只读复盘不重复消耗，帮助保持关闭。 |

回执分别在 `artifacts/littoral-drag/{guide-player,guide-player-realtime,identity-responsive}/receipt.json`，手势轨迹在 `followed-hands.json`。图像包括 `hand-move.png`、`hand-support.png`、`hand-return.png`、`player-real-result.png`，以及 `two-new-identities-real-land.png`、`actual-finite-ability.png`、三窗口的海陆主图。

第一套指令诊断32项发生过结果页释放输入的脚本错误，现已修复；该候选记录明确排除在最终107项之外。早期layout截图仅作布局讨论，也不计验收。新身份测试克隆有明确QA授权的20拥有账号，报告标注 `isolated_qa_grant=true`，不冒称普通免费解锁路径；正常首章测试则必须真胜利才获得岛屿和礁刃。Windows实际窗口与输入事件的验证不冒称手机硬件实测。
