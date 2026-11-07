# 塔萨法隆格：原页核验与时期录入来源登记

《Rising Sun》五版 PDF 75–76（印刷页 74–75）为唯一剧本来源，正文与海图各一页。本文登记逐条出处、与原页冲突或印刷不清处、待裁决项，以及 roadmap 第 3 节「05 塔萨法隆格 优先做」条目的逐条核对。数据落在 `data/campaign/period/tassafaronga-1942.json`（source_only_not_runtime_ready），由 `scripts/check-campaign.py` 的 `verify_tassafaronga()` 校验。

## 来源与页码

| 文档 | PDF 页 | 印刷页 | 用途 |
| --- | --- | --- | --- |
| 《Rising Sun》五版（`剧本/Rising_Sun_5th_ed_Std_1_Oct_25.pdf`） | 75 | 74 | 正文：态势、环境、双方编制、命令、胜负条件、部署、特则、历史结果 |
| 同上 | 76 | 75 | 海图：三处 Resupply Point、双方队形锚点、0–5 海里比例尺、经纬网 |
| 同上 | 74、77 | 73、76 | 边界核验：PDF 74 为前剧本（第一次瓜岛）结尾，PDF 77 起为科曼多尔群岛，塔萨法隆格恰占两页 |
| 《American Fleets》 | 15–22 | A-12…A-19 | 新奥尔良（A-13）、北安普敦/彭萨科拉（A-14）、布鲁克林一组（A-16）、弗莱彻/布里斯托尔（A-17）、西姆斯/本哈姆/格里德利/巴克利（A-18）、马汉（A-19）舰级行 |
| 《American Fleets》 | 107–109 | C-1…C-3 | Annex C1&C2 舰炮表：5in/38（C-2）、Mk16 6in/47（C-2）、Mk12,15 8in/55（C-2）、Mk9,10,11,13,14 8in/55（C-3） |
| 《American Fleets》 | 119 | F-1 | Annex F 鱼雷表：Mk14、Mk15（TNT／Torpex 两行） |
| 《The Emperor's Fleet》 | 27–29 | A-24…A-26 | 夕云（A-24）、阳炎（A-25）、白露（A-25–A-26）舰级行 |
| 《The Emperor's Fleet》 | 97 | C-1 | Annex C1 舰炮表：3rd Yr Type 12.7cm/50 |
| 《The Emperor's Fleet》 | 105 | F-1 | Annex F 鱼雷表：Type 93 Model 1 Mod 1/2 |
| 旧版 Rising Sun Form 10s | 90、92、94、105、106、109、128、138、241、243、250、252、267、277、298、320、330、331、332 | 同页码 | 19 艘具名舰的逐舰时期佐证（仅作对照，不作权威） |

页码核法：PDF 从 1 起与书上印刷页同时登记；表列、舰卡全部目视核页（`artifacts/tassafaronga-pages/` 下为本轮渲染的核页截图，属可重建临时产物）。

## 19 艘具名舰逐舰核名结论

原页（PDF 75 / 印 74）实际名单：美方 11 艘（5 巡洋舰 + 6 驱逐舰）＋日方 8 艘驱逐舰 = 19 艘具名舰。**原页没有任何具名驳船／小艇单位**——补给桶（40–50 桶一串、每舰 200–240 桶）是货物不是单位；roadmap 描述中「美方 5 艘＋6 艘驳船/运输相关单位」的 19 艘构成与原页不符，原页美方不止 5 艘，日方运输单位是两支各 3／2 艘的驱逐舰运输队。以下逐舰均为原页出现过的舰名，无一凭记忆补入：

