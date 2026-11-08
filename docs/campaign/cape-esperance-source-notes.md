# 埃斯佩兰斯角：原页核验与时期录入来源登记

《Rising Sun》五版 PDF 65（印刷页 64）为唯一剧本来源，正文一页、无海图（Setup 明写 Open ocean，部署全部是相对位置）。本文登记逐条出处、与原页冲突或印刷不清处、待裁决项，以及 roadmap 第 3 节「02、08、11」条目中埃斯佩兰斯角部分的逐条核对。数据落在 `data/campaign/period/cape-esperance-1942.json`（source_only_not_runtime_ready），由新建的 `scripts/check-cape-esperance.py` 校验（不改 `check-campaign.py`）。

对照表登记起点为 [source-crosswalk.md](source-crosswalk.md) 第 02 行（IBS-S-01，PDF 65／印 64）与已登记记录 [../../data/campaign/cape-esperance.json](../../data/campaign/cape-esperance.json)。本轮以实际 PDF 复核：登记页码正确；原记录的开局时刻、环境、双方名单、部署、三种开局、胜负条件与特则逐项对上，未发现差异；原记录缺项与措辞差异见下文冲突清单。

## 来源与页码

| 文档 | PDF 页 | 印刷页 | 用途 |
| --- | --- | --- | --- |
| 《Rising Sun》五版（`剧本/Rising_Sun_5th_ed_Std_1_Oct_25.pdf`） | 65 | 64 | 正文全部：态势、环境、双方编制、命令、胜负条件、三种开局、特则、历史结果 |
| 同上 | 64、66 | 63、65 | 边界核验：PDF 64 起《Missed Opportunity》、PDF 66 起《Guadalcanal Air Battle》，本剧本恰占一页 |
| 《Command at Sea》五版主规则 | 13–14 | 2-1、2-2 | 炮座射界（沿用已核时期包口径的引用页） |
| 同上 | 23 | 3-2 | 机动等级与加减速（同上） |
| 同上 | 47 | 5-10 | §5.4／5.4.1 目视发现：Clear Night 随月相修正，能见度由剧本给定 |
| 同上 | 49 | 5-12 | §5.4.3 雨幕（6 千码圆、3D6／2D6／4D6）、§5.4.4 夜间照明（10–5% 能见度照明减半、2% 照明弹失效） |
| 同上 | 51 | 5-14 | Visibility Modifiers：夜间炮口闪光升表、cued search −20%、10% 能见度开火 −20% |
| 《American Fleets》 | 16 | A-13 | 新奥尔良级舰级行＋旧金山舰注（Mar 42 雷达） |
| 《American Fleets》 | 17 | A-14 | 彭萨科拉级舰级行＋盐湖城舰注（11 Oct 42 受损、11 月起加装 SC） |
| 《American Fleets》 | 19 | A-16 | 布鲁克林一／二组舰级行与雷达注（博伊西、海伦娜） |
| 《American Fleets》 | 108、109、119 | C-2、C-3、F-1 | 5in/38、6in/47、8in/55 两行、Mk15 鱼雷（经塔萨法隆格包交叉引用，本轮复核 8in 两行差异） |
| 《The Emperor's Fleet》 | 17、18 | A-14、A-15 | 青叶（1938）／古鹰（1937）舰级行、损伤航速表（A-15 顶部表为 A-14 右栏古鹰条的接排） |
| 《The Emperor's Fleet》 | 97、98 | C-1、C-2 | 12.7cm/50（C-1）、20cm/50 No.2（C-2）炮表行 |
| 《The Emperor's Fleet》 | 105 | F-1 | Type 93 Model 1 Mod 1/2 鱼雷行（经圣乔治角包交叉引用，舰卡同值复核） |
| 旧版 Rising Sun Form 10s | 46、47、53、156、159、245、253、254、263、265、266、292、293、295、296、297、299 | 同页码 | 14 艘具名舰的逐舰时期佐证（仅作对照，不作权威） |

页码核法：PDF 从 1 起与书上印刷页同时登记；表列、舰卡全部用 Read 目视核页。Form 10 索引页未再发现塔萨法隆格轮记录的那类错页；本轮 17 页均按页眉舰名＋页脚期号逐页确认。

## 14 艘具名舰逐舰核名结论

原页实际名单：美方 9 艘（4 巡洋舰 + Desron 12 五驱逐）＋日方 5 艘（3 重巡 + 2 驱逐）= 14 艘具名舰，另有 1 架 SOC-3 在空。以下均为原页出现过的舰名，无一凭记忆补入；「旧作八艘日军增援」不在 CAS 原页（见 source-crosswalk 第 02 行登记，本轮复核确认原页无这些舰）：

