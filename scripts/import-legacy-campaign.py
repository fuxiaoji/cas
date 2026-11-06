"""Regenerate the five RTS fallback manifests from the pinned IBS 0.6.9 stages.

Default verifies checked-in geometry without Python dependencies. With
--ibs-worktree, use PyYAML and run the original stage boot from a temporary
Git archive. Add --write only when intentionally regenerating the manifests.
"""
import argparse
from collections import defaultdict
from datetime import date
import io
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import tarfile
from tempfile import TemporaryDirectory


ROOT = Path(__file__).resolve().parents[1]
CAMPAIGN = ROOT / "data/campaign"
OUT = CAMPAIGN / "legacy"
STRUCTURED = "resources/derived/structured"
IBS_MAP = f"{STRUCTURED}/maps/main-map.yaml"
SCHEMA = "cas-legacy-deployment-v1"
HEADING = {1: 60, 2: 120, 3: 180, 4: 240, 5: 300, 6: 0}
DELTA = {1: (1, -1), 2: (1, 0), 3: (0, 1), 4: (-1, 1), 5: (-1, 0), 6: (0, -1)}
SPACING = 600 * 0.9144
TURN_SECONDS = 180
KNOT_MPS = 1852 / 3600

# Only the rows without a same-event CAS scenario qualify. Objectives retain
# the design intent; any old numeric score remains non-executable evidence.
MIGRATIONS = {
    "IBS-S-03": ("03", "channel-action", "night", 8, [
        "同盟追击德国驱逐舰；击沉或使至少一艘丧失足够航速达战术目标，多艘达战略目标。",
        "轴心保全全部驱逐舰速度与生存；在此基础上击沉至少两艘英舰可提升战果。",
    ], ["待用 CAS 损伤后的航速定义替换铁底湾 2-2-2 速度轨门槛。"]),
    "IBS-S-07": ("07", "solomons-1928", None, 22, [
        "双方攻击对方战列巡洋舰；需同时领先战列巡洋舰击沉数和损伤分，否则判平。",
    ], ["待定义 CAS 损伤分与领先门槛；图纸舰与架空服役必须找到对应 CAS 舰卡。"]),
    "IBS-S-12": ("12", "bougainville-1928", None, 14, [
        "双方以造成更多损伤争胜；击沉一至两艘敌方战列舰且己方无战列舰损失可达决定性胜利。",
    ], ["待定义 CAS 损伤分与领先门槛，以及首阶段禁火的 RTS 时间窗。"]),
    "IBS-S-EM-01": ("erma", "philippine-sea-surface", None, 24, [
        "双方可在规定区域交替部署。比拼敌舰舰体损伤及对敌战列舰火控、雷达、主炮、速度的破坏。",
    ], ["待接自由部署、CAS 关键损伤分和门槛；架空改装仅在核得 CAS 舰卡后开放。"]),
    "IBS-S-FM-01": ("fm01", "midnight-fleet", "night", 91, [
        "剧情：轴心突入铁底湾炮击亨德森机场；同盟封锁峡口。",
        "旧作实际以双方造成的舰体损伤得分判胜，未设置可炮击机场或出口目标点。",
    ], ["待定义 CAS 损伤分与领先门槛，并验证 91 舰昼夜接触、机动、界面性能。"]),
}


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def require(condition, error):
    if not condition:
        raise ValueError(error)


def hex_offset(label):
    match = re.fullmatch(r"([A-Z]+)([1-9][0-9]*)", label)
    require(match is not None and len(set(match[1])) == 1, f"invalid IBS hex: {label}")
    return 26 * (len(match[1]) - 1) + ord(match[1][0]) - ord("A"), int(match[2]) - 1


def xy(label, rows):
    q, row = hex_offset(label)
    return [round(SPACING / math.sqrt(3) + q * math.sqrt(3) * SPACING / 2, 6),
            round((rows - row - 0.5 * (q % 2)) * SPACING, 6)]


def bounds(columns, rows):
    return [round(SPACING * ((columns - 1) * math.sqrt(3) / 2 + 2 / math.sqrt(3)), 6),
            round((rows + 0.5) * SPACING, 6)]


def speed_knots(hexes_per_turn):
    return round(hexes_per_turn * SPACING / TURN_SECONDS / KNOT_MPS, 6)


def angle(degrees):
    return math.sin(math.radians(degrees)), math.cos(math.radians(degrees))


def coast_polygons(labels, rows):
    radius = SPACING / math.sqrt(3)
    return [
        [[round(x + radius * math.cos(math.radians(60 * n)), 6),
          round(y + radius * math.sin(math.radians(60 * n)), 6)] for n in range(6)]
        for x, y in (xy(label, rows) for label in labels)
    ]


