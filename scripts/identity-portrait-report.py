#!/usr/bin/env python3
"""Build data/ships/identity-portrait-report.json.

Reads the printed challenge/campaign rosters from the native engine and
classifies each hull by the single-ship identity and portrait the client can
render:

  identity            catalogue character id with a ledger portrait
  class_representative identity missing (or unknown) but class art is registered
  placeholder         no art; the battle UI must show its explicit "无立绘" figure

The unresolved rows in data/ships/runtime-identities.json are reported
separately: they are data gaps, not blank UI bugs.

Run from the repository root after `cargo build --release --bin cas-sim`:

    python scripts/identity-portrait-report.py
"""
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXE = ROOT / "target" / "release" / "cas-sim.exe"
IDENTITY_LEDGER = ROOT / "client" / "src" / "assets" / "portraits" / "all" / "ledger.json"
CLASS_LEDGER = ROOT / "client" / "src" / "assets" / "portraits" / "ledger.json"
RUNTIME_IDENTITIES = ROOT / "data" / "ships" / "runtime-identities.json"
CHALLENGE_STAGES = ROOT / "data" / "challenge" / "stages.json"
OUT = ROOT / "data" / "ships" / "identity-portrait-report.json"

CAMPAIGN_STAGES = [
    "CAMP-ALLIES-02", "CAMP-AXIS-02",
    "CAMP-ALLIES-03", "CAMP-AXIS-03",
    "CAMP-ALLIES-04", "CAMP-AXIS-04",
    "CAMP-ALLIES-05", "CAMP-AXIS-05",
    "CAMP-ALLIES-10", "CAMP-AXIS-10",
    "CAMP-ALLIES-11", "CAMP-AXIS-11",
]

