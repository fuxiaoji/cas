"""Validate CAS historical references and quarantine source-only scenario data."""
import argparse
from collections import Counter
from datetime import date, time
from hashlib import file_digest
import json
from math import atan2, cos, degrees, hypot, isclose, radians, sin
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[1]
CAMPAIGN = ROOT / "data" / "campaign"
EXPECTED_CLASSES = {
    "exact_historical_counterpart": 11,
    "related_alternate": 1,
    "ibs_original_or_absent": 3,
    "unverified": 1,
}
ROSTER_FILE = "roster-crosswalk.json"


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def sources(obj):
    """Find all linked PDF citations without requiring a PDF dependency."""
    if isinstance(obj, dict):
        if "document" in obj and "printed_pages" in obj and "pdf_pages" in obj:
            yield obj
        for value in obj.values():
            yield from sources(value)
    elif isinstance(obj, list):
        for value in obj:
            yield from sources(value)


def verify_baseline(crosswalk, rows, repository):
    baseline = crosswalk["baseline"]
    rev = baseline["commit"]

    def read(rel):
        return subprocess.check_output(["git", "-C", str(repository), "show", f"{rev}:{rel}"])

    manifest = json.loads(read(baseline["scenario_index"]))
    briefings = json.loads(read(baseline["briefings"]))["briefings"]
    ibs_scenarios = {s["id"]: s for s in manifest["scenarios"]}
    assert ibs_scenarios.keys() == rows.keys()
    stage_map = {s["id"]: s["scenario_id"] for s in manifest["stages"]}
    audit = read(baseline["initial_stage_evidence"]).decode("utf-8")
    for stage, ibs in re.findall(r"\| (CAMP-ALLIES-0[123]) \| (IBS-S-\d{2})", audit):
        stage_map[stage] = ibs
        stage_map[stage.replace("ALLIES", "AXIS")] = ibs
    assert stage_map == {stage: ibs for ibs, row in rows.items() for stage in row["stage_ids"]}
    for ibs_id, row in rows.items():
        ibs = ibs_scenarios[ibs_id]
        assert row["ibs_title"] == ibs["title"]
        assert row["ibs_date"] == ibs["date"]
        assert row["ibs_source"] == ibs["source"]
        assert row["ibs_kind"] == briefings[ibs_id]["kind"]
    assert briefings["CAMP-NIGHT-01"]["kind"] == "training"


def verify_imports(crosswalk):
    rows = {row["ibs_id"]: row for row in crosswalk["scenarios"]}
    assert len(rows) == len(crosswalk["scenarios"]) == 16
    assert Counter(row["classification"] for row in rows.values()) == EXPECTED_CLASSES
    stages = [stage for row in rows.values() for stage in row["stage_ids"]]
    assert len(stages) == len(set(stages)) == 32
    assert set(stages) == {f"CAMP-{side}-{n:02}" for side in ("ALLIES", "AXIS") for n in range(1, 17)}
    cas_ids = set()
    linked = set()
    next_records = set()
    refs = list(sources(crosswalk))
    for row in rows.values():
        assert row["playable"] is False
        date.fromisoformat(row["ibs_date"])
        assert row["stage_ids"][0][-2:] == row["stage_ids"][1][-2:]
        cas = row["cas"]
        if row["classification"] in {"unverified", "ibs_original_or_absent"}:
            assert cas is None and row["checked_sources"]
            continue
        assert cas["scenario_id"] not in cas_ids
        cas_ids.add(cas["scenario_id"])
        date.fromisoformat(cas["start_date"])
        time.fromisoformat(cas["start_time_local"])
        if cas["import"]:
            assert row["classification"] == "exact_historical_counterpart"
            assert cas["verification"] == "scenario_page_transcribed"
            path = CAMPAIGN / cas["import"]
            assert path.resolve().parent == CAMPAIGN and path.name not in linked
            linked.add(path.name)
            record = load(path)
            refs.extend(sources(record))
            assert record["scenario_id"] == cas["scenario_id"] and record["ibs_id"] == row["ibs_id"]
            assert record["title_en"] == cas["title"]
            assert record["source"] == cas["source"]
            assert record["start"]["date_local"] == cas["start_date"]
            assert record["start"]["time_local"] == cas["start_time_local"]
            assert record["status"] == "source_transcribed"
            assert record["playable"] is False and record["blockers"]
            for side in ("axis", "allies"):
                assert {"orders", "decisive", "tactical"} <= record["objectives"][side].keys()
    assert linked == {p.name for p in CAMPAIGN.glob("*.json")} - {"crosswalk.json", ROSTER_FILE}
    assert len(linked) == EXPECTED_CLASSES["exact_historical_counterpart"]
    for path in (CAMPAIGN / "next").glob("*.json"):
        record = load(path)
        row = rows[record["ibs_id"]]
        cas = row["cas"]
        assert row["classification"] == "exact_historical_counterpart" and not cas["import"]
        assert record["scenario_id"] == cas["scenario_id"] and record["title_en"] == cas["title"]
        assert record["source"] == cas["source"] and record["playable"] is False
        assert record["start"]["date_local"] == cas["start_date"] and record["start"]["time_local"] == cas["start_time_local"]
        assert record["status"] == "source_transcribed" and record["blockers"]
        assert all({"orders", "decisive", "tactical"} <= record["objectives"][side].keys() for side in ("axis", "allies"))
        assert record["scenario_id"] not in next_records
        next_records.add(record["scenario_id"])
        refs.extend(sources(record))
    for path in (CAMPAIGN / "period").glob("*.json"):
        refs.extend(sources(load(path)))
    for ref in refs:
        assert ref["document"] in crosswalk["documents"]
        assert len(ref["pdf_pages"]) == len(ref["printed_pages"]) > 0
        assert all(isinstance(p, int) and p >= 1 for p in ref["pdf_pages"])
    return rows, linked, next_records


