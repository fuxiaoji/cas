# -*- coding: utf-8 -*-
"""Build the course-assignment deck: abstracting the gacha business model."""

import os
import sys

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.util import Inches, Pt

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from deck_light import (  # noqa: E402
    ACCENT, CONTENT_W, FONT, INK, M, MUTED, NUM, PAPER, RULE, SLATE, WARNINGS,
    WASH, WASH2, WHITE, bullets, footer, kicker, new_slide, rect, rule, table,
    text, title,
)

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "二游商业模型-课程大作业-v1.0.pptx")

prs = Presentation()
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)

FAINT = RGBColor(0x9A, 0x9F, 0xA4)

n = 1

# ============================================================ 01 封面
s = new_slide(prs)
text(s, M, 1.42, 8, 0.24, "企 业 商 业 化　·　课 程 大 作 业", size=10, color=ACCENT, bold=True)
rect(s, M, 1.80, 1.3, 0.012, fill=ACCENT)
text(s, M, 2.12, 11.0, 0.85, "二游的商业模型", size=46, color=INK, bold=True, spacing=1.05)
text(s, M, 3.06, 11.0, 0.85, "先抽象一套模型，再把一款兵棋改造成二游", size=25, color=SLATE, spacing=1.15)
text(s, M, 4.28, 7.4, 0.9,
     "这次作业我们想证明一件事：二游的收入结构是可以被公式化的，\n"
     "而一旦公式化，它就变成一套可以搬到别的品类上的改造方法。",
     size=11.5, color=MUTED, spacing=1.55)
rect(s, M, 6.10, CONTENT_W, 0.008, fill=RULE)
for i, (k, v) in enumerate((
    ("课　程", "企业商业化（2026 秋）"),
    ("小　组", "第 __ 组　·　组员：____ / ____ / ____"),
    ("日　期", "2026 年 11 月"),
)):
    x = M + i * 3.9
    text(s, x, 6.28, 3.6, 0.2, k, size=8, color=ACCENT, bold=True)
    text(s, x, 6.50, 3.6, 0.24, v, size=10, color=INK)

# ============================================================ 02 我们做了什么
n += 1
s = new_slide(prs)
kicker(s, "0 1　/　作 业 概 览")
title(s, "我们做了三件事，顺序不能颠倒")
rule(s)
steps = [
    ("① 抽象", "从三款头部二游里，抽出五个共同要素，写成一条能算的公式。",
     "产出：五要素模型 + 单角色收入公式"),
    ("② 回测", "用模型反推这三款产品各自的收入结构，解释不通的要素就删掉。",
     "产出：要素权重表，验证模型能证伪自己"),
    ("③ 应用", "选一款完全不是二游的产品，按模型改造，写一份能落地的方案。",
     "产出：Command at Sea → CAS 的改造方案"),
]
for i, (head, body_, out) in enumerate(steps):
    y = 1.95 + i * 1.28
    text(s, M, y, 0.9, 0.34, head, size=13, color=ACCENT, bold=True)
    text(s, M + 1.05, y - 0.02, 6.2, 0.6, body_, size=11.5, color=INK, spacing=1.4)
    text(s, M + 7.6, y + 0.02, 3.9, 0.4, out, size=9.5, color=MUTED, spacing=1.3)
    rect(s, M, y + 0.70, CONTENT_W, 0.006, fill=RULE)

rect(s, M, 5.86, CONTENT_W, 0.86, fill=WASH)
rect(s, M, 5.86, 0.05, 0.86, fill=ACCENT)
text(s, M + 0.34, 6.02, 2.0, 0.24, "一句话结论", size=8.5, color=ACCENT, bold=True)
text(s, M + 1.85, 5.99, 9.3, 0.34, "二游卖的不是角色，是“想要”。", size=17, color=INK, bold=True)
text(s, M + 1.85, 6.36, 9.3, 0.24, "角色只是“想要”的载体，抽卡只是“想要”的收费界面。", size=10, color=MUTED)
footer(s, n)

# ============================================================ 03 方法
n += 1
s = new_slide(prs)
kicker(s, "0 2　/　方 法")
title(s, "怎么抽象：只记录“收钱的动作”，不记录“好看的东西”")
rule(s)

