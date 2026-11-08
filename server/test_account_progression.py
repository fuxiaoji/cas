"""Seven-day schedule, account isolation, and calendar authority regression."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import ExitStack, closing
from datetime import datetime, timezone
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from fastapi.testclient import TestClient

from .accounts import create_app
from .account_progression import CHECK_IN_SHIP, DAY_MS

PATH = "/missions/check-in"
CLAIM = PATH + "/claim"


class AccountProgressionTest(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.db = Path(self.stack.enter_context(TemporaryDirectory())) / "accounts.sqlite3"
        self.now = int(datetime(2026, 11, 6, 15, 59, 59, tzinfo=timezone.utc).timestamp() * 1000)
        self.app = self.new_app()
        self.client = self.stack.enter_context(TestClient(self.app))
        self.headers = self.register("signed-tester")
        self.account_id = self.get("/me")["account_id"]

    def new_app(self, catalog_path=None):
        if catalog_path is None:
            return create_app(self.db, check_in_clock_ms=lambda: self.now)
        return create_app(self.db, catalog_path=catalog_path, check_in_clock_ms=lambda: self.now)

    def catalog_with_unverified_ship(self):
        """A catalog copy whose day-7 ship has no verified combat profile."""
        catalog = json.loads((Path(__file__).resolve().parent / "catalog.json").read_text(encoding="utf-8"))
        for ship in catalog["ships"]:
            if ship["id"] == CHECK_IN_SHIP:
                ship["combat_ready"] = False
                ship.pop("combat_source", None)
        path = Path(self.stack.enter_context(TemporaryDirectory())) / "catalog-unverified.json"
        path.write_text(json.dumps(catalog, ensure_ascii=False), encoding="utf-8")
        return path

    def good(self, response):
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def register(self, name):
        auth = self.good(self.client.post("/auth/register", json={"username": name, "password": "temporary-test-password"}))
        return {"Authorization": "Bearer " + auth["token"]}

    def get(self, path=PATH, headers=None):
        return self.good(self.client.get(path, headers=self.headers if headers is None else headers))

    def claim(self, tag, headers=None):
        return self.good(self.client.post(CLAIM, headers=self.headers if headers is None else headers,
                                          json={"request_id": "check-in-" + tag}))

    def test_seven_days_grant_the_verified_battleship_and_replay_stably(self):
        self.assertEqual(self.client.get(PATH).status_code, 401)
        self.assertEqual(self.client.get("/progression").status_code, 401)
        self.assertEqual(self.client.post(CLAIM, headers=self.headers, json={"request_id": "forged-claim",
                         "day": "2026-11-30", "standard_tickets": 99}).status_code, 422)
        original = self.get()
        self.assertEqual((original["day"], original["claimed"], original["available"]), ("2026-11-06", 0, True))
        self.assertEqual(original["refresh_at"], self.now + 1000)
        with ThreadPoolExecutor(max_workers=6) as pool:
            outcomes = list(pool.map(lambda i: self.claim(f"parallel-{i}"), range(6)))
        first, = [outcome for outcome in outcomes if outcome["claimed"]]
        self.assertEqual(first["check_in"]["claimed"], 1)
        self.assertEqual(first["meta"]["wallet"]["standard_tickets"], 2)
        self.assertFalse(self.claim("same-day-new-id")["claimed"])
        self.now += 1000  # Precisely Beijing midnight, not UTC midnight.
        self.assertEqual(self.get()["day"], "2026-11-07")
        self.assertTrue(self.claim("second-day")["claimed"])
        before_rollback = self.now
        self.now -= 1000
        self.assertTrue(self.get()["clock_behind"])
        self.assertFalse(self.claim("clock-rolled-back")["claimed"])
        self.now = before_rollback + 3 * DAY_MS  # A missed day does not reset or advance the track.
        self.assertEqual(self.get()["next"]["id"], "rookie-check-in-v1:3")
        for day in range(3, 7):
            latest = self.claim(f"day-{day}")
            self.assertTrue(latest["claimed"])
            self.assertEqual(latest["check_in"]["claimed"], day)
            self.now += DAY_MS
        self.assertEqual(self.claim("second-day")["check_in"]["claimed"], 2)  # Stable reply from the prior date.
        pending = self.get()
        self.assertEqual((pending["claimed"], pending["available"], pending["ship_pending"]), (6, True, False))
        self.assertEqual(pending["next"]["ship_ids"], [CHECK_IN_SHIP])
        self.assertIn("north-carolina", pending["next"]["ship_source"])
        # Day 7 now grants the verified North Carolina period card directly.
        seventh = self.claim("seventh-day")
        self.assertTrue(seventh["claimed"])
        reward = seventh["rewards"][0]
        self.assertEqual(reward["ship_ids"], [CHECK_IN_SHIP])
        self.assertIn("cas-prologue-runtime-v1#north-carolina", reward["ship_source"])
        self.assertIn(CHECK_IN_SHIP, seventh["meta"]["owned_ships"])
        self.assertEqual(seventh["check_in"]["claimed"], 7)
        self.assertFalse(seventh["check_in"]["ship_pending"])
        wallet = seventh["meta"]["wallet"]
        self.assertEqual((wallet["credits"], wallet["standard_tickets"], wallet["up_tickets"], wallet["medals"]), (2500, 10, 10, 0))
        with closing(self.app.state.accounts.connect()) as conn:
            self.assertEqual(conn.execute("SELECT COUNT(*) FROM ledger WHERE operation='check-in-claim'").fetchone()[0], 7)
            self.assertEqual(conn.execute("PRAGMA user_version").fetchone()[0], 2)
        self.assertEqual(self.claim("seventh-day"), seventh)  # Same request id replays the first receipt.
        self.assertFalse(self.claim("after-the-seventh")["claimed"])
        with TestClient(self.new_app()) as restarted:
            restored = self.good(restarted.get(PATH, headers=self.headers))
            self.assertEqual((restored["claimed"], restored["available"]), (7, False))
        self.assertIn(CHECK_IN_SHIP, self.get("/me")["meta"]["owned_ships"])

    def test_unverified_ship_keeps_day_seven_pending(self):
        self.app = self.new_app(self.catalog_with_unverified_ship())
        self.client = self.stack.enter_context(TestClient(self.app))
        self.headers = self.register("locked-tester")
        self.now += 1000
        for day in range(1, 7):
            latest = self.claim(f"locked-day-{day}")
            self.assertTrue(latest["claimed"])
            self.now += DAY_MS
        pending = self.get()
        self.assertEqual((pending["claimed"], pending["available"], pending["ship_pending"]), (6, False, True))
        self.assertEqual(pending["next"]["ship_ids"], [CHECK_IN_SHIP])
        blocked = self.claim("locked-seventh")
        self.assertFalse(blocked["claimed"])
        self.assertEqual(blocked["rewards"], [])
        self.assertNotIn(CHECK_IN_SHIP, blocked["meta"]["owned_ships"])
        with closing(self.app.state.accounts.connect()) as conn:
            self.assertEqual(conn.execute("SELECT COUNT(*) FROM ledger WHERE operation='check-in-claim'").fetchone()[0], 6)

    def test_already_owned_check_in_ship_converts_to_medals(self):
        self.now += 1000
        for day in range(1, 7):
            self.assertTrue(self.claim(f"dup-day-{day}")["claimed"])
            self.now += DAY_MS
        # Out-of-band grant: the seventh day must convert the duplicate instead
        # of duplicating the stable identity in the collection.
        with closing(self.app.state.accounts.connect()) as conn, conn:
            conn.execute("BEGIN IMMEDIATE")
            state = json.loads(conn.execute("SELECT state FROM assets WHERE account_id=?",
                                            (self.account_id,)).fetchone()["state"])
            state["owned_ships"].append(CHECK_IN_SHIP)
            conn.execute("UPDATE assets SET state=? WHERE account_id=?",
                         (json.dumps(state, ensure_ascii=False, sort_keys=True, separators=(",", ":")), self.account_id))
        seventh = self.claim("dup-seventh")
        self.assertTrue(seventh["claimed"])
        reward = seventh["rewards"][0]
        self.assertNotIn("ship_ids", reward)
        self.assertEqual(reward["medals"], 50)  # The North Carolina card is UR after the UP promotion.
        self.assertEqual(seventh["meta"]["owned_ships"].count(CHECK_IN_SHIP), 1)
        self.assertEqual(seventh["meta"]["wallet"]["medals"], 50)

    def test_summary_reads_only_the_authenticated_accounts_growth(self):
        other = self.register("separate-tester")
        self.claim("original-first")
        gifts = self.good(self.client.post("/starter-gifts/claim", headers=self.headers,
                                          json={"request_id": "starter-bridge", "course": "bridge"}))
        one = self.get("/progression")
        two = self.get("/progression", other)
        self.assertEqual(one["collection"]["ship_count"], len(gifts["meta"]["owned_ships"]))
        self.assertEqual(two["collection"]["ship_count"], 0)
        self.assertEqual(one["starter_gifts"], {"claimed": ["tutorial-bridge"], "practice_verified": False})
        self.assertEqual(two["starter_gifts"]["claimed"], [])
        self.assertEqual((one["check_in"]["claimed"], two["check_in"]["claimed"]), (1, 0))
        self.assertEqual(one["campaign"], {"stages": {}, "primary_objective_wins": 0})


if __name__ == "__main__":
    unittest.main()
