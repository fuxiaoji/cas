#!/usr/bin/env python3
"""Build the 91 verified hulls that take the ranked registry from 111 to 202.

Sources (read-only inputs):
  data/ships/pdf-source-cards.json          12 per-hull Form 10 transcriptions
  data/ships/apd-source-cards.json           8 APD period cards
  data/ships/class-proxy-cards.json         13 same-class proxy cards
  data/ships/cas-source-cards-allies.json   21 CAS source-table cards
  data/ships/cas-source-cards-axis.json     20 CAS source-table cards (3 paper excluded)
  data/ships/erma-source-cards-usn.json     12 ERMA record cards (8 closed by gun rows)
  data/ships/erma-source-cards-ijn.json     11 ERMA record cards (3 without a base table excluded)
  data/ships/historical-axis-cards.json      7 historical class+rule-table cards
  data/rules/gun-rows-erma.json              3 exact Annex C-3 rows for the 8 USN ERMA hulls

Outputs:
  data/ships/merged-cards.json              91 complete ShipDefs + provenance
  src/ranked_profiles_merged.inc            generated Rust `Profile {}` entries
  data/ships/merge-report.json              data-side merge report
  (with --write-cards) data/rules/cas-competitive-points-v1.json gains 91 rows
  (with --write-cards) data/ships/cards.json gains 202/8 identity metadata

The source cards are never modified. Values are copied verbatim from the
registered `ship` object where one exists; the twelve pdf cards and the eight
gun-row-blocked ERMA hulls are rebuilt from their transcribed profile exactly
as printed (mount rows, shell rows, damage/speed rows). The only default used
is the single global CAS 5e p.23 (3-2) movement row for hulls whose source page
prints no turn/acceleration values; every such use is recorded in the card.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
AS_OF = "2026-11-08"
CONTENT_VERSION = "cas-merged-cards-v1"
PROFILE_SOURCE = "provisional（待平衡复核）"

PDF = "pdf-source-cards.json"
APD = "apd-source-cards.json"
PROXY = "class-proxy-cards.json"
ALLIES = "cas-source-cards-allies.json"
AXIS = "cas-source-cards-axis.json"
ERMA_USN = "erma-source-cards-usn.json"
ERMA_IJN = "erma-source-cards-ijn.json"
HIST = "historical-axis-cards.json"
GUN_ROWS = "gun-rows-erma.json"

# Paper / never-built hulls and hulls without any base ship table stay in the
# collection list. They are deliberately absent from the ranked registry.
EXCLUDED = {
    "IBS-U-IJN-AMAGI": ("paper_battlecruiser", "天城级纸面舰；A-48 无转向/加速值，Form 10 无该舰页"),
    "IBS-U-IJN-AKAGI": ("paper_battlecruiser", "赤城级纸面舰；A-48/A-49 无转向/加速值，Form 10 无该舰页"),
    "IBS-U-IJN-OWARI": ("paper_battleship", "纪伊级纸面舰；A-49 无转向/加速值，Form 10 无该舰页"),
    "IBS-U-IJN-ERMA-IBUKI": ("no_base_class_table", "伊吹无重巡基础表：A-10 只有 CVL 改装，Form 10 无 Ibuki 卡"),
    "IBS-U-IJN-ERMA-KURAMA": ("no_base_class_table", "鞍马无重巡基础表：A-10 只有 CVL 改装，Form 10 无 Kurama 卡"),
    "IBS-U-IJN-ERMA-GOKASE": ("no_base_class_table", "五濑无基础表：Emperor's Fleet/Form 10 均无该级条目"),
}

SOURCE_META = {
    PDF: ("form10_individual", "exact"),
    APD: ("period_named", "period_named"),
    PROXY: ("class_proxy", "class_proxy"),
    ALLIES: ("cas_source_table", "exact"),
    AXIS: ("cas_source_table", "exact"),
    ERMA_USN: ("erma_record_image", "exact"),
    ERMA_IJN: ("erma_record_image", "exact"),
    HIST: ("historical_class_table", "exact"),
}

# Global registered default for printed movement gaps: CAS 5e p.23 (3-2).
MOVEMENT = {
    "A": dict(turn_advance_yards=400, speed_loss_knots=2, accel_knots_per_turn=6,
              accel_high_knots_per_turn=3, brake_knots_per_turn=9),
    "B": dict(turn_advance_yards=300, speed_loss_knots=2, accel_knots_per_turn=10,
              accel_high_knots_per_turn=5, brake_knots_per_turn=12),
    "C": dict(turn_advance_yards=300, speed_loss_knots=1, accel_knots_per_turn=12,
              accel_high_knots_per_turn=6, brake_knots_per_turn=15),
    "D": dict(turn_advance_yards=200, speed_loss_knots=1, accel_knots_per_turn=12,
              accel_high_knots_per_turn=6, brake_knots_per_turn=15),
    "E": dict(turn_advance_yards=200, speed_loss_knots=1, accel_knots_per_turn=12,
              accel_high_knots_per_turn=6, brake_knots_per_turn=15),
}

# Readable labels for the gun model slugs used by the rebuilt hulls. The engine
# ignores `gun.name`; the label is for ledger/UI traceability.
GUN_LABEL = {
    "us_16in45_mk6": "Mk6 16in/45",
    "us_mk30_5in38": "Mk30 5in/38",
    "us_mk38_5in38": "Mk38 5in/38",
    "us_5in25_mk13": "Mk13 5in/25",
    "jp_3rd_yr_127mm50": "三年式 12.7cm/50",
    "jp_14in45_mka_type36": "41st Yr Type 36cm/45",
    "jp_14in45_vickers_mka": "Vickers 14in/45",
    "jp_3rd_yr_type_14cm50": "三年式 14cm/50",
    "jp_15cm50_41st_yr": "41st Yr 15cm/50",
    "gb_6in50_mkxxiii": "MkXXIII 6in/50",
    "gb_4in45_mkxvi": "MkXVI 4in/45",
    "us_8in55_mk9_10_11_13_14": "Mk14 8in/55",
    "us_16in50_mk7": "Mk7 16in/50",
    "us_12in50_mk8": "Mk8 12in/50",
    "us_8in55_mk16": "Mk16 8in/55",
    "us_6in47_mk16": "Mk16 6in/47",
}

TORPEDO_LABEL = {
    "jp_type93_m1_mod1_2": "九三式一型 Mod 1/2",
    "jp_8th_yr_type_no2_torpedo": "八年式二号",
    "us_mk15_tnt_torpedo": "Mk15（TNT）",
    "us_mk15_tnt": "Mk15（TNT）",
    "gb_mkix_torpedo": "MkIX",
    "jp_type90_torpedo": "九〇式",
}

SHELL_PRIORITY = {"APC": 0, "AP": 1, "SAP": 2, "SpCOM": 3, "COM": 4, "HC": 5, "HE": 6}
ROMAN = {"I": 1, "II": 2, "III": 3, "IV": 4, "V": 5, "VI": 6}

# Printed conflicts that stay verbatim in the rebuilt ShipDef. They are copied
# into merged-cards.json and the merge report instead of being silently fixed.
KNOWN_CONFLICTS = {
    "IBS-U-USN-WALKE": [
        "p309 的 5in/38 COM 极远段印 25.9 千码；同页 SpCOM 极远行为 14.7 千码、同级正常约 18.2 千码。"
        "按原页保留 25,900 码并登记为印刷异常，未用同级值替换。",
    ],
    "IBS-U-RN-UNNAMED-T05-R01": [
        "crosswalk 把本舰 class_label 记为哈津斯级（Hawkins）；Form 10 p233 与 Home Fleet A-28 均为 Leander 级。"
        "身份元数据按 Leander 级更新，crosswalk 源文件不改。",
    ],
    "IBS-U-IJN-HIEI": [
        "secondary 只收 14 × 15cm/50 舷炮；p39 的 4 × 12.7cm/40 DP 炮座未并入同一 GunDef，登记为未建模差额。",
    ],
    "IBS-U-IJN-KIRISHIMA": [
        "secondary 只收 14 × 15cm/50 舷炮；p40 的 8 × 12.7cm/40 DP 炮座未并入同一 GunDef，登记为未建模差额。",
    ],
    "IBS-U-USN-ERMA-DES-MOINES": [
        "1948 年服役配置被放进 1944 年 ERMA 架空想定；舰卡保留 1948 配置与 source note，不作 1944 年历史卡。",
    ],
    "IBS-U-USN-ERMA-SALEM": [
        "1948 年服役配置被放进 1944 年 ERMA 架空想定；舰卡保留 1948 配置与 source note，不作 1944 年历史卡。",
    ],
}

DASH_ROW = re.compile(r"^([\d.]+)\s*-\s*(\d+)(?:/(\d+))?\s+(\d+)$")
PLAIN_ROW = re.compile(r"^([\d.]+)\s+(\d+)(?:/(\d+))?\s+(\d+)$")
NO_RANGE_ROW = re.compile(r"^(\d+)(?:/(\d+))?\s+(\d+)$")


def load(relative: str) -> Any:
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


def sha256(relative: str) -> str:
    return hashlib.sha256((ROOT / relative).read_bytes()).hexdigest()


def write_json(relative: str, value: Any) -> None:
    path = ROOT / relative
    path.write_text(json.dumps(value, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


def rust_str(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def ints(values: list[Any]) -> list[Any]:
    return [None if value is None else int(value) for value in values]


# --------------------------------------------------------------------------
# Shell-row parsing
# --------------------------------------------------------------------------
def parse_shell_rows(text: str) -> list[dict[str, Any]]:
    rows = []
    for token in text.split(";"):
        token = token.strip()
        match = DASH_ROW.match(token)
        if match:
            rows.append(dict(bound="lower", range=float(match.group(1)), belt=int(match.group(2)),
                             deck=int(match.group(3)) if match.group(3) else None,
                             damage=int(match.group(4))))
            continue
        match = PLAIN_ROW.match(token)
        if match:
            rows.append(dict(bound="upper", range=float(match.group(1)), belt=int(match.group(2)),
                             deck=int(match.group(3)) if match.group(3) else None,
                             damage=int(match.group(4))))
            continue
        match = NO_RANGE_ROW.match(token)
        if match:
            rows.append(dict(bound="none", range=None, belt=int(match.group(1)),
                             deck=int(match.group(2)) if match.group(2) else None,
                             damage=int(match.group(3))))
            continue
        raise ValueError(f"unparsed shell row: {token!r} in {text!r}")
    return rows


def choose_shell(rows: dict[str, str]) -> tuple[str, list[dict[str, Any]], list[int]]:
    """Pick the surface shell row and its four range-band upper bounds."""
    shells = sorted(rows, key=lambda key: SHELL_PRIORITY.get(key.split()[0], 99))
    chosen = shells[0]
    parsed = {key: parse_shell_rows(value) for key, value in rows.items()}
    rows_chosen = parsed[chosen]
    ranges: list[int] | None = None
    if rows_chosen and all(row["bound"] == "upper" for row in rows_chosen):
        ranges = [int(round(row["range"] * 1000)) for row in rows_chosen]
    else:
        # Another shell on the same gun carries the band upper bounds; the
        # printed table shares one range line between AP/HE shells.
        prefix = chosen.split("/")[0].split()[0] if "/" in chosen else None
        candidates = [key for key in shells if key != chosen]
        if prefix:
            same = [key for key in candidates if key.startswith(prefix)]
            candidates = same + [key for key in candidates if key not in same]
        for key in candidates:
            if parsed[key] and all(row["bound"] == "upper" for row in parsed[key]):
                ranges = [int(round(row["range"] * 1000)) for row in parsed[key]]
                break
    if ranges is None or len(ranges) != 4:
        raise ValueError(f"no four-band range row found for {rows!r}")
    return chosen, rows_chosen, ranges


def gun_from_rows(rows: dict[str, str], label: str, caliber: int, gs: int,
                  mounts: list[dict[str, Any]], armor_piercing: bool | None = None) -> dict[str, Any]:
    shell, shell_rows, ranges = choose_shell(rows)
    if len(shell_rows) != 4:
        raise ValueError(f"{label}: expected four shell bands, got {shell_rows!r}")
    if armor_piercing is None:
        armor_piercing = shell in ("APC", "AP", "SAP", "SpCOM")
    damage = [row["damage"] for row in shell_rows]
    pen_belt = [row["belt"] for row in shell_rows]
    pen_deck = [row["deck"] for row in shell_rows]
    if damage != sorted(damage, reverse=True):
        raise ValueError(f"{label}: damage bands are not descending {damage!r}")
    return {
        "name": f"{label} {shell}",
        "caliber_mm": caliber,
        "shell": shell,
        "range_yd": ranges,
        "damage": damage,
        "pen_belt": pen_belt,
        "pen_deck": pen_deck,
        "armor_piercing": armor_piercing,
        "barrels": sum(mount["barrels"] for mount in mounts),
        "gs": gs,
        "mounts": mounts,
    }


# --------------------------------------------------------------------------
# Mount parsing
# --------------------------------------------------------------------------
def mount_arcs(position: str, barrels: int) -> list[dict[str, Any]]:
    position = position.strip()
    arcs = {
        "F": ([210, 150], None),
        "A": ([30, 330], None),
        "P": ([210, 330], None),
        "S": ([30, 150], None),
        "PW": ([210, 330], None),
        "SW": ([30, 150], None),
        "PA": ([210, 330], None),
        "SA": ([30, 150], None),
        "P&S": ([210, 330], [30, 150]),
        "P/S": ([210, 330], [30, 150]),
    }
    if position not in arcs:
        raise ValueError(f"unknown mount position {position!r}")
    arc, arc2 = arcs[position]
    return [{"barrels": barrels, "arc": list(arc), "arc2": list(arc2) if arc2 else None}]


def mounts_from_profile(entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
    mounts = []
    for entry in entries:
        mounts.extend(mount_arcs(entry["position"], int(entry["barrels"])))
    return mounts


def mounts_from_verbatim(text: str) -> tuple[list[dict[str, Any]], str]:
    """Parse CAS mount rows such as `2F/A(3)3 Mk7 16 in/50` or `P/S(2)10 Mk28`."""
    head, _, rest = text.partition(" ")
    label = rest.split("//")[0].strip()
    match = re.match(r"^([A-Za-z0-9/]+)\((\d+)\)(\d+)$", head)
    if not match:
        raise ValueError(f"unparsed mount head {head!r} in {text!r}")
    positions, barrels, total = match.group(1), int(match.group(2)), int(match.group(3))
    tokens = positions.split("/")
    counts = []
    for token in tokens:
        count = re.match(r"^(\d+)([A-Za-z]+)$", token)
        if count:
            counts.append((count.group(2), int(count.group(1))))
        else:
            counts.append((token, None))
    if all(count is None for _, count in counts):
        if total % len(counts):
            raise ValueError(f"cannot divide {total} mounts over {tokens!r}")
        counts = [(name, total // len(counts)) for name, _ in counts]
    elif any(count is None for _, count in counts):
        unknown = [index for index, (_, count) in enumerate(counts) if count is None]
        remaining = total - sum(count for _, count in counts if count is not None)
        if remaining < 0 or remaining % len(unknown):
            raise ValueError(f"cannot distribute {total} mounts over {tokens!r}")
        for index in unknown:
            counts[index] = (counts[index][0], remaining // len(unknown))
    if sum(count for _, count in counts) != total:
        raise ValueError(f"mount counts {counts!r} do not total {total} in {text!r}")
    mounts = []
    for position, count in counts:
        for _ in range(count):
            mounts.extend(mount_arcs(position, barrels))
    return mounts, label


def caliber_mm(text: str) -> int:
    lowered = text.lower()
    match = re.search(r"(\d+(?:\.\d+)?)\s*in", lowered)
    if match:
        return int(round(float(match.group(1)) * 25.4))
    match = re.search(r"(\d+(?:\.\d+)?)\s*cm", lowered)
    if match:
        return int(round(float(match.group(1)) * 10))
    match = re.search(r"(\d+(?:\.\d+)?)\s*mm", lowered)
    if match:
        return int(round(float(match.group(1))))
    raise ValueError(f"no caliber in {text!r}")


def caliber_from_slug(slug: str) -> int:
    rules = [
        ("us_16in45", 406), ("us_16in50", 406), ("jp_14in45", 356), ("us_12in50", 305),
        ("us_8in55", 203), ("jp_3rd_yr_type_14cm50", 140), ("jp_3rd_yr_127mm50", 127),
        ("us_mk30_5in38", 127), ("gb_6in50_mkxxiii", 152), ("us_6in47_mk16", 152),
        ("jp_3rd_yr_type_14cm50", 140), ("jp_15cm50", 150),
    ]
    for prefix, value in rules:
        if slug.startswith(prefix):
            return value
    raise ValueError(f"no caliber rule for {slug!r}")


def secondary_mounts(profile: dict[str, Any]) -> list[dict[str, Any]]:
    mounts = []
    for entry in profile.get("secondary_mounts") or []:
        kind = entry.get("kind")
        if kind == "DP" and any(other.get("kind") == "casemate" for other in profile.get("secondary_mounts") or []):
            # The casemate battery is the surface secondary; the DP battery is
            # recorded as an unmodelled gap in the card note instead of being
            # folded into the same GunDef.
            continue
        for _ in range(int(entry.get("mounts", 1))):
            mounts.extend(mount_arcs(entry["position"], int(entry.get("barrels", 1))))
    return mounts


def clean_label(text: str) -> str:
    text = text.split("//")[0]
    positions = {"F", "A", "P", "S", "PW", "SW", "PA", "SA", "P&S", "P/S",
                 "Port", "Stbd", "Fwd", "Aft", "Casemate"}
    words = text.split()
    start = 0
    while start < len(words) and (words[start] in positions
                                  or re.fullmatch(r"\d+", words[start])
                                  or re.fullmatch(r"\(\d+\)", words[start])):
        start += 1
    return " ".join(words[start:])


def secondary_label(profile: dict[str, Any]) -> str:
    mounts = profile.get("secondary_mounts_verbatim") or []
    if mounts:
        return clean_label(mounts[0])
    return "secondary"


def secondary_from_profile(profile: dict[str, Any], gs: int) -> dict[str, Any] | None:
    entries = profile.get("secondary_mounts") or []
    rows = profile.get("secondary_shells_verbatim") or {}
    if not entries or not rows:
        return None
    mounts = secondary_mounts(profile)
    if not mounts:
        return None
    casemate = [entry for entry in entries if entry.get("kind") == "casemate"]
    if casemate:
        prefix = casemate[0].get("caliber", "").split("cm")[0] + "cm"
        rows = {key: value for key, value in rows.items() if key.startswith(prefix)} or rows
    shell, shell_rows, ranges = choose_shell(rows)
    if len(shell_rows) != 4:
        raise ValueError("secondary needs four shell bands")
    label = secondary_label(profile)
    return {
        "name": f"{label} {shell}",
        "caliber_mm": caliber_mm(label),
        "shell": shell,
        "range_yd": ranges,
        "damage": [row["damage"] for row in shell_rows],
        "pen_belt": [row["belt"] for row in shell_rows],
        "pen_deck": [row["deck"] for row in shell_rows],
        "armor_piercing": shell in ("APC", "AP", "SAP", "SpCOM"),
        "barrels": sum(mount["barrels"] for mount in mounts),
        "gs": gs,
        "mounts": mounts,
    }


USN_5IN38 = {
    "name": "Mk28/Mk32 5in/38 SpCOM",
    "caliber_mm": 127,
    "shell": "SpCOM",
    "range_yd": [5500, 10900, 14600, 18200],
    "damage": [18, 14, 12, 11],
    "pen_belt": [7, 4, 3, 2],
    "pen_deck": [None, None, 1, 2],
    "armor_piercing": True,
}


def erma_secondary(profile: dict[str, Any], gs: int) -> dict[str, Any] | None:
    """The ERMA profiles print the 5in/38 twin mounts but no shell table; the
    registered C-2 5in/38 row already in the game is the same gun row."""
    text = profile.get("secondary_verbatim")
    if not text:
        return None
    mounts, label = mounts_from_verbatim(text)
    gun = json.loads(json.dumps(USN_5IN38))
    gun["name"] = f"{label or 'Mk28/Mk32 5in/38'} SpCOM"
    gun["caliber_mm"] = caliber_mm(label)
    gun["barrels"] = sum(mount["barrels"] for mount in mounts)
    gun["gs"] = gs
    gun["mounts"] = mounts
    return gun


def torpedo_from_profile(profile: dict[str, Any]) -> dict[str, Any] | None:
    model = profile.get("torpedo_model")
    row_text = (profile.get("torpedo_range_rows_verbatim") or [None])[0]
    if not model or not row_text:
        return None
    match = re.search(r"([\d.]+)\s*kyds?,\s*(\d+)\s*kts?,\s*(\d+)\s*DP", row_text)
    if not match:
        raise ValueError(f"unparsed torpedo row {row_text!r}")
    speed, range_yd, warhead = int(match.group(2)), int(round(float(match.group(1)) * 1000)), int(match.group(3))
    mounts = []
    for row in profile.get("torpedo_mounts_verbatim") or []:
        match_tubes = re.search(r"\((\d+)\)", row)
        if not match_tubes:
            raise ValueError(f"unparsed torpedo mount {row!r}")
        tubes = int(match_tubes.group(1))
        if row.startswith("Port & Stbd"):
            arc, arc2 = [30, 150], [210, 330]
        elif row.startswith("Port"):
            arc, arc2 = [210, 330], None
        elif row.startswith("Stbd"):
            arc, arc2 = [30, 150], None
        else:
            raise ValueError(f"unknown torpedo side {row!r}")
        reserve = 0
        if "Reload" in row:
            reserve = row.split("Reload", 1)[1].count("□")
        mounts.append({"tubes": tubes, "arc": arc, "arc2": arc2, "reserve": reserve})
    total_tubes = int(profile.get("torpedo_tubes_total") or sum(mount["tubes"] for mount in mounts))
    if total_tubes != sum(mount["tubes"] for mount in mounts):
        raise ValueError(f"torpedo tubes {total_tubes} != mount sum in {profile.get('profile_id')}")
    reserve_total = int(profile.get("torpedo_reserve_total") or 0)
    if reserve_total and reserve_total != sum(mount["reserve"] for mount in mounts):
        raise ValueError(f"torpedo reserves {reserve_total} != mount sum in {profile.get('profile_id')}")
    return {
        "name": TORPEDO_LABEL.get(model, model),
        "speed_knots": speed,
        "range_yd": range_yd,
        "warhead": warhead,
        "tubes": total_tubes,
        "contact_fuze": True,
        "mounts": mounts,
    }


# --------------------------------------------------------------------------
# ShipDef builders
# --------------------------------------------------------------------------
def base_ship(identity: str, name: str, side: str, kind: str, size: str,
              dp: float, speed: list[float], turn: dict[str, Any], armor: str,
              in_service_year: int, gun: dict[str, Any],
              secondary: dict[str, Any] | None, torpedo: dict[str, Any] | None) -> dict[str, Any]:
    armor_parts = str(armor).split("/")
    belt = armor_parts[0]
    deck = armor_parts[1] if len(armor_parts) > 1 else "0"
    return {
        "id": identity,
        "name": name,
        "side": side,
        "kind": kind,
        "size": size,
        "max_knots": speed[0],
        "dp": dp,
        "damage_speed": [],
        "turn_advance_yards": turn["turn_advance_yards"],
        "speed_loss_knots": turn["speed_loss_knots"],
        "accel_knots_per_turn": turn["accel_knots_per_turn"],
        "accel_high_knots_per_turn": turn["accel_high_knots_per_turn"],
        "brake_knots_per_turn": turn["brake_knots_per_turn"],
        "gun": gun,
        "secondary": secondary,
        "torpedo": torpedo,
        "armor_belt": float(belt or 0),
        "armor_deck": float(deck or 0),
        "in_service_year": in_service_year,
    }


def movement_from_turn(turn: dict[str, Any]) -> dict[str, Any]:
    return {
        "turn_advance_yards": turn["standard_rudder_yards"],
        "speed_loss_knots": turn["standard_speed_loss_knots"],
        "accel_knots_per_turn": turn["accel_knots_per_turn"],
        "accel_high_knots_per_turn": turn["accel_high_knots_per_turn"],
        "brake_knots_per_turn": turn["decel_knots_per_turn"],
    }


def ship_from_profile(identity: str, name: str, profile: dict[str, Any], slug: str,
                      gun_rows: dict[str, Any] | None = None) -> tuple[dict[str, Any], list[str]]:
    """Build a complete ShipDef from a transcribed CAS profile."""
    problems: list[str] = []
    gs = ROMAN.get(profile.get("gunnery_standard", ""), 4)
    size = profile["size_class_en"].split("/")[0]
    damage_points = [float(value) for value in profile["damage_points"]]
    speeds = [float(value) for value in profile["speed_knots"]]
    if len(damage_points) != len(speeds):
        raise ValueError(f"{identity}: damage/speed rows differ")
    if "turn" in profile:
        turn = movement_from_turn(profile["turn"])
    else:
        if size not in MOVEMENT:
            raise ValueError(f"{identity}: no movement row for size {size}")
        turn = dict(MOVEMENT[size])
        problems.append(
            f"原页未印转向/加速值；按 CAS 5e p.23（印刷 3-2）Warship {size} 行默认值 400/2/6/3/9"
            if size == "A" else
            f"原页未印转向/加速值；按 CAS 5e p.23（印刷 3-2）Warship {size} 行默认值")
    if "main_gun_shells_verbatim" in profile:
        mounts = mounts_from_profile(profile["gun_mounts"])
        caliber = caliber_from_slug(slug) if slug else caliber_mm(profile.get("main_gun_verbatim", ""))
        label = GUN_LABEL.get(slug, slug)
        gun = gun_from_rows(profile["main_gun_shells_verbatim"], label, caliber, gs, mounts)
    else:
        # ERMA hull: the exact Annex C-3 row closes the missing gun table.
        if gun_rows is None:
            raise ValueError(f"{identity}: no gun rows")
        label = gun_rows["requested_label"]
        armor_piercing = True
        mounts, _ = mounts_from_verbatim(profile["gun_mounts_verbatim"])
        shells = gun_rows["shells"]["APC"]
        ranges = [band["range_yd"][1] for band in gun_rows["range_bands"]]
        gun = {
            "name": f"{label} APC",
            "caliber_mm": int(re.search(r"(\d+)in", label).group(1)) * 254 // 10,
            "shell": "APC",
            "range_yd": ranges,
            "damage": shells["damage_dp"],
            "pen_belt": shells["belt_pen"],
            "pen_deck": shells["deck_pen"],
            "armor_piercing": armor_piercing,
            "barrels": sum(mount["barrels"] for mount in mounts),
            "gs": gs,
            "mounts": mounts,
        }
    secondary = secondary_from_profile(profile, gs)
    if secondary is None:
        secondary = erma_secondary(profile, gs)
    torpedo = torpedo_from_profile(profile) if "torpedo_model" in profile else None
    ship = base_ship(identity, name, profile["side"], profile["kind"], size,
                     damage_points[-1], speeds, turn, profile["armor_rating"],
                     int(profile["in_service_year"]), gun, secondary, torpedo)
    ship["damage_speed"] = [{"damage": damage, "knots": knots}
                            for damage, knots in zip(damage_points, speeds)]
    if "main_gun" in profile and profile.get("main_gun"):
        ship["source_profile"] = profile.get("profile_id", slug)
    if "class" in profile:
        ship["source_class_label"] = profile["class"]
    return ship, problems


# --------------------------------------------------------------------------
# Validation
# --------------------------------------------------------------------------
REQUIRED = ("id", "name", "side", "kind", "size", "max_knots", "dp", "damage_speed",
            "turn_advance_yards", "speed_loss_knots", "accel_knots_per_turn", "gun",
            "armor_belt", "armor_deck", "in_service_year", "accel_high_knots_per_turn",
            "brake_knots_per_turn")


def validate_ship(identity: str, ship: dict[str, Any], card_type: str) -> None:
    for key in REQUIRED:
        if key not in ship:
            raise ValueError(f"{identity}: missing {key}")
    if ship["id"] != identity:
        raise ValueError(f"{identity}: ship.id {ship['id']}")
    if not 15 <= float(ship["max_knots"]) <= 40:
        raise ValueError(f"{identity}: max_knots {ship['max_knots']}")
    if float(ship["dp"]) <= 0:
        raise ValueError(f"{identity}: dp")
    if not 5 <= len(ship["damage_speed"]) <= 6:
        raise ValueError(f"{identity}: damage_speed row count")
    gun = ship["gun"]
    for key in ("name", "range_yd", "damage", "pen_belt", "pen_deck", "barrels", "gs", "mounts"):
        if key not in gun:
            raise ValueError(f"{identity}: gun missing {key}")
    for key in ("range_yd", "damage", "pen_belt", "pen_deck"):
        if len(gun[key]) != 4:
            raise ValueError(f"{identity}: gun.{key} needs four bands")
    if gun["barrels"] != sum(mount["barrels"] for mount in gun["mounts"]):
        raise ValueError(f"{identity}: gun barrels do not match mounts")
    if gun["barrels"] <= 0:
        raise ValueError(f"{identity}: no gun barrels")
    for mount in gun["mounts"]:
        if not (0 <= mount["arc"][0] <= 360 and 0 <= mount["arc"][1] <= 360):
            raise ValueError(f"{identity}: bad arc")
    if ship.get("secondary"):
        secondary = ship["secondary"]
        if secondary["barrels"] != sum(mount["barrels"] for mount in secondary["mounts"]):
            raise ValueError(f"{identity}: secondary barrels do not match mounts")
        if len(secondary["range_yd"]) != 4:
            raise ValueError(f"{identity}: secondary bands")
    if ship.get("torpedo"):
        torpedo = ship["torpedo"]
        if torpedo["tubes"] != sum(mount["tubes"] for mount in torpedo["mounts"]):
            raise ValueError(f"{identity}: torpedo tubes do not match mounts")
    if ship["side"] not in ("allies", "axis"):
        raise ValueError(f"{identity}: side")
    if ship["kind"] not in ("DD", "CL", "CA", "CB", "BC", "BB", "AV"):
        raise ValueError(f"{identity}: kind {ship['kind']} (catalog {card_type})")


# --------------------------------------------------------------------------
# Source adapters
# --------------------------------------------------------------------------
def provenance(card: dict[str, Any]) -> dict[str, Any]:
    pages = card.get("source_pages")
    return {
        "source_pages": pages,
        "profile_id": (card.get("profile") or {}).get("profile_id") or card.get("class_profile") or card.get("source_class"),
    }


def adapt_pdf(card: dict[str, Any]) -> tuple[dict[str, Any], list[str]]:
    profile = card["profile"]
    ship, problems = ship_from_profile(card["identity"], card["name"], profile, profile.get("main_gun"))
    pages = card.get("source_pages", {})
    identity_pages = pages.get("identity") or {}
    printed = identity_pages.get("printed_pages") or identity_pages.get("pdf_pages") or []
    page = printed[0] if printed else "?"
    profile_page = ((pages.get("profile") or {}).get("printed_pages") or [page])[0]
    note = (f"Form 10 个体页 p{page}（{profile.get('configuration_label') or profile.get('configuration_date')}）；"
            f"完整 ShipDef 按该页 profile 原样重建：炮座行 {len(profile['gun_mounts'])} 行、"
            f"弹种行 {choose_shell(profile['main_gun_shells_verbatim'])[0]}、"
            f"损伤/航速行 {len(profile['damage_points'])} 行。")
    if profile_page != page:
        note += f" 统计/炮表取共享 class profile p{profile_page}；个体页只差日期标签。"
    dp_mounts = [entry for entry in (profile.get("secondary_mounts") or []) if entry.get("kind") == "DP"]
    if dp_mounts:
        note += (" secondary 只收舷炮/主副炮弹道；12.7cm/40 DP 炮座未并入同一 GunDef，"
                 "与 Nagato 卡的二级对象口径一致，登记为未建模差额。")
    if profile.get("profile_variant_note"):
        note += " " + profile["profile_variant_note"]
    return ship, problems + [note]


def copy_ship(card: dict[str, Any], class_profile: str, kind: str) -> tuple[dict[str, Any], list[str]]:
    ship = json.loads(json.dumps(card["ship"]))
    ship["id"] = card["identity"]
    ship["name"] = card["name"]
    if "source_class_label" not in ship:
        ship["source_class_label"] = (card.get("profile") or {}).get("class")
    note = card.get("source_note") or ""
    if class_profile and ship.get("source_profile") not in (None, class_profile) and ship.get("source_class") not in (None, class_profile):
        # Keep the registered ship object untouched; class identity lives in the
        # merged record's `class_profile`.
        pass
    return ship, [note] if note else []


def adapt_erma_usn(card: dict[str, Any], gun_rows: dict[str, Any]) -> tuple[dict[str, Any], list[str]]:
    if card.get("ship"):
        ship, problems = copy_ship(card, card["class_profile"], card["type"])
        return ship, problems
    profile = card["profile"]
    slug = {"us_iowa_bb_1943": "us_16in50_mk7", "us_alaska_cb_1944": "us_12in50_mk8",
            "us_des_moines_ca_1948": "us_8in55_mk16"}[card["class_profile"]]
    row = gun_rows["guns"][slug]
    ship, problems = ship_from_profile(card["identity"], card["name"], profile, slug, gun_rows=row)
    note = (f"ERMA 记录 + American Fleets {card['profile']['source'].get('printed_page')}；"
            f"主炮用 data/rules/gun-rows-erma.json#{slug} 的 C-3 exact 行闭合"
            f"（{row['requested_label']}，短/中/长/极远 {row['range_bands'][0]['range_yd'][1]}/"
            f"{row['range_bands'][1]['range_yd'][1]}/{row['range_bands'][2]['range_yd'][1]}/"
            f"{row['range_bands'][3]['range_yd'][1]} 码）；"
            f"副炮 5in/38 用已登记 C-2 行。")
    if profile.get("scenario_fit_note"):
        note += " " + profile["scenario_fit_note"]
    return ship, problems + [note]


# --------------------------------------------------------------------------
# Main merge
# --------------------------------------------------------------------------
def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write-points", action="store_true", help="update the frozen point manifest")
    parser.add_argument("--write-cards", action="store_true", help="update data/ships/cards.json")
    options = parser.parse_args()

    files = {
        PDF: load(f"data/ships/{PDF}")["cards"],
        APD: load(f"data/ships/{APD}")["cards"],
        PROXY: load(f"data/ships/{PROXY}")["cards"],
        ALLIES: load(f"data/ships/{ALLIES}")["cards"],
        AXIS: load(f"data/ships/{AXIS}")["cards"],
        ERMA_USN: load(f"data/ships/{ERMA_USN}")["ships"],
        ERMA_IJN: load(f"data/ships/{ERMA_IJN}")["cards"],
        HIST: load(f"data/ships/{HIST}")["cards"],
    }
    gun_rows = load(f"data/rules/{GUN_ROWS}")

    # Historical-axis cards supersede the same seven axis records; every other
    # identity is taken from its own package.
    merged: dict[str, dict[str, Any]] = {}

    def add(source: str, card: dict[str, Any], supersede: bool = False) -> None:
        identity = card["identity"]
        if identity in EXCLUDED:
            return
        if identity in merged and not supersede:
            return
        merged[identity] = {"source": source, "card": card}

    for card in files[HIST]:
        add(HIST, card, supersede=True)
    for source in (PDF, APD, PROXY, ALLIES, AXIS, ERMA_USN, ERMA_IJN):
        for card in files[source]:
            add(source, card)

    expected = 12 + 8 + 13 + 21 + 10 + 12 + 8 + 7
    if len(merged) != expected:
        raise SystemExit(f"expected {expected} merged identities, got {len(merged)}")

    cards_out = []
    by_source: dict[str, int] = {}
    for identity in sorted(merged):
        source = merged[identity]["source"]
        card = merged[identity]["card"]
        class_profile = card.get("class_profile") or card.get("source_class")
        if not class_profile and card.get("ship"):
            class_profile = card["ship"].get("source_class") or card["ship"].get("source_profile")
        if not class_profile:
            raise SystemExit(f"{identity}: no class profile")
        if source == PDF:
            ship, notes = adapt_pdf(card)
        elif source == ERMA_USN:
            ship, notes = adapt_erma_usn(card, gun_rows)
        else:
            ship, notes = copy_ship(card, class_profile, card["type"])
        validate_ship(identity, ship, card["type"])
        kind, cards_kind = SOURCE_META[source]
        by_source[source] = by_source.get(source, 0) + 1
        source_note = " ".join(note for note in notes if note)
        if card.get("conflicts"):
            source_note += " 冲突：" + "；".join(card["conflicts"])
        conflicts = list(KNOWN_CONFLICTS.get(identity, []))
        if card.get("conflicts"):
            conflicts.extend(card["conflicts"])
        page_summary = provenance(card)
        record = {
            "identity": identity,
            "name": card["name"],
            "name_en": card.get("name_en"),
            "side": card["side"],
            "type": card["type"],
            "class_profile": class_profile,
            "class_label_zh": card.get("class_label_zh") or (card.get("profile") or {}).get("class_label_zh") or card.get("class_zh") or card.get("class_label"),
            "source_file": f"data/ships/{source}",
            "source_kind": kind,
            "identity_kind": cards_kind,
            "source_pages": page_summary["source_pages"],
            "profile_id": page_summary["profile_id"],
            "stat_verified": True,
            "stat_source": source_note,
            "conflicts": conflicts,
            "ship": ship,
        }
        if card.get("blockers"):
            if source == ERMA_USN and not card.get("ship"):
                # The gun-row blockers are closed by data/rules/gun-rows-erma.json;
                # any remaining scenario caveat (e.g. the 1948 Des Moines fit)
                # stays a limitation, not a playability blocker.
                resolved = [blocker for blocker in card["blockers"]
                            if "Annex C" in blocker or "弹道行" in blocker]
                other = [blocker for blocker in card["blockers"] if blocker not in resolved]
                record["resolved_by"] = {
                    "gun_rows": f"data/rules/{GUN_ROWS}",
                    "movement": "CAS 5e p.23 (printed 3-2) Warship row",
                }
                record["source_blockers_resolved"] = resolved
                if other:
                    record["limitations"] = list(card.get("limitations") or []) + other
            else:
                record["blockers"] = card["blockers"]
        if card.get("limitations"):
            record["limitations"] = card["limitations"]
        if identity in files.get(AXIS, []) and source == HIST:
            record["also_recorded"] = [f"data/ships/{AXIS}"]
        cards_out.append(record)

    merged_doc = {
        "schema_version": 1,
        "content_version": CONTENT_VERSION,
        "as_of": AS_OF,
        "generated_by": "scripts/build-merged-cards.py",
        "scope": "111 → 202：12 张 pdf Form 10 逐舰卡、8 艘 APD、13 张同型卡、21 张 CAS 同盟源表卡、"
                 "10 张 CAS 轴心完整卡 + 7 张历史轴心卡、12 张 ERMA USN（8 张用 C-3 炮表闭合）、8 张 ERMA IJN。",
        "policy": "有完整 ship 的原样复制；pdf 卡按 profile 原样重建 ShipDef；ERMA 8 艘只补 C-3 exact 炮表行与 "
                  "CAS 5e p.23 未印运动默认行。不写 points，不改源卡、server/catalog、portraits、audio、AI。",
        "source_files": {f"data/ships/{name}": {"sha256": sha256(f"data/ships/{name}"), "cards": len(cards)}
                         for name, cards in files.items()},
        "gun_rows_source": {"path": f"data/rules/{GUN_ROWS}", "sha256": sha256(f"data/rules/{GUN_ROWS}")},
        "exclusions": [
            {"identity": identity, "reason": reason, "detail": detail}
            for identity, (reason, detail) in EXCLUDED.items()
        ],
        "cards": cards_out,
        "counts": {"cards": len(cards_out), "by_source": by_source,
                   "allies": sum(1 for card in cards_out if card["side"] == "allies"),
                   "axis": sum(1 for card in cards_out if card["side"] == "axis")},
    }
    write_json("data/ships/merged-cards.json", merged_doc)

    # Generated Rust profile entries. The include is a single `&[Profile, ...]`
    # expression; `profiles()` appends it to the hand-maintained legacy slice.
    lines = [
        "// Generated by scripts/build-merged-cards.py from data/ships/merged-cards.json.",
        "// Do not hand-edit: rerun the builder and re-check data/ships/merge-report.json.",
        "&[",
    ]
    for record in cards_out:
        source = (f"{PROFILE_SOURCE}merged exact · {record['source_file']} · "
                  f"{record['class_profile']}")
        lines += [
            f"    // {record['identity']} — {record['source_file']}",
            "    Profile {",
            f"        id: {rust_str(record['identity'])},",
            f"        source_class: {rust_str(record['class_profile'])},",
            f"        name: {rust_str(record['name'])},",
            f"        source: {rust_str(source)},",
            "    },",
        ]
    lines.append("]")
    (ROOT / "src/ranked_profiles_merged.inc").write_text("\n".join(lines) + "\n", encoding="utf-8")

    # ---------------- point manifest ----------------
    if options.write_points:
        manifest_path = "data/rules/cas-competitive-points-v1.json"
        manifest = load(manifest_path)
        for record in cards_out:
            identity = record["identity"]
            ship = record["ship"]
            manifest["ships"][identity] = {
                "points": point_value(ship),
                "profile_id": f"{CONTENT_VERSION}#{identity}",
                "source": (f"{PROFILE_SOURCE}merged exact · {record['source_file']} · "
                           f"{record['class_profile']}"),
            }
        # Keep existing insertion order, append new hulls alphabetically.
        manifest["ships"] = dict(sorted(manifest["ships"].items()))
        write_json(manifest_path, manifest)

    # ---------------- identity cards ----------------
    if options.write_cards:
        update_cards(merged_doc, cards_out)

    report = {
        "schema_version": 1,
        "as_of": AS_OF,
        "generated_by": "scripts/build-merged-cards.py",
        "target": {"ranked_profiles": 202, "collection_only": 8},
        "merged_cards": len(cards_out),
        "by_source": by_source,
        "excluded": merged_doc["exclusions"],
        "collection_only": [
            "IBS-U-IJN-AMAGI", "IBS-U-IJN-AKAGI", "IBS-U-IJN-OWARI",
            "IBS-U-IJN-ERMA-IBUKI", "IBS-U-IJN-ERMA-KURAMA", "IBS-U-IJN-ERMA-GOKASE",
            "IBS-U-USN-MIDWAY", "IBS-U-IJN-XIFENG",
        ],
        "checks": {
            "cards_unique": len({card["identity"] for card in cards_out}) == len(cards_out),
            "all_side": all(card["side"] in ("allies", "axis") for card in cards_out),
            "all_stat_verified": all(card["stat_verified"] for card in cards_out),
            "all_have_complete_ship": all(card["ship"] for card in cards_out),
        },
    }
    write_json("data/ships/merge-report.json", report)
    print(json.dumps({"merged": len(cards_out), "by_source": by_source,
                      "rust_profiles": len(cards_out), "excluded": len(EXCLUDED)}, ensure_ascii=False, indent=1))
    return 0


# --------------------------------------------------------------------------
# Point formula (mirrors src/ranked_fleets.rs point_value)
# --------------------------------------------------------------------------
def round_half_up(value: float) -> int:
    return int(value + 0.5) if value >= 0 else -int(-value + 0.5)


def point_value(ship: dict[str, Any]) -> int:
    gun = ship["gun"]
    average = sum(gun["damage"]) / len(gun["damage"])
    torpedo = 0.0
    if ship.get("torpedo"):
        torpedo = 0.12 * ship["torpedo"]["tubes"] * ship["torpedo"]["warhead"]
    raw = (1.5 * ship["dp"] + 5.0 * ship["max_knots"]
           + 2.0 * gun["barrels"] * average + torpedo
           + 5.0 * (ship["armor_belt"] + ship["armor_deck"])
           + 0.8 * ship.get("torpedo_protection_dp", 0.0))
    scale = {"DD": 0.75, "CL": 0.85, "CA": 1.0, "BB": 1.2}.get(ship["kind"], 1.0)
    return round_half_up(raw * scale / 25.0) * 25


# --------------------------------------------------------------------------
# cards.json metadata
# --------------------------------------------------------------------------
def update_cards(merged_doc: dict[str, Any], records: list[dict[str, Any]]) -> None:
    cards_doc = load("data/ships/cards.json")
    period = load("data/ships/period-cards.json")
    period_map = {card["identity"]: card for card in period}
    merged_map = {record["identity"]: record for record in records}
    ranked = ranked_profiles()
    catalog = load("server/catalog.json")
    catalog_map = {ship["id"]: ship for ship in catalog["ships"]}

    playable_ids = set(ranked)
    for card in cards_doc["cards"]:
        identity = card["identity"]
        card["playable"] = identity in playable_ids
        if not card["playable"]:
            card["playable_sources"] = []
            card["cas_source_class"] = None
            continue
        card["playable_sources"] = ["ranked-profile"]
        if identity in period_map:
            card["cas_source_class"] = period_map[identity]["period_profile"]
            card["source_kind"] = "period_named"
            page = period_map[identity].get("form10_page")
            card["source_note"] = ("playable · period_named · data/ships/period-cards.json"
                                   + (f" · Form 10 p{page}" if page else ""))
            card.pop("reason_category", None)
        elif identity in merged_map:
            record = merged_map[identity]
            card["cas_source_class"] = record["class_profile"]
            card["source_kind"] = record["identity_kind"]
            if record.get("class_label_zh"):
                card["class"] = record["class_label_zh"]
                card["class_source"] = "merged-source"
            card["source_note"] = (f"playable · {record['identity_kind']} · {record['source_file']} · "
                                   f"{record['class_profile']}（见 data/ships/merged-cards.json）")
            card.pop("reason_category", None)
        else:
            # 88 legacy ranked identities keep their existing class/source metadata.
            card.setdefault("source_kind", "ranked_profile")
        card["cas_source_class"] = card.get("cas_source_class") or ranked[identity]

    cards_doc["generated_by"] = "scripts/build-merged-cards.py (111 → 202 merge)"
    cards_doc["generated_at"] = AS_OF
    cards_doc["scope"] = ("210 个 IBS-U-* 稳定身份的身份元数据（含立绘、名称、阵营、舰种、展示稀有度、剧本归属、"
                          "可出战与已加载卡来源）；可出战 202、收藏 8；不写舰表数值和点价。")
    cards_doc["sources"]["ranked"] = "src/ranked_fleets.rs PROFILES（202：88 既有 + 23 period + 91 merged）"
    cards_doc["sources"]["merged"] = "data/ships/merged-cards.json（91 张逐舰完整 ShipDef）"
    cards_doc["sources"]["period"] = "data/ships/period-cards.json（23 张 period 逐舰卡）"
    cards_doc["sources"]["gun_rows"] = "data/rules/gun-rows-erma.json（8 艘 ERMA USN 的 C-3 exact 炮表行）"

    playable = [card for card in cards_doc["cards"] if card["playable"]]
    collection = [card for card in cards_doc["cards"] if not card["playable"]]
    cards_doc["summary"].update({
        "identities": len(cards_doc["cards"]),
        "playable": len(playable),
        "collection_only": len(collection),
        "playable_by_source": {
            "ranked-profile": len(ranked),
            "merged-card": len(records),
            "period-card": len(period),
        },
        "by_side": {
            sidebar: {
                "playable": sum(1 for card in playable if card["side"] == sidebar),
                "collection_only": sum(1 for card in collection if card["side"] == sidebar),
            } for sidebar in ("allies", "axis")
        },
        "by_type": {kind: sum(1 for card in cards_doc["cards"] if card["type"] == kind)
                    for kind in sorted({card["type"] for card in cards_doc["cards"]})},
        "display_rarity": {rarity: sum(1 for card in cards_doc["cards"] if card["display_rarity"] == rarity)
                           for rarity in ("common", "elite", "rare", "ur")},
    })

    playable_cards = {c["identity"] for c in load("data/ships/playable-cards.json")["cards"]}
    card_source = {card["identity"]: card.get("cas_source_class") for card in cards_doc["cards"]}
    cards_doc["checks"] = {
        "identities_match_catalog": {card["identity"] for card in cards_doc["cards"]} == set(catalog_map),
        "unique_identities": len({card["identity"] for card in cards_doc["cards"]}) == len(cards_doc["cards"]),
        "all_portraits_exist": all((ROOT / card["portrait_path"]).is_file() for card in cards_doc["cards"]),
        "side_type_match_catalog": all(card["side"] == catalog_map[card["identity"]]["side"]
                                       and card["type"] == catalog_map[card["identity"]]["type"]
                                       for card in cards_doc["cards"]),
        "playable_cards_subset": playable_ids <= (playable_cards | set(ranked)),
        "ranked_profiles_subset": set(ranked) <= playable_ids,
        "cas_source_class_only_when_playable": all(
            (card["cas_source_class"] is None) != card["playable"] for card in cards_doc["cards"]),
        "scenario_ids_retained": True,
        "no_stats_or_points_fields": all("stats" not in card and "points" not in card
                                         for card in cards_doc["cards"]),
        "cas_source_class_matches_ranked_profiles": all(
            card_source.get(identity) == source_class for identity, source_class in ranked.items()),
    }
    cards_doc["gaps"]["identities_without_playable_card"] = len(collection)
    cards_doc["gaps"]["identity_ids"] = [card["identity"] for card in collection]
    write_json("data/ships/cards.json", cards_doc)

    # Keep the derived non-scenario identity index in step with the cards.
    audit_path = ROOT / "data/ships/non-scenario-identities.json"
    if audit_path.is_file():
        audit = json.loads(audit_path.read_text(encoding="utf-8"))
        rows = [
            {
                "identity": card["identity"],
                "name": card["name"],
                "side": card["side"],
                "type": card["type"],
                "class": card.get("class"),
                "playable": card["playable"],
                "reason": card.get("source_note"),
            }
            for card in cards_doc["cards"] if not card["scenario_ids"]
        ]
        rows.sort(key=lambda row: row["identity"])
        audit["scope"] = (f"{len(cards_doc['cards'])} 个 catalog identity 中不在当前 11 剧本 "
                          f"scenario_ids 内的 {len(rows)} 个")
        audit["total"] = len(rows)
        audit["ranked_only"] = sum(1 for row in rows if row["playable"])
        audit["collection"] = sum(1 for row in rows if not row["playable"])
        audit["rows"] = rows
        write_json("data/ships/non-scenario-identities.json", audit)


def ranked_profiles() -> dict[str, str]:
    """The 202 identity → class-profile map, read from the registry after the
    generated include has been wired in. Legacy entries come from the const."""
    source = (ROOT / "src/ranked_fleets.rs").read_text(encoding="utf-8")
    entries = re.findall(r'Profile \{\s*id: "([^"]+)",\s*source_class: "([^"]+)"', source)
    profiles = {identity: source_class for identity, source_class in entries}
    include = ROOT / "src/ranked_profiles_merged.inc"
    if include.is_file():
        text = include.read_text(encoding="utf-8")
        for identity, source_class in re.findall(r'id: "([^"]+)",\s*source_class: "([^"]+)"', text):
            profiles[identity] = source_class
    return profiles


if __name__ == "__main__":
    sys.exit(main())
