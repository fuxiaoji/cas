# 二、三章与角色／敌情演出交付

2026-11-12。二章《无名者的航线》、三章《门后的潮声》已接入真实章节目录、关卡航线、演出、原核战斗和账户结算。每章14节点、3场实际作战。新章承接第一章的失忆、憎恶例外与上层担保，从流民淡水航线进入拜AI教的旧维护网络；第三章取得阶段性证据，保留身份和灾变原因的悬念。

## 玩家入口与内容

母港 → 剧情 → 章封面 → 航线节点。第二章在第一章结尾后解锁，第三章在第二章结尾后解锁；未完成实战不能通过跳过对白跨过。返回章节、上层目录与母港沿现有导航层级运行。

每章新增3张独立环境CG、1张准确身份的多人CG；弗莱彻、德雷顿、旧金山、潮痕各有6种表情，包括实际闭眼帧和说话帧。打字期间驱动说话，定时短眨眼与轻微呼吸。舞台保持实例，只有场景改变才交叉淡出，剧情不逐句整页重闪。

七种怪物保留严格90°俯视原始图，通过六姿态、短跨帧混合和局部网格尾肢变形连接游动、蓄力、打击、受伤与确认死亡。敌情卡可展开公开HP、最大速度、伤害、射程、冷却、装甲和弱点；详情展开时收起重复教学卡，关闭后恢复。失去公开接触会清空详情，失联不播放死亡。

巡航速度输入改为滑块，旁边显示当前值与该舰最大值；实际 `speed` 命令保持原数值。

## 可编辑资源

- [完整章节设计](../design/chapters-two-three.md)：节点顺序、叙事、奖励、演出边界。
- [完整图片台账](../art/generated-chapters-two-three.json)：12张原图的完整提示词、准确角色参考、原路径和SHA256；项目内复制与原图逐字节相同。
- `godot/data/chapter-two.json`、`chapter-three.json`：节点、选择、前置、实战和奖励。
- `godot/data/chapter-scenes/c2-*.tres`、`c3-*.tres`：28个原生可编辑场景覆写资源，控制地点、背景、角色、表情、对白和音乐；战斗条件和奖励不允许由演出覆写。
- `godot/assets/story/expressions-v2/*-faces.tres`：24个原生Atlas表情区域，不改源图像素。
- `godot/scenes/chapter_stage.tscn`、`godot/scenes/ui/story_catalog.tscn`、`story_route.tscn`、`monster_intel.tscn`：布局可在Godot场景编辑器修改。
- `chapter_stage.gd` 的 `preview_scene` 可输入第一至三章节点ID进行编辑器预览。

## 真实验收

最终联调核心：`9c2557bb6cc9736069e53209112aaf15f157a62d3064fc8d8dd8cf3314c6692e`，运行文件为 `target/tide-v1-runtime/<SHA>/cas-sim.exe`。

| 验收 | 结果 | 证据 |
| --- | --- | --- |
| GPU新档完整三章、9场原核战斗、六新关详情／奖励／恢复 | 1392/1392，46张实际窗口截图 | `artifacts/godot/chapters-two-three/receipt.json` |
| 28个场景资源与24表情、场景打包保存重载 | 124/124 | `artifacts/godot/chapters-two-three/editable-receipt.json` |
| 七怪动作、实际原核读招／受伤／确认死亡、五程序场景各双种子 | 200/200，39张截图 | `artifacts/godot/expedition-presentation/receipt.json` |
| 六新关原生／WASM实际胜利和精确保存重放 | 6/6 | `artifacts/chapter-two-three-core/receipt.json` |

上述三轮Godot日志均为0 ERROR、0 SCRIPT ERROR：`artifacts/chapter-review-final.txt`、`chapter-editable-review.txt`、`chapter-enemy-motion-review.txt`。GPU为实际RTX5070 OpenGL窗口，不是仅解析场景或伪造战果。

GPU玩家指令流胜利时刻：第一章68／65／109秒，第二章58／69／36秒，第三章58／69／216秒。全程实际选择舰艇、滑块设速、指针绘制／提交航线、炮击／鱼雷授权、搜索、集结撤离；只推进原核时间，不直接写胜利状态。六新关的终局快照与命令流分别在 `artifacts/godot/chapters-two-three/<stage>-terminal.json`。

覆盖章节锁、过早领奖拒绝、原核真实胜利要求、首次奖励仅一次、重复结算不再加钱、不写历史星数、六次账户重载、两次实际关进程再恢复、终局命令重放精确一致；第二章护航关五舰生还。档案受击中断后重新开始真实搜索，未把点一次搜索视为已经取得档案。

建议目视截图：`c2-rations-actors.png`、`c2-lifeline-cg.png`、`c3-choice-cg.png`、`c3-breaker-warning.png`、`c3-breaker-enemy-detail.png`、`exercise-enemy-detail.png`，均在 `artifacts/godot/chapters-two-three/`。

## 规则与表现边界

新章使用独立 `chapter-02-v1`／`chapter-03-v1`，显式新建 `cas-adventure-v1` 与 `open-intel-v1`。按用户追加授权，第一章新出航也显式公开敌情；旧保存缺省行为不升级。真实历史观察没有这些公开数据时不能打开完整敌情，已用独立真实历史想定验证。

历史原始舰表、想定阵位、环境和PDF未修改；剧情CG只用于演出，战场海、水波、云和陆地仍为种子驱动的程序环境。四名角色为六帧表情与轻程序动作，七怪为六姿态加局部网格变形；本批不等同于完整骨骼动画或逐句配音。谜底按章节节奏保留，尚未写出的后续故事未登记为完成。
