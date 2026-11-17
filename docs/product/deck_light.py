# -*- coding: utf-8 -*-
"""Light 'report' slide kit for the course-assignment deck."""

from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.util import Inches, Pt

FONT = "微软雅黑"
NUM = "Georgia"

PAPER = RGBColor(0xF7, 0xF5, 0xEF)
INK = RGBColor(0x1B, 0x20, 0x26)
MUTED = RGBColor(0x6E, 0x76, 0x7E)
ACCENT = RGBColor(0xB4, 0x46, 0x2C)
SLATE = RGBColor(0x2E, 0x46, 0x58)
RULE = RGBColor(0xD6, 0xD0, 0xC2)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
WASH = RGBColor(0xEF, 0xEB, 0xDF)
WASH2 = RGBColor(0xE7, 0xE1, 0xD2)

M = 0.90
CONTENT_W = 13.333 - 2 * M

WARNINGS = []


def new_slide(prs):
    s = prs.slides.add_slide(prs.slide_layouts[6])
    bg = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, prs.slide_width, prs.slide_height)
    bg.fill.solid()
    bg.fill.fore_color.rgb = PAPER
    bg.line.fill.background()
    bg.shadow.inherit = False
    return s


def rect(slide, x, y, w, h, fill=None, line=None, line_w=0.75):
    sh = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(h))
    style = sh._element.find("{http://schemas.openxmlformats.org/presentationml/2006/main}style")
    if style is not None:
        sh._element.remove(style)
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


def _hang(p, marl=0.26):
    pPr = p._p.get_or_add_pPr()
    pPr.set("marL", str(int(marl * 914400)))
    pPr.set("indent", str(int(-marl * 914400)))


def text(slide, x, y, w, h, s, size=13, color=INK, bold=False, font=FONT,
         align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP, spacing=1.22, space_after=0,
         italic=False):
    tb = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = tb.text_frame
    tf.word_wrap = True
    tf.vertical_anchor = anchor
    tf.margin_left = 0
    tf.margin_right = 0
    tf.margin_top = 0
    tf.margin_bottom = 0
    for i, line in enumerate(s.split("\n")):
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
    return tb


def kicker(slide, s):
    text(slide, M, 0.50, CONTENT_W, 0.22, s, size=9.5, color=ACCENT, bold=True)


def title(slide, s, size=27, y=0.80, h=0.9, color=INK):
    text(slide, M, y, CONTENT_W, h, s, size=size, color=color, bold=True, spacing=1.12)


def rule(slide, y=1.66, width=1.3, color=RULE):
    rect(slide, M, y, CONTENT_W, 0.010, fill=color)
    rect(slide, M, y, width, 0.010, fill=ACCENT)


def footer(slide, n, total=20):
    text(slide, M, 7.02, 8.4, 0.2, "企业商业化　·　课程大作业　·　二游商业模型",
         size=8, color=RGBColor(0x9A, 0x9F, 0xA4))
    text(slide, 13.333 - M - 1.1, 7.02, 1.1, 0.2, f"{n:02d}", size=8.5,
         color=RGBColor(0x9A, 0x9F, 0xA4), align=PP_ALIGN.RIGHT, font=NUM)


def bullets(slide, x, y, w, items, size=12, color=INK, mark_color=ACCENT,
            gap=0.12, spacing=1.30, marker="▪  "):
    tb = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(0.4))
    tf = tb.text_frame
    tf.word_wrap = True
    for m in ("margin_left", "margin_right", "margin_top", "margin_bottom"):
        setattr(tf, m, 0)
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
        r.font.bold = True
        r.font.color.rgb = mark_color
        if isinstance(item, tuple):
            lead, rest = item
            for chunk, col, bold in ((lead, color, True), (rest, MUTED, False)):
                r = p.add_run()
                r.text = chunk
                r.font.name = FONT
                r.font.size = Pt(size)
                r.font.bold = bold
                r.font.color.rgb = col
        else:
            r = p.add_run()
            r.text = item
            r.font.name = FONT
            r.font.size = Pt(size)
            r.font.color.rgb = color
    return tb


def table(slide, x, y, w, col_ratios, rows, size=10, head_size=9.5,
          row_h=0.42, head_h=0.34):
    nrows, ncols = len(rows), len(rows[0])
    height = head_h + row_h * (nrows - 1) + 0.06
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
            cell.margin_left = Inches(0.09)
            cell.margin_right = Inches(0.07)
            cell.margin_top = Inches(0.04)
            cell.margin_bottom = Inches(0.03)
            cell.vertical_anchor = MSO_ANCHOR.MIDDLE
            cell.fill.solid()
            if r == 0:
                cell.fill.fore_color.rgb = INK
            else:
                cell.fill.fore_color.rgb = WHITE if (r - 1) % 2 == 0 else RGBColor(0xF1, 0xED, 0xE2)
            p = cell.text_frame.paragraphs[0]
            p.alignment = PP_ALIGN.LEFT
            p.line_spacing = 1.10
            cell.text_frame.word_wrap = True
            run = p.add_run()
            run.text = val
            run.font.name = FONT
            run.font.size = Pt(head_size if r == 0 else size)
            run.font.bold = r == 0 or (c == 0)
            run.font.color.rgb = PAPER if r == 0 else (INK if c == 0 else MUTED)
    if y + height > 6.95:
        WARNINGS.append(f"table bottom {y + height:.2f} > 6.95")
    return tbl
