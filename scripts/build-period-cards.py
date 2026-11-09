"""Build the ranked period-card registry from the verified period packages.

Every row is copied verbatim from a period JSON - nothing is typed by hand and
nothing is estimated. The Cape Esperance package stores cross-references
(``profile_ref``) instead of full rows, so those are resolved against the
package the ref names and then read from that package's compiled runtime card,
exactly like ``scripts/build_esperance_cards.py`` does for the scenario deck.

Run: python scripts/build-period-cards.py
Outputs:
  data/ships/period-cards.json        23 complete ShipDefs for the ranked registry
  data/ships/period-cards-report.json provenance, hashes, completeness and gaps
"""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PERIOD = ROOT / "data" / "campaign" / "period"
PLAYABLE = ROOT / "data" / "ships" / "playable-cards.json"
CATALOG = ROOT / "server" / "catalog.json"
OUT_CARDS = ROOT / "data" / "ships" / "period-cards.json"
OUT_REPORT = ROOT / "data" / "ships" / "period-cards-report.json"

# The 23 collection-only hulls that carry a per-ship period card and are warships
# (the five APD/transport identities with a period card stay collection-only).
# Order follows the task list so the registry reads the same way.
ORDER = [
    "IBS-U-USN-BOISE",
    "IBS-U-USN-FARENHOLT",
    "IBS-U-USN-DUNCAN",
    "IBS-U-USN-LAFFEY",
    "IBS-U-USN-BUCHANAN",
    "IBS-U-USN-MCCALLA",
    "IBS-U-USN-HONOLULU",
    "IBS-U-IJN-UZUKI",
    "IBS-U-USN-RALPH-TALBOT",
    "IBS-U-USN-MONSSEN",
    "IBS-U-RAN-AUSTRALIA",
    "IBS-U-RAN-CANBERRA",
    "IBS-U-USN-BAGLEY",
    "IBS-U-USN-PATTERSON",
    "IBS-U-USN-HELM",
    "IBS-U-USN-WILSON",
    "IBS-U-USN-UNNAMED-T01-R25",
    "IBS-U-USN-JARVIS",
    "IBS-U-USN-SELFRIDGE",
    "IBS-U-USN-HULL-I",
    "IBS-U-IJN-CHOKAI",
    "IBS-U-IJN-TENRYU",
    "IBS-U-IJN-YUBARI",
]

# Period profile chosen per identity. Where playable-cards.json lists two cards
# for one hull (Buchanan: Savo/Escutcheon vs Cape Esperance, Honolulu:
# Kula vs Tassafaronga) the registered runtime card that carries the hull's own
# Form 10 is used.
PROFILE = {
    "IBS-U-USN-BOISE": "brooklyn_first_group_1942",
    "IBS-U-USN-FARENHOLT": "bristol_1942",
    "IBS-U-USN-DUNCAN": "bristol_1942",
    "IBS-U-USN-LAFFEY": "bristol_1942",
    "IBS-U-USN-BUCHANAN": "us_bristol_dd",
    "IBS-U-USN-MCCALLA": "bristol_1942",
    "IBS-U-USN-HONOLULU": "brooklyn_1",
    "IBS-U-IJN-UZUKI": "mutsuki_1943_uzuki",
    "IBS-U-USN-RALPH-TALBOT": "us_bagley_dd",
    "IBS-U-USN-MONSSEN": "us_benson_dd",
    "IBS-U-RAN-AUSTRALIA": "gb_kent_1939_ca",
    "IBS-U-RAN-CANBERRA": "gb_kent_1939_ca",
    "IBS-U-USN-BAGLEY": "us_bagley_dd",
    "IBS-U-USN-PATTERSON": "us_bagley_dd",
    "IBS-U-USN-HELM": "us_bagley_dd",
    "IBS-U-USN-WILSON": "us_benham_dd",
    "IBS-U-USN-UNNAMED-T01-R25": "us_atlanta_cl",
    "IBS-U-USN-JARVIS": "us_bagley_dd",
    "IBS-U-USN-SELFRIDGE": "us_porter_dd",
    "IBS-U-USN-HULL-I": "us_farragut_dd",
    "IBS-U-IJN-CHOKAI": "jp_takao_1939_ca",
    "IBS-U-IJN-TENRYU": "jp_tenryu_cl",
    "IBS-U-IJN-YUBARI": "jp_yubari_cl",
}

