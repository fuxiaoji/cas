"""Validate CAS historical references and quarantine source-only scenario data."""
import argparse
from collections import Counter
from datetime import date, time
from hashlib import file_digest
import json
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
                assert {"orders", "decisive", "tactical"} == record["objectives"][side].keys()
    assert linked == {p.name for p in CAMPAIGN.glob("*.json")} - {"crosswalk.json"}
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ibs-worktree", type=Path, help="Optionally check the pinned 铁底湾 0.6.9 Git objects")
    args = parser.parse_args()
    crosswalk = load(CAMPAIGN / "crosswalk.json")
    rows, linked, next_records = verify_imports(crosswalk)
    verify_cape_st_george()
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
          f"{checked_sources} local PDF hashes; pinned legacy baseline: {'checked' if args.ibs_worktree else 'not requested'}")


if __name__ == "__main__":
    main()