| 舰名（原页拼写） | 原页编制 | 舰级（原页原文） | Form 10（适用期） | 阵位／部署 |
| --- | --- | --- | --- | --- |
| Minneapolis | TG 67.2.2（旗舰） | New Orleans class CA | PDF 241（Jul-42） | 巡洋舰纵队第 1；全队航向 320°、20 节；23:06 SG 接触 284°、13 海里 |
| New Orleans | TG 67.2.2 | New Orleans class CA | PDF 243（Jan-42） | 巡洋舰纵队第 2 |
| Pensacola | TG 67.2.2 | Pensacola class CA | PDF 252（1942） | 巡洋舰纵队第 3 |
| Honolulu | TG 67.2.3 | Brooklyn 1st group CL | PDF 267（Sep-Oct 42） | 巡洋舰纵队第 4 |
| Northampton | TG 67.2.3 | Northampton class CA | PDF 250（Jul-42） | 巡洋舰纵队第 5（末舰，尾部两驱在其左舷舰艉方向） |
| Fletcher | TG 67.2.4 | Fletcher class DD | PDF 277（Oct-42） | 前卫四驱第 1（领衔舰，明舰旗舰左舰艏 30°、4,000 码） |
| Perkins | TG 67.2.4 | Mahan class DD | PDF 332（Jan-Feb 42） | 前卫第 2（按图注顺序） |
| Maury | TG 67.2.4 | Gridley class DD | PDF 320（Dec-41） | 前卫第 3（按图注顺序） |
| Drayton | TG 67.2.4 | Mahan class DD | PDF 330（Mar-May 42） | 前卫第 4（按图注顺序） |
| Lamson | TG 67.2.4 | Mahan class DD | PDF 331（Dec-41） | 尾随两驱第 1（Northampton 左舷舰艉方向 2,000 码） |
| Lardner | TG 67.2.4 | Bristol class DD | PDF 298（Mar-42） | 尾随两驱第 2 |
| Naganami | 第二水雷战队旗舰（RADM Raizo Tanaka），Screening Unit | Yugumo class DD | PDF 92（Jun-42） | 日军队列前端（推断，见冲突项）；田中赖三所在舰；保有完整备用雷 |
| Makinami | Desron 2, Screening Unit | Yugumo class DD | PDF 90（Aug-42） | 原页注明「(Makinami carries supply drums)」；无备用雷 |
| Takanami | Desron 2, Screening Unit（picket） | Yugumo class DD | PDF 94（Aug-42） | 长波左舰艏 30°、4,000 码瞭望位；保有完整备用雷 |
| Oyashio | Desron 2, Transport Unit 1 | Kagero class DD | PDF 109（Dec-41） | 运输一队；载桶，无备用雷 |
| Kuroshio | Desron 2, Transport Unit 1 | Kagero class DD | PDF 106（Dec-41） | 运输一队；载桶，无备用雷 |
| Kagero | Desron 2, Transport Unit 1 | Kagero class DD | PDF 105（Apr-May 42） | 运输一队；载桶，无备用雷；已按 A-25 附注完成 4–5 月反潜改装 |
| Kawakaze | Desron 2, Transport Unit 2 | Shiratsuyu class DD | PDF 128（Dec-41） | 运输二队；载桶，无备用雷 |
| Suzukaze | Desron 2, Transport Unit 2 | Shiratsuyu class DD | PDF 138（Dec-41） | 运输二队（图注列尾）；载桶，无备用雷 |

注：
- 原页与已核 annex 均未印具名舰舷号（annex 只印区间，如 Bristol「DD 453-464, 483-497…」；Form 10 表头只印舰名与舰级），录入不凭记忆补舷号。
- 原页日方只按「Desron 2: Screening Unit / Transport Unit 1 / Transport Unit 2」组织，未印第 X 驱逐队番号细分。
- Form 10 索引页自身有三处页码错误（321 实为 Bagley、107 实为 Maikaze、110 实为 Tanikaze），已逐页目视改正：Maury=320、Kuroshio=106、Oyashio=109；Kawakaze 127 与 Suzukaze 137 是 1943 年配置，本关用 Dec-41 的 128、138。

## 三处补给圈与五串规则（原页位置）

均在 PDF 75（印 74）「Special Rules」段，逐句对应：

