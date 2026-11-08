# 萨沃岛海战（IBS-S-10）原页核验与录入记录

分支 `entry-savo`，交付批次 2026-11-07。对应 [roadmap 第 3 节](../implementation-roadmap.md) 「06、09、10」条目中的萨沃岛。数据文件为 [`data/campaign/period/savo-island-1942.json`](../../data/campaign/period/savo-island-1942.json)，校验脚本为 [`scripts/check-savo-island.py`](../../scripts/check-savo-island.py)。本批只做资料核页与录入，不接引擎、不改客户端与服务端；历史关依然 0 个开放出击。

## 1. PDF 与页码登记

| 文件（D:/desktop/cas/CAS带翻译/CAS带翻译/ 下） | 用途 | PDF 页（从 1 起） | 印刷页 |
| --- | --- | --- | --- |
| `剧本/Rising_Sun_5th_ed_Std_1_Oct_25.pdf` | 萨沃岛想定原页 | 52、53、54 | 51、52、53 |
| `船表/American_Fleets_2012_Standard.pdf` | 美舰类级页、Annex C-2/C-3 炮弹行 | 16–18、20–22、26、108、109 | A-13–A-15、A-17–A-19、A-23、C-2、C-3 |
| `船表/The_Emperor_s_Fleet.pdf` | 日舰类级页、Annex C-1/C-2、Annex F-1 | 16–18、22、23、27、97、98、105 | A-13–A-15、A-19、A-20、A-24、C-1、C-2、F-1 |
| `船表/Home_Fleet_2012_Standard.pdf` | 澳/英舰类级页、Annex C-2、F-1 | 9、115、122 | A-5、C-2、F-1 |
| `船表/旧版太平洋 船表Rising_Sun_Form_10s.pdf` | 具名舰 Form 10 佐证（抽查） | 46、47、49、50、52、53、75、80、81、176、240、244、246、248、262 | — |

- 对照登记：[source-crosswalk.md](source-crosswalk.md) 第 10 行登记《Rising Sun》PDF 52–54（印刷 51–53）。实际核页一致：PDF 52 印刷页眉为 51，PDF 53 为整页海图（印刷 52），PDF 54 为 Setup 页（印刷 53）。**无页码差异。**
- 双线关位：铁底湾想定 `IBS-S-10 萨沃岛海战`，同盟/轴心共用同一 CAS 想定 `cas-rs-savo-island`（[crosswalk.json](../../data/campaign/crosswalk.json) scenarios[9]）。
- 文本提取对本批 PDF 无效（扫描图像），全部页面用渲染截图逐页目视核验；表列、海图、Form 10 均以目视为准。

## 2. 原页逐条登记

### 2.1 开局与部署（PDF 52 正文 + PDF 53 海图 + PDF 54 Setup）
- 开局：1942-08-09 00:52，Iron Bottom Sound（Location 行）。
- 同盟巡逻航速 12 节；未进入战斗岗位（Special Rules）；全员 Condition II, modified general quarters。
- 日军：135°/28 节接近 Blue 哨线，纵队巡洋舰间距 1300 码，顺序 Chokai→Aoba→Kako→Kinugasa→Furutaka→Tenryu→Yubari→Yunagi；Chokai 自 Blue 345°/12 kyds；Blue 在其巡逻线 235° 航向段。午夜全员战位航速 28 节，0133「All ships attack」后 30 节（Historical Outcome）。
- 海图（印刷 52，北朝上，159°35'E–160°20'E、09°00'S–09°25'S，0–10 NM）：Blue/Ralph Talbot 巡逻线、北队巡逻箱（顺时针箭头循环）、南队巡逻线、Australia 独立巡逻线、东队巡逻线、X-Ray 与 Yoke 运输区、Henderson Field、烧毁坐沉的 George F. Elliot 标记、日军接近箭头。
- Special Rules：被探测后 D6/3 战术回合（向上取整）不能开火；日军水上机已探测北队、南队与 Yoke 运输队（雷达哨舰、东屏护、X-Ray 不在列）。
- Variations 1/2 与日方备选舰（Tatsuta、Yuzuki、Uzuki）均为可选，不纳入基础编成。

