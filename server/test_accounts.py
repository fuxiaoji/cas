from concurrent.futures import ThreadPoolExecutor
from contextlib import closing, ExitStack
import hashlib
from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
import time
import unittest

from fastapi import HTTPException
from fastapi.testclient import TestClient

from server.accounts import APPLICATION_ID, PROLOGUE_SHIPS, beijing_week, create_app


class FreeEconomyTest(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.db = Path(self.stack.enter_context(TemporaryDirectory())) / "cas-accounts.sqlite3"
        self.app = create_app(self.db)
        self.service = self.app.state.accounts
        self.client = self.stack.enter_context(TestClient(self.app))
        self.password = "free-economy-test-password"
        self.account, self.headers = self.register("Test.Commander")

    def register(self, username):
        response = self.client.post("/auth/register", json={"username": username, "password": self.password})
        self.assertEqual(response.status_code, 200, response.text)
        session = response.json()
        return session, {"Authorization": "Bearer " + session["token"]}

    def post(self, path, request_id, headers=None, **body):
        return self.client.post(path, headers=self.headers if headers is None else headers,
                                json={"request_id": request_id, **body})

    def meta(self):
        return self.client.get("/me", headers=self.headers).json()["meta"]

    def assert_success(self, response):
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def fund_mail(self, up, standard):
        self.service.deliver_mail(self.account["account_id"], "test-coupons",
                                  title="测试券", body="CAS", attachments={"up_tickets": up, "standard_tickets": standard})
        return self.assert_success(self.post("/mail/test-coupons/claim", "test-coupon-claim"))

    def test_private_identity_and_restart(self):
        self.assertTrue(self.account["account_id"].startswith("cas-"))
        self.assertEqual(self.account["username"], "test.commander")
        self.assertEqual(self.client.get("/me").status_code, 401)
        duplicate = self.client.post("/auth/register", json={"username": "TEST.COMMANDER", "password": self.password})
        self.assertEqual(duplicate.status_code, 409)
        self.assertEqual(self.client.post("/auth/login", json={"username": "Test.Commander", "password": "incorrect-long"}).status_code, 401)
        with closing(self.service.connect()) as db:
            self.assertEqual(db.execute("PRAGMA application_id").fetchone()[0], APPLICATION_ID)
            self.assertEqual(db.execute("PRAGMA journal_mode").fetchone()[0], "wal")
            row = db.execute("SELECT salt,password_hash FROM accounts").fetchone()
            self.assertEqual(len(row["salt"]), 32)
            self.assertNotEqual(row["password_hash"], self.password)
            token_hash = db.execute("SELECT token_hash FROM sessions").fetchone()[0]
            self.assertEqual(token_hash, hashlib.sha256(self.account["token"].encode()).hexdigest())
        gift = self.assert_success(self.post("/prologue/claim", "prologue-first", leader_id=PROLOGUE_SHIPS[1]))
        self.assertFalse(gift["practice_verified"])
        self.assertEqual(set(gift["meta"]["owned_ships"]), set(PROLOGUE_SHIPS))
        self.assertEqual(gift["meta"]["wallet"]["up_tickets"], 10)
        self.assertEqual(gift["meta"]["wallet"]["standard_tickets"], 10)
        self.assertEqual(gift["meta"]["fleets"], [])
        self.assertFalse(self.assert_success(self.post("/prologue/claim", "prologue-second", leader_id=PROLOGUE_SHIPS[0]))["claimed"])
        with TestClient(create_app(self.db)) as restarted:
            self.assertEqual(restarted.get("/me", headers=self.headers).json()["meta"], self.meta())
        self.assert_success(self.client.post("/auth/logout", headers=self.headers))
        self.assertEqual(self.client.get("/me", headers=self.headers).status_code, 401)
        login = self.assert_success(self.client.post("/auth/login", json={"username": "TEST.COMMANDER", "password": self.password}))
        self.assertNotEqual(login["token"], self.account["token"])
        self.assertEqual(login["account_id"], self.account["account_id"])

    def test_mail_retries_and_account_isolation(self):
        aid = self.account["account_id"]
        _, other_headers = self.register("test.opponent")
        info = {"title": "邮件", "body": "CAS", "attachments": {"up_tickets": 4, "standard_tickets": 8}}
        initial = self.service.deliver_mail(aid, "weekly-1", **info)
        self.assertEqual(initial, self.service.deliver_mail(aid, "weekly-1", **info))
        with self.assertRaises(HTTPException) as conflict:
            self.service.deliver_mail(aid, "weekly-1", **{**info, "body": "changed"})
        self.assertEqual(conflict.exception.status_code, 409)
        self.assertEqual(self.meta()["wallet"]["up_tickets"], 0)
        self.assertEqual(self.client.get("/mail", headers=other_headers).json(), {"messages": []})
        self.assertEqual(self.post("/mail/weekly-1/claim", "other-user-claim", other_headers).status_code, 404)
        with ThreadPoolExecutor(max_workers=5) as workers:
            copies = list(workers.map(lambda i: self.post("/mail/weekly-1/claim", f"same-mail-retry-{i}"), range(8)))
        receipts = [self.assert_success(r) for r in copies]
        self.assertTrue(all(r == receipts[0] for r in receipts))
        self.assertEqual(self.meta()["wallet"]["up_tickets"], 4)
        self.assertEqual(self.meta()["wallet"]["standard_tickets"], 8)
        self.assertEqual(len(self.client.get("/me/ledger", headers=self.headers).json()), 1)
        self.assertEqual(self.client.post("/mail", headers=self.headers, json=info).status_code, 405)

    def test_concurrent_draw_retry_and_insufficient_funds_are_atomic(self):
        self.fund_mail(10, 10)
        self.service._random = lambda: 0.0

        def draw(i, pool_id, count):
            return self.post("/recruit", i, pool_id=pool_id, count=count)

        with ThreadPoolExecutor(max_workers=6) as workers:
            results = list(workers.map(lambda _: draw("same-draw-retry", "missouri-up", 10), range(8)))
        data = [self.assert_success(r) for r in results]
        self.assertTrue(all(x == data[0] for x in data))
        self.assertEqual(len(data[0]["receipts"]), 10)
        self.assertEqual(data[0]["receipts"][-1]["rarity"], "elite")
        self.assertEqual(sum(r["duplicate"] for r in data[0]["receipts"]), 8)
        self.assertEqual(draw("same-draw-retry", "missouri-up", 1).status_code, 409)
        with ThreadPoolExecutor(max_workers=2) as workers:
            results = list(workers.map(lambda i: draw(f"distinct-draw-{i}", "standard-v2", 10), range(2)))
        self.assertEqual(sorted(r.status_code for r in results), [200, 400])
        meta = self.meta()
        self.assertEqual((meta["wallet"]["up_tickets"], meta["wallet"]["standard_tickets"]), (0, 0))
        self.assertEqual(len(meta["pools"]["standard-v2"]["history"]), 10)
        self.assertEqual(len(self.client.get("/me/ledger", headers=self.headers).json()), 3)

    def test_actual_pools_pity_featured_and_fixed_shop_prices(self):
        self.fund_mail(81, 80)
        self.service._random = lambda: 0.0

        def advance(pool_id, count, request):
            return self.assert_success(self.post("/recruit", request, pool_id=pool_id, count=count))

        for pool_id in ("standard-v2", "missouri-up"):
            draws = []
            for index, n in enumerate([10] * 7 + [9]):
                draws.extend(advance(pool_id, n, f"draw-{pool_id}-{index}")["receipts"])
            self.assertEqual(draws[9]["rarity"], "elite")
            self.assertEqual(draws[39]["rarity"], "rare")
            self.assertNotIn("ur", {r["rarity"] for r in draws})
        standard = advance("standard-v2", 1, "draw-standard-80")
        self.assertEqual(standard["receipts"][0]["rarity"], "ur")
        standard_state = standard["meta"]["pools"]["standard-v2"]

        randoms = iter([0.75, 0.0])  # UR pity, misses the UP 50/50.
        self.service._random = lambda: next(randoms)
        off_banner = advance("missouri-up", 1, "draw-up-offbanner")
        self.assertEqual(off_banner["receipts"][0]["rarity"], "ur")
        self.assertNotEqual(off_banner["receipts"][0]["ship_id"], "IBS-U-USN-ERMA-MISSOURI")
        self.assertTrue(off_banner["meta"]["pools"]["missouri-up"]["up_guaranteed"])
        randoms = iter([0.99, 0.0])  # Natural UR; featured guarantee needs no 50/50 roll.
        next_ur = advance("missouri-up", 1, "draw-up-guarantee")
        self.assertEqual(next_ur["receipts"][0]["ship_id"], "IBS-U-USN-ERMA-MISSOURI")
        self.assertFalse(next_ur["meta"]["pools"]["missouri-up"]["up_guaranteed"])
        self.assertEqual(next_ur["meta"]["pools"]["standard-v2"], standard_state)
        ex = self.assert_success(self.post("/shop/purchase", "exchange-standard-one", kind="pool_ship",
                                           pool_id="standard-v2", item_id="IBS-U-USN-ERMA-DES-MOINES", currency="exchange_points"))
        self.assertEqual(ex["meta"]["pools"]["standard-v2"]["exchange_points"], 0)
        self.assertIn("IBS-U-USN-ERMA-DES-MOINES", ex["meta"]["owned_ships"])

        self.assertEqual(self.post("/starter-gifts/claim", "starter-out-of-order", course="night").status_code, 400)
        starter = self.assert_success(self.post("/starter-gifts/claim", "starter-valid-order", course="bridge"))
        self.assertEqual(starter["meta"]["wallet"]["credits"], 800)
        forged = self.post("/shop/purchase", "weekly-forged-price", kind="weekly_ticket", price=1)
        self.assertEqual(forged.status_code, 422)
        weekly = self.assert_success(self.post("/shop/purchase", "weekly-ticket-buy", kind="weekly_ticket"))
        self.assertEqual((weekly["meta"]["wallet"]["credits"], weekly["meta"]["wallet"]["standard_tickets"]), (300, 5))
        self.assertEqual(self.post("/shop/purchase", "weekly-ticket-repeat", kind="weekly_ticket").status_code, 400)
        self.assertEqual(self.meta()["wallet"]["paid_crystals"], 0)

    def test_trusted_weekly_clear_hook_and_client_rejection(self):
        endpoint = "/missions/weekly-pve/claim"
        self.assertEqual(self.post(endpoint, "pve-weekly-before-play").status_code, 403)
        self.assertEqual(self.post(endpoint, "pve-weekly-forgery", count=3, reward=1000).status_code, 422)
        self.assertEqual(self.client.post("/battles", headers=self.headers, json={"result": {"win": True}}).status_code, 404)
        self.assertEqual(self.client.post("/orders/test", headers=self.headers, json={"paid": True}).status_code, 404)
        aid = self.account["account_id"]
        now = int(time.time() * 1000)

        def record(conn, meta):
            write = self.service.record_authoritative_pve_clear
            self.assertTrue(write(conn, meta, aid, "prior-week", beijing_week(now)["start"] - 1))
            for i in range(3):
                self.assertTrue(write(conn, meta, aid, f"game-{i}", now))
            self.assertFalse(write(conn, meta, aid, "game-0", now))
            return {}

        self.service.mutate(aid, "internal/trusted-test", "verified-battle-completion", {}, record)
        mission = self.client.get("/missions/weekly-pve", headers=self.headers).json()
        self.assertEqual((mission["count"], mission["eligible"]), (3, True))
        first = self.assert_success(self.post(endpoint, "pve-weekly-earned"))
        self.assertTrue(first["claimed"])
        second = self.assert_success(self.post(endpoint, "pve-weekly-again"))
        self.assertFalse(second["claimed"])
        self.assertEqual(second["meta"]["wallet"]["standard_tickets"], 3)

    def test_catalog_and_foreign_database_gate(self):
        catalog = self.client.get("/catalog").json()
        self.assertEqual(len(catalog["ships"]), 210)
        self.assertEqual(sum(s["recruitable"] for s in catalog["ships"]), 22)
        combat_ships = [s for s in catalog["ships"] if s["combat_ready"]]
        # Only the verified North Carolina period card may claim combat
        # readiness, and it must cite its registered CAS profile source.
        self.assertEqual([s["id"] for s in combat_ships], ["IBS-U-USN-UNNAMED-T01-R03"])
        self.assertEqual(catalog["ships"].count(combat_ships[0]), 1)
        self.assertIn("cas-prologue-runtime-v1#north-carolina", combat_ships[0]["combat_source"])
        self.assertTrue(all(not s["combat_ready"] or s.get("combat_source") for s in catalog["ships"]))
        self.assertTrue(all("record_id" not in s and "cost" not in s for s in catalog["ships"]))
        self.assertFalse(self.client.get("/health").json()["real_payments"])
        foreign = self.db.with_name("iron-bottom.sqlite3")
        with closing(sqlite3.connect(foreign)) as db:
            db.execute("CREATE TABLE old_game(a)")
        before = foreign.read_bytes()
        with self.assertRaisesRegex(ValueError, "does not belong to CAS"):
            with TestClient(create_app(foreign)):
                self.fail("CAS accepted another game's database")
        self.assertEqual(foreign.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