| 舰名（原页拼写） | 原页编制 | 舰级（原页原文） | Form 10（适用期） | 阵位／部署（原页） |
| --- | --- | --- | --- | --- |
| San Francisco | Task Force 64（旗舰，RADM Norman Scott） | New Orleans class CA | PDF 245（Mar 42） | 美纵队第 4（领巡）；全队 045°、15 节 |
| Salt Lake City | Task Force 64 | Pensacola class CA | PDF 254（Dec 1941）；253（Nov 42–Mar 43）为战后佐证 | 美纵队第 5 |
| Boise | Task Force 64 | Brooklyn 1st group CL | PDF 265（Jan–Jun 42）；266（Dec 1941）为更早佐证 | 美纵队第 6 |
| Helena | Task Force 64 | Brooklyn 2nd group CL | PDF 263（Dec 41–Jul 42） | 美纵队第 7；其 SG 射程超旗舰（原页 Setup 明写） |
| Farenholt | Desron 12 | Bristol class DD | PDF 296（Apr 1942） | 美纵队第 1（领舰） |
| Duncan | Desron 12 | Bristol class DD | PDF 295（Apr 1942） | 美纵队第 2 |
| Laffey | Desron 12 | Bristol class DD | PDF 297（Mar 1942） | 美纵队第 3 |
| Buchanan | Desron 12 | Bristol class DD | PDF 293（Mar 1942）；292（Nov–Dec 42）为战后佐证 | 美纵队第 8（队尾两驱之首） |
| McCalla | Desron 12 | Bristol class DD | PDF 299（May 1942） | 美纵队第 9（末舰） |
| Aoba | Crudiv 6（旗舰，RADM Aritomo Goto） | Aoba class CA | PDF 46（Dec 1941） | 日纵队第 1（领先舰）；自海伦娜 315°、13.5 海里 |
| Furutaka | Crudiv 6 | Furutaka class CA | PDF 53（Dec 1941） | 日纵队第 2 |
| Kinugasa | Crudiv 6 | Aoba class CA | PDF 47（Dec 1941） | 日纵队第 3（末舰） |
| Fubuki | Desdiv 11(-) | Fubuki class DD | PDF 156（Apr–May 42） | Aoba 左舷正横（距离未印） |
| Hatsuyuki | Desdiv 11(-) | Fubuki class DD | PDF 159（Dec 1941） | Aoba 右舷正横（距离未印） |

注：
- 原页日方编制名「Desdiv 11(-)」带括减号，印为分队的部分兵力；原页与已核 annex 均未印舷号，不凭记忆补。
- 原页日方纵队次序为「Aoba in front, followed by Furutaka and Kinugasa」（Setup），与编制段列举次序（Aoba、Kinugasa、Furutaka）不同；以 Setup 次序登记，两处原文均保留。
- SOC-3 叙事逐句登记在 JSON `aircraft.us`：4 架可用；San Francisco 与 Boise 各放出 1 架；放出两架中 1 架引擎故障陆基备降；舰上余两架中 1 架放飞事故损失、1 架弃置；其余飞机全部在岸。

## 开局时刻与三种开局（原页位置）

全部在 PDF 65（印 64）Setup 叙述内：

| 开局 | 原页时间 | 内容 | 日方探测 |
| --- | --- | --- | --- |
| 标准 | 2324 | 美纵队 045°、15 节；日领先舰（Aoba）自海伦娜 315°、13.5 海里，135°、30 节；Fubuki／Hatsuyuki 分居 Aoba 左／右舷正横 | 未印；特则段保持「枪口火光近距被见前 unaware」 |
| 海伦娜无线电接触 | 2339 | 「six miles away, bearing 285」（原页印 miles，未标海里；见冲突项） | 「the Japanese had not detected the American force」 |
| 海伦娜目视接触 | 2345 | 「bearing 300° at 5000 yards」；Helena 可在 2345 回合计划射击阶段开火，其余美舰须自行（cued visual search 或雷达）探测后才能反应射击 | 「The Japanese had still not detected the Americans.」 |

另有一项部署事件：**2330 美纵队按既定计划转向反航**（「as previously planned, Scott ordered the column to reverse course at 2330」），原页印在叙述里而非表列；2324 开局须处理该事件，运行包须显式决定其执行方式，本包未代选。已登记记录 `cape-esperance.json` 未含此条，本轮补入。

## 可选增援、输送／撤离目标、海岸与海况（roadmap 逐条）

