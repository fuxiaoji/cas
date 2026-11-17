# 第一章《返航灯》实装与验收

本章是独立的架空故事与真实单人关卡链。母港和出航模式均有“第一章 · 返航灯”入口；原有序章指挥教学保留，可从本章目录进入。不会把架空海怪、账户成长或新地图写进历史 CAS 战役。

2026-11-12 的后续演出、三张新增背景、Godot 可编辑资源和指挥官经验接入见 [演出更新验收](chapter-presentation-v2-receipt.md)，它包含本轮的最新验证数据。

## 叙事与演出

阅读用户提供的 `D:/downloads/CAS_世界观设定_v1.0.docx`，保留失忆主角、被第五驱逐小队救起、对憎恶舰娘的异常反应、战帮质疑、上层担保、AI 神教与淹没世界的线索。世界观中的“候选设定”没有直接当作已揭示的最终答案；本章反派明确为开门派传讯者，旁白与角色对白区分其和港内修理师，避免把整个 AI 神教写成单一敌人。

实际浏览的官方参考包括[明日方舟官网](https://ak.hypergryph.com/)、[Yostar Pictures 的第十二章 PV 制作页](https://yostar-pictures.co.jp/works/detail/2513/?lang=en)、[重返未来：1999 官网](https://re1999.bluepoch.com/en/home/)。用于研究角色焦点、场景叙事、短对白与轻控制的呈现方式；没有复制其 UI 或角色素材，也不声称逐帧观看了完整宣传片。

[chapter-one.json](../../godot/data/chapter-one.json) 包含 16 个节点：救援、接过海图、真实脱困、未落下的炮火、返港、听证、可选母港导览、补给任务、真实档案打捞、档案线索、教团来讯、真实首领战、战后接触、担保与命名、结尾线索、章节完成。两个玩家回答写入存档，后续短对白会呼应选择；不锁资源和战力。

演出是全屏场景，退出母港的钱包与导航外壳。四张原创 CG 分别用于救援、异常接触、听证、沉没信标；普通场景支持三角色同框、说话者提亮、入场淡入、轻呼吸、镜头近移与信号闪烁。三张明确的表情差分是弗莱彻担忧/决意、德雷顿担忧，另有潮痕和传讯者的独立角色立绘。资产路径、提示词、来源与 SHA-256 见 [chapter1/ledger.json](../../godot/assets/story/chapter1/ledger.json)。这些是静态角色图与程序动作，不是完整 Live2D 或全角色表情库；没有声称新增整章角色配音。

阅读可自动、空格/Enter 推进、先显示完整句子、回顾、跳过当前段、目录回看。跳过会停在需要亲自选择的回答或实际关卡前。已读记录和章节位置持久保存；重看对白不改变实际推进、选择或奖励。若玩家没有在实际战斗中触发 `aversion_spared_flagship`，后续对白采用记录不足的版本，不伪称目睹免疫。

## 三场实际行动

| 关卡 | 原核目标与条件 | 首次通关资源 |
|---|---|---|
| 雾线突围 `c1-breakout` | 触达公布的返航信标，仍可航行的全队进入撤离区并完成撤离 | 40 元词 / 200 银币 / 4 材料 |
| 失声信标 `c1-salvage` | 实际搜索指定档案残骸，再带着档案撤离；受攻击可中断搜索 | 60 元词 / 300 银币 / 6 材料 |
| 渊喉 `c1-boss` | 击败真实 HP、攻击预兆、阶段变化和召唤机制的架空海怪 | 100 元词 / 500 银币 / 10 材料 |

通过 `new_chapter` 启动，固定借用第五小队五舰，不扣个人体力、弹药、耐久，也不借此改变原舰表。每场只在 `view.chapter.status=won` 且真实 `result.winner=allies`、`primary=true` 时解锁后段；失败、主动撤退、跳过对白均不能通关。首次奖励共 200 元词、1000 银币、20 材料，并在同一事务增加每关 150、合计 450 指挥官经验；重复提交和再次实胜均不重复发奖。原有历史星数与序章进度保持独立。

`story_chapter` 航次上下文与原核 `chapter-01-v1` 快照共同校验章节、关卡、种子、版本、固定出航编成和战况时刻。存档保留同一会话、命令与模拟时刻；中途返港暂停，继续时重演原核快照。主角保护只属于指定憎恶实体对固定 1 号舰的目标筛选，其他舰仍受攻击，首领战也不提供全队免疫。

## 母港教学

[chapter_guide.gd](../../godot/scripts/chapter_guide.gd) 在实际页面上提供可关闭的小提示：母港、编队、舰库/详情、军需、征募、仓库、资源海域、天梯、活动、邮件共十站。页面其余部分仍可操作，不需要购物、抽卡或领取附件才能继续；可跳过整段，在章节目录随时重看。

## 文件与接口

- [chapter_story_data.gd](../../godot/scripts/chapter_story_data.gd)：只读章节数据。
- [chapter_progression.gd](../../godot/scripts/chapter_progression.gd)：阅读、选择、导览、关卡准备及独立幂等结算。
- [progression.gd](../../godot/scripts/progression.gd)：`chapter_status()`、`chapter_move(action,value)`、`chapter_prepare(stage)`；既有 `begin_mode`/`finish_mode` 接入 `story_chapter`。
- [chapter_presentation.gd](../../godot/scripts/chapter_presentation.gd)：全屏演出、回看、目录、关卡简报。
- [chapter_dialogue_player.gd](../../godot/scripts/chapter_dialogue_player.gd)：打字、自动阅读与键盘推进，不执行战斗裁决。
- [main.gd](../../godot/scripts/main.gd)：根代理接入 `chapter` 路由、全屏切换、继续第一章和各页导览。

## 实际检查

[chapter_integration_test.gd](../../godot/tests/chapter_integration_test.gd) 的 **96/96** 客户端闭环通过，见 [integration-receipt.json](../../artifacts/godot/chapter-one/integration-receipt.json)。使用临时账号与真实原生进程，没有改 HP、伪造胜利或直接写入章节解锁。验证实际入口按钮、失败后重试、任务不可跳过、战斗中的搜索/撤离按钮、受击中断后重试、关核保存恢复、真实奖励及指挥官经验、重复幂等、完整结尾、历史/序章/个人舰队独立。

固定种子 6109 的实际记录：脱困 tick 812，档案 tick 728，首领 tick 462；随后真实重打脱困 tick 812 没有重复首通奖励。首领路线需要绕开岛岸取得射线，验收使用 `(8000,1200)` 合法航点；没有把直线撞岸失败改成自动胜利。原生/WASM 对照与海怪机制回归由原核代理单独记录，本文件不冒称本测试覆盖了它们。

表现检查使用 [chapter_presentation_test.gd](../../godot/tests/chapter_presentation_test.gd)，最新真实窗口 **135/135** 通过，覆盖全部 16 节点、可编辑场景与资源、轻颤和阅读节奏、减少动态、两个选择边界、三张真实表情选择、十站导览、导览收起/展开和无交易推进。记录见 [presentation-receipt.json](../../artifacts/godot/chapter-one/presentation-receipt.json)。20 张图位于 `artifacts/godot/chapter-one/`，已目视 CG、三人站位、名字/对白/控制按钮、表情、战前简报、导览与邮件操作区。脱困前为风暴清晨甲板，避免尚未返港却站在港口的场景矛盾；导览移到左侧并可收起，邮件附件与母港底栏保持可用。表现截图使用临时节点展示夹具，完成页的计数没有伪写成三次胜利；实际三关推进与奖励见上方独立真实战果记录。

## 保留边界

- 本章使用固定章节种子与目标保证可教学、可重演；自由搜打撤的随机地图另属原核模式。
- 初期对白与 CG 有叙事压缩，不把每个镜头中的道具虚构成玩家仓库到账物品。
- 不强制征募或付费；没有实现支付、线上 PvP 或服务端账户。
- 原始 DOCX、PDF、历史数据与旧序章没有被覆盖。
