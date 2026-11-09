"""Build the authoritative per-identity portrait ledger for CAS.

One catalogue identity (``server/catalog.json`` ships[].id, which is also the
pinned mobile ``ibs_ship_id`` and the 立绘索引.csv 编号) gets exactly one
portrait.  No class representative is ever substituted for a named identity.

Sources (read-only reference project, outside this workspace):

* ``mobile/release/立绘全集/立绘索引.csv``  -- 210 现版舰船 rows with 编号,
  fleet-v2 path and SHA-256.  A byte copy is kept at
  ``data/portraits/source/portrait-index.csv`` and its hash registered.
* ``mobile/content/fleet-portrait-manifest.json`` -- corroborates the same
  210 paths/hashes (status ``ready``).
* ``mobile/public/characters/ships/fleet-v2/*.png`` -- 1024x1536 RGBA source.

Outputs:

* ``client/src/assets/portraits/all/ledger.json`` -- 210 entries.  The 167
  identities already projected into the free-economy pool reuse the verified
  ``client/src/online-recruit/assets/*.webp`` bytes (700x1050); the remaining
  43 get a 512x768 WebP thumbnail in ``client/src/assets/portraits/all/`` so
  the repository does not double every full-body asset.
* ``data/portraits/sources.json`` -- source registry (paths + SHA-256).
* ``data/portraits/report.json`` -- coverage, duplicate and class-card checks.
* ``data/portraits/scenario-mapping.json`` -- the 11 kept scenarios' ship
  names -> identity -> portrait, including runtime rows.
* ``data/portraits/rarity.json`` -- display-only rarity tier, its rule and
  distribution.  Gacha rarity/rates/pools/prices are never written here.

Usage:
    python scripts/import-portraits-identity.py
    python scripts/import-portraits-identity.py --check
    python scripts/import-portraits-identity.py --source <ironbottom-checkout>
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = Path(r"F:/Codex/worktrees/android-mobile/铁底湾")

CATALOG = ROOT / "server/catalog.json"
CROSSWALK = ROOT / "data/campaign/roster-crosswalk.json"
SCENARIO_INDEX = ROOT / "data/campaign/crosswalk.json"
LABELS = ROOT / "data/campaign/locale/zh-labels.json"
PORT_TS = ROOT / "client/src/port.ts"
RANKED_FLEETS = ROOT / "src/ranked_fleets.rs"
CLASS_LEDGER = ROOT / "client/src/assets/portraits/ledger.json"
RECRUIT_LEDGER = ROOT / "client/src/online-recruit/ledger.json"
RECRUIT_ASSETS = ROOT / "client/src/online-recruit/assets"
ALL_DIR = ROOT / "client/src/assets/portraits/all"
ALL_LEDGER = ALL_DIR / "ledger.json"
DATA_DIR = ROOT / "data/portraits"
SOURCE_COPY = DATA_DIR / "source/portrait-index.csv"
SOURCES_OUT = DATA_DIR / "sources.json"
REPORT_OUT = DATA_DIR / "report.json"
MAPPING_OUT = DATA_DIR / "scenario-mapping.json"
RARITY_OUT = DATA_DIR / "rarity.json"

THUMB_SIZE = (512, 768)
THUMB_QUALITY = 82
THUMB_METHOD = 6

# The eleven CAS surface scenarios that currently have a source record in
# data/campaign/*.json.  Removed scenarios stay in the crosswalk for future
# restoration but are not part of this report.
SCENARIO_FILES = [
    ("cape-esperance", "IBS-S-01"),
    ("kula-gulf", "IBS-S-02"),
    ("tassafaronga", "IBS-S-04"),
    ("cape-st-george", "IBS-S-05"),
    ("guadalcanal-ii", "IBS-S-06"),
    ("kolombangara", "IBS-S-08"),
    ("guadalcanal-i", "IBS-S-09"),
    ("savo-island", "IBS-S-10"),
    ("empress-augusta-bay", "IBS-S-11"),
    ("vella-lavella", "IBS-S-13"),
    ("horaniu", "IBS-S-14"),
]

# JSON-backed runtimes that the engine includes for those scenarios.  Empress
# and Esperance compile their ship lists into src/empress.rs and
# src/campaign/esperance.rs; they are reported from the scenario source rows.
RUNTIME_FILES = [
    ("data/campaign/period/cape-runtime.json", "cape-st-george", "ships"),
    ("data/campaign/period/kula-runtime.json", "kula-gulf", "instances"),
    ("data/campaign/period/savo-runtime.json", "savo-island", "ships"),
    ("data/campaign/period/tassafaronga-runtime.json", "tassafaronga", "ships"),
]

DISPLAY_RANKS = ["common", "elite", "rare", "ur"]
DISPLAY_RANK_INDEX = {name: index for index, name in enumerate(DISPLAY_RANKS)}
CAPITAL_TYPES = {"BB", "BC", "CV"}
LATE_WAR_FROM = "1943-01-01"


def sha256_bytes(blob: bytes) -> str:
    return hashlib.sha256(blob).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def payload(value) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2) + "\n"


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def fail(message: str):
    raise SystemExit(message)


def write_or_check(path: Path, text: str, check: bool):
    if check:
        if not path.exists():
            fail(f"缺少输出：{rel(path)}")
        if path.read_text(encoding="utf-8") != text:
            fail(f"输出过期：{rel(path)}（重新运行不带 --check）")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def read_index_rows(index_path: Path):
    with index_path.open(encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    return rows


def current_ship_rows(rows):
    return [row for row in rows if row["分类"] == "现版舰船"]


def verify_sources(source: Path, catalog, crosswalk, index_path: Path, check: bool):
    manifest_path = source / "mobile/content/fleet-portrait-manifest.json"
    if not manifest_path.exists():
        fail(f"找不到手游立绘清单：{manifest_path}")
    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes)
    manifest_by_id = {row["ship_id"]: row for row in manifest["ships"]}

    rows = current_ship_rows(read_index_rows(index_path))
    if len(rows) != 210:
        fail(f"立绘索引现版舰船应为 210 行，实际 {len(rows)} 行")
    by_id = {row["编号"]: row for row in rows}
    if len(by_id) != 210:
        fail("立绘索引现版舰船编号有重复")

    catalog_ids = [ship["id"] for ship in catalog["ships"]]
    if len(catalog_ids) != 210 or len(set(catalog_ids)) != 210:
        fail("server/catalog.json 应恰有 210 个唯一 identity")
    if set(catalog_ids) != set(by_id):
        missing = sorted(set(catalog_ids) - set(by_id))
        extra = sorted(set(by_id) - set(catalog_ids))
        fail(f"catalog 与立绘索引 identity 不一致：缺图 {missing}，多图 {extra}")
    if set(manifest_by_id) != set(catalog_ids):
        fail("手游立绘清单与 catalog identity 不一致")

    cross_by_ship = {row["ibs_ship_id"]: row for row in crosswalk["ships"]}
    if set(cross_by_ship) != set(catalog_ids):
        fail("roster-crosswalk ibs_ship_id 与 catalog identity 不一致")

    for identity in catalog_ids:
        row = by_id[identity]
        item = manifest_by_id[identity]
        source_rel = row["项目内来源"]
        if item["path"] != "/characters/ships/" + source_rel.split("/characters/ships/")[-1]:
            fail(f"{identity} 清单路径与索引不一致")
        if item.get("sha256") != row["SHA256"]:
            fail(f"{identity} 清单 SHA 与索引不一致")
        if item.get("status") != "ready":
            fail(f"{identity} 清单状态不是 ready")
        if row["角色或舰名"] != next(ship["name"] for ship in catalog["ships"] if ship["id"] == identity):
            fail(f"{identity} 索引舰名与 catalog 不一致")
    return rows, by_id, manifest_bytes, manifest, cross_by_ship


def reusable_recruit_assets():
    ledger = read_json(RECRUIT_LEDGER)
    available = {}
    for entry in ledger["assets"]:
        target = RECRUIT_ASSETS / entry["path"]
        if not target.exists():
            fail(f"征募立绘缺失：{rel(target)}")
        if sha256_file(target) != entry["sha256"]:
            fail(f"征募立绘哈希不符：{rel(target)}")
        available[entry["character_id"]] = entry
    return available


def encode_thumbnail(source_path: Path):
    from PIL import Image

    with Image.open(source_path) as image:
        image = image.convert("RGBA")
        image.thumbnail(THUMB_SIZE, Image.LANCZOS)
        if image.size != THUMB_SIZE:
            fail(f"{source_path.name} 缩放后为 {image.size}，预期 {THUMB_SIZE}")
        buffer = io.BytesIO()
        image.save(buffer, "WEBP", quality=THUMB_QUALITY, method=THUMB_METHOD)
    return buffer.getvalue()


def build_identity_ledger(source: Path, catalog, by_id, cross_by_ship, recruit, check: bool):
    ALL_DIR.mkdir(parents=True, exist_ok=True)
    previous = {}
    if ALL_LEDGER.exists():
        previous = {entry["identity"]: entry for entry in read_json(ALL_LEDGER)["assets"]}

    assets = []
    reused = []
    generated = []
    reused_from_existing = 0
    for ship in catalog["ships"]:
        identity = ship["id"]
        row = by_id[identity]
        source_rel = row["项目内来源"]
        source_path = source / source_rel
        if not source_path.exists():
            fail(f"源图缺失：{source_path}")
        if sha256_file(source_path) != row["SHA256"]:
            fail(f"源图哈希不符：{source_rel}")

        recruit_entry = recruit.get(identity)
        if recruit_entry and recruit_entry["source_sha256"] == row["SHA256"]:
            entry = {
                "identity": identity,
                "character_id": identity,
                "mobile_character_id": cross_by_ship[identity]["ibs_character_id"],
                "character_name": ship["name"],
                "side": ship["side"],
                "ship_type": ship["type"],
                "source_path": source_rel,
                "source_sha256": row["SHA256"],
                "root": "online-recruit",
                "path": recruit_entry["path"],
                "sha256": recruit_entry["sha256"],
                "bytes": (RECRUIT_ASSETS / recruit_entry["path"]).stat().st_size,
                "width": recruit_entry["size"][0],
                "height": recruit_entry["size"][1],
            }
            reused.append(identity)
            assets.append(entry)
            continue

        filename = identity.lower() + ".webp"
        target = ALL_DIR / filename
        prior = previous.get(identity)
        if target.exists() and prior and prior.get("source_sha256") == row["SHA256"]:
            blob = target.read_bytes()
            if sha256_bytes(blob) == prior.get("sha256"):
                entry = {
                    "identity": identity,
                    "character_id": identity,
                    "mobile_character_id": cross_by_ship[identity]["ibs_character_id"],
                    "character_name": ship["name"],
                    "side": ship["side"],
                    "ship_type": ship["type"],
                    "source_path": source_rel,
                    "source_sha256": row["SHA256"],
                    "root": "all",
                    "path": filename,
                    "sha256": prior["sha256"],
                    "bytes": len(blob),
                    "width": prior["width"],
                    "height": prior["height"],
                }
                assets.append(entry)
                reused_from_existing += 1
                generated.append(identity)
                continue
        if check:
            fail(f"缺少已生成的 512x768 缩略图：{rel(target)}")
        blob = encode_thumbnail(source_path)
        target.write_bytes(blob)
        assets.append({
            "identity": identity,
            "character_id": identity,
            "mobile_character_id": cross_by_ship[identity]["ibs_character_id"],
            "character_name": ship["name"],
            "side": ship["side"],
            "ship_type": ship["type"],
            "source_path": source_rel,
            "source_sha256": row["SHA256"],
            "root": "all",
            "path": filename,
            "sha256": sha256_bytes(blob),
            "bytes": len(blob),
            "width": THUMB_SIZE[0],
            "height": THUMB_SIZE[1],
        })
        generated.append(identity)

    # Cross-check the two output roots, then write one authoritative ledger.
    for entry in assets:
        root = RECRUIT_ASSETS if entry["root"] == "online-recruit" else ALL_DIR
        target = root / entry["path"]
        if not target.exists():
            fail(f"ledger 指向的立绘不存在：{rel(target)}")
        if sha256_file(target) != entry["sha256"]:
            fail(f"ledger 立绘哈希不符：{rel(target)}")

    ledger = {
        "schema_version": 1,
        "kind": "identity-portraits",
        "note": "一个 IBS-U-* identity 一张立绘；按 identity 查，同级舰不得互相顶替。",
        "generated_by": "scripts/import-portraits-identity.py",
        "source_project": "铁底湾",
        "source_mobile_version": "0.6.9",
        "source_checkout": source.as_posix(),
        "source_index": {
            "workspace_copy": rel(SOURCE_COPY),
            "original_path": "mobile/release/立绘全集/立绘索引.csv",
            "sha256": sha256_file(SOURCE_COPY) if SOURCE_COPY.exists() else sha256_file(source / "mobile/release/立绘全集/立绘索引.csv"),
            "row_count": 210,
        },
        "thumbnail": {
            "reused": {"root": "online-recruit", "width": 700, "height": 1050,
                       "note": "已提交的征募全身图，按源图 SHA-256 逐张校验后复用"},
            "generated": {"root": "all", "width": THUMB_SIZE[0], "height": THUMB_SIZE[1],
                          "quality": THUMB_QUALITY, "format": "webp"},
        },
        "counts": {
            "identities": len(assets),
            "reused_online_recruit": len(reused),
            "generated_all": len(assets) - len(reused),
        },
        "assets": assets,
    }
    stats = {"reused": reused, "generated": generated, "reused_existing_files": reused_from_existing}
    return ledger, stats


def collect_scenario_names(node, path: str, out):
    """Collect ship names from forces/groups/ships/setup without inventing any."""
    if isinstance(node, dict):
        label = node.get("name") if isinstance(node.get("name"), str) else node.get("ship")
        if isinstance(label, str) and any(key in node for key in ("class", "kind", "flagship", "class_as_printed")):
            out.append((label.strip(), path))
        for key, value in node.items():
            child = f"{path}.{key}" if path else key
            if key in ("ships", "names") and isinstance(value, list):
                for item in value:
                    if isinstance(item, str):
                        out.append((item.strip(), f"{child}"))
                    elif isinstance(item, dict):
                        collect_scenario_names(item, child, out)
            elif key == "column":
                if isinstance(value, list):
                    for item in value:
                        if isinstance(item, str):
                            out.append((item.strip(), child))
                        elif isinstance(item, dict):
                            collect_scenario_names(item, child, out)
                elif isinstance(value, str):
                    for token in value.split(","):
                        token = token.strip()
                        # Kolombangara prints "..., then transport destroyers";
                        # that trailing phrase is prose, not a hull name.  The
                        # actual transport destroyers are listed in forces.
                        if token and not token.lower().startswith(("then ", "and ")):
                            out.append((token, child))
            elif isinstance(value, (dict, list)):
                collect_scenario_names(value, child, out)
    elif isinstance(node, list):
        for index, item in enumerate(node):
            collect_scenario_names(item, f"{path}[{index}]", out)


def side_from_path(path: str):
    if ".allies" in path or path.startswith("forces.allies") or ".allies[" in path:
        return "allies"
    if ".axis" in path or path.startswith("forces.axis") or ".axis[" in path:
        return "axis"
    return None


def build_name_resolver(catalog, labels):
    by_name = defaultdict(list)
    for ship in catalog["ships"]:
        by_name[ship["name"]].append(ship["id"])
    legacy = labels["legacy_name_ids"]
    zh = labels["ships"]

    def resolve(name: str, side: str | None):
        for candidate in ([side] if side else ["allies", "axis"]):
            identity = legacy.get(candidate, {}).get(name)
            if identity:
                return identity, "legacy_name_ids", "exact"
        for candidate in ([side] if side else ["allies", "axis"]):
            chinese = zh.get(candidate, {}).get(name)
            if chinese and len(by_name.get(chinese, [])) == 1:
                return by_name[chinese][0], "zh_label_exact_catalog_name", "exact"
        return None, "unmapped", None

    return resolve, by_name, legacy, zh


def name_side(name: str, side: str | None, legacy, zh):
    if side:
        return side
    for candidate in ("allies", "axis"):
        if name in legacy.get(candidate, {}):
            return candidate
    for candidate in ("allies", "axis"):
        if name in zh.get(candidate, {}):
            return candidate
    return None


def build_mapping(catalog, ledger, labels, scenario_index):
    resolve, by_name, legacy, zh = build_name_resolver(catalog, labels)
    identity_asset = {entry["identity"]: entry for entry in ledger["assets"]}
    catalog_ids = {ship["id"] for ship in catalog["ships"]}
    scenario_meta = {row["ibs_id"]: row for row in scenario_index["scenarios"]}

    scenarios = []
    missing_rows = []
    runtime_rows = []
    unresolved_runtime = []
    all_rows = []

    for filename, ibs_id in SCENARIO_FILES:
        path = ROOT / "data/campaign" / (filename + ".json")
        data = read_json(path)
        meta = scenario_meta.get(ibs_id, {})
        collected = []
        collect_scenario_names({key: data[key] for key in ("forces", "groups", "ships", "setup") if key in data}, "", collected)
        # de-duplicate identical (name, location) pairs while keeping order
        seen = set()
        rows = []
        for name, location in collected:
            if not name or (name, location) in seen:
                continue
            seen.add((name, location))
            side = side_from_path(location)
            identity, resolution, confidence = resolve(name, side)
            resolved_side = name_side(name, side, legacy, zh)
            exists = bool(identity and identity in identity_asset)
            portrait = identity_asset[identity]["path"] if exists else None
            row = {
                "name": name,
                "side": resolved_side,
                "identity": identity,
                "portrait": portrait,
                "exists": exists,
                "resolution": resolution,
                "confidence": confidence,
                "locations": [location],
            }
            rows.append(row)
            all_rows.append((filename, row))

        merged = {}
        for row in rows:
            key = (row["name"], row["side"], row["identity"], row["resolution"])
            if key in merged:
                for location in row["locations"]:
                    if location not in merged[key]["locations"]:
                        merged[key]["locations"].append(location)
            else:
                merged[key] = row
        rows = list(merged.values())

        missing = [row for row in rows if not row["exists"]]
        for row in missing:
            missing_rows.append({
                "scenario_file": filename,
                "scenario_id": data.get("scenario_id"),
                "ibs_id": ibs_id,
                "name": row["name"],
                "side": row["side"],
                "zh_name": zh.get(row["side"] or "allies", {}).get(row["name"])
                           or zh.get("axis" if (row["side"] or "allies") == "allies" else "allies", {}).get(row["name"]),
                "reason": row["resolution"],
                "kind": None,
            })
        scenarios.append({
            "scenario_id": data.get("scenario_id"),
            "ibs_id": ibs_id,
            "title": data.get("title"),
            "title_en": data.get("title_en"),
            "source_file": rel(path),
            "ibs_date": meta.get("ibs_date"),
            "rows": rows,
            "missing": [{"name": row["name"], "side": row["side"], "reason": row["resolution"]}
                        for row in missing],
        })

    for runtime_path, scenario_file, ship_key in RUNTIME_FILES:
        path = ROOT / runtime_path
        data = read_json(path)
        ships = data[ship_key]
        scenario = next(item for item in scenarios if item["source_file"] == f"data/campaign/{scenario_file}.json")
        scenario_names = {re.sub(r"[^a-z0-9]", "", row["name"].lower()): row["name"]
                          for row in scenario["rows"]}
        rows = []
        for ship in ships:
            name = ship.get("name")
            name_en = ship.get("name_en")
            candidate = name_en or name
            side = ship.get("side")
            identity, resolution, confidence = resolve(candidate, side)
            if identity is None:
                slug = ship["id"].split("_", 1)[-1] if "_" in ship["id"] else ship["id"]
                normalized = re.sub(r"[^a-z0-9]", "", slug.lower())
                english = scenario_names.get(normalized)
                if english:
                    identity, resolution, confidence = resolve(english, side)
                    if identity:
                        resolution, confidence = "runtime_id_suffix", "inferred"
                if identity is None and name:
                    identity, resolution, confidence = resolve(name, side)
            exists = bool(identity and identity in identity_asset)
            row = {
                "id": ship.get("id"),
                "name": name,
                "name_en": name_en,
                "side": side,
                "kind": ship.get("kind"),
                "identity": identity,
                "portrait": identity_asset[identity]["path"] if exists else None,
                "exists": exists,
                "resolution": resolution,
                "confidence": confidence,
            }
            rows.append(row)
            runtime_rows.append({"runtime_file": runtime_path, "scenario_file": scenario_file, **row})
            if not exists:
                unresolved_runtime.append({"runtime_file": runtime_path, "scenario_file": scenario_file, **row})
        scenario["runtime"] = {
            "file": runtime_path,
            "ship_count": len(rows),
            "resolved": sum(1 for row in rows if row["exists"]),
            "rows": rows,
        }

    unique_names = {}
    for _, row in all_rows:
        unique_names.setdefault((row["name"], row["side"]), row)
    unique_missing = [row for row in unique_names.values() if not row["exists"]]
    runtime_kinds = {(row["scenario_file"], row["name"]): row["kind"]
                     for row in runtime_rows if row.get("kind")}
    for row in missing_rows:
        if row["kind"] is None:
            row["kind"] = runtime_kinds.get((row["scenario_file"], row["zh_name"]))
    missing_by_reason = Counter(row["reason"] for row in missing_rows)
    missing_by_scenario = Counter(row["scenario_file"] for row in missing_rows)
    missing_by_kind = Counter(row["kind"] or "unknown" for row in missing_rows)
    return {
        "schema_version": 1,
        "generated_by": "scripts/import-portraits-identity.py",
        "scope": "当前 11 个有 CAS 源记录的剧本；提到=forces/groups/ships/setup 的舰名，载入=对应 JSON 运行时。",
        "resolution_order": [
            "data/campaign/locale/zh-labels.json#legacy_name_ids（手游固定舰名映射）",
            "zh-labels.ships 中文名 -> server/catalog.json 唯一同名 identity（仅精确同名）",
            "未命中即登记 missing，不用同级代表图或其它舰顶替",
        ],
        "summary": {
            "scenarios": len(scenarios),
            "scenario_rows": len(all_rows),
            "unique_scenario_names": len(unique_names),
            "unique_resolved": len(unique_names) - len(unique_missing),
            "unique_missing": len(unique_missing),
            "missing_rows": len(missing_rows),
            "missing_by_reason": dict(sorted(missing_by_reason.items())),
            "missing_by_scenario": dict(sorted(missing_by_scenario.items())),
            "missing_by_kind": dict(sorted(missing_by_kind.items())),
            "runtime_rows": len(runtime_rows),
            "runtime_resolved": sum(1 for row in runtime_rows if row["exists"]),
            "runtime_unresolved": len(unresolved_runtime),
        },
        "scenarios": scenarios,
        "missing": missing_rows,
        "runtime": {
            "rows": runtime_rows,
            "unresolved": unresolved_runtime,
        },
    }


def build_rarity(catalog, crosswalk, scenario_index):
    cross_by_ship = {row["ibs_ship_id"]: row for row in crosswalk["ships"]}
    scenario_meta = {row["ibs_id"]: row for row in scenario_index["scenarios"]}
    ships = []
    distribution = Counter()
    late_war = 0
    bumped = []
    type_floor_changes = []
    for ship in catalog["ships"]:
        identity = ship["id"]
        row = cross_by_ship[identity]
        evidence = None
        for membership in row["campaign_memberships"]:
            meta = scenario_meta.get(membership["scenario_id"])
            if not meta or meta.get("ibs_kind") != "history":
                continue
            date = meta.get("ibs_date", "")
            if date >= LATE_WAR_FROM and (evidence is None or date > evidence["date"]):
                evidence = {"scenario_id": meta["ibs_id"], "date": date, "title": meta.get("ibs_title")}
        rank = DISPLAY_RANK_INDEX[ship["rarity"]]
        floored = rank
        if ship["type"] in CAPITAL_TYPES:
            floored = max(rank, DISPLAY_RANK_INDEX["rare"])
            if floored != rank:
                type_floor_changes.append(identity)
        display_rank = min(len(DISPLAY_RANKS) - 1, floored + (1 if evidence else 0))
        display = DISPLAY_RANKS[display_rank]
        distribution[display] += 1
        if evidence:
            late_war += 1
        if display != ship["rarity"]:
            bumped.append(identity)
        ships.append({
            "identity": identity,
            "name": ship["name"],
            "side": ship["side"],
            "type": ship["type"],
            "legacy_class_label": row.get("legacy_class_label"),
            "gacha_rarity": ship["rarity"],
            "display_rarity": display,
            "late_war_evidence": evidence,
        })
    capital = [ship for ship in catalog["ships"] if ship["type"] in CAPITAL_TYPES]
    capital_ok = all(ship["rarity"] in ("rare", "ur") for ship in capital)
    return {
        "schema_version": 1,
        "kind": "display-rarity",
        "rule_version": "cas-display-rarity-v1",
        "not_gacha_rarity": True,
        "notes": [
            "只用于展示/排序，不参与征募概率、保底、价格、兑换或任何服务端经济判定。",
            "不写 server/catalog.json；gacha rarity 保持手游固定快照原值。",
            "显示档 = 以固定快照的抽卡稀有度为底板，战列舰/战巡/航母至少 rare，战争后期参战舰上浮一档，封顶 ur。",
            "战列舰/战巡/航母 19 艘在底板上已全部是 rare/ur，因此“至少 rare”的类型下限实际改变 0 艘；不再把 19 艘主力舰全部抬到 ur，UR 保留给原有 UR 与战争后期上浮。",
            "“战争后期”以 data/campaign/crosswalk.json 中的史实剧本日期为准：1943-01-01 及以后有参战记录；虚构剧本（IBS-S-07/12/FM-01）不计。",
            "因此只在 1942 年或虚构 1944 年剧本出场、没有 1943+ 史实参战记录的主力舰（如大和）保持底板档；这是证据边界，不臆造服役年。",
        ],
        "rule": {
            "base": "server/catalog.json ships[].rarity（手游 0.6.9 固定快照，只读）",
            "ranks": DISPLAY_RANKS,
            "type_floor": {"types": sorted(CAPITAL_TYPES), "minimum": "rare",
                           "applied_changes": len(type_floor_changes)},
            "late_war": {"from": LATE_WAR_FROM, "bump": 1,
                         "source": "data/campaign/crosswalk.json scenarios[].ibs_kind == history"},
            "cap": "ur",
        },
        "distribution": {rank: distribution.get(rank, 0) for rank in DISPLAY_RANKS},
        "capital_ships_at_least_rare": capital_ok,
        "late_war_identities": late_war,
        "changed_from_gacha": len(bumped),
        "ships": ships,
    }


def parse_ranked_profiles():
    text = RANKED_FLEETS.read_text(encoding="utf-8")
    if "const PROFILES" not in text:
        fail("src/ranked_fleets.rs 中找不到 PROFILES")
    block = text.split("const PROFILES", 1)[1].split("];", 1)[0]
    return re.findall(r'id:\s*"([^"]+)"', block)


def parse_local_hulls():
    text = PORT_TS.read_text(encoding="utf-8")
    hulls = re.findall(r"^\s{2}(\w+): \{ name: '([^']+)', side: '(\w+)', kind: '([^']+)', max: (\d+) \},",
                       text, re.M)
    return [{"class_id": hull[0], "name": hull[1], "side": hull[2], "kind": hull[3], "max": int(hull[4])}
            for hull in hulls]


def build_report(source, catalog, ledger, class_ledger, mapping, rarity, sources, stats, index_rows_count, manifest):
    crosswalk = read_json(CROSSWALK)
    cross_by_ship = {row["ibs_ship_id"]: row for row in crosswalk["ships"]}
    identity_ids = {entry["identity"] for entry in ledger["assets"]}
    asset_ids = {entry["identity"] for entry in ledger["assets"]}
    catalog_ids = {ship["id"] for ship in catalog["ships"]}

    duplicate_source_paths = [path for path, count in
                              Counter(row["项目内来源"] for row in current_ship_rows(read_index_rows(
                                  ROOT / "data/portraits/source/portrait-index.csv")))
                              .items() if count > 1]
    duplicate_source_hashes = [digest for digest, count in
                               Counter(row["SHA256"] for row in current_ship_rows(read_index_rows(
                                   ROOT / "data/portraits/source/portrait-index.csv")))
                               .items() if count > 1]
    duplicate_names = []
    by_name = defaultdict(list)
    for ship in catalog["ships"]:
        by_name[ship["name"]].append(ship["id"])
    for name, ids in sorted(by_name.items()):
        if len(ids) > 1:
            duplicate_names.append({"name": name, "identities": ids,
                                    "character_ids": [cross_by_ship[i]["ibs_character_id"] for i in ids]})
    shared_characters = [{"character_id": row["ibs_character_id"],
                          "identities": sorted(i for i in catalog_ids
                                               if cross_by_ship[i]["ibs_character_id"] == row["ibs_character_id"])}
                         for row in crosswalk["ships"]
                         if cross_by_ship[row["ibs_ship_id"]]["ibs_character_id"] != row["ibs_ship_id"]]
    # de-duplicate shared character list
    shared = {}
    for item in shared_characters:
        shared[item["character_id"]] = item
    shared = list(shared.values())

    profiles = parse_ranked_profiles()
    cape_instances = sorted(identity_ids & {
        row["ibs_ship_id"] for row in crosswalk["ships"] if row.get("cas_source_instance")
    })
    runtime_direct = set()
    for path in ("data/campaign/period/prologue-runtime.json", "data/campaign/period/channel-runtime.json"):
        for ship in read_json(ROOT / path)["ships"]:
            if ship["id"].startswith("IBS-U-"):
                runtime_direct.add(ship["id"])
    independent = sorted(set(profiles) | set(cape_instances) | runtime_direct)
    class_card_only = sorted(catalog_ids - set(independent))

    class_representatives = []
    class_impact = {}
    for entry in class_ledger["assets"]:
        if entry.get("mapping") != "class_representative":
            continue
        label = entry["character_name"] + "级"
        affected = sorted(identity for identity in catalog_ids
                          if cross_by_ship[identity].get("legacy_class_label") == label)
        class_representatives.append({
            "class_id": entry.get("cas_class_id"),
            "identity": entry["ibs_character_id"],
            "character_name": entry["character_name"],
            "path": entry["path"],
            "sha256": entry["sha256"],
            "same_class_label": label,
            "would_bind": affected,
        })
        class_impact[label] = affected

    local_hulls = parse_local_hulls()
    classes_with_rep = {entry.get("cas_class_id") for entry in class_ledger["assets"]
                        if entry.get("mapping") == "class_representative"}

    missing_count = mapping["summary"]["unique_missing"]
    blockers = [
        {
            "id": "campaign-identity-wiring",
            "status": "external",
            "detail": "战斗里的 characterId 仅在圣乔治角/通道行动（src/campaign/live.rs）与序章/排位（src/world.rs）注入；"
                      "埃斯佩兰斯角、萨沃、塔萨法隆格、库拉湾、皇后湾及资料层剧本没有 IBS identity，"
                      "shipPortrait 无法在这些战役里按 identity 选图。需要内核/战役接线，超出本次立绘 scope。",
            "affected": ["cas-rs-cape-esperance", "cas-rs-savo-island", "cas-rs-tassafaronga",
                         "cas-rs-kula-gulf", "cas-rs-empress-augusta-bay", "cas-rs-horaniu",
                         "cas-rs-kolombangara", "cas-rs-vella-lavella", "cas-rs-guadalcanal-i",
                         "cas-rs-guadalcanal-ii"],
        },
        {
            "id": "shared-character-ids",
            "status": "registered",
            "detail": "roster-crosswalk 有 4 个 ibs_character_id 被两个舰 identity 共用；本 ledger 以 catalog identity（ibs_ship_id）为键，"
                      "每艘有自己的 PNG。若运行时只回传共享的 character_id，客户端无法区分这两艘。",
            "items": shared,
        },
        {
            "id": "scenario-names-without-identity",
            "status": "blocked",
            "detail": f"11 个剧本有 {missing_count} 个唯一舰名在 210 identity 中没有对应；多为运输舰/APD/DMS/飞机/旧式驱逐舰，"
                      "按规范登记，不用同级代表图或借用其它 identity。逐条见 data/portraits/scenario-mapping.json。",
            "count": missing_count,
            "samples": [{"scenario": row["scenario_file"], "name": row["name"], "reason": row["reason"]}
                        for row in mapping["missing"][:12]],
        },
        {
            "id": "local-recruit-four-hulls",
            "status": "known",
            "detail": "本机征募/母港仍只有 4 个舰型（fletcher/cleveland/kagero/sendai），线上征募池 167 艘；"
                      "本轮按要求不改 Harbor/port.ts，因此本机到港仍是舰型代表图，线上收藏才按 identity 出图。",
            "hulls": local_hulls,
            "online_recruitable": sum(1 for ship in catalog["ships"] if ship.get("recruitable")),
        },
        {
            "id": "class-representative-fallback",
            "status": "explicit",
            "detail": "4 个 class_representative 仍保留给没有任何 identity 的舰级槽位，返回 representative=true 并在界面标注“舰型代表”；"
                      "有 identity 的舰永远先按 identity 查，不会落到同级代表图。",
            "class_ids": sorted(classes_with_rep),
        },
        {
            "id": "thumbnail-resolution-mix",
            "status": "documented",
            "detail": "167 个 identity 复用已提交的 700x1050 征募 WebP；43 个非征募 identity 新生成 512x768 WebP，控制新增体积。",
        },
        {
            "id": "stale-browser-assertions",
            "status": "external",
            "detail": "client/tests/browser-online-supply.mjs 仍断言“收藏里只有弗莱彻有立绘”且查看器必须返回 fletcher.png；"
                      "210 identity 上任后该断言过期，应由测试 owner 更新。client/tests/browser-campaign.mjs 是已废弃的旧档案脚本。",
        },
    ]

    return {
        "schema_version": 1,
        "generated_by": "scripts/import-portraits-identity.py",
        "source": sources,
        "checks": {
            "catalog_identities": len(catalog_ids),
            "index_current_ship_rows": index_rows_count,
            "manifest_ships": len(manifest["ships"]),
            "identity_sets_equal": sorted(catalog_ids) == sorted(asset_ids),
            "identities_without_asset": sorted(catalog_ids - asset_ids),
            "assets_without_identity": sorted(asset_ids - catalog_ids),
            "duplicate_source_paths": duplicate_source_paths,
            "duplicate_source_sha256": duplicate_source_hashes,
            "duplicate_display_names": duplicate_names,
            "shared_character_ids": shared,
            "class_representatives": class_representatives,
            "class_representative_impact": class_impact,
        },
        "coverage": {
            "identities": len(catalog_ids),
            "with_identity_portrait": len(asset_ids),
            "missing": len(catalog_ids - asset_ids),
            "reused_online_recruit": ledger["counts"]["reused_online_recruit"],
            "generated_512x768": ledger["counts"]["generated_all"],
            "dimensions": dict(Counter(f"{entry['width']}x{entry['height']}" for entry in ledger["assets"])),
            "bytes": sum(entry["bytes"] for entry in ledger["assets"]),
        },
        "scenario_mapping": mapping["summary"],
        "display_rarity": {
            "distribution": rarity["distribution"],
            "changed_from_gacha": rarity["changed_from_gacha"],
            "late_war_identities": rarity["late_war_identities"],
            "capital_ships_at_least_rare": rarity["capital_ships_at_least_rare"],
        },
        "entities": {
            "count_with_independent_card": len(independent),
            "count_class_card_only": len(class_card_only),
            "independent_profiles": profiles,
            "independent_period_instances": cape_instances,
            "independent_runtime_identities": sorted(runtime_direct),
            "class_card_only": [
                {
                    "identity": identity,
                    "name": next(ship["name"] for ship in catalog["ships"] if ship["id"] == identity),
                    "side": next(ship["side"] for ship in catalog["ships"] if ship["id"] == identity),
                    "type": next(ship["type"] for ship in catalog["ships"] if ship["id"] == identity),
                    "legacy_class_label": cross_by_ship[identity].get("legacy_class_label"),
                    "cas_named_hull_status": cross_by_ship[identity].get("cas_named_hull_status"),
                }
                for identity in class_card_only
            ],
        },
        "local_recruit": {
            "hulls": local_hulls,
            "roster_slots": 5,
            "note": "本机征募仍按 port.ts 的 4 个舰型抽取；线上 167 舰池未回灌本机。",
        },
        "blockers": blockers,
    }


def build_sources(source, scenario_index, mapping):
    files = []

    def add(role, path: Path, copy_path: Path | None = None, extra=None):
        try:
            display_path = rel(path)
        except ValueError:
            display_path = path.as_posix()
        item = {
            "role": role,
            "original_path": display_path,
            "sha256": sha256_file(path),
            "bytes": path.stat().st_size,
        }
        if copy_path is not None:
            item["workspace_copy"] = rel(copy_path)
            item["workspace_sha256"] = sha256_file(copy_path)
        if extra:
            item.update(extra)
        files.append(item)

    add("portrait_index", source / "mobile/release/立绘全集/立绘索引.csv", SOURCE_COPY,
        {"current_ship_rows": 210, "total_rows": 307})
    add("portrait_manifest", source / "mobile/content/fleet-portrait-manifest.json", None,
        {"ships": 210})
    add("pilot_catalog", ROOT / "server/catalog.json", None, {"ships": 210})
    add("roster_crosswalk", ROOT / "data/campaign/roster-crosswalk.json", None, {"ships": 210})
    add("scenario_index", ROOT / "data/campaign/crosswalk.json", None,
        {"scenarios": len(scenario_index["scenarios"])})
    add("zh_name_labels", ROOT / "data/campaign/locale/zh-labels.json", None, {})
    add("class_representative_ledger", ROOT / "client/src/assets/portraits/ledger.json", None, {})
    scenario_files = []
    for filename, ibs_id in SCENARIO_FILES:
        path = ROOT / "data/campaign" / (filename + ".json")
        scenario_files.append({"path": rel(path), "ibs_id": ibs_id, "sha256": sha256_file(path)})
    runtime_files = []
    for runtime_path, scenario_file, _ in RUNTIME_FILES:
        runtime_files.append({"path": runtime_path, "scenario": scenario_file,
                              "sha256": sha256_file(ROOT / runtime_path)})
    return {
        "schema_version": 1,
        "generated_by": "scripts/import-portraits-identity.py",
        "reference_project": "铁底湾",
        "reference_checkout": source.as_posix(),
        "reference_mobile_version": "0.6.9",
        "rule": "参考项目与原始素材只读；工作区只保留复核过的派生物和索引副本。",
        "files": files,
        "scenario_files": scenario_files,
        "runtime_files": runtime_files,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE,
                        help="铁底湾 read-only checkout (default: pinned worktree)")
    parser.add_argument("--index", type=Path, default=None,
                        help="立绘索引 CSV; defaults to <source>/mobile/release/立绘全集/立绘索引.csv")
    parser.add_argument("--check", action="store_true",
                        help="verify committed outputs without writing")
    args = parser.parse_args()

    source = args.source
    index_path = args.index or (source / "mobile/release/立绘全集/立绘索引.csv")
    if not index_path.exists():
        fail(f"找不到立绘索引：{index_path}")
    if not (source / "mobile/public/characters/ships/fleet-v2").exists():
        fail(f"找不到 fleet-v2：{source}")

    catalog = read_json(CATALOG)
    crosswalk = read_json(CROSSWALK)
    scenario_index = read_json(SCENARIO_INDEX)
    labels = read_json(LABELS)
    class_ledger = read_json(CLASS_LEDGER)

    rows, by_id, manifest_bytes, manifest, cross_by_ship = verify_sources(
        source, catalog, crosswalk, index_path, args.check)

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    (DATA_DIR / "source").mkdir(parents=True, exist_ok=True)
    if not SOURCE_COPY.exists():
        if args.check:
            fail(f"缺少索引副本：{rel(SOURCE_COPY)}")
        SOURCE_COPY.write_bytes(index_path.read_bytes())
    if sha256_file(SOURCE_COPY) != sha256_file(index_path):
        fail("data/portraits/source/portrait-index.csv 与源索引不一致")

    recruit = reusable_recruit_assets()
    ledger, stats = build_identity_ledger(source, catalog, by_id, cross_by_ship, recruit, args.check)
    mapping = build_mapping(catalog, ledger, labels, scenario_index)
    rarity = build_rarity(catalog, crosswalk, scenario_index)
    sources = build_sources(source, scenario_index, mapping)
    report = build_report(source, catalog, ledger, class_ledger, mapping, rarity, sources,
                          stats, len(rows), manifest)

    outputs = {
        ALL_LEDGER: payload(ledger),
        SOURCES_OUT: payload(sources),
        REPORT_OUT: payload(report),
        MAPPING_OUT: payload(mapping),
        RARITY_OUT: payload(rarity),
    }
    for path, text in outputs.items():
        write_or_check(path, text, args.check)

    print(f"identity ledger: {ledger['counts']['identities']} identities "
          f"({ledger['counts']['reused_online_recruit']} reused, {ledger['counts']['generated_all']} generated)")
    print(f"scenario mapping: {mapping['summary']['unique_scenario_names']} unique names, "
          f"{mapping['summary']['unique_resolved']} resolved, {mapping['summary']['unique_missing']} missing; "
          f"runtime {mapping['summary']['runtime_resolved']}/{mapping['summary']['runtime_rows']}")
    print(f"display rarity: {rarity['distribution']} (late-war {rarity['late_war_identities']}, "
          f"changed {rarity['changed_from_gacha']})")
    print(f"class-card only: {report['entities']['count_class_card_only']} / "
          f"{report['coverage']['identities']}")
    print("check: PASS" if args.check else "wrote outputs")


if __name__ == "__main__":
    main()
