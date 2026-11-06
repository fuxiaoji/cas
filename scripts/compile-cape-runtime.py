"""Compile the source-backed Saint George hulls for a restricted RTS variant.

No PDF is edited. The inputs are the separately checked period and scenario
transcriptions; the omissions below are deliberate scenario policy.
"""

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCENARIO = ROOT / "data/campaign/cape-st-george.json"
PERIOD = ROOT / "data/campaign/period/cape-st-george-1943.json"
OUT = ROOT / "data/campaign/period/cape-runtime.json"

GUN = {
    "us_mk30_5in38": ("Mk30 5in/38", 127, "SpCOM"),
    "jp_3rd_yr_127mm50": ("三年式 12.7cm/50", 127, "COM"),
    "jp_3rd_yr_120mm45": ("三年式 12cm/45", 120, "COM"),
}
TORPEDO = {
    "us_mk15_tnt": "Mk15（TNT）",
    "jp_type93_m1_mod1_2": "九三式一型 Mod 1/2",
}
# CAS 5th main PDF 13–14. P&S is one mount with two legal sectors.
ARC = {"F": ([210, 150], None), "A": ([30, 330], None), "P&S": ([30, 150], [210, 330])}
TRANSPORTS = {"amagiri", "yugiri", "uzuki"}


def mount(key, arc, number):
    a, b = ARC[arc]
    return {key: number, "arc": a, "arc2": b}


def compile_data(scenario, period):
    assert scenario["scenario_id"] == period["scenario_id"]
    assert scenario["start"]["date_local"] == period["as_of"]
    assert scenario["troop_transport"]["individual_loads_at_start"] is None
    assert set(next(g for g in scenario["groups"] if g["role"] == "destroyer_transport")["members_in_order"]) == TRANSPORTS
    models = period["weapon_models"]
    ships = []
    fits = {}
    for instance in scenario["ships"]:
        ship_id = instance["id"]
        fit = period["instances"][ship_id]
        profile = period["profiles"][fit["profile"]]
        motion = period["maneuver_classes"][profile["turn_class"]]
        damage_speed = profile["damage_speed_rows_dp_knots"]
        assert profile["armor_rating"] == 0
        assert damage_speed[-1][1] is None
        assert profile["class"] == instance["class"]
        gun_model = profile["main_gun"]
        gun_name, caliber, shell = GUN[gun_model]
        gun_data = models[gun_model]["shells"][shell]
        mounts = [mount("barrels", arc, n) for arc, n in profile["gun_mounts"]]
        gun = {
            "name": f"{gun_name} {shell}", "caliber_mm": caliber,
            "range_yd": [hi for _, hi in gun_data["range_yd"]], "damage": gun_data["damage_dp"],
            "barrels": sum(m["barrels"] for m in mounts), "gs": profile["gunnery_standard"],
            "mounts": mounts, "pen_belt": gun_data["belt"], "pen_deck": gun_data["deck"],
            "armor_piercing": False,  # Selected shells are COM/SpCOM, not AP/SAP.
        }
        rack = profile["torpedo_mounts"]
        torp_model = rack["model"]
        torpedo = None
        if ship_id not in TRANSPORTS:
            torp_data = models[torp_model]["torpedo"]
            yard, knots = torp_data["range_speed_pairs_yd_knots"][0]
            loaded = rack["loaded_tubes_per_mount"]
            assert knots == max(k for _, k in torp_data["range_speed_pairs_yd_knots"])
            torpedo = {
                "name": TORPEDO[torp_model], "speed_knots": knots, "range_yd": yard,
                "warhead": torp_data["damage_dp"], "tubes": sum(loaded), "contact_fuze": True,
                "mounts": [mount("tubes", rack["arc"], n) for n in loaded],
            }
        low, high, brake = profile["accel_decel_knots_per_turn"]
        ships.append({
            "id": ship_id, "name": instance["name"], "side": profile["side"], "kind": profile["kind"],
            "size": profile["size"], "max_knots": damage_speed[0][1], "dp": damage_speed[-1][0],
            "damage_speed": [{"damage": d, "knots": k if k is not None else 0} for d, k in damage_speed],
            "turn_advance_yards": motion["normal_advance_yd"], "speed_loss_knots": motion["normal_loss_knots"],
            "accel_knots_per_turn": low, "accel_high_knots_per_turn": high, "brake_knots_per_turn": brake,
            "armor_belt": 0, "armor_deck": 0, "in_service_year": profile["class_in_service_year"],
            "gun": gun, "torpedo": torpedo,
        })
        fits[ship_id] = {
            "period_profile": fit["profile"], "crew_complement": profile["crew"], "gun_model": gun_model,
            "hull_source": profile["source"], "dated_form10": fit["form10"],
            "gun_annex": models[gun_model]["source"], "gun_shell_rts_selection": shell,
            "radar_confirmed": fit["radar_confirmed"], "radar_candidates_inactive": fit.get("radar_candidates", []),
            "scenario_troops_aboard": None,
            "torpedo_model": torp_model,
            "torpedo_annex": models[torp_model]["source"] if torp_model else None,
            "torpedo_historical_opening_loaded": None,
            "torpedo_variant_opening_loaded": [m["tubes"] for m in torpedo["mounts"]] if torpedo else None,
            "torpedo_fit_loaded_capacity": rack["loaded_tubes_per_mount"],
            "torpedo_fit_reserve_capacity": rack["reserve_per_mount"],
            "torpedo_fit_reload_seconds": rack["reload_seconds"],
            "torpedo_runtime_policy": "initial_annex_capacity_no_reload" if torpedo else "unverified_transport_weapons_unavailable",
        }
    assert len(ships) == 10 and set(fits) == set(period["instances"])
    assert sum(s["torpedo"] is not None for s in ships) == 7
    return {
        "ships": ships,
        "metadata": {
            "schema_version": 1, "content_version": "cas-cape-runtime-v1", "scenario_id": scenario["scenario_id"],
            "period_source_version": period["content_version"], "as_of": period["as_of"],
            "status": "restricted_rts_adaptation_only",
            "source": scenario["source"], "instance_fits": fits,
            "restrictions": [
                "Three transport torpedo launchers are unavailable because exact 0143 cargo and weapon loads are not stated. This is not a historical claim that they carried no torpedoes.",
                "Other ships start with Annex A ready tube capacity, not a documented individual historical inventory. Only fastest shallow setting and contact action run; no reserve reload is simulated. See Annex F for alternative speed settings.",
                "No invented ship lengths: ShipDef length is omitted and the engine's generic clearance floor applies. Crew complement and class first service year are not individual wartime manpower or commissioning dates.",
                "Named profiles leave ammunition mix, Yugiri Type 22, and undocumented night equipment unresolved. Only individually confirmed sets are listed for activation; all candidates stay inactive.",
                "Original column interval, screen anchor for transport offset, map origin, escape line and time limit are unstated. Any chosen values belong in the separate RTS scenario configuration.",
            ],
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify the checked-in data without rewriting it")
    args = parser.parse_args()
    scenario, period = (json.loads(p.read_text(encoding="utf-8")) for p in (SCENARIO, PERIOD))
    compiled = compile_data(scenario, period)
    if args.check:
        assert json.loads(OUT.read_text(encoding="utf-8")) == compiled, "Cape runtime data is stale"
    else:
        OUT.write_text(json.dumps(compiled, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    print("Cape runtime: 10 named hulls, 7 executable tube fits, 3 intentionally unavailable transport torpedo fits")


if __name__ == "__main__":
    main()
