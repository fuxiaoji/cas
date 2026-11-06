# 铁底湾 0.6.9 双线战役与 CAS 原页对照

基线为铁底湾 0.6.9 的 Git 快照 `48385c8`。`mobile/content/campaign-scenarios.json` 登记 16 个想定，列出双线第 04–16 关；第 01–03 关沿用该快照的 `docs/mobile-content-audit-20261104.md` 证实的映射。两条线共享 16 个战场，共 32 个旧关卡 ID。序章后的夜战教学 `CAMP-NIGHT-01` 是单独的训练关，独立迁移。

[机器可读对照表](../../data/campaign/crosswalk.json) 保存旧 ID、标题、日期、原始出处、CAS 剧本 ID、页码及本地原文件哈希。下表的 PDF 页码从 1 起算，括号内为书上印刷页。历史对应只表示同一次交战；关卡的编制、布置、时间、任务和特例仍由 CAS 原页决定。

| 双线关位 | 铁底湾想定 | CAS 对应与状态 |
|---|---|---|
| 01 | IBS-S-03 通道行动 | **未定位**。旧作是 1940 年 11 月 28–29 日普利茅斯外海的标枪号行动。已查《Gruppe Nord》《Clear the Coast!》《Mighty Midgets》PDF 3（印刷 2），及《No Sailor But a Fool》PDF 4（印刷 4）。刻耳柏洛斯行动、隧道行动是不同交战。 |
| 02 | IBS-S-01 埃斯佩兰斯角海战 | **同一交战**。《Rising Sun》PDF 65（64）；[原页数据](../../data/campaign/cape-esperance.json)。CAS 基础编制不包含旧作八艘日军增援；CAS 正文给三种开局时间。 |
| 03 | IBS-S-05 圣乔治角海战 | **同一交战**。《Rising Sun》PDF 92（91）；[原页数据](../../data/campaign/cape-st-george.json)。 |
| 04 | IBS-S-02 库拉湾海战 | **同一交战**。《Rising Sun》PDF 85–86（84–85）；[原页数据](../../data/campaign/kula-gulf.json)。 |
| 05 | IBS-S-04 塔萨法隆格海战 | **同一交战**。《Rising Sun》PDF 75–76（74–75）；[原页数据](../../data/campaign/tassafaronga.json)。两档日方门槛在原书都标为决定胜利，250 分档留待核对。 |
| 06 | IBS-S-06 第二次瓜达卡纳尔岛海战 | **同一交战**。《Rising Sun》PDF 73–74（72–73）；[原页数据](../../data/campaign/guadalcanal-ii.json)。CAS 于 11 月 14 日 23:00 开局，战斗跨午夜至旧作标记的 11 月 15 日。 |
| 07 | IBS-S-07 所罗门群岛海战 | **架空／无对应**。查《Bywater’s War》PDF 3、27–37（2、26–36），同类架空背景下没有这场 1928 年 7 月 3 日交战。 |
| 08 | IBS-S-08 科隆班加拉岛海战 | **同一交战**。《Rising Sun》PDF 87（86）；[原页数据](../../data/campaign/kolombangara.json)。 |
| 09 | IBS-S-09 第一次瓜达卡纳尔岛海战 | **同一交战**。《Rising Sun》PDF 71–72（70–71）；[原页数据](../../data/campaign/guadalcanal-i.json)。 |
| 10 | IBS-S-10 萨沃岛海战 | **同一交战**。《Rising Sun》PDF 52–54（51–53）；[原页数据](../../data/campaign/savo-island.json)。 |
| 11 | IBS-S-11 奥古斯塔皇后湾海战 | **同一交战**。《Rising Sun》PDF 91（90）；[原页数据](../../data/campaign/empress-augusta-bay.json)。采用正文的 Empress Augusta Bay 拼写。 |
| 12 | IBS-S-12 布干维尔岛海战（第一战队出击！） | **架空／无对应**。查《Bywater’s War》PDF 3、27–37（2、26–36）；《Rising Sun》目录里的布干维尔想定是 1942 年的空战，另有 1943 年历史交战。 |
| 13 | IBS-S-13 韦拉拉韦拉岛海战 | **同一交战**。《Rising Sun》PDF 90（89）；[原页数据](../../data/campaign/vella-lavella.json)。这是 1943 年 10 月 6 日的撤离战。 |
| 14 | IBS-S-14 霍腊纽海战 | **同一交战**。《Rising Sun》PDF 89（88）；[原页数据](../../data/campaign/horaniu.json)。 |
| 15 | IBS-S-EM-01 第二次马里亚纳海战 | **相关架空想定**。《Steel Typhoon》PDF 46–47（45–46）夜间追击与旧关日期、战区相同，但 CAS 是美舰载机对日舰队，旧作是架空水面舰队对决。 |
| 16 | IBS-S-FM-01 铁底湾的回响·午夜舰队决战 | **旧作原创／无对应**。《Steel Typhoon》PDF 60、62、64、66（59、61、63、65）所载莱特湾不同交战，均不能替代旧作的铁底湾大舰队。 |