### 2.2 双方逐舰核名（以原页名单为准）
- 同盟 22 艘作战舰 + 26 艘运输/辅助：TG 62.6 哨舰 Blue、Ralph Talbot；南队 Australia、Canberra、Chicago、Bagley、Patterson；北队 Vincennes、Quincy（w/5 SOC-3）、Astoria、Helm、Wilson；TG 62.4 San Juan（旗舰）、Hobart、Monssen、Buchanan、Jarvis；X-Ray 屏护 Hopkins、Trever、Zane、Southard、Hovey、Dewey、Selfridge、Mugford；Yoke 屏护 Henley、Ellet，分遣 Hull；Transdiv A–D 与 E、Transdiv 12 共 23 艘运输/辅助（George F. Elliott 在 X-Ray B 分队与 Yoke 分遣行重复出现，系同一舰）。
- 轴心 8 艘：Chokai（旗舰）、Aoba、Kinugasa、Furutaka、Kako、Tenryu、Yubari、Yunagi；备选 Tatsuta、Yuzuki、Uzuki。
- 中文名全部取自 [zh-labels.json](../../data/campaign/locale/zh-labels.json)（allies/axis 词条），逐舰核对通过；仅 Tatsuta（龙田）未登记词表，已记待办。
- 注意：编制页写「Aoba, Kinugasa (both Aoba class CA), Furutaka, Kako (both Furutaka class CA)」，Setup 纵队顺序为「Aoba, Kako, Kinugasa, Furutaka」，两处均照录。

### 2.3 历史炮弹核对（重点：重巡主炮）
原页（PDF 52–54）**没有**给本关特定炮弹或穿深口径——正文只有历史叙述（Chokai 8 inch 集火 Astoria 等）。因此按 roadmap 口径，重巡主炮逐行用五版舰队书 Annex C 核定：

| 炮 | 弹种行 | 出处 | 核验结论 |
| --- | --- | --- | --- |
| 美 8in/55 Mk9/10/11/13/14（Vincennes、Quincy、Astoria、Chicago） | APC / SpCOM / Com / HC | American Fleets PDF 109（印刷 C-3） | 4 段射距 0-7/7.1-16/16.1-25.5/25.6-31.9 kyds；APC 穿深 33/22/15/12、甲 5/10（长/远），伤害 23/18/15/13；四行逐列目视核过 |
| 日 3rd Yr Type No.2 20cm/50（Chokai、Aoba、Kinugasa、Furutaka、Kako） | APC / HE | Emperor's Fleet PDF 98（印刷 C-2） | APC 穿深 34/23/16/12、甲 5/10，伤害 26/20/17/15；HE 28/23/21/18 |
| 英 8in/50 MkVIII（Australia、Canberra） | APC / SAP / HE | Home Fleet PDF 115（印刷 C-2） | APC 33/22/15/12、甲 5/10，伤害 26/20/17/15 |
| 美 5in/38 Mk12–38（Atlanta 级主炮与各级副炮/驱逐主炮） | SpCOM / COM / HE | American Fleets PDF 108（印刷 C-2） | SpCOM 18/14/12/11（与圣乔治角 v2 复核一致）；COM 22/19/17/15；HE 18/15/14/12 |
| 英 6in/50 MkXXIII（Hobart） | APC / HE | Home Fleet PDF 115 | APC 21/13/9/7、甲 3/6，伤害 20/15/13/11 |
| 日 10th Yr Type 12cm/45（重巡副炮） | COM / HE | Emperor's Fleet PDF 97（印刷 C-1） | COM 15/12/11/10 |
| 日 3rd/11th Yr Type 12cm/45（Yunagi 主炮） | COM / HE | Emperor's Fleet PDF 97 | COM 14/11/10/9 |
| 日 3rd Yr Type 14cm/50（Tenryu、Yubari） | SpCOM | Emperor's Fleet PDF 97 | 17/13/12/10；与 Tenryu Form 10 同行一致 |

鱼雷行（配套雷装引用）：九三 Model 1 Mod 1/2「Long Lance」22/49、35/41、43.8/37 kyds/kts，610mm，490kg，95 DP（EF F-1 PDF 105）；8th Yr No.1/No.2 与 Type 90 同页；英 MkIX 11.0/45、15.0/35，533mm，330kg，84 DP（HF F-1 PDF 122）；美 Mk15 TNT 沿用库拉湾包已核引用（AF F-1 PDF 119，本批未逐列重核，已在 JSON 注明）。

