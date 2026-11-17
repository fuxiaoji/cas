# -*- coding: utf-8 -*-
"""Build the CAS pitch deck (PPTX)."""

import os
import sys

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.util import Inches, Pt

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pptx_kit import (  # noqa: E402
    BG, BRASS, BRASS_DK, CARD, CARD2, CONTENT_W, CREAM, DANGER, FONT, LINE, M,
    MUTED, NUM, WARNINGS, bullets, footer, kicker, new_slide, rect, rule,
    table, text, title,
)

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "CAS-项目提案-v1.0.pptx")

prs = Presentation()
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)

n = 1

# ============================================================ 01 封面
s = new_slide(prs)
text(s, M, 1.15, 8, 0.26, "C A S　·　P R O J E C T　P R O P O S A L", size=11, color=BRASS, bold=True)
rect(s, M, 1.62, 1.6, 0.014, fill=BRASS)
text(s, M, 1.95, 11.0, 0.85, "炮火之下，", size=52, color=CREAM, bold=True, spacing=1.0)
text(s, M, 2.88, 11.0, 0.85, "我是舰队的眼睛", size=52, color=CREAM, bold=True, spacing=1.0)
text(s, M, 4.02, 11.0, 0.36, "二次元实时海战指挥游戏　·　项目企划书 v1.0", size=16, color=MUTED)
text(s, M, 4.62, 7.6, 1.0,
     "外层是碧蓝航线式的收藏与情感，内层是兵棋级的紧张。\n玩家抽到的每一艘船，都能编进舰队、开进历史。",
     size=13, color=RGBColor(0xC6, 0xCF, 0xD8), spacing=1.5)

for i, (k, v) in enumerate((
    ("对　标", "碧蓝航线 × 明日方舟"),
    ("内　核", "CAS 五版水面规则 · 逐秒改编"),
    ("日　期", "2026 年 11 月　·　立项评审稿"),
)):
    x = M + i * 3.95
    text(s, x, 6.12, 3.6, 0.2, k, size=8.5, color=BRASS, bold=True)
    text(s, x, 6.38, 3.6, 0.26, v, size=11.5, color=CREAM)
rect(s, M, 5.98, CONTENT_W, 0.01, fill=LINE)
rect(s, 11.05, 1.15, 0.008, 4.72, fill=LINE)
_spine = text(s, 10.52, 3.44, 3.30, 0.28,
              "P A C I F I C   T H E A T E R   ·   1 9 4 2 – 1 9 4 3",
              size=9, color=BRASS, align=PP_ALIGN.CENTER)
_spine.rotation = 270

# ============================================================ 02 一页看懂
n += 1
s = new_slide(prs)
kicker(s, "0 0　/　一 页 看 懂")
title(s, "一款让你真的坐在指挥位上的舰娘游戏", size=27)
rule(s)
text(s, M, 1.86, CONTENT_W, 0.6,
     "不是“点一下出击看数值结算”，而是在太平洋的夜战海图上，用逐秒机动的舰队打一场 20–40 分钟的真实海战。",
     size=13, color=RGBColor(0xC6, 0xCF, 0xD8))

stats = [
    ("167", "可征募身份", "立绘 / 档案 / 语音已就位"),
    ("11", "已录入历史想定", "其中 6 关当前可出航"),
    ("10%", "单条成长线封顶", "熟练度命中上限，可验证"),
    ("18", "个月上线周期", "8–12 人团队，6 个节点"),
]
for i, (num, label, note) in enumerate(stats):
    x = M + i * 2.97
    text(s, x, 2.62, 2.6, 0.62, num, size=38, color=BRASS, bold=True, font=NUM, spacing=1.0)
    text(s, x, 3.32, 2.6, 0.24, label, size=11.5, color=CREAM, bold=True)
    text(s, x, 3.60, 2.6, 0.24, note, size=9.5, color=MUTED)

rect(s, M, 4.08, CONTENT_W, 0.01, fill=LINE)
text(s, M, 4.26, 4.0, 0.24, "三条红线（任何版本都不得越过）", size=10, color=BRASS, bold=True)

red = [
    ("不卖数值。", "元词不能换取任何影响裁决的东西：命中、伤害、耐久、装备成品、水手词条。"),
    ("历史模式数值归零。", "战役“标准 / 挑战”与任何复现原页阵位的对局，养成加成一律按 0 计。"),
    ("体力只锁刷取。", "战役首通、剧情、排位、挑战计奖次数内，不消耗燃油。"),
]
for i, (lead, rest) in enumerate(red):
    y = 4.62 + i * 0.62
    text(s, M, y, 0.42, 0.3, f"0{i + 1}", size=12, color=BRASS_DK, bold=True)
    text(s, M + 0.52, y, 1.95, 0.3, lead, size=13, color=CREAM, bold=True)
    text(s, M + 2.52, y, 9.2, 0.34, rest, size=12, color=MUTED)
footer(s, n)

# ============================================================ 03 市场空位
n += 1
s = new_slide(prs)
kicker(s, "0 1　/　产 品 定 位")
title(s, "赛道上有三块完美的产品，各缺一块", size=27)
rule(s)

