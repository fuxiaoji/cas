"""CAS point-table admission and the two independent competitive rating ladders."""
from __future__ import annotations

from hashlib import sha256
from itertools import combinations
import json
from pathlib import Path
from typing import Annotated, Literal

from pydantic import Field

from .contracts import Mutation, StrictModel, deny, encode
from .fleets import FleetId, RANKED_BUDGETS, ranked_composition_errors


DAY_MS = 86_400_000
SEASON_DAYS = 42
SEASON_MS = SEASON_DAYS * DAY_MS
START_RATING = 1000
RATING_K = 24
RANKS = ((2100, "元帅"), (1800, "钻石"), (1500, "铂金"), (1200, "黄金"), (1000, "白银"))
STATS = ("rating", "games", "wins", "losses", "draws")
SUPPORTED_AI = {"adaptive", "rc_coordinated", "coord", "gunnery", "torpedo"}
Budget = Literal[3000, 10000]

SCHEMA = (
    "CREATE TABLE ranked_settings(key TEXT PRIMARY KEY, value INTEGER NOT NULL)",
    """CREATE TABLE ranked_queue(account_id TEXT PRIMARY KEY, budget INTEGER NOT NULL,
        season_id TEXT NOT NULL, points_sha TEXT NOT NULL, core_sha TEXT NOT NULL,
        queued_ms INTEGER NOT NULL, fleet TEXT NOT NULL)""",
    "CREATE INDEX ranked_queue_group ON ranked_queue(budget,season_id,points_sha,core_sha,queued_ms)",
    """CREATE TABLE ranked_ratings(account_id TEXT NOT NULL, budget INTEGER NOT NULL, season_id TEXT NOT NULL,
        rating INTEGER NOT NULL,games INTEGER NOT NULL,wins INTEGER NOT NULL,losses INTEGER NOT NULL,draws INTEGER NOT NULL,
        PRIMARY KEY(account_id,budget,season_id))""",
    """CREATE TABLE ranked_outcomes(match_id TEXT PRIMARY KEY REFERENCES matches(id), result TEXT NOT NULL)""",
)


class RankedQueue(Mutation):
    budget: Budget
    fleet_id: FleetId


class HullPrice(StrictModel):
    profile_id: str = Field(min_length=1, max_length=120)
    points: int = Field(gt=0, le=10_000)
    source: str = Field(min_length=1, max_length=700)


class PointsManifest(StrictModel):
    schema_version: Literal[1]
    version: Annotated[str, Field(pattern=r"^cas-[a-z0-9-]{3,90}$")]
    rules_version: Literal["cas-realtime-v10"]
    enabled_budgets: list[Budget] = Field(min_length=1, max_length=2)
    ships: dict[str, HullPrice] = Field(min_length=1, max_length=250)


class PointTable:
    def __init__(self, path: str | Path, catalog: dict, starter_ids: list[str]):
        data = Path(path).read_bytes()
        self.sha256 = sha256(data).hexdigest()
        self.manifest = PointsManifest.model_validate_json(data)
        self.version = self.manifest.version
        self.rules_version = self.manifest.rules_version
        self.budgets = tuple(sorted(set(self.manifest.enabled_budgets)))
        self.hulls = self.manifest.ships
        self.catalog = {ship["id"]: ship for ship in catalog["ships"]}
        if len(self.budgets) != len(self.manifest.enabled_budgets) or not self.hulls.keys() <= self.catalog.keys():
            raise ValueError("CAS ranked point table has duplicate budgets or unknown ship identities")

        self.probes = {}
        for budget in self.budgets:
            eligible = [ship_id for ship_id in (starter_ids if budget == 3000 else self.hulls) if ship_id in self.hulls]
            lineup = self._example(budget, eligible)
            if lineup is None:
                requirement = "a free starter escort fleet" if budget == 3000 else "a battleship and two same-side escorts"
                raise ValueError(f"CAS {budget} ranked point table needs {requirement} within budget")
            self.probes[budget] = self._snapshot({"id": "startup-probe", "name": "", "budget": budget,
                "ship_ids": lineup, "leader_id": lineup[0], "ai_profile": "rc_coordinated",
                "side": self.catalog[lineup[0]]["side"], "cost_version": None})

    def _example(self, budget, ids):
        # Three cheapest same-side ships of the relevant roles are enough to
        # determine whether the minimum lawful fleet can fit the budget.
        ordered = sorted(ids, key=lambda ship_id: self.hulls[ship_id].points)
        for side in ("allies", "axis"):
            eligible = [ship_id for ship_id in ordered if self.catalog[ship_id]["side"] == side]
            escorts = [ship_id for ship_id in eligible if self.catalog[ship_id]["type"] in ("DD", "CL", "CA")]
            if budget == 3000:
                dds = [ship_id for ship_id in escorts if self.catalog[ship_id]["type"] == "DD"]
                fleets = ([*pair, extra] for pair in combinations(dds[:3], 2) for extra in escorts[:3] if extra not in pair)
            else:
                bbs = [ship_id for ship_id in eligible if self.catalog[ship_id]["type"] == "BB"]
                fleets = ([bbs[0], *escorts[:2]],) if bbs and len(escorts) >= 2 else ()
            for fleet in fleets:
                if sum(self.hulls[ship_id].points for ship_id in fleet) <= budget:
                    return fleet
        return None

    def _snapshot(self, fleet):
        ordered = [fleet["leader_id"], *[ship_id for ship_id in fleet["ship_ids"] if ship_id != fleet["leader_id"]]]
        ships = [{"ship_id": ship_id, **self.hulls[ship_id].model_dump()} for ship_id in ordered]
        return {"fleet": {**fleet, "ship_ids": ordered, "cost_version": self.version}, "ships": ships,
                "cost": sum(ship["points"] for ship in ships)}

    def checked(self, meta, budget, fleet_id):
        if budget not in self.budgets:
            deny("该档位的 CAS 点表或实战尚未开放。", 409)
        fleet = next((entry for entry in meta["fleets"] if entry["id"] == fleet_id), None)
        if fleet is None:
            deny("本账号没有此编队预设。", 404)
        ids = fleet["ship_ids"]
        if fleet["budget"] != budget or not ids or len(set(ids)) != len(ids) or fleet["leader_id"] not in ids:
            deny("所选编队与排位档位或领舰条件不符。", 409)
        if not self.still_owned(meta, {"fleet": fleet}):
            deny("舰船或 AI 已不属于该账号。", 403)
        if fleet["ai_profile"] not in SUPPORTED_AI:
            deny("该 AI 指挥风格尚未接入 CAS 排位。", 409)
        if any(ship_id not in self.hulls or self.catalog[ship_id]["side"] != fleet["side"] for ship_id in ids):
            deny("舰队含尚未通过个人出战核验的舰船。", 409)
        errors = ranked_composition_errors(budget, [self.catalog[ship_id]["type"] for ship_id in ids])
        if errors:
            deny("。".join(errors) + "。", 409)
        snapshot = self._snapshot(fleet)
        if snapshot["cost"] > budget:
            deny(f"本编队按 CAS 点表为 {snapshot['cost']} 分，超过 {budget} 分上限。", 409)
        return snapshot

    @staticmethod
    def still_owned(meta, snapshot):
        fleet = snapshot["fleet"]
        return set(fleet["ship_ids"]).issubset(meta["owned_ships"]) and fleet["ai_profile"] in meta["ai_profiles"]


