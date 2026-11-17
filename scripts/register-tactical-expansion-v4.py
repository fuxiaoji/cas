"""Register the approved five-identity art handoff without changing source pixels."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/art/tactical-expansion-20261115/asset-ledger.json"


def main():
    ledger = json.loads(SOURCE.read_text(encoding="utf-8-sig"))
    result = {"version": "tactical-expansion-art-v4", "units": {}, "vehicles": {}}
    for unit in ledger["units"]:
        sprite = unit["assets"]["sprite"]
        path = ROOT / "godot" / sprite["path"].removeprefix("res://")
        assert hashlib.sha256(path.read_bytes()).hexdigest() == sprite["sha256"]
        frames = []
        for index, authored in enumerate(sprite["frames"]):
            frame = dict(authored, source=sprite["path"], reference_height=sprite["reference_height"])
            if index == 11:
                x0, y0, x1, y1 = authored["bounds"]
                frame["pivot"] = [(x0+x1)/2, (y0+y1)/2]
            frames.append(frame)
        result["units"][unit["id"]] = {
            "id": unit["id"], "portrait": unit["assets"]["portrait"]["path"],
            "art_status": "approved_original_identity_handoff", "frames": frames,
            "animations": {"idle": [0,1], "walk": [2,3,4,5], "fire": [6,7],
                           "hurt": [8], "search": [9], "fall": [10], "defeated": [11],
                           "deploy": [0], "parachuting": [0]},
            "source_ledger": "docs/art/tactical-expansion-20261115/asset-ledger.json",
            "source_sha256": sprite["sha256"],
        }
        if "vehicle" in unit["assets"]:
            result["vehicles"][unit["id"]] = unit["assets"]["vehicle"]
    target = ROOT / "godot/data/tactical-expansion-art-v4.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({"units": len(result["units"]), "vehicles": len(result["vehicles"]),
                      "source_pixels_modified": False}, ensure_ascii=False))


if __name__ == "__main__":
    main()