cols = [
    ("碧蓝航线", "收藏与情感做到极致",
     ["6+6 编队，角色分工一眼可读", "立绘、皮肤、后宅，情感浓度高", "战斗是自动弹幕，玩家不在指挥位"],
     "取：立绘与情感浓度的天花板"),
    ("舰队 Collection", "拟真与历史感扎实",
     ["舰种、装备、改修体系完整", "历史梗与世界观沉淀深", "界面与节奏停留在页游时代，移动端劝退"],
     "取：历史感与世界观沉淀"),
    ("战舰世界", "指挥与拟真到位",
     ["弹道、穿深、损管都是真机制", "对局节奏与操作深度足够", "没有角色、没有叙事、没有情感承接"],
     "取：真机制带来的指挥深度"),
]
for i, (name, sub, items, take) in enumerate(cols):
    x = M + i * 4.04
    rect(s, x, 1.92, 3.72, 2.94, fill=CARD)
    rect(s, x, 1.92, 0.03, 2.94, fill=LINE)
    text(s, x + 0.28, 2.12, 3.2, 0.32, name, size=17, color=CREAM, bold=True)
    text(s, x + 0.28, 2.48, 3.2, 0.24, sub, size=10, color=BRASS)
    bullets(s, x + 0.28, 2.84, 3.16, items, size=10.5, color=RGBColor(0xB9, 0xC4, 0xCF), gap=0.10, spacing=1.3)
    text(s, x + 0.28, 4.38, 3.16, 0.26, take, size=10, color=BRASS)

rect(s, M, 5.18, CONTENT_W, 1.02, fill=RGBColor(0x16, 0x33, 0x47))
rect(s, M, 5.18, 0.05, 1.02, fill=BRASS)
text(s, M + 0.34, 5.36, 11.2, 0.28, "空位：立绘级的美术　+　兵棋级的裁决　+　一个必须动脑的指挥位",
     size=19, color=CREAM, bold=True)
text(s, M + 0.34, 5.74, 11.2, 0.28, "CAS 的内核本来就是为了“让你下命令”而写的——它缺的只是外面那层产品。",
     size=11, color=MUTED)
footer(s, n)

# ============================================================ 04 对标
n += 1
s = new_slide(prs)
kicker(s, "0 1　/　对 标 拆 解")
title(s, "学什么，明确不学什么", size=27)
rule(s)
table(s, M, 1.86, CONTENT_W, [0.13, 0.25, 0.25, 0.37], [
    ["维度", "碧蓝航线", "明日方舟", "CAS 取什么"],
    ["核心循环", "建造 → 编队 → 推图 → 养成", "抽卡 → 编队 → 推图 → 基建", "征募 → 编成 → 出击 → 舰历"],
    ["编队", "前排 / 后排，6+6", "12 人 + 费用 + 阻挡", "历史舰位 + 同阵营换舰 + 点价预算"],
    ["关卡", "海图节点、掉落、三星", "章节 → 关卡 → 三星条件", "战线 → 战区 → 关卡；战后直达下一关"],
    ["养成", "等级 / 技能 / 装备 / 好感", "等级 / 精英化 / 模组", "熟练度 / 等级 / 装备 / 水手（幅度封顶）"],
    ["视觉", "高饱和、角色优先", "低饱和、信息优先", "海军部海图室：深蓝 + 黄铜 + 水彩立绘"],
    ["节奏", "活动驱动，日常轻", "理智驱动，周常重", "周常驱动；燃油只锁刷取，不锁首通"],
], size=10.5, row_h=0.66)
text(s, M, 6.30, CONTENT_W, 0.5,
     "最短的板从来不是战斗内核，也不是立绘，是中间那层产品：把关卡的硬规则，翻译成玩家每一步能做的决定。",
     size=12, color=BRASS)
footer(s, n)

# ============================================================ 05 壁垒
n += 1
s = new_slide(prs)
kicker(s, "0 1　/　差 异 化")
title(s, "三层壁垒：为什么这套东西抄不动", size=27)
rule(s)

walls = [
    ("规则内核", "CAS 五版水面规则 + 逐秒实时改编；舰卡、炮表、鱼雷表逐项可溯源，权威真态不进战斗界面。",
     "工程壁垒"),
    ("内容门槛", "每个历史关都要核页、核舰卡、核阵位、核双方独立胜负条件；单关 4–6 人周，且不许用近似坐标填。",
     "成本壁垒"),
    ("体验稀缺", "同时机动、雷达接触、探照灯与烟幕、编队航速上限——二次元品类里没有对手，且必须内核先支持。",
     "认知壁垒"),
]
for i, (name, desc, tag) in enumerate(walls):
    y = 1.92 + i * 1.42
    rect(s, M, y, CONTENT_W, 1.24, fill=CARD)
    rect(s, M, y, 0.05, 1.24, fill=BRASS)
    text(s, M + 0.34, y + 0.47, 0.6, 0.30, f"0{i + 1}", size=15, color=BRASS_DK, bold=True)
    text(s, M + 1.0, y + 0.45, 2.2, 0.32, name, size=16, color=CREAM, bold=True)
    text(s, M + 3.25, y + 0.16, 6.9, 0.92, desc, size=11, color=MUTED, spacing=1.35, anchor=MSO_ANCHOR.MIDDLE)
    text(s, 11.05, y + 0.47, 1.30, 0.30, tag, size=9.5, color=BRASS, align=PP_ALIGN.RIGHT)
text(s, M, 6.26, CONTENT_W, 0.3,
     "竞品可以抄界面，抄不了这 11 场逐页核验过的海战。", size=12, color=BRASS)
footer(s, n)

# ============================================================ 06 核心循环
n += 1
s = new_slide(prs)
kicker(s, "0 2　/　核 心 循 环")
title(s, "一圈 2–4 天：出征募到下一次征募", size=27)
rule(s)

