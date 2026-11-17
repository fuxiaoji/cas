"""Measure original RGBA atlas cells; never modify the artwork pixels.

The editable JSON stores a visible crop and ground pivot for each original pose.
Standing scale comes from pose zero, so a lying pose stays low and wide instead
of being stretched into a standing character's height.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "godot/assets/tactical/sprites"
OUTPUT = ROOT / "godot/data/tactical-sprite-anchors-v1.json"


def measure(path: Path) -> dict:
    image = Image.open(path).convert("RGBA")
    width, height = image.size
    cell = (width // 4, height // 3)
    frames = []
    for index in range(12):
        origin = ((index % 4) * cell[0], (index // 4) * cell[1])
        alpha = image.crop((*origin, origin[0] + cell[0], origin[1] + cell[1])).getchannel("A")
        mask = alpha.point(lambda a: 255 if a >= 128 else 0)
        box = mask.getbbox()
        if box is None:
            raise ValueError(f"Empty pose {index}: {path}")
        left, top, right, bottom = box
        # The lower silhouette locates boots, independent of a raised weapon.
        foot_band = max(top, bottom - max(5, int((bottom - top) * .1)))
        pixels = mask.load()
        feet = [x for y in range(foot_band, bottom) for x in range(left, right) if pixels[x, y]]
        feet.sort()
        pivot_x = float(feet[len(feet) // 2]) if feet and index < 10 else (left + right) * .5
        frames.append({"bounds": [left, top, right - left, bottom - top], "pivot": [pivot_x, float(bottom)], "cell": [*origin, *cell]})
    return {"sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "cell": list(cell), "reference_height": frames[0]["bounds"][3], "frames": frames}


def main() -> None:
    paths = [ASSETS / f"MCP-{identity}-sheet.png" for identity in ("001", "034", "076", "009", "022")]
    paths.append(ASSETS / "enemy-security-sheet.png")
    result = {"version": "tactical-sprite-anchors-v1", "pixels_modified": False, "source": "Local alpha-silhouette measurement of each original 4x3 cell; editable ground pivots", "atlases": {f"res://assets/tactical/sprites/{path.name}": measure(path) for path in paths}}
    OUTPUT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Measured {len(paths)} atlases / 72 original poses -> {OUTPUT}")


if __name__ == "__main__":
    main()