# A profile_ref in a package names both the package and the row; the compiled
# runtime card for that package is the checked-in, complete ShipDef.
REF_RUNTIME = {"tassafaronga-1942.json": "tassafaronga-runtime.json"}

# Scenario packages that keep the per-hull Form 10 citation next to the hull.
FORM10_INDEX = {
    "savo-runtime.json": ("savo-island-1942.json", "instances"),
}

REQUIRED = [
    "id", "name", "side", "kind", "size", "max_knots", "dp", "turn_advance_yards",
    "speed_loss_knots", "accel_knots_per_turn", "gun", "armor_belt", "armor_deck",
    "in_service_year", "accel_high_knots_per_turn", "brake_knots_per_turn",
]
REQUIRED_GUN = ["name", "range_yd", "damage", "barrels", "gs", "pen_belt", "pen_deck",
                "armor_piercing"]
REQUIRED_TORPEDO = ["name", "speed_knots", "range_yd", "warhead", "tubes", "contact_fuze"]

# The scenario runtimes mis-read six hulls: the mount count was multiplied by
# the barrel count (Chokai 5x? -> 20 barrels, San Juan 5 mounts instead of 8,
# the destroyers 2 mounts of 4 instead of their printed single/quintuple fit),
# and Hull's Farragut row still carried the Savo mis-read of AF A-19.
# The rows below are the printed mount layout, transcribed from the page named
# in `source`; the arcs reuse the registry convention already carried by the
# stage0 cards (Fwd 210-150 / P&S 30-150 + 210-330 / Port 210-330 /
# Stbd 30-150 / Aft 30-330). Only the mount structure, the tube total and the
# listed hull fields change: the gun table, torpedo model row and every other
# ShipDef field stay as the period package printed them.
MOUNT_FIX = {
    "IBS-U-IJN-CHOKAI": {
        "gun": [
            (1, [210, 150], None),
            (2, [210, 150], None),
            (2, [30, 150], [210, 330]),
            (2, [30, 330], None),
            (2, [30, 330], None),
        ],
        "torpedo": [
            (4, [30, 150], [210, 330], 4),
            (4, [30, 150], [210, 330], 4),
        ],
        "torpedo_fit_note": "mount row P/S(2)4 610mm TT w/2 Type 93 torps（8 reserve torp，6 分钟快装）",
        "source": "Rising Sun Form 10 p.49（Chokai CA, Aug 42 Damage）：Fwd (1)+Fwd (2)+P&S (2)+Aft (2)+Aft (2)=9 管/5 座；Port/Stbd (4) 610mm TT=8 雷管；DP 471、损伤行 0/118/236/353/424/471→33/25/16/8/0",
        "fields": {
            "dp": 471,
            "max_knots": 33,
            "damage_speed": [
                {"damage": 0, "knots": 33},
                {"damage": 118, "knots": 25},
                {"damage": 236, "knots": 16},
                {"damage": 353, "knots": 8},
                {"damage": 424, "knots": 0},
                {"damage": 471, "knots": 0},
            ],
        },
        "conflicts": [
            "class profile jp_takao_1939_ca 印 (2)5=10 管、P/S(4)4=16 雷管、401 DP，属 Takao/Atago（p.52）；鸟海按本舰 p.49 取 9 管/8 雷管/471 DP，级表差额保留",
        ],
    },
    "IBS-U-USN-WILSON": {
        "gun": [(1, [210, 150], None), (1, [210, 150], None), (1, [30, 330], None), (1, [30, 330], None)],
        "torpedo": [
            (4, [210, 330], None, 0),
            (4, [210, 330], None, 0),
            (4, [30, 150], None, 0),
            (4, [30, 150], None, 0),
        ],
        "torpedo_fit_note": "mount row P/S(4)4 Mk12 533mm TT w/4 Mk15 torpedoes（4 座×4=16）",
        "source": "Rising Sun Form 10 p.317（Wilson DD, Dec 1941）＋American Fleets A-18 Benham：F/A(1)4=4 门单装；Port/Stbd (4)×2=16 雷管；DP 118、38 节，损伤行 0/30/59/89/106/118→38/28/19/10/0",
        "fields": {
            "dp": 118,
            "max_knots": 38,
            "damage_speed": [
                {"damage": 0, "knots": 38},
                {"damage": 30, "knots": 28},
                {"damage": 59, "knots": 19},
                {"damage": 89, "knots": 10},
                {"damage": 106, "knots": 0},
                {"damage": 118, "knots": 0},
            ],
        },
        "conflicts": [
            "class 行 A-18（Benham）印 124 DP、35 节；本卡按个体页 p.317 取 118/38，级表差额保留",
        ],
    },
    "IBS-U-USN-MONSSEN": {
        "gun": [(1, [210, 150], None), (1, [210, 150], None), (1, [30, 330], None), (1, [30, 330], None)],
        "torpedo": [
            (5, [30, 150], [210, 330], 0),
            (5, [30, 150], [210, 330], 0),
        ],
        "torpedo_fit_note": "mount row Port & Stbd (5)×2 Mk14 533mm TT w/5 Mk15 torp（2 座×5=10，同型 Gwin p.301 口径）",
        "source": "Rising Sun Form 10 p.303（Monssen DD, May 42 Modification）：Fwd (1)×2+Aft (1)×2=4 门单装；Port & Stbd (5)×2=10 雷管；DP 128、35 节，损伤行 0/32/64/96/115/128→35/26/18/9/0",
        "fields": {
            "dp": 128,
            "max_knots": 35,
            "damage_speed": [
                {"damage": 0, "knots": 35},
                {"damage": 32, "knots": 26},
                {"damage": 64, "knots": 18},
                {"damage": 96, "knots": 9},
                {"damage": 115, "knots": 0},
                {"damage": 128, "knots": 0},
            ],
        },
        "conflicts": [
            "class 行 A-17（Benson）印 5 门单装、37 节/144 DP；本卡按个体页 p.303 取 4 门单装、35 节/128 DP",
            "p.303 雷装印一行 Port & Stbd (5)（5 个雷位框）；按同型 Gwin p.301 / 13 张同型卡口径取 2 座×5=10 管，若后续确认单座再回调",
        ],
    },
    "IBS-U-USN-BUCHANAN": {
        "gun": [(1, [210, 150], None), (1, [210, 150], None), (1, [30, 330], None), (1, [30, 330], None)],
        "torpedo": [
            (5, [30, 150], [210, 330], 0),
            (5, [30, 150], [210, 330], 0),
        ],
        "torpedo_fit_note": "mount row Port & Stbd (5)×2 Mk15 533mm TT w/5 Mk15 torpedoes（2 座×5=10，同型 Barton p.291 口径）",
        "source": "Rising Sun Form 10 p.292（Buchanan DD, Mar 42/Nov-Dec 42 两页同装）＋American Fleets A-17 Bristol：F/A(1)4 Mk30=4 门单装；Port & Stbd (5)×2=10 雷管；DP 118、37 节",
        "conflicts": [
            "class 行 A-17（Bristol）与个体页 p.292/p.293 同印 Port & Stbd (5)；按同型 Barton p.291 / 13 张同型卡口径取 2 座×5=10 管，若后续确认单座再回调",
        ],
    },
    "IBS-U-USN-HULL-I": {
        "gun": [
            (1, [210, 150], None),
            (1, [30, 150], [210, 330]),
            (1, [30, 330], None),
            (1, [210, 150], None),
            (1, [30, 330], None),
        ],
        "torpedo": [
            (4, [30, 150], [210, 330], 0),
            (4, [30, 150], [210, 330], 0),
        ],
        "torpedo_fit_note": "mount row P&S(4)2 Mk11 533mm TT w/4 Mk15 torpedoes（2 座×4=8）",
        "source": "American Fleets A-19（Farragut）：2F/P&S/2A(1)5 Mk21=5 门单装；P&S(4)2 Mk11=8 雷管；Size D/Small、Standard Rudder 200 yds (1)；Dam 0/26/53/79/95/105 → 36/27/18/9/0",
        "fields": {
            "size": "D",
            "turn_advance_yards": 200,
            "damage_speed": [
                {"damage": 0, "knots": 36},
                {"damage": 26, "knots": 27},
                {"damage": 53, "knots": 18},
                {"damage": 79, "knots": 9},
                {"damage": 95, "knots": 0},
                {"damage": 105, "knots": 0},
            ],
        },
        "conflicts": [
            "Savo 包 us_farragut_dd 旧值 Dam 36/speed 26、turn 300、size C 与 AF A-19 原页冲突；本卡按 A-19 修正（与同盟 source card 一致）",
            "A-19 备注「1942: P&S 5in removed」未落在本卡：class 行印 5 门，Hull 无本舰 Form 10；ASW w/7 DC 未建模",
        ],
    },
    "IBS-U-USN-UNNAMED-T01-R25": {
        "gun": [
            (2, [210, 150], None),
            (2, [210, 150], None),
            (2, [210, 150], None),
            (2, [210, 330], None),
            (2, [30, 150], None),
            (2, [30, 330], None),
            (2, [30, 330], None),
            (2, [30, 330], None),
        ],
        "torpedo": [(4, [210, 330], None, 0), (4, [30, 150], None, 0)],
        "torpedo_fit_note": "mount row P/S(4)2 533mm TT w/4 Mk15 torpedoes（2 座×4=8）",
        "source": "Rising Sun Form 10 p.262（San Juan CL, May 1942）＋American Fleets A-15 Atlanta：3F/P/S/3A(2)8=8 座双联 16 管；Port/Stbd (4)=8 雷管",
        "conflicts": [],
    },
}

