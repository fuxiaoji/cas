"""Authority for the existing seven-day CAS check-in and account summary."""
from __future__ import annotations

from contextlib import closing
from datetime import date, timedelta
import json
import time
from typing import TYPE_CHECKING

from fastapi import Depends, FastAPI

from .contracts import Mutation, deny

if TYPE_CHECKING:
    from .accounts import AccountService


CHECK_IN_VERSION = "rookie-check-in-v1"
DAY_MS = 86_400_000
BEIJING_OFFSET_MS = 28_800_000
UNIX_EPOCH = date(1970, 1, 1)
CHECK_IN_SHIP = "IBS-U-USN-UNNAMED-T01-R03"
SCHEDULE = (
    {"credits": 500, "standard_tickets": 2}, {"up_tickets": 2},
    {"credits": 800, "standard_tickets": 3}, {"up_tickets": 3},
    {"credits": 1200, "standard_tickets": 5}, {"up_tickets": 5},
    {"ship_ids": [CHECK_IN_SHIP]},
)
REWARDS = tuple({"id": f"{CHECK_IN_VERSION}:{day}", "title": f"新手七日签到 · 第 {day} 天", **reward}
                for day, reward in enumerate(SCHEDULE, start=1))


def check_in_status(state: dict, now: int, ship_ready: bool) -> dict:
    track = state.get("check_in", {})
    day_index = (now + BEIJING_OFFSET_MS) // DAY_MS
    day = (UNIX_EPOCH + timedelta(days=day_index)).isoformat()
    last_day = track.get("last_day")
    claimed = sum(reward["id"] in state["claims"] for reward in REWARDS)
    next_reward = next((reward for reward in REWARDS if reward["id"] not in state["claims"]), None)
    ship_pending = bool(next_reward and "ship_ids" in next_reward and not ship_ready)
    return {
        "version": CHECK_IN_VERSION, "day": day, "last_day": last_day, "claimed": claimed,
        "available": bool(next_reward and (last_day is None or day > last_day) and not ship_pending),
        "clock_behind": last_day is not None and day < last_day, "ship_pending": ship_pending,
        "refresh_at": (day_index + 1) * DAY_MS - BEIJING_OFFSET_MS,
        "next": next_reward, "rewards": REWARDS,
    }


class AccountProgression:
    def __init__(self, accounts: AccountService, clock_ms=None):
        self.accounts = accounts
        self.clock_ms = clock_ms or (lambda: time.time_ns() // 1_000_000)
        self.ship = next((ship for ship in accounts.catalog["ships"]
                          if ship["id"] == CHECK_IN_SHIP and ship["type"] == "BB" and ship.get("combat_ready") is True), None)

    def status(self, state, now):
        return check_in_status(state, now, self.ship is not None)

    def check_in(self, account_id):
        return self.status(self.accounts.meta(account_id), self.clock_ms())

    def claim(self, account_id, data):
        from .accounts import DUPLICATE_MEDALS, grant

        def claim(_conn, state):
            now = self.clock_ms()
            status = self.status(state, now)
            if not status["available"]:
                return {"claimed": False, "rewards": [], "check_in": status}
            reward = dict(status["next"])
            if reward.get("ship_ids") and self.ship["id"] in state["owned_ships"]:
                reward.pop("ship_ids")
                reward["medals"] = DUPLICATE_MEDALS[self.ship["rarity"]]
            if not grant(state, reward, now):
                deny("签到已入账，请刷新签到状态。", 409)
            state["check_in"] = {"last_day": status["day"], "last_claimed_at": now}
            return {"claimed": True, "rewards": [reward], "check_in": self.status(state, now)}

        return self.accounts.mutate(account_id, data.request_id, "check-in-claim", data.model_dump(), claim)

    def overview(self, account_id):
        from .accounts import STARTER_GIFTS

        with closing(self.accounts.connect()) as conn, conn:
            conn.execute("BEGIN")
            row = conn.execute("SELECT state FROM assets WHERE account_id=?", (account_id,)).fetchone()
            if row is None:
                deny("账号不存在。", 404)
            state = json.loads(row["state"])
            wins = conn.execute("SELECT COUNT(*) FROM pve_clears WHERE account_id=?", (account_id,)).fetchone()[0]
        return {
            "source": "cas-account-server",
            "collection": {"ship_count": len(state["owned_ships"]), "ai_profiles": state["ai_profiles"]},
            "campaign": {"stages": state.get("campaign_progress", {}), "primary_objective_wins": wins},
            "starter_gifts": {"claimed": [entry["id"] for entry in STARTER_GIFTS.values() if entry["id"] in state["claims"]],
                              "practice_verified": False},
            "check_in": self.status(state, self.clock_ms()),
        }


def mount(app: FastAPI, service: AccountProgression, account):
    @app.get("/missions/check-in")
    def check_in(account_id: str = Depends(account)):
        return service.check_in(account_id)

    @app.post("/missions/check-in/claim")
    def claim(data: Mutation, account_id: str = Depends(account)):
        return service.claim(account_id, data)

    @app.get("/progression")
    def progression(account_id: str = Depends(account)):
        return service.overview(account_id)