| 规则 | 原文位置 | 登记值 |
| --- | --- | --- |
| 每串 20 分 | Special Rules 第 1 句 | points_per_string_dropped_within_radius=20 |
| 补给圈半径 | 同句「within 1.5 nmi of a Resupply Point (see map)」 | resupply_radius_nmi=1.5 |
| 三处补给点 | 海图（PDF 76 / 印 75）瓜岛西北岸三枚「Resupply Point」圆点，位于 Cape Esperance 与 Tassafaronga Point 之间 | resupply_point_count=3（坐标未印，待数字化） |
| 每点同时三舰 | 「Each Resupply Point can only handle recovering three destroyer loads at one time.」 | simultaneous_capacity_destroyer_loads=3 |
| 每舰五串、每战术窗一串 | 「Each ship can carry five drum strings, but only one may be offloaded per turn.」 | strings_per_ship=5；offload_rate=每 Tactical Turn 一串 |
| 满卸五窗 | 「Five turns will be needed to completely offload the supplies on each destroyer.」 | turns_to_fully_offload=5 |
| 卸货限速 | 「During the unloading evolution, a destroyer's maximum speed is 2 knots – bare steerageway.」 | unloading_max_speed_knots=2 |
| 未卸串扣分 | 「Any drum strings that are not successfully offloaded will have their points deducted from the Japanese player's point total at the end of the scenario.」 | 未卸串按 20 分/串扣 |
| 战果分 | 「The Japanese player also receives one point for every damage point inflicted on a US ship.」 | 1 分/DP |
| 备雷特例 | 「Due to the weight of the drum strings, all Japanese destroyers with supplies cannot carry their torpedo reloads. Thus, only Naganami and Takanami have their full torpedo complement.」 | 6 艘载桶舰 reserve=0；长波、高波各 8 枚备用雷（4×2 座） |
| 运输命令 | Japanese Orders 段 | 指定点卸桶、天亮前退出岸基航空兵范围 |

派生算术（非原页印出）：6 载桶舰 × 5 串 × 20 分 = 600 供给分上限，另加战果分。

## 500／250 双「Decisive」印刷冲突的处理

原页（PDF 75 / 印 74）Japanese Victory Conditions 依次印：

```
Decisive: 500 or more total points.
Decisive: 250 or more total points.
```

两档都印作 Decisive。处理方式（roadmap 要求「保留原记录，注明此处将按 RTS 分级采用哪档」）：
- `victory_conditions_as_printed.japanese_tiers` 原样保留两条 Decisive 及其原文；
- `objective_reading_for_rts_fixture` 登记 RTS 采用分级：500=决定、250=战术，并注明该分级是 RTS 裁定而非原文；玩家可见内容必须标明采用的分级；
- 500、250 两条门槛（以及美方 120／240）在检查脚本中分别断言，均可独立测试。
美方两档的印刷笔误（「has being crippled」、行尾多余「)」）按原样保留并注记，读法登记为「至多一艘重巡受损 ≥50%（决定）／至多一艘重巡被击沉（战术）」；条件只约束四艘 CA（Honolulu 是 CL）。

## Annex C 炮弹／鱼雷行核对结果

本关涉及的新核行（本轮目视逐列核出）：

| 行 | 出处 | 近/中/远/极（千码） | Belt | Deck | DP |
| --- | --- | --- | --- | --- | --- |
| Mk9,10,11,13,14 8in/55 APC | AF C-3（PDF 109） | 0-7 / 7.1-16 / 16.1-25.5 / 25.6-31.9 | 33/22/15/12 | -/-/5/10 | 23/18/15/13 |
| 同上 SpCOM | AF C-3 | 同上 | 15/10/7/5 | -/-/2/4 | 24/19/17/15 |
| 同上 Com | AF C-3 | 同上 | 10/7/5/4 | -/-/2/4 | 23/18/16/14 |
| 同上 HC | AF C-3 | 同上 | 3/2/2/1 | -/-/1/2 | 26/22/19/17 |
| Mk12,15 8in/55 APC、SpCOM（仅登记备查，无本关舰装备） | AF C-2（PDF 108） | 0-6.6 / 6.7-15 / 15.1-24 / 24.1-30 | APC 30/20/14/11；SpCOM 13/9/6/5 | APC -/-/5/9；SpCOM -/-/2/4 | APC 24/19/16/14；SpCOM 24/19/17/15 |
| Mk16 6in/47 APC、HC（Honolulu） | AF C-2 | APC 0-6.2…20.9-26；HC 0-5.8…19.3-24 | APC 15/9/7/5；HC 1/1/1/0 | APC -/-/2/4；HC -/-/0/1 | APC 18/14/12/11；HC 24/20/18/16 |
| Mk15 TNT | AF F-1（PDF 119） | 6.0 千码 @45 节（单一速度档） | — | — | 87 |
| Mk15 Torpex（1943 年起，本关不可用） | AF F-1 | 10.0 @34、15.0 @27 | — | — | 99 |
| Type 93 Model 1 Mod 1/2 | EF F-1（PDF 105） | 22/35/43.8 千码 @49/41/37 节 | — | — | 95 |