def ship_state(ship_id, initial_hex, heading, speed, rows):
    x, y = xy(initial_hex, rows)
    return {
        "ibs_ship_id": ship_id, "initial_hex": initial_hex, "x_m": x, "y_m": y,
        "legacy_heading": heading, "heading_deg": HEADING[heading],
        "legacy_speed_hex_per_turn": speed, "speed_knots": speed_knots(speed),
    }


def geometry_conflicts(ships, formations, land_hexes):
    positions, by_id = defaultdict(list), {s["ibs_ship_id"]: s for s in ships}
    for s in ships:
        positions[s["initial_hex"]].append(s["ibs_ship_id"])
    conflicts = [
        {"kind": "same_hex", "hex": label, "ships": ids}
        for label, ids in sorted(positions.items()) if len(ids) > 1
    ] + [
        {"kind": "ship_on_land", "hex": label, "ships": ids}
        for label, ids in sorted(positions.items()) if label in land_hexes
    ]
    for f in formations:
        leader = by_id[f["ship_ids"][0]]
        sx, cy = angle(leader["heading_deg"])
        previous_along = 0.0
        for ship_id in f["ship_ids"][1:]:
            s = by_id[ship_id]
            dx, dy = s["x_m"] - leader["x_m"], s["y_m"] - leader["y_m"]
            along, cross = dx * sx + dy * cy, dx * cy - dy * sx
            if abs(cross) > 1e-5 or along > previous_along + 1e-5:
                conflicts.append({"kind": "proposed_line_does_not_fit_source_positions",
                                  "formation_id": f["id"], "ship": ship_id,
                                  "astern_m": round(-along, 3), "cross_track_m": round(cross, 3)})
            previous_along = along
    return conflicts


def assert_same_runtime(a, b):
    require(a == b, "legacy opening differs between campaign seats")


def capture_runtime(pin):
    sys.path[:0] = [str(pin / "backend/src"), str(pin / "mobile")]
    from iron_bottom_sound.engine import IronBottomEngine
    from iron_bottom_sound.models import GameOptions, OrderBatch, Phase, Side
    from iron_bottom_sound.realistic_command import default_setup_orders
    import progression

    def snapshot(state):
        return {
            "phase": state.phase.value,
            "columns": state.map_columns, "rows": state.map_rows,
            "printed_columns": state.printed_columns, "printed_rows": state.printed_rows,
            "land_hexes": sorted(state.land_hexes), "coast_hexes": sorted(state.coast_hexes),
            "radar_blocking_hexes": sorted(state.radar_blocking_hexes),
            "ships": [
                [s.id, s.position.label if s.position else None, s.heading, s.current_speed]
                for s in state.ships.values()
            ],
        }

    result = {}
    rows = read(CAMPAIGN / "crosswalk.json")["scenarios"]
    for row in rows:
        if row["ibs_id"] not in MIGRATIONS:
            continue
        for stage_id in row["stage_ids"]:
            config, _ = progression.prepare_stage({"stage_id": stage_id, "difficulty": "standard"})
            require(config["scenario_id"] == row["ibs_id"], f"{stage_id}: wrong IBS scenario")
            engine = IronBottomEngine()
            state = engine.reset(config["scenario_id"], seed=config["seed"], options=GameOptions(
                mode="hotseat", realistic_command=config["style"] == "formation",
                ruleset_version="night-v2", night_recognition=True,
                optional_rules=config["optional_rules"]))
            loaded = snapshot(state)
            post_setup = None
            if state.phase == Phase.FORMATION_SETUP:
                groups = []
                for side in Side:
                    orders = default_setup_orders(state, side)
                    submitted = engine.submit_orders(state.game_id, OrderBatch(
                        side=side, phase=state.phase, formation_setup=orders))
                    require(submitted.valid, f"{stage_id}: {submitted.errors}")
                    groups.extend({
                        "id": o.formation_id, "side": side.value, "ship_ids": o.ship_ids,
                        "leader_id": o.leader_id, "flagship_id": o.flagship_id,
                        "reserve_flagship_id": o.reserve_flagship_id,
                        "heading_deg": HEADING[o.heading], "spacing_m": o.spacing * SPACING,
                    } for o in orders)
                engine.advance(state.game_id)
                require(state.phase != Phase.FORMATION_SETUP, f"{stage_id}: no opening advance")
                post_setup = {"state": snapshot(state), "formations": groups}
            replay = {"loaded": loaded, "post_setup": post_setup}
            if row["ibs_id"] in result:
                assert_same_runtime(replay, result[row["ibs_id"]])
            else:
                result[row["ibs_id"]] = replay
        print(f"{row['ibs_id']}: verified both old stage openings", flush=True)
    return result


