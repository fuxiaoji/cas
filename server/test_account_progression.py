"""Seven-day schedule, account isolation, and calendar authority regression."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import ExitStack, closing
from datetime import datetime, timezone
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

    def new_app(self):
        return create_app(self.db, check_in_clock_ms=lambda: self.now)

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

    def test_pinned_six_grants_and_unverified_ship_remains_pending(self):
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
        self.assertEqual((pending["claimed"], pending["available"], pending["ship_pending"]), (6, False, True))
        self.assertEqual(pending["next"]["ship_ids"], [CHECK_IN_SHIP])
        seventh = self.claim("seventh-blocked")
        self.assertFalse(seventh["claimed"])
        self.assertEqual(seventh["rewards"], [])
        wallet = seventh["meta"]["wallet"]
        self.assertEqual((wallet["credits"], wallet["standard_tickets"], wallet["up_tickets"], wallet["medals"]), (2500, 10, 10, 0))
        self.assertNotIn(CHECK_IN_SHIP, seventh["meta"]["owned_ships"])
        with closing(self.app.state.accounts.connect()) as conn:
            self.assertEqual(conn.execute("SELECT COUNT(*) FROM ledger WHERE operation='check-in-claim'").fetchone()[0], 6)
            self.assertEqual(conn.execute("PRAGMA user_version").fetchone()[0], 2)
        with TestClient(self.new_app()) as restarted:
            self.assertEqual(self.good(restarted.get(PATH, headers=self.headers)), pending)

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
