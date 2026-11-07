# 奥古斯塔皇后湾海战：时期舰卡与规则闭合载体

选本剧本作为水面规则闭合的载体：它是《旭日》五版里中型、夜间、双方都编有巡洋舰与驱逐舰的水面战，同时覆盖雷达、照明弹／探照灯、烟雾、鱼雷再装填、巡洋舰副炮与多指挥仪、多纵队、先验舰损和岸角方位裁决。

## 原页与编制

- 剧本页：《Rising Sun》五版 PDF 90（印刷 90）。
- 时间与地点：1943-11-02 0227，布干维尔岛托罗基纳角西北。
- 环境：夜，100% 低云、零星阵雨，能见度 10%，风 225°/2 节，海况 1。
- 美方：TF 39，4 艘克利夫兰级轻巡（Montpelier、Cleveland、Columbia、Denver）＋ Desdiv 45/46 八艘弗莱彻级驱逐舰，三列梯队。
- 日方：Crudiv 5 两艘妙高级重巡（Myoko、Haguro）＋ Desron 3（Sendai、Shigure、Samidare、Shiratsuyu）＋ Desron 10（Agano、Naganami、Hatsukaze、Wakatsuki），三列。
- 特例：两架 F1M2 水上侦察机开局在空中；Haguro 在 0130 被轰炸后最高 30 节；可选运输驱逐舰不纳入基础编成。
- 胜利条件：见 `data/campaign/empress-augusta-bay.json` 的 `objectives`。美方要求击沉三艘日舰并把日方重巡压在海角外侧；日方要求重创三艘美巡并让重巡切入美巡与海角之间。

## 舰卡来源

| 舰型 | 舰表 | 日期舰表（Form 10） |
| --- | --- | --- |
| Cleveland | 《American Fleets》PDF 18（A-15） | Montpelier 259、Cleveland 255、Columbia 257、Denver 258 |
| Fletcher | 《American Fleets》PDF 20（A-17） | Ausburne 270、Claxton 272、Converse 273、Dyson 276、Foote 278、Spence 284、Stanly 285、Thatcher 287 |
| Myoko (1940) | 《The Emperor's Fleet》PDF 15、18（A-12、A-15） | Myoko 61、Haguro 62–63 |
| Sendai (May-Jun 43) | 《The Emperor's Fleet》PDF 21–22（A-18、A-19） | Sendai 74 |
| Agano (Jun-Jul 43) | 《The Emperor's Fleet》PDF 20（A-17） | Agano 68 |
| Kagero | 《The Emperor's Fleet》PDF 28（A-9） | Hatsukaze 102 |
| Shiratsuyu | 《The Emperor's Fleet》PDF 28（A-22） | Shigure 133、Samidare 131、Shiratsuyu 135 |
| Yugumo | 《The Emperor's Fleet》PDF 27（A-24） | Naganami 91 |
| Akizuki | 《The Emperor's Fleet》PDF 27（A-53） | Wakatsuki 85 |

## 炮雷表与新增型号

已复用其他时期包的型号：Mk16 6in/47、Mk30 5in/38、三年式 12.7cm/50、三年式 No.2 20cm/50、三年式 14cm/50、Type 93 鱼雷、Mk15 鱼雷、八年式 No.2 鱼雷。

本批从《The Emperor's Fleet》C-1（PDF 97）与 C-2（PDF 98）新录四个对海炮行：

- Type 89 12.7cm/40（妙高副炮）
- 41st Yr Type 15cm/50（Agano 主炮）
- Type 98 8cm/60（Agano 副炮）
- Type 98 10cm/65（秋月主炮）

四行的近／中／远／极远射程、侧带穿深、甲板穿深和表伤均按 C-1/C-2 原值抄录。

## 未决冲突（不填默认值）