def render(row, scenario, source_path, catalogue, briefing, runtime, git_rev, map_definition):
    ibs_id = row["ibs_id"]
    _, slug, light, n, intents, gates = MIGRATIONS[ibs_id]
    original, post = runtime["loaded"], runtime["post_setup"]
    cols, rows = original["columns"], original["rows"]
    ship_entries, setup = scenario["ships"], scenario.get("setup", {})
    require(not scenario.get("reinforcements"), f"{ibs_id}: import reinforcement entry zones first")
    require(not original["land_hexes"] and not original["coast_hexes"] and not original["radar_blocking_hexes"],
            f"{ibs_id}: resolve placed overlay before using sea-only map")
    require(original["ships"] == [[s["id"], s["position"], s["heading"], s["speed"]] for s in ship_entries],
            f"{ibs_id}: reset deployment differs from structure")
    require(len(ship_entries) == n and scenario["turns"] == catalogue["turns"], f"{ibs_id}: incorrect force or turns")
    for side in ("axis", "allies"):
        require({s["id"] for s in ship_entries if s["side"] == side} == set(catalogue["fleets"][side]),
                f"{ibs_id}: {side} OOB differs from campaign fleet")
    definitions = setup.get("engine_default_formations", {})
    formations = [{"id": f["id"], "side": side, "role": f["role"], "ship_ids": f["ships"],
                   "note": f.get("note"), "status": "legacy_setup_proposal"}
                  for side, group in definitions.items() for f in group]
    assigned = {s: f["id"] for f in formations for s in f["ship_ids"]}
    ships = [{
        **ship_state(s["id"], s["position"], s["heading"], s["speed"], rows),
        "name": s["name"], "side": s["side"], "flagship": bool(s.get("flagship")),
        "formation_id": assigned.get(s["id"]), "cas_profile_id": None,
    } for s in ship_entries]
    width, height = bounds(cols, rows)
    zones = [{
        "side": side, "from_hex": z["from"], "to_hex": z["to"],
        "from_m": xy(z["from"], rows), "to_m": xy(z["to"], rows),
        "half_plane": z["side"], "include_boundary": z["include_line"],
    } for side, z in setup.get("zones", {}).items()]
    if post:
        require({k: v for k, v in post["state"].items() if k not in {"phase", "ships"}}
                == {k: v for k, v in original.items() if k not in {"phase", "ships"}},
                f"{ibs_id}: resolved setup map differs")
        post_ships = [ship_state(*s, rows) for s in post["state"]["ships"]]
        post = {
            "phase": post["state"]["phase"], "formations": post["formations"],
            "ships": post_ships,
            "conflicts": geometry_conflicts(post_ships, [], original["land_hexes"]),
        }
    restrictions = [{
        "rule_id": r["id"], "sides": r["sides"], "legacy_turns": r["turns"],
        "actions": r["actions"], "reason": r["reason"], "status": "requires_rts_timing_decision",
    } for r in scenario.get("special_rule_kinds", []) if r["kind"] == "turn_restriction"]
    return {
        "schema": SCHEMA, "scenario_id": f"cas-ibs-{slug}", "ibs_id": ibs_id,
        "stage_ids": row["stage_ids"], "title": row["ibs_title"], "date": row["ibs_date"],
        "classification": row["classification"], "playable": False,
        "source": {
            "baseline": "铁底湾手游 0.6.9", "commit": git_rev, "scenario_yaml": source_path,
            "scenario": scenario["source"], "map_yaml": IBS_MAP,
            "scale": {"document": "resources/originals/rules/iron-bottom-sound-iv-rules-zh.pdf",
                      "section": "1.2", "pdf_page": 3, "printed_page": 3},
            "mobile_index": "mobile/content/campaign-scenarios.json",
            "mobile_briefing": "mobile/content/campaign-briefings.json",
            "runtime": [
                "mobile/progression.py::prepare_stage", "backend/src/iron_bottom_sound/engine.py::reset",
                "backend/src/iron_bottom_sound/data.py::build_initial_state",
                "backend/src/iron_bottom_sound/night.py::initialize",
            ] + (["backend/src/iron_bottom_sound/realistic_command.py::default_setup_orders",
                  "backend/src/iron_bottom_sound/realistic_command.py::resolve_setup"] if post else []),
        },
        "start": {
            "legacy_mobile_mode": catalogue["mode"], "legacy_seed": catalogue["seed"],
            "legacy_phase": original["phase"], "light_hint": light,
            "legacy_turn_limit": scenario["turns"],
            "legacy_printed_turn_limit": scenario.get("source_turns"),
            "duration_candidate_seconds": scenario["turns"] * TURN_SECONDS,
            "duration_authority": "rts_conversion_proposal_not_cas",
            "deploy_mode": setup.get("mode", "scenario_positions"),
            "setup_order": setup.get("order"), "setup_first_player": setup.get("first_player"),
            "large_ship_types": setup.get("large_ship_types"), "small_ship_types": setup.get("small_ship_types"),
            "setup_zones": zones,
        },
        "map": {
            "width_m": width, "height_m": height, "columns": cols, "rows": rows,
            "legacy_printed_columns": original["printed_columns"],
            "legacy_printed_rows": original["printed_rows"],
            "terrain": map_definition["terrain_default"],
            "land_hexes": original["land_hexes"], "coast_hexes": original["coast_hexes"],
            "legacy_radar_blocking_hexes": original["radar_blocking_hexes"],
            "land_polygons_m": coast_polygons(original["land_hexes"], rows),
            "coast_polygons_m": coast_polygons(original["coast_hexes"], rows),
            "origin": "southwest_rectangle_corner", "x_axis": "east", "y_axis": "north",
            "heading": "clockwise_from_north", "legacy_layout": "flat_top_odd_q",
            "hex_center_spacing_m": SPACING, "legacy_hex_spacing_yards": 600,
            "legacy_turn_seconds": TURN_SECONDS,
            "speed_authority": "rts_opening_speed_proposal_not_cas_hull_performance",
        },
        "ships": ships, "formations": formations, "reinforcements": [],
        "post_default_formation_setup": post,
        "conflicts": geometry_conflicts(ships, formations, original["land_hexes"]),
        "objectives": {
            "status": "legacy_intent_requires_cas_outcome_binding", "intent": intents,
            "legacy_scoring_evidence": scenario["victory"], "legacy_opening_restrictions": restrictions,
            "location": briefing["location"], "background": briefing["background"],
        },
        "gates": ["全部舰实例须绑定该时期的已核验 CAS 舰卡；开局航速必须按舰卡逐舰验证。",
                  "需要确定 CAS 环境、接触/作战能力及匹配的结算版本。", *gates],
    }