steps = ["征募", "编成", "出击", "战果", "养成", "再征募"]
xs = []
for i, st in enumerate(steps):
    x = M + i * 2.0
    xs.append(x)
    rect(s, x, 1.95, 1.72, 0.62, fill=CARD2, line=LINE)
    text(s, x, 2.09, 1.72, 0.3, st, size=13, color=CREAM, bold=True, align=PP_ALIGN.CENTER)
    if i < 5:
        text(s, x + 1.74, 2.12, 0.28, 0.28, "›", size=16, color=BRASS, align=PP_ALIGN.CENTER)

text(s, M, 2.78, CONTENT_W, 0.3,
     "每一次循环都必须让玩家在两件事上推进：舰队更强一点，和“我想让谁上场”更清楚一点。",
     size=11.5, color=MUTED)

layers = [
    ("外层（慢）", "3–15 分钟", "母港、征募、编成、剧情、水手洗练、舰历",
     "没有倒计时，没有弹窗打断。它是收藏与情感发生的地方。",
     "例：周三晚上把编队存好，周五下班直接出航。"),
    ("内层（紧）", "20–40 分钟", "实时海战：航路、炮击、雷击、照明、损管",
     "默认自动暂停，随时预令与撤销。误点不能是致命的。",
     "例：一场夜战 28 分钟，中途暂停三次改令。"),
]
for i, (name, dur, what, why, eg) in enumerate(layers):
    x = M + i * 6.06
    rect(s, x, 3.38, 5.72, 1.92, fill=CARD)
    text(s, x + 0.3, 3.56, 2.6, 0.3, name, size=15, color=CREAM, bold=True)
    text(s, x + 3.9, 3.56, 1.5, 0.3, dur, size=12, color=BRASS, align=PP_ALIGN.RIGHT, font=NUM)
    text(s, x + 0.3, 3.98, 5.1, 0.26, what, size=10.5, color=RGBColor(0xB9, 0xC4, 0xCF))
    text(s, x + 0.3, 4.38, 5.1, 0.54, why, size=10.5, color=MUTED, spacing=1.35)
    text(s, x + 0.3, 4.90, 5.1, 0.24, eg, size=9.5, color=BRASS)

text(s, M, 5.62, CONTENT_W, 0.4,
     "两层绝不混：战斗里不弹活动广告，母港里不催你开下一局。", size=13, color=BRASS)
footer(s, n)

# ============================================================ 07 模式全景
n += 1
s = new_slide(prs)
kicker(s, "0 3　/　系 统 总 览")
title(s, "三条玩法线，一条经济", size=27)
rule(s)

lanes = [
    ("PVE", "看完这段历史", [
        "战役 · 故事 / 标准 / 挑战",
        "剧情模式（架空，独立存档）",
        "挑战模式（越级天梯）",
        "三个养成副本",
        "产出：星数、元词碎片、素材",
    ]),
    ("PVP", "证明谁更会打", [
        "普通对战（不计分）",
        "排位 · 3000 / 10000 分档",
        "3v3 / 5v5（远期）",
        "赛季与段位",
        "产出：元词、段位、限定涂装",
    ]),
    ("养成", "让同一艘船更顺手", [
        "熟练度：命中相对 +10%",
        "等级：船体 / 火力 +5%",
        "装备：六槽，每件约 +1%",
        "水手：四组，每套约 +1%",
        "来源：出战、副本、挑战",
    ]),
]
for i, (name, sub, items) in enumerate(lanes):
    x = M + i * 4.04
    rect(s, x, 1.92, 3.72, 3.9, fill=CARD)
    rect(s, x, 1.92, 3.72, 0.05, fill=BRASS)
    text(s, x + 0.28, 2.14, 3.2, 0.3, name, size=16, color=CREAM, bold=True)
    text(s, x + 0.28, 2.50, 3.2, 0.24, sub, size=9.5, color=BRASS)
    for j, it in enumerate(items):
        color = BRASS if j == 4 else RGBColor(0xB9, 0xC4, 0xCF)
        text(s, x + 0.28, 2.94 + j * 0.58, 3.16, 0.5, it, size=10.5, color=color, spacing=1.3)

text(s, M, 6.02, CONTENT_W, 0.6,
     "一条铁律：所有模式共用同一条流程——选关 → 简报 → 编成 → 出航确认 → 战斗 → 战果 → 结算。"
     "模式差异只体现在步骤内容，不体现在步骤顺序。",
     size=11.5, color=MUTED, spacing=1.4)
footer(s, n)

# ============================================================ 08 战役三难度
n += 1
s = new_slide(prs)
kicker(s, "0 4　/　P V E")
title(s, "三个难度不是数值缩放，是三种约束", size=27)
rule(s)
table(s, M, 1.86, CONTENT_W, [0.09, 0.31, 0.28, 0.20, 0.12], [
    ["难度", "编成", "敌人", "目的", "给谁"],
    ["故事", "历史舰位数量不变；每位可换同阵营自有舰，或直接借历史舰", "AI 更协同、更宽容", "看完这段历史", "新玩家"],
    ["标准", "原历史编制，不可增减、不可换舰", "原 AI", "复现原战", "主线玩家"],
    ["挑战", "原历史编制", "同编制但更聪明的 AI + 更苛刻的胜负条件", "打赢同一个局面", "硬核玩家"],
], size=10, row_h=0.80, head_h=0.34)
text(s, M, 4.78, CONTENT_W, 0.3,
     "我们不修改历史舰卡去制造难度，我们修改“你必须怎么打”。挑战难度的胜负条件从原页任务派生：",
     size=11, color=BRASS)