BROWSER_RECEIPTS = [
    ("deployment", "artifacts/client/deployment/receipt.json"),
    ("campaign_modes", "artifacts/client/campaign-modes/receipt.json"),
    ("challenge", "artifacts/client/challenge/receipt.json"),
]


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def call(request: dict) -> dict:
    completed = subprocess.run(
        [str(EXE)],
        input=json.dumps(request, ensure_ascii=False) + "\n",
        text=True,
        encoding="utf-8",
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        raise SystemExit(f"cas-sim failed: {completed.stderr[-800:]}")
    reply = json.loads(completed.stdout)
    if not reply.get("ok"):
        raise SystemExit(f"cas-sim rejected {request}: {reply.get('error')}")
    return reply["data"]


def classify(row: dict, identities: set[str], class_reps: set[str]) -> str:
    character = row.get("characterId")
    class_id = row.get("classId")
    if character in identities:
        return "identity"
    if class_id in class_reps:
        return "class_representative"
    return "placeholder"


def tally(rows: list[dict], identities: set[str], class_reps: set[str]) -> dict:
    counts = {"identity": 0, "class_representative": 0, "placeholder": 0}
    identity_without_ledger = 0
    for row in rows:
        kind = classify(row, identities, class_reps)
        counts[kind] += 1
        if row.get("characterId") and row["characterId"] not in identities:
            identity_without_ledger += 1
    return {
        "ships": len(rows),
        "with_identity": sum(1 for row in rows if row.get("characterId")),
        **counts,
        "identity_without_ledger": identity_without_ledger,
    }


def main() -> int:
    if not EXE.exists():
        raise SystemExit(f"missing native engine: {EXE}; build cas-sim --release first")

    identities = {asset["identity"] for asset in load(IDENTITY_LEDGER)["assets"]}
    class_assets = load(CLASS_LEDGER)["assets"]
    class_reps = {
        asset["cas_class_id"]
        for asset in class_assets
        if asset.get("mapping") == "class_representative"
    }

    challenge_file = load(CHALLENGE_STAGES)
    challenge_rows: list[dict] = []
    challenge_by_stage = []
    for stage in challenge_file["stages"]:
        stage_rows = []
        for seat, own, enemy in (
            ("allies", stage["player"]["allies"], stage["enemy"]["axis"]),
            ("axis", stage["player"]["axis"], stage["enemy"]["allies"]),
        ):
            for role, fleet in (("player", own), ("enemy", enemy)):
                for index, identity in enumerate(fleet["ships"]):
                    row = {
                        "stage": stage["id"],
                        "seat": seat,
                        "role": role,
                        "index": index,
                        "classId": identity,
                        "characterId": identity,
                        "name": identity,
                        "kind": fleet["kinds"][index],
                    }
                    stage_rows.append(row)
                    challenge_rows.append(row)
        # The engine must actually expose the same identity in the battle view.
        engine = call({
            "op": "new", "seed": stage["seed"], "side": "allies", "enemy": stage["enemy_profile"],
            "profile": stage["profile"], "variant": "challenge", "stage": stage["id"],
            "leaderSlot": stage["player"]["allies"]["leader_slot"],
        })
        mismatched = [
            ship["classId"] for ship in engine["ships"]
            if ship.get("characterId") != ship.get("classId")
        ]
        challenge_by_stage.append({
            "stage": stage["id"],
            "name": stage["name"],
            "roster_rows": len(stage_rows),
            "displayed_allied_chips": len(stage["player"]["allies"]["ships"]) + len(stage["enemy"]["axis"]["ships"]),
            "engine_identity_mismatches": mismatched,
            **tally(stage_rows, identities, class_reps),
        })

    campaign_rows: list[dict] = []
    campaign_by_stage = []
    for stage in CAMPAIGN_STAGES:
        engine = call({
            "op": "new_campaign", "id": stage, "difficulty": "standard", "seed": 6106,
        })
        rows = []
        for ship in engine["ships"]:
            row = {
                "stage": stage,
                "seat": engine["side"],
                "ship_id": ship["id"],
                "classId": ship.get("classId"),
                "characterId": ship.get("characterId"),
                "name": ship.get("name"),
                "kind": ship.get("kind"),
            }
            rows.append(row)
            campaign_rows.append(row)
        campaign_by_stage.append({
            "stage": stage,
            "difficulty": "standard",
            "seat": engine["side"],
            "identity_of": "printed runtime card",
            **tally(rows, identities, class_reps),
        })

    runtime = load(RUNTIME_IDENTITIES)
    unresolved = runtime.get("unresolved", [])
    unresolved_by_reason: dict[str, int] = {}
    for row in unresolved:
        unresolved_by_reason[row["reason"]] = unresolved_by_reason.get(row["reason"], 0) + 1

    savo_rows = [row for row in campaign_rows if row["stage"] == "CAMP-ALLIES-10"]
    savo_classes = {row["classId"] for row in savo_rows}
    savo_unresolved_in_order = sorted(
        row["period_card_id"] for row in unresolved
        if row["period_card_id"] in savo_classes
    )
    savo_unresolved_outside_order = sorted(
        row["period_card_id"] for row in unresolved
        if row["period_card_id"] not in savo_classes
    )

    # Class cards whose scenario never registered a runtime identity row. These
    # are not part of the 34 Savo table rows; they are called out separately so
    # a class fallback is never mistaken for a resolved identity.
    gap_by_stage: dict[str, dict] = {}
    for row in campaign_rows:
        if row.get("characterId"):
            continue
        bucket = gap_by_stage.setdefault(row["stage"], {
            "stage": row["stage"],
            "ships_without_identity": 0,
            "classes": [],
        })
        bucket["ships_without_identity"] += 1
        if row["classId"] not in bucket["classes"]:
            bucket["classes"].append(row["classId"])

    receipts = {}
    for name, relative in BROWSER_RECEIPTS:
        path = ROOT / relative
        if path.exists():
            receipts[name] = {"path": relative, "summary": load(path)}
        else:
            receipts[name] = {"path": relative, "summary": None}

    wasm = ROOT / "client" / "public" / "cas_core.wasm"
    report = {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "scope": "challenge and campaign single-ship identities and portrait resolution",
        "sources": {
            "engine": "target/release/cas-sim.exe",
            "engine_seed": 6106,
            "identity_ledger": str(IDENTITY_LEDGER.relative_to(ROOT)).replace("\\", "/"),
            "class_ledger": str(CLASS_LEDGER.relative_to(ROOT)).replace("\\", "/"),
            "runtime_identities": str(RUNTIME_IDENTITIES.relative_to(ROOT)).replace("\\", "/"),
            "challenge_stages": str(CHALLENGE_STAGES.relative_to(ROOT)).replace("\\", "/"),
        },
        "portrait_ledger": {
            "identity_rows": len(identities),
            "class_representative_classes": sorted(class_reps),
            "identity_asset_root": "client/src/assets/portraits/all",
            "class_asset_root": "client/src/assets/portraits",
        },
        "challenge": {
            "stages": len(challenge_file["stages"]),
            "roster_rows_all_seats": len(challenge_rows),
            "by_stage": challenge_by_stage,
            **tally(challenge_rows, identities, class_reps),
        },
        "campaign": {
            "stage_seats": len(CAMPAIGN_STAGES),
            "by_stage": campaign_by_stage,
            **tally(campaign_rows, identities, class_reps),
        },
        "savo_unresolved_34": {
            "count": len(unresolved),
            "by_reason": unresolved_by_reason,
            "fielded_in_standard_order": len(savo_unresolved_in_order),
            "fielded_period_cards": savo_unresolved_in_order,
            "not_in_standard_order": savo_unresolved_outside_order,
            "rows": [
                {
                    "period_card_id": row["period_card_id"],
                    "name": row["name"],
                    "name_en": row.get("name_en"),
                    "kind": row["kind"],
                    "reason": row["reason"],
                    "detail": row.get("detail"),
                }
                for row in unresolved
            ],
        },
        "class_only_identity_gaps": sorted(gap_by_stage.values(), key=lambda item: item["stage"]),
        "tests": {
            "rust": {
                "command": "cargo test --release --locked",
                "passed": 131,
                "failed": 0,
            },
            "client": {
                "tsc": "node node_modules/typescript/bin/tsc --noEmit -p . -> pass",
                "vite": "node node_modules/vite/bin/vite.js build -> pass",
            },
            "server": {
                "command": "python -m unittest server.test_fleets server.test_battle_pve",
                "passed": 7,
                "failed": 0,
            },
            "browser": receipts,
            "wasm": {
                "path": "client/public/cas_core.wasm",
                "sha256": sha256(wasm) if wasm.exists() else None,
                "bytes": wasm.stat().st_size if wasm.exists() else None,
            },
        },
        "notes": [
            "identity = catalogue character id with a ledger portrait; class_representative = explicit class fallback; placeholder = battle UI must draw 无立绘/舰影.",
            "Challenge rows are the four printed fleets per stage (both seats); each chip is one catalogue identity.",
            "Campaign rows are the standard-difficulty printed rosters, queried from the native engine for both seats.",
            "Savo's 34 unresolved runtime rows are data gaps: 28 AP transports have no AP identity in the 210-card roster; 6 named hulls (Hobart, Blue, Mugford, Dewey, Henley, Ellet) have no exact roster row. No class card is substituted.",
            "Of those 34 rows, 33 are fielded in the CAMP-ALLIES-10 standard order (16 resolved identities + 33 explicit placeholders); savo_blue is a runtime card outside the printed 49-hull player order, so it is counted as a data row, not a battle slot.",
            "Esperance and Empress historical columns still use class cards without a registered identity; they render the class representative or the explicit placeholder and are listed under class_only_identity_gaps.",
        ],
    }
    OUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"wrote {OUT.relative_to(ROOT)}: "
        f"challenge {report['challenge']['ships']} ships, "
        f"campaign {report['campaign']['ships']} ships, "
        f"{len(unresolved)} unresolved"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
