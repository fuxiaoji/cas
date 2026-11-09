#!/usr/bin/env python3
"""Validate data/challenge/stages.json and emit the client-side stage module.

The stage table names registered CAS identities, so the generator resolves the
frozen point table (data/rules/cas-competitive-points-v1.json) and the identity
ledger (data/ships/cards.json) as read-only inputs. It fails if a stage declares
a point total, hull kind, budget, map or evidence row that disagrees with those
sources.

Usage:
  python scripts/challenge-stages.py --check   # fail if the generated module drifts
  python scripts/challenge-stages.py --write   # regenerate the module
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data" / "challenge" / "stages.json"
TARGET = ROOT / "client" / "src" / "activities" / "challenge-stages.ts"
POINTS = ROOT / "data" / "rules" / "cas-competitive-points-v1.json"
CARDS = ROOT / "data" / "ships" / "cards.json"
STAGE_ID = re.compile(r"^challenge-[0-9]{2}$")
PROFILES = {"coord", "gunnery", "torpedo"}
SCHEMA = 2
VERSION = "cas-challenge-v2"
RULES_VERSION = "cas-realtime-v9"


class Invalid(Exception):
    pass


def load(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise Invalid(f"{path}: invalid UTF-8 JSON: {error}") from error


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--write", action="store_true", help="regenerate the TypeScript module")
    mode.add_argument("--check", action="store_true", help="verify the TypeScript module is current")
    args = parser.parse_args()

    try:
        raw = SOURCE.read_bytes()
        data = json.loads(raw.decode("utf-8"))
        points = load(POINTS)["ships"]
        cards = {row["identity"]: row for row in load(CARDS)["cards"]}
        digest = hashlib.sha256(raw).hexdigest()
        validate(data, points, cards)
        generated = ts_module(data, points, cards, digest)
    except Invalid as error:
        print(f"challenge stages invalid: {error}", file=sys.stderr)
        return 1

    current = TARGET.read_text(encoding="utf-8") if TARGET.exists() else None
    if args.write:
        TARGET.parent.mkdir(parents=True, exist_ok=True)
        if current != generated:
            TARGET.write_text(generated, encoding="utf-8", newline="\n")
        print(f"wrote {TARGET.relative_to(ROOT)} (source sha256 {digest})")
        return 0
    if current != generated:
        print(
            f"{TARGET.relative_to(ROOT)} is stale; run `python scripts/challenge-stages.py --write`",
            file=sys.stderr,
        )
        return 1
    playable = sum(stage["status"] == "playable" for stage in data["stages"])
    print(f"challenge stages ok: {playable} playable, {len(data['stages'])} total (source sha256 {digest})")
    return 0


def total(fleet: dict, points: dict, cards: dict) -> int:
    return sum(points.get(identity, {}).get("points", -10**9) for identity in fleet["ships"])


def validate(data: dict, points: dict, cards: dict) -> None:
    if data.get("schema_version") != SCHEMA:
        raise Invalid(f"schema_version must be {SCHEMA}")
    if data.get("version") != VERSION:
        raise Invalid(f"version must be {VERSION}")
    if data.get("kind") != "fictional":
        raise Invalid("challenge data must be declared fictional")
    if not str(data.get("source", "")).strip():
        raise Invalid("source is required")
    engine = data.get("engine")
    if not isinstance(engine, dict) or engine.get("variant") != "challenge":
        raise Invalid("engine.variant must be challenge")
    if engine.get("rules_version") != RULES_VERSION:
        raise Invalid(f"engine.rules_version must stay frozen at {RULES_VERSION}")
    if not isinstance(engine.get("notes"), list) or not engine["notes"]:
        raise Invalid("engine.notes is required")
    field = engine.get("field")
    if not isinstance(field, dict) or not all(isinstance(field.get(k), (int, float)) for k in ("width", "height", "limit")):
        raise Invalid("engine.field is required")
    rewards = data.get("rewards")
    if not isinstance(rewards, dict) or not all(isinstance(rewards.get(k), str) for k in ("first_clear", "repeat", "basis")):
        raise Invalid("rewards policy is required")

    stages = data.get("stages")
    if not isinstance(stages, list) or len(stages) != 5:
        raise Invalid("the ladder must hold exactly five stages")
    previous: str | None = None
    for position, stage in enumerate(stages, start=1):
        if not isinstance(stage, dict):
            raise Invalid(f"stage #{position} must be an object")
        stage_id = stage.get("id")
        if not isinstance(stage_id, str) or not STAGE_ID.match(stage_id) or stage_id != f"challenge-{position:02d}":
            raise Invalid(f"stage #{position} has invalid id {stage_id!r}")
        if stage.get("order") != position:
            raise Invalid(f"{stage_id}: order must be the contiguous position {position}")
        for key in ("name", "tier", "brief", "objective", "source"):
            if not isinstance(stage.get(key), str) or not stage[key].strip():
                raise Invalid(f"{stage_id}: missing non-empty {key}")
        if stage.get("status") != "playable":
            raise Invalid(f"{stage_id}: the five staged rosters are wired; no blocked row")
        if stage.get("unlock_after") != previous:
            raise Invalid(f"{stage_id}: unlock_after must be {previous!r}")
        if stage.get("profile") not in PROFILES or stage.get("enemy_profile") not in PROFILES:
            raise Invalid(f"{stage_id}: profile must be coord/gunnery/torpedo")
        if not isinstance(stage.get("budget"), int) or stage["budget"] <= 0:
            raise Invalid(f"{stage_id}: budget must be a positive integer")
        if not isinstance(stage.get("seed"), int):
            raise Invalid(f"{stage_id}: seed must be an integer")
        if not isinstance(stage.get("spacing"), (int, float)) or stage["spacing"] <= 0:
            raise Invalid(f"{stage_id}: spacing must be positive")
        stage_field = stage.get("field")
        if not isinstance(stage_field, dict) or not all(isinstance(stage_field.get(k), (int, float)) for k in ("width", "height", "limit")):
            raise Invalid(f"{stage_id}: field is required")
        if not 1800 <= stage_field["limit"] <= 5400:
            raise Invalid(f"{stage_id}: limit must be 30-90 minutes")
        required = stage.get("required_enemy_losses")
        if not isinstance(required, int) or required <= 0:
            raise Invalid(f"{stage_id}: required_enemy_losses must be positive")

        for role in ("player", "enemy"):
            sides = stage.get(role)
            if not isinstance(sides, dict) or set(sides) != {"allies", "axis"}:
                raise Invalid(f"{stage_id}: {role} must define allies and axis")
            for side, fleet in sides.items():
                label = f"{stage_id}/{role}.{side}"
                if not isinstance(fleet, dict):
                    raise Invalid(f"{label}: must be an object")
                if not isinstance(fleet.get("name"), str) or not fleet["name"].strip():
                    raise Invalid(f"{label}: name is required")
                ships = fleet.get("ships")
                kinds = fleet.get("kinds")
                if not isinstance(ships, list) or not 1 <= len(ships) <= 8 or not all(isinstance(v, str) for v in ships):
                    raise Invalid(f"{label}: ships must be 1..8 identities")
                if len(set(ships)) != len(ships):
                    raise Invalid(f"{label}: duplicate identity")
                if not isinstance(kinds, list) or len(kinds) != len(ships):
                    raise Invalid(f"{label}: kinds must align with ships")
                for identity, kind in zip(ships, kinds):
                    if identity not in cards:
                        raise Invalid(f"{label}: {identity} is not a registered identity")
                    if identity not in points:
                        raise Invalid(f"{label}: {identity} has no frozen point row")
                    if cards[identity].get("type") != kind:
                        raise Invalid(
                            f"{label}: {identity} kind {cards[identity].get('type')} != declared {kind}"
                        )
                    if kind not in {"DD", "CL", "CA", "CB", "BC", "BB", "AV"}:
                        raise Invalid(f"{label}: {identity} has unsupported type {kind}")
                expected = total(fleet, points, cards)
                if fleet.get("points") != expected:
                    raise Invalid(f"{label}: declared points {fleet.get('points')} != {expected}")
                leader = fleet.get("leader_slot")
                if not isinstance(leader, int) or not 0 <= leader < len(ships):
                    raise Invalid(f"{label}: leader_slot out of range")
                if not isinstance(fleet.get("speed"), (int, float)) or not 1 <= fleet["speed"] <= 40:
                    raise Invalid(f"{label}: speed out of range")
                for key in ("x", "y", "heading"):
                    if not isinstance(fleet.get(key), (int, float)) or not math.isfinite(fleet[key]):
                        raise Invalid(f"{label}: {key} is required")
                width, height = stage_field["width"], stage_field["height"]
                for index in range(len(ships)):
                    dx = math.cos(math.radians(fleet["heading"])) * stage["spacing"] * index
                    dy = math.sin(math.radians(fleet["heading"])) * stage["spacing"] * index
                    x, y = fleet["x"] - dx, fleet["y"] - dy
                    if not (50 <= x <= width - 50 and 50 <= y <= height - 50):
                        raise Invalid(f"{label}: ship {index + 1} starts outside the chart")

        for side in ("allies", "axis"):
            player = stage["player"][side]
            if player["points"] > stage["budget"]:
                raise Invalid(f"{stage_id}: {side} player fleet exceeds the {stage['budget']} budget")
            enemy = stage["enemy"]["axis" if side == "allies" else "allies"]
            if required > len(enemy["ships"]):
                raise Invalid(f"{stage_id}: enemy loss target exceeds the fleet")

        light = lambda fleet: all(kind in {"DD", "CL"} for kind in fleet["kinds"])
        heavy = lambda fleet: any(kind in {"BB", "BC"} for kind in fleet["kinds"])
        if position <= 3:
            for role in ("player", "enemy"):
                for side in ("allies", "axis"):
                    if not light(stage[role][side]):
                        raise Invalid(f"{stage_id}: the first three stages may only field DD/CL")
            if stage_field["width"] > 24000 or stage_field["height"] > 14000:
                raise Invalid(f"{stage_id}: light stages keep the 24,000x14,000 chart")
        else:
            for role in ("player", "enemy"):
                for side in ("allies", "axis"):
                    fleet = stage[role][side]
                    if not heavy(fleet):
                        raise Invalid(f"{stage_id}: {role}.{side} must include a battleship")
                    capitals = sum(kind in {"BB", "BC"} for kind in fleet["kinds"])
                    if not 1 <= capitals <= 2:
                        raise Invalid(f"{stage_id}: {role}.{side} capital slots must be 1..2")
                    if fleet["kinds"].count("DD") > 4:
                        raise Invalid(f"{stage_id}: {role}.{side} destroyer slots must be <= 4")
            if stage_field["width"] < 48000 or stage_field["height"] < 28000:
                raise Invalid(f"{stage_id}: capital stages need a larger chart")
        if position == 1 and (stage["player"]["allies"]["points"] != 1875 or len(stage["player"]["allies"]["ships"]) != 3):
            raise Invalid("stage 1 must keep the accepted 3-ship 1875-point force")

        evidence = stage.get("evidence")
        if not isinstance(evidence, dict):
            raise Invalid(f"{stage_id}: evidence record is required")
        if evidence.get("seed") != stage["seed"] or evidence.get("enemy_profile") != stage["enemy_profile"]:
            raise Invalid(f"{stage_id}: evidence seed/AI must match the stage")
        result = evidence.get("result")
        if not isinstance(result, dict) or result.get("primary") is not True:
            raise Invalid(f"{stage_id}: evidence must record a primary-objective win")
        if not isinstance(result.get("allies"), int) or result["allies"] < required:
            raise Invalid(f"{stage_id}: evidence must sink at least {required} enemy ships")
        if not isinstance(result.get("axis"), int) or not 0 <= result["axis"] < len(stage["player"]["allies"]["ships"]):
            raise Invalid(f"{stage_id}: evidence must record a surviving own ship")
        previous = stage_id


def ts_module(data: dict, points: dict, cards: dict, digest: str) -> str:
    header = (
        "// Generated by scripts/challenge-stages.py from data/challenge/stages.json.\n"
        "// Do not edit by hand; run `python scripts/challenge-stages.py --write`.\n"
        f"// source sha256: {digest}\n\n"
    )
    types = """export type ChallengeStatus = 'playable' | 'blocked';
