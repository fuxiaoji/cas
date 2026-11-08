"""Rebuild the campaign coastlines from the cached satellite tiles.

The first sampling pass left blocky 36-point outlines. This pass classifies
water/land with numpy, closes the dark-vegetation gaps inside islands, and
traces proper contours with scipy, then simplifies with a 220 m tolerance.
The field anchors come from the digitized Savo landmark (159.82320, -9.13042):
each chart JSON registers the real lonlat of its field origin.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "artifacts/basemap"
META = json.loads((BASE / "basemap-meta.json").read_text(encoding="utf-8"))
TOLERANCE_M = 220.0  # Douglas-Peucker tolerance; keeps bays and points
CLOSE_PX = 3  # morphological closing radius at base resolution


def stitch(name: str):
    meta = META["esperance"]  # one mosaic covers every Iron Bottom chart
    paths = sorted(BASE.glob(f"esperance-10-*.jpg"))
    xs, ys = [], []
    for path in paths:
        _, _, tx, ty = path.stem.split("-")
        xs.append(int(tx))
        ys.append(int(ty))
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    tile = Image.open(paths[0])
    tw, th = tile.size
    canvas = Image.new("RGB", ((x1 - x0 + 1) * tw, (y1 - y0 + 1) * th))
    for path in paths:
        _, _, tx, ty = path.stem.split("-")
        canvas.paste(Image.open(path), ((int(tx) - x0) * tw, (int(ty) - y0) * th))
    mosaic_w, mosaic_h = canvas.size

    def pixel_lonlat(px, py):
        lon = meta["lon_w"] + (px / mosaic_w) * (meta["lon_e"] - meta["lon_w"])
        lat = meta["lat_n"] + (py / mosaic_h) * (meta["lat_s"] - meta["lat_n"])
        return lon, lat

    return canvas, pixel_lonlat


def land_contours(image: Image.Image, min_area_px: int = 900):
    """Return per-island boundary polylines in pixel coordinates."""
    pixels = np.asarray(image).astype(np.int16)
    r, g, b = pixels[..., 0], pixels[..., 1], pixels[..., 2]
    green = g > b + 4
    # Close dark vegetation/shadow gaps inside islands so a single island
    # stays one component; bays narrower than ~2*CLOSE_PX may fill in.
    closed = ndimage.binary_closing(green, structure=np.ones((CLOSE_PX * 2 + 1,) * 2))
    labels, count = ndimage.label(closed)
    contours = []
    for index in range(1, count + 1):
        island = labels == index
        area = int(island.sum())
        if area < min_area_px:
            continue
        eroded = ndimage.binary_erosion(island)
        boundary = np.argwhere(island & ~eroded)
        # Order the boundary by angle around the centroid: robust for the
        # roughly star-shaped islands on this chart.
        cy, cx = boundary.mean(axis=0)
        order = np.argsort(np.arctan2(boundary[:, 0] - cy, boundary[:, 1] - cx))
        contours.append([(int(x), int(y)) for y, x in boundary[order]])
    return contours


SAVO = (159.82320, -9.13042)  # digitized chart landmark, the only reliable anchor


def contour_to_metres(boundary, pixel_lonlat, field):
    """Project a contour into field coordinates.

    Engine convention (matching the digitized chart ingest): x grows east
    from the field's west edge, y grows NORTH from its south edge.
    """
    mx = 111_320 * math.cos(math.radians(field["lat_n"]))
    lat_bottom = field["lat_n"] - field["span_y"] / 110_574
    pts = [((lon - field["lon_w"]) * mx, (lat - lat_bottom) * 110_574)
           for lon, lat in (pixel_lonlat(px, py) for px, py in boundary)]
    return simplify(pts, TOLERANCE_M)


def simplify(points_m, tolerance):
    """Douglas-Peucker in metres."""
    if len(points_m) < 3:
        return points_m
    def perp(p, a, b):
        ax, ay = a; bx, by = b; px, py = p
        dx, dy = bx - ax, by - ay
        length = math.hypot(dx, dy) or 1e-9
        return abs(dx * (py - ay) - dy * (px - ax)) / length
    stack = [(0, len(points_m) - 1)]
    keep = [False] * len(points_m)
    keep[0] = keep[-1] = True
    while stack:
        lo, hi = stack.pop()
        if hi <= lo + 1:
            continue
        worst, index = -1.0, -1
        for i in range(lo + 1, hi):
            d = perp(points_m[i], points_m[lo], points_m[hi])
            if d > worst:
                worst, index = d, i
        if worst > tolerance:
            keep[index] = True
            stack.append((lo, index))
            stack.append((index, hi))
    return [p for p, k in zip(points_m, keep) if k]


def rebuild(span_x: int, span_y: int, anchor: tuple[float, float]):
    """anchor = the real lonlat of this field's origin (x=0, y=0)."""
    field = {"span_x": span_x, "span_y": span_y, "lon_w": anchor[0], "lat_n": anchor[1]}
    image, pixel_lonlat = stitch("esperance")
    contours = land_contours(image)
    islands = []
    for boundary in sorted(contours, key=len, reverse=True)[:12]:
        pts = contour_to_metres(boundary, pixel_lonlat, field)
        if len(pts) < 10:
            continue
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        # Drop contours that only graze this field's corner.
        if max(xs) < 0 or min(xs) > span_x or max(ys) < 0 or min(ys) > span_y:
            continue
        islands.append({
            "points": [[round(x, 1), round(y, 1)] for x, y in pts],
            "vertices": len(pts),
            "centroid_lonlat": pixel_lonlat(*boundary[len(boundary) // 2]),
        })
    # Name by real geography: the largest landmass overlapping the field's
    # south is Guadalcanal; Savo sits within 12 km of its landmark.
    m_per_lon = 111_320 * math.cos(math.radians(field["lat_n"]))
    for island in islands:
        lon, lat = island["centroid_lonlat"]
        island["savo_dist_km"] = math.hypot(
            (lon - SAVO[0]) * m_per_lon / 1000, (lat - SAVO[1]) * 110_574 / 1000)
        xs = [p[0] for p in island["points"]]
        ys = [p[1] for p in island["points"]]
        island["span_km"] = max(max(xs) - min(xs), max(ys) - min(ys)) / 1000
    islands.sort(key=lambda island: -island["span_km"])
    named = []
    for island in islands:
        if island["span_km"] > 20 and island["savo_dist_km"] > 20:
            # Largest is Guadalcanal; the other big ridge east of Savo is
            # the Florida (Nggela) group.
            island["name"] = "florida" if named and "guadalcanal" in [n["name"] for n in named] else "guadalcanal"
        elif island["savo_dist_km"] < 12:
            island["name"] = "savo"
        else:
            continue
        island.pop("centroid_lonlat")
        named.append(island)
    named.sort(key=lambda island: {"guadalcanal": 0, "florida": 1, "savo": 2}[island["name"]])
    return {
        "span_x": span_x, "span_y": span_y,
        "anchor": {"lon_w": anchor[0], "lat_n": anchor[1]},
        "islands": named,
        "source": f"ArcGIS World_Imagery z10 tiles; closing {CLOSE_PX}px; "
                  f"{TOLERANCE_M:.0f} m simplification; anchored on the digitized "
                  "Savo landmark (159.82320, -9.13042)",
    }


def main():
    # Field anchors derived from the digitized Savo landmark: each chart's
    # registered scenario anchor stands at the real island position.
    for key, out, span, anchor in [
        ("esperance", ROOT / "data/campaign/period/chart-esperance.json",
         (76_000, 50_000), (159.5894, -8.8898)),
        ("tassafaronga", ROOT / "data/campaign/period/chart-tassafaronga.json",
         (76_000, 50_000), (159.6902, -8.9029)),
        ("savo", ROOT / "data/campaign/period/chart-savo.json",
         (82_415, 57_500), (159.5834, -8.8969)),
    ]:
        payload = rebuild(span[0], span[1], anchor)
        # The Savo chart also carries the digitized patrol lines, ship
        # silhouettes and transport areas; refresh only the coastlines.
        if key == "savo":
            merged = json.loads((ROOT / "data/campaign/period/chart-savo.json").read_text(encoding="utf-8"))
            merged["islands"] = [{"name": i["name"], "points": i["points"]} for i in payload["islands"]]
            merged["coastline_source"] = payload["source"]
            payload = merged
        out.write_text(json.dumps(payload, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
        print(key, [(i["name"], i.get("vertices", len(i["points"]))) for i in payload["islands"]])


if __name__ == "__main__":
    main()
