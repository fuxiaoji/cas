# -*- coding: utf-8 -*-
"""Structural audit for the generated DOCX and PPTX."""

import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

from docx import Document
from docx.shared import Cm
from pptx import Presentation
from pptx.util import Emu

BASE = r"D:\desktop\cas\docs\product"

print("=" * 60)
print("DOCX")
doc = Document(BASE + r"\CAS-项目企划书-v1.0.docx")
print("tables", len(doc.tables))
bad = 0
for i, t in enumerate(doc.tables):
    w = sum((c.width.cm if c.width else 0) for c in t.rows[0].cells)
    if w > 16.4 or w < 10:
        bad += 1
        print(f"  table {i}: width {w:.2f}cm rows={len(t.rows)}")
print("width problems:", bad)

# longest cell text vs column width (rough)
tight = []
for i, t in enumerate(doc.tables):
    if not t.rows[0].cells[0].width:
        continue
    widths = [c.width.cm for c in t.rows[0].cells]
    for r in t.rows:
        for j, c in enumerate(r.cells):
            txt = c.text
            if not txt:
                continue
            cm = widths[j]
            chars_per_line = main = max(1.0, (cm - 0.34) / 0.317)
            lines = 0
            for part in txt.split("\n"):
                units = sum(1.0 if ord(ch) > 0x2000 else 0.55 for ch in part)
                lines += max(1, int(-(-units // chars_per_line)))
            need = lines * 0.42
            if need > 2.6:
                tight.append((i, j, round(need, 2), txt[:26]))
print("tall cells (>2.6cm):", len(tight))
for x in tight[:10]:
    print("  ", x)

print("=" * 60)
print("PPTX")
prs = Presentation(BASE + r"\CAS-项目提案-v1.0.pptx")
SW, SH = prs.slide_width, prs.slide_height
print("size", SW / 914400, "x", SH / 914400, "slides", len(prs.slides))
for idx, s in enumerate(prs.slides, 1):
    for sh in s.shapes:
        try:
            l, t_, w, h = sh.left, sh.top, sh.width, sh.height
        except Exception:
            continue
        if l is None:
            continue
        if l + w > SW + 9000 or t_ + h > SH + 9000 or l < -9000 or t_ < -9000:
            print(f"  slide {idx}: shape out of bounds L={l/914400:.2f} T={t_/914400:.2f} "
                  f"W={w/914400:.2f} H={h/914400:.2f} :: {sh.shape_type} :: "
                  f"{(sh.text_frame.text[:20] if sh.has_text_frame else '')}")
print("bounds check done")

print("=" * 60)
print("DECK OUTLINE")
for idx, s in enumerate(prs.slides, 1):
    texts = []
    for sh in s.shapes:
        if sh.has_text_frame and sh.text_frame.text.strip():
            texts.append(sh.text_frame.text.strip().replace("\n", " / "))
    print(f"[{idx:02d}] " + " || ".join(texts[:3]))
