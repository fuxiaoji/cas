# -*- coding: utf-8 -*-
"""Minimal slide toolkit for the CAS pitch deck."""

from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.util import Emu, Inches, Pt

FONT = "微软雅黑"
NUM = "Georgia"

BG = RGBColor(0x0A, 0x1C, 0x2B)
CARD = RGBColor(0x11, 0x2A, 0x3D)
CARD2 = RGBColor(0x0E, 0x24, 0x35)
BRASS = RGBColor(0xC8, 0xA4, 0x5C)
BRASS_DK = RGBColor(0x8A, 0x66, 0x30)
CREAM = RGBColor(0xEE, 0xE9, 0xDD)
MUTED = RGBColor(0x8C, 0xA2, 0xB3)
LINE = RGBColor(0x25, 0x3E, 0x51)
DANGER = RGBColor(0xC4, 0x6A, 0x50)

M = 0.78          # left/right margin
CONTENT_W = 13.333 - 2 * M

WARNINGS = []


def _rgb(hexstr):
    return RGBColor.from_string(hexstr)


def new_slide(prs):
    s = prs.slides.add_slide(prs.slide_layouts[6])
    bg = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, prs.slide_width, prs.slide_height)
    bg.fill.solid()
    bg.fill.fore_color.rgb = BG
    bg.line.fill.background()
    bg.shadow.inherit = False
    return s


def rect(slide, x, y, w, h, fill=None, line=None, line_w=0.75):
    sh = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(h))
    if fill is None:
        sh.fill.background()
    else:
        sh.fill.solid()
        sh.fill.fore_color.rgb = fill
    if line is None:
        sh.line.fill.background()
    else:
        sh.line.color.rgb = line
        sh.line.width = Pt(line_w)
    sh.shadow.inherit = False
    return sh


def _hang(p, marl=0.24):
    pPr = p._p.get_or_add_pPr()
    pPr.set("marL", str(int(marl * 914400)))
    pPr.set("indent", str(int(-marl * 914400)))


def text(slide, x, y, w, h, s, size=14, color=CREAM, bold=False, font=FONT,
         align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP, spacing=1.15, space_after=0,
         italic=False, wrap=True):
    tb = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = tb.text_frame
    tf.word_wrap = wrap
    tf.vertical_anchor = anchor
    tf.margin_left = 0
    tf.margin_right = 0
    tf.margin_top = 0
    tf.margin_bottom = 0
    lines = s.split("\n")
    for i, line in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        p.line_spacing = spacing
        p.space_before = Pt(0)
        p.space_after = Pt(space_after)
        r = p.add_run()
        r.text = line
        r.font.name = font
        r.font.size = Pt(size)
        r.font.bold = bold
        r.font.italic = italic
        r.font.color.rgb = color
    estimate(s, size, w, h, FONT if font == NUM else font)
    return tb