export type ChallengeProfile = 'coord' | 'gunnery' | 'torpedo';

export interface ChallengeField {
  readonly width: number;
  readonly height: number;
  readonly limit: number;
}

export interface ChallengeFleet {
  readonly name: string;
  readonly ships: readonly string[];
  readonly kinds: readonly string[];
  readonly points: number;
  readonly leader_slot: number;
  readonly x: number;
  readonly y: number;
  readonly heading: number;
  readonly speed: number;
}

export interface ChallengeSideFleets {
  readonly allies: ChallengeFleet;
  readonly axis: ChallengeFleet;
}

export interface ChallengeReward {
  readonly first_clear: string;
  readonly repeat: string;
  readonly basis: string;
}

export interface ChallengeEvidence {
  readonly seed: number;
  readonly enemy_profile: string;
  readonly result: { readonly allies: number; readonly axis: number; readonly primary: boolean };
  readonly note: string;
}

export interface ChallengeStage {
  readonly id: string;
  readonly order: number;
  readonly name: string;
  readonly tier: string;
  readonly status: ChallengeStatus;
  readonly brief: string;
  readonly objective: string;
  readonly unlock_after: string | null;
  readonly source: string;
  readonly profile: ChallengeProfile;
  readonly seed: number;
  readonly enemy_profile: ChallengeProfile;
  readonly budget: number;
  readonly required_enemy_losses: number;
  readonly spacing: number;
  readonly field: ChallengeField;
  readonly player: ChallengeSideFleets;
  readonly enemy: ChallengeSideFleets;
  readonly reward: ChallengeReward;
  readonly evidence: ChallengeEvidence;
  readonly blocker?: string;
  readonly required_engine?: readonly string[];
}
"""
    referenced = sorted({identity for stage in data["stages"]
                         for role in ("player", "enemy")
                         for side in ("allies", "axis")
                         for identity in stage[role][side]["ships"]})
    names = {identity: cards[identity]["name"] for identity in referenced}
    engine = data["engine"]
    stages = data["stages"]
    return (
        header
        + types
        + "\nexport const challengeVersion = "
        + json.dumps(data["version"], ensure_ascii=False)
        + ";\n"
        + "export const challengeKind = "
        + json.dumps(data["kind"], ensure_ascii=False)
        + ";\n\n"
        + "export const challengeEngine = "
        + json.dumps(engine, ensure_ascii=False, indent=2)
        + " as const;\n\n"
        + "export const challengeRewards = "
        + json.dumps(data["rewards"], ensure_ascii=False, indent=2)
        + " as const;\n\n"
        + "export const challengeShipNames: Readonly<Record<string, string>> = "
        + json.dumps(names, ensure_ascii=False, indent=2)
        + ";\n\n"
        + "export const challengeStages: readonly ChallengeStage[] = "
        + json.dumps(stages, ensure_ascii=False, indent=2)
        + ";\n"
    )


if __name__ == "__main__":
    raise SystemExit(main())
