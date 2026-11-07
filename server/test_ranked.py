"""Point-table admission and the ranked settlement ladder, from the merged service."""
from collections import Counter
from contextlib import closing
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from .accounts import create_app
from .rankings import PointTable, START_RATING, rank_for
from .duels import DuelStore, MAX_TICKS, SIM_TICK_MS

import sqlite3

ROOT = Path(__file__).resolve().parents[1]
POINTS = ROOT / "data" / "rules" / "cas-competitive-points-v1.json"
CATALOG = ROOT / "server" / "catalog.json"
PROLOGUE_SHIPS = ["IBS-U-USN-FLETCHER", "IBS-U-USN-PERKINS", "IBS-U-USN-MAURY", "IBS-U-USN-DRAYTON", "IBS-U-USN-LAMSON"]
# The lawful 3000-point free escort preset: the three cheapest verified hulls.
FREE_FLEET = ["IBS-U-USN-FLETCHER", "IBS-U-USN-PERKINS", "IBS-U-USN-MAURY"]
NATIVE = None  # set from CAS_TEST_DUEL_SIM_PATH at import time below
import os
NATIVE = os.environ.get("CAS_TEST_DUEL_SIM_PATH")


def catalog():
    return json.loads(CATALOG.read_text(encoding="utf-8"))


class PointTableTest(unittest.TestCase):
    def setUp(self):
        self.points = PointTable(POINTS, catalog(), PROLOGUE_SHIPS)

    def meta(self, ships=None, ai="rc_coordinated"):
        lineup = FREE_FLEET if ships is None else ships
        return {"owned_ships": list(PROLOGUE_SHIPS if ships is None else ships),
                "ai_profiles": ["adaptive", ai],
                "fleets": [{"id": "fleet-free", "name": "序章演习队", "side": "allies", "budget": 3000,
                            "ship_ids": list(lineup),
                            "leader_id": lineup[0], "ai_profile": ai, "cost_version": None}]}

    def test_manifest_matches_the_frozen_table(self):
        self.assertEqual(self.points.version, "cas-points-surface-v1")
        self.assertEqual(self.points.rules_version, "cas-realtime-v10")
        self.assertEqual(self.points.budgets, (3000,))
        self.assertEqual(len(self.points.hulls), 10)
        self.assertTrue(set(PROLOGUE_SHIPS) <= set(self.points.hulls))
        self.assertEqual(set(self.points.probes), {3000})

    def test_free_starter_fleet_is_ranked_ready(self):
        snapshot = self.points.checked(self.meta(), 3000, "fleet-free")
        self.assertEqual(snapshot["cost"], 1875)
        with self.assertRaises(Exception):
            self.points.checked(self.meta(ships=list(PROLOGUE_SHIPS)), 3000, "fleet-free")
        self.assertEqual(snapshot["fleet"]["cost_version"], "cas-points-surface-v1")
        self.assertEqual(snapshot["fleet"]["ship_ids"][0], PROLOGUE_SHIPS[0])

    def test_gates(self):
        with self.assertRaises(Exception):
            self.points.checked(self.meta(), 10000, "fleet-free")
        with self.assertRaises(Exception):
            self.points.checked(self.meta(), 3000, "missing-fleet")
        wrong_side = self.meta(ships=["IBS-U-IJN-KAGERO", *PROLOGUE_SHIPS[1:]])
        with self.assertRaises(Exception):
            self.points.checked(wrong_side, 3000, "fleet-free")
        unowned = self.meta(ships=["IBS-U-USN-FLETCHER"])
        with self.assertRaises(Exception):
            self.points.checked(unowned, 3000, "fleet-free")
        with self.assertRaises(Exception):
            self.points.checked(self.meta(ai="balanced"), 3000, "fleet-free")
        not_unlocked = self.meta(ai="torpedo")
        not_unlocked["ai_profiles"] = ["adaptive"]
        with self.assertRaises(Exception):
            self.points.checked(not_unlocked, 3000, "fleet-free")


