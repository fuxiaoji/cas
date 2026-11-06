"""Validate the local radar sources and first-pass surface arithmetic fixtures."""

from hashlib import sha256
from json import loads
from math import isclose
from pathlib import Path


HERE = Path(__file__).resolve().parent
data = loads((HERE / "radar-source.json").read_text(encoding="utf-8"))
acquisition = data["acquisition"]
clutter = data["clutter"]
los = data["surface_los"]
sets = data["sets"]
fixtures = data["fixtures"]


def clutter_range(nominal, generation, eligible):
    net = max(eligible, default=0) - clutter["resistance_by_generation"][str(generation)]
    # The printed table starts at positive net clutter. Nonpositive means no reduction.
    if net <= 0:
        return nominal
    return nominal * next(factor for low, high, factor in clutter["printed_range_factors"] if low <= net <= high)


def effective_range(case, radar):
    if case.get("land_blocks"):
        return 0.0
    obs = acquisition["surface_class_column"][case["observer_class"]]
    target = acquisition["surface_class_column"][case["target_class"]]
    col = clutter["profiles"].index(radar["clutter_profile"])
    eligible = [clutter["sea_state"][str(case["sea_state"])][col]]
    for fixture_key, rule_key in (("rain", "precipitation"), ("land", "land")):
        if value := case.get(fixture_key):
            eligible.append(clutter[rule_key][value][col])
    nominal = radar["surface_range_nmi"][acquisition["target_columns"].index(target)]
    horizon = los["observer_rows_nmi"][obs][los["target_columns"].index(target)]
    return min(horizon, clutter_range(nominal, radar["generation"], eligible))


source_root = HERE.parent.parent / "CAS带翻译" / "CAS带翻译"
for source in data["sources"].values():
    (file,) = source_root.rglob(source["file"])
    with file.open("rb") as f:
        digest = sha256()
        while chunk := f.read(1024 * 1024):
            digest.update(chunk)
    assert digest.hexdigest() == source["sha256"], file

assert data["status"] == "source_transcribed_not_active"
assert len(data["cape_st_george"]["ships"]) == 10
for ship in data["cape_st_george"]["ships"].values():
    assert all(set_id in sets for set_id in ship["sets"]), ship

for case in fixtures["acquisition"]:
    radar = sets[case["set"]]
    maximum = effective_range(case, radar)
    acquired = maximum > 0 and case["distance_nmi"] <= maximum and case["roll"] <= acquisition["chance_by_generation_pct"][str(radar["generation"])]
    assert isclose(maximum, case["expected_effective_range_nmi"]), (case, maximum)
    assert acquired == case["expected_acquired"], (case, acquired)

for case in fixtures["printed_clutter_examples"]:
    actual = clutter_range(case["nominal_nmi"], case["generation"], case["eligible_clutter"])
    assert isclose(actual, case["expected_effective_range_nmi"]), (case, actual)

for case in fixtures["muzzle_flash_examples"]:
    assert case["gs"] == 4 and case["band"] == "long"
    hit = case["base_pct"] + 2 * (sum(case["other_modifiers"]) + case["muzzle_flash_modifier"])
    assert hit == case["expected_raw_hit_pct"] and (hit >= 0) == case["legal"], (case, hit)

print(f"Radar source: {len(data['sources'])} local hashes, 10 scenario ship records, {sum(map(len, fixtures.values()))} arithmetic fixtures passed (not runtime).")
