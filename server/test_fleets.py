"""Account HTTP regression for cloud fleet presets and unpriced ranked drafts."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import ExitStack, closing
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from .accounts import AccountService, Credentials, PROLOGUE_SHIPS, create_app
from .fleets import ranked_composition_errors


class FleetTest(unittest.TestCase):
    password = "fleet-local-test-password"

    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.db = Path(self.stack.enter_context(TemporaryDirectory())) / "cas.sqlite3"
        # This account predates the routes. It starts with the existing asset shape.
        account = AccountService(self.db).register(Credentials(username="existing-captain", password=self.password))
        self.headers = self.token(account)
        self.app = create_app(self.db)
        self.client = self.stack.enter_context(TestClient(self.app))

    def good(self, response):
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    @staticmethod
    def token(account):
        return {"Authorization": "Bearer " + account["token"]}

    def register(self, name):
        return self.token(self.good(self.client.post("/auth/register", json={"username": name, "password": self.password})))

    def gift(self, headers=None):
        self.good(self.client.post("/prologue/claim", headers=headers or self.headers,
                                  json={"request_id": "fleet-starter-gift", "leader_id": PROLOGUE_SHIPS[0]}))

    def save(self, key, headers=None, **fields):
        fleet = {"id": "fleet-primary", "name": "  第五驱逐小队  ", "side": "allies", "budget": 3000,
                 "ship_ids": PROLOGUE_SHIPS[:3], "ai_profile": "rc_coordinated", **fields}
        return self.client.post("/fleets", headers=headers or self.headers, json={"request_id": key, "fleet": fleet})

    def test_existing_and_new_accounts_save_independently_and_resume(self):
        self.assertEqual(self.client.get("/fleets").status_code, 401)
        self.assertEqual(self.client.post("/fleets", json={}).status_code, 401)
        self.assertEqual(self.good(self.client.get("/fleets", headers=self.headers)), {
            "fleets": [], "active_fleet_id": None, "point_table_version": None, "ranked_available": False})
        self.gift()
        other = self.register("new-captain")
        self.assertEqual(self.save("different-captain", other, ai_profile="adaptive").status_code, 403)
        before = self.good(self.client.get("/me", headers=self.headers))["meta"]["wallet"]
        with ThreadPoolExecutor(max_workers=4) as pool:
            saves = list(pool.map(lambda _: self.good(self.save("idempotent-fleet")), range(4)))
        first = saves[0]
        self.assertTrue(all(copy == first for copy in saves))
        self.assertEqual(first["fleet"]["name"], "第五驱逐小队")
        self.assertEqual(first["fleet"]["leader_id"], PROLOGUE_SHIPS[0])
        self.assertEqual(first["active_fleet_id"], "fleet-primary")
        self.assertEqual(first["meta"]["wallet"], before)
        self.assertEqual(first["validation"]["unavailable_ship_ids"], PROLOGUE_SHIPS[:3])
        self.assertIsNone(first["validation"]["cost"])
        self.assertIsNone(first["fleet"]["cost_version"])
        self.assertFalse(first["validation"]["combat_ready"])
        self.assertFalse(first["validation"]["ranked_ready"])
        self.assertEqual(self.client.get("/fleets/fleet-primary", headers=other).status_code, 404)
        self.assertEqual(self.good(self.client.get("/fleets", headers=other))["fleets"], [])
        self.gift(other)
        self.good(self.save("idempotent-fleet", other, name="另一账号同名ID"))
        self.assertEqual(self.save("idempotent-fleet", name="误复用请求编号").status_code, 409)
        changed = self.good(self.save("rename-own-fleet", name="换领舰", leader_id=PROLOGUE_SHIPS[2]))
        self.assertEqual(self.good(self.save("idempotent-fleet")), first)

        with TestClient(create_app(self.db)) as restarted:
            resumed = self.good(restarted.get("/fleets", headers=self.headers))
            self.assertEqual(resumed["fleets"], [{"fleet": changed["fleet"], "validation": changed["validation"]}])
            self.assertEqual(resumed["active_fleet_id"], "fleet-primary")
            self.assertEqual(self.good(restarted.get("/fleets/fleet-primary", headers=other))["fleet"]["name"], "另一账号同名ID")
            self.assertFalse(self.good(restarted.get("/health"))["ranked_pvp"])
            self.assertFalse(self.good(restarted.get("/health"))["fleet_point_table_available"])
        with closing(self.app.state.accounts.connect()) as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM ledger WHERE operation='fleet-save'").fetchone()[0], 3)

    def test_inventory_input_and_real_3000_10000_constraints(self):
        self.gift()
        rejected = (
            (400, {"name": "   "}),
            (400, {"ship_ids": [PROLOGUE_SHIPS[0]] * 3}),
            (400, {"ship_ids": ["IBS-U-USN-UNKNOWN", *PROLOGUE_SHIPS[:2]]}),
            (403, {"ship_ids": ["IBS-U-IJN-KAGERO", *PROLOGUE_SHIPS[:2]]}),
            (400, {"side": "axis"}),
            (403, {"ai_profile": "rc_pincer"}),
            (400, {"leader_id": PROLOGUE_SHIPS[4]}),
            (400, {"ship_ids": PROLOGUE_SHIPS[:2]}),
            (400, {"budget": 10000}),
            (422, {"budget": 3300}),
            (422, {"cost_version": "cas-free-economy-v1"}),
            (422, {"cost": 0, "combat_ready": True}),
        )
        for index, (status, fields) in enumerate(rejected):
            result = self.save(f"bad-fleet-{index}", **fields)
            self.assertEqual(result.status_code, status, result.text)
        self.assertEqual(self.good(self.client.get("/fleets", headers=self.headers))["fleets"], [])

        # The battleship is obtained through the real UP purchase path, not a fake roster.
        with patch.object(self.app.state.accounts, "_random", side_effect=[.99, .1, .0]):
            draw = self.good(self.client.post("/recruit", headers=self.headers, json={
                "request_id": "fleet-get-carolina", "count": 1, "pool_id": "missouri-up"}))
        battleship = draw["receipts"][0]["ship_id"]
        self.assertEqual(battleship, "IBS-U-USN-UNNAMED-T01-R03")
        with_bb = [battleship, *PROLOGUE_SHIPS[:2]]
        self.assertEqual(self.save("escort-illegal-bb", ship_ids=with_bb).status_code, 400)
        self.assertEqual(self.save("five-dd-illegal", budget=10000, ship_ids=[battleship, *PROLOGUE_SHIPS]).status_code, 400)
        valid = self.good(self.save("battleship-draft", budget=10000, ship_ids=with_bb))
        self.assertTrue(valid["validation"]["structure_valid"])
        self.assertFalse(valid["validation"]["ranked_ready"])  # the two escorts are not owned yet
        self.assertEqual(valid["validation"]["unavailable_ship_ids"], with_bb[1:])

    def test_role_limits_preserve_original_ranked_composition(self):
        self.assertEqual(ranked_composition_errors(3000, ["DD"] * 6), [])
        self.assertTrue(ranked_composition_errors(3000, ["DD"] * 7))
        self.assertTrue(ranked_composition_errors(3000, ["DD", "DD", "CL", "CA", "CA"]))
        self.assertTrue(ranked_composition_errors(3000, ["DD", "CA", "CL"]))
        self.assertEqual(ranked_composition_errors(10000, ["BB", "BB", "CL", "CA"]), [])
        self.assertTrue(ranked_composition_errors(10000, ["BB", "BB", "BB", "CL", "CA"]))
        self.assertTrue(ranked_composition_errors(10000, ["BB", "BB", "CA"]))
        self.assertTrue(ranked_composition_errors(10000, ["BB", "CA", "CV"]))


if __name__ == "__main__":
    unittest.main()