def initialize(db, now):
    epoch = now // DAY_MS * DAY_MS
    db.execute("INSERT OR IGNORE INTO ranked_settings VALUES('season_epoch',?)", (epoch,))


def season(db, now, season_id=None):
    epoch = db.execute("SELECT value FROM ranked_settings WHERE key='season_epoch'").fetchone()[0]
    index = int(season_id[1:]) - 1 if season_id is not None else max(0, (now - epoch) // SEASON_MS)
    start = epoch + index * SEASON_MS
    return {"id": f"S{index + 1:04d}", "start": start, "end": start + SEASON_MS, "duration_days": SEASON_DAYS}


def rank_for(rating):
    return next((name for minimum, name in RANKS if rating >= minimum), "青铜")


def rating(db, account, budget, season_id):
    row = db.execute("""SELECT rating,games,wins,losses,draws FROM ranked_ratings
        WHERE account_id=? AND budget=? AND season_id=?""", (account, budget, season_id)).fetchone()
    return dict(row) if row else {"rating": START_RATING, "games": 0, "wins": 0, "losses": 0, "draws": 0}


def ladders(db, account, current_season):
    ratings = []
    for budget in RANKED_BUDGETS:
        row = rating(db, account, budget, current_season["id"])
        ratings.append({**row, "budget": budget, "season_id": current_season["id"], "rank": rank_for(row["rating"])})
    history = db.execute("""SELECT budget,season_id,rating,games,wins,losses,draws FROM ranked_ratings
        WHERE account_id=? AND season_id<>? ORDER BY LENGTH(season_id) DESC,season_id DESC,budget LIMIT 100""",
        (account, current_season["id"]))
    return {"season": current_season, "ratings": ratings,
            "historical_ratings": [{**row, "rank": rank_for(row["rating"]), "ended": True} for row in history]}


def settle(db, match_id, accounts, context, winner, reason):
    prior = db.execute("SELECT result FROM ranked_outcomes WHERE match_id=?", (match_id,)).fetchone()
    if prior:
        return json.loads(prior["result"])
    budget, season_id = context["budget"], context["season"]["id"]
    rated = reason in ("battle", "surrender")
    if rated and winner not in ("allies", "axis", "draw"):
        raise ValueError("Rated CAS match must have a verified winner or draw")
    seats = ("allies", "axis")
    stats = {seat: rating(db, accounts[seat], budget, season_id) for seat in seats}
    before = {seat: stats[seat]["rating"] for seat in seats}
    actual = {"allies": 1, "axis": 0, "draw": .5}.get(winner, .5)
    # The clamp avoids exponent overflow for unbounded ratings without altering
    # any Elo rounding result at the original K=24.
    difference = max(-20, min(20, (before["axis"] - before["allies"]) / 400))
    expected = 1 / (1 + 10 ** difference)
    delta = round(RATING_K * (actual - expected)) if rated else 0
    for index, seat in enumerate(seats):
        if not rated:
            continue
        row = stats[seat]
        row["rating"] += delta if index == 0 else -delta
        row["games"] += 1
        row["draws" if winner == "draw" else "wins" if winner == seat else "losses"] += 1
        db.execute("INSERT OR REPLACE INTO ranked_ratings VALUES(?,?,?,?,?,?,?,?)",
                   (accounts[seat], budget, season_id, *(row[key] for key in STATS)))
    result = {"match_id": match_id, "budget": budget, "season_id": season_id, "rated": rated,
              "winner_side": winner if winner in seats else None, "reason": reason,
              "ratings": {seat: {"before": before[seat], "after": stats[seat]["rating"],
                                 "delta": stats[seat]["rating"] - before[seat],
                                 "rank": rank_for(stats[seat]["rating"])} for seat in seats}}
    db.execute("INSERT INTO ranked_outcomes VALUES(?,?)", (match_id, encode(result)))
    return result