### 2.4 探测和天候（五版 §5 口径）
- 夜间；能见度 10%；100% 云量、云底 2000 米；雷暴带闪电覆盖萨沃岛及周边 3 海里内；海况 3；0611 民用晨光（能见度 20%）、0633 黎明（能见度 50%）。原文整句已在 JSON `environment.verbatim` 照录。
- 目视/照明条件：原页未给双方照明弹与探照灯的规则数据（历史叙述只有日军探照灯照北队、Quincy 弹爆水上机成「marker」等），正式照明值**未核，待裁决**。
- 月光：原页未登记（无月相/月出月没），**待裁决**。
- 探测：日军水上机前置探测北队、南队、Yoke（Special Rules）；同盟在 0052 前对日军无接触（Patterson 0143 才目视）；哨舰雷达状态逐舰按类级 dated 备注登记（见 JSON instances 的 radar_confirmed/radar_note）。
- 原页未定的具体警戒距离、海图剪影航向与队内间距：**待裁决**。

### 2.5 双方历史胜负条件（按原页分别登记，不套对称）
- 日方 Decisive：sink or damage more than 75% five transports（原句无 of，照录；「五艘」基数算法待裁决）。日方 Tactical：2:1 伤害点比。
- 同盟 Decisive：3:1 伤害比且无运输舰受损 25%。同盟 Tactical：1:1 伤害比且无运输舰受损 50%。
- 双方命令（orders）原文整句照录于 JSON `objectives`。历史结局（澳舰沉没、日舰几乎无伤离场）只写入 `setup.historical_outcome_dates` 与实例 `history` 备注字段，不进入胜负判定。

## 3. 冲突与印刷不清处

1. **Henley 级属**：想定页印 `Henley (Gridley class DD)`；American Fleets A-18 级备注把 Henley 列入 Bagley 级（DD 386-393）。想定照录，级属待裁决（实例 profile 暂挂 `us_bagley_dd` 并注明）。
2. **Yunagi 鱼雷**：Kamikaze (1941) 印 `Type 96 torp`，F-1 无此行；候选 6th Yr Type / Type 89 Mod 1 均不启用，待裁决。
3. **Takao In Class**：1939 配置块印 2，1932 配置与备注列四舰；按四舰处理，块值记录在案。
4. **Northampton 配置漂移**：编制块（1929，含雷装、GS III）与备注（Mid-30s/1936 拆雷装、8× 5in/25、GS IV）并存；1942-08 有效值取备注。
5. **George F. Elliott/Elliot**：双 t/单 t 两种拼法指向同一艘受损运输舰（海图 DIW on fire），不重复生成。
6. **Aoba 特速行**：Aoba 级 D&S 附 `S Sp (Aoba) 28/21/14/7/0`，Kinugasa 是否适用未印。
7. **Yubari 轻防空**：类级块印 2× Type 92 7.7mm；1935 备注加 (2)1 Type 93 13.2mm；25mm 系 1943-04 起才加装。
8. **Tatsuta Form 10 页眉**：缩略视读似 `Tatsuya`，疑印误，待放大复核（页码 80）。
9. **Form 10 只作佐证**：具名舰抽查页眉（见 JSON evidence），美英驱逐舰/运输舰 Form 10 未定位，标未核；Kako Form 10 推定 pdf 54 未目视。

## 4. 待裁决项清单

1. 月光相位与月出月没（原页未登记）。
2. 双方照明弹/探照灯正式规则数据（原页只有历史叙述）。
3. 各巡逻线/箱的精确几何与各舰航向、队内间距（海图无数字）。
4. 日军纵队 Tenryu/Yubari/Yunagi 段间距（原页只给巡洋舰 1300 码）。
5. 东巡逻线两艘未具名 DD 的身份（Monssen/Buchanan 系编制推定）。
6. Yunagi 鱼雷型号（Type 96 无 F-1 行）。
7. Henley 级属（Gridley vs Bagley）。
8. 年内改装时点：Dewey/Hull 的「1942: P&S 5in removed」、Monssen 的「not all units」拆炮拆雷、Canberra 的 (1)5 20mm、Aoba 的 Fall 42 水上机换装。
9. 五艘 DMS 与四艘 APD 的 8 月有效武备（A-23 与 APD 条目未逐舰核到）。
10. 日方 Decisive「five transports」的基数与计数算法（参照塔萨法隆格「两档都印决定胜利」的处理，保留原记录，RTS 分级另行标注）。
11. Tatsuta 中文名入词表（zh-labels.json 由后续批次处理，本批不改他文件）。
12. Kako Form 10 页码目视确认。
13. Chicago 的 SC/SG/Mk3/Mk4 具体月份（1942 备注无日期，CXAM 已确认）。