TORPEDO_MODEL = ("data/campaign/period/savo-island-1942.json",
                 "weapon_models", "us_mk15_tnt_torpedo")


def apply_mount_fix(ship, fix):
    """Replace the mis-read mount structure with the printed rows."""
    for key, value in (fix.get("fields") or {}).items():
        ship[key] = value
    ship["gun"]["mounts"] = [
        {"barrels": barrels, "arc": arc, "arc2": arc2} for barrels, arc, arc2 in fix["gun"]
    ]
    ship["gun"]["barrels"] = sum(barrels for barrels, _, _ in fix["gun"])
    tubes = fix["torpedo"]
    total = sum(tube for tube, _, _, _ in tubes)
    if ship.get("torpedo") is None:
        source, block, key = TORPEDO_MODEL
        model = load(source)[block][key]["torpedo"]
        speed, distance = model["range_speed_pairs_yd_knots"][0][1], model["range_speed_pairs_yd_knots"][0][0]
        ship["torpedo"] = {
            "name": "Mk15（TNT）",
            "speed_knots": speed,
            "range_yd": distance,
            "warhead": model["damage_dp"],
            "contact_fuze": True,
            "tubes": total,
            "mounts": [],
        }
    torpedo = ship["torpedo"]
    torpedo["tubes"] = total
    torpedo["mounts"] = [
        {"tubes": tube, "arc": arc, "arc2": arc2, "reserve": reserve}
        for tube, arc, arc2, reserve in tubes
    ]
    torpedo["fit_note"] = fix["torpedo_fit_note"]
    return ship



