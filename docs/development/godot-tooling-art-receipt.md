# Godot 工具和美术迁移记录

日期：2026-11-11。本批只改开发工具、素材副本、导入器与素材台账；原始 PDF、参考项目、历史舰卡和裁决数值均未修改。

## Godot 和 MCP

用户给出的 `D:\downloads\Godot_v4.7.2-stable_win64.exe` 是目录。实际控制台程序是该目录中的 `Godot_v4.7.2-stable_win64_console.exe`，实测 `--headless --version` 返回 `4.7.2.stable.official.ed1daf0bf`。

Godot MCP 来源：[Coding-Solo/godot-mcp](https://github.com/Coding-Solo/godot-mcp)，固定提交 `1209744fad78f3998f98c7394fd0f6ef50da5281`，MIT。既有下载位于 `tools/godot-mcp`，运行副本在 `tools/godot-mcp-runtime`。本批执行锁文件安装与 TypeScript 构建成功，配置到用户 Codex 的 `godot` MCP，命令指向本地 `tools/godot-mcp-runtime/build/index.js` 并设置实际 `GODOT_PATH`。

`node tools/verify-godot-mcp.mjs` 通过真实 stdio transport 完成 initialize、列出 14 个工具并调用 `get_godot_version`，返回上述真实版本。证据为 `artifacts/godot/mcp-receipt.json`。`package.json` 自报版本 0.1.1，服务握手自报 0.1.0，均保留上游原值。新 MCP 配置在新会话加载；本轮验证直接使用 SDK 连接实际服务器，不宣称工具已动态加入当前工具列表。配置依据为 [Codex MCP 官方文档](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)。

## GitHub 设计和游戏技能

使用系统技能安装器从固定 GitHub 提交下载到 `C:\Users\fwj\.codex\skills`；原有 `frontend-design` 未覆盖。安装结果和绝对位置见 `tools/skills/installation-ledger.json`。新技能在下一轮自动可用。

| 来源 | 固定提交 | 本次安装 | 许可 |
| --- | --- | --- | --- |
| anthropics/skills | `2c5958ecac7cee2b583967a2c4981d0f4a75c579` | github-frontend-design | Apache-2.0 |
| gamedev-skills/awesome-gamedev-agent-skills | `dcf3bbbb83f365632402c086bf595048aa24aaa8` | game-ui-ux、game-feel、procedural-gen、godot-ui-control、godot-gdscript | Apache-2.0 |
| saschb2b/skills | `31a6a1364b73ff24f388f9e35c6e3ccd9baa7d89` | game-design | MIT |

已补齐各安装目录的 LICENSE，以及 gamedev 技能的 NOTICE。`github-frontend-design` 的元数据 name 改为同名，避免与原有技能重名；正文未改。

## UI 参考与可执行约束

阅读 [明日方舟官网](https://ak.hypergryph.com/)、[碧蓝航线官网](https://azurlane.yo-star.com/) 与两款游戏的发行方 App Store 页面（[明日方舟](https://apps.apple.com/us/app/arknights/id1464872022)、[碧蓝航线](https://apps.apple.com/us/app/azur-lane/id1411126549)）。另外通过图片搜索查看编队和大厅实际画面：明日方舟的 [7-16 编队截图](https://www.biubiu001.com/mrfz/42489.html)，碧蓝航线的 [编队截图](https://game.xiaomi.com/viewpoint/1127866428_1604657313151_16) 和 [主界面截图](https://forum.gamer.com.tw/C.php?bsn=32550&snA=15048)。后者是第三方发布的游戏截图，只作视觉观察；不据此声称发行方拥有某套固定布局，也未复制其 UI 图像进入游戏。

本项目采用的设计判断：大厅以角色和军港场景为视觉中心，常用入口聚集边缘；编队把舰位、选择状态和出航行动分开，立绘承担识别，不堆同权重的信息卡；抽卡界面突出一名角色和明确的概率/保底信息。操作层用 Godot Control 与容器布局，返回、焦点、钱数变化与禁用理由须可见，避免让装饰掩盖游戏状态。具体 UI 实现与窗口验收由主代理记录，本文件不提前宣称验收通过。

## 立绘和参考 SD 小人

`python scripts/import-godot-art.py` 和 `--verify` 真跑通过：210 个稳定身份、202 个可战身份、210 张 exact identity 立绘，全部副本 SHA-256 对原台账一致；没有同级代舰。神话/纸面舰的收藏状态仍遵循原目录。所有图片均为本地开发与测试范围，发布许可未确认的资产不得由本记录推断可公开分发。

用户提供的 [小人资源站说明](https://ww-rm.top/azurlane_char/) 与 [索引](https://ww-rm.top/azurlane_char/index.json) 本轮已可访问。来源格式实际是 Spine `.skel`、`.atlas` 和纹理页，不是可直接当作完整角色的纹理图。下载器对现有 210 舰中文名逐项做严格相等匹配，102 身份命中 99 个原始模型（同名时期身份仍各保留单独台账）；所有 99 个模型下载、102 张静态透明 PNG 渲染成功，没有把碎片纹理直接冒充小人。

准备工具位于 `tools/spine-reference/`。Spine 3.8 WebGL runtime 固定到 `8b4844bd4b193ba9e54487ed397a777993cbad56`，仅在本地资产准备工具中运行，不加入 Godot 游戏运行包。运行时自带 Spine Runtimes License，保留 `SPINE-LICENSE`；不将其误标为 MIT 或 Apache。输出使用 `stand` 优先的实际骨骼动画帧，透明 PNG，512×512；小人在图中的大小只是显示投影，不改变战斗内核的一条舰长线。人物外形目视检查了弗莱彻、火奴鲁鲁、阳炎、亲潮样本，WebGL 渲染消除了早期 Canvas 三角网格接缝。102 张图逐张检测了尺寸、透明通道和非空轮廓，全部通过，证据 `artifacts/godot/art-receipt.json`。

重要边界：网站同舰名角色与本项目现有立绘可能拥有不同发色、服装和舰装。这 102 张明确标记为 `reference_spine_projection`，属于参考 SD 投影，不宣称为“对应 CAS 立绘新生成的小人”。目前符合“按现有 CAS 立绘生成并审查”要求的小人仍为 0/210，逐身份 blocker 登记在 `godot/assets/characters/ledger.json` 的 `pending_chibis` 中；另外 108 身份连可用参考 SD 都没有，保留立绘投影/原舰影回退。

首张通过 imagegen 得到的弗莱彻小人被用户否定风格，已从默认投影撤下，原图保留在 `godot/assets/characters/rejected/ibs-u-usn-fletcher-generated.png`，sidecar 标记 `rejected_style`，不计已完成。

默认投影读取 `godot/data/ships.json` 的逐舰 `chibi` 路径，`projection_status` 分辨来源；切换回原舰影由客户端实现。完整原始文件来源、各文件 SHA-256、渲染动画、身份与图片 SHA-256 保存在逐舰 sidecar、`tools/spine-reference/downloads.json`、`renders.json` 与 Godot 总台账。没有下载或分发站点全部模型。

可复验命令：`python tools/spine-reference/download.py`、`node tools/spine-reference/render.mjs --refresh`、`python scripts/import-godot-art.py`、`python scripts/import-godot-art.py --verify`。刷新仅覆盖来源状态为 reference_spine_render 的副本，保留已登记生成稿；用户否定稿单独保留。

本轮 npm 下载缓存与小人渲染预览清单、已被 WebGL 替代的 Canvas 准备运行时已移入 `artifacts/godot/tool-cache-20261111/` 可恢复归档，清出工具工作目录。此前自动审批拒绝了删除这些过程文件的命令，只返回 `blocked by policy`；未重试删除，采用保留副本的归档方式完成整理。保留锁文件、可重建脚本、来源文件、最终 PNG、sidecar 和实际 MCP 运行目录，避免清理破坏已注册的 MCP。

## 后续风格校准 v2

主代理参照网站实际 SD 样图重新调用内置 imagegen，输出弗莱彻 v2，保留 CAS 立绘的金色短发、青色眼睛和围巾、海军蓝金边服饰与白帽，而不照搬网站同舰名的红发眼镜角色。主代理与本代理均已目视对照；大头占约六成、短肢、明确平涂线稿更接近用户指定的比例方向。候选为 `godot/assets/characters/chibis-generated/ibs-u-usn-fletcher.png`，sidecar 状态 `generated_v2_candidate`，原始图 1254×1254 RGBA，透明/非空检测通过，证据 `artifacts/godot/generated-v2-receipt.json`。

按主代理要求，此 CAS 身份候选在本地默认投影中优先于网站参考版；`ships.json` 的 `chibi` 指向 v2，`chibi_reference` 保留网站版作为对照，`chibi_generated` 指明生成稿。没有把候选等同用户验收：`chibi_user_style_accepted=false`，正式方向稿、动画与用户风格验收仍在 blockers。统计为 1 个 v2 候选、0 个已验收生成稿、102 个网站参考 SD；网站参考与候选分别保留台账和哈希。原始拒稿继续保存在 rejected 目录，不恢复为默认。

## 原创 SD 首发候选批

在逐张查看各自 CAS 立绘、Fletcher v2 和网站实际 SD 后，使用内置 imagegen 分别生成 Perkins、Maury、Kagero，再补齐 Honolulu、Drayton，连同已登记 Fletcher v2 共 6 张。没有调用 CLI、API 或下载网站同名角色冒充原创。统一约束为约两头身、头部高占约 55–60%、短手短腿、平涂清晰描边、低细节和紧凑舰装。每次生成的完整提示词保存在相应 sidecar，汇总输入为 `tools/first-wave-generated-art.json` 与 `tools/initial-fleet-generated-art.json`；`tools/register-generated-art.py` 仅登记已存在的工具输出，不调用生成服务。

| 身份 | 本项目立绘保留的主要特征 | 默认候选路径 |
| --- | --- | --- |
| IBS-U-USN-FLETCHER | 金色短发、青色眼睛与围巾、白色船舵帽、藏蓝金边服 | `godot/assets/characters/chibis-generated/ibs-u-usn-fletcher.png` |
| IBS-U-USN-PERKINS | 黑色短发、双银发夹、圆眼镜、藏蓝银边制服、望远镜 | `godot/assets/characters/chibis-generated/ibs-u-usn-perkins.png` |
| IBS-U-USN-MAURY | 橙棕马尾、头顶护目镜、橙色夹克、奶油裙、怀表 | `godot/assets/characters/chibis-generated/ibs-u-usn-maury.png` |
| IBS-U-USN-DRAYTON | 薰衣草色长发、象牙白大蝴蝶结、淡紫裙、浅色小布袋 | `godot/assets/characters/chibis-generated/ibs-u-usn-drayton.png` |
| IBS-U-USN-HONOLULU | 棕发、花饰米白宽檐帽、珊瑚粉裙、青色蝴蝶结、小花罐 | `godot/assets/characters/chibis-generated/ibs-u-usn-honolulu.png` |
| IBS-U-IJN-KAGERO | 栗红长辫、红色发饰、红披肩、黑裙、提灯与纸笺 | `godot/assets/characters/chibis-generated/ibs-u-ijn-kagero.png` |

6 张图片均通过透明通道、非空内容、源立绘 SHA 与逐图 SHA 校验，注册和导入 `--verify` 通过。证据为 `artifacts/godot/generated-first-wave-receipt.json`。`tools/preview-generated-art.mjs` 将原始生成图放在 225px 展示和实际 80px 的深海/浅色两种背景中检查，截图为 `artifacts/godot/chibi-first-wave-review.png`；本代理已目视确认六舰主要发色、饰物、服饰与短肢形态在 80px 下仍可区分，没有方形底色或剪裁缺脚。

首批 5 艘初始同盟舰现均优先显示其 CAS 对应原创候选。Kagero 默认使用栗红长辫红披肩候选，网站金发兔耳版仅留在独立 reference 字段，不再代替最终身份外观。所有 6 张仍标 `generated_v2_candidate`，用户验收数为 0；只制作了单一正面三分之四静态姿态，没有冒充完整角色动画或多方向素材。其余 204 个身份尚未生成 CAS 对应候选；用户风格验收、方向稿与动画的待办继续按身份保留。

## 舰长核心线独立审计

本节只提供现状和接线建议，未修改 UI、观测结构或裁决代码。源码与数据追踪证据为 `artifacts/godot/length-source-audit.json`、`length-registry-audit.json`。

- 可用的现有数据字段是 `ShipDef.length_m`（`src/model.rs:162`，单位米，缺省 0），本席观测处已经持有 `d = self.data.ships[s.def]`，因此应由内核导出真实正值 `lengthM`，缺失时导出空值/缺失状态；不要让客户端按人物图尺寸、舰种或固定 120 米推断。
- `stage0.json` 有 13 个显式舰长行；period、merged 与 prologue-runtime 中均没有显式舰长。追踪 ranked 202 个注册身份的真实选卡优先级后，47 个继承可用正值、155 个缺失。初始弗莱彻、帕金斯、莫里、德雷顿、火奴鲁鲁等缺失，高波继承夕云级 119 米。不能把“有 length_m 字段”误写为“202 张均有真实舰长”。
- 当前 `sea_map.gd` 的核心线硬写 120 米，并用 `width` 比例算线长；实际 `project()` 使用宽高两个比例的较小值，两者在部分画幅不一致。`maxf(5)` 还会把低缩放下的核心线放大。应把舰中心加减世界朝向向量乘半舰长所得的两个端点统一调用 `project()`，用该结果画真实长度线；最小尺寸选择圈作为独立交互标记保留。
- 内核 `P::bearing(0)=(0,+1)`，当前海图 `project()` 的世界 Y 直接向屏幕下方递增，但舰艏绘制用 `(sin,-cos)`，南北方向标记与内核运动方向不一致。建议在 project/unproject 成对翻转 Y，所有舰长端点、鱼雷、航路和地形继续使用同一投影函数。
- 敌接触 `Contact` 只有观测到的位置、朝向、速度、可选名称/舰种，没有舰长与稳定角色身份。不能利用内部 `ship` 字段给未识别接触灌入敌方真舰长；应仅在已识别时输出已知舰长，否则显示明确未知接触符号。
- 全库 `length_m` 的现有数值使用处是 `movement.clearance`，它对缺值/短舰采用 75 米最低避让尺度。这是航路避让尺度，不能冒充实舰舰长；当前也不足以证明内核已有完整的舰长线碰撞模型。若用户要求所有舰体严格按舰长线参与几何裁决，仍须明确内核规格、补齐来源并做原生/WASM 回归。
