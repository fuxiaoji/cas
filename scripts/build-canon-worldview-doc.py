"""Publish the authored v1.1 world bible using the bundled document runtime.

No original DOCX/PDF or live player profile is modified.
"""
from pathlib import Path
import re
from docx import Document
from docx.shared import Cm, Pt, RGBColor
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_CELL_VERTICAL_ALIGNMENT

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/product/CAS_世界观设定_v1.1_正史增补.md"
OUTPUT = ROOT / "docs/product/CAS_世界观设定_v1.1_正史增补.docx"


def configure_font(style, size, bold=False, color="161E24"):
    style.font.name = "Microsoft YaHei"
    style.font.size = Pt(size)
    style.font.bold = bold
    style.font.color.rgb = RGBColor.from_string(color)
    fonts = style.element.get_or_add_rPr().get_or_add_rFonts()
    for kind in ["ascii", "hAnsi", "eastAsia", "cs"]:
        fonts.set(qn("w:" + kind), "Microsoft YaHei")


def clean(text):
    return re.sub(r"`([^`]+)`", r"\1", text).replace("**", "")


def build():
    doc = Document()
    section = doc.sections[0]
    section.page_width, section.page_height = Cm(21), Cm(29.7)
    section.top_margin, section.bottom_margin = Cm(2), Cm(1.9)
    section.left_margin, section.right_margin = Cm(2.1), Cm(2.1)
    section.header_distance, section.footer_distance = Cm(.8), Cm(.8)
    configure_font(doc.styles["Normal"], 10)
    normal = doc.styles["Normal"].paragraph_format
    normal.line_spacing = 1.3
    normal.space_after = Pt(6)
    normal.widow_control = True
    configure_font(doc.styles["Title"], 22, True, "000000")
    configure_font(doc.styles["Heading 1"], 14, True, "000000")
    configure_font(doc.styles["Heading 2"], 11.5, True, "000000")
    for name in ["Title", "Heading 1", "Heading 2"]:
        style = doc.styles[name]
        style.paragraph_format.keep_with_next = True
        style.paragraph_format.space_before = Pt(12 if name != "Title" else 0)
        style.paragraph_format.space_after = Pt(7)
        properties = style.element.find(qn("w:pPr"))
        if properties is not None:
            for border in list(properties.findall(qn("w:pBdr"))):
                properties.remove(border)
    header = section.header.paragraphs[0]
    header.text = "CAS   世界观与三章正史   版本 1.1"
    header.style = doc.styles["Normal"]
    for run in header.runs:
        run.font.size = Pt(8)
        run.font.color.rgb = RGBColor.from_string("65717A")
    footer = section.footer.paragraphs[0]
    footer.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    run = footer.add_run("CAS  世界观修订 1.1     ")
    run.font.size = Pt(8)
    field = OxmlElement("w:fldSimple")
    field.set(qn("w:instr"), "PAGE")
    footer._p.append(field)
    lines = SOURCE.read_text(encoding="utf-8").splitlines()
    index = 0
    while index < len(lines):
        line = lines[index].strip()
        if not line:
            index += 1
            continue
        if line.startswith("|"):
            rows = []
            while index < len(lines) and lines[index].strip().startswith("|"):
                cells = [clean(c.strip()) for c in lines[index].strip().strip("|").split("|")]
                if not all(re.fullmatch(r"[:\-\s]+", c) for c in cells):
                    rows.append(cells)
                index += 1
            table = doc.add_table(rows=1, cols=len(rows[0]))
            table.alignment = WD_TABLE_ALIGNMENT.CENTER
            table.style = "Table Grid"
            table.autofit = False
            for row_index, values in enumerate(rows):
                cells = table.rows[0].cells if row_index == 0 else table.add_row().cells
                for col, text in enumerate(values):
                    cells[col].text = text
                    cells[col].vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
                    for paragraph in cells[col].paragraphs:
                        paragraph.paragraph_format.line_spacing = 1.2
                        paragraph.paragraph_format.space_after = Pt(4)
                        paragraph.paragraph_format.space_before = Pt(4)
                        for run in paragraph.runs:
                            run.font.size = Pt(8.5)
                            run.font.bold = row_index == 0
                row_properties = cells[0]._tc.getparent().get_or_add_trPr()
                no_split = OxmlElement("w:cantSplit")
                row_properties.append(no_split)
                if row_index == 0:
                    repeat = OxmlElement("w:tblHeader")
                    row_properties.append(repeat)
            doc.add_paragraph().paragraph_format.space_after = Pt(0)
            continue
        if line.startswith("# "):
            doc.add_paragraph(clean(line[2:]), "Title")
        elif line.startswith("### "):
            doc.add_paragraph(clean(line[4:]), "Heading 2")
        elif line.startswith("## "):
            doc.add_paragraph(clean(line[3:]), "Heading 1")
        else:
            doc.add_paragraph(clean(line))
        index += 1
    doc.core_properties.title = "CAS 海洋废土世界观与三章正史"
    doc.core_properties.subject = "用户确认的神通流浪战帮主线与密苏里白龙新设"
    doc.core_properties.author = "CAS 项目"
    doc.core_properties.comments = "版本化增补；原始 v1.0 文档只读保留。"
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    doc.save(OUTPUT)
    print(str(OUTPUT))


if __name__ == "__main__":
    build()
