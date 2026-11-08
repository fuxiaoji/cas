"""Compile the checked Tassafaronga named hulls into the campaign runtime."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PERIOD = ROOT / "data/campaign/period/tassafaronga-1942.json"
OUT = ROOT / "data/campaign/period/tassafaronga-runtime.json"
NAMES = {
    "minneapolis": "明尼阿波利斯", "new_orleans": "新奥尔良", "pensacola": "彭萨科拉",
    "northampton": "北安普敦", "honolulu": "火奴鲁鲁", "fletcher": "弗莱彻",
    "perkins": "帕金斯", "maury": "莫里", "drayton": "德雷顿", "lamson": "拉姆森",
    "lardner": "拉德纳", "naganami": "长波", "makinami": "卷波", "takanami": "高波",
    "oyashio": "亲潮", "kuroshio": "黑潮", "kagero": "阳炎", "kawakaze": "川风",
    "suzukaze": "凉风",
}
GUN = {
    "us_8in55_mk9_10_11_13_14": ("Mk9/14 8in/55", 203, "APC"),
    "us_6in47_mk16": ("Mk16 6in/47", 152, "APC"),
    "us_mk30_5in38": ("Mk30 5in/38", 127, "SpCOM"),
    "jp_3rd_yr_127mm50": ("三年式 12.7cm/50", 127, "COM"),
}
ARC = {"F": ([210, 150], None), "A": ([30, 330], None), "P&S": ([30, 150], [210, 330])}
# Source rule: six drum-carrying destroyers have no torpedo reloads.
NO_RELOAD = {"makinami", "oyashio", "kuroshio", "kagero", "kawakaze", "suzukaze"}
GRIDLEY_MOUNTS = [["F", 1], ["F", 1], ["A", 1], ["A", 1]]


def mount(key, arc, number):
    a, b = ARC[arc]
    return {key: number, "arc": a, "arc2": b}


def armor(text):
    if not text or text == 0:
        return 0, 0
    belt, deck = str(text).split("/")
    return int(belt), int(deck)


def compile_data(period):
    models = period["weapon_models"]
    ships = []
    for instance in period["named_ships"]:
        profile_name = instance["profile"]
        profile = period["profiles"][profile_name]
        if "profile_ref" in profile and "damage_speed_rows_dp_knots" not in profile:
            ref = profile["profile_ref"]
            if ref.startswith("#"):
                profile = period["profiles"][ref[1:]]
        ship = instance["id"]
        gun_model = profile["main_gun"]
        gun_name, caliber, shell = GUN[gun_model]
        data = models[gun_model]["shells"][shell]
        ranges = data.get("range_yd")
        if ranges is None:
            ranges = models[gun_model].get("range_yd")
        if isinstance(ranges, dict):
            ranges = ranges[shell]
        ranges = [hi for _, hi in ranges]
        mounts = profile.get("gun_mounts")
        note = None
        if mounts is None and profile_name == "gridley_1942":
            mounts = GRIDLEY_MOUNTS
            note = "Gridley 'F/A(1)4' adopted as four single mounts F/F/A/A (registered RTS reading)."
        assert mounts, ship
        gun = {"name": f"{gun_name} {shell}", "caliber_mm": caliber, "range_yd": ranges,
               "damage": data["damage_dp"], "barrels": sum(n for _, n in mounts),
               "gs": profile["gunnery_standard"],
               "mounts": [mount("barrels", arc, n) for arc, n in mounts],
               "pen_belt": data["belt"], "pen_deck": data["deck"],
               "armor_piercing": shell in ("APC", "SpCOM")}
        rack = profile.get("torpedo_mounts")
        torpedo = None
        if rack and rack.get("model"):
            torp = models[rack["model"]]["torpedo"]
            yard, knots = torp["range_speed_pairs_yd_knots"][0]
            loaded = rack["loaded_tubes_per_mount"]
            reserve = [0] * len(loaded) if ship in NO_RELOAD else list(rack.get("reserve_per_mount") or [0] * len(loaded))
            torpedo = {"name": "九三式一型 Mod 1/2" if rack["model"].startswith("jp_") else "Mk15（TNT）",
                       "speed_knots": knots, "range_yd": yard, "warhead": torp["damage_dp"],
                       "tubes": sum(loaded), "contact_fuze": True,
                       "mounts": [{**mount("tubes", rack["arc"], n), "reserve": reserve[i]}
                                  for i, n in enumerate(loaded)],
                       "reload_seconds": rack.get("reload_seconds")}
        belt, deck = armor(profile.get("armor_rating"))
        low, high, brake = profile["accel_decel_knots_per_turn"]
        damage_speed = profile["damage_speed_rows_dp_knots"]
        ships.append({
            "id": "tass_" + ship, "name": NAMES[ship], "side": profile["side"], "kind": profile["kind"],
            "size": profile["size"], "max_knots": damage_speed[0][1], "dp": damage_speed[-1][0],
            "damage_speed": [{"damage": d, "knots": k or 0} for d, k in damage_speed],
            "turn_advance_yards": 300 if profile["turn_class"] == "B" else 250,
            "speed_loss_knots": 3 if profile["turn_class"] == "B" else 4,
            "accel_knots_per_turn": low, "accel_high_knots_per_turn": high, "brake_knots_per_turn": brake,
            "armor_belt": belt, "armor_deck": deck, "in_service_year": profile["class_in_service_year"],
            "gun": gun, "torpedo": torpedo,
            "source_class": profile_name,
            "gun_note": note,
        })
    assert len(ships) == 19
    return {"ships": ships, "metadata": {
        "content_version": "cas-tassafaronga-runtime-v1",
        "scenario_id": "cas-rs-tassafaronga",
        "as_of": period["as_of"],
        "status": "restricted_rts_adaptation_only",
        "policy": period["policy"],
        "restrictions": [
            "Shell selections: 8in APC, 6in APC, 5in SpCOM, 12.7cm COM. The source leaves per-ship loadouts unresolved.",
            "Gridley 'F/A(1)4' adopted as four single mounts.",
            "Only Naganami and Takanami keep torpedo reloads; the six drum carriers start with zero reserve.",
            "Resupply-point coordinates are an RTS chart registration, not printed values.",
        ],
    }}


if __name__ == "__main__":
    period = json.loads(PERIOD.read_text(encoding="utf-8"))
    OUT.write_text(json.dumps(compile_data(period), ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print("Tassafaronga runtime: 19 named hulls")