text(s, M, 1.86, 7.4, 0.3, "三步法", size=9.5, color=ACCENT, bold=True)
method = [
    ("拆解", "Decompose", "只看三个问题：钱从哪来、什么时候来、玩家在哪一刻决定付。"),
    ("归纳", "Induce", "把动作归到要素上。要素必须同时满足：跨产品重复、能解释收入节奏、能被改造。"),
    ("回测", "Backtest", "用模型反推已知产品。解释不了的要素，删掉，不要留着好看。"),
]
for i, (cn, en, desc) in enumerate(method):
    y = 2.18 + i * 1.35
    text(s, M, y, 0.5, 0.26, f"0{i + 1}", size=10, color=ACCENT, bold=True)
    text(s, M + 0.55, y - 0.04, 1.2, 0.28, cn, size=14, color=INK, bold=True)
    text(s, M + 1.55, y + 0.02, 1.6, 0.26, en, size=8.5, color=FAINT, italic=True)
    text(s, M, y + 0.40, 7.1, 0.6, desc, size=11, color=MUTED, spacing=1.4)

rect(s, 8.55, 1.86, 0.008, 4.30, fill=RULE)
text(s, 8.92, 1.86, 3.5, 0.3, "被我们砍掉的三个候选要素", size=9.5, color=ACCENT, bold=True)
text(s, 8.92, 2.16, 3.5, 0.3, "它们影响成功率，但不解释收入结构", size=9, color=MUTED)
bullets(s, 8.92, 2.62, 3.5, [
    ("IP 大小　", "只影响触达人数 N，不影响玩家为什么在那一抽付钱"),
    ("美术质量　", "决定 P 的上限，但无法解释版本节奏与保底结构"),
    ("玩法深度　", "决定留存，却和付费频次没有稳定关系"),
], size=10, gap=0.14, spacing=1.35)
footer(s, n)

# ============================================================ 04 六个变量
n += 1
s = new_slide(prs)
kicker(s, "0 2　/　拆 解")
title(s, "先把一款二游，拆成六个可以观测的变量")
rule(s)
table(s, M, 1.88, CONTENT_W, [0.20, 0.36, 0.44], [
    ["变量", "怎么观测", "头部产品的常见取值"],
    ["角色供给", "每月上新的可抽取角色数", "1–3 个 / 月，UP 与常驻分开上"],
    ["抽取结构", "概率分档、保底次数、UP 占比", "UR 0.6%–2%，保底 80–300 抽"],
    ["收费入口", "玩家实际花钱的地方", "抽卡 / 皮肤 / 通行证 / 月卡，四类"],
    ["版本节奏", "大版本之间的间隔", "6–8 周一个版本，一年 6–8 次"],
    ["养成深度", "单角色从到手到满配的时长", "2–8 周，且需要重复素材"],
    ["社群载体", "玩家自发生产内容的形态", "二创图 / 攻略 / 语音切片 / 考据"],
], size=10, row_h=0.58)
text(s, M, 5.62, CONTENT_W, 0.3,
     "这六个变量都能在游戏内直接观察，不依赖任何第三方流水数据——这是后面回测能成立的前提。",
     size=10, color=MUTED)
footer(s, n)

# ============================================================ 05 五要素
n += 1
s = new_slide(prs)
kicker(s, "0 3　/　归 纳")
title(s, "归纳成五个要素：角、率、限、养、版")
rule(s)

five = [
    ("角", "角色 SKU", "角色同时是内容、玩法单位和情感对象，一件商品三份用途"),
    ("率", "概率定价", "用期望值出售“拥有”，把高客单拆成可重复的小额"),
    ("限", "限时稀缺", "限定与复刻制造时间窗口，是收入节奏的调速器"),
    ("养", "养成锁定", "抽到只是开始，用沉没成本把玩家的时间留在游戏里"),
    ("版", "版本订阅", "固定周期上新内容，把“一次性买断”变成“按月订阅”"),
]
w = (CONTENT_W - 4 * 0.22) / 5
for i, (ch, name, desc) in enumerate(five):
    x = M + i * (w + 0.22)
    rect(s, x, 1.90, w, 2.62, fill=WHITE)
    rect(s, x, 1.90, w, 0.03, fill=ACCENT if i < 3 else SLATE)
    text(s, x + 0.22, 2.04, 0.5, 0.22, f"0{i + 1}", size=8.5, color=ACCENT, bold=True)
    text(s, x + 0.22, 2.28, 0.8, 0.80, ch, size=40, color=INK, bold=True, spacing=0.95)
    text(s, x + 0.22, 3.16, w - 0.40, 0.24, name, size=11, color=SLATE, bold=True)
    text(s, x + 0.22, 3.50, w - 0.40, 1.10, desc, size=9, color=MUTED, spacing=1.38)