def archive(repo, revision, folder):
    paths = ["backend/src", STRUCTURED, "mobile/progression.py", "mobile/content",
             "resources/originals/rules", "resources/originals/scenarios",
             "resources/originals/records/ship-record-manual-1.1-zh.pdf",
             "resources/originals/assets/images/岛屿.jpg"]
    package = subprocess.check_output(["git", "-C", str(repo), "archive", revision, *paths])
    with tarfile.open(fileobj=io.BytesIO(package)) as original:
        original.extractall(folder, filter="data")


def regenerate(repo):
    import yaml
    crosswalk = read(CAMPAIGN / "crosswalk.json")
    rev = crosswalk["baseline"]["commit"]
    with TemporaryDirectory(prefix="cas-legacy-") as tmp:
        pin = Path(tmp)
        archive(repo, rev, pin)
        mobile = read(pin / crosswalk["baseline"]["scenario_index"])
        briefings = read(pin / crosswalk["baseline"]["briefings"])["briefings"]
        catalogue = {s["id"]: s for s in mobile["scenarios"]}
        map_definition = yaml.safe_load((pin / IBS_MAP).read_text(encoding="utf-8"))
        require(map_definition["layout"] == "flat_top_odd_q"
                and map_definition["hex_scale"]["yards"] == 600, "unexpected source map geometry")
        runtime = capture_runtime(pin)
        files = {}
        for row in crosswalk["scenarios"]:
            ibs_id = row["ibs_id"]
            if ibs_id not in MIGRATIONS:
                continue
            yaml_id, slug, *_ = MIGRATIONS[ibs_id]
            path = f"{STRUCTURED}/scenarios/scenario-{yaml_id}.yaml"
            scenario = yaml.safe_load((pin / path).read_text(encoding="utf-8"))
            files[f"{slug}.json"] = render(row, scenario, path, catalogue[ibs_id], briefings[ibs_id],
                                           runtime[ibs_id], rev, map_definition)
        return files