def verify_cape_st_george():
    scenario = load(CAMPAIGN / "cape-st-george.json")
    groups = {group["id"]: group for group in scenario["groups"]}
    members = [member for g in groups.values() for member in g["members_in_order"]]
    ships = {ship["id"]: ship for ship in scenario["ships"]}
    assert len(ships) == len(set(members)) == len(members) == 10
    assert set(members) == ships.keys()
    assert Counter(g["side"] for g in groups.values() for _ in g["members_in_order"]) == {"allies": 5, "axis": 5}
    assert all(g["members_in_order"][0] == g["leader"] for g in groups.values())
    assert all(g["column_spacing_yd"] is None for g in groups.values())
    assert all(ship["period_record"] in scenario["period_records"] for ship in ships.values())
    assert groups["us-desdiv-46"]["leader_position"] == {
        "type": "bearing_from_ship", "ship": "dyson", "bearing_deg": 240, "distance": 3000, "unit": "yd"
    }
    assert groups["ijn-desdiv-31"]["leader_position"] == {
        "type": "bearing_from_ship", "ship": "ausburne", "bearing_deg": 80, "distance": 11, "unit": "nmi"
    }
    assert groups["ijn-destroyer-transport-group"]["leader_position"] == {
        "type": "astern_of_group", "group": "ijn-desdiv-31", "distance": 13000, "unit": "yd", "reference_ship": None
    }
    goals = scenario["objectives"]
    assert goals["axis"]["decisive"]["all_of"][1] == {"type": "all_own_ships_damage_strictly_below_pct", "pct": 25}
    assert goals["allies"]["decisive"]["all_of"][1] == {"type": "all_own_ships_damage_at_most_pct", "kind": "DD", "pct": 25}
    assert all(value is None for value in goals["adjudication"].values())
    period = load(CAMPAIGN / "period" / "cape-st-george-1943.json")
    assert period["scenario_id"] == scenario["scenario_id"] and period["as_of"] == scenario["start"]["date_local"]
    assert period["status"] == "source_data_not_launchable"
    assert period["instances"].keys() == ships.keys()
    # American Fleets PDF 108 (C-2) and Emperor's Fleet PDF 97 (C-1).
    # Annex rows checked here separately from the dated Form 10 loadouts.
    gun_annex = {
        "us_mk30_5in38": {
            "SpCOM": ([5500, 10900, 14600, 18200], [7, 4, 3, 2], [1, 2], [18, 14, 12, 11]),
            "COM": ([5500, 10900, 14600, 18200], [5, 3, 2, 2], [1, 2], [22, 19, 17, 15]),
            "HE": ([7100, 14300, 19000, 23800], [2, 1, 1, 1], [0, 1], [18, 15, 14, 12]),
        },
        "jp_3rd_yr_127mm50": {
            "COM": ([6000, 12000, 16000, 20000], [5, 3, 2, 2], [1, 2], [16, 13, 11, 10]),
            "HE": ([6000, 12000, 16000, 20000], [2, 1, 1, 1], [1, 1], [17, 14, 13, 11]),
        },
        "jp_3rd_yr_120mm45": {
            "COM": ([5300, 10600, 14100, 17600], [4, 3, 2, 1], [1, 2], [14, 11, 10, 9]),
            "HE": ([5300, 10600, 14100, 17600], [1, 1, 1, 0], [0, 1], [15, 13, 11, 10]),
        },
    }
    for gun, shell_rows in gun_annex.items():
        models = period["weapon_models"][gun]["shells"]
        assert models.keys() == shell_rows.keys()
        for shell, (ranges, belt, deck, dp) in shell_rows.items():
            assert models[shell] == {
                "range_yd": [[lo, hi] for lo, hi in zip([0] + [hi + 100 for hi in ranges[:-1]], ranges)],
                "belt": belt, "deck": [None, None] + deck, "damage_dp": dp,
            }, (gun, shell)
    classes = {}
    for sid, instance in period["instances"].items():
        group = next(g for g in groups.values() if sid in g["members_in_order"])
        profile = period["profiles"][instance["profile"]]
        assert (profile["side"], profile["class"], profile["kind"]) == (group["side"], ships[sid]["class"], ships[sid]["kind"])
        assert profile["turn_class"] in period["maneuver_classes"]
        assert profile["main_gun"] in period["weapon_models"]
        assert profile["damage_speed_rows_dp_knots"][-1][1] is None  # sunk, not stopped
        assert profile["damage_speed_rows_dp_knots"][0][1] >= group["speed_knots"]
        assert all(arc in ("F", "A", "P&S") and barrels > 0 for arc, barrels in profile["gun_mounts"])
        racks = profile["torpedo_mounts"]
        assert racks["model"] is None or racks["model"] in period["weapon_models"]
        assert racks["reserve_per_mount"] is None or len(racks["reserve_per_mount"]) == len(racks["loaded_tubes_per_mount"])
        assert not set(instance["radar_confirmed"]) & set(instance.get("radar_candidates", []))
        classes[profile["class"]] = profile["damage_speed_rows_dp_knots"][-1][0]
    assert classes == {"Fletcher": 144, "Yugumo": 140, "Fubuki": 106, "Mutsuki": 88}
    assert {i["id"] for i in period["conflicts"] if i["status"] == "unresolved"} == {
        "fubuki-torpedo-reserve", "yugiri-type22-date", "uzuki-torpedo-model", "troop-loadout"
    }
    assert period["profiles"]["fubuki_1936_refit"]["torpedo_mounts"]["reserve_per_mount"] is None
    assert period["profiles"]["mutsuki_1943_uzuki"]["torpedo_mounts"]["model"] is None
    assert period["instances"]["yugiri"]["radar_confirmed"] == []
    return ships