与仓库已有行对照（「对照已有 Annex C 数据行」）：
- `us_mk30_5in38`（AF C-2，SpCOM 18/14/12/11、COM 22/19/17/15、HE 18/15/14/12）与圣乔治角 v2 包登记值逐列一致；圣乔治角更正的 HE 近/中档 18/15 DP 在原页复核成立。Mahan 的 Mk21 与 Gridley 的 Mk21/Mk24 都落在此行「Mk12, 21, 22, 24, 25, 28, 29, 30, 32, 37, 38 5in/38」内。
- `jp_3rd_yr_127mm50`（EF C-1，COM 16/13/11/10、HE 17/14/13/11）与圣乔治角 v2 登记值逐列一致。
- `jp_type93_m1_mod1_2`（EF F-1，95 DP、22/35/43.8 千码 @49/41/37 节、610 mm、蒸汽）与圣乔治角 v2 登记值一致。
- `us_mk15_tnt` 存在差异：圣乔治角 v2 登记 87 DP 配三档速度（6,000/45、10,000/34、15,000/27，承旧 Form 10）；AF F-1 原页把三档中的后两档印在 Torpex 行（99 DP、1943 年列装）。本关按 1942-11-30 只登记 TNT 单档 87 DP @45 节/6,000 码，差异列为冲突项 `mk15-tnt-speed-range-pairs`，裁决留给消费者。
- 8 英寸炮归属：A-13 印新奥尔良级标准主炮「2F/A(3)3 Mk12, 15 8in/55」（C-2 行）并注「前三舰用 Mk9 或 Mk14 8in/55」（C-3 行）。Minneapolis、New Orleans 属前三舰，故取 C-3 行；C-2 行一并登记备查。

## 舰级 annex 页核对结果（伤害/航速、乘员、转向）

| 舰级 | 出处 | Dam Pts | 节 | 乘员 | 转向级 | 加减速（0-75%/76-100%/减速） |
| --- | --- | --- | --- | --- | --- | --- |
| New Orleans | AF A-13（PDF 16） | 0/99/199/298/357/397 | 32/24/16/8/0 | 1042 | B（B/Medium） | 10/5/12 |
| Northampton | AF A-14（PDF 17） | 0/93/185/278/333/370 | 32/24/16/8/0 | 621 | B | 10/5/12 |
| Pensacola | AF A-14 | 0/93/186/279/335/372 | 32/24/16/8/0 | 653 | B | 10/5/12 |
| Brooklyn first group | AF A-16（PDF 19） | 0/97/194/291/349/388 | 32/24/16/8/0 | 1200 | B | 10/5/12 |
| Fletcher | AF A-17（PDF 20） | 0/36/72/108/130/144 | 37/28/18/9/0 | 273 | A（单舵注记） | 12/6/15 |
| Bristol | AF A-17 | 0/30/59/89/106/118 | 37/28/18/9/0 | 208 | C | 12/6/15 |
| Mahan | AF A-19（PDF 22） | 0/28/56/84/101/112 | 36/27/18/9/0 | 172 | D | 12/6/15 |
| Gridley | AF A-18（PDF 21） | 0/29/58/87/104/116 | 38/28/19/10/0 | 158 | C | 12/6/15 |
| Yugumo | EF A-24（PDF 27） | 0/35/70/105/126/140 | 35/26/18/9/0 | 228 | C | 12/6/15 |
| Kagero | EF A-25（PDF 28） | 0/35/69/104/124/138 | 35/26/18/9/0 | 240 | C | 12/6/15 |
| Shiratsuyu | EF A-25–A-26 | 0/31/61/92/110/122 | 34/26/17/8/0 | 180 | C | 12/6/15 |

