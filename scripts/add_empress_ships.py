"""One-off: add the Empress Augusta Bay ship classes to the exercise data."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
stage_path = ROOT / "data/stage0.json"
stage = json.loads(stage_path.read_text(encoding="utf-8"))
period = json.loads((ROOT / "data/campaign/period/empress-augusta-bay-1943.json").read_text(encoding="utf-8"))
wm = period["weapon_models"]
tass = json.loads((ROOT / "data/campaign/period/tassafaronga-1942.json").read_text(encoding="utf-8"))
wm["us_6in47_mk16"] = tass["weapon_models"]["us_6in47_mk16"]
profiles = period["profiles"]


def gun_from(model, shell, name, caliber, mounts, barrels, director=None, reload=None, ap=True):
    m = wm[model]
    s = m["shells"][shell]
    ranges = s.get("range_yd")
    if ranges is None:
        table = m["range_yd"]
        ranges = table[shell] if isinstance(table, dict) else table
    return {
        "name": name, "caliber_mm": caliber, "range_yd": [r[1] for r in ranges],
        "damage": s["damage_dp"], "barrels": barrels, "gs": 4, "mounts": mounts,
        "pen_belt": s["belt"], "pen_deck": s["deck"], "armor_piercing": ap,
        **({"director_arc": director} if director else {}),
        **({"reload_seconds": reload} if reload else {}),
    }


kagero = next(s for s in stage["ships"] if s["id"] == "kagero")["torpedo"]


def torpedo(tubes, per_mount, reserve, reload):
    return {
        "name": kagero["name"], "speed_knots": kagero["speed_knots"], "range_yd": kagero["range_yd"],
        "warhead": kagero["warhead"], "warhead_kg": kagero["warhead_kg"], "depth": kagero["depth"],
        "contact_fuze": True, "tubes": tubes,
        "mounts": [{"tubes": t, "arc": [30, 150], "arc2": [210, 330], "reserve": reserve} for t in per_mount],
        "reload_seconds": reload, "source": kagero["source"],
    }


new = []


def add(pid, name, side, kind, size, profile, gun, secondary, torp, length, accel):
    pr = profiles[profile]
    rows = [{"damage": d, "knots": k} for d, k in pr["damage_speed_rows_dp_knots"] if k != "Sunk"]
    new.append({
        "id": pid, "name": name, "side": side, "kind": kind, "size": size,
        "max_knots": rows[0]["knots"], "dp": pr["damage_speed_rows_dp_knots"][-1][0],
        "damage_speed": rows, "engineering_speed_multiplier": None,
        "turn_advance_yards": 300. if size != "C" else 400., "speed_loss_knots": 2.,
        "accel_knots_per_turn": accel[0], "gun": gun, "secondary": secondary, "torpedo": torp,
        "length_m": length,
        "armor_belt": float(pr["armor_rating"].split("/")[0]),
        "armor_deck": float(pr["armor_rating"].split("/")[1]) if "/" in pr["armor_rating"] else 0.,
        "torpedo_protection_dp": 0.,
        "in_service_year": pr["class_in_service_year"],
        "accel_high_knots_per_turn": accel[1], "brake_knots_per_turn": accel[2],
    })


cleveland_gun = gun_from(
    "us_6in47_mk16", "APC", "Mk16 6in/47", 152.4,
    [{"barrels": 3, "arc": [-150, 150]}, {"barrels": 3, "arc": [-150, 150]},
     {"barrels": 3, "arc": [30, 210]}, {"barrels": 3, "arc": [30, 210]}], 12)
sec_5in = gun_from(
    "us_mk30_5in38", "COM", "Mk32 5in/38", 127,
    [{"barrels": 2, "arc": [300, 60]}, {"barrels": 2, "arc": [200, 340]},
     {"barrels": 2, "arc": [200, 340]}, {"barrels": 2, "arc": [20, 160]},
     {"barrels": 2, "arc": [20, 160]}, {"barrels": 2, "arc": [120, 240]}], 12, reload=4)
add("cleveland", "克利夫兰级", "allies", "CL", "B", "cleveland_1943", cleveland_gun, sec_5in, None, 185., [10., 5., 12.])

myoko_gun = gun_from(
    "jp_20cm50_3rd_yr_type_no2", "APC", "三年式 No.2 20cm/50", 203,
    [{"barrels": 2, "arc": [-150, 150]}, {"barrels": 2, "arc": [-150, 150]},
     {"barrels": 2, "arc": [30, 150]}, {"barrels": 2, "arc": [210, 330]},
     {"barrels": 2, "arc": [30, 210]}], 10)
myoko_sec = gun_from(
    "jp_type89_12_7cm40", "COM", "八九式 12.7cm/40", 127,
    [{"barrels": 2, "arc": [200, 340]}, {"barrels": 2, "arc": [200, 340]},
     {"barrels": 2, "arc": [20, 160]}, {"barrels": 2, "arc": [20, 160]}], 8, reload=4)
add("myoko", "妙高级", "axis", "CA", "B", "myoko_1940", myoko_gun, myoko_sec,
    torpedo(8, [4, 4], 4, 360), 203., [10., 5., 12.])

agano_gun = gun_from(
    "jp_41st_yr_15cm50", "COM", "四一式 15cm/50", 152,
    [{"barrels": 2, "arc": [-150, 150]}, {"barrels": 2, "arc": [-150, 150]},
     {"barrels": 2, "arc": [30, 210]}], 6, director=[-150, 150])
agano_sec = gun_from(
    "jp_type98_8cm60", "COM", "九八式 8cm/60", 76,
    [{"barrels": 2, "arc": [200, 340]}, {"barrels": 2, "arc": [20, 160]}], 4, reload=3)
add("agano", "阿贺野级", "axis", "CL", "B", "agano_1943", agano_gun, agano_sec,
    torpedo(8, [4, 4], 0, None), 174., [10., 5., 12.])

shira_gun = gun_from(
    "jp_3rd_yr_127mm50", "COM", "三年式 12.7cm/50", 127,
    [{"barrels": 1, "arc": [-150, 150]}, {"barrels": 1, "arc": [30, 210]},
     {"barrels": 1, "arc": [200, 340]}, {"barrels": 1, "arc": [20, 160]},
     {"barrels": 1, "arc": [300, 60]}], 5, director=[-150, 150])
add("shiratsuyu", "白露级", "axis", "DD", "C", "shiratsuyu_1943", shira_gun, None,
    torpedo(8, [4, 4], 4, 360), 107.5, [12., 6., 15.])

yugumo_gun = gun_from(
    "jp_3rd_yr_127mm50", "COM", "三年式 12.7cm/50", 127,
    [{"barrels": 2, "arc": [-150, 150]}, {"barrels": 2, "arc": [30, 210]},
     {"barrels": 2, "arc": [30, 210]}], 6, director=[-150, 150])
add("yugumo", "夕云级", "axis", "DD", "C", "yugumo_1943", yugumo_gun, None,
    torpedo(8, [4, 4], 4, 360), 119., [12., 6., 15.])

akizuki_gun = gun_from(
    "jp_type98_10cm65", "COM", "九八式 10cm/65", 100,
    [{"barrels": 2, "arc": [-150, 150]}, {"barrels": 2, "arc": [-150, 150]},
     {"barrels": 2, "arc": [30, 210]}, {"barrels": 2, "arc": [30, 210]}], 8,
    director=[-150, 150])
add("akizuki", "秋月级", "axis", "DD", "C", "akizuki_1943", akizuki_gun, None,
    torpedo(4, [4], 4, 360), 134., [12., 6., 15.])

ids = {s["id"] for s in stage["ships"]}
added = []
for ship in new:
    if ship["id"] not in ids:
        stage["ships"].append(ship)
        added.append(ship["id"])
stage_path.write_text(json.dumps(stage, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
print("added", added)
