# 第一章演出在 Godot 中编辑

实际游戏使用 `godot/scenes/chapter_stage.tscn`，不是仅供演示的副本。剧情文字、镜头标签和演出设置在 `godot/data/chapter-scenes/` 的 16 个 `.tres` 资源中；历史 CAS 舰表、战役和章节实战规则不在这些资源中修改。

## 改文字、旁白和表情

在 Godot 文件系统中双击例如 `data/chapter-scenes/archive.tres`。在 Inspector 展开 `Lines`，逐项修改 `Text`、`Speaker`、`Speaker Name`、`Tone`、`Shot`、`Motion`、`Text Effect`、`Characters Per Second` 或 `Caption`。

- `Speaker` 使用 `chapter-one.json` 的 cast 键，如 `fletcher`、`drayton`、`perkins`。为空时默认显示“旁白”；`Speaker Name` 可改为“断续信号”或其他叙事身份。
- `Tone` 选择已有表情；无对应差分时回退到该角色基础立绘。它不会改变角色身份或舰表绑定。
- `Shot=near` 轻微推近背景；`Motion=step/wake` 为说话者入场提供短动作。旧 `pulse` 标签仍可读，但不再触发全屏闪光，信号以字幕与有限文字回声表达。
- `Text Effect=tremble/echo` 只用于寒冷、惊恐或断续信号，幅度很小；完整句子出现后 0.35 秒停止。普通对白保持静止。“减少动态”开启时不施加波动、呼吸、闪光或慢推。
- `Caption` 是对白上方独立、较浅的环境提示，不属于可推进的第二段对白。
- 标点自带短停顿。首次点击、空格或 Enter 显示整句并停止波动，第二次才推进；回顾或目录弹出时暂停阅读计时。

保留原有行序及两处选择的结尾位置。当前少数选择回声按 `waking`、`silence`、`hearing`、`message` 的原始行号定位。追加旁白可放在段尾；若重排原对白，需要同时核对 `chapter_presentation.gd` 的 `_spoken_text()`。编辑资源不会更改存档选择或替玩家完成关卡。

## 改场景和字幕版式

打开 `scenes/chapter_stage.tscn`。根节点的 `Preview Scene`、`Preview Line` 用于编辑器预览，修改 `.tres` 后可点击“刷新场景预览”。预览生成的立绘节点不写回场景文件。

稳定节点为 `Backdrop`、`Cast`、`HeaderShade`、`DialogueShade`、`SpeakerAccent`、`Speaker`、`Body`、`Environment`。可直接拖动锚点、修改字体大小、色彩和渐变。`Body` 是 RichTextLabel，使用 Noto Sans SC 400 字重。游戏运行时给同一组节点填入真实对白。

在场景资源上，`Background` 可指向新的 PNG/WebP，`Full Cg` 决定是否让整幅 CG 独占画面，`Actors` 决定普通场景同框角色，`Location` 是左上角地点，`Music Scene` 选择现有母港、整备或航行音景。只调整这些字段即可换背景和表现。

## 保持关卡与奖励独立

`data/chapter-one.json` 继续拥有 `kind`、`stage`、`next`、`rewards`、`choices` 和章节版本。`.tres` 只允许覆盖表现字段，不能跳过脱困、档案打捞或首领战。三场关卡使用真实核心结果才解锁后段；奖励仍在同一账户事务结算。

原有存档继续使用 16 个节点 ID 和 `chapter-01-v1`。本轮没有迁移历史战役或原始参考文档。第一章是独立架空故事。

## 编辑章节入口、路线和战场教学

`scenes/ui/story_catalog.tscn` 是实际竖幅封面目录，`scenes/ui/story_route.tscn` 是实际深色叙事航图。各节点锚点、封面裁切、字体和遮罩都可直接编辑；`Graph` 节点的 `Route Points` 是 16 个归一化坐标，可在 Inspector 中调整航线。节点 ID 和顺序仍来自原章 JSON。未解锁节点只留航线标记，不显示重复的“未抵达”文字。第二、三卷封面只为明确禁用的“未公开记录”，不代表已制作章节。

`scenes/ui/chapter_battle_guide.tscn` 是实战的可收起教学卡。它由实际 `LegacyBattle.build()` 之后挂接，观察已接受命令、当前选择、真实打捞/撤离计时及本席公开预警，按当前操作更新卡片。定位按钮只移动镜头和选择对象；减速、交还自动炮击是明确点击后才发出的普通命令。它不改关卡状态、不造胜利、不解锁未来段落。

同一剧情页中的舞台、背景和保留角色不会逐句销毁；只有背景资源改变时交叉淡出约 0.45 秒。说话者使用固定站位与短高亮，不循环呼吸，不从零透明度重新出现。“自动”开关保留本句已显文字与计时；“减少动态”立即停止镜头和角色动作，并保留对白内容。