text(s, M, 5.10, CONTENT_W, 0.3,
     "前三个（角 / 率 / 限）决定“钱怎么来”，后两个（养 / 版）决定“钱来得多不多、久不久”。",
     size=11, color=INK)
rect(s, M, 5.52, CONTENT_W, 0.008, fill=RULE)
text(s, M, 5.68, 5.4, 0.7,
     "五要素不是我们发明的。\n我们做的是把它们压到最少的、彼此不重复的五个。",
     size=10, color=MUTED, spacing=1.45)
text(s, 6.6, 5.68, 5.3, 0.7,
     "少一个就解释不通：只有角没有率，是买断制；\n只有率没有版，是一次性收割。",
     size=10, color=MUTED, spacing=1.45)
footer(s, n)

# ============================================================ 06 公式
n += 1
s = new_slide(prs)
kicker(s, "0 3　/　模 型")
title(s, "写成一条能算的公式：单角色的收入拆成四个乘数")
rule(s)

parts = [
    ("N", "触达", "买量 + 二创 + 联动\n决定有多少人看见"),
    ("P(想要)", "转化", "角色设计 × 剧情曝光\n× 稀缺度"),
    ("E[抽数]", "深度", "保底结构 × UP 概率\n× 已有库存"),
    ("p", "单价", "¥6–18 / 抽\n行业定价惯例"),
]
bw = 2.42
gap = 0.30
for i, (sym, name, desc) in enumerate(parts):
    x = M + i * (bw + gap)
    rect(s, x, 1.96, bw, 1.62, fill=WHITE)
    text(s, x, 2.10, bw, 0.5, sym, size=22, color=INK, bold=True, align=PP_ALIGN.CENTER, spacing=1.0)
    text(s, x, 2.62, bw, 0.22, name, size=9, color=ACCENT, bold=True, align=PP_ALIGN.CENTER)
    text(s, x + 0.10, 2.92, bw - 0.20, 0.6, desc, size=8.5, color=MUTED,
         align=PP_ALIGN.CENTER, spacing=1.3)
    if i < 3:
        text(s, x + bw + 0.03, 2.52, 0.26, 0.3, "×", size=15, color=MUTED, align=PP_ALIGN.CENTER)

text(s, M, 3.78, CONTENT_W, 0.34, "R（单角色生命周期收入）  =  N  ×  P(想要)  ×  E[抽数]  ×  p",
     size=15, color=INK, bold=True)
text(s, M, 4.18, CONTENT_W, 0.3,
     "整款游戏的收入 = Σ 角色 + 皮肤 + 通行证 + 月卡；其中 Σ 角色 通常占六成以上。",
     size=9.5, color=MUTED)

rect(s, M, 4.66, CONTENT_W, 1.42, fill=WASH)
text(s, M + 0.34, 4.80, 2.4, 0.24, "这条公式的用处", size=8.5, color=ACCENT, bold=True)
text(s, M + 0.34, 5.04, 10.9, 0.92,
     "四个乘数里，N 靠钱、p 靠行业惯例、E 靠数学（保底结构），只有 P 是“产品能力”。\n"
     "所以二游的预算为什么大头在立绘、CV、剧情、二创激励上——那不是审美选择，是在买 P。",
     size=11, color=INK, spacing=1.55)
footer(s, n)

# ============================================================ 07 本质
n += 1
s = new_slide(prs)
kicker(s, "0 4　/　本 质")
title(s, "所以二游不是“抽卡游戏”，是订阅制内容生意")
rule(s)
table(s, M, 1.88, CONTENT_W, [0.18, 0.27, 0.27, 0.28], [
    ["", "传统买断（3A / 兵棋）", "订阅制（服务型）", "二游"],
    ["付费时点", "一次，发售当天", "每月，固定", "每次“想要”发生时"],
    ["内容单位", "整部作品", "月度内容包", "单个角色 + 配套剧情"],
    ["收入曲线", "首发峰值，之后归零", "平稳，可预测", "脉冲式：每个版本一个尖峰"],
    ["玩家关系", "消费者", "订阅者", "收藏者 + 订阅者"],
], size=10.5, row_h=0.62)
text(s, M, 4.92, CONTENT_W, 0.3, "抽卡只是这个订阅制的收费界面。", size=13, color=INK, bold=True)
text(s, M, 5.28, 11.2, 1.1,
     "把这句话说透：一家二游公司真正的产品不是游戏，是“每个月让玩家产生 1–3 次强烈想要的能力”。\n"
     "游戏只是这条生产线的载体；皮肤、联动、复刻，都是在同一条产线上换产品。",
     size=10.5, color=MUTED, spacing=1.5)
