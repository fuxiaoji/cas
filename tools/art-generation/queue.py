"""Read-only queue for root/tooling_art's non-overlapping identity allocation."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "godot/data/ships.json"
cards = json.loads(CATALOG.read_text(encoding="utf-8"))["ships"]
batch = []
produced = 0
for i, row in enumerate(cards):
    image = ROOT / "godot/assets/characters/chibis-generated" / (row["id"].lower()+".png")
    if image.is_file():
        produced += 1
        continue
    if i > 69:  # tooling_art owns inclusive catalogue indices 0..69 only
        continue
    batch.append({"id":row["id"], "name":row["name"], "type":row["type"],
                  "portrait":str(ROOT/"godot"/row["portrait"].removeprefix("res://"))})
print(json.dumps({"produced":produced, "remaining":210-produced, "assigned_remaining":len(batch), "batch":batch[:6]},ensure_ascii=True))
