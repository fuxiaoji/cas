"""Compile eight named hulls for the restricted IBS-S-03 CAS adaptation."""

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LAYOUT = ROOT / "data/campaign/legacy/channel-action.json"
OUTPUT = ROOT / "data/campaign/period/channel-runtime.json"
HOME = "Home_Fleet_2012_Standard.pdf"
ARCTIC = "Arctic_Fleets_5th_ed._Standard.pdf"
NORD = "（德国海军）Gruppe_Nord_2012_Standard-onlyTrans.pdf"
Z20_RECOGNITION = "https://www.ibiblio.org/hyperwar/USN/ref/ONI/ONI-204/img/ONI-204-96.JPG"


def src(file, page, table):
    return {"document": file, "pdf_page": page, "table": table}


ARC = {"F": ([210, 150], None), "A": ([30, 330], None),
       "P&S": ([30, 150], [210, 330]), "A20": ([30, 170], [190, 330])}
HULLS = {
    "de_1934_34a_1940": dict(dp=[0, 37, 73, 110, 131, 146], speed=[38, 28, 19, 10, 0, 0],
                            year=1937, crew=315, source=src(NORD, 66, "A-11 Type 1934 (Z1–Z16)")),
    "de_1936_1940": dict(dp=[0, 38, 77, 115, 138, 153], speed=[38, 29, 19, 10, 0, 0],
                        year=1938, crew=313, source=src(NORD, 66, "A-11 Type 1936 (Z17–Z22)")),
    "gb_jk_1940": dict(dp=[0, 30, 61, 91, 109, 121], speed=[36, 27, 18, 9, 0, 0],
                       year=1939, crew=183, source=src(HOME, 40, "A-36 J/K/N")),
}
FITS = {
    "IBS-U-KM-KARL-GALSTER": ("Z20 Karl Galster", "Type 1936", "de_1936_1940"),
    "IBS-U-KM-RICHARD-BEITZEN": ("Z4 Richard Beitzen", "Type 1934", "de_1934_34a_1940"),
    "IBS-U-KM-HANS-LODY": ("Z10 Hans Lody", "Type 1934A", "de_1934_34a_1940"),
    "IBS-U-RN-JAVELIN": ("HMS Javelin", "J", "gb_jk_1940"),
    "IBS-U-RN-JUPITER": ("HMS Jupiter", "J", "gb_jk_1940"),
    "IBS-U-RN-KASHMIR": ("HMS Kashmir", "K", "gb_jk_1940"),
    "IBS-U-RN-JACKAL": ("HMS Jackal", "J", "gb_jk_1940"),
    "IBS-U-RN-JERSEY": ("HMS Jersey", "J", "gb_jk_1940"),
}


def mount(key, count, position):
    arc, arc2 = ARC[position]
    return {key: count, "arc": arc, "arc2": arc2}