| roadmap 项 | 原页结论 | 位置 |
| --- | --- | --- |
| 可选编成／可选增援 | **原页没有任何可选增援或可选编成条款**。唯一「options」是 Setup 中三种开局位置的选择。旧关（IBS）的八艘日军增援驱逐舰不在 CAS 原页 | PDF 65（64）Setup；source-crosswalk 第 02 行 |
| 不同输送／撤离目标 | **原页没有运输或撤离任务条款**：日方命令只有炮击亨德森机场 90 分钟（30 战术回合）；「reinforcement convoy」仅出现在态势与历史结果叙述，无具名运输船、无卸载规则、无撤离线或撤出边界。历史结果句「The Japanese reinforcement group landed its cargo」一并登记为叙述 | PDF 65（64）Japanese Orders／Tactical Situation／Historical Outcome |
| 岛岸位置 | **原页无海图**：地图类型 open ocean，位置全部相对（自海伦娜的方位距离、Aoba 两舷正横）；未印任何坐标、边界或岸线 | PDF 65（64）Setup |
| 天候／月光／能见度 | 夜间、能见度 10%、月面 1%（sliver）、民暮光 0539、黎明 0600、萨沃岛西北 5–50 海里强降雨带、海况 3；接敌时日方「still immersed in a squall」 | PDF 65（64）Environment／Setup |

## 夜间光学与输送状态（复用口径）

- 五版 §5 口径按已核时期包的引用方式结构化登记：§5.4／5.4.1（PDF 47／印 5-10）、§5.4.3 雨幕与 §5.4.4 夜间照明（PDF 49／印 5-12）、Visibility Modifiers（PDF 51／印 5-14，含 20–74mm 炮闪升两表、75mm+ 升三表、cued search −20%、10% 能见度开火 −20%）。雨幕圆数量、照明器材与炮闪升表在 10% 能见度下的具体交互属运行消费者，本包只登记规则引用页与剧本环境，不代填参数。
- 照明状态：**原页未印任何照明弹／探照灯事件**，登记为「none printed」；Annex I2 探照灯数据未在本轮核验，留在待办。
- 雷达（双方逐舰）：美方 — San Francisco SC-1＋2 Mk3＋2 Mk4（Form 245 Mar 42 与 A-13 舰注一致）；Salt Lake City 无雷达（Form 254 Sensors「None.」；A-14 舰注把 SC 系于战后 11 月–3 月大修；Form 253 的 SC 为 Nov 42–Mar 43 改装期佐证）；Boise SC＋SG＋2 Mk3＋2 Mk4（Form 265 Jan–Jun 42；A-16 组注 Feb 42 有 SC＋Mk3）；Helena SC＋SG＋2 Mk3＋2 Mk4（Form 263；A-16 Feb 42 注 SG；原页 Setup 亦明写 Helena 的 SG）；Desron 12 五舰全部 SC（CXBD）＋Mk4（FD）（各舰 Mar–May 42 舰卡一致，Buchanan 战后 Nov–Dec 42 卡同配置，构成夹逼）。日方 — 三巡两驱全部无雷达（Form 46/47/53/156/159 Sensors「None.」；A-14 注 Aoba 的 Type 21 雷达系 1943 年 8–11 月修理加装）。
- 输送状态：原页唯一载具状态是「日巡洋舰水上机按额定半数搭载」（额定：青叶级 2、古鹰 1，按 annex；古鹰的 Form 10 印 2 架 E7K1，见冲突项）；无运输货物状态可登记。塔萨法隆格包的卸载／载桶机制在本剧本无对应条款，不迁入。

## 双方胜负条件（按原页分别登记）

| 方 | Decisive | Tactical | 原文措辞 |
| --- | --- | --- | --- |
| 日方 | 对同盟海军造成 3:1 damage ratio | 1:1 damage ratio | 印为「damage ratio」 |
| 美方 | 对日方造成 3:1 damage point ratio | 1.5:1 damage ratio | 印为「damage point ratio」 |

原页各自给条件、无互相取消条款，同一场交战双方可同时达标，结果分别保留（与库拉湾／圣乔治角的双方独立判定口径一致）。日方 90 分钟炮击任务是命令不是胜负门槛，原页未把两个比值与炮击完成度挂钩。损伤比的具体度量、零分母与同时达成处理沿用库拉湾待裁决口径，不在本包代定。

## 特则（原页 Special Rules，逐句）

1. 日方在近距见到枪口火光前不知美舰存在；**美方在日方还击前获得一个免费战术回合的开火**。
2. 双方各每战术回合掷一枚 D10，掷出 1 该方停火一战术回合；**每方整场只发生一次**，发生后停掷。
3. 2345 开局的 Helena 计划射击阶段开火权与其余美舰的反应射击条件（见上表）。
4. 日方命令内含 90 分钟 = 30 战术回合的等式；页未印每回合时长。