text(s, M, 5.08, CONTENT_W, 0.3,
     "“必须 02:30 前完成卸载”　·　“不得让运输船沉没”　·　“以少于 2 艘驱逐舰的损失脱离”。",
     size=11, color=MUTED)

rect(s, M, 5.58, CONTENT_W, 1.00, fill=CARD2)
rect(s, M, 5.58, 0.05, 1.00, fill=BRASS)
text(s, M + 0.28, 5.72, 2.0, 0.26, "借　舰", size=10, color=BRASS, bold=True)
text(s, M + 1.5, 5.70, 10.1, 0.76,
     "零资源玩家可以把该关的历史舰队整支借出来打：零消耗，不吃养成加成，首通奖励按 70% 结算。"
     "它是“试玩”，不是“替代”——先让她在这片海上出现，再让你想拥有她。",
     size=10.5, color=RGBColor(0xB9, 0xC4, 0xCF), spacing=1.35)
footer(s, n)

# ============================================================ 09 挑战模式
n += 1
s = new_slide(prs)
kicker(s, "0 4　/　挑 战 模 式")
title(s, "3000 分的舰队，去打 4500 分的对手", size=27)
rule(s)

table(s, M, 1.90, 6.1, [0.30, 0.70], [
    ["规则", "设计"],
    ["形式", "自组舰队（点价 A）挑战 AI（点价 B > A）"],
    ["计奖", "每周 5 次；次数外可无限打，只进榜"],
    ["首通", "每档倍率首次通关额外给元词 + 称号"],
    ["AI", "复用现有三种风格：协同 / 炮战 / 雷击"],
    ["排行", "4 周一季；倍率 × 胜率 × 剩余舰数"],
], size=10, row_h=0.56, head_h=0.34)
text(s, M, 5.16, 6.1, 0.9,
     "不需要新海图、不需要新 AI、不需要新战斗内容——只把已有的点价表、AI 风格和阵位复用起来，"
     "就能提供近乎无限的可玩性。", size=10.5, color=MUTED, spacing=1.4)

base = 3000
ladder = [(3450, "×1.15"), (3900, "×1.30"), (4500, "×1.50"), (5250, "×1.75")]
text(s, 7.15, 1.92, 5.2, 0.24, "点价阶梯（玩家固定 3,000 分）", size=9.5, color=BRASS, bold=True)
for i, (pts, mul) in enumerate(ladder):
    y = 2.26 + i * 0.86
    w = pts / 5250 * 4.5
    shade = (0x1E, 0x44, 0x5E) if i < 2 else (0x2A, 0x4A, 0x3C)
    rect(s, 7.15, y, w, 0.52, fill=RGBColor(shade[0], shade[1], shade[2]))
    rect(s, 7.15, y, 0.04, 0.52, fill=BRASS)
    text(s, 7.32, y + 0.12, 2.4, 0.28, f"{pts:,}", size=14, color=CREAM, bold=True, font=NUM)
    text(s, 7.15 + w - 0.72, y + 0.13, 0.66, 0.26, mul, size=11, color=BRASS, bold=True, align=PP_ALIGN.RIGHT)
text(s, 7.15, 5.86, 5.2, 0.24, "同分对打没有意义，越级才有：难度就是玩家自己选的点价差。", size=10, color=MUTED)
footer(s, n)

# ============================================================ 10 PVP
n += 1
s = new_slide(prs)
kicker(s, "0 5　/　P V P")
title(s, "PVP 的平衡器是点价，不是战力评分", size=27)
rule(s)

modes = [
    ("普通对战", "不计分，给少量银币与熟练度", "让玩家敢试新编队，而不是只在排位里赌分"),
    ("排位", "3000 / 10000 两档，8 周一季", "段位只升不降，星级会掉；赛季给元词与涂装"),
    ("3v3 · 5v5", "房间制，1 领舰 + 2–4 分舰队指挥", "快捷指令轮盘与标记，断线 30 秒 AI 接管"),
]
for i, (name, sub, desc) in enumerate(modes):
    x = M + i * 4.04
    rect(s, x, 1.90, 3.72, 1.66, fill=CARD)
    text(s, x + 0.26, 2.06, 3.2, 0.28, name, size=14, color=CREAM, bold=True)
    text(s, x + 0.26, 2.40, 3.2, 0.28, sub, size=9.5, color=BRASS)
    text(s, x + 0.26, 2.72, 3.2, 0.6, desc, size=9.5, color=MUTED, spacing=1.35)

text(s, M, 3.86, 5.0, 0.24, "段位：水兵 → 士官 → 尉官 → 校官 → 将官 → 大将", size=9.5, color=BRASS, bold=True)
tiers = ["水兵", "士官", "尉官", "校官", "将官", "大将"]
for i, t in enumerate(tiers):
    x = M + i * 1.18
    rect(s, x, 4.16, 1.06, 0.5, fill=CARD2, line=LINE)
    text(s, x, 4.28, 1.06, 0.26, t, size=10.5, color=CREAM if i > 2 else MUTED,
         bold=i > 2, align=PP_ALIGN.CENTER)

text(s, M, 4.96, CONTENT_W, 0.24, "公平性由内核保证，不由运营保证", size=9.5, color=BRASS, bold=True)
bullets(s, M, 5.26, CONTENT_W, [
    ("同一档，同样的点价预算。", "平衡工作从“调数值”变成“调点表”，可解释、可公示。"),
    ("双盲观察。", "只返回本席可见的接触；权威真态不进战斗界面，客户端只提交命令。"),
    ("服务端权威时钟与种子。", "命令日志逐条可重演；同对手 24 小时内重复对局不计分。"),
], size=10.5, gap=0.08, spacing=1.25)
footer(s, n)

