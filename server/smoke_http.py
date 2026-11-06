"""Start the private server in a temporary directory and verify real loopback HTTP."""
import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
from tempfile import TemporaryDirectory
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def smoke(sim=None, duels=False):
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
    base = f"http://127.0.0.1:{port}"

    def ask(path, data=None, token=None, method=None):
        headers = {"Content-Type": "application/json"} if data is not None else {}
        if token:
            headers["Authorization"] = "Bearer " + token
        body = json.dumps(data).encode("utf-8") if data is not None else None
        with urlopen(Request(base + path, body, headers, method=method), timeout=4) as response:
            return json.load(response)

    def expect_status(status, path, data=None, token=None):
        try:
            ask(path, data, token)
        except HTTPError as error:
            assert error.code == status, error.read().decode("utf-8")
        else:
            raise AssertionError(f"Expected {status} for {path}")

    with TemporaryDirectory(prefix="cas-http-") as tmp:
        db = Path(tmp) / "smoke.sqlite3"
        log = Path(tmp) / "uvicorn.log"
        env = {**os.environ, "CAS_ACCOUNT_DB": str(db)}
        env.pop("CAS_SIM_PATH", None)
        env.pop("CAS_ENABLE_DUELS", None)
        if sim is not None:
            env["CAS_SIM_PATH"] = str(Path(sim).resolve(strict=True))
        if duels:
            env["CAS_ENABLE_DUELS"] = "1"
        cmd = [sys.executable, "-m", "uvicorn", "server.accounts:app", "--host", "127.0.0.1",
               "--port", str(port), "--log-level", "warning"]
        with log.open("w+", encoding="utf-8") as output:
            child = subprocess.Popen(cmd, env=env, stdout=output, stderr=output,
                                     creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            try:
                deadline = time.monotonic() + 8
                while True:
                    try:
                        ready = ask("/health")
                        break
                    except (TimeoutError, URLError):
                        if child.poll() is not None or time.monotonic() >= deadline:
                            output.seek(0)
                            raise RuntimeError(output.read())
                        time.sleep(0.1)
                assert ready["service"] == "cas-free-economy" and ready["real_payments"] is False
                assert ready["pve_available"] is (sim is not None)
                assert ready["pvp_available"] is duels and ready["ranked_pvp"] is False
                auth = ask("/auth/register", {"username": "cas-smoke", "password": "temporary-smoke-password"})
                token = auth["token"]
                from server.accounts import AccountService
                AccountService(db).deliver_mail(auth["account_id"], "smoke-01", title="试运行",
                                                 body="CAS", attachments={"standard_tickets": 2})
                first = ask("/mail/smoke-01/claim", {"request_id": "smoke-claim-01"}, token)
                assert first["meta"]["wallet"]["standard_tickets"] == 2
                payload = {"request_id": "smoke-recruit-01", "count": 2, "pool_id": "standard-v2"}
                draw = ask("/recruit", payload, token)
                assert len(draw["receipts"]) == 2 and draw == ask("/recruit", payload, token)
                assert ask("/me", token=token)["meta"]["wallet"]["standard_tickets"] == 0
                assert len(ask("/me/ledger", token=token)) == 2
                if sim is not None:
                    started = ask("/battles", {"request_id": "http-native-01", "stage_id": "CAMP-AXIS-03",
                                               "difficulty": "standard"}, token)
                    path = "/battles/" + started["battle_id"]
                    assert started["view"]["side"] == "axis" and len(started["view"]["ships"]) == 5
                    assert "seed" not in started and "seed" not in started["view"]
                    enemy = ask("/auth/register", {"username": "second-smoke", "password": "temporary-smoke-password"})
                    expect_status(404, path, token=enemy["token"])
                    expect_status(422, path + "/inspect", {"command": {"op": "save"}}, token)
                    expect_status(409, path + "/claim", {"request_id": "http-claim-early"}, token)
                    fleet = started["view"]["fleets"][0]["id"]
                    order = {"request_id": "http-native-order", "revision": 0, "command": {
                        "op": "ai", "fleet": fleet, "mode": "auto", "profile": "coord",
                        "move": True, "gun": True, "torpedo": True}}
                    accepted = ask(path + "/commands", order, token)
                    assert accepted["revision"] == 1 and ask(path + "/commands", order, token) == accepted
                    time.sleep(0.35)
                    observed = ask(path, token=token)
                    assert observed["tick"] > started["tick"] and observed["revision"] == 1
                    assert ask("/battles", token=token)[0]["battle_id"] == started["battle_id"]
                    assert len(ask("/me/ledger", token=token)) == 2
                rookie = ask("/auth/register", {"username": "rookie-smoke", "password": "temporary-smoke-password"})["token"]
                assert ask("/missions/check-in", token=rookie)["next"]["id"] == "rookie-check-in-v1:1"
                check_in_payload = {"request_id": "http-check-in-one"}
                welcome = ask("/missions/check-in/claim", check_in_payload, rookie)
                assert welcome["claimed"] and welcome == ask("/missions/check-in/claim", check_in_payload, rookie)
                assert welcome["meta"]["wallet"]["credits"] == 500 and welcome["meta"]["wallet"]["standard_tickets"] == 2
                assert ask("/progression", token=rookie)["check_in"]["claimed"] == 1
                assert ask("/progression", token=token)["check_in"]["claimed"] == 0
                duel_evidence = None
                if duels:
                    invited = ask("/pvp/invites", {"request_id": "http-duel-invite"}, token)
                    guest = ask(f"/pvp/invites/{invited['code']}/join", {"request_id": "http-duel-join"}, enemy["token"])
                    duel_path = "/pvp/matches/" + guest["match_id"]
                    host = ask(duel_path, token=token)
                    assert (host["seat"], guest["seat"]) == ("allies", "axis")
                    assert [ship["id"] for ship in host["view"]["ships"]] == [1, 2, 3, 4, 5]
                    assert [ship["id"] for ship in guest["view"]["ships"]] == [6, 7, 8, 9, 10]
                    expect_status(404, duel_path, token=rookie)
                    for seat_token, fleet, x, y in ((token, 1, 16000, 6550), (enemy["token"], 2, 8000, 7650)):
                        route = {"request_id": "http-duel-route", "revision": 0, "command": {
                            "op": "route", "fleet": fleet, "mode": "follow", "speed": 26, "points": [{"x": x, "y": y}]}}
                        accepted = ask(duel_path + "/commands", route, seat_token)
                        assert accepted["revision"] == 1 and accepted == ask(duel_path + "/commands", route, seat_token)
                    time.sleep(.35)
                    assert ask(duel_path, token=token)["tick"] > 0
                    final = ask(duel_path + "/surrender", {"request_id": "http-duel-surrender"}, enemy["token"])
                    assert final["result"]["winner"] == "allies" and final["end_reason"] == "surrender"
                    assert ask(duel_path + "/report", token=token)["result"] == final["result"]
                    duel_evidence = {"sameMatch": True, "privateSeats": True, "outsiderDenied": True,
                                     "idempotentRoutes": True, "clockAdvanced": True, "surrenderSettled": True}
                assert ask("/auth/logout", token=token, method="POST")["logged_out"]
                expect_status(401, "/me", token=token)
            finally:
                child.terminate()
                child.wait(timeout=8)
    print(json.dumps({"ok": True, "service": "cas-free-economy", "realHttp": True, "idempotentDraw": True,
                      "serverMail": True, "ledgerEntries": 2, "logoutRevoked": True,
                      "rookieCheckIn": {"slot": 1, "credits": 500, "standardTickets": 2, "idempotent": True, "isolated": True},
                      "nativeUnrankedDuel": duel_evidence,
                      "nativeCapePvE": ({"stageId": started["stage_id"], "seat": started["view"]["side"],
                                         "tick": observed["tick"], "revision": observed["revision"],
                                         "crossAccountDenied": True, "earlyClaimDenied": True,
                                         "rawSaveDenied": True, "idempotentOrder": True} if sim else None)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sim", type=Path, help="optional native CAS CLI to test authenticated Cape PvE too")
    parser.add_argument("--duels", action="store_true", help="also test the opt-in native two-seat trial")
    args = parser.parse_args()
    if args.duels and args.sim is None:
        parser.error("--duels requires --sim")
    smoke(args.sim, args.duels)
