"""Private two-seat authority for the fixed, unrated CAS surface exercise."""
from __future__ import annotations

from contextlib import closing, contextmanager
from hashlib import sha256
import json
import secrets
import sqlite3
import time
from typing import Annotated, TYPE_CHECKING

from fastapi import Depends, FastAPI, Path

from .battle_pve import AI_UNLOCK, Inspect, MAX_ORDERS, MAX_TICKS, NativeCore, Order, SIM_TICK_MS, VIEW_KEYS, player_response, verified
from .contracts import Mutation, deny, encode

if TYPE_CHECKING:
    from .accounts import AccountService


VERSION = "cas-realtime-v8"
MODE = "fixed-5v5-unranked"
SEATS = ("allies", "axis")
WAIT_MS = 15 * 60 * 1000
APPLICATION_ID = 0x43415344  # CAS duels; independent of accounts and IBS.
SCHEMA = (
    """CREATE TABLE matches(
        id TEXT PRIMARY KEY, allies_id TEXT NOT NULL, axis_id TEXT NOT NULL,
        created_ms INTEGER NOT NULL, clock_ms INTEGER NOT NULL, completed_ms INTEGER,
        core_sha TEXT NOT NULL, state TEXT NOT NULL, CHECK (allies_id <> axis_id))""",
    "CREATE INDEX matches_allies ON matches(allies_id, created_ms DESC)",
    "CREATE INDEX matches_axis ON matches(axis_id, created_ms DESC)",
    """CREATE TABLE invites(
        code TEXT PRIMARY KEY, host_id TEXT NOT NULL, expires_ms INTEGER NOT NULL,
        match_id TEXT REFERENCES matches(id), cancelled INTEGER NOT NULL DEFAULT 0)""",
    "CREATE INDEX invites_host ON invites(host_id, expires_ms)",
    "CREATE TABLE queue(account_id TEXT PRIMARY KEY, queued_ms INTEGER NOT NULL)",
    """CREATE TABLE requests(account_id TEXT NOT NULL, request_id TEXT NOT NULL, fingerprint TEXT NOT NULL,
        response TEXT NOT NULL, PRIMARY KEY(account_id, request_id))""",
    """CREATE TABLE settlements(match_id TEXT PRIMARY KEY REFERENCES matches(id), completed_ms INTEGER NOT NULL,
        reason TEXT NOT NULL, result TEXT NOT NULL)""",
)


class DuelStore:
    def __init__(self, path):
        self.path = path

    def connect(self):
        db = sqlite3.connect(self.path, timeout=8, isolation_level=None)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys=ON")
        return db

    def initialize(self):
        with self.write() as db:
            app = db.execute("PRAGMA application_id").fetchone()[0]
            if app == 0 and not db.execute("SELECT 1 FROM sqlite_schema LIMIT 1").fetchone():
                for statement in SCHEMA:
                    db.execute(statement)
                db.execute(f"PRAGMA application_id={APPLICATION_ID}")
                db.execute("PRAGMA user_version=1")
            elif app != APPLICATION_ID or db.execute("PRAGMA user_version").fetchone()[0] != 1:
                raise ValueError("Not a supported CAS duel store")
        with closing(self.connect()) as db:
            db.execute("PRAGMA journal_mode=WAL")

    @contextmanager
    def write(self):
        with closing(self.connect()) as db, db:
            db.execute("BEGIN IMMEDIATE")
            yield db

    def mutate(self, account, request_id, op, payload, action):
        fingerprint = sha256(encode({"op": op, "body": payload}).encode()).hexdigest()
        with self.write() as db:
            prior = db.execute("SELECT fingerprint,response FROM requests WHERE account_id=? AND request_id=?",
                               (account, request_id)).fetchone()
            if prior is not None:
                if prior["fingerprint"] != fingerprint:
                    deny("此请求编号已用于其他操作。", 409)
                return json.loads(prior["response"])
            result = action(db)
            db.execute("INSERT INTO requests VALUES(?,?,?,?)", (account, request_id, fingerprint, encode(result)))
            return result


def seat_for(row, account):
    return "allies" if row["allies_id"] == account else "axis"


def opponent(seat):
    return "axis" if seat == "allies" else "allies"


def native_view(response, seat, tick, result):
    view = verified(response)
    if (view.get("version") != VERSION or view.get("side") != seat or view.get("tick") != tick
            or view.get("result") != result or "campaign" in view or not isinstance(view.get("ships"), list)):
        deny("原生内核返回了不匹配的座席观察。", 503)
    return {key: value for key, value in view.items() if key in VIEW_KEYS}


