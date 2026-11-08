"""Build the Cape Esperance runtime cards into data/stage0.json.

Sources are the separately verified period packages; the esperance file stores
cross-references (profile_ref / carried_by) rather than full rows, so this
builder resolves them against tassafaronga, kula, cape-st-george and empress.
Run:  python scripts/build_esperance_cards.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
stage_path = ROOT / "data/stage0.json"
stage = json.loads(stage_path.read_text(encoding="utf-8"))
esp = json.loads((ROOT / "data/campaign/period/cape-esperance-1942.json").read_text(encoding="utf-8"))
esp_profiles = esp["profiles"]
SOURCES = {
    "tassafaronga-1942.json": json.loads((ROOT / "data/campaign/period/tassafaronga-1942.json").read_text(encoding="utf-8")),
    "kula-runtime.json": json.loads((ROOT / "data/campaign/period/kula-runtime.json").read_text(encoding="utf-8")),
    "cape-st-george-1943.json": json.loads((ROOT / "data/campaign/period/cape-st-george-1943.json").read_text(encoding="utf-8")),
    "empress-augusta-bay-1943.json": json.loads((ROOT / "data/campaign/period/empress-augusta-bay-1943.json").read_text(encoding="utf-8")),
}

def resolve_ref(file, path):
    node = SOURCES[file]
    for part in path.split("."):
        node = node[part]
    return node

def resolve(profile_name):
    ref = esp_profiles[profile_name]["profile_ref"]
    file, path = ref.split("#")
    return resolve_ref(file, path)

def weapon_models():
    # cross-ref-only entries (no "shells") must not shadow full rows: merge
    # everything first, then let full-row files win.
    full_row_files = ("tassafaronga-1942.json", "cape-st-george-1943.json", "empress-augusta-bay-1943.json")
    merged = {}
    for name in ("cape-esperance-1942.json", "kula-runtime.json", "cape-st-george-1943.json",
                 "empress-augusta-bay-1943.json", "tassafaronga-1942.json"):  # tass last: full rows win
        path = ROOT / "data/campaign/period" / name
        if path.exists():
            merged.update(json.loads(path.read_text(encoding="utf-8")).get("weapon_models", {}))
    # final pass: keep only entries with shells; restore from full files if shadowed
    return merged

WM = weapon_models()

def row(model, shell):
    m = WM[model]
    s = m["shells"][shell]
    ranges = s.get("range_yd")
    if ranges is None:
        table = m["range_yd"]
        ranges = table[shell] if isinstance(table, dict) else table
    return [r[1] for r in ranges], s["belt"], s["deck"], s["damage_dp"]

def gun(model, shell, name, caliber, mounts, barrels, reload=None, ap=True):
    ranges, belt, deck, dmg = row(model, shell)
    return {"name": name, "caliber_mm": caliber, "range_yd": ranges, "damage": dmg,
            "barrels": barrels, "gs": 4, "mounts": mounts, "pen_belt": belt,
            "pen_deck": deck, "armor_piercing": ap,
            **({"reload_seconds": reload} if reload else {})}

def jp_torp():
    kagero = next(s for s in stage["ships"] if s["id"] == "kagero")
    return json.loads(json.dumps(kagero["torpedo"]))

sec_5in38 = gun("us_mk30_5in38", "COM", "Mk11 5in/25", 127,
    [{"barrels": 1, "arc": [200, 340]}, {"barrels": 1, "arc": [200, 340]},
     {"barrels": 1, "arc": [20, 160]}, {"barrels": 1, "arc": [20, 160]}], 4, reload=5, ap=False)
ca8 = gun("us_8in55_mk9_10_11_13_14", "APC", "Mk9 8in/55", 203,
    [{"barrels": 3, "arc": [-150, 150]}, {"barrels": 3, "arc": [-150, 150]},
     {"barrels": 2, "arc": [30, 210]}, {"barrels": 2, "arc": [30, 210]}], 10)
brooklyn6 = gun("us_6in47_mk16", "APC", "Mk16 6in/47", 152.4,
    [{"barrels": 3, "arc": [-150, 150]}, {"barrels": 3, "arc": [-150, 150]},
     {"barrels": 3, "arc": [30, 210]}, {"barrels": 3, "arc": [30, 210]}], 15, reload=10)
jp20 = gun("jp_20cm50_3rd_yr_type_no2", "APC", "三年式 No.2 20cm/50", 203,
    [{"barrels": 3, "arc": [-150, 150]}, {"barrels": 3, "arc": [-150, 150]},
     {"barrels": 2, "arc": [30, 210]}], 8)

cards = []
def add(pid, name, side, kind, size, profile_src, profile_key, gun_def, secondary, torp, length):
    pr = resolve_ref(profile_src, "profiles." + profile_key) if profile_src else esp_profiles[profile_key]
    rows = [{"damage": d, "knots": k} for d, k in pr["damage_speed_rows_dp_knots"] if k != "Sunk"]
    belt, deck = (str(pr["armor_rating"]).split("/") + ["0"])[:2]
    cards.append({
        "id": pid, "name": name, "side": side, "kind": kind, "size": size,
        "max_knots": rows[0]["knots"], "dp": pr["damage_speed_rows_dp_knots"][-1][0],
        "damage_speed": rows, "engineering_speed_multiplier": None,
        "turn_advance_yards": 300. if size != "C" else 400., "speed_loss_knots": 2.,
        "accel_knots_per_turn": 10. if size != "C" else 12.,
        "gun": gun_def, "secondary": secondary, "torpedo": torp, "length_m": length,
        "armor_belt": float(belt), "armor_deck": float(deck), "torpedo_protection_dp": 0.,
        "in_service_year": pr["class_in_service_year"],
        "accel_high_knots_per_turn": 5. if size != "C" else 6.,
        "brake_knots_per_turn": 12. if size != "C" else 15.,
    })

add("new_orleans_1942", "新奥尔良级", "allies", "CA", "B", "tassafaronga-1942.json", "new_orleans_1942", ca8, sec_5in38, None, 179.)
add("northampton_1942", "北安普顿级", "allies", "CA", "B", "tassafaronga-1942.json", "pensacola_1942", ca8, sec_5in38, None, 183.)
add("salt_lake_city_1942", "盐湖城", "allies", "CA", "B", "tassafaronga-1942.json", "pensacola_1942", ca8, sec_5in38, None, 178.)
_bk = resolve_ref("kula-runtime.json", "profiles.brooklyn_2")
cards.append({
    "id": "brooklyn_second_group_1942", "name": "布鲁克林级（后批）",
    "side": "allies", "kind": "CL", "size": "B",
    "max_knots": _bk["max_knots"], "dp": _bk["dp"], "damage_speed": _bk["damage_speed"],
    "engineering_speed_multiplier": None,
    "turn_advance_yards": _bk["turn_advance_yards"], "speed_loss_knots": _bk["speed_loss_knots"],
    "accel_knots_per_turn": _bk["accel_knots_per_turn"],
    "gun": brooklyn6, "secondary": sec_5in38, "torpedo": None, "length_m": 185.,
    "armor_belt": _bk["armor_belt"], "armor_deck": _bk["armor_deck"], "torpedo_protection_dp": 0.,
    "in_service_year": _bk["in_service_year"],
    "accel_high_knots_per_turn": _bk["accel_high_knots_per_turn"],
    "brake_knots_per_turn": _bk["brake_knots_per_turn"],
})
add("aoba_1938", "青叶级", "axis", "CA", "B", None, "aoba_1938", jp20, None, jp_torp(), 185.)
add("kinugasa_1938", "衣笠", "axis", "CA", "B", None, "aoba_1938", jp20, None, jp_torp(), 185.)
add("furutaka_1937", "古鹰级", "axis", "CA", "B", None, "furutaka_1937", jp20, None, jp_torp(), 185.)

kagero = next(s for s in stage["ships"] if s["id"] == "kagero")
fubuki_pr = resolve("fubuki_1936_refit")
fubuki_gun = json.loads(json.dumps(kagero["gun"]))
fubuki_gun["mounts"] = [{"barrels": 2, "arc": [-150, 150]},
                        {"barrels": 2, "arc": [30, 210]}, {"barrels": 2, "arc": [30, 210]}]
rows = [{"damage": d, "knots": k} for d, k in fubuki_pr["damage_speed_rows_dp_knots"] if k != "Sunk"]
cards.append({
    "id": "fubuki_1936_refit", "name": "吹雪级（改装）", "side": "axis", "kind": "DD", "size": "C",
    "max_knots": rows[0]["knots"], "dp": fubuki_pr["damage_speed_rows_dp_knots"][-1][0],
    "damage_speed": rows, "engineering_speed_multiplier": None,
    "turn_advance_yards": 400., "speed_loss_knots": 2.,
    "accel_knots_per_turn": 12., "gun": fubuki_gun, "secondary": None,
    "torpedo": json.loads(json.dumps(kagero["torpedo"])), "length_m": 118.,
    "armor_belt": 0., "armor_deck": 0., "torpedo_protection_dp": 0.,
    "in_service_year": fubuki_pr["class_in_service_year"],
    "accel_high_knots_per_turn": 6., "brake_knots_per_turn": 15.,
})

ids = {s["id"] for s in stage["ships"]}
added = [c["id"] for c in cards if c["id"] not in ids]
for c in cards:
    if c["id"] not in ids:
        stage["ships"].append(c)
stage_path.write_text(json.dumps(stage, ensure_ascii=False, indent=1) + chr(10), encoding="utf-8")
print("added", added)
