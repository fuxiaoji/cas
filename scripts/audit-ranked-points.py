#!/usr/bin/env python3
"""Audit the frozen CAS ranked point table against the complete ShipDefs.

Reads `data/rules/cas-competitive-points-v1.json` (202 rows), resolves every row
back to the complete ShipDef its `profile_id` names, recomputes `point_value`
exactly as `src/ranked_fleets.rs` does, and checks the 3000/10000 build gates.

Output: `artifacts/points-audit.json` plus a compact stdout summary.

Usage:
  python scripts/audit-ranked-points.py            # audit + write artifact
  python scripts/audit-ranked-points.py --check    # fail on any arithmetic drift
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "data" / "rules" / "cas-competitive-points-v1.json"
STAGE0 = ROOT / "data" / "stage0.json"
PROLOGUE = ROOT / "data" / "campaign" / "period" / "prologue-runtime.json"
PERIOD = ROOT / "data" / "ships" / "period-cards.json"
MERGED = ROOT / "data" / "ships" / "merged-cards.json"
OUT = ROOT / "artifacts" / "points-audit.json"

POINT_UNIT = 25
DP_WEIGHT = 1.5
KNOT_WEIGHT = 5.0
GUN_BARREL_DAMAGE_WEIGHT = 2.0
TORPEDO_TUBE_WARHEAD_WEIGHT = 0.12
ARMOR_WEIGHT = 5.0
TORPEDO_PROTECTION_WEIGHT = 0.8
SCALE = {"DD": 0.75, "CL": 0.85, "CA": 1.0, "BB": 1.2}


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def rust_round(value: float) -> int:
    """Rust f64::round: half away from zero, not banker's rounding."""
    return int(math.floor(value + 0.5)) if value >= 0 else -int(math.floor(-value + 0.5))


def point_value(ship: dict) -> int:
    gun = ship["gun"]
    average_damage = sum(gun["damage"]) / len(gun["damage"])
    torpedo = 0.0
    if ship.get("torpedo"):
        torp = ship["torpedo"]
        torpedo = TORPEDO_TUBE_WARHEAD_WEIGHT * torp["tubes"] * torp["warhead"]
    raw = (
        DP_WEIGHT * ship["dp"]
        + KNOT_WEIGHT * ship["max_knots"]
        + GUN_BARREL_DAMAGE_WEIGHT * gun["barrels"] * average_damage
        + torpedo
        + ARMOR_WEIGHT * (ship["armor_belt"] + ship["armor_deck"])
        + TORPEDO_PROTECTION_WEIGHT * ship.get("torpedo_protection_dp", 0.0)
    )
    scale = SCALE.get(ship["kind"], 1.0)
    return rust_round(raw * scale / POINT_UNIT) * POINT_UNIT


def component_breakdown(ship: dict) -> dict:
    gun = ship["gun"]
    average_damage = sum(gun["damage"]) / len(gun["damage"])
    torpedo = 0.0
    if ship.get("torpedo"):
        torp = ship["torpedo"]
        torpedo = TORPEDO_TUBE_WARHEAD_WEIGHT * torp["tubes"] * torp["warhead"]
    hull = DP_WEIGHT * ship["dp"]
    speed = KNOT_WEIGHT * ship["max_knots"]
    battery = GUN_BARREL_DAMAGE_WEIGHT * gun["barrels"] * average_damage
    armor = ARMOR_WEIGHT * (ship["armor_belt"] + ship["armor_deck"])
    tpd = TORPEDO_PROTECTION_WEIGHT * ship.get("torpedo_protection_dp", 0.0)
    scale = SCALE.get(ship["kind"], 1.0)
    raw = hull + speed + battery + torpedo + armor + tpd
    return {
        "hull": round(hull, 2), "speed": round(speed, 2), "battery": round(battery, 2),
        "torpedo": round(torpedo, 2), "armor": round(armor, 2), "torpedo_protection": round(tpd, 2),
        "raw": round(raw, 2), "scale": scale, "scaled_over_25": round(raw * scale / POINT_UNIT, 3),
    }


