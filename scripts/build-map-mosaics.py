"""Stitch the cached satellite tiles into the client chart underlay.

One mosaic covers the Iron Bottom Sound charts (Savo, Cape Esperance,
Tassafaronga). The geographic bounds in the manifest let the client align the
image with the engine field using each scenario's registered north-west
anchor.
"""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "artifacts/basemap"
OUT = ROOT / "client/public/maps"
META = json.loads((BASE / "basemap-meta.json").read_text(encoding="utf-8"))["esperance"]
UPSCALE = 1.5


def main():
    paths = sorted(BASE.glob("esperance-10-*.jpg"))
    xs, ys = set(), set()
    for path in paths:
        _, _, tx, ty = path.stem.split("-")
        xs.add(int(tx))
        ys.add(int(ty))
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    tile = Image.open(paths[0])
    tw, th = tile.size
    canvas = Image.new("RGB", ((x1 - x0 + 1) * tw, (y1 - y0 + 1) * th))
    for path in paths:
        _, _, tx, ty = path.stem.split("-")
        canvas.paste(Image.open(path), ((int(tx) - x0) * tw, (int(ty) - y0) * th))
    canvas = canvas.resize((int(canvas.width * UPSCALE), int(canvas.height * UPSCALE)), Image.LANCZOS)
    OUT.mkdir(parents=True, exist_ok=True)
    canvas.save(OUT / "ironbottom.jpg", "JPEG", quality=82, optimize=True)
    manifest = {
        "source": "ArcGIS World_Imagery z10 tiles cached in artifacts/basemap",
        "image": "ironbottom.jpg",
        "lon_w": META["lon_w"], "lon_e": META["lon_e"],
        "lat_n": META["lat_n"], "lat_s": META["lat_s"],
        "width": canvas.width, "height": canvas.height,
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8", newline="\n")
    print(f"ironbottom.jpg {canvas.size} covering lon {META['lon_w']}..{META['lon_e']} "
          f"lat {META['lat_s']}..{META['lat_n']}")


if __name__ == "__main__":
    main()