footer(s, n)

# ============================================================ 08 定价解剖
n += 1
s = new_slide(prs)
kicker(s, "0 4　/　定 价 机 制")
title(s, "为什么是抽卡，而不是把角色标价 648")
rule(s)

rows = [
    ("标价的天花板", "虚拟商品的心理价位被皮肤锚死在 ¥68–128。直接标 648 卖一个角色，几乎没人买。"),
    ("把一次大额拆成多次小额", "¥6–18 一抽，绕开“这笔钱值不值”的判断，进入“再来十抽”的节奏。"),
    ("用保底给出确定性锚点", "玩家心里算的是“最多 ¥648 必出”，不是“期望 ¥900”。锚点从期望值换成了上限。"),
    ("沉没成本接管决策", "已经投了 60 抽，第 61 抽的边际成本被感知为“只差 20 抽”。"),
]
for i, (head, body_) in enumerate(rows):
    y = 1.90 + i * 1.02
    text(s, M, y, 2.6, 0.26, head, size=11, color=INK, bold=True)
    text(s, M, y + 0.32, 7.5, 0.55, body_, size=9.8, color=MUTED, spacing=1.4)
    rect(s, M, y + 0.90, 7.5, 0.006, fill=RULE)

rect(s, 8.90, 1.90, 0.008, 4.05, fill=RULE)
text(s, 9.25, 1.90, 3.2, 0.24, "代价", size=8.5, color=ACCENT, bold=True)
text(s, 9.25, 2.20, 3.2, 1.6,
     "这套机制把“买不买”变成了“忍不忍”。\n它同时是收入的引擎，和舆论与监管的靶心。",
     size=10, color=INK, spacing=1.55)
text(s, 9.25, 3.70, 3.2, 2.2,
     "我们在方案里保留抽卡，\n但加了两条约束：\n概率公示到小数点后一位；\n不卖任何影响胜负的数值。",
     size=9.5, color=MUTED, spacing=1.55)
footer(s, n)

# ============================================================ 09 回测 1
n += 1
s = new_slide(prs)
kicker(s, "0 5　/　回 测 （一）")
title(s, "碧蓝航线：模型成立，但“角”的权重最高")
rule(s)
table(s, M, 1.88, 7.55, [0.22, 0.78], [
    ["要素", "它怎么做"],
    ["角", "历史舰艇拟人，一次可抽身份上百个；角色即收藏品"],
    ["率", "建造分四档池，概率友好，另有兑换点数兜底"],
    ["限", "限定池 + 定期复刻，复刻本身是一次收入事件"],
    ["养", "等级 / 技能 / 装备 / 好感，四轴并行"],
    ["版", "活动与主线交替，版本密度高但单版本内容轻"],
], size=9.5, row_h=0.62)
rect(s, 8.85, 1.88, 0.008, 3.70, fill=RULE)
text(s, 9.20, 1.88, 3.2, 0.24, "回测读到什么", size=8.5, color=ACCENT, bold=True)
text(s, 9.20, 2.20, 3.2, 2.0,
     "“角”做到极致：玩家为“拥有”付费，而不是为“变强”付费。\n"
     "“率”反而最轻——概率友好、有兜底，收入靠人数不靠大额。",
     size=9.5, color=INK, spacing=1.5)
text(s, 9.20, 4.42, 3.2, 1.0,
     "皮肤是它的第二收入曲线，且不占抽卡预算——这是“角”权重高的自然结果。",
     size=8.5, color=MUTED, spacing=1.4)
footer(s, n)

# ============================================================ 10 回测 2
n += 1
s = new_slide(prs)
kicker(s, "0 5　/　回 测 （二）")
title(s, "明日方舟：同样五个要素，但“版”和“限”在承重")
rule(s)
table(s, M, 1.88, 7.55, [0.22, 0.78], [
    ["要素", "它怎么做"],
    ["角", "干员带职业 / 费用 / 阻挡，角色同时是玩法单位"],
    ["率", "单池 UP，出率与保底结构清晰，另设兑换口径"],
    ["限", "限定池 + 联动，窗口期明确，复刻克制"],
    ["养", "精英化 / 模组 / 技能专精，养成周期长"],
    ["版", "六周一个版本，剧情驱动，剧情本身就是“想要”的生产线"],
], size=9.5, row_h=0.62)
rect(s, 8.85, 1.88, 0.008, 3.70, fill=RULE)
text(s, 9.20, 1.88, 3.2, 0.24, "回测读到什么", size=8.5, color=ACCENT, bold=True)
text(s, 9.20, 2.20, 3.2, 2.0,
     "“角”被做成了玩法单位：抽到就能改变关卡的解法，付费动机来自“战术需求”而非单纯收藏。\n"
     "“版”承担了主要的内容节奏，剧情是 P 的主力生产手段。",
     size=9.5, color=INK, spacing=1.5)