# ============================================================ 11 经济
n += 1
s = new_slide(prs)
kicker(s, "0 6　/　经 济")
title(s, "四层货币 + 一条配额，每层只做一件事", size=27)
rule(s)
table(s, M, 1.86, CONTENT_W, [0.07, 0.11, 0.22, 0.30, 0.30], [
    ["层", "名称", "作用", "主要来源", "主要消耗"],
    ["高级", "元词", "抽卡与兑换的硬通货", "挑战周次数、排位赛季、剧情首通、充值", "兑征募券、兑换商店、预设位扩容"],
    ["票据", "征募券", "执行一次抽卡", "元词兑换、战役星奖、签到、邮箱", "常驻 / UP 征募"],
    ["软通货", "银币", "养成的手续费", "战役、副本、日常、重复关卡", "修理、补给、强化、洗练"],
    ["凭证", "舰队勋章", "定向换船", "重复征募、三星奖励", "指定舰兑换、AI 战术"],
    ["配额", "燃油", "刷取节奏的阀门", "自然恢复、每日补给、购买", "副本、重复刷关、超次挑战"],
], size=10, row_h=0.60)

rect(s, M, 5.30, 5.72, 1.32, fill=CARD)
text(s, M + 0.26, 5.44, 5.2, 0.26, "燃油只锁刷取", size=11, color=BRASS, bold=True)
text(s, M + 0.26, 5.72, 5.2, 0.80,
     "上限 120，6 分钟 1 点，12 小时回满。首通、剧情、排位、挑战计奖次数内，一点不耗。",
     size=10, color=RGBColor(0xB9, 0xC4, 0xCF), spacing=1.35)
rect(s, 6.82, 5.30, 5.72, 1.32, fill=CARD)
text(s, 7.08, 5.44, 5.2, 0.26, "月抽数目标", size=11, color=BRASS, bold=True)
text(s, 7.08, 5.72, 5.2, 0.80,
     "无氪 22–26 抽 / 月，月卡 42–48 抽 / 月。1 元词 = 1 征募券，玩家心算成本最低。",
     size=10, color=RGBColor(0xB9, 0xC4, 0xCF), spacing=1.35)
footer(s, n)

# ============================================================ 12 养成总览
n += 1
s = new_slide(prs)
kicker(s, "0 7　/　养 成")
title(s, "四条线，全部低幅度、只靠玩", size=27)
rule(s)

lines = [
    ("熟练度", "出战时长 + 有效命中 + 存活", "命中 +10%", 10, "玩得多就打得准；单舰满熟练 8–12 小时"),
    ("等　级", "出战与副本经验，0–60 级", "船体 / 火力 +5%", 5, "航速 +2%，但历史关不生效"),
    ("装　备", "副本图纸 + 银币强化，六槽", "单维约 +1% / 件", 1, "只改裁决前修正，不改穿深射程"),
    ("水　手", "副本契约 + 洗练，四组", "单维约 +1% / 组", 1, "指挥组影响同时机动成功率"),
]
for i, (name, src, effect, ticks, note) in enumerate(lines):
    y = 1.92 + i * 1.12
    text(s, M, y + 0.04, 1.5, 0.28, name, size=14, color=CREAM, bold=True)
    text(s, M, y + 0.38, 2.6, 0.26, src, size=9.5, color=MUTED)
    text(s, 3.55, y + 0.12, 2.2, 0.28, effect, size=12, color=BRASS, bold=True)
    for k in range(10):
        rect(s, 5.95 + k * 0.36, y + 0.13, 0.28, 0.21,
             fill=BRASS if k < ticks else RGBColor(0x1B, 0x33, 0x46))
    text(s, 9.70, y + 0.06, 2.85, 0.5, note, size=9.5, color=MUTED, spacing=1.3)

text(s, M, 6.30, CONTENT_W, 0.28,
     "一格 = 1%。横条表示这条线对“单一”维度最多能贡献多少：熟练度满格，装备与水手各一格。",
     size=9.5, color=MUTED)
rect(s, M, 6.20, CONTENT_W, 0.01, fill=LINE)
text(s, M, 6.62, CONTENT_W, 0.3,
     "四条线封顶后合计：命中 +12%、火力 +6%、船体 +6%、航速 +2%。满养成与零养成的同分对局，胜率差必须 ≤ 55:45。",
     size=10.5, color=BRASS)
footer(s, n)

# ============================================================ 13 熟练度/等级
n += 1
s = new_slide(prs)
kicker(s, "0 7　/　熟 练 度 与 等 级")
title(s, "熟练度决定打不打得中，等级决定扛不扛得住", size=26)
rule(s)

panels = [
    ("熟练度", "0 – 100", [
        ("累积　", "出战时长 + 有效命中 + 存活到结束"),
        ("效果　", "命中率相对 +10%（原值 × 1.10）"),
        ("节奏　", "单舰满熟练 8–12 小时；每天两局约两周"),
        ("蚊子腿", "每 10 点给银币 + 档案，满点给称号 + 涂装"),
    ]),
    ("等　级", "0 – 60", [
        ("经验　", "出战、副本、剧情"),
        ("效果　", "船体 +5% / 火力 +5% / 最大航速 +2%"),
        ("红线　", "航速加成在历史战役（标准 / 挑战）不生效"),
        ("理由　", "航速改接敌几何，快 2% 原页阵位就不再复现"),
    ]),
]
for i, (name, rng, rows) in enumerate(panels):
    x = M + i * 6.06
    rect(s, x, 1.90, 5.72, 3.30, fill=CARD)
    text(s, x + 0.28, 2.06, 2.4, 0.3, name, size=16, color=CREAM, bold=True)
    text(s, x + 4.4, 2.06, 1.05, 0.3, rng, size=13, color=BRASS, align=PP_ALIGN.RIGHT, font=NUM)
    for j, (lead, rest) in enumerate(rows):
        y = 2.56 + j * 0.62
        text(s, x + 0.28, y, 0.78, 0.26, lead, size=9.5, color=BRASS, bold=True)
        text(s, x + 1.10, y, 4.4, 0.5, rest, size=9.5, color=RGBColor(0xB9, 0xC4, 0xCF), spacing=1.3)