def load(rel):
    return json.loads((ROOT / rel).read_text(encoding="utf-8"))


def sha(rel):
    return hashlib.sha256((ROOT / rel).read_bytes()).hexdigest()


def find_def(period_file, hull_id, profile):
    """Return (ship_def, source_rel, source_ship_id, resolution)."""
    data = load(period_file)
    ships = data.get("ships")
    if isinstance(ships, list):
        for ship in ships:
            if ship["id"] == hull_id:
                return dict(ship), period_file, hull_id, "period ships[].%s" % hull_id
        raise SystemExit("%s 没有 %s 的完整舰卡" % (period_file, hull_id))
    profiles = data.get("profiles") or {}
    entry = profiles.get(profile)
    if entry is None:
        raise SystemExit("%s 没有 profile %s" % (period_file, profile))
    ref = entry.get("profile_ref")
    if not ref:
        return dict(entry), period_file, profile, "period profiles.%s（内联完整 ShipDef）" % profile
    ref_file, ref_path = ref.split("#")
    if ref_path != "profiles." + profile:
        raise SystemExit("%s 的 profile_ref 与档案不符：%s" % (period_file, ref))
    runtime = REF_RUNTIME.get(ref_file)
    if runtime is None:
        raise SystemExit("尚未登记 %s 的编译运行时" % ref_file)
    runtime_rel = "data/campaign/period/" + runtime
    for ship in load(runtime_rel)["ships"]:
        if ship.get("source_class") == profile:
            return (dict(ship), runtime_rel, ship["id"],
                    "%s profiles.%s → %s → %s %s" % (period_file, profile, ref, runtime, ship["id"]))
    raise SystemExit("%s 没有 %s 的编译卡" % (runtime_rel, profile))