## 与原页冲突或印刷不清处

| 冲突 ID | 状态 | 内容 |
| --- | --- | --- |
| san-francisco-gun-mark | unresolved | A-13 舰级行「2F/A(3)3 Mk12, 15 8in/55」＋注「First three units had Mk9 or Mk14」（即旧金山应属后四单元用 Mk12/15＝C-2 行）；但旧金山本人 Mar 42 Form 10（PDF 245）印「Fwd (3)/Fwd (3)/Aft (3) Mk9/14 8 in/55」，其 APC 行（33/25、22/19、15/5/16）与 C-3 的射程穿深一致而伤害 +1。两种读法都登记，行选择留给运行消费者，不得拼凑弹种 |
| helena-radio-range-unit | recorded_as_printed | 2339 选项印「six miles」，未标海里／英里；同页部署用海里（13.5 nmi）。已登记记录读作 6 nmi，本包保留原文并注歧义 |
| furutaka-torpedo-reserve | unresolved | A-14 古鹰（1937）印「4 reserve torp/mount for quick reload in 6 minutes」；Dec 1941 舰卡（PDF 53）两座四联各 4 枚、**无 Reload 格**。1942-10-11 是否带备用雷无源可断 |
| furutaka-light-aa-25mm | unresolved | A-14 古鹰（1937）Light AA 印 (2)4 Type 96 25mm＋(2)2 13.2mm（1.2）；Dec 1941 舰卡仅 4×13.2mm（0.2）。25mm 加装日期两源均未印 |
| aoba-floatplane-type-and-count | unresolved | A-14 注「Oct 42: E7K2 Alf floatplanes replaced by E13A1 Jake」只到月，对不上 10 月 11 日；Dec 1941 舰卡印 2×E7K1。古鹰「额定半数」按 annex（1 架）取整还是按舰卡（2 架）折半，无源可断 |
| ijn-cruiser-signature-and-crew | recorded_as_printed | 青叶级两张 Dec 1941 舰卡印乘员 657–680、特征 Medium/Loud；annex 印 625／Medium/Noisy；古鹰舰卡同为 Medium/Loud。以 annex 入档案，差异保留 |
| fubuki-dp-139-vs-106 | recorded_as_printed | 吹雪（Apr–May 42）与初雪（Dec 1941）舰卡均印 139 DP（0/35/70/104/125/139）；Annex A-27 1936 改装行 106 DP。沿用圣乔治角包 fubuki-damage 的处理（annex 行入档） |
| us-form10-gun-values | recorded_as_printed | Boise（265）／Helena（263）舰卡 6in/47 APC 近距（pen 20、dam 22）高于已核 Annex C-2 行（15/18）；美系舰卡伤害普遍比 annex 高 1–2。沿用 fletcher-gun-table 惯例：matched Annex C 行控制，不拼表 |
| old-record-additions | resolved_by_verification | 已登记 `cape-esperance.json` 缺：2330 定时反航、SOC-3 四架叙事、接敌时雨幕浸没、「damage ratio／damage point ratio」措辞差。本轮全部按原文补入时期包；原记录已核数据本身无冲突 |

## 待裁决项清单

1. San Francisco 1942-10-11 主炮行：A-13 舰级读法（Mk12/15）vs 本人 Mar 42 舰卡（Mk9/14）。
2. Furutaka 的备用雷与 25mm 轻防空在 10 月 11 日的配置（annex 1937 块 vs Dec 1941 舰卡）。
3. 青叶级水上机型号（E7K2 vs 只到月的 E13A1 注）与古鹰「半数」取整。
4. 「萨沃岛西北 5–50 海里强降雨」映射到 §5.4.3 雨幕圆的数量与布设（4D6 heavy 档是候选，不是决定）。
5. 逐舰探照灯／星弹照明配置（Annex I2 与舰 annex），照明消费者启用前必须核。
6. 损伤比度量、零分母、双方同时达成的引擎约定（与库拉湾共用）。
7. 运行包采用哪个开局（或三个都提供），及 2330 反航在 2324 开局下的执行方式（脚本事件还是改编）。
8. 双方纵队站距（美军队内间距、Fubuki/Hatsuyuki 正横距离）原页未印，需登记改编距离或显式注记。
9. Desron 12 雷达时点只有 Mar–May 42 与 Nov–Dec 42（Buchanan）两批舰卡夹逼，单舰 10 月 11 日的独立佐证缺乏。
10. 90 分钟炮击的每战术回合实际秒数属引擎改编，不写回本记录。

## 与 roadmap 第 3 节「02、08、11」条目逐条核对