转向表与加减速表来自五版主规则印页 3-2（PDF 23）：B 级直进 300 码/2 节、急舵 200 码/3 节；B 级加减速 10/5/12 节、C 与 D/E 12/6/15。弗莱彻「Due to single rudder, turns as Size A warship」沿用圣乔治角包结论。北安普敦级 A-14 印「In Svc: 1929」，按原样登记不作裁定。

## 与 roadmap 要求逐条对应的核对表

| roadmap 条目 | 结论 | 出处 |
| --- | --- | --- |
| 《旭日》PDF 75–76，19 艘具名舰 | 已核：恰为两页，19 艘=美方 11+日方 8；无具名驳船单位 | PDF 75-76（印 74-75） |
| 三处补给圈半径 1.5 海里 | 已核：Special Rules「within 1.5 nmi of a Resupply Point」＋海图三枚圆点 | PDF 75（印 74）＋PDF 76（印 75） |
| 每处至多三舰 | 已核：「can only handle recovering three destroyer loads at one time」 | PDF 75 |
| 2 节或以下 | 已核：「maximum speed is 2 knots – bare steerageway」 | PDF 75 |
| 每舰每战术窗一串共五串 | 已核：「one drum string every Tactical Turn」「Each ship can carry five drum strings」「Five turns」 | PDF 75 |
| 未卸货串按原页扣分 | 已核：「will have their points deducted from the Japanese player's point total」 | PDF 75 |
| 原文把 500／250 两档都印作决定胜利 | 已核并保留；RTS 采用 500=决定、250=战术，用户可见内容须标明采用分级；两条门槛已单测 | PDF 75；`verify_tassafaronga()` |
| 补北安普敦级 | 已录：`northampton_1942` 全行＋8in/55 C-3 炮行 | AF A-14＋C-3 |
| 布里斯托尔级（Bristol-class） | 已录：`bristol_1942` 全行；Lardner 原页印「Bristol class DD」。「原页美方实际是 Northampton + 4 艘驱逐舰」的说法与原页不符：原页美方为 5 巡洋舰＋6 驱逐舰 | PDF 75；AF A-17 |
| 当期日舰 | 已录：`yugumo_1942`、`kagero_1942_base`、`kagero_1942_asw_refit`、`shiratsuyu_1942`（含 Kagero 4–5 月反潜改装与 Oyashio/Kuroshio 未改装的分别） | EF A-24/A-25/A-26 |
| 8 英寸炮伤害按五版 Annex C-3 核定 | 已核：Mk9,10,11,13,14 8in/55 四弹种行逐列登记，出处 AF C-3（PDF 109）；另登记 C-2 的 Mk12,15 行备查 | AF C-3/C-2 |
| 备用雷两艘各 8 枚 | 已核：「only Naganami and Takanami have their full torpedo complement」＝各 4×2 座 8 枚；载桶六舰 reserve=0 | PDF 75；EF A-24/A-25/A-26 |
| 原页未定座位或时长不得用默认值填补 | 已执行：纵队逐舰座位、补给点坐标、每串墙钟时长、8in/6in 弹种选择、Mk15 TNT 速度档、马汉级 Late 42 中炮拆除日期、Gridley 炮座文本均留空或标 unresolved | `conflicts`、`pending_items` |

## 与原页冲突或印刷不清处

