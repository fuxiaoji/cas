"""Project the digitized Savo chart into engine metres without adding ships."""
import json, math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "data/campaign/period/savo-chart-digitized.json"
OUT = ROOT / "data/campaign/period/chart-savo.json"
data = json.loads(SRC.read_text(encoding="utf-8"))
ext = data["chart"]["extent"]
lat0 = (ext["north"] + ext["south"]) / 2
mx = 111_320 * math.cos(math.radians(lat0))
my = 110_574
def project(lon, lat):
    return [round((lon - ext["west"]) * mx, 1), round((lat - ext["south"]) * my, 1)]
lines = []
for line in data["patrol_lines"]:
    lines.append({"name": line["name"], "kind": line["kind"],
                  "points": [project(*p) for p in line["lonlat"]],
                  "confidence": line.get("confidence")})
ships = []
for ship in data["ships"]:
    ships.append({**ship, "engine": project(*ship["lonlat"])})
areas = []
for area in data["transport_areas"]:
    areas.append({"name": area["name"], "points": [project(*p) for p in area["lonlat"]],
                  "center": project(*area["center_lonlat"]), "confidence": area.get("confidence")})
marks = [{**m, "engine": project(*m["lonlat"])} for m in data["landmarks"]]
payload = {"schema_version": 1, "source": "savo-chart-digitized.json",
           "extent": ext, "meters_per_degree": [mx, my],
           "field": [round((ext["east"] - ext["west"]) * mx, 1), round((ext["north"] - ext["south"]) * my, 1)],
           "patrol_lines": lines, "ships": ships, "transport_areas": areas, "landmarks": marks,
           "japanese_arrow": {**data["japanese_arrow"],
               "start_engine": project(*data["japanese_arrow"]["start_lonlat"]),
               "end_engine": project(*data["japanese_arrow"]["end_lonlat"])},
           "unreadable": data.get("unreadable", [])}
OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
print(f"Savo chart: {len(lines)} lines, {len(ships)} ships, {len(areas)} transport areas, "
      f"{len(marks)} landmarks, field {payload['field']}")