1. **Cleveland DP**：A-15 级表给 CL 55–65 为 336、CL 66+ 为 396；四舰 Form 10 印的是 396 行。舰卡按级表取 336，Form 10 差额保留。
2. **妙高 DP/航速**：级表印 428/35 节；1943 年 6–7 月 Form 10 印 471/33 节。舰卡取 Form 10（471/33），级表差额保留。
3. **Sendai 鱼雷**：1943 年 5–6 月 Form 10 仍印八年式 No.2（每座两枚再装填、15 分钟），不是 Type 93；改装备注没有换雷。
4. **Sendai 副炮**：三年式 8cm/40 尚未登记为对海型号，舰卡 `secondary_gun.model` 留空。
5. **Agano DP**：级表 346，Form 10 302；舰卡取 Form 10。
6. **侦察机**：两架 F1M2 的搜索与照明弹属于航空范围，当前不执行。
7. **多纵队与岸角**：每方三列的初始队形、托罗基纳角方位裁决尚未接入引擎。

## RTS 闭环还需要的规则项

- 多指挥仪与局地控制（后向 ±30° 局地 −2、观察尺寸降一级）
- 巡洋舰副炮对海（独立火力组、独立指挥仪）
- 过度集中（多舰同靶的弹着混淆修正）
- 舰桥／舵／武器（鱼雷管）临界的效果
- 雷达接触引导照明弹
- 鱼雷再装填（日方 6 分钟／Sendai 15 分钟）
- AI 夜间照明、探照灯与烟幕
- 先验舰损（Haguro 最高 30 节）
- 多纵队部署与岸角方位

这些项按“数据 → 内核规则 → 剧本运行时 → 验收”的顺序推进；每项都以真实对局和边界测试验收，不以函数存在代替。

## 初始阵位核对（《旭日》PDF 90，印 90）

运行时按原页方位/距离计算，不再用近似坐标。坐标系为 80,000 × 55,000 码的海图（原 24,000 × 14,000 演习场容纳不下 18–19 海里接敌距离，已扩图而不是压缩阵位）。托罗基纳角取 `(72,000, 12,000)`，海图上以小型岸角多边形表示，评级几何使用同一点。

| 原页 | 运行时 | 状态 |
| --- | --- | --- |
| 美方领舰在托罗基纳角 292° 方向 19 海里 | `CAPE + bearing(292°) × 19 nmi` | 按原值 |
| 右列（Ausburne、Dyson、Stanly、Claxton）领舰在 Montpelier 右舷艏 5,000 码 | `Montpelier = Ausburne − bearing(30°) × 5,000 yd` | 按原值（右舷艏取艏向 +45°） |
| 中央列 Montpelier、Cleveland、Columbia、Denver，航向 345°、20 节 | 同序列、同航向/航速 | 按原值 |
| 左列领舰 Spence 在 Denver 左舷艉 3,000 码 | `Spence = Denver + bearing(210°) × 3,000 yd` | 按原值（左舷艉取艏向 −135°） |
| 日方 Myoko 在 Montpelier 295° 方向 18 海里 | `Myoko = Montpelier + bearing(295°) × 18 nmi` | 按原值 |
| 日方中央列 Myoko、Haguro，航向 140°、30 节 | 同序列、同航向/航速 | 按原值 |
| 日方左列 10,000 码外：Sendai、Shigure、Samidare、Shiratsuyu | `Sendai = Myoko + bearing(50°) × 10,000 yd` | 按原值（140° 的左侧为 50°） |
| 日方右列 5,500 码外：Agano、Naganami、Hatsukaze、Wakatsuki | `Agano = Myoko + bearing(230°) × 5,500 yd` | 按原值（140° 的右侧为 230°） |
| 列内舰间距 | 500 码 | **原页未印**；采用 CAS 战役统一默认值，登记待实舰/队形证据替换 |
| 两架 F1M2 侦察机 | 未实现 | 显式登记，属航空范围，不在水面规则内静默删除 |

## 已知平衡偏差

按原页阵位重跑后，美方雷达＋四艘轻巡的持续火力仍会在日方进入鱼雷射程前击沉其大部分舰艇；日方 AI 的九三式长雷攻击尚未形成原页中的战果（历史为美方损失 Foote、日方损失 Sendai）。这是 AI 战术/火力节奏问题，已登记为下一轮平衡项；不得通过改原页阵位或删舰来“修”它。