rect(s, M, 5.42, CONTENT_W, 1.30, fill=RGBColor(0x2A, 0x22, 0x1E), line=DANGER, line_w=0.9)
text(s, M + 0.30, 5.56, 1.2, 0.26, "陷阱", size=9.5, color=DANGER, bold=True)
text(s, M + 0.30, 5.84, 5.4, 0.72,
     "不能说“命中 +10 个百分点”。\nCAS 远距离基础命中只有个位数，加 10 点等于翻倍。",
     size=10, color=RGBColor(0xD8, 0xC6, 0xB8), spacing=1.35)
text(s, M + 6.10, 5.56, 1.4, 0.26, "红线", size=9.5, color=DANGER, bold=True)
text(s, M + 6.10, 5.84, 5.4, 0.72,
     "航速加成永久不进历史关。\n差一个字，整套平衡与历史保真一起废。",
     size=10, color=RGBColor(0xD8, 0xC6, 0xB8), spacing=1.35)
footer(s, n)

# ============================================================ 14 水手
n += 1
s = new_slide(prs)
kicker(s, "0 7　/　水 手")
title(s, "水手四组：把真实机制做成词条", size=27)
rule(s)

groups = [
    ("舵手组", "转向 · 回转半径 · 编队保持", "最小回转半径 −2~4%", "舵效、容差、转向响应", False),
    ("火炮组", "射击指挥 · 齐射节奏", "首轮修正 −1~2", "散布、炮座转速、装填", False),
    ("损管组", "进水 · 火灾 · 临界损伤", "进水速率 −3~5%", "火灾蔓延、临界修复、堵漏", False),
    ("指挥组", "同时机动成功率 · 命令延迟", "同步机动 +2~4%", "命令延迟、协同加成、航速差容忍", True),
]
for i, (name, mech, main, sub, hot) in enumerate(groups):
    x = M + i * 2.97
    rect(s, x, 1.92, 2.72, 3.44, fill=RGBColor(0x17, 0x33, 0x4A) if hot else CARD,
         line=BRASS if hot else None, line_w=1.1)
    if hot:
        text(s, x + 0.22, 2.06, 2.3, 0.22, "推荐优先养成", size=8, color=BRASS, bold=True)
    text(s, x + 0.22, 2.32 if hot else 2.14, 2.3, 0.3, name, size=15, color=CREAM, bold=True)
    text(s, x + 0.22, 2.72 if hot else 2.54, 2.3, 0.62, mech, size=9, color=MUTED, spacing=1.3)
    text(s, x + 0.22, 3.48 if hot else 3.30, 2.3, 0.24, "主词条", size=8, color=BRASS, bold=True)
    text(s, x + 0.22, 3.72 if hot else 3.54, 2.34, 0.5, main, size=10.5, color=CREAM, spacing=1.25)
    text(s, x + 0.22, 4.44 if hot else 4.26, 2.3, 0.24, "副词条池", size=8, color=BRASS, bold=True)
    text(s, x + 0.22, 4.68 if hot else 4.50, 2.34, 0.6, sub, size=9, color=RGBColor(0xB9, 0xC4, 0xCF), spacing=1.3)

text(s, M, 5.62, CONTENT_W, 0.7,
     "指挥组为什么值钱：历史上“同时转向”靠信号旗、无线电和领舰观察，成功率本来就不高——"
     "CAS 把它做成检定而不是必然。指挥组给的正是这个检定的加值，玩家能感觉到“我的参谋组让整个舰队转得更齐”。",
     size=10.5, color=BRASS, spacing=1.4)
text(s, M, 6.42, CONTENT_W, 0.4,
     "主词条可锁定重铸，副词条随机，洗练 10 次保底 1 条 T1；一套 T1 约 6–8 周。不做水手人格抽卡，不做套装效果。",
     size=9.5, color=MUTED)
footer(s, n)

# ============================================================ 15 总量与协议
n += 1
s = new_slide(prs)
kicker(s, "0 7–0 8　/　封 顶 与 验 证")
title(s, "总量封顶，再用一个模式开关收口", size=27)
rule(s)

table(s, M, 1.92, 5.9, [0.36, 0.32, 0.32], [
    ["维度", "单线上限", "合计上限"],
    ["命中率", "熟练度 +10%", "+12%"],
    ["火力", "等级 +5%", "+6%"],
    ["船体", "等级 +5%", "+6%"],
    ["航速", "等级 +2%", "+2%（仅自有舰队）"],
    ["同时机动", "指挥组 +8pt", "+8pt"],
], size=10, row_h=0.62)

