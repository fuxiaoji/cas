"""Import the registered identity artwork into Godot without changing sources.

The import preserves one stable IBS-U identity per portrait and verifies the
existing ledger digest. Generated or reference-model chibis are registered only
when an identity-named image and a provenance sidecar are both present. The two
sources remain separately counted; rejected drafts are never default projections.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GODOT = ROOT / "godot"
CHARACTERS = GODOT / "assets" / "characters"
CATALOG = GODOT / "data" / "ships.json"
LEDGER = CHARACTERS / "ledger.json"
STARTERS = {
    "allies": [
        "IBS-U-USN-FLETCHER", "IBS-U-USN-PERKINS", "IBS-U-USN-MAURY",
        "IBS-U-USN-DRAYTON", "IBS-U-USN-HONOLULU",
    ],
    "axis": [
        "IBS-U-IJN-KAGERO", "IBS-U-IJN-TAKANAMI", "IBS-U-IJN-OYASHIO",
        "IBS-U-IJN-KUROSHIO", "IBS-U-IJN-SENDAI",
    ],
}


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def resource(path: Path) -> str:
    return "res://" + path.relative_to(GODOT).as_posix()


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def registered_chibi(identity: str, folder: str = "chibis") -> tuple[str, dict | None]:
    stem = identity.lower()
    for extension in ("png", "webp"):
        path = CHARACTERS / folder / f"{stem}.{extension}"
        sidecar = path.with_suffix(".json")
        if not path.exists() or not sidecar.exists():
            continue
        entry = read_json(sidecar)
        if entry.get("identity") != identity or entry.get("status") not in {"generated", "generated_v2_candidate", "reference_spine_render"}:
            raise ValueError(f"Invalid chibi provenance for {identity}: {sidecar}")
        if entry.get("sha256") and entry["sha256"] != digest(path):
            raise ValueError(f"Chibi digest mismatch: {path}")
        if entry.get("source_portrait_sha256"):
            portrait_path = GODOT / entry["source_portrait"].removeprefix("res://")
            if digest(portrait_path) != entry["source_portrait_sha256"]:
                raise ValueError(f"Generated chibi portrait reference changed: {identity}")
        entry = dict(entry, path=resource(path), sha256=digest(path))
        return resource(path), entry
    return "", None


def build() -> dict:
    cards = read_json(ROOT / "data/ships/cards.json")["cards"]
    portraits = read_json(ROOT / "client/src/assets/portraits/all/ledger.json")
    portrait_by_id = {row["identity"]: row for row in portraits["assets"]}
    points = read_json(ROOT / "data/rules/cas-competitive-points-v1.json")["ships"]
    if len(cards) != 210 or len(portrait_by_id) != 210:
        raise ValueError("Identity catalogue must contain all 210 registered hulls")
    rows: list[dict] = []
    imported: list[dict] = []
    chibi_entries: list[dict] = []
    all_chibi_variants: list[dict] = []
    for card in cards:
        identity = card["identity"]
        art = portrait_by_id[identity]
        source_root = (ROOT / "client/src/online-recruit/assets" if art["root"] == "online-recruit"
                       else ROOT / "client/src/assets/portraits/all")
        source = source_root / art["path"]
        actual_digest = digest(source)
        if actual_digest != art["sha256"]:
            raise ValueError(f"Registered portrait digest mismatch: {identity}")
        target = CHARACTERS / "portraits" / (identity.lower() + source.suffix)
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists() or digest(target) != actual_digest:
            shutil.copy2(source, target)
        point_row = points.get(identity, {})
        profile_id = point_row.get("profile_id", "")
        reference_chibi, reference_provenance = registered_chibi(identity)
        generated_chibi, generated_provenance = registered_chibi(identity, "chibis-generated")
        for variant in (reference_provenance, generated_provenance):
            if variant:
                all_chibi_variants.append(variant)
        chibi, provenance = ((generated_chibi, generated_provenance) if generated_chibi
                             else (reference_chibi, reference_provenance))
        if provenance:
            chibi_entries.append(provenance)
        rows.append({
            "id": identity, "name": card["name"], "side": card["side"],
            "type": card["type"], "class": card.get("class", ""),
            "points": point_row.get("points", 0),
            "portrait": resource(target), "chibi": chibi,
            "chibi_reference": reference_chibi,
            "chibi_generated": generated_chibi,
            "playable": bool(card.get("playable")),
            "profile": profile_id.partition("#")[2], "profile_id": profile_id,
            "class_id": card.get("cas_source_class", ""),
            "rarity": card.get("display_rarity", "rare"),
            "gacha_rarity": card.get("gacha_rarity", "rare"),
            "projection_status": (({"generated": "generated_chibi", "generated_v2_candidate": "generated_v2_candidate", "reference_spine_render": "reference_spine_projection"}[provenance["status"]])
                                  if chibi else "portrait_projection"),
            "chibi_appearance_verified_against_cas_portrait": bool(provenance and
                (provenance["status"] == "generated" or provenance.get("appearance_review") == "agent_visual_checked")),
            "chibi_user_style_accepted": bool(provenance and provenance["status"] == "generated"),
            "chibi_user_style_acceptance_required_for_integration": False,
            "art_scope": "local_developer_and_test_builds",
        })
        imported.append({
            "identity": identity, "character_name": card["name"],
            "path": resource(target), "source": source.relative_to(ROOT).as_posix(),
            "source_ledger": "client/src/assets/portraits/all/ledger.json",
            "sha256": actual_digest, "mapping": "exact_identity",
        })
    background_ledger = read_json(ROOT / "client/src/assets/harbor/ledger.json")
    background_assets = []
    for art in background_ledger["assets"]:
        source = ROOT / "client/src/assets/harbor" / art["path"]
        if digest(source) != art["sha256"]:
            raise ValueError(f"Background digest mismatch: {source}")
        target = GODOT / "assets/backgrounds" / art["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists() or digest(target) != art["sha256"]:
            shutil.copy2(source, target)
        background_assets.append({"path": resource(target), "sha256": art["sha256"],
                                  "source": source.relative_to(ROOT).as_posix()})
    summary = {
        "identities": len(rows), "playable": sum(row["playable"] for row in rows),
        "portraits": len(imported),
        "available_chibis": len(chibi_entries),
        "generated_chibis": sum(entry["status"] == "generated" for entry in chibi_entries),
        "generated_v2_candidates": sum(entry["status"] == "generated_v2_candidate" for entry in all_chibi_variants),
        "produced_generated_images": sum(entry["status"] in {"generated", "generated_v2_candidate"} for entry in all_chibi_variants),
        "accepted_generated_images": sum(entry["status"] == "generated" for entry in all_chibi_variants),
        "identities_without_generated_candidate": len(rows) - sum(entry["status"] in {"generated", "generated_v2_candidate"} for entry in chibi_entries),
        "reference_spine_chibis": sum(entry["status"] == "reference_spine_render" for entry in all_chibi_variants),
        "portrait_matched_generated_chibis_pending": len(rows) - sum(entry["status"] in {"generated", "generated_v2_candidate"} for entry in chibi_entries),
        "portrait_projections_pending_chibi": len(rows) - len(chibi_entries),
        "identity_fallbacks": 0,
    }
    write_json(CATALOG, {
        "schema_version": 1, "kind": "cas-godot-identity-catalogue",
        "generated_by": "scripts/import-godot-art.py", "summary": summary,
        "starters": STARTERS, "featured_ship": "IBS-U-USN-ERMA-MISSOURI",
        "ships": rows,
    })
    write_json(LEDGER, {
        "schema_version": 1, "scope": "CAS local developer and test builds; public distribution rights not established.",
        "summary": summary, "portraits": imported,
        "chibis": all_chibi_variants,
        "generated_chibis": [entry for entry in chibi_entries if entry["status"] == "generated"],
        "generated_v2_candidates": [entry for entry in all_chibi_variants if entry["status"] == "generated_v2_candidate"],
        "reference_spine_chibis": [entry for entry in all_chibi_variants if entry["status"] == "reference_spine_render"],
        "pending_chibis": [{"identity": row["id"], "name": row["name"],
                            "display_fallback": row["projection_status"],
                            "blocker": "Not yet generated and agent-reviewed against the CAS identity portrait; third-party reference shape is not a portrait-matched derivative."}
                           for row in rows if row["projection_status"] not in {"generated_chibi", "generated_v2_candidate"}],
        "backgrounds": background_assets,
        "chibi_reference": {
            "url": "https://ww-rm.top/azurlane_char/", "accessed": "2026-11-11",
            "format": "Spine .skel/.atlas/texture pages, not assembled sprite images",
            "status": "exact_name_reference_models_rendered_for_local_testing",
            "source_manifest": "tools/spine-reference/downloads.json",
            "render_manifest": "tools/spine-reference/renders.json",
            "public_distribution_rights": "not_established",
        },
    })
    return summary


def verify() -> dict:
    catalogue = read_json(CATALOG)
    ledger = read_json(LEDGER)
    ships = catalogue["ships"]
    ids = [row["id"] for row in ships]
    assert len(ids) == 210 and len(set(ids)) == 210
    assert sum(row["playable"] for row in ships) == 202
    assert all(row["points"] > 0 and row["profile"] for row in ships if row["playable"])
    by_id = {row["id"]: row for row in ships}
    for side, starter_ids in STARTERS.items():
        assert len(starter_ids) == len(set(starter_ids)) == 5
        assert all(by_id[identity]["playable"] and by_id[identity]["side"] == side for identity in starter_ids)
    for row in ledger["portraits"] + ledger["backgrounds"] + ledger["chibis"]:
        path = GODOT / row["path"].removeprefix("res://")
        assert path.is_file() and digest(path) == row["sha256"], path
    for row in ships:
        assert (GODOT / row["portrait"].removeprefix("res://")).is_file()
        if row["chibi"]:
            assert (GODOT / row["chibi"].removeprefix("res://")).is_file()
        if row.get("chibi_generated"):
            assert row["chibi"] == row["chibi_generated"]
        if row["projection_status"] == "generated_v2_candidate":
            assert not row["chibi_user_style_accepted"]
        if row.get("chibi_reference"):
            assert (GODOT / row["chibi_reference"].removeprefix("res://")).is_file()
    return dict(catalogue["summary"], verified=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true", help="Verify the registered import without writing")
    options = parser.parse_args()
    print(json.dumps(verify() if options.verify else build(), ensure_ascii=False))