def verify_roster(crosswalk, campaign_rows, cape_ships, repository):
    roster = load(CAMPAIGN / ROSTER_FILE)
    assert roster["baseline_commit"] == crosswalk["baseline"]["commit"]
    assert roster["status"] == "identity_inventory_not_a_battle_pack"
    by_id = {ship["ibs_ship_id"]: ship for ship in roster["ships"]}
    assert len(roster["ships"]) == len(by_id) == 210
    assert sum(bool(ship["campaign_memberships"]) for ship in by_id.values()) == 208
    assert sum(ship["legacy_catalog_entry"] for ship in by_id.values()) == 22
    assert {sid for sid, ship in by_id.items() if not ship["campaign_memberships"]} == {"IBS-U-USN-GEARING", "IBS-U-USN-MIDWAY"}
    mapped = {}
    for sid, ship in by_id.items():
        assert sid.startswith("IBS-U-") and ship["ibs_character_id"].startswith("IBS-U-")
        assert ship["side"] in {"allies", "axis"}
        assert all(m["scenario_id"] in campaign_rows and isinstance(m["reinforcement"], bool) for m in ship["campaign_memberships"])
        assert not {"cost", "combat_ready", "recruitable", "guns", "torpedoes", "dp"} & ship.keys()
        if ship["cas_named_hull_status"] == "period_review":
            inst = ship["cas_source_instance"]
            assert inst["scenario_id"] == "cas-rs-cape-st-george" and inst["ship_id"] not in mapped
            mapped[inst["ship_id"]] = sid
        else:
            assert ship["cas_named_hull_status"] == "unverified" and "cas_source_instance" not in ship
    assert mapped.keys() == cape_ships.keys()
    assert mapped["uzuki"] == "IBS-U-IJN-UZUKI-2"
    prologue = load(CAMPAIGN / "period" / "prologue-us-destroyers.json")
    assert prologue["status"] == "dated_source_records_not_a_frozen_sortie"
    assert {ship["ibs_ship_id"] for ship in prologue["ships"]} == {
        "IBS-U-USN-" + name for name in ("FLETCHER", "PERKINS", "MAURY", "DRAYTON", "LAMSON")
    }
    for entry in prologue["ships"]:
        assert entry["name"] == by_id[entry["ibs_ship_id"]]["name"]
        assert prologue["dated_fits"][entry["fit"]]["hull"] in prologue["hull_classes"]
    if repository:
        def read(rel):
            return json.loads(subprocess.check_output(
                ["git", "-C", str(repository), "show", f"{roster['baseline_commit']}:{rel}"]
            ))
        manifest, catalog, portrait = map(read, roster["sources"])
        assert by_id.keys() == {s["ship_id"] for s in portrait["ships"]}
        legacy_scenario = {s["id"]: s for s in manifest["ships"]}
        legacy_catalog = {s["id"]: s for s in catalog["ships"]}
        assert by_id.keys() == legacy_scenario.keys() | legacy_catalog.keys()
        for sid, ship in by_id.items():
            legacy = legacy_scenario.get(sid) or legacy_catalog[sid]
            assert (ship["name"], ship["side"], ship["legacy_type"]) == (legacy["name"], legacy["side"], legacy["type"])
            assert ship["legacy_catalog_entry"] == (sid in legacy_catalog)
            assert ship["campaign_memberships"] == sorted(legacy.get("campaign_sources", []), key=lambda m: (m["scenario_id"], m["reinforcement"]))
    return len(by_id)