| roadmap 原文要求 | 结论 | 落点 |
| --- | --- | --- |
| 核开局时刻 | 三种开局 2324／2339／2345 全部登记，含 2330 定时反航；「90 分钟＝30 战术回合」按原文登记 | JSON `start.start_options`、`special_rules_as_printed`；本表「开局时刻」节 |
| 可选增援 | 原页无此条款，明确登记「无」；旧关八舰日增援不入 CAS 原页 | JSON `conflicts.old-record-additions` 注、`counts.note`；本表「可选增援」节 |
| 不同输送／撤离目标 | 原页无运输／撤离任务条款；日方任务只有亨德森机场炮击 90 分钟；历史结果句按叙述登记 | JSON `transport_states`、`orders`；本表「输送／撤离」节 |
| 海岸和海况 | 无海图（open ocean）、无岸线目标；环境五项（能见度／月光／暮光／雨带／海况）逐项登记并注页码 | JSON `start.environment`、`start.map_type`；本表「海岸与海况」节 |
| 复用已核时期包 | 四个舰体档案交叉复用：new_orleans_1942／pensacola_1942／brooklyn 一组／bristol（塔萨法隆格包）、brooklyn 二组（库拉湾运行包）、fubuki_1936_refit（圣乔治角包）；青叶级／古鹰级为本轮新核（EF A-14/A-15＋C-2 炮表＋两张 Dec 41 舰卡） | JSON `profiles`（profile_ref 引用）、`weapon_models`（cross_ref） |
| 夜间光学 | §5.4/5.4.1、§5.4.3、§5.4.4、Visibility Modifiers 四处引用页结构化登记；逐舰雷达状态 14 舰全登记（美方 8 舰有源、Salt Lake City 显式无雷达、日方 5 舰无雷达）；照明「none printed」如实登记 | JSON `night_optics_sources`、`named_ships[*].radar_confirmed` |
| 输送状态 | 唯一印出的载具状态是日巡水上机半数搭载；无运输货物、无卸载机制，不迁入塔萨法隆格口径 | JSON `transport_states`、`aircraft.axis` |

## 校验

`python scripts/check-cape-esperance.py`（独立脚本，不改 `check-campaign.py`）检查 JSON 结构、14 艘舰数与双方名单、三种开局与部署数字、登记页码（剧本页、17 页 Form 10、annex 引用页必须在已核集合内）、胜负条件与特则原文、跨包 profile_ref／weapon cross_ref 的存在性，以及新增青叶／古鹰档案的必填字段。本轮实际运行通过（0 failures）。该检查与原页目视校对同属来源证据，不当作双边实战验证。

## 运行时阵位与海图投影（cas-esperance-runtime-v1）

- 海图底图：ArcGIS World_Imagery z10 卫星瓦片（309×232 km 窗口，150.8 m/px），按水域色阈值提取萨沃岛与瓜达卡纳尔西北海岸多边形，投影为 76×50 km 引擎海图坐标。提取对火山海岸欠敏感（萨沃检测尺寸 5.4×6.7 km，实际 10×13 km），已登记；评级与航行使用同一多边形。
- 阵位：美方九舰单列（Farenholt…McCalla，500 码默认间距）位于萨沃东南 12 km，航向 045/15 节；日方 Crudiv 6+Desdiv 11 在青叶自海伦娜 305°/13.5 海里处，航向 135/30 节。
- **登记偏差**：原页印 315°/13.5 海里；卫星投影下萨沃正好压在 315° 连线上，与历史（日方自萨沃东北侧通过）不符。运行时采用 305°/13.5 海里，使 135° 航向从萨沃东北通过——按规范显式登记，不静默移动。
- 双方沿印定航向直航 15 km 后由 AI 接管；美方 SG/SC-2 雷达逐舰安装并开机，日方无水面搜索雷达（Type 21 仅空搜）。
- 评级按原页损伤点比：比值 = 造成损伤 / 承受损伤（首版方向写反，已修正——决定性 3:1、同盟战术 1.5:1、日方战术 1:1）。任务栏目标同步按原页文案。
- 14 艘具名舰已入目录卡池（recruitable；吹雪/初雪原本已可招募，实际新增 11），并从参考仓 fleet-v2 投影绑定全身立绘（14 张 PNG 逐文件 SHA-256 入 ledger，参考仓只读未动）。
- 验收：引擎 79 项、服务端 33 项、parity 19 场（含 empress 与 esperance）、浏览器出航（CAMP-ALLIES-02）真实战斗 1268 次炮击事件并达成决定性评级（凭证 artifacts/client/esperance/browser-receipt.json）。