class SettlementTest(unittest.TestCase):
    def setUp(self):
        import sqlite3
        self.stack = TemporaryDirectory()
        self.addCleanup(self.stack.cleanup)
        self.db = Path(self.stack.name) / "ranked.sqlite3"
        with self.write() as db:
            for statement in ("CREATE TABLE ranked_settings(key TEXT PRIMARY KEY, value INTEGER NOT NULL)",
                              """CREATE TABLE ranked_ratings(account_id TEXT NOT NULL, budget INTEGER NOT NULL,
                                  season_id TEXT NOT NULL, rating INTEGER NOT NULL, games INTEGER NOT NULL,
                                  wins INTEGER NOT NULL, losses INTEGER NOT NULL, draws INTEGER NOT NULL,
                                  PRIMARY KEY(account_id,budget,season_id))""",
                              "CREATE TABLE ranked_outcomes(match_id TEXT PRIMARY KEY, result TEXT NOT NULL)"):
                db.execute(statement)
            db.execute("INSERT INTO ranked_settings VALUES('season_epoch', 1793923200000)")

    def write(self):
        connection = sqlite3.connect(self.db)
        connection.row_factory = sqlite3.Row
        self.addCleanup(connection.close)
        return connection

    def settle(self, winner, reason="battle"):
        from . import rankings
        with self.write() as db:
            return rankings.settle(db, "duel-x", {"allies": "acc-a", "axis": "acc-b"},
                                   {"budget": 3000, "season": rankings.season(db, 1_800_000_000_000)},
                                   winner, reason)

    def test_equal_ratings_settle_twelve_points(self):
        result = self.settle("allies")
        self.assertTrue(result["rated"])
        self.assertEqual(result["ratings"]["allies"]["after"], START_RATING + 12)
        self.assertEqual(result["ratings"]["axis"]["after"], START_RATING - 12)
        self.assertEqual(result["ratings"]["allies"]["rank"], "白银")
        self.assertEqual(result["ratings"]["axis"]["rank"], "青铜")

    def test_draw_counts_without_delta(self):
        result = self.settle("draw")
        self.assertEqual(result["ratings"]["allies"]["delta"], 0)
        self.assertEqual(result["ratings"]["axis"]["delta"], 0)
        with self.write() as db:
            row = db.execute("SELECT draws FROM ranked_ratings WHERE account_id='acc-a'").fetchone()
            self.assertEqual(row["draws"], 1)

    def test_voided_fault_never_rated(self):
        result = self.settle(None, "server_fault")
        self.assertFalse(result["rated"])
        self.assertEqual(result["ratings"]["allies"]["delta"], 0)
        with self.write() as db:
            self.assertIsNone(db.execute("SELECT * FROM ranked_ratings WHERE account_id='acc-a'").fetchone())

    def test_settlement_is_idempotent_per_match(self):
        first = self.settle("allies")
        replay = self.settle("allies")
        self.assertEqual(first, replay)
        with self.write() as db:
            row = db.execute("SELECT rating FROM ranked_ratings WHERE account_id='acc-a'").fetchone()
            self.assertEqual(row["rating"], START_RATING + 12)

    def test_rank_names(self):
        self.assertEqual(rank_for(1000), "白银")
        self.assertEqual(rank_for(2100), "元帅")
        self.assertEqual(rank_for(0), "青铜")


