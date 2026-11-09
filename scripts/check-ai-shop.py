"""Check that the client AiShop projection matches the server catalog.

The client is TypeScript source, so this is a deliberately small field-level
reader rather than a TS compiler plugin: it extracts the six object literals and
compares id/name/description/unlock/cost/currency/provisional against
`server/catalog.json`, plus the optional role/axes metadata against the report.
"""
from __future__ import annotations

import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
TEXT = (ROOT / "client" / "src" / "ai-shop.ts").read_text(encoding="utf-8")
CATALOG = json.loads((ROOT / "server" / "catalog.json").read_text(encoding="utf-8"))
REPORT = json.loads((ROOT / "data" / "ai" / "ai-report.json").read_text(encoding="utf-8"))

BLOCK = re.compile(r"\{\s*id: '([^']+)'(.*?)\n  \},", re.S)


def field(body: str, name: str):
    match = re.search(rf"{name}: '([^']*)'", body)
    return match.group(1) if match else None


def number(body: str, name: str):
    match = re.search(rf"{name}: (\d+)", body)
    return int(match.group(1)) if match else None


def main():
    rows = {}
    for item_id, body in BLOCK.findall(TEXT):
        rows[item_id] = {
            "id": item_id,
            "name": field(body, "name"),
            "description": field(body, "description"),
            "unlock": field(body, "unlock"),
            "stage": field(body, "stage"),
            "stageName": field(body, "stageName"),
            "cost": number(body, "cost"),
            "currency": field(body, "currency"),
            "provisional": "provisional: true" in body,
            "role": field(body, "role"),
        }
    catalog = {entry["id"]: entry for entry in CATALOG["ai_profiles"]}
    problems = []
    if len(rows) != 6:
        problems.append(f"client has {len(rows)} entries, expected 6")
    if set(rows) != set(catalog):
        problems.append(f"id sets differ: client {sorted(rows)} catalog {sorted(catalog)}")
    for item_id, row in rows.items():
        entry = catalog.get(item_id)
        if entry is None:
            continue
        for key in ("name", "description", "unlock", "cost"):
            if row[key] != entry[key]:
                problems.append(f"{item_id}.{key}: client={row[key]!r} catalog={entry[key]!r}")
        if row["currency"] != entry["currency"] or not row["provisional"] or not entry.get("provisional"):
            problems.append(f"{item_id}: currency/provisional mismatch")
    report_rows = {profile["id"]: profile for profile in REPORT["profiles"]}
    for item_id, row in rows.items():
        profile = report_rows.get(item_id)
        if profile is None:
            problems.append(f"{item_id}: missing from ai-report")
            continue
        if row["role"] != profile["role"]:
            problems.append(f"{item_id}.role: client={row['role']!r} report={profile['role']!r}")
        if row["stage"] != row["unlock"].split(":", 1)[-1]:
            problems.append(f"{item_id}: stage does not match unlock")
        if item_id in ("evo-brawler", "evo-kiter", "evo-denial"):
            for axis in ("range", "maneuver", "torpedo"):
                if f"{axis}: '" not in TEXT.split(f"id: '{item_id}'", 1)[1].split("},", 1)[0]:
                    problems.append(f"{item_id}: missing axes.{axis}")
    if problems:
        print("\n".join(problems))
        return 1
    print("client/src/ai-shop.ts matches server/catalog.json and ai-report.json for six profiles")
    return 0


if __name__ == "__main__":
    sys.exit(main())
