#!/usr/bin/env python3
"""Check the Cape Esperance 1942 period package against the verified source pages.

Validates JSON structure, ship counts, both sides' printed rosters, the
registered source page numbers, the three printed start options, deployment
numbers, victory conditions and the cross-package profile references.

Usage: python scripts/check-cape-esperance.py
Exits non-zero and prints the failures if any check does not pass.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PERIOD_DIR = ROOT / "data" / "campaign" / "period"
TARGET = PERIOD_DIR / "cape-esperance-1942.json"

# Rosters exactly as printed on Rising Sun PDF 65 (printed 64).
ALLIED_ROSTER = [
    "san_francisco",
    "salt_lake_city",
    "boise",
    "helena",
    "farenholt",
    "duncan",
    "laffey",
    "buchanan",
    "mccalla",
]
AXIS_ROSTER = [
    "aoba",
    "furutaka",
    "kinugasa",
    "fubuki",
    "hatsuyuki",
]

SCENARIO_PDF_PAGES = [65]
SCENARIO_PRINTED_PAGES = [64]

# Printed page -> PDF page pairs for the Form 10 corroboration pages cited
# in named_ships and profiles (verified visually in this entry pass).
FORM10_PAGES = {
    46: "Aoba CA (Dec 1941)",
    47: "Kinugasa CA (Dec 1941)",
    53: "Furutaka CA (Dec 1941)",
    156: "Fubuki DD (Apr-May 42)",
    159: "Hatsuyuki DD (Dec 1941)",
    245: "San Francisco CA (Mar 42)",
    253: "Salt Lake City CA (Nov 42-Mar 43)",
    254: "Salt Lake City CA (Dec 1941)",
    263: "Helena CL (Dec 41-Jul 42)",
    265: "Boise CL (Jan-Jun 42)",
    266: "Boise CL (Dec 1941)",
    292: "Buchanan DD (Nov-Dec 42)",
    293: "Buchanan DD (Mar 1942)",
    295: "Duncan DD (Apr 1942)",
    296: "Farenholt DD (Apr 1942)",
    297: "Laffey DD (Mar 1942)",
    299: "McCalla DD (May 1942)",
}

ANNEX_PAGES = {
    ("emperors_fleet", 17): "A-14 (Aoba/Furutaka 1937-38 refit entries)",
    ("emperors_fleet", 18): "A-15 (damage & speed breakdowns)",
    ("emperors_fleet", 97): "C-1 (12.7cm/50 gun row)",
    ("emperors_fleet", 98): "C-2 (20cm/50 No.2 gun row)",
    ("emperors_fleet", 105): "F-1 (Type 93 torpedo)",
    ("american_fleets", 16): "A-13 (New Orleans class)",
    ("american_fleets", 17): "A-14 (Pensacola class)",
    ("american_fleets", 19): "A-16 (Brooklyn groups)",
    ("cas_5e_main", 13): "2-1 mount sectors",
    ("cas_5e_main", 14): "2-2 mount sectors",
    ("cas_5e_main", 23): "3-2 maneuver",
    ("cas_5e_main", 47): "5-10 visual detection",
    ("cas_5e_main", 49): "5-12 squalls and nighttime illumination",
    ("cas_5e_main", 51): "5-14 visibility modifiers",
}

CROSS_PACKAGE_REFS = [
    ("tassafaronga-1942.json", "profiles", [
        "new_orleans_1942",
        "pensacola_1942",
        "brooklyn_first_group_1942",
        "bristol_1942",
    ]),
    ("tassafaronga-1942.json", "weapon_models", [
        "us_8in55_mk9_10_11_13_14",
        "us_8in55_mk12_15",
        "us_6in47_mk16",
        "us_mk15_tnt",
    ]),
    ("kula-runtime.json", "profiles", ["brooklyn_2"]),
    ("cape-st-george-1943.json", "profiles", ["fubuki_1936_refit"]),
    ("cape-st-george-1943.json", "weapon_models", [
        "jp_3rd_yr_127mm50",
        "us_mk30_5in38",
        "jp_type93_m1_mod1_2",
    ]),
]


class Checker:
    def __init__(self) -> None:
        self.failures: list[str] = []

    def check(self, ok: bool, message: str) -> None:
        if not ok:
            self.failures.append(message)

    def check_equal(self, got, expected, message: str) -> None:
        self.check(got == expected, f"{message}: got {got!r}, expected {expected!r}")


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def check_structure(c: Checker, data: dict) -> None:
    for key in [
        "schema_version", "content_version", "id", "scenario_id", "as_of",
        "status", "policy", "scenario_source", "start", "named_ships",
        "profiles", "weapon_models", "orders", "victory_conditions_as_printed",
        "special_rules_as_printed", "conflicts", "pending_items",
        "night_optics_sources", "transport_states", "named_ship_count", "counts",
    ]:
        c.check(key in data, f"missing top-level key {key!r}")
    c.check_equal(data.get("schema_version"), 1, "schema_version")
    c.check_equal(data.get("scenario_id"), "cas-rs-cape-esperance", "scenario_id")
    c.check_equal(data.get("as_of"), "1942-10-11", "as_of")
    c.check(
        data.get("status") == "source_only_not_runtime_ready",
        "status must stay source_only_not_runtime_ready until runtime consumers exist",
    )


def check_scenario_source(c: Checker, data: dict) -> None:
    src = data.get("scenario_source", {})
    c.check_equal(src.get("pdf_pages"), SCENARIO_PDF_PAGES, "scenario pdf_pages")
    c.check_equal(src.get("printed_pages"), SCENARIO_PRINTED_PAGES, "scenario printed_pages")
    c.check(
        bool(src.get("note")),
        "scenario_source.note must record the adjacent-page check",
    )


def check_rosters(c: Checker, data: dict) -> None:
    ships = data.get("named_ships", [])
    ids = [s.get("id") for s in ships]
    c.check_equal(len(ids), 14, "named ship count")
    c.check_equal(data.get("named_ship_count"), 14, "named_ship_count field")

    allies = [s["id"] for s in ships if s.get("side") == "allies"]
    axis = [s["id"] for s in ships if s.get("side") == "axis"]
    c.check_equal(sorted(allies), sorted(ALLIED_ROSTER), "allied roster")
    c.check_equal(sorted(axis), sorted(AXIS_ROSTER), "axis roster")
    c.check_equal(len(set(ids)), len(ids), "duplicate ship ids")
    c.check_equal(data.get("counts", {}).get("allies"), 9, "counts.allies")
    c.check_equal(data.get("counts", {}).get("axis"), 5, "counts.axis")

    for ship in ships:
        for key in ["id", "name", "side", "kind", "unit", "profile", "position"]:
            c.check(bool(ship.get(key)), f"ship {ship.get('id')!r} missing {key!r}")
        form = ship.get("form10") or {}
        c.check_equal(form.get("document"), "rising_sun_form10", f"{ship['id']} form10 document")
        for page in form.get("pdf_pages", []):
            c.check(
                page in FORM10_PAGES,
                f"{ship['id']} cites Form 10 page {page} which is not in the verified set",
            )
        c.check(bool(form.get("form10_date") if "form10_date" in form else ship.get("form10_date")),
                f"{ship['id']} needs a form10_date")


def check_start_options(c: Checker, data: dict) -> None:
    start = data.get("start", {})
    c.check_equal(start.get("local_date"), "1942-10-11", "start date")
    c.check_equal(start.get("local_time"), "23:24", "start time")
    c.check_equal(start.get("map_type"), "open_ocean", "map type")
    c.check(start.get("chart_on_scenario_page") is False, "scenario page must stay chart-less")

    env = start.get("environment", {})
    c.check_equal(env.get("visibility_pct"), 10, "visibility")
    c.check_equal(env.get("moon_pct"), 1, "moon")
    c.check_equal(env.get("sea_state"), 3, "sea state")
    c.check_equal(env.get("civil_twilight_begins_local"), "05:39", "civil twilight")
    c.check_equal(env.get("dawn_local"), "06:00", "dawn")
    c.check("squall" in (env.get("squalls_text") or "").lower(), "squall text")

    us = start.get("us_formation", {})
    c.check_equal(us.get("course_deg_true"), 45, "US course")
    c.check_equal(us.get("speed_knots"), 15, "US speed")
    c.check_equal(
        us.get("column_order"),
        ["farenholt", "duncan", "laffey", "san_francisco", "boise",
         "salt_lake_city", "helena", "buchanan", "mccalla"],
        "US column order",
    )
    reversal = us.get("scheduled_course_reversal", {})
    c.check_equal(reversal.get("time_local"), "23:30", "scheduled course reversal time")

    jp = start.get("japan_formation", {})
    c.check_equal(jp.get("course_deg_true"), 135, "IJN course")
    c.check_equal(jp.get("speed_knots"), 30, "IJN speed")
    c.check_equal(jp.get("column_order"), ["aoba", "furutaka", "kinugasa"], "IJN column order")
    lead = jp.get("leading_ship_from_helena", {})
    c.check_equal(lead.get("bearing_deg_true"), 315, "Aoba bearing from Helena")
    c.check_equal(lead.get("range_nmi"), 13.5, "Aoba range from Helena")
    screen = jp.get("screen", {})
    c.check("port beam" in screen.get("fubuki", ""), "Fubuki beam side")
    c.check("starboard beam" in screen.get("hatsuyuki", ""), "Hatsuyuki beam side")
    c.check_equal(screen.get("ranges"), "not printed", "screen ranges must stay unregistered")

    options = {o.get("id"): o for o in start.get("start_options", [])}
    c.check_equal(
        [o.get("time_local") for o in start.get("start_options", [])],
        ["23:24", "23:39", "23:45"],
        "three printed start options",
    )
    radio = options.get("helena_radio_contact", {})
    c.check_equal(radio.get("enemy_from_helena", {}).get("bearing_deg_true"), 285,
                  "2339 contact bearing")
    c.check_equal(radio.get("enemy_from_helena", {}).get("range_text"), "six miles",
                  "2339 contact range text")
    visual = options.get("helena_visual_contact", {})
    c.check_equal(visual.get("enemy_from_helena", {}).get("bearing_deg_true"), 300,
                  "2345 contact bearing")
    c.check_equal(visual.get("enemy_from_helena", {}).get("range_yd"), 5000,
                  "2345 contact range")


def check_rules_and_objectives(c: Checker, data: dict) -> None:
    orders = data.get("orders", {})
    c.check("90 minutes" in orders.get("japan", ""), "Japanese orders must keep the 90-minute bombardment")
    c.check("30 Tactical Turns" in orders.get("japan", ""), "Japanese orders must keep 30 Tactical Turns")
    c.check("Intercept" in orders.get("us", ""), "US orders")

    vc = data.get("victory_conditions_as_printed", {})
    jp = vc.get("japan", {})
    us = vc.get("us", {})
    c.check("3:1" in jp.get("decisive", ""), "Japanese decisive ratio")
    c.check("1:1" in jp.get("tactical", ""), "Japanese tactical ratio")
    c.check("3:1" in us.get("decisive", ""), "US decisive ratio")
    c.check("1.5:1" in us.get("tactical", ""), "US tactical ratio")
    c.check(bool(vc.get("independence_note")), "both-sides-achieve note must be present")

    rules = data.get("special_rules_as_printed", {})
    c.check("free Tactical Turn of fire" in rules.get("surprise_fire", ""),
            "US free tactical turn rule")
    c.check("D10" in rules.get("cease_fire_d10", ""), "D10 cease-fire rule")
    c.check("Planned Fire Phase" in rules.get("helena_2345_fire_rule", ""),
            "2345 Helena fire rule")

    aircraft = data.get("aircraft", {}).get("us", {})
    c.check_equal(aircraft.get("airborne_count"), 1, "one SOC-3 airborne")
    c.check("aborted" in aircraft.get("scenario_text", ""), "SOC-3 narrative kept verbatim")


def check_page_registrations(c: Checker, data: dict) -> None:
    seen_docs = {}

    def visit(node, path):
        if isinstance(node, dict):
            doc = node.get("document")
            if doc in ("rising_sun_5e", "cas_5e_main", "emperors_fleet",
                       "american_fleets", "rising_sun_form10"):
                for page in node.get("pdf_pages", []) or ([node["pdf_page"]] if "pdf_page" in node else []):
                    key = (doc, page)
                    seen_docs.setdefault(key, []).append(path)
                    if doc == "cas_5e_main":
                        c.check(page in {p for d, p in ANNEX_PAGES if d == doc},
                                f"{path}: cas_5e_main page {page} not in verified set")
                    elif doc == "rising_sun_form10":
                        c.check(page in FORM10_PAGES,
                                f"{path}: Form 10 page {page} not in verified set")
            for value in node.values():
                visit(value, path)
        elif isinstance(node, list):
            for idx, value in enumerate(node):
                visit(value, f"{path}[{idx}]")

    visit(data, "root")

    # The key annex pages must be cited somewhere in the package.
    for key in [
        ("emperors_fleet", 17), ("emperors_fleet", 18), ("emperors_fleet", 98),
        ("american_fleets", 16), ("american_fleets", 17), ("american_fleets", 19),
        ("cas_5e_main", 47), ("cas_5e_main", 49),
    ]:
        c.check(key in seen_docs, f"no citation found for {ANNEX_PAGES[key]} ({key[0]} PDF {key[1]})")

    night = data.get("night_optics_sources", {})
    for key in ["visual_detection", "squalls", "nighttime_illumination"]:
        block = night.get(key, {})
        c.check(bool(block.get("pdf_pages")), f"night_optics_sources.{key} needs pdf_pages")
        c.check(bool(block.get("printed_pages")), f"night_optics_sources.{key} needs printed_pages")

    citations = data.get("annex_citations", {})
    for key in ["new_orleans_class_a13", "pensacola_class_a14", "brooklyn_a16"]:
        block = citations.get(key, {})
        c.check(bool(block.get("pdf_pages")), f"annex_citations.{key} needs pdf_pages")
        c.check(bool(block.get("quoted_remarks")), f"annex_citations.{key} needs quoted_remarks")


def check_cross_package_refs(c: Checker, data: dict) -> None:
    profiles = data.get("profiles", {})
    for filename, section, names in CROSS_PACKAGE_REFS:
        path = PERIOD_DIR / filename
        if not path.exists():
            c.check(False, f"cross-referenced package missing: {filename}")
            continue
        target = load_json(path)
        container = target.get(section, {})
        for name in names:
            c.check(name in container, f"{filename}#{section}.{name} not found for cross-reference")

    ref_by_profile = {
        "new_orleans_1942": ("tassafaronga-1942.json", "new_orleans_1942"),
        "pensacola_1942": ("tassafaronga-1942.json", "pensacola_1942"),
        "brooklyn_first_group_1942": ("tassafaronga-1942.json", "brooklyn_first_group_1942"),
        "bristol_1942": ("tassafaronga-1942.json", "bristol_1942"),
        "brooklyn_second_group_1942": ("kula-runtime.json", "brooklyn_2"),
        "fubuki_1936_refit": ("cape-st-george-1943.json", "fubuki_1936_refit"),
    }
    for local_name, (filename, remote_name) in ref_by_profile.items():
        block = profiles.get(local_name, {})
        ref = block.get("profile_ref", "")
        c.check(
            ref == f"{filename}#profiles.{remote_name}",
            f"profile {local_name!r} must point at {filename}#profiles.{remote_name}, got {ref!r}",
        )

    # Every named ship must resolve to a registered profile.
    for ship in data.get("named_ships", []):
        c.check(ship.get("profile") in profiles,
                f"ship {ship.get('id')!r} profile not registered in profiles")

    # The new IJN cruiser profiles must be self-contained.
    for name in ["aoba_1938", "furutaka_1937"]:
        block = profiles.get(name, {})
        for key in ["source", "crew", "std_displacement_tons", "size", "armor_rating",
                    "gunnery_standard", "turn_class", "accel_decel_knots_per_turn",
                    "damage_speed_rows_dp_knots", "main_gun", "torpedo_mounts",
                    "special_damage_modifier_pct"]:
            c.check(key in block, f"profile {name} missing {key!r}")
        c.check_equal(block.get("special_damage_modifier_pct"), -15,
                      f"{name} special damage modifier")
        c.check(block.get("main_gun") == "jp_20cm50_3rd_yr_type_no2",
                f"{name} main gun model")

    gun = data.get("weapon_models", {}).get("jp_20cm50_3rd_yr_type_no2", {})
    c.check_equal(gun.get("source", {}).get("printed_pages"), ["C-2"], "20cm/50 source page")
    c.check_equal(gun.get("shells", {}).get("APC", {}).get("damage_dp"), [26, 20, 17, 15],
                  "20cm/50 APC damage")
    c.check_equal(gun.get("shells", {}).get("HE", {}).get("damage_dp"), [28, 23, 21, 18],
                  "20cm/50 HE damage")


def check_conflicts_and_pending(c: Checker, data: dict) -> None:
    conflicts = {item.get("id"): item for item in data.get("conflicts", [])}
    for expected in [
        "san-francisco-gun-mark",
        "helena-radio-range-unit",
        "furutaka-torpedo-reserve",
        "furutaka-light-aa-25mm",
        "aoba-floatplane-type-and-count",
        "fubuki-dp-139-vs-106",
        "us-form10-gun-values",
    ]:
        c.check(expected in conflicts, f"missing conflict {expected!r}")
    for item in data.get("conflicts", []):
        c.check(item.get("status") in ("unresolved", "recorded_as_printed",
                                      "resolved_by_verification", "resolved_by_annex",
                                      "resolved_by_scenario_text", "resolved_by_dated_forms"),
                f"conflict {item.get('id')!r} has unknown status {item.get('status')!r}")
        c.check(bool(item.get("detail")), f"conflict {item.get('id')!r} needs detail")
    c.check(bool(data.get("pending_items")), "pending_items must not be empty")
    for entry in data.get("pending_items", []):
        c.check(isinstance(entry, str) and entry.strip(), "pending item must be a non-empty string")


def main() -> int:
    c = Checker()
    if not TARGET.exists():
        print(f"FAIL: {TARGET} does not exist")
        return 1
    data = load_json(TARGET)

    check_structure(c, data)
    check_scenario_source(c, data)
    check_rosters(c, data)
    check_start_options(c, data)
    check_rules_and_objectives(c, data)
    check_page_registrations(c, data)
    check_cross_package_refs(c, data)
    check_conflicts_and_pending(c, data)

    if c.failures:
        print(f"FAIL: {len(c.failures)} problem(s) in {TARGET.name}")
        for failure in c.failures:
            print(f"  - {failure}")
        return 1
    print(f"OK: {TARGET.name} passed "
          f"(14 named ships: 9 allied / 5 axis; scenario Rising Sun PDF 65 / printed 64; "
          f"{len(FORM10_PAGES)} verified Form 10 pages; {len(c.failures)} failures)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