@unittest.skipUnless(NATIVE and Path(NATIVE).is_file(), "set CAS_TEST_DUEL_SIM_PATH to the native duel-enabled binary")
class RankedFlowTest(unittest.TestCase):
    def setUp(self):
        from fastapi.testclient import TestClient
        from contextlib import ExitStack
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.db = Path(self.stack.enter_context(TemporaryDirectory())) / "cas.sqlite3"
        self.store = DuelStore(self.db.with_name("cas-duels.sqlite3"))
        self.now = 1_800_000_000_000
        self.client = self.stack.enter_context(TestClient(self.app()))
        self.host = self.register("ranked-host")
        self.guest = self.register("ranked-guest")

    def app(self):
        return create_app(self.db, sim_path=NATIVE, enable_duels=True,
                          ranked_points_path=POINTS, clock_ms=lambda: self.now, seed_source=lambda: 6106)

    def good(self, result):
        self.assertEqual(result.status_code, 200, result.text)
        return result.json()

    def register(self, username):
        auth = self.good(self.client.post("/auth/register", json={"username": username, "password": "ranked-test-pass"}))
        return {"Authorization": "Bearer " + auth["token"]}

    def post(self, path, headers, tag, **body):
        return self.client.post(path, headers=headers, json={"request_id": tag, **body})

    def preset(self, headers, tag):
        self.good(self.post("/prologue/claim", headers, tag + "-gift", leader_id="IBS-U-USN-FLETCHER"))
        fleet = {"id": "fleet-3000", "name": "序章护航队", "side": "allies", "budget": 3000,
                 "ship_ids": FREE_FLEET, "leader_id": FREE_FLEET[0], "ai_profile": "rc_coordinated",
                 "cost_version": None}
        saved = self.good(self.post("/fleets", headers, tag + "-fleet", fleet=fleet))
        self.assertTrue(saved["validation"]["ranked_ready"], saved)
        self.assertEqual(saved["validation"]["cost"], 1875)
        return fleet

    def queue(self, headers, tag, fleet_id="fleet-3000"):
        return self.post("/pvp/ranked/queue", headers, tag, budget=3000, fleet_id=fleet_id)

    def test_health_and_ladders(self):
        health = self.good(self.client.get("/health"))
        self.assertTrue(health["ranked_pvp"] and health["fleet_point_table_available"])
        self.assertEqual(health["ranked_budgets"], [3000])
        status = self.good(self.get("/pvp/ranked/status", self.host))
        self.assertEqual(status["available_budgets"], [3000])
        self.assertEqual(status["point_table_version"], "cas-points-surface-v1")
        self.assertEqual([entry["budget"] for entry in status["ratings"]], [3000, 10000])
        self.assertTrue(all(entry["rating"] == START_RATING and entry["rank"] == "白银" for entry in status["ratings"]))

    def get(self, path, headers):
        return self.client.get(path, headers=headers)

    def test_queue_retry_is_idempotent_and_matching_settles(self):
        for headers in (self.host, self.guest):
            self.preset(headers, "host" if headers is self.host else "guest")
        first = self.good(self.queue(self.host, "host-queue"))
        self.assertEqual(first["status"], "queued")
        self.assertEqual(first["season_id"], "S0001")
        replay = self.good(self.queue(self.host, "host-queue"))
        self.assertEqual(replay, first)
        clash = self.post("/pvp/ranked/queue", self.host, "host-queue", budget=3000, fleet_id="other")
        self.assertEqual(clash.status_code, 409)
        matched = self.good(self.queue(self.guest, "guest-queue"))
        self.assertEqual(matched["status"], "matched")
        match = matched["match"]
        self.assertEqual(match["mode"], "ranked")
        self.assertEqual((match["budget"], match["season_id"], match["fleet_cost"]), (3000, "S0001", 1875))
        self.assertIsNone(self.good(self.get("/pvp/ranked/status", self.host))["queue"])
        path = "/pvp/matches/" + match["match_id"]
        # "coord" needs no unlock, so a frozen ranked AI style is reached directly.
        frozen = self.order(path, self.host, 0, "ranked-ai-frozen", op="ai", fleet=1,
                            profile="coord", mode="manual", move=True, gun=True, torpedo=True)
        self.assertEqual(frozen.status_code, 409, frozen.text)
        self.assertIn("冻结", frozen.json()["detail"])
        surrendered = self.good(self.post(path + "/surrender", self.guest, "guest-surrenders"))
        self.assertEqual(surrendered["end_reason"], "surrender")
        self.assertTrue(surrendered["rated"])
        self.assertEqual(surrendered["result"]["winner"], "allies")
        # The surrendering axis seat loses twelve points; the allies seat gains them.
        self.assertEqual(surrendered["rating"]["delta"], -12)
        late = self.good(self.get(path, self.host))
        self.assertEqual(late["rating"]["delta"], 12)
        status = self.good(self.get("/pvp/ranked/status", self.host))
        self.assertEqual((status["ratings"][0]["wins"], status["ratings"][0]["games"]), (1, 1))
        guest_status = self.good(self.get("/pvp/ranked/status", self.guest))
        self.assertEqual((guest_status["ratings"][0]["losses"], guest_status["ratings"][0]["rating"]),
                         (1, START_RATING - 12))

    def order(self, path, headers, revision, tag, **command):
        return self.post(path + "/commands", headers, tag, revision=revision, command=command)

    def test_ranked_mutual_fire_natural_end_and_settlement(self):
        from fastapi.testclient import TestClient
        for headers in (self.host, self.guest):
            self.preset(headers, "host" if headers is self.host else "guest")
        self.good(self.queue(self.host, "host-queue"))
        matched = self.good(self.queue(self.guest, "guest-queue"))
        self.assertEqual(matched["status"], "matched")
        path = "/pvp/matches/" + matched["match"]["match_id"]

        def seek(account, tick):
            current = self.good(self.get(path, account))
            self.now += (tick - current["tick"]) * SIM_TICK_MS
            while current["tick"] < tick and current["status"] == "active":
                current = self.good(self.get(path, account))
            return current

        # Both fleets steam toward each other; contacts appear within gun range.
        opening = self.good(self.get(path, self.host))
        guest_opening = self.good(self.get(path, self.guest))
        routed = self.order(path, self.host, opening["revision"], "ranked-route-host", op="route",
                            fleet=opening["view"]["fleets"][0]["id"], mode="follow", speed=30,
                            points=[{"x": 15000, "y": 6550}])
        self.assertEqual(routed.status_code, 200, routed.text)
        routed = self.order(path, self.guest, guest_opening["revision"], "ranked-route-guest", op="route",
                            fleet=guest_opening["view"]["fleets"][0]["id"], mode="follow", speed=30,
                            points=[{"x": 6000, "y": 7650}])
        self.assertEqual(routed.status_code, 200, routed.text)
        current = seek(self.host, 420)
        self.assertTrue(current["view"]["contacts"], "ranked fleets must make contact")

        # A fresh service process on the same store restores the same ranked battle.
        before = self.good(self.get(path, self.guest))
        with TestClient(self.app()) as restarted:
            after = self.good(self.get(path, self.guest))
            self.assertEqual((after["match_id"], after["tick"], after["mode"], after["budget"]),
                             (before["match_id"], before["tick"], before["mode"], before["budget"]))
            self.assertEqual(after["view"]["ships"], before["view"]["ships"])

        # Both seats shoot at their contacts every window until the battle ends.
        revisions = {"host": current["revision"], "guest": self.good(self.get(path, self.guest))["revision"]}
        shots = {"host": 0, "guest": 0}
        while current["status"] == "active":
            self.now += 30 * SIM_TICK_MS
            for seat, headers in (("host", self.host), ("guest", self.guest)):
                state = self.good(self.get(path, headers))
                if state["status"] != "active" or not state["view"]["contacts"]:
                    current = state
                    continue
                ships = [ship["id"] for ship in state["view"]["ships"]]
                for ship in ships:
                    fired = self.order(path, headers, revisions[seat], f"ranked-shot-{seat}-{ship}-{shots[seat]}",
                                       op="fire", ship=ship, weapon="gun", target=state["view"]["contacts"][0]["id"])
                    if fired.status_code == 200:
                        revisions[seat] += 1
                        shots[seat] += 1
                    else:
                        self.assertEqual(fired.status_code, 409, fired.text)
                current = self.good(self.get(path, headers))
        self.assertGreater(shots["host"], 0, "the allies seat must have fired")
        self.assertGreater(shots["guest"], 0, "the axis seat must have fired")
        self.assertEqual(current["end_reason"], "battle")

        # Both seats see one settlement with symmetric, rated deltas.
        finals = [self.good(self.get(path, headers)) for headers in (self.host, self.guest)]
        self.assertEqual([final["status"] for final in finals], ["complete", "complete"])
        self.assertTrue(finals[0]["rated"] and finals[1]["rated"])
        self.assertTrue(all(final["result"]["winner"] in ("allies", "axis", "draw") for final in finals))
        deltas = sorted((final["rating"]["delta"] for final in finals))
        self.assertEqual(deltas[0], -deltas[1])
        status = self.good(self.get("/pvp/ranked/status", self.host))
        ladder = status["ratings"][0]
        self.assertEqual(ladder["games"], 1)
        if finals[0]["result"]["winner"] == "draw":
            self.assertEqual((deltas[0], deltas[1]), (0, 0))
            self.assertEqual(ladder["draws"], 1)
        for seat, headers in (("host", self.host), ("guest", self.guest)):
            evidence = self.good(self.get(path + "/report", headers))
            events = Counter(event["kind"] for event in evidence["events"])
            self.assertGreater(events.get("gun", 0), 0, seat + " must report gun fire")
        self.assertEqual(self.good(self.post(path + "/surrender", self.host, "too-late-surrender"))["result"],
                         finals[0]["result"])
        with closing(self.store.connect()) as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM settlements").fetchone()[0], 1)

    def test_cancelled_queue_never_matches(self):
        self.preset(self.host, "host")
        self.preset(self.guest, "guest")
        self.good(self.queue(self.host, "host-queue"))
        self.assertTrue(self.good(self.post("/pvp/ranked/queue/cancel", self.host, "host-cancel"))["cancelled"])
        matched = self.good(self.queue(self.guest, "guest-queue"))
        self.assertEqual(matched["status"], "queued")


if __name__ == "__main__":
    unittest.main()