1. 日方胜负两档都印「Decisive」（500、250）——保留原文，RTS 分级另注（见上）。
2. 美方 Decisive「only one US heavy cruiser has being crippled」语法错误、Tactical 行尾多余「)」——按原样保留。
3. 战术态势「a small wart on Cape Esperance」——「wart」为原页笔误（疑为 warship），按原样登记；SG 接触时间高倍渲染下印作 23:06（低倍渲染易误读为 2300）。原页该句无脚注；页面底部的「Xi Wang (Order #30858642)」是 PDF 购买水印，不是脚注。
4. AF F-1 的 Mk15 行：TNT 单档（87 DP @45 节/6,000 码）与 Torpex（99 DP，1943）分开印；圣乔治角 v2 把三档速度配在 87 DP 上。两处都登记，未擅自合并。
5. AF A-13 新奥尔良级：标准行印 Mk12,15 8in/55，附注前三舰用 Mk9/14——两行都登记，按附注取 C-3 行。
6. AF A-14 北安普敦级「In Svc: 1929」——按印登记。
7. Form 10 索引页三处页码错误（Maury/Kuroshio/Oyashio 各给出两个页码，其一是他舰）——已目视改正并登记。
8. 主档案 `data/campaign/tassafaronga.json`（档案层，非本轮交付物）有几处与原页的偏差，本轮不改该文件，仅在此记录：US 编制把 TG 67.2.2 与 67.2.3 合写成「TG67.2.2–3」；SG 接触时间记 2300（原页 2306）；「未卸货的分数从日方总分扣除」一句写成独立特则而非引用原文。
9. 原页美阵列句印作「The trailing destroyers are off Northampton's port quarter」——核页过程记录：该词在低倍渲染下曾误读，高倍渲染确认印作 trailing。

## 待裁决项（清单）

1. 三处补给点坐标未印，海图数字化前 1.5 海里规则无法运行。
2. 日军队列逐舰座位未印（只印图注清单）；「长波端为前卫」是从高波哨位推出的读法，需裁决或明确标为 RTS 改编。
3. 美方前卫/巡洋舰/尾随队逐舰座位未印，按图注清单登记，同上需裁决。
4. Mk15 TNT 在 1942-11-30 可用哪几档速度（F-1 单档 vs Form 10 三档佐证）。
5. 马汉级 Late 42 中炮拆除无确切日期，11 月 30 日炮座数不定。
6. Gridley「F/A(1)4」炮座文本未展开，gun_mounts 留空。
7. 美日各舰弹种实配（APC/SpCOM/Com/HC 等）未印，留给运行方。
8. 马汉（w/4 两行）与格里德利（w/4 四座）备用雷的逐座分摊未印，留空。
9. 檀香山 SG（「Late '42」无日期）、明尼阿波利斯战前 SC/Mk3、马汉级搜索雷达型号均未定。
10. 每串卸载无墙钟时长（只按战术窗计），秒数属 RTS 改编，不回填。

## 检查脚本

`scripts/check-campaign.py` 新增 `verify_tassafaronga()`（复用既有 `load`/`Counter`/结构断言惯例），校验：JSON 结构与 crosswalk 引用合法性、19 艘具名舰及双方构成、Form 10 页映射、三处补给圈与五串规则、500/250 与 120/240 门槛、8in/55 四弹种行、6in/47 与 5in/38、127mm/50 对照、Mk15 TNT/Torpex 与 Type 93 行、11 个舰级伤害/航速/乘员/转向行、备用雷特例、Kagero 反潜改装分别、unresolved／recorded 冲突集合。运行结果：

```
$ python -I scripts/check-campaign.py
CAS campaign: 16 scenarios, 32 legacy stages, 11 catalogued and 0 staged source-only imports; 210 legacy identities, 10 dated Cape St. George, 8 source-only Horaniu destroyers and 19 source-only Tassafaronga named ships; 0 local PDF hashes; pinned legacy baseline: not requested

$ python -I scripts/check-campaign.py --ibs-worktree 'F:/Codex/worktrees/android-mobile/铁底湾'
… pinned legacy baseline: checked
```

「0 local PDF hashes」为 E:/CAS-rules-next 工作区内无 `CAS带翻译` 原件目录所致（与既有行为一致，主仓运行时会核 11 份 PDF 哈希）。