text(s, 9.20, 4.42, 3.2, 1.0,
     "体力（理智）是节奏阀：它不产生收入，但把玩家的内容消费速度对齐到版本节奏上。",
     size=8.5, color=MUTED, spacing=1.4)
footer(s, n)

# ============================================================ 11 回测结论
n += 1
s = new_slide(prs)
kicker(s, "0 5　/　回 测 结 论")
title(s, "要素集合是稳的，变的是权重")
rule(s)
_weight_tbl = table(s, M, 1.88, CONTENT_W, [0.16, 0.17, 0.17, 0.17, 0.17, 0.16], [
    ["", "角", "率", "限", "养", "版"],
    ["碧蓝航线", "●●●", "●○○", "●●○", "●●○", "●●○"],
    ["明日方舟", "●●○", "●●○", "●●●", "●●●", "●●●"],
    ["CAS（我们改的）", "●●●", "●●○", "●●○", "●●○", "●●●"],
], size=10.5, row_h=0.56)
for _r in range(1, 4):
    for _c in range(1, 6):
        _cell = _weight_tbl.cell(_r, _c)
        _p = _cell.text_frame.paragraphs[0]
        _txt = _p.text
        for _run in list(_p.runs):
            _run._r.getparent().remove(_run._r)
        for _ch in _txt:
            _run = _p.add_run()
            _run.text = _ch
            _run.font.name = FONT
            _run.font.size = Pt(13)
            _run.font.bold = False
            _run.font.color.rgb = ACCENT if _ch == "●" else RGBColor(0xD3, 0xCD, 0xBD)
text(s, M, 4.10, CONTENT_W, 0.3,
     "● 的多少是我们按公开机制做的判断，不是官方数据；它的作用是解释结构，不是排名。",
     size=9, color=MUTED)
rect(s, M, 4.62, CONTENT_W, 1.34, fill=WASH)
text(s, M + 0.34, 4.76, 3.0, 0.24, "这一步的结论", size=8.5, color=ACCENT, bold=True)
text(s, M + 0.34, 5.04, 10.9, 0.86,
     "三款产品的五要素集合完全一样，差别只在权重分配。\n"
     "所以“二游化”不是照抄某一款，而是：先确认五要素齐全，再决定把资源压在哪个要素上。",
     size=11, color=INK, spacing=1.55)
footer(s, n)

# ============================================================ 12 准入
n += 1
s = new_slide(prs)
kicker(s, "0 6　/　选 品 标 准")
title(s, "那么，什么样的游戏能被包装成二游")
rule(s)
table(s, M, 1.88, CONTENT_W, [0.24, 0.46, 0.30], [
    ["准入条件", "判定标准", "为什么必须"],
    ["可拟人化的对象池", "≥ 50 个可独立命名、可考据的对象", "角色供给是订阅制的原材料"],
    ["可重复消耗的内容单位", "关卡 / 战役 / 赛季，能反复打", "版本制需要一个可以不断加长的容器"],
    ["可数值化的成长轴", "等级 / 装备 / 词条，且能拆得很细", "养成锁定需要足够的沉没空间"],
    ["可叙事化的世界观", "历史 / 架空 / 神话，能持续产出文本", "“想要”主要靠叙事生产"],
], size=10, row_h=0.62)
text(s, M, 5.30, CONTENT_W, 0.3, "四条全中是“可改造”；缺一条，最多只能做皮肤联动。", size=12, color=INK, bold=True)
text(s, M, 5.66, CONTENT_W, 0.3,
     "用这把尺子量了一圈：竞技类缺第 3 条（公平性冲突），叙事类缺第 2 条（一次性消耗），工具类四条全缺。",
     size=9.5, color=MUTED)
footer(s, n)

# ============================================================ 13 选品
n += 1
s = new_slide(prs)
kicker(s, "0 6　/　选 品")
title(s, "我们选了 Command at Sea：资产极厚，商业模型极薄")
rule(s)

text(s, M, 1.86, 5.2, 0.24, "它是什么", size=8.5, color=ACCENT, bold=True)
text(s, M, 2.14, 5.2, 1.3,
     "一套公开出版的二战水面战兵棋规则（五版）。\n"
     "核心是逐秒的舰队裁决：航向、航速、炮表、鱼雷、雷达接触。",
     size=10, color=MUTED, spacing=1.5)

