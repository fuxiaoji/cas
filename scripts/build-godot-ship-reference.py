"""Copy verified CAS cards for read-only UI, following ranked_fleets::data order."""
from __future__ import annotations
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ["src/ranked_fleets.rs", "src/ranked_profiles_merged.inc", "data/stage0.json",
           "data/campaign/period/prologue-runtime.json", "data/ships/period-cards.json",
           "data/ships/merged-cards.json"]

def read(path):
    return json.loads((ROOT / path).read_text(encoding="utf-8-sig"))

def build():
    registry = (ROOT / SOURCES[0]).read_text(encoding="utf-8").split("fn profiles()")[0]
    registry += (ROOT / SOURCES[1]).read_text(encoding="utf-8")
    profiles = re.findall(r'Profile\s*\{\s*id:\s*"([^"]+)"\s*,\s*source_class:\s*"([^"]+)"\s*,\s*name:\s*"([^"]+)"\s*,\s*source:\s*"([^"]+)"', registry)
    reference = {}
    for path in SOURCES[2:4]:
        for card in read(path)["ships"]:
            reference.setdefault(card["id"], (card, path))
    period = {row["identity"]: row for row in read(SOURCES[4])}
    merged = {row["identity"]: row for row in read(SOURCES[5])["cards"]}
    output = {}
    for identity, source_class, name, source in profiles:
        record = period.get(identity)
        path, kind = SOURCES[4], "period"
        if record is None:
            record = merged.get(identity)
            path, kind = SOURCES[5], "merged"
        if record is not None:
            assert record.get("period_profile", record.get("class_profile")) == source_class
            if not record.get("stat_verified", False):
                continue
            raw = record["ship"]
        else:
            raw, path = reference[source_class]
            kind = "named" if raw["id"] == identity else "same_class"
        card = dict(raw, id=identity, name=name)
        assert {k:v for k,v in card.items() if k not in {"id", "name"}} == {k:v for k,v in raw.items() if k not in {"id", "name"}}
        output[identity] = {"base": card, "source": source, "source_class": source_class,
                            "source_kind": kind, "source_file": path,
                            "source_pages": record.get("source_pages", {}) if record else {}}
    playable = {row["id"] for row in read("godot/data/ships.json")["ships"] if row.get("playable")}
    assert set(output) == playable, (len(output), len(playable), playable - set(output))
    result = {"version": 1, "scope": "Read-only CAS base cards; no account growth applied.",
              "source_order": "ranked_fleets::data: verified period > verified merged > first prologue/exercise card match",
              "source_hashes": {p: hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in SOURCES},
              "ships": output}
    target = ROOT / "godot/data/ship-reference.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"cards":len(output), "source_fields_unchanged": True, "output": str(target)}))

if __name__ == "__main__":
    build()
