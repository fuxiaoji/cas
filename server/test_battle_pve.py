"""Real native Cape battles against the HTTP contract, with server-side test time."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import ExitStack, closing
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from fastapi.testclient import TestClient

from .accounts import PROLOGUE_SHIPS, beijing_week, create_app
from .battle_pve import MAX_TICKS, SIM_TICK_MS


NATIVE = Path(os.environ.get("CAS_TEST_SIM_PATH", Path(__file__).resolve().parents[1] / "target" / "release"
                             / ("cas-sim.exe" if os.name == "nt" else "cas-sim")))
STAGE = "CAMP-ALLIES-03"
AXIS = "CAMP-AXIS-03"


@unittest.skipUnless(NATIVE.is_file(), "build the native cas-sim release binary first")
class AuthorityTest(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.db = Path(self.stack.enter_context(TemporaryDirectory())) / "cas.sqlite3"
        self.ms = beijing_week()["start"] + 86_400_000
        self.seed = 6107
        self.app = self.new_app()
        self.client = self.stack.enter_context(TestClient(self.app))
        self.headers = self.register("allied-tester")

    def new_app(self):
        return create_app(self.db, sim_path=NATIVE, clock_ms=lambda: self.ms, seed_source=lambda: self.seed)

    def good(self, response):
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def register(self, name):
        auth = self.good(self.client.post("/auth/register", json={"username": name, "password": "temporary-test-password"}))
        return {"Authorization": "Bearer " + auth["token"]}

    def get(self, path, headers=None):
        return self.client.get(path, headers=self.headers if headers is None else headers)

    def post(self, path, *, headers=None, **body):
        return self.client.post(path, headers=self.headers if headers is None else headers, json=body)

    def start(self, tag, stage=STAGE, difficulty="story"):
        return self.good(self.post("/battles", request_id=f"start-{tag}", stage_id=stage, difficulty=difficulty))

    def finish(self, path):
        for _ in range(48):
            self.ms += MAX_TICKS * SIM_TICK_MS
            snapshot = self.good(self.get(path))
            if snapshot["status"] == "complete":
                return snapshot
        self.fail("native session did not finish within the scenario's time limit")

    def ai(self, path, request_id, revision, fleet, profile):
        return self.post(path + "/commands", request_id=request_id, revision=revision,
                         command={"op": "ai", "fleet": fleet, "mode": "auto", "profile": profile,
                                  "move": True, "gun": True, "torpedo": True})

    def test_empress_stage_starts_and_completes_with_native_events(self):
        path = "/battles/" + self.start("empress", stage="CAMP-ALLIES-11")["battle_id"]
        for i in range(3):
            self.good(self.ai(path, f"empress-ai-{i}", i, i + 1, "coord"))
        end = self.finish(path)
        assert end["result"] is not None
        report = self.good(self.get(path + "/report"))
        assert report["events"]
        assert any(event["kind"] in ("gun", "torpedo", "secondary") for event in report["events"])

    def test_scope_clock_retries_and_restart(self):
        stranger = self.register("other-tester")
        self.assertTrue(self.good(self.client.get("/health"))["pve_available"])
        self.assertEqual(self.client.get("/battles").status_code, 401)
        self.assertEqual(self.post("/battles", request_id="forged-start", stage_id=STAGE, difficulty="story",
                                   seed=123, side="axis").status_code, 422)
        self.assertEqual(self.post("/battles", request_id="other-stage", stage_id="CAMP-ALLIES-01",
                                   difficulty="story").status_code, 422)
        battle = self.start("test-scope")
        self.assertEqual(self.start("test-scope"), battle)
        self.assertEqual(battle["view"]["side"], "allies")
        self.assertEqual((battle["tick"], len(battle["view"]["ships"]), battle["view"]["contacts"]), (0, 5, []))
        self.assertTrue({"seed", "snapshot", "save", "commands", "enemy"}.isdisjoint(battle["view"]))
        path = "/battles/" + battle["battle_id"]
        self.assertEqual(self.good(self.get("/battles", stranger)), [])
        for response in (self.get(path, stranger), self.get(path + "/report", stranger),
                         self.post(path + "/inspect", headers=stranger, command={"op": "suggest", "fleet": 1}),
                         self.post(path + "/claim", headers=stranger, request_id="claim-foreign"),
                         self.post(path + "/commands", headers=stranger, request_id="order-foreign", revision=0,
                                   command={"op": "preview_route", "fleet": 1}),
                         self.post(path + "/commands", headers=stranger, request_id="foreign-valid", revision=0,
                                   command={"op": "reform", "fleet": 1})):
            self.assertIn(response.status_code, (404, 422), response.text)
        self.assertEqual(self.get(path, stranger).status_code, 404)
        for op in ("save", "load", "replay", "step", "report", "new_campaign"):
            for route in ("commands", "inspect"):
                body = {"command": {"op": op, "seconds": 2000, "save": {}}}
                if route == "commands":
                    body.update({"request_id": f"forged-{op}", "revision": 0})
                self.assertEqual(self.post(path + "/" + route, **body).status_code, 422)
        self.assertEqual(self.post(path + "/claim", request_id="forged-claim", grade="decisive",
                                   credits=10000).status_code, 422)
        self.assertEqual(self.post(path + "/claim", request_id="claim-active").status_code, 409)
        self.assertEqual(self.post(path + "/inspect", command={"op": "suggest", "fleet": 1,
                                                               "apply": True}).status_code, 422)
        self.good(self.post(path + "/inspect", command={"op": "suggest", "fleet": 1}))
        self.good(self.post(path + "/inspect", command={"op": "preview_route", "fleet": 1, "mode": "follow",
                                                         "points": [{"x": 30000, "y": 20000}]}))
        self.assertEqual(self.ai(path, "locked-torpedo", 0, 1, "evo-torpedo").status_code, 403)
        order = self.good(self.ai(path, "valid-first-ai", 0, 1, "coord"))
        self.assertEqual(order["revision"], 1)
        self.assertEqual(order, self.good(self.ai(path, "valid-first-ai", 0, 1, "coord")))
        self.assertEqual(self.ai(path, "different-stale-ai", 0, 1, "coord").status_code, 409)
        self.ms += MAX_TICKS * SIM_TICK_MS + 2 * SIM_TICK_MS
        self.assertEqual(self.good(self.get(path))["tick"], MAX_TICKS)
        advanced = self.good(self.get(path))
        self.assertEqual(advanced["tick"], MAX_TICKS + 2)
        self.assertEqual(self.good(self.get(path)), advanced)
        with TestClient(self.new_app()) as restarted:
            self.assertEqual(self.good(restarted.get(path, headers=self.headers)), advanced)
        axis = self.start("axis-seat", AXIS, "standard")
        self.assertEqual((axis["view"]["side"], axis["view"]["campaign"]["stageId"]), ("axis", AXIS))
        self.assertEqual(len(axis["view"]["ships"]), 5)
        self.start("third-seat", AXIS, "challenge")
        self.start("fourth-seat", STAGE, "challenge")
        self.assertEqual(self.post("/battles", request_id="fifth-seat-start", stage_id=STAGE,
                                   difficulty="story").status_code, 409)

    def test_previous_cas_database_keeps_assets_and_token_during_schema_upgrade(self):
        granted = self.good(self.post("/starter-gifts/claim", request_id="schema-test-grant", course="bridge"))
        with self.app.state.accounts.write() as conn:
            conn.execute("DROP TABLE pve_battles")
            conn.execute("PRAGMA user_version=1")
        with TestClient(self.new_app()) as restarted:
            me = self.good(restarted.get("/me", headers=self.headers))
            self.assertEqual(me["meta"], granted["meta"])
            self.assertEqual(self.good(restarted.get("/battles", headers=self.headers)), [])
            with closing(restarted.app.state.accounts.connect()) as conn:
                self.assertEqual(conn.execute("PRAGMA user_version").fetchone()[0], 2)

    def test_real_victories_pay_fixed_rewards_once_and_weekly_clears(self):
        # The two fixtures reach different victory grades in both supported
        # native campaign versions. The server still pays from actual results.
        self.seed = 6102
        path = "/battles/" + self.start("real-tactical")["battle_id"]
        for i in range(2):
            self.good(self.ai(path, f"tactical-ai-{i}", i, i + 1, "coord"))
        tactical = self.finish(path)
        self.assertEqual(tactical["result"]["grade"], "tactical")
        report = self.good(self.get(path + "/report"))
        self.assertEqual(report["result"], tactical["result"])
        self.assertTrue(report["events"])
        with ThreadPoolExecutor(max_workers=5) as workers:
            claims = list(workers.map(lambda i: self.good(self.post(path + "/claim", request_id=f"tactical-claim-{i}")), range(5)))
        paid, = [claim for claim in claims if claim["claimed"]]
        self.assertEqual([reward["id"] for reward in paid["rewards"]], [STAGE + "-CLEAR", STAGE + "-STAR2"])
        self.assertEqual((paid["meta"]["wallet"]["credits"], paid["meta"]["wallet"]["standard_tickets"]), (600, 2))
        self.assertEqual(self.good(self.get("/missions/weekly-pve"))["count"], 1)

        self.good(self.post("/prologue/claim", request_id="unlock-prologue", leader_id=PROLOGUE_SHIPS[0]))
        self.good(self.post("/starter-gifts/claim", request_id="unlock-starter-bridge", course="bridge"))
        self.good(self.post("/starter-gifts/claim", request_id="unlock-starter-night", course="night"))
        # The six evolved doctrines replace the old mobile AI list in the
        # catalog. Buy the torpedo doctrine with recruit tickets after the
        # CAMP-ALLIES-03 clear above unlocked it.
        me = self.good(self.get("/me"))
        self.app.state.accounts.deliver_mail(
            me["account_id"], "pve-ai-tickets", title="测试征募券", body="CAS",
            attachments={"up_tickets": 0, "standard_tickets": 900})
        self.good(self.post("/mail/pve-ai-tickets/claim", request_id="pve-ai-ticket-claim"))
        self.good(self.post("/shop/purchase", request_id="unlock-torpedo", kind="ai", item_id="evo-torpedo",
                            currency="recruit_ticket"))
        # cas-realtime-v10 brings both sides into contact earlier and the
        # closed 8.3 criticals plus torpedo reloads moved the seed. With the
        # evolved torpedo doctrine the verified seed is 6150 (decisive in both
        # standard and challenge on CAMP-ALLIES-03).
        self.seed = 6150
        path = "/battles/" + self.start("real-decisive", difficulty="standard")["battle_id"]
        for i in range(2):
            self.good(self.ai(path, f"decisive-ai-{i}", i, i + 1, "evo-torpedo"))
        self.assertEqual(self.finish(path)["result"]["grade"], "decisive")
        before = self.good(self.get("/me"))["meta"]["wallet"]
        decisive = self.good(self.post(path + "/claim", request_id="claim-decisive-one"))
        after = decisive["meta"]["wallet"]
        self.assertEqual([reward["id"] for reward in decisive["rewards"]], [STAGE + "-STAR3"])
        self.assertEqual((after["credits"] - before["credits"], after["standard_tickets"] - before["standard_tickets"],
                          after["medals"] - before["medals"]), (0, 2, 10))
        self.assertEqual(decisive, self.good(self.post(path + "/claim", request_id="claim-decisive-one")))
        self.assertFalse(self.good(self.post(path + "/claim", request_id="claim-decisive-twice"))["claimed"])
        self.assertEqual(self.good(self.get("/missions/weekly-pve"))["count"], 2)
        weekly_path = "/missions/weekly-pve/claim"
        self.assertEqual(self.post(weekly_path, request_id="before-third-win").status_code, 403)

        path = "/battles/" + self.start("repeat-decisive", difficulty="challenge")["battle_id"]
        for i in range(2):
            self.good(self.ai(path, f"repeat-ai-{i}", i, i + 1, "evo-torpedo"))
        self.assertEqual(self.finish(path)["result"]["grade"], "decisive")
        self.assertFalse(self.good(self.post(path + "/claim", request_id="claim-third-stage"))["claimed"])
        mission = self.good(self.get("/missions/weekly-pve"))
        self.assertEqual((mission["count"], mission["eligible"]), (3, True))
        supply = self.good(self.post(weekly_path, request_id="claim-weekly-real"))
        self.assertTrue(supply["claimed"])
        self.assertFalse(self.good(self.post(weekly_path, request_id="claim-weekly-again"))["claimed"])
        growth = self.good(self.get("/progression"))["campaign"]
        self.assertEqual(growth["primary_objective_wins"], 3)
        self.assertEqual(growth["stages"][STAGE], {"best": {"story": 2, "standard": 3, "challenge": 3}, "claimed": 3})
        with closing(self.app.state.accounts.connect()) as conn:
            self.assertEqual(conn.execute("SELECT COUNT(*) FROM pve_clears").fetchone()[0], 3)
            self.assertEqual(conn.execute("SELECT COUNT(*) FROM ledger WHERE operation='battle-claim'").fetchone()[0], 2)
            self.assertEqual(conn.execute("SELECT COUNT(*) FROM ledger WHERE operation='weekly-pve-claim'").fetchone()[0], 1)
            self.assertEqual(conn.execute("PRAGMA user_version").fetchone()[0], 2)


if __name__ == "__main__":
    unittest.main()