def verify_horaniu_basis():
    record = load(CAMPAIGN / "horaniu.json")
    period = load(CAMPAIGN / "period" / "horaniu-1943.json")
    small = load(ROOT / "data" / "rules" / "small-craft-source.json")
    assert record["playable"] is False and period["status"] == "source_only_not_runtime_ready"
    assert period["start"]["geometry_conflict"]["selection"] is None
    assert period["start"]["destination_arrival_boundary"] is None
    named = period["named_destroyers"]
    assert len({ship["id"] for ship in named}) == len(named) == 8
    assert Counter(ship["side"] for ship in named) == {"allies": 4, "axis": 4}
    assert all(ship["profile"] in period["profiles"] for ship in named)
    assert [ship["name"] for ship in named if ship["side"] == "allies"] == record["forces"]["allies"]["column"]
    craft = period["small_craft"]
    transport, = (ship for ship in craft if ship["class_ref"] == "daihatsu_type_a")
    assert (transport["formation"], transport["count"]) == ("convoy", 13)
    assert period["objective_reading_for_rts_fixture"]["japan_tactical"]["convoy_type_a_arrived_min"] == (transport["count"] + 1) // 2
    for ship in craft:
        if ship["class_ref"] is None:
            assert ship["candidate_ref"] in small["unbound_candidates"]
        else:
            assert ship["class_ref"] in small["classes"]
    assert all(ship["class_ref"] is None for ship in craft if ship["scenario_label"] == "T.14 MTB")
    refs = period["start"]["from_nicholas"]
    def p(ref):
        bearing = radians(ref["bearing_deg_true"])
        return ref["range_nmi"] * sin(bearing), ref["range_nmi"] * cos(bearing)
    sx, sy = p(refs["sazanami"])
    cx, cy = p(refs["convoy"])
    conflict = period["start"]["geometry_conflict"]
    assert isclose(hypot(cx - sx, cy - sy), conflict["convoy_from_sazanami_derived_range_nmi"], abs_tol=1e-6)
    assert isclose(degrees(atan2(cx - sx, cy - sy)) % 360, conflict["convoy_from_sazanami_derived_bearing_deg_true"], abs_tol=1e-6)
    return len(named)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ibs-worktree", type=Path, help="Optionally check the pinned 铁底湾 0.6.9 Git objects")
    args = parser.parse_args()
    crosswalk = load(CAMPAIGN / "crosswalk.json")
    rows, linked, next_records = verify_imports(crosswalk)
    cape_ships = verify_cape_st_george()
    horaniu_ships = verify_horaniu_basis()
    roster_count = verify_roster(crosswalk, rows, cape_ships, args.ibs_worktree)
    originals = ROOT / crosswalk["source_path_root"]
    checked_sources = 0
    if originals.is_dir():
        for doc in crosswalk["documents"].values():
            with (originals / doc["path"]).open("rb") as f:
                assert file_digest(f, "sha256").hexdigest() == doc["sha256"], doc["path"]
            checked_sources += 1
    if args.ibs_worktree:
        verify_baseline(crosswalk, rows, args.ibs_worktree)
    print(f"CAS campaign: {len(rows)} scenarios, 32 legacy stages, {len(linked)} catalogued and {len(next_records)} staged source-only imports; "
          f"{roster_count} legacy identities, {len(cape_ships)} dated Cape St. George and {horaniu_ships} source-only Horaniu destroyers; "
          f"{checked_sources} local PDF hashes; pinned legacy baseline: {'checked' if args.ibs_worktree else 'not requested'}")


if __name__ == "__main__":
    main()