def compile_data(layout):
    assert layout["ibs_id"] == "IBS-S-03" and layout["date"] == "1940-11-28"
    assert len(layout["ships"]) == 8 and {s["ibs_ship_id"] for s in layout["ships"]} == FITS.keys()
    ships, fits = [], {}
    for placement in layout["ships"]:
        sid = placement["ibs_ship_id"]
        name, ship_class, profile = FITS[sid]
        hull = HULLS[profile]
        british = profile == "gb_jk_1940"
        assert placement["side"] == ("allies" if british else "axis")
        mount_plan = [(2, "F"), (2, "F"), (2, "A20")] if british else [(1, p) for p in ("F", "F", "P&S", "A", "A")]
        tubes = 5 if british else 4
        gun = {
            "name": "4.7in/45 Mk XII HE" if british else "12.7cm/45 SK C/34 HE",
            "caliber_mm": 4.7 * 25.4 if british else 127,
            "range_yd": [5100, 10200, 13600, 17000] if british else [5700, 11400, 15200, 19000],
            "damage": [18, 15, 14, 12] if british else [19, 16, 14, 13],
            "barrels": sum(c for c, _ in mount_plan), "gs": 4,
            "mounts": [mount("barrels", c, p) for c, p in mount_plan],
            "pen_belt": [1, 1, 1, 0] if british else [2, 1, 1, 1],
            "pen_deck": [None, None, 0, 1], "armor_piercing": False,
        }
        torpedo = {
            "name": "21in Mk IX" if british else "G7a (T-I)",
            "speed_knots": 41 if british else 44, "range_yd": 11000 if british else 6500,
            "warhead": 84 if british else 88, "tubes": tubes * 2,
            "contact_fuze": True, "mounts": [mount("tubes", tubes, "P&S") for _ in range(2)],
        }
        ships.append({
            "id": sid, "name": placement["name"], "side": placement["side"], "kind": "DD", "size": "C",
            "max_knots": hull["speed"][0], "dp": hull["dp"][-1],
            "damage_speed": [{"damage": dp, "knots": knots} for dp, knots in zip(hull["dp"], hull["speed"], strict=True)],
            **({"engineering_speed_multiplier": 2} if british else {}),
            "turn_advance_yards": 300, "speed_loss_knots": 1, "accel_knots_per_turn": 12,
            "accel_high_knots_per_turn": 6, "brake_knots_per_turn": 15,
            "armor_belt": 0, "armor_deck": 0, "in_service_year": hull["year"], "gun": gun, "torpedo": torpedo,
        })
        fits[sid] = {
            "name": name, "class": ship_class, "period_profile": profile,
            "crew_complement": hull["crew"], "hull_source": hull["source"],
            "gun_model": "gb_mkxii_47in45" if british else "de_skc34_127mm45",
            "gun_annex": src(HOME, 115, "C-2 4.7in/45 Mk IX/Mk XII HE") if british else src(NORD, 120, "C-2 12.7cm SK C/34 HE"),
            "gun_shell_rts_selection": "HE", "gun_mount_layout_status": (
                "conservative_original_aft_20deg_mask; exact correction dates unverified" if british else
                "reconstructed from Type 1936 relation to 1934A and English primary recognition diagram; local translation mount row corrupt" if ship_class == "Type 1936" else
                "verified_combined_1934_and_1934A_annex_mount_row"),
            "gun_mount_corroboration": {
                "document": "US Navy ONI 204, Karl Galster—DD20", "date": "1942-09", "url": Z20_RECOGNITION,
                "use": "count and position of five guns and two quad racks only; no CAS numerical stats imported",
            } if ship_class == "Type 1936" else None,
            "radar_confirmed": [], "radar_candidates_inactive": [] if british else ["de_fumo21"],
            "torpedo_enabled": True, "torpedo_model": "gb_mkix_21in" if british else "de_g7a_t1",
            "torpedo_annex": src(ARCTIC, 90, "F-1 21in Mk IX/IX*") if british else src(NORD, 124, "F-1 G7a (T-1)"),
            "torpedo_historical_opening_loaded": None, "torpedo_variant_opening_loaded": [tubes, tubes],
            "torpedo_runtime_policy": "annex_ready_capacity_fast_setting_contact_action_no_reload",
        }
    return {"ships": ships, "metadata": {
        "schema_version": 1, "content_version": "cas-channel-runtime-v1", "scenario_id": layout["scenario_id"],
        "status": "restricted_rts_adaptation_only", "as_of": layout["date"], "source": layout["source"],
        "instance_fits": fits,
        "restrictions": [
            "No exact CAS scenario found. Start positions, heading, duration, visibility and goals are adapted from IBS-S-03; hull and weapon adjudication uses CAS.",
            "Known class ready tube capacities initialize the adaptation. Individual historical opening loads are unknown. No reserve reload, historical dud override, or ammunition inventory is inferred.",
            "No sensors, individual early-war retrofits, per-hull lengths or undocumented ammunition data are inferred. German Seetakt candidates stay inactive.",
            "See docs/campaign/channel-runtime-sources.md for the conservative early British aft mask and the separately corroborated normalization of the translated German Type 1936 mounting line.",
        ],
    }}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    compiled = compile_data(json.loads(LAYOUT.read_text(encoding="utf-8")))
    if args.check:
        assert json.loads(OUTPUT.read_text(encoding="utf-8")) == compiled, "Channel runtime data is stale"
    else:
        OUTPUT.write_text(json.dumps(compiled, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    print("Channel runtime: eight named destroyers, three period profiles, eight ready-tube fits; no active radar")


if __name__ == "__main__":
    main()