“未定位”和“无对应”的范围是当前本地 CAS 剧本集。这五场按旧作固定快照迁入原地图、阵位、编队与任务，参见[旧战场迁移记录](legacy-deployment.md)。CAS 相关但不同的想定保留为参考，不覆盖原关。奖励和剧情继续使用旧关卡 ID；战斗内核读取独立想定 ID 和冻结内容版本。

游戏里的战役航图沿用同盟／轴心和故事、标准、挑战三档选项。每条线显示 16 个原编号；11 场有精确对应的旧关已接上 CAS 开局、编制、双方任务、胜利条件与已录特例。档案读取接口 `campaign_detail` 接受旧关编号、旧想定编号或新想定编号；11 场返回 CAS 的 `record`，其余五场返回旧作迁移的 `legacy`。档案不会启动演习来替代原对局。

圣乔治角是优先候选：开阔水面、十艘驱逐舰，不需海岸图。美方两列 000°/23 节，日方屏护、运输两列 280°/25 节；保留三个相对阵位约束。[1943 年时期包](../../data/campaign/period/cape-st-george-1943.json)有四类舰体、十艘具名舰、五类机动／弹道引用页、炮雷型号和弹种、射界、损伤阶梯和当期设备。改装吹雪级按 Annex A-27 用 106 DP，旧表 139 DP 另存。吹雪级备雷、卯月鱼雷型号、夕雾 Type 22 的具体生效时间以及运输舰开局载员仍未定，不能默认套用。[雷达数据](../rules/radar-source.md)单独区分已确认装具与已实现功能。

圣乔治角的结算函数只接收战局权威方给出的十舰终局事实。日方决定胜利要求全队逃脱且每舰损伤严格低于 25%；美方决定胜利要求击沉至少三艘敌舰且本方各舰损伤至多 25%。两方可同时达到战术胜利，分别保留结果。队内距离、13,000 码的屏护参考舰、逃脱边界、裁决终点和最终并列政策尚未定；源页列的行动总人数也不能当作逐舰初载。函数不提供历史开局。

库拉湾正文与图上的美军最后两舰顺序相反；霍腊纽的相对几何不能精确闭合；韦拉拉韦拉的 Ralph Talbot 在本页印为 Gridley，科隆班加拉页明确记为 Bagley。这些问题连同各关必需的天气、海岸、运输、小艇、侦察机或岸上目标规则，登记在各关记录的待验证项中。

[旧舰身份对照](../../data/campaign/roster-crosswalk.json)收录 210 个稳定 ID：208 个登场于旧战役，22 个收录于收藏目录，其中两舰仅收录于收藏目录。旧舰名、旧作舰类、角色 ID 和登场关系作为迁移证据；战斗用武备、价格和可用性不从旧档导入。圣乔治角十艘已关联具名舰期；[序章五舰原页](../../data/campaign/period/prologue-us-destroyers.json)另列弗莱彻、帕金斯、莫里、德雷顿和拉姆森各自的有日期舰表，不能把不同月份的卡视为同一天的舰队。

复核结构、文件哈希和铁底湾固定快照：`python scripts/check-campaign.py --ibs-worktree "F:/Codex/worktrees/android-mobile/铁底湾"`。未给旧仓参数时仍检查 CAS 记录的完整性。该检查与原页目视校对是来源证据，不能当成双边实战验证。