def estimate(s, size, w, h, font=FONT):
    """Rough overflow estimate for CJK-heavy text."""
    per = 1.0 if font == FONT else 0.58
    width_pt = w * 72.0
    lines = 0
    for line in s.split("\n"):
        units = 0.0
        for ch in line:
            units += 1.0 if ord(ch) > 0x2000 else 0.55
        width_units = width_pt / (size * per)
        lines += max(1, int(-(-units // width_units)))
    need = lines * size * 1.32 * 1.15 / 72.0
    if need > h + 0.02:
        WARNINGS.append(f"overflow? need {need:.2f}in > box {h:.2f}in :: {s[:34]}")


def kicker(slide, s):
    text(slide, M, 0.46, CONTENT_W, 0.24, s, size=10, color=BRASS, bold=True)


def title(slide, s, size=28, y=0.76, h=0.9, color=CREAM):
    text(slide, M, y, CONTENT_W, h, s, size=size, color=color, bold=True, spacing=1.1)


def rule(slide, y=1.68, width=1.5):
    rect(slide, M, y, CONTENT_W, 0.011, fill=LINE)
    rect(slide, M, y, width, 0.011, fill=BRASS)


def footer(slide, n, label="CAS 项目企划书 v1.0　·　内部立项评审稿"):
    text(slide, M, 7.02, 8.0, 0.22, label, size=8.5, color=RGBColor(0x52, 0x68, 0x78))
    text(slide, 13.333 - M - 1.2, 7.02, 1.2, 0.22, f"{n:02d} / 20", size=8.5,
         color=RGBColor(0x52, 0x68, 0x78), align=PP_ALIGN.RIGHT, font=NUM)


def bullets(slide, x, y, w, items, size=14, color=CREAM, bullet_color=BRASS,
            gap=0.16, spacing=1.25, marker="▪  "):
    tb = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(0.4))
    tf = tb.text_frame
    tf.word_wrap = True
    tf.margin_left = 0
    tf.margin_right = 0
    tf.margin_top = 0
    tf.margin_bottom = 0
    n = len(items)
    for i, item in enumerate(items):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.line_spacing = spacing
        p.space_after = Pt(gap * 72)
        p.space_before = Pt(0)
        _hang(p)
        r = p.add_run()
        r.text = marker
        r.font.name = FONT
        r.font.size = Pt(size)
        r.font.color.rgb = bullet_color
        r.font.bold = True
        if isinstance(item, tuple):
            lead, rest = item
            r = p.add_run()
            r.text = lead
            r.font.name = FONT
            r.font.size = Pt(size)
            r.font.bold = True
            r.font.color.rgb = color
            r = p.add_run()
            r.text = rest
            r.font.name = FONT
            r.font.size = Pt(size)
            r.font.color.rgb = MUTED
        else:
            r = p.add_run()
            r.text = item
            r.font.name = FONT
            r.font.size = Pt(size)
            r.font.color.rgb = color
    # rough height estimate for caller reference
    total = 0.0
    for item in items:
        s = item[0] + item[1] if isinstance(item, tuple) else item
        units = sum(1.0 if ord(c) > 0x2000 else 0.55 for c in s) + 2
        per_line = (w * 72.0) / size
        lines = max(1, int(-(-units // per_line)))
        total += lines * size * spacing * 1.32 / 72.0 + gap
    return tb


def table(slide, x, y, w, col_ratios, rows, size=10.5, head_size=10,
          row_h=0.42, head_h=0.36, head_fill="1A3D57", alt=(CARD2, BG)):
    nrows = len(rows)
    ncols = len(rows[0])
    height = head_h + row_h * (nrows - 1)
    shape = slide.shapes.add_table(nrows, ncols, Inches(x), Inches(y),
                                  Inches(w), Inches(height))
    tbl = shape.table
    tbl.first_row = False
    tbl.horz_banding = False
    widths = [w * r for r in col_ratios]
    for i, cw in enumerate(widths):
        tbl.columns[i].width = Inches(cw)
    tbl.rows[0].height = Inches(head_h)
    for r in range(1, nrows):
        tbl.rows[r].height = Inches(row_h)
    for r, row in enumerate(rows):
        for c, val in enumerate(row):
            cell = tbl.cell(r, c)
            cell.margin_left = Inches(0.10)
            cell.margin_right = Inches(0.08)
            cell.margin_top = Inches(0.05)
            cell.margin_bottom = Inches(0.04)
            cell.vertical_anchor = MSO_ANCHOR.MIDDLE
            cell.fill.solid()
            if r == 0:
                cell.fill.fore_color.rgb = _rgb(head_fill)
            else:
                cell.fill.fore_color.rgb = alt[(r - 1) % 2]
            tf = cell.text_frame
            tf.word_wrap = True
            p = tf.paragraphs[0]
            p.alignment = PP_ALIGN.LEFT
            p.line_spacing = 1.12
            run = p.add_run()
            run.text = val
            run.font.name = FONT
            run.font.size = Pt(head_size if r == 0 else size)
            run.font.bold = r == 0 or (c == 0)
            run.font.color.rgb = BRASS if r == 0 else (CREAM if c == 0 else MUTED)
    bottom = y + height
    if bottom > 6.9:
        WARNINGS.append(f"table bottom {bottom:.2f} > 6.9 at y={y}")
    return tbl