def signature(ship: dict) -> tuple:
    gun = ship["gun"]
    torp = ship.get("torpedo")
    return (
        ship["kind"], round(ship["dp"], 3), round(ship["max_knots"], 3),
        gun["barrels"], tuple(round(v, 3) for v in gun["damage"]),
        torp["tubes"] if torp else 0,
        round(torp["warhead"], 3) if torp else 0.0,
        round(ship["armor_belt"], 3), round(ship["armor_deck"], 3),
        round(ship.get("torpedo_protection_dp", 0.0), 3),
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail on arithmetic drift")
    args = parser.parse_args()

    manifest = load(MANIFEST)
    stage0 = {ship["id"]: ship for ship in load(STAGE0)["ships"]}
    prologue = {ship["id"]: ship for ship in load(PROLOGUE)["ships"]}
    base = dict(stage0)
    base.update(prologue)
    period = {row["period_ship_id"]: row for row in load(PERIOD)}
    merged = {row["identity"]: row for row in load(MERGED)["cards"]}

    rows = []
    mismatches = []
    unresolved = []
    for identity, row in sorted(manifest["ships"].items()):
        profile_id = row["profile_id"]
        kind, _, key = profile_id.partition("#")
        ship = None
        card_kind = None
        if kind == "cas-prologue-runtime-v1":
            ship = base.get(key)
            card_kind = "class"
        elif kind == "cas-period-cards-v1":
            card = period.get(key)
            if card:
                ship = card["ship"]
                card_kind = "period"
        elif kind == "cas-merged-cards-v1":
            card = merged.get(key)
            if card:
                ship = card["ship"]
                card_kind = "merged"
        if ship is None:
            unresolved.append({"identity": identity, "profile_id": profile_id})
            continue
        computed = point_value(ship)
        row_points = row["points"]
        drift = computed - row_points
        if drift:
            mismatches.append({"identity": identity, "manifest": row_points, "computed": computed,
                               "drift": drift, "profile_id": profile_id})
        rows.append({
            "identity": identity, "name": ship["name"], "kind": ship["kind"], "side": ship["side"],
            "points": row_points, "computed": computed, "profile_id": profile_id, "card_kind": card_kind,
            "source": row["source"], "provisional": "provisional" in row["source"],
            "signature": signature(ship), "components": component_breakdown(ship),
            "dp": ship["dp"], "max_knots": ship["max_knots"], "gun_barrels": ship["gun"]["barrels"],
            "torpedo_tubes": (ship.get("torpedo") or {}).get("tubes", 0),
            "year": ship.get("in_service_year"),
        })

    # Same-stat groups must price identically; a differing price proves the
    # table carries a stale value for at least one of the two rows.
    groups = defaultdict(list)
    for row in rows:
        groups[row["signature"]].append(row)
    duplicate_stat_conflicts = [
        {"points": sorted({r["points"] for r in group}), "identities": [r["identity"] for r in group]}
        for group in groups.values() if len({r["points"] for r in group}) > 1
    ]

    # Rows priced from a class card while the identity has an exact registered
    # card elsewhere would be a stale proxy. The registry only registers exact
    # cards for period/merged rows, so check that class rows do not collide with
    # an exact card carrying the same identity.
    exact_identities = set(period) | set()
    stale_proxy = [
        row for row in rows
        if row["card_kind"] == "class" and row["identity"] in exact_identities
    ]

    # Same-type proxy consistency: identities sharing one class card must carry
    # one price.
    class_prices = defaultdict(lambda: defaultdict(list))
    for row in rows:
        if row["card_kind"] == "class":
            class_prices[row["profile_id"]][row["points"]].append(row["identity"])
    same_class_price_conflicts = [
        {"profile_id": profile_id, "prices": {str(price): ids for price, ids in by_price.items()}}
        for profile_id, by_price in class_prices.items() if len(by_price) > 1
    ]

    # 3000 / 10000 build gates (same slot rules as `ranked_fleets::roster`).
    def kind_group(kind: str) -> str:
        if kind == "DD":
            return "DD"
        if kind in {"CL", "CA", "CB", "AV"}:
            return "cruiser"
        if kind in {"BB", "BC"}:
            return "capital"
        return "other"

    dd = sorted((r for r in rows if kind_group(r["kind"]) == "DD"), key=lambda r: r["points"])
    bb = sorted((r for r in rows if kind_group(r["kind"]) == "capital" and r["kind"] != "BC"),
                key=lambda r: r["points"])
    bb_all = sorted((r for r in rows if kind_group(r["kind"]) == "capital"), key=lambda r: r["points"])
    cheapest_six_dd = dd[:6]
    cheapest_two_bb = bb[:2]
    cheapest_four_dd = dd[:4]
    six_dd_total = sum(r["points"] for r in cheapest_six_dd)
    bb_escort_total = sum(r["points"] for r in cheapest_two_bb) + sum(r["points"] for r in cheapest_four_dd)
    gates_by_side = {}
    for side in ("allies", "axis"):
        side_dd = sorted((r for r in rows if r["side"] == side and kind_group(r["kind"]) == "DD"),
                         key=lambda r: r["points"])
        side_bb = sorted((r for r in rows if r["side"] == side and r["kind"] == "BB"),
                         key=lambda r: r["points"])
        six = sum(r["points"] for r in side_dd[:6])
        escort = sum(r["points"] for r in side_bb[:2]) + sum(r["points"] for r in side_dd[:4])
        gates_by_side[side] = {
            "six_dd_total": six,
            "six_dd_fits": six <= 3000,
            "six_dd": [{"identity": r["identity"], "points": r["points"]} for r in side_dd[:6]],
            "two_bb_four_dd_total": escort,
            "two_bb_four_dd_fits": escort <= 10000,
            "two_bb": [{"identity": r["identity"], "points": r["points"]} for r in side_bb[:2]],
            "dd_count": len(side_dd),
            "bb_count": len(side_bb),
        }
    gates = {
        "3000": {
            "six_dd_total": six_dd_total,
            "six_dd_fits": six_dd_total <= 3000,
            "six_dd": [{"identity": r["identity"], "points": r["points"]} for r in cheapest_six_dd],
            "cheapest_dd": {"identity": dd[0]["identity"], "points": dd[0]["points"]},
        },
        "10000": {
            "two_bb_four_dd_total": bb_escort_total,
            "two_bb_four_dd_fits": bb_escort_total <= 10000,
            "two_bb": [{"identity": r["identity"], "points": r["points"]} for r in cheapest_two_bb],
            "four_dd": [{"identity": r["identity"], "points": r["points"]} for r in cheapest_four_dd],
            "cheapest_capital": {"identity": bb_all[0]["identity"], "kind": bb_all[0]["kind"],
                                 "points": bb_all[0]["points"]},
        },
    }

    report = {
        "schema_version": 1,
        "as_of": "2026-11-09",
        "manifest": str(MANIFEST.relative_to(ROOT)),
        "manifest_sha256": hashlib.sha256(MANIFEST.read_bytes()).hexdigest(),
        "rows": len(rows),
        "provisional": sum(1 for row in rows if row["provisional"]),
        "arithmetic_mismatches": mismatches,
        "unresolved": unresolved,
        "duplicate_stat_conflicts": duplicate_stat_conflicts,
        "stale_class_proxies": stale_proxy,
        "same_class_price_conflicts": same_class_price_conflicts,
        "gates": gates,
        "gates_by_side": gates_by_side,
        "by_kind": {kind: sum(1 for row in rows if kind_group(row["kind"]) == kind)
                    for kind in ("DD", "cruiser", "capital", "other")},
        "provisional_breakdown": {
            "merged_new_rows": sum(1 for row in rows if row["profile_id"].startswith("cas-merged-cards-v1")),
            "period_rows": sum(1 for row in rows if row["profile_id"].startswith("cas-period-cards-v1")),
            "legacy_class_proxy_rows": sum(1 for row in rows if row["profile_id"].startswith("cas-prologue-runtime-v1") and row["provisional"]),
        },
        "rows_detail": [
            {key: row[key] for key in ("identity", "name", "kind", "side", "points", "computed",
                                       "profile_id", "card_kind", "provisional", "dp", "max_knots",
                                       "gun_barrels", "torpedo_tubes")}
            for row in rows
        ],
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"rows {report['rows']} provisional {report['provisional']}")
    print(f"arithmetic mismatches: {len(mismatches)}")
    print(f"unresolved cards: {len(unresolved)}")
    print(f"duplicate-stat conflicts: {len(duplicate_stat_conflicts)}")
    print(f"same-class price conflicts: {len(same_class_price_conflicts)}")
    print(f"3000 six DD: {six_dd_total} fits={six_dd_total <= 3000}")
    print(f"10000 2BB+4DD: {bb_escort_total} fits={bb_escort_total <= 10000}")
    if mismatches:
        for row in mismatches[:20]:
            print("  drift", row)
    if args.check and (mismatches or unresolved):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