def verify(record, row):
    require(record["schema"] == SCHEMA and record["ibs_id"] == row["ibs_id"]
            and record["stage_ids"] == row["stage_ids"], "record bound to wrong campaign stage")
    require(record["playable"] is False and not record["reinforcements"], "unsupported ready manifest")
    require(date.fromisoformat(record["date"]).isoformat() == row["ibs_date"], "incorrect scenario date")
    m, ships = record["map"], record["ships"]
    require([m["width_m"], m["height_m"]] == bounds(m["columns"], m["rows"]), "incorrect map bounds")
    require(not m["land_hexes"] and not m["coast_hexes"] and not m["legacy_radar_blocking_hexes"]
            and not m["land_polygons_m"] and not m["coast_polygons_m"] and m["terrain"] == "sea",
            "unexpected terrain in pinned fallback stage")
    ids = {s["ibs_ship_id"]: s for s in ships}
    require(len(ids) == len(ships) == MIGRATIONS[record["ibs_id"]][3], "incorrect ship count")
    require(all(s["cas_profile_id"] is None for s in ships), "unverified CAS ship binding")

    def validate_positions(positions):
        require({s["ibs_ship_id"] for s in positions} == ids.keys(), "incorrect placement membership")
        for s in positions:
            q, r = hex_offset(s["initial_hex"])
            require(q < m["columns"] and r < m["rows"], "off-board hex")
            expected = ship_state(s["ibs_ship_id"], s["initial_hex"], s["legacy_heading"],
                                  s["legacy_speed_hex_per_turn"], m["rows"])
            require(all(s[k] == v for k, v in expected.items()), f"{s['ibs_ship_id']}: incorrect continuous state")

    def validate_groups(groups):
        group_members = set()
        for group in groups:
            require(group["ship_ids"] and group_members.isdisjoint(group["ship_ids"])
                    and len(set(group["ship_ids"])) == len(group["ship_ids"]), "invalid formation membership")
            group_members.update(group["ship_ids"])
            require(all(ids[s]["side"] == group["side"] for s in group["ship_ids"]), "cross-seat formation")

    validate_positions(ships)
    validate_groups(record["formations"])
    require(record["conflicts"] == geometry_conflicts(ships, record["formations"], m["land_hexes"]),
            "incorrect source geometry conflict list")
    post = record["post_default_formation_setup"]
    if post:
        validate_positions(post["ships"])
        validate_groups(post["formations"])
        require(post["conflicts"] == geometry_conflicts(post["ships"], [], m["land_hexes"]),
                "incorrect old resolved opening conflict list")
    for zone in record["start"]["setup_zones"]:
        require(zone["from_m"] == xy(zone["from_hex"], m["rows"])
                and zone["to_m"] == xy(zone["to_hex"], m["rows"]), "incorrect free-deployment zone")


def check_geometry():
    def label(q, r):
        return chr(ord("A") + q % 26) * (q // 26 + 1) + str(r + q // 2 + 1)
    for q in (2, 3, 25, 26, 52, 78):
        r = 14 - q // 2
        x, y = xy(label(q, r), 78)
        for heading, (dq, dr) in DELTA.items():
            nx, ny = xy(label(q + dq, r + dr), 78)
            sx, cy = angle(HEADING[heading])
            require(abs(nx - x - sx * SPACING) < 2e-6 and abs(ny - y - cy * SPACING) < 2e-6,
                    f"incorrect scale or direction at {label(q, r)} / {heading}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ibs-worktree", type=Path)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    if args.write and not args.ibs_worktree:
        parser.error("--write requires --ibs-worktree")
    check_geometry()
    crosswalk = read(CAMPAIGN / "crosswalk.json")
    rows = {r["ibs_id"]: r for r in crosswalk["scenarios"]}
    require(set(MIGRATIONS) == {i for i, r in rows.items() if r["classification"] != "exact_historical_counterpart"},
            "fallback IDs must exactly cover the stages without a same-event CAS scenario")
    if args.ibs_worktree:
        generated = regenerate(args.ibs_worktree)
        for name, record in generated.items():
            data = json.dumps(record, ensure_ascii=False, indent=2) + "\n"
            path = OUT / name
            if args.write:
                OUT.mkdir(exist_ok=True)
                path.write_text(data, encoding="utf-8", newline="\n")
            else:
                require(path.read_text(encoding="utf-8") == data, f"{name}: differs from pinned source")
    count, summaries = 0, []
    for ibs_id, (_, slug, *_rest) in MIGRATIONS.items():
        path = OUT / f"{slug}.json"
        record = read(path)
        require(record["source"]["commit"] == crosswalk["baseline"]["commit"], "incorrect source revision")
        verify(record, rows[ibs_id])
        count += len(record["ships"])
        summaries.append(f"{ibs_id}={len(record['ships'])} ships, {len(record['conflicts'])} source geometry notes")
    print(f"Verified {len(MIGRATIONS)} fallback scenarios, {count} source ship placements")
    print("; ".join(summaries))


if __name__ == "__main__":
    main()