text(s, M, 3.62, 5.2, 0.24, "它的资产", size=8.5, color=ACCENT, bold=True)
bullets(s, M, 3.90, 5.2, [
    ("内容　", "11 场逐页核验过的历史海战"),
    ("对象　", "167 个可征募的舰艇身份"),
    ("结构　", "可重演、可复盘、双盲裁决"),
], size=9.5, gap=0.10, spacing=1.35)

text(s, 6.55, 1.86, 5.4, 0.24, "它的问题", size=8.5, color=ACCENT, bold=True)
bullets(s, 6.55, 2.14, 5.4, [
    ("受众窄　", "万级，且集中在兵棋与海军史圈层"),
    ("一次性　", "买断 + 剧本包，没有持续付费的理由"),
    ("无成长　", "舰卡即历史，玩家没有“变强”的轴"),
    ("无版本　", "内容靠人工翻译规则，天然低频"),
], size=9.5, gap=0.10, spacing=1.35)

rect(s, 6.55, 4.30, 5.4, 0.008, fill=RULE)
text(s, 6.55, 4.46, 5.4, 0.9,
     "结论：它的“内容价值”很高，但完全不具备把内容变成现金流的结构。"
     "这正是最适合拿来改造的对象——不用造内容，只要造结构。",
     size=10, color=INK, spacing=1.5)
footer(s, n)

# ============================================================ 14 改造对照
n += 1
s = new_slide(prs)
kicker(s, "0 7　/　改 造 方 案")
title(s, "把五个要素逐条装上：一张表看完全部改造")
rule(s)
table(s, M, 1.86, CONTENT_W, [0.16, 0.27, 0.24, 0.33], [
    ["要素", "原模型（兵棋）", "改造动作", "落地机制"],
    ["角", "只有规则书里的舰名", "给每艘船一个角色身份", "立绘 + 语音 + 舰历档案，167 个身份"],
    ["率", "一次性买断", "改成免费 + 概率抽取", "征募：UR 2%，保底 80 抽，UP 占 50%"],
    ["限", "无", "加限定池与复刻", "活动限定 + 赛季复刻，8 周一轮"],
    ["养", "无", "加四条低幅成长轴", "熟练度 / 等级 / 装备 / 水手，单线 ≤ 10%"],
    ["版", "人工翻译，低频", "改成版本制", "8–10 周一个历史关 + 剧情章 + 副本"],
], size=9.5, row_h=0.60)
text(s, M, 5.28, CONTENT_W, 0.3, "外加两条竞技线：越级挑战（天梯）与点价排位。", size=10, color=INK)
text(s, M, 5.62, CONTENT_W, 0.5,
     "注意：五要素是齐的，但每一项都做了“减法”——概率、幅度、频率全部压到行业下限，"
     "因为这款产品的护城河是历史保真，不是数值刺激。",
     size=9.5, color=MUTED, spacing=1.45)
footer(s, n)

# ============================================================ 15 改造后形态
n += 1
s = new_slide(prs)
kicker(s, "0 7　/　改 造 后")
title(s, "改造后的产品形态：CAS")
rule(s)

mods = [
    ("战役", "11 场历史想定\n故事 / 标准 / 挑战三档"),
    ("剧情", "架空章节\n独立存档，VN 播放器"),
    ("挑战", "越级天梯\n3000 分打 4500 分"),
    ("排位", "点价档 3000 / 10000\n8 周一赛季"),
    ("养成", "四线低幅成长\n熟练度 / 等级 / 装备 / 水手"),
]
w = (CONTENT_W - 4 * 0.20) / 5
for i, (name, desc) in enumerate(mods):
    x = M + i * (w + 0.20)
    rect(s, x, 1.90, w, 1.72, fill=WHITE)
    text(s, x + 0.20, 2.04, w - 0.3, 0.26, name, size=12, color=INK, bold=True)
    text(s, x + 0.20, 2.42, w - 0.32, 1.0, desc, size=9, color=MUTED, spacing=1.4)

text(s, M, 3.86, CONTENT_W, 0.24, "一条经济串起来", size=8.5, color=ACCENT, bold=True)
text(s, M, 4.14, CONTENT_W, 0.3,
     "征募券 → 编成 → 出击 → 元词 / 银币 / 素材 → 养成 → 更强的编队 → 更高的点价档",
     size=11, color=INK)