def native_summary(response):
    value = verified(response)
    result = value.get("result")
    if (value.get("version") != VERSION or type(value.get("tick")) is not int or
            (result is not None and (not isinstance(result, dict) or result.get("winner") not in (*SEATS, "draw")))):
        deny("原生内核返回了不匹配的约战状态。", 503)
    return value["tick"], result


def native_snapshot(response, tick):
    save = verified(response)
    if save.get("duel") is not True or save.get("version") != VERSION or save.get("tick") != tick:
        deny("原生内核未返回有效的双席快照。", 503)
    return save


class DuelService:
    def __init__(self, accounts: AccountService, core: NativeCore, *, clock_ms=None, seed_source=None):
        self.accounts = accounts
        self.core = core
        self.clock_ms = clock_ms or (lambda: time.time_ns() // 1_000_000)
        self.seed_source = seed_source or (lambda: secrets.randbits(32))
        account_path = accounts.db_path
        self.store = DuelStore(account_path.with_name(account_path.stem + "-duels.sqlite3"))

    def initialize(self):
        self._start_world(6106)
        self.store.initialize()

    def _start_world(self, seed):
        opened, allies, axis, saved = self.core.request(
            {"op": "match_new", "seed": seed},
            {"op": "match_observe", "seat": "allies"}, {"op": "match_observe", "seat": "axis"},
            {"op": "match_save"})
        tick, result = native_summary(opened)
        views = {seat: native_view(answer, seat, tick, result) for seat, answer in zip(SEATS, (allies, axis))}
        snapshot = native_snapshot(saved, tick)
        if (tick != 0 or result is not None or snapshot.get("seed") != seed or
                any(len(view["ships"]) != 5 or not view["fleets"] or
                    any(fleet["ai"]["mode"] != "manual" for fleet in view["fleets"]) for view in views.values())):
            deny("原生内核无法建立两席均手动的五对五演习。", 503)
        return {"tick": tick, "result": None, "reason": None, "views": views,
                "revision": dict.fromkeys(SEATS, 0), "snapshot": snapshot, "reports": None}

    @staticmethod
    def _active(db, account):
        return db.execute("SELECT * FROM matches WHERE completed_ms IS NULL AND (allies_id=? OR axis_id=?)",
                          (account, account)).fetchone()

    @staticmethod
    def _row(db, match_id, account):
        row = db.execute("SELECT * FROM matches WHERE id=? AND (allies_id=? OR axis_id=?)",
                         (match_id, account, account)).fetchone()
        if row is None:
            deny("本账号没有此约战。", 404)
        return row

    def _summary(self, row, account, *, with_view=False):
        state = json.loads(row["state"])
        seat = seat_for(row, account)
        value = {"match_id": row["id"], "seat": seat, "mode": MODE, "revision": state["revision"][seat],
                 "tick": state["tick"], "status": "complete" if row["completed_ms"] is not None else "active",
                 "result": state["result"], "end_reason": state["reason"]}
        if with_view:
            value["view"] = state["views"][seat]
        return value

    def _create_match(self, db, allies, axis, now):
        state = self._start_world(self.seed_source())
        match_id = "duel-" + secrets.token_hex(16)
        db.execute("INSERT INTO matches VALUES(?,?,?,?,?,NULL,?,?)",
                   (match_id, allies, axis, now, now, self.core.sha256, encode(state)))
        db.execute("DELETE FROM queue WHERE account_id IN (?,?)", (allies, axis))
        db.execute("UPDATE invites SET cancelled=1 WHERE host_id IN (?,?) AND match_id IS NULL", (allies, axis))
        return match_id

    def _load(self, row, state):
        if row["core_sha"] != self.core.sha256:
            deny("此约战需要开局时冻结的原生内核。", 409)
        return {"op": "match_load", "save": state["snapshot"]}

    def _check_load(self, loaded, state):
        if native_summary(loaded) != (state["tick"], state["result"]):
            deny("原生约战的快照与服务记录不一致。", 503)

    def _reports(self, row, state, *, engine_result):
        loaded, allies, axis = self.core.request(self._load(row, state),
            {"op": "match_report", "seat": "allies"}, {"op": "match_report", "seat": "axis"})
        if native_summary(loaded) != (state["tick"], engine_result):
            deny("原生约战战报未对应当前模拟秒。", 503)
        reports = {}
        for seat, response in zip(SEATS, (allies, axis)):
            report = verified(response)
            if report.get("result") != engine_result or not isinstance(report.get("events"), list):
                deny("原生约战的座席战报与终局不一致。", 503)
            reports[seat] = {"result": state["result"], "events": report["events"]}
        return reports

    def _settle(self, db, row, state, now, reason, result, *, engine_result):
        state["result"] = result
        state["reason"] = reason
        state["reports"] = self._reports(row, state, engine_result=engine_result)
        for view in state["views"].values():
            view["result"] = result
        db.execute("INSERT INTO settlements VALUES(?,?,?,?)", (row["id"], now, reason, encode(result)))
        db.execute("UPDATE matches SET clock_ms=?,completed_ms=?,state=? WHERE id=?",
                   (now, now, encode(state), row["id"]))

    def _refresh(self, db, row, account, now):
        owed = min(MAX_TICKS, max(0, now - row["clock_ms"]) // SIM_TICK_MS)
        if row["completed_ms"] is not None or not owed:
            return row
        state = json.loads(row["state"])
        loaded, advanced, allies, axis, saved = self.core.request(self._load(row, state),
            {"op": "match_step", "seconds": owed}, {"op": "match_observe", "seat": "allies"},
            {"op": "match_observe", "seat": "axis"}, {"op": "match_save"})
        self._check_load(loaded, state)
        tick, result = native_summary(advanced)
        delta = tick - state["tick"]
        if not 1 <= delta <= owed:
            deny("原生约战超出了服务器本批时钟。", 503)
        clock = row["clock_ms"] + delta * SIM_TICK_MS
        state.update(tick=tick, snapshot=native_snapshot(saved, tick), views={
            seat: native_view(answer, seat, tick, result) for seat, answer in zip(SEATS, (allies, axis))})
        if result is None:
            db.execute("UPDATE matches SET clock_ms=?,state=? WHERE id=?", (clock, encode(state), row["id"]))
        else:
            self._settle(db, row, state, clock, "battle", result, engine_result=result)
        return self._row(db, row["id"], account)

    def _current(self, account, match_id):
        with closing(self.store.connect()) as db:
            row = self._row(db, match_id, account)
            if row["completed_ms"] is not None or self.clock_ms() - row["clock_ms"] < SIM_TICK_MS:
                return row
        with self.store.write() as db:
            return self._refresh(db, self._row(db, match_id, account), account, self.clock_ms())

    @staticmethod
    def _invite(row):
        return {"code": row["code"], "expires_at": row["expires_ms"], "status": "waiting"}

    def invite(self, account, data):
        def create(db):
            if self._active(db, account):
                deny("请先完成当前约战。", 409)
            now = self.clock_ms()
            prior = db.execute("""SELECT * FROM invites WHERE host_id=? AND expires_ms>?
                AND match_id IS NULL AND cancelled=0""", (account, now)).fetchone()
            if prior:
                return self._invite(prior)
            code = "invite-" + secrets.token_urlsafe(12)
            db.execute("INSERT INTO invites(code,host_id,expires_ms) VALUES(?,?,?)", (code, account, now + WAIT_MS))
            db.execute("DELETE FROM queue WHERE account_id=?", (account,))
            return self._invite(db.execute("SELECT * FROM invites WHERE code=?", (code,)).fetchone())
        return self.store.mutate(account, data.request_id, "invite", data.model_dump(), create)

    def join(self, account, code, data):
        def join(db):
            now = self.clock_ms()
            invite = db.execute("SELECT * FROM invites WHERE code=?", (code,)).fetchone()
            if (not invite or invite["cancelled"] or invite["match_id"] is not None or invite["expires_ms"] <= now):
                deny("邀请无效、已使用或已过期。", 404)
            host = invite["host_id"]
            if host == account:
                deny("请把邀请交给另一个账号。", 409)
            if self._active(db, account) or self._active(db, host):
                deny("有一方正在另一场约战中。", 409)
            match_id = self._create_match(db, host, account, now)
            db.execute("UPDATE invites SET match_id=?,cancelled=0 WHERE code=?", (match_id, code))
            return self._summary(self._row(db, match_id, account), account, with_view=True)
        return self.store.mutate(account, data.request_id, "invite-join", {"code": code}, join)

    def cancel_invite(self, account, code, data):
        def cancel(db):
            row = db.execute("SELECT * FROM invites WHERE code=? AND host_id=?", (code, account)).fetchone()
            if not row:
                deny("本账号没有此约战邀请。", 404)
            if row["match_id"] is not None:
                deny("该邀请已经开局。", 409)
            db.execute("UPDATE invites SET cancelled=1 WHERE code=?", (code,))
            return {"cancelled": True}
        return self.store.mutate(account, data.request_id, "invite-cancel", {"code": code}, cancel)

    def queue(self, account, data):
        def queue(db):
            active = self._active(db, account)
            if active:
                return {"status": "matched", "match": self._summary(active, account, with_view=True)}
            now = self.clock_ms()
            db.execute("DELETE FROM queue WHERE queued_ms<=?", (now - WAIT_MS,))
            db.execute("UPDATE invites SET cancelled=1 WHERE host_id=? AND match_id IS NULL", (account,))
            queued = db.execute("SELECT queued_ms FROM queue WHERE account_id=?", (account,)).fetchone()
            if queued is None:
                db.execute("INSERT INTO queue VALUES(?,?)", (account, now))
            other = db.execute("SELECT * FROM queue WHERE account_id<>? ORDER BY queued_ms,account_id LIMIT 1",
                               (account,)).fetchone()
            if other is None:
                queued_at = queued["queued_ms"] if queued else now
                return {"status": "queued", "queued_at": queued_at, "expires_at": queued_at + WAIT_MS}
            match_id = self._create_match(db, other["account_id"], account, now)
            return {"status": "matched", "match": self._summary(self._row(db, match_id, account), account, with_view=True)}
        return self.store.mutate(account, data.request_id, "queue", data.model_dump(), queue)

    def cancel_queue(self, account, data):
        def cancel(db):
            removed = db.execute("DELETE FROM queue WHERE account_id=?", (account,)).rowcount
            return {"cancelled": bool(removed)}
        return self.store.mutate(account, data.request_id, "queue-cancel", data.model_dump(), cancel)

    def status(self, account):
        with closing(self.store.connect()) as db, db:
            db.execute("BEGIN")
            now = self.clock_ms()
            invites = db.execute("""SELECT * FROM invites WHERE host_id=? AND expires_ms>?
                AND match_id IS NULL AND cancelled=0 ORDER BY expires_ms""", (account, now))
            queued = db.execute("SELECT queued_ms FROM queue WHERE account_id=? AND queued_ms>?",
                                (account, now - WAIT_MS)).fetchone()
            matches = db.execute("""SELECT * FROM matches WHERE allies_id=? OR axis_id=?
                ORDER BY (completed_ms IS NULL) DESC,created_ms DESC,id DESC LIMIT 50""", (account, account))
            return {"mode": MODE, "ranked_available": False, "point_table_version": None,
                    "invites": [self._invite(row) for row in invites],
                    "queue": {"queued_at": queued["queued_ms"], "expires_at": queued["queued_ms"] + WAIT_MS} if queued else None,
                    "matches": [self._summary(row, account) for row in matches]}

    def view(self, account, match_id):
        return self._summary(self._current(account, match_id), account, with_view=True)

    def order(self, account, match_id, data):
        self._current(account, match_id)
        command = data.command.model_dump(exclude_none=True)
        if command["op"] == "ai":
            if command["mode"] == "auto":
                deny("双人演习只提供建议，须由本人确认下令。", 409)
            unlock = AI_UNLOCK.get(command["profile"])
            if unlock and unlock not in self.accounts.meta(account)["ai_profiles"]:
                deny("请先解锁此指挥风格。", 403)

        def act(db):
            row = self._row(db, match_id, account)
            state, seat = json.loads(row["state"]), seat_for(row, account)
            if row["completed_ms"] is not None or state["revision"][seat] != data.revision or data.revision >= MAX_ORDERS:
                deny("对局已结束、命令达到上限或本席修订号变化，请刷新。", 409)
            if self.clock_ms() - row["clock_ms"] >= MAX_TICKS * SIM_TICK_MS:
                deny("约战正在追赶服务器时钟，请刷新后再下令。", 409)
            other = opponent(seat)
            loaded, accepted, observed, saved = self.core.request(self._load(row, state),
                {"op": "match_act", "seat": seat, "command": command}, {"op": "match_observe", "seat": other},
                {"op": "match_save"})
            self._check_load(loaded, state)
            player_response(accepted)
            tick = state["tick"]
            state["views"] = {seat: native_view(accepted, seat, tick, None), other: native_view(observed, other, tick, None)}
            state["snapshot"] = native_snapshot(saved, tick)
            state["revision"][seat] += 1
            db.execute("UPDATE matches SET state=? WHERE id=?", (encode(state), match_id))
            return self._summary(self._row(db, match_id, account), account, with_view=True)
        return self.store.mutate(account, data.request_id, "match-command", {"match_id": match_id, **data.model_dump()}, act)

    def inspect(self, account, match_id, data):
        row = self._current(account, match_id)
        if row["completed_ms"] is not None:
            deny("此约战已经结算。", 409)
        state, seat = json.loads(row["state"]), seat_for(row, account)
        loaded, result = self.core.request(self._load(row, state), {"op": "match_inspect", "seat": seat,
            "command": data.command.model_dump(exclude_none=True)})
        self._check_load(loaded, state)
        return player_response(result)

    def report(self, account, match_id):
        row = self._current(account, match_id)
        state, seat = json.loads(row["state"]), seat_for(row, account)
        if state["reports"] is not None:
            return state["reports"][seat]
        loaded, response = self.core.request(self._load(row, state), {"op": "match_report", "seat": seat})
        self._check_load(loaded, state)
        report = verified(response)
        return {"result": report["result"], "events": report["events"]}

    def surrender(self, account, match_id, data):
        self._current(account, match_id)

        def surrender(db):
            row = self._row(db, match_id, account)
            if row["completed_ms"] is not None:
                return self._summary(row, account, with_view=True)
            if self.clock_ms() - row["clock_ms"] >= MAX_TICKS * SIM_TICK_MS:
                deny("约战正在追赶服务器时钟，请刷新。", 409)
            state, seat = json.loads(row["state"]), seat_for(row, account)
            result = {"winner": opponent(seat), **{name: 5 - len(state["views"][opponent(name)]["ships"])
                                                   for name in SEATS}}
            self._settle(db, row, state, row["clock_ms"], "surrender", result, engine_result=None)
            return self._summary(self._row(db, match_id, account), account, with_view=True)
        return self.store.mutate(account, data.request_id, "match-surrender", {"match_id": match_id}, surrender)


InviteCode = Annotated[str, Path(pattern=r"^invite-[A-Za-z0-9_-]{16}$")]
MatchId = Annotated[str, Path(pattern=r"^duel-[a-f0-9]{32}$")]


def mount(app: FastAPI, service: DuelService, account):
    @app.get("/pvp/status")
    def status(account_id: str = Depends(account)):
        return service.status(account_id)

    @app.post("/pvp/invites")
    def invite(data: Mutation, account_id: str = Depends(account)):
        return service.invite(account_id, data)

    @app.post("/pvp/invites/{code}/join")
    def join(code: InviteCode, data: Mutation, account_id: str = Depends(account)):
        return service.join(account_id, code, data)

    @app.post("/pvp/invites/{code}/cancel")
    def cancel_invite(code: InviteCode, data: Mutation, account_id: str = Depends(account)):
        return service.cancel_invite(account_id, code, data)

    @app.post("/pvp/queue")
    def queue(data: Mutation, account_id: str = Depends(account)):
        return service.queue(account_id, data)

    @app.post("/pvp/queue/cancel")
    def cancel_queue(data: Mutation, account_id: str = Depends(account)):
        return service.cancel_queue(account_id, data)

    @app.get("/pvp/matches/{match_id}")
    def view(match_id: MatchId, account_id: str = Depends(account)):
        return service.view(account_id, match_id)

    @app.post("/pvp/matches/{match_id}/commands")
    def command(match_id: MatchId, data: Order, account_id: str = Depends(account)):
        return service.order(account_id, match_id, data)

    @app.post("/pvp/matches/{match_id}/inspect")
    def inspect(match_id: MatchId, data: Inspect, account_id: str = Depends(account)):
        return service.inspect(account_id, match_id, data)

    @app.get("/pvp/matches/{match_id}/report")
    def report(match_id: MatchId, account_id: str = Depends(account)):
        return service.report(account_id, match_id)

    @app.post("/pvp/matches/{match_id}/surrender")
    def surrender(match_id: MatchId, data: Mutation, account_id: str = Depends(account)):
        return service.surrender(account_id, match_id, data)