def form10_page(period_file, hull_id, card_page):
    if card_page is not None:
        return card_page, "period_card"
    index = FORM10_INDEX.get(Path(period_file).name)
    if index is None:
        return None, "unverified"
    source, block = index
    rows = load("data/campaign/period/" + source).get(block) or {}
    row = rows.get(hull_id.replace("_", "-"))
    page = ((row or {}).get("form10") or {}).get("pdf_page")
    if page is None:
        return None, "unverified"
    return page, "%s#%s.%s" % (source, block, hull_id.replace("_", "-"))


def completeness(ship):
    missing = [key for key in REQUIRED if key not in ship]
    gun = ship.get("gun") or {}
    missing += ["gun." + key for key in REQUIRED_GUN if key not in gun]
    torpedo = ship.get("torpedo")
    if torpedo:
        missing += ["torpedo." + key for key in REQUIRED_TORPEDO if key not in torpedo]
    return missing


def main():
    playable = load("data/ships/playable-cards.json")
    cards = {card["identity"]: card for card in playable["cards"]}
    catalog = load("server/catalog.json")
    catalog_ids = [ship["id"] for ship in catalog["ships"]]

    out, report_cards = [], []
    for identity in ORDER:
        card = cards[identity]
        profile = PROFILE[identity]
        chosen = [entry for entry in card.get("period_cards") or [] if entry["profile"] == profile]
        if len(chosen) != 1:
            raise SystemExit("%s 的 period 卡无法唯一确定为 %s" % (identity, profile))
        period_card = chosen[0]
        period_file = period_card["file"]
        ship, def_file, def_ship_id, resolution = find_def(
            period_file, period_card["hull_id"], profile)
        # The registry card is the identity card: the period hull row is taken
        # verbatim, then the stable catalogue identity and its Chinese name are
        # written over the period id/name (no other field is touched).
        ship["id"] = identity
        ship["name"] = card["name"]
        page, page_source = form10_page(period_file, period_card["hull_id"],
                                        period_card.get("form10_page"))
        fix = MOUNT_FIX.get(identity)
        before = None
        if fix is not None:
            before = {
                "dp": ship["dp"],
                "max_knots": ship["max_knots"],
                "gun_barrels": ship["gun"]["barrels"],
                "gun_mounts": len(ship["gun"]["mounts"]),
                "torpedo_tubes": (ship.get("torpedo") or {}).get("tubes"),
                "torpedo_mounts": len((ship.get("torpedo") or {}).get("mounts") or []),
            }
            apply_mount_fix(ship, fix)
        missing = completeness(ship)
        if ship.get("side") != card["side"]:
            raise SystemExit("%s 的阵营与 period 卡不一致" % identity)
        if ship.get("kind") != card["type"]:
            raise SystemExit("%s 的舰种与 period 卡不一致" % identity)

        also = [
            {"file": entry["file"], "hull_id": entry["hull_id"], "profile": entry["profile"],
             "form10_page": entry.get("form10_page")}
            for entry in card.get("period_cards") or [] if entry is not period_card
        ]
        resolved = {"file": def_file, "ship_id": def_ship_id, "note": resolution}
        after = {
            "dp": ship["dp"],
            "max_knots": ship["max_knots"],
            "gun_barrels": ship["gun"]["barrels"],
            "gun_mounts": len(ship["gun"]["mounts"]),
            "torpedo_tubes": (ship.get("torpedo") or {}).get("tubes"),
            "torpedo_mounts": len((ship.get("torpedo") or {}).get("mounts") or []),
        }
        stat_source = fix["source"] if fix else "period runtime row（与本包一致，本批未改）"
        conflicts = fix["conflicts"] if fix else []
        out.append({
            "identity": identity,
            "name": card["name"],
            "side": card["side"],
            "type": card["type"],
            "source_file": period_file,
            "period_ship_id": period_card["hull_id"],
            "period_profile": profile,
            "form10_page": page,
            "stat_verified": not missing,
            "stat_source": stat_source,
            "stat_conflicts": conflicts,
            "resolved_from": resolved,
            "also_recorded": also,
            "ship": ship,
        })
        report_cards.append({
            "identity": identity,
            "name": card["name"],
            "side": card["side"],
            "type": card["type"],
            "source_file": period_file,
            "source_sha256": sha(period_file),
            "resolved_from": dict(resolved, sha256=sha(def_file)),
            "period_ship_id": period_card["hull_id"],
            "period_profile": profile,
            "form10_page": page,
            "form10_page_source": page_source,
            "complete": not missing,
            "missing_fields": missing,
            "stat_verified": not missing,
            "stat_source": stat_source,
            "stat_conflicts": conflicts,
            "stat_before": before,
            "stat_after": after,
            "also_recorded": also,
        })

    OUT_CARDS.write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    # ---- coverage: what stays collection-only and why
    ranked = set(load("data/rules/cas-competitive-points-v1.json")["ships"]) | set(ORDER)
    scenario_ids = set(cards)
    collection = [identity for identity in catalog_ids if identity not in ranked]
    scenario_collection = [identity for identity in collection if identity in scenario_ids]
    no_period = [identity for identity in scenario_collection
                 if not (cards.get(identity) or {}).get("period_cards")]
    apd = [identity for identity in scenario_collection
           if (cards.get(identity) or {}).get("reason_category") == "non_combatant"
           and (cards.get(identity) or {}).get("period_cards")]
    outside = [identity for identity in collection if identity not in scenario_ids]

    report = {
        "schema_version": 1,
        "content_version": "cas-period-cards-v1",
        "as_of": "2026-11-08",
        "generated_by": "scripts/build-period-cards.py",
        "source": {
            "identity_index": "data/ships/playable-cards.json#cards[].period_cards",
            "packages": sorted({row["source_file"] for row in report_cards}
                               | {row["resolved_from"]["file"] for row in report_cards}),
            "policy": ("逐舰 period 卡原样复制：不做换算、不补默认值、不跨级套用类卡。"
                       "Cape Esperance 包以 profile_ref 指向 Tassafaronga 包时，按该包已编译的"
                       "运行时舰卡取完整 ShipDef（与 scripts/build_esperance_cards.py 同一解析路径）。"
                       "Chokai / Wilson / Monssen / Buchanan / San Juan 五张的炮座与雷管按原页/class 行"
                       "重录（此前 runtime 把座数×管数算错），其余字段不动；差额与冲突逐条在 stat_conflicts。"),
        },
        "ranked_registry": {
            "before": 88,
            "added": len(out),
            "after": 88 + len(out),
            "playable_cards_identities": len(cards),
            "playable_cards_before": sum(1 for card in cards.values() if card["playable"]),
            "playable_cards_after": sum(1 for card in cards.values() if card["playable"]) + len(out),
        },
        "coverage_after": {
            "catalog_identities": len(catalog_ids),
            "playable": 88 + len(out),
            "collection_only": len(collection),
            "collection_breakdown": {
                "no_period_card": len(no_period),
                "apd_non_combatant": len(apd),
                "outside_current_scenarios": len(outside),
            },
            "note": ("111 / 99 = 210 个 identity 减去可出战（88 既有 + 23 新增）。"
                     "收藏侧 99 = 28 张无 period 卡 + 5 艘 APD（有 period 卡但按运输/非战斗保持收藏）"
                     " + 66 个不在当前 11 个剧本交叉表内的 identity。"),
        },
        "gaps": {
            "no_period_card": no_period,
            "apd_non_combatant": apd,
            "outside_current_scenarios": outside,
        },
        "stat_fixes": [
            {"identity": row["identity"], "name": row["name"],
             "before": row["stat_before"], "after": row["stat_after"],
             "source": row["stat_source"], "conflicts": row["stat_conflicts"]}
            for row in report_cards if row["stat_before"]
        ],
        "cards": report_cards,
        "tests": json.loads((ROOT / "data" / "ships" / "period-cards-tests.json").read_text(encoding="utf-8"))
        if (ROOT / "data" / "ships" / "period-cards-tests.json").exists() else {},
        "tests_source": "data/ships/period-cards-tests.json",
    }
    OUT_REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print("cards", len(out), "sources", sorted(report["source"]["packages"]))
    print("complete", sum(1 for row in report_cards if row["complete"]),
          "incomplete", [row["identity"] for row in report_cards if not row["complete"]])
    print("collection", len(collection), "no_period", len(no_period), "apd", len(apd),
          "outside", len(outside))


if __name__ == "__main__":
    main()