rect(s, M, 4.62, CONTENT_W, 0.008, fill=RULE)
text(s, M, 4.78, 5.5, 1.2,
     "和原模型的对照：\n同一套裁决内核，一点没改；\n换掉的是它外面的商业外壳。",
     size=10, color=MUTED, spacing=1.5)
text(s, 6.55, 4.78, 5.4, 1.2,
     "这也是我们想说明的方法论价值：\n改造不需要重做产品，\n只需要重做“收钱的结构”。",
     size=10, color=MUTED, spacing=1.5)
footer(s, n)

# ============================================================ 16 单位经济
n += 1
s = new_slide(prs)
kicker(s, "0 8　/　算 一 笔 账")
title(s, "改造前后的单位经济：LTV 提升有限，杠杆在人数")
rule(s)
table(s, M, 1.88, CONTENT_W, [0.26, 0.30, 0.24, 0.20], [
    ["指标", "兵棋（改造前）", "CAS（改造后）", "变化"],
    ["获客成本", "¥80 / 人（垂直渠道）", "¥35 / 人（二创摊薄）", "↓"],
    ["付费率", "100%（买断）", "4%（免费 + 内购）", "↓"],
    ["ARPPU", "¥300（一次性）", "¥85 / 月", "→"],
    ["LTV（12 个月）", "¥300", "¥380", "↑ 27%"],
    ["年内容成本", "约 ¥120 万", "约 ¥600 万", "↑ 5 倍"],
], size=10, row_h=0.56)
text(s, M, 5.10, CONTENT_W, 0.3,
     "LTV 只涨了不到三成，内容成本涨了五倍——单看这两个数，改造是亏的。",
     size=11, color=INK)
text(s, M, 5.46, CONTENT_W, 0.3,
     "真正的杠杆在另一个乘数：可触达人数从万级变成百万级，规模把单用户的小幅提升放大成了总量的大幅提升。",
     size=10, color=MUTED, spacing=1.4)
text(s, M, 5.96, CONTENT_W, 0.24,
     "以上全部为我们自己的估算与假设，不是实测数据；它的作用是把改造的代价摆到台面上。",
     size=8.5, color=ACCENT)
footer(s, n)

# ============================================================ 17 风险
n += 1
s = new_slide(prs)
kicker(s, "0 8　/　代 价")
title(s, "改造会失去什么：三条红线，三个代价")
rule(s)
table(s, M, 1.88, CONTENT_W, [0.22, 0.34, 0.44], [
    ["失去的东西", "为什么必然失去", "我们的处理"],
    ["拟真受众的信任", "任何数值成长都会让历史阵位无法复现", "养成协议：标准/挑战难度加成归零"],
    ["公平性口碑", "付费即变强，竞技线立刻失去公信力", "不卖数值：元词换不到任何影响裁决的道具"],
    ["内容成本可控", "二游是内容军备竞赛，版本一停收入就断", "靠挑战梯度与副本复用撑周更"],
], size=10, row_h=0.86)
text(s, M, 5.30, CONTENT_W, 0.3,
     "这三条不是“注意事项”，是我们方案里被写进验收门的硬约束。", size=11, color=INK, bold=True)
text(s, M, 5.68, CONTENT_W, 0.6,
     "比如第二条：只要元词能换到一件成品装备，“只卖外观”的承诺就在一周内作废。"
     "所以我们把“付费墙检查”做成每次发版的必过项，而不是运营时的自觉。",
     size=9.5, color=MUTED, spacing=1.45)
footer(s, n)

# ============================================================ 18 边界
n += 1
s = new_slide(prs)
kicker(s, "0 9　/　结 论")
title(s, "这套模型的边界在哪")
rule(s)

text(s, M, 1.86, 5.3, 0.24, "可迁移", size=8.5, color=ACCENT, bold=True)
text(s, M + 0.02, 2.14, 5.3, 0.6,
     "任何同时具备“对象池 + 内容单位 + 成长轴 + 世界观”的产品。",
     size=10, color=INK, spacing=1.45)
bullets(s, M, 2.80, 5.3, [
    "舰船 / 枪械 / 坦克 / 机体 / 车站——可拟人的工业对象",
    "战役 / 关卡 / 赛季——可反复消耗的内容容器",
    "历史 / 架空 / 神话——可持续产出的叙事来源",
], size=9.5, gap=0.10, spacing=1.35)

text(s, 6.55, 1.86, 5.4, 0.24, "不可迁移", size=8.5, color=ACCENT, bold=True)
text(s, 6.57, 2.14, 5.4, 0.6,
     "三条里缺一条，硬做就会出结构性问题。",
     size=10, color=INK, spacing=1.45)