text(s, 7.0, 1.92, 5.5, 0.24, "养成协议：加成是否生效由模式决定", size=9.5, color=BRASS, bold=True)
table(s, 7.0, 2.22, 5.55, [0.42, 0.30, 0.28], [
    ["模式", "加成", "原因"],
    ["战役 · 故事", "自有 100% / 借舰 0%", "用自己的船改变历史"],
    ["战役 · 标准 / 挑战", "0%", "历史保真，舰卡即历史"],
    ["剧情模式", "100%", "架空叙事"],
    ["挑战 / 排位 / 演习", "100%", "竞技与养成的战场"],
], size=9.5, row_h=0.64)

text(s, 7.0, 5.26, 5.55, 1.3,
     "这套开关是整份企划里最关键的调和：\n"
     "既让玩家“练的船有用”，又保证“历史关还是历史”。\n"
     "编成屏上必须明示当前模式吃不吃加成。",
     size=10, color=MUTED, spacing=1.5)
text(s, M, 6.30, 5.9, 0.4,
     "四条线全满也只是“同一艘船更顺手一点”，不会变成另一艘船。",
     size=10.5, color=BRASS)
footer(s, n)

# ============================================================ 16 内容产能
n += 1
s = new_slide(prs)
kicker(s, "0 9　/　内 容 产 能")
title(s, "最大的运营风险不是留存，是内容饿死", size=27)
rule(s)
table(s, M, 1.90, CONTENT_W, [0.24, 0.13, 0.17, 0.20, 0.26], [
    ["内容类型", "单件人周", "18 个月产能", "复用度", "作用"],
    ["历史关（新想定）", "4–6 人周", "12–16 关", "低", "买点、口碑、史料馆"],
    ["剧情章节", "2–3 人周", "8 章", "中", "周更主力、情感承接"],
    ["副本", "3–5 人周", "6 个", "高（复用海图）", "养成出口"],
    ["挑战梯度", "0.5 人周 / 档", "近乎无限", "极高（复用点表与 AI）", "长期耐玩、赛季"],
], size=10, row_h=0.62)
text(s, M, 5.06, CONTENT_W, 0.9,
     "按这个结构，18 个月内玩家每周都有新东西：4 周一个副本或剧情章，8–10 周一个历史关，每 4 周一个挑战赛季。\n"
     "历史关慢一点没关系，但不能断。",
     size=11, color=MUTED, spacing=1.5)
rect(s, M, 6.10, CONTENT_W, 0.62, fill=CARD2)
text(s, M + 0.26, 6.24, 11.2, 0.34,
     "口碑靠历史关，周更靠剧情与副本，耐玩靠挑战梯度——三层各自解决不同的问题，不能互相替代。",
     size=11, color=CREAM, bold=True)
footer(s, n)

# ============================================================ 17 商业化
n += 1
s = new_slide(prs)
kicker(s, "1 0　/　商 业 化")
title(s, "只卖外观与便利，怎么赚钱", size=27)
rule(s)

rev = [
    ("外观", "45%", "涂装、立绘皮肤、舰名牌、母港装饰、战报边框", "68–128 元 / 件；赛季限定 198"),
    ("通行证", "30%", "双轨（免费 / 付费），给元词、外观、素材，不含数值", "68 元 / 赛季（8 周）"),
    ("便利与月卡", "25%", "月卡、预设位扩容、战报导出、燃油补给包（日限 3）", "6–328 元"),
]
for i, (name, pct, what, price) in enumerate(rev):
    x = M + i * 4.04
    rect(s, x, 1.90, 3.72, 1.90, fill=CARD)
    text(s, x + 0.26, 2.06, 2.0, 0.28, name, size=14, color=CREAM, bold=True)
    text(s, x + 2.90, 2.02, 0.62, 0.3, pct, size=16, color=BRASS, bold=True, font=NUM, align=PP_ALIGN.RIGHT)
    text(s, x + 0.26, 2.48, 3.24, 0.62, what, size=9.5, color=MUTED, spacing=1.35)
    text(s, x + 0.26, 3.44, 3.24, 0.24, price, size=9.5, color=RGBColor(0xB9, 0xC4, 0xCF))

text(s, M, 4.02, 6.1, 0.24, "收入测算（内部假设，需测试期校准）", size=9.5, color=BRASS, bold=True)
table(s, M, 4.32, 6.1, [0.24, 0.24, 0.22, 0.30], [
    ["情景", "DAU", "付费率", "月流水（估）"],
    ["保守", "50,000", "3.0%", "≈ 90 万元"],
    ["基准", "150,000", "4.0%", "≈ 510 万元"],
    ["乐观", "300,000", "5.0%", "≈ 1,650 万元"],
], size=9.5, row_h=0.44, head_h=0.32)

text(s, 7.0, 4.32, 5.55, 1.3,
     "三行都是假设，不是预测。真正要验证的是两个数：\n"
     "付费率能否到 4%，月卡渗透能否到 8%。\n"
     "只卖外观的产品，收入结构一定偏“靠人数”。",
     size=9.5, color=MUTED, spacing=1.45)

rect(s, M, 6.28, CONTENT_W, 0.50, fill=RGBColor(0x2A, 0x22, 0x1E), line=DANGER, line_w=0.9)
text(s, M + 0.26, 6.39, 11.3, 0.3,
     "红线：不卖命中、伤害、耐久、装备成品、水手词条、熟练度经验；不卖必胜道具；燃油包每日限 3 次。",
     size=10, color=RGBColor(0xD8, 0xC6, 0xB8))
footer(s, n)

# ============================================================ 18 路线图
n += 1
s = new_slide(prs)
kicker(s, "1 1　/　路 线 图")
title(s, "18 个月：从可信内核走到上线", size=27)
rule(s)

