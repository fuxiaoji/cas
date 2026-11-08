"""Bind every kept-scenario ship into the free-economy card pool with its portrait.

The CAS campaign only keeps the twelve scenarios that have a Rising Sun
counterpart (see src/campaign.rs REMOVED_SCENARIOS). Every identity that those
scenarios list in data/campaign/roster-crosswalk.json becomes recruitable and
gets the pinned mobile portrait encoded as WebP, mirroring the economy
projection in server/import_catalog.py (mobile 0.6.11 pools, pity, duplicate
medals and prices untouched).

Usage:
    python scripts/import-scenario-portraits.py <ironbottom-worktree> [--check]
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REMOVED = {"IBS-S-03", "IBS-S-07", "IBS-S-12", "IBS-S-FM-01"}
CATALOG = ROOT / "server/catalog.json"
OVERLAY = ROOT / "server/scenario-recruitable.json"
LEDGER = ROOT / "client/src/online-recruit/ledger.json"
ASSETS = ROOT / "client/src/online-recruit/assets"
SOURCE_COMMIT = "41a1fb93063673ac8f84388a8f326a8b1a5fc3d5"


def scenario_memberships():
    rows = json.loads((ROOT / "data/campaign/roster-crosswalk.json").read_text(encoding="utf-8"))["ships"]
    memberships = {}
    for row in rows:
        kept = sorted({item["scenario_id"] for item in row["campaign_memberships"]} - REMOVED)
        if kept:
            memberships[row["ibs_character_id"]] = kept
    return memberships


def catalog_projection(source, memberships):
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    mobile = json.loads((source / "mobile/content/catalog.json").read_text(encoding="utf-8"))
    scenario = json.loads((source / "mobile/content/campaign-scenarios.json").read_text(encoding="utf-8"))
    cost = {ship["id"]: ship for ship in mobile["ships"] + scenario["ships"]}
    for ship in catalog["ships"]:
        if ship["id"] in memberships:
            ship["recruitable"] = True
            if ship["rarity"] == "common" and ship.get("credits_price") is None:
                ship["credits_price"] = max(200, ((cost[ship["id"]]["cost"] + 99) // 100) * 100)
    return catalog


def portraits(source, memberships, catalog):
    from PIL import Image

    manifest_path = source / "mobile/content/fleet-portrait-manifest.json"
    manifest_bytes = manifest_path.read_bytes()
    manifest = {row["ship_id"]: row for row in json.loads(manifest_bytes)["ships"]}
    ledger = json.loads(LEDGER.read_text(encoding="utf-8"))
    assert hashlib.sha256(manifest_bytes).hexdigest() == ledger["source_manifest_sha256"]
    known = {entry["character_id"]: entry for entry in ledger["assets"]}
    wanted = [ship for ship in catalog["ships"] if ship["recruitable"]]
    assets = []
    for ship in wanted:
        row = manifest[ship["id"]]
        assert row["status"] == "ready", ship["id"]
        source_rel = "mobile/public" + row["path"]
        raw = (source / source_rel).read_bytes()
        source_sha = hashlib.sha256(raw).hexdigest()
        assert source_sha == row["sha256"], source_rel
        filename = ship["id"].lower() + ".webp"
        target = ASSETS / filename
        if not target.exists():
            with Image.open(source / source_rel) as image:
                image = image.convert("RGBA")
                image.thumbnail((700, 1050), Image.LANCZOS)
                image.save(target, "WEBP", quality=92, method=4)
        blob = target.read_bytes()
        with Image.open(target) as image:
            size = list(image.size)
        entry = {
            "path": filename,
            "character_id": ship["id"],
            "character_name": ship["name"],
            "source_path": source_rel,
            "source_sha256": source_sha,
            "sha256": hashlib.sha256(blob).hexdigest(),
            "size": size,
        }
        previous = known.get(ship["id"])
        if previous:
            assert previous["source_path"] == source_rel and previous["source_sha256"] == source_sha
        assets.append(entry)
    ledger["assets"] = assets
    return ledger


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_checkout", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    memberships = scenario_memberships()
    catalog = catalog_projection(args.source_checkout, memberships)
    ledger = portraits(args.source_checkout, memberships, catalog)
    overlay = {
        "schema_version": 1,
        "source": "data/campaign/roster-crosswalk.json",
        "removed_scenarios": sorted(REMOVED),
        "ships": {ship_id: scenarios for ship_id, scenarios in sorted(memberships.items())},
    }
    payloads = {
        CATALOG: json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        OVERLAY: json.dumps(overlay, ensure_ascii=False, indent=2) + "\n",
        LEDGER: json.dumps(ledger, ensure_ascii=False, indent=2) + "\n",
    }
    if args.check:
        for path, payload in payloads.items():
            assert path.read_text(encoding="utf-8") == payload, path
    else:
        for path, payload in payloads.items():
            path.write_text(payload, encoding="utf-8", newline="\n")
    recruitable = [ship for ship in catalog["ships"] if ship["recruitable"]]
    print(f"Bound {len(recruitable)} recruitable identities "
          f"({len(memberships)} from kept scenarios) to portraits.")


if __name__ == "__main__":
    main()