bullets(s, 6.55, 2.80, 5.4, [
    ("纯竞技　", "付费即变强与公平性直接冲突，只能卖外观"),
    ("纯叙事　", "内容一次性消耗，抽卡没有可重复的载体"),
    ("纯工具　", "用户为效率付费，不为情感付费"),
], size=9.5, gap=0.10, spacing=1.35)

rect(s, M, 4.86, CONTENT_W, 1.42, fill=WASH)
text(s, M + 0.34, 5.00, 3.2, 0.24, "一句话把作业收掉", size=8.5, color=ACCENT, bold=True)
text(s, M + 0.34, 5.28, 10.9, 0.9,
     "二游化的本质，是把一次性交付的内容，改造成一条能持续生产“想要”的流水线。\n"
     "流水线能不能建，取决于原材料；流水线赚不赚钱，取决于你愿意在生产“想要”上花多少钱。",
     size=11, color=INK, spacing=1.55)
footer(s, n)

# ============================================================ 19 反思
n += 1
s = new_slide(prs)
kicker(s, "1 0　/　复 盘")
title(s, "我们自己在这次作业里踩的三个坑")
rule(s)
pits = [
    ("以为模型的核心是抽卡概率",
     "第一版模型把概率结构当主线。回测时发现：概率只影响 E[抽数]，而 E 是最容易算、也最不差异化的乘数。",
     "修正：把 P(想要) 提到模型中心。"),
    ("以为 IP 大就能成",
     "IP 只作用于 N（触达），解释不了为什么同一款游戏在不同版本收入能差三倍。",
     "修正：N 和 P 拆成两个独立乘数。"),
    ("改造方案第一版把养成做成 +20%",
     "写完自己做了一次胜率抽样，满养成对零养成到了 70:30，直接推翻了整个公平性叙事。",
     "修正：单线封顶 10%，并加 55:45 的验收门。"),
]
for i, (head, body_, fix) in enumerate(pits):
    y = 1.90 + i * 1.56
    text(s, M, y, 0.5, 0.24, f"0{i + 1}", size=9.5, color=ACCENT, bold=True)
    text(s, M + 0.55, y - 0.03, 6.4, 0.3, head, size=12, color=INK, bold=True)
    text(s, M + 0.55, y + 0.34, 6.9, 0.72, body_, size=9.5, color=MUTED, spacing=1.4)
    text(s, M + 7.75, y + 0.10, 3.7, 0.6, fix, size=9.5, color=SLATE, spacing=1.4)
    rect(s, M + 7.65, y + 0.06, 0.02, 0.34, fill=ACCENT)
    rect(s, M, y + 1.28, CONTENT_W, 0.006, fill=RULE)
footer(s, n)

# ============================================================ 20 结尾
n += 1
s = new_slide(prs)
rect(s, M, 1.46, 1.3, 0.012, fill=ACCENT)
text(s, M, 1.82, 11.2, 1.6,
     "模型的价值不是解释过去，\n而是能证伪自己的方案。",
     size=36, color=INK, bold=True, spacing=1.26)
text(s, M, 3.86, 10.4, 0.6,
     "我们做完这套模型之后，第一件事是用它推翻了我们自己的第一版商业方案。这是这次作业最大的收获。",
     size=11, color=MUTED, spacing=1.5)

rect(s, M, 4.80, CONTENT_W, 0.008, fill=RULE)
text(s, M, 4.96, 3.0, 0.24, "分工", size=8.5, color=ACCENT, bold=True)
for i, (role, name) in enumerate((("模型抽象与回测", "____"), ("选品与改造方案", "____"), ("数据与答辩材料", "____"))):
    x = M + i * 3.9
    text(s, x, 5.24, 2.0, 0.24, role, size=9.5, color=INK)
    text(s, x + 2.10, 5.24, 1.4, 0.24, name, size=9.5, color=MUTED)

text(s, M, 6.12, 5.6, 0.7,
     "说明：本文所有产品机制描述均来自游戏内公开界面；\n"
     "概率、价格与财务数字为公开值或我们的假设，未引用第三方流水数据。",
     size=8.5, color=MUTED, spacing=1.5)
text(s, 6.55, 6.12, 5.4, 0.7,
     "参考资料：各产品游戏内公示概率与商城定价；\n"
     "Command at Sea 五版规则书（公开出版）。",
     size=8.5, color=MUTED, spacing=1.5)

prs.save(OUT)
print("saved")
print("slides", len(prs.slides))
for w in WARNINGS:
    print("WARN", w)



