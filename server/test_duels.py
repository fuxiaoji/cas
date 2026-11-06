"""Exercise two authenticated seats against one real native CAS world."""
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from contextlib import ExitStack, closing
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from fastapi.testclient import TestClient

from .accounts import create_app
from .duels import DuelStore, MAX_TICKS, SIM_TICK_MS, WAIT_MS


NATIVE = os.environ.get("CAS_TEST_DUEL_SIM_PATH")


@unittest.skipUnless(NATIVE and Path(NATIVE).is_file(), "set CAS_TEST_DUEL_SIM_PATH to the native duel-enabled binary")
class DuelTest(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.db = Path(self.stack.enter_context(TemporaryDirectory())) / "cas.sqlite3"
        self.store = DuelStore(self.db.with_name("cas-duels.sqlite3"))
        self.now = 1_800_000_000_000
        self.client = self.stack.enter_context(TestClient(self.app()))
        self.host = self.register("duel-host")
        self.guest = self.register("duel-guest")
        self.other = self.register("duel-outsider")

    def app(self):
        return create_app(self.db, sim_path=NATIVE, enable_duels=True, clock_ms=lambda: self.now, seed_source=lambda: 6107)

    def good(self, result):
        self.assertEqual(result.status_code, 200, result.text)
        return result.json()

    def register(self, username):
        auth = self.good(self.client.post("/auth/register", json={"username": username, "password": "duel-test-password"}))
        return {"Authorization": "Bearer " + auth["token"]}

    def post(self, path, headers, tag, **body):
        return self.client.post(path, headers=headers, json={"request_id": tag, **body})

    def get(self, path, headers):
        return self.client.get(path, headers=headers)

    def invite(self):
        return self.good(self.post("/pvp/invites", self.host, "host-invites"))["code"]

    def match(self, code):
        joined = self.good(self.post(f"/pvp/invites/{code}/join", self.guest, "guest-accepts"))
        return "/pvp/matches/" + joined["match_id"], joined

    def order(self, path, account, revision, tag, **command):
        return self.post(path + "/commands", account, tag, revision=revision, command=command)

    def seek(self, path, tick):
        current = self.good(self.get(path, self.host))
        self.now += (tick - current["tick"]) * SIM_TICK_MS
        while current["tick"] < tick and current["status"] != "complete":
            last = current["tick"]
            current = self.good(self.get(path, self.host))
            self.assertGreater(current["tick"], last)
            self.assertLessEqual(current["tick"] - last, MAX_TICKS)
        return current

    def test_shared_battle_real_fire_torpedoes_and_atomic_end(self):
        code = self.invite()
        self.assertEqual(self.invite(), code)
        self.assertEqual(self.post(f"/pvp/invites/{code}/join", self.host, "host-self-join").status_code, 409)
        path, axis = self.match(code)
        self.assertEqual(self.match(code)[1], axis)
        self.assertEqual(self.post(f"/pvp/invites/{code}/join", self.other, "used-invite").status_code, 404)
        self.assertEqual(self.client.get(path).status_code, 401)
        for suffix in ("", "/report"):
            self.assertEqual(self.get(path + suffix, self.other).status_code, 404)
        self.assertEqual(self.post(path + "/surrender", self.other, "foreign-surrender").status_code, 404)
        self.assertEqual(self.order(path, self.other, 0, "foreign-command", op="reform", fleet=1).status_code, 404)
        self.assertEqual(self.client.post(path + "/inspect", headers=self.other, json={"command":{"op":"suggest","fleet":1}}).status_code, 404)
        allies = self.good(self.get(path, self.host))
        self.assertEqual((allies["seat"], axis["seat"], allies["tick"], axis["tick"]), ("allies", "axis", 0, 0))
        self.assertEqual([ship["id"] for ship in allies["view"]["ships"]], [1,2,3,4,5])
        self.assertEqual([ship["id"] for ship in axis["view"]["ships"]], [6,7,8,9,10])
        for view in (allies, axis):
            self.assertTrue({"seed", "snapshot", "commands", "reports", "views"}.isdisjoint(view))
            self.assertTrue(all(fleet["ai"]["mode"] == "manual" for fleet in view["view"]["fleets"]))
            self.assertTrue(all("ship" not in contact and not contact["name"] for contact in view["view"]["contacts"]))
        self.assertEqual(self.order(path, self.host, 0, "enemy-fleet", op="reform", fleet=2).status_code, 409)
        self.assertEqual(self.order(path, self.guest, 0, "enemy-fletcher", op="fire", ship=1,
                                    weapon="gun", target="C01").status_code, 409)
        self.assertEqual(self.order(path, self.host, 0, "forged-pvp-step", op="match_step", seconds=1000).status_code, 422)
        self.assertEqual(self.post(path + "/commands", self.host, "forged-pvp-seat", revision=0, seat="axis",
                                   command={"op":"reform","fleet":1}).status_code, 422)
        self.assertEqual(self.order(path, self.host, 0, "forged-auto-ai", op="ai", fleet=1, profile="coord", mode="auto",
                                    move=True, gun=True, torpedo=True).status_code, 409)
        self.assertEqual(self.client.post(path + "/inspect", headers=self.host,
                                         json={"command":{"op":"suggest","fleet":1,"apply":True}}).status_code, 422)
        self.good(self.client.post(path + "/inspect", headers=self.host, json={"command":{"op":"suggest","fleet":1}}))
        self.assertEqual(self.client.post(path + "/inspect", headers=self.host,
                                         json={"command":{"op":"suggest","fleet":2}}).status_code, 409)

        def route(values):
            account, fleet, x, y = values
            return self.good(self.order(path, account, 0, "set-duel-route", op="route", fleet=fleet, mode="follow",
                                        speed=26, points=[{"x": x, "y": y}]))

        with ThreadPoolExecutor(max_workers=2) as workers:
            moved = list(workers.map(route, ((self.host, 1, 16000, 6550), (self.guest, 2, 8000, 7650))))
        self.assertEqual([(m["tick"], m["revision"]) for m in moved], [(0, 1), (0, 1)])
        self.assertEqual(route((self.host, 1, 16000, 6550)), moved[0])
        self.assertEqual(self.order(path, self.host, 0, "stale-own-revision", op="reform", fleet=1).status_code, 409)
        for account in (self.host, self.guest):
            evidence = self.good(self.get(path + "/report", account))
            self.assertEqual(sum(event["kind"] == "route" for event in evidence["events"]), 1)

        # The same world continues from disk after process restart, preserving each seat's order.
        self.seek(path, 540)
        before = self.good(self.get(path, self.guest))
        with TestClient(self.app()) as restarted:
            self.assertEqual(self.good(restarted.get(path, headers=self.guest)), before)
        revisions = [1, 1]
        for tick in (540, 600, 660, 720, 780, 840, 900, 960, 1020):
            self.seek(path, tick)
            for i in range(1, 6):
                for index, account in enumerate((self.host, self.guest)):
                    ship = i + index * 5
                    for weapon in (("gun", "torpedo") if tick in (600, 720, 840) else ("gun",)):
                        fired = self.order(path, account, revisions[index], f"shot-{tick}-{ship}-{weapon}",
                                           op="fire", ship=ship, weapon=weapon, target="C01")
                        if fired.status_code == 200:
                            revisions[index] += 1
                        else:
                            self.assertEqual(fired.status_code, 409, fired.text)
        self.seek(path, 2640)
        self.now += 120 * SIM_TICK_MS
        with ThreadPoolExecutor(max_workers=2) as workers:
            finals = list(workers.map(lambda account: self.good(self.get(path, account)), (self.host, self.guest)))
        result = {"winner": "allies", "allies": 2, "axis": 1}
        self.assertEqual([(final["status"], final["result"], final["end_reason"]) for final in finals],
                         [("complete", result, "battle")] * 2)
        for account in (self.host, self.guest):
            evidence = self.good(self.get(path + "/report", account))
            events = Counter(event["kind"] for event in evidence["events"])
            self.assertEqual(evidence["result"], result)
            self.assertTrue(all(events[key] > 0 for key in ("gun", "hit", "torpedo", "torpedo_hit")), events)
            self.assertEqual(self.good(self.get("/me", account))["meta"]["wallet"]["credits"], 0)
            self.assertEqual(self.good(self.get("/missions/weekly-pve", account))["count"], 0)
        self.assertEqual(self.good(self.post(path + "/surrender", self.host, "too-late-surrender"))["result"], result)
        with closing(self.store.connect()) as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM settlements").fetchone()[0], 1)

    def test_queue_expiry_cancel_surrender_and_gates(self):
        health = self.good(self.client.get("/health"))
        self.assertTrue(health["pvp_available"])
        self.assertFalse(health["ranked_pvp"])
        self.assertEqual(self.post("/pvp/queue", self.host, "spoof-ranked-queue", budget=3000).status_code, 422)
        code = self.invite()
        self.assertEqual(self.post(f"/pvp/invites/{code}/cancel", self.guest, "foreign-cancel").status_code, 404)
        self.now += WAIT_MS
        self.assertEqual(self.post(f"/pvp/invites/{code}/join", self.guest, "expired-invite").status_code, 404)
        self.assertEqual(self.good(self.get("/pvp/status", self.host))["invites"], [])
        queue = "/pvp/queue"
        self.assertEqual(self.good(self.post(queue, self.host, "first-queue"))["status"], "queued")
        self.assertTrue(self.good(self.post(queue + "/cancel", self.host, "cancel-queue"))["cancelled"])
        self.assertEqual(self.good(self.post(queue, self.host, "second-queue"))["status"], "queued")
        found = self.good(self.post(queue, self.guest, "queue-join"))["match"]
        path = "/pvp/matches/" + found["match_id"]
        self.assertEqual(found["seat"], "axis")
        self.assertIsNone(self.good(self.get("/pvp/status", self.host))["queue"])
        self.assertEqual(self.good(self.get("/pvp/status", self.host))["matches"][0]["match_id"], found["match_id"])
        with ThreadPoolExecutor(max_workers=2) as workers:
            results = list(workers.map(lambda account: self.good(self.post(path + "/surrender", account, "end-early")),
                                       (self.host, self.guest)))
        self.assertEqual(results[0]["result"], results[1]["result"])
        self.assertEqual([result["end_reason"] for result in results], ["surrender"] * 2)
        self.assertIn(results[0]["result"]["winner"], ("allies", "axis"))
        with closing(self.store.connect()) as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM settlements").fetchone()[0], 1)


if __name__ == "__main__":
    unittest.main()