## 5. 与 roadmap 要求的核对表

| roadmap「06、09、10」要求 | 本批结果 |
| --- | --- |
| 核开局时刻 | 0052 1942-08-09（PDF 52 Location 行）✅ |
| 双方具名舰逐舰核名 | 同盟 22 作战舰 + 26 辅助、轴心 8 + 3 备选，全部照录并配中文名；Form 10 抽查 15 页 ✅（驱逐/运输 Form 10 未核，已标注） |
| 阵位、航向、航速、编制与部署（含警戒舰哨位） | Setup 数值 + 海图七条巡逻线/箱 + 运输区全部登记；剪影航向/间距标待裁决 ✅/⚠️ |
| 优先补战列舰与重巡 | 本关无战列舰；六型重巡（New Orleans、Northampton、Kent、Takao、Aoba、Furutaka）类级页逐条目视核过 ✅ |
| 历史炮弹逐条登记 | 重巡主炮 3 国 4 型炮弹行逐列核定并记出处；副炮/轻巡/驱逐炮行 5 型核过；鱼雷 4 行核过 ✅ |
| 探测和天候按五版 §5 逐条登记 | 夜/能见度/云/雷暴/海况/晨光时刻照录；月光与照明未定，标待裁决 ✅/⚠️ |
| 双方历史胜负条件分别登记 | 四条胜利条件 + 双方 orders 原文照录，日方 Decisive 原句保留 ✅ |
| 未核条目标「未核」/「待裁决」 | JSON `conflicts` + `pending_adjudication` 共 7 冲突 + 13 项 ✅ |

## 6. 交付与边界

- 新增文件：`data/campaign/period/savo-island-1942.json`、`docs/campaign/savo-island-source-notes.md`（本文）、`scripts/check-savo-island.py`；未改动 src/、server/、client/、data/rules/ 与其他战役文件。
- 运行校验：`python scripts/check-savo-island.py`（见提交记录中的运行输出）。
- 本批不跑 cargo、uvicorn 或浏览器；历史关不标可玩，`status` 保持 `source_only_not_runtime_ready`，与 [savo-island.json](../../data/campaign/savo-island.json) v1 档案互为引用。

## 7. 运输舰数据补充核页（2026-11-08）

此前 `savo-island-1942.json` 的 `auxiliary_transports.policy` 写“不生成战斗实例”，这是**本批未转录**的状态，不是原书没有数据。复核《American Fleets》PDF 45–50（印刷 A-42–A-47）后确认存在运输/辅助舰卡：

| 页 | 内容 |
| --- | --- |
| PDF 45（A-42） | Arcturus AKA（DP 0/43/86/128/154/171，16 节，5in/38、40mm/20mm，民用 -50% 损伤修正）、Indus AKN 等 |
| PDF 46（A-43） | Patoka AO 等辅助舰 |
| PDF 47（A-44） | McCawley AP（DP 0/78/156/233/280/311，21 节，4×5in/38）、Harry Lee AP 等 |
| PDF 48（A-45） | President Jackson 级 APA、Doyen APA、Windsor APA 等 |
| PDF 49（A-46） | Arthur Middleton APA、Crescent City APA、Heywood/Harris APA 等 |
| PDF 50（A-47） | Wickes APD、Clemson DMS 等 |

因此运输舰可以按舰级卡转录为可受损/可击沉实例；`Neville`、`Zellin`、`Colhoun`、`Gregory`、`McKean` 等 Yoke 小舰需按对应 APD/DMS/DE 舰级页补核。运输舰的民用 -50% 损伤修正、单轴工程临界双倍掉速和载员/登陆艇字段按上表页录入，不用默认值代替。