rect(s, 1.30, 3.24, 10.9, 0.012, fill=LINE)
miles = [
    ("M0 · 已完成", "内核可信", "逐秒裁决、双盲观察、可重演"),
    ("M1 · 0–4 月", "产品层闭环", "编成屏、经济并轨、母港单页"),
    ("M2 · 4–9 月", "养成四线", "熟练度 / 等级 / 装备 / 水手 + 三副本"),
    ("M3 · 9–12 月", "挑战与天梯", "五档倍率、周次数、赛季排行"),
    ("M4 · 12–15 月", "排位 PVP", "3000 / 10000 档、段位、匹配"),
    ("M5 · 15–18 月", "3v3·5v5 与上线", "房间制、多指挥、双端发行"),
]
for i, (when, name, what) in enumerate(miles):
    x = 1.30 + i * 2.02
    done = i == 0
    rect(s, x - 0.055, 3.175, 0.12, 0.12, fill=BRASS if done else BG, line=BRASS, line_w=1.1)
    up = i % 2 == 0
    if up:
        text(s, x - 0.3, 2.28, 1.6, 0.22, when, size=9, color=BRASS, bold=True)
        text(s, x - 0.3, 2.54, 1.7, 0.26, name, size=11, color=CREAM, bold=True)
        text(s, x - 0.3, 2.80, 1.7, 0.36, what, size=8.5, color=MUTED, spacing=1.25)
        rect(s, x, 2.72, 0.01, 0.5, fill=LINE)
    else:
        text(s, x - 0.3, 3.44, 1.6, 0.22, when, size=9, color=BRASS, bold=True)
        text(s, x - 0.3, 3.70, 1.7, 0.26, name, size=11, color=CREAM, bold=True)
        text(s, x - 0.3, 3.96, 1.7, 0.44, what, size=8.5, color=MUTED, spacing=1.25)
        rect(s, x, 3.30, 0.01, 0.14, fill=LINE)


text(s, M, 5.06, CONTENT_W, 0.9,
     "排序原则：内核先行、产品层紧随、PVP 最后。\n"
     "养成四线（M2）必须排在排位（M4）之前——否则排位会拿一套还没校准的成长去平衡。",
     size=10.5, color=MUTED, spacing=1.5)
text(s, M, 5.86, CONTENT_W, 0.3,
     "每个里程碑都有硬验收门，不通过不进下一段。", size=11, color=BRASS)
footer(s, n)

# ============================================================ 19 风险
n += 1
s = new_slide(prs)
kicker(s, "1 2　/　风 险")
title(s, "六个真实风险，以及各自的止损", size=27)
rule(s)
table(s, M, 1.86, CONTENT_W, [0.28, 0.09, 0.63], [
    ["风险", "影响", "对策"],
    ["历史关产能低，内容饥荒", "高", "剧情 + 副本 + 挑战梯度三层兜底；历史关按 8–10 周一关排"],
    ["实时指挥门槛高，首日流失", "高", "借舰兜底、固定流程教学、默认自动暂停、撤销一切误操作"],
    ["养成幅度太小，玩家无感", "中", "加成做成可见数字；战报里逐条标注“熟练度 +3%”"],
    ["燃油与硬核受众冲突", "中", "只锁刷取；首通与竞技零消耗；社区沟通时写在最前面"],
    ["排位被点表绑架", "中", "点价表按赛季公示与调整；同档内禁用唯一最优解"],
    ["PVP 同步与作弊", "高", "服务端权威时钟与种子；命令日志可重演；异常对局人工复核"],
], size=9.5, row_h=0.68)
footer(s, n)

# ============================================================ 20 结尾
n += 1
s = new_slide(prs)
rect(s, M, 1.42, 1.6, 0.014, fill=BRASS)
text(s, M, 1.78, 11.2, 1.5,
     "玩家的决策，\n必须比他的收藏更值钱。",
     size=42, color=CREAM, bold=True, spacing=1.24)
text(s, M, 4.06, 10.6, 0.6,
     "这是这款游戏唯一真正的卖点：不是 167 张立绘，是那 167 张立绘背后，每一艘都值得你亲自指挥一次的海。",
     size=13, color=MUTED, spacing=1.45)

text(s, M, 4.96, 3.0, 0.24, "接下来三步", size=9.5, color=BRASS, bold=True)
steps = [
    ("1", "拍板四处冲突", "附录 C：体力、养成数值、挑战模式、元词"),
    ("2", "补舰船所有权", "本地存档按身份的 owned，养成线才能落地"),
    ("3", "做编成屏", "母港 → 首战 ≤ 4 次点击，它吃到五个系统"),
]
for i, (num, name, desc) in enumerate(steps):
    x = M + i * 3.95
    rect(s, x, 5.28, 3.66, 1.30, fill=CARD)
    text(s, x + 0.24, 5.42, 0.3, 0.26, num, size=13, color=BRASS, bold=True)
    text(s, x + 0.58, 5.40, 2.9, 0.26, name, size=12, color=CREAM, bold=True)
    text(s, x + 0.24, 5.74, 3.2, 0.66, desc, size=9, color=MUTED, spacing=1.35)

text(s, M, 6.86, 6.0, 0.24, "CAS　·　2026 年 11 月", size=9, color=RGBColor(0x52, 0x68, 0x78))
text(s, 13.333 - M - 3.0, 6.86, 3.0, 0.24, "详细系统见《CAS 项目企划书 v1.0》", size=9,
     color=RGBColor(0x52, 0x68, 0x78), align=PP_ALIGN.RIGHT)

prs.save(OUT)
print("saved")
print("slides", len(prs.slides))
import io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
for w in WARNINGS:
    print("WARN", w)












