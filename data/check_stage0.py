"""Check source-shaped CAS Stage 0 data and independently transcribed golden rows."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / "data" / "stage0.json"
ORIGINALS = ROOT / "CAS带翻译" / "CAS带翻译"


def nearest(rows, run, spread, stationary=False):
    selectable = [r for r in rows if len(r[1][spread - 1]) == spread]
    index = min(
        range(len(selectable)),
        key=lambda i: (abs(selectable[i][0] - run), -selectable[i][0]),
    )
    if stationary:
        index = max(index - 2, 0)
    yd, probabilities = selectable[index]
    return yd, probabilities[spread - 1]


def fired_mounts(weapon, heading, field):
    def bears(arc):
        start, end = arc
        return start <= heading <= end if start <= end else heading >= start or heading <= end

    return sum(
        m[field] for m in weapon["mounts"] if bears(m["arc"]) or (
            "arc2" in m and bears(m["arc2"])
        )
    )


def main():
    data = json.loads(PACK.read_text(encoding="utf-8"))
    rules = data["rules"]
    ships = {s["id"]: s for s in data["ships"]}
    expected = {
        # actual class, turn class, max speed, full DP, belt, deck, in-service year,
        # normal turn advance (yd), loss (kt), main gun barrel count
        "fletcher": ("C", "A", 37, 144, 0, 0, 1942, 400, 2, 5),
        "cleveland": ("B", "B", 33, 336, 13, 6, 1942, 300, 2, 12),
        "kagero": ("C", "C", 35, 138, 0, 0, 1939, 300, 1, 6),
        "sendai": ("C", "C", 32, 217, 4, 2, 1924, 300, 1, 7),
    }
    assert ships.keys() == expected.keys()
    assert {s["side"] for s in ships.values()} == {"allies", "axis"}
    for id_, s in ships.items():
        assert (
            s["size"], s["turn_size"], s["max_knots"], s["dp"], s["armor_belt"],
            s["armor_deck"], s["in_service_year"], s["turn_advance_yards"],
            s["speed_loss_knots"], s["gun"]["barrels"],
        ) == expected[id_]
        assert s["damage_speed"][0] == {"damage": 0, "knots": s["max_knots"]}
        assert s["damage_speed"][-1] == {"damage": s["dp"], "knots": 0}
        assert all(
            a["damage"] < b["damage"] and a["knots"] >= b["knots"]
            for a, b in zip(s["damage_speed"], s["damage_speed"][1:])
        )
        assert s["gun"]["gs"] == 4
        assert s["gun"]["range_yd"] == sorted(set(s["gun"]["range_yd"]))
        for weapon, count in ((s["gun"], "barrels"), (s["torpedo"], "tubes")):
            if weapon:
                assert sum(m[count] for m in weapon["mounts"]) == weapon[count]
    f = ships["fletcher"]
    c = ships["cleveland"]
    k = ships["kagero"]
    s = ships["sendai"]
    assert fired_mounts(f["gun"], 0, "barrels") == 2
    assert fired_mounts(f["gun"], 90, "barrels") == 5
    assert fired_mounts(f["gun"], 180, "barrels") == 2
    assert fired_mounts(c["gun"], 270, "barrels") == 12
    assert fired_mounts(k["gun"], 180, "barrels") == 4
    assert fired_mounts(s["gun"], 270, "barrels") == 6
    assert fired_mounts(f["torpedo"], 10, "tubes") == 0
    assert fired_mounts(f["torpedo"], 90, "tubes") == fired_mounts(f["torpedo"], 270, "tubes") == 10
    assert fired_mounts(s["torpedo"], 270, "tubes") == 4
    assert c["torpedo"] is None
    assert [(u["torpedo"]["range_yd"], u["torpedo"]["warhead"]) for u in (f, k, s)] == [
        (6000, 87), (22000, 95), (10900, 87)
    ]
    assert rules["visual_chance_yd"]["32000"] == [32000, 29000, 26000, 22500, 19500]
    assert rules["visual_chance_yd"]["34000"][2] == 27500
    assert rules["visual_chance_yd"]["36000"][3] == 25500
    assert "29000" not in rules["visual_chance_yd"]  # known missing decimal in printed cell
    assert rules["gun_belt_chance"] == [100, 100, 40, 30]
    assert rules["gun_base_hit"]["4"] == [60, 40, 15, 5]
    assert rules["gun_damage_multiplier"][5] == [6, 4, 3, 2]  # 12 barrels
    assert rules["critical_damage_ratio_d6"][3][3] == 2  # printed 0.35, die 4 example
    assert rules["critical_hit_d20"]["underwater"][3] == "flooding"
    assert rules["critical_hit_d20"]["minor_surface"][19] == "rudder*"
    assert rules["damage_control_d6"][8] == [1, 1, 1, 2]
    assert rules["torpedo_danger_half_width_yd"] == 500
    ranges = {"II": (44, 39000), "III": (35, 30000), "IV": (28, 23000), "V": (27, 22000), "VI": (25, 20000)}
    for name, rows in rules["torpedo_hit"].items():
        assert (len(rows), rows[-1][0]) == ranges[name]
        assert [yd for yd, _ in rows] == sorted({yd for yd, _ in rows})
        for _, panels in rows:
            assert len(panels) == 6
            for n, panel in enumerate(panels, 1):
                assert len(panel) in (0, n) and all(0 <= p <= 90 for p in panel)
                assert panel == sorted(panel, reverse=True)
    t = rules["torpedo_hit"]
    assert nearest(t["II"], 1400, 3) == (1500, [87, 37, 12])  # source example
    assert nearest(t["III"], 1000, 5) == (1000, [90, 35, 22, 7, 1])
    assert nearest(t["IV"], 1000, 4) == (1000, [61, 16, 3, 1])
    assert nearest(t["V"], 1000, 5) == (1000, [49, 10, 4, 2, 1])
    assert nearest(t["VI"], 1000, 5) == (1000, [34, 5, 3, 2, 1])
    assert nearest(t["II"], 8500, 3)[0] == 9000  # exactly halfway rounds up
    assert nearest(t["III"], 5000, 1, stationary=True)[0] == 3500
    assert nearest(t["VI"], 20000, 4)[0] == 18000  # no invented fourth-spread row
    if ORIGINALS.is_dir():
        for record in data["documents"].values():
            with (ORIGINALS / record["path"]).open("rb") as file:
                assert hashlib.file_digest(file, "sha256").hexdigest() == record["sha256"]
    print("CAS Stage 0: four hulls, 159 torpedo range rows, firing-arc fixtures and source hashes verified")


if __name__ == "__main__":
    main()
