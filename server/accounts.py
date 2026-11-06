"""Independent CAS free economy; adapted from the pinned IBS 0.6.9 account service.

Source: backend/src/iron_bottom_sound/mobile_account_service.py at
48385c8337d3f5a08e3ebc5676d68309df87542d. SQLite, wallets, two pools, and
server-issued receipts are retained. No IBS engine, save, or database is used.
"""
from __future__ import annotations

from contextlib import asynccontextmanager, closing, contextmanager
from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import sqlite3
import time
from typing import Any, Callable, Literal

from fastapi import Depends, FastAPI, Header
from fastapi.middleware.cors import CORSMiddleware
from pydantic import Field

from .contracts import Mutation, StrictModel, deny, encode

ROOT = Path(__file__).resolve().parent
CATALOG_FILE = ROOT / "catalog.json"
DEFAULT_DB = ROOT / "data" / "cas-accounts.sqlite3"
APPLICATION_ID = 0x43415341  # CAS account store; never initialize another application's database.
SCHEMA = """
CREATE TABLE accounts(id TEXT PRIMARY KEY,username TEXT NOT NULL UNIQUE,salt TEXT NOT NULL,password_hash TEXT NOT NULL,created INTEGER NOT NULL);
CREATE TABLE sessions(token_hash TEXT PRIMARY KEY,account_id TEXT NOT NULL REFERENCES accounts(id),expires INTEGER NOT NULL);
CREATE TABLE assets(account_id TEXT PRIMARY KEY REFERENCES accounts(id),state TEXT NOT NULL);
CREATE TABLE requests(account_id TEXT NOT NULL REFERENCES accounts(id),request_id TEXT NOT NULL,fingerprint TEXT NOT NULL,response TEXT NOT NULL,PRIMARY KEY(account_id,request_id));
CREATE TABLE ledger(id INTEGER PRIMARY KEY AUTOINCREMENT,account_id TEXT NOT NULL REFERENCES accounts(id),request_id TEXT NOT NULL,operation TEXT NOT NULL,change_json TEXT NOT NULL,created INTEGER NOT NULL);
CREATE INDEX ledger_owner_recent ON ledger(account_id,id DESC);
CREATE TABLE account_mail(
    account_id TEXT NOT NULL REFERENCES accounts(id), id TEXT NOT NULL,
    title TEXT NOT NULL, body TEXT NOT NULL, sender TEXT NOT NULL,
    created_at INTEGER NOT NULL, claimed_at INTEGER,
    up_tickets INTEGER NOT NULL CHECK(up_tickets >= 0),
    standard_tickets INTEGER NOT NULL CHECK(standard_tickets >= 0),
    PRIMARY KEY(account_id,id)
);
CREATE TABLE pve_clears(
    account_id TEXT NOT NULL REFERENCES accounts(id),
    game_id TEXT NOT NULL, completed_at INTEGER NOT NULL, PRIMARY KEY(account_id,game_id)
);
CREATE INDEX pve_clears_week ON pve_clears(account_id,completed_at);
"""
PVE_SCHEMA = """
CREATE TABLE pve_battles(
    id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id),
    stage_id TEXT NOT NULL, difficulty TEXT NOT NULL, core_sha TEXT NOT NULL,
    revision INTEGER NOT NULL, clock_ms INTEGER NOT NULL, created_at INTEGER NOT NULL,
    snapshot TEXT NOT NULL, view TEXT NOT NULL, report TEXT, completed_at INTEGER
);
CREATE INDEX pve_battles_owner ON pve_battles(account_id,created_at DESC);
"""
PASSWORD_ROUNDS = 600_000
SESSION_SECONDS = 30 * 24 * 60 * 60
DUPLICATE_MEDALS = {"common": 1, "elite": 5, "rare": 20, "ur": 50}
MEDAL_PRICES = {"common": 15, "elite": 45, "rare": 120, "ur": 300}
DEDICATED_TICKETS = ("up_tickets", "standard_tickets")
PROLOGUE_SHIPS = ["IBS-U-USN-" + name for name in ("FLETCHER", "PERKINS", "MAURY", "DRAYTON", "LAMSON")]
STARTER_GIFTS = {
    "bridge": {"id": "tutorial-bridge", "title": "舰桥入门赠礼", "credits": 800, "tickets": 4,
               "ship_ids": ["IBS-U-USN-FLETCHER", "IBS-U-USN-PERKINS", "IBS-U-USN-MAURY"], "ai_profiles": ["adaptive"]},
    "night": {"id": "tutorial-night", "title": "夜战初阵赠礼", "credits": 600, "tickets": 3,
              "ship_ids": ["IBS-U-USN-DRAYTON"]},
    "torpedo": {"id": "tutorial-torpedo", "title": "编队训练赠礼", "credits": 1000, "tickets": 3,
                "ship_ids": ["IBS-U-USN-HONOLULU"], "ai_profiles": ["rc_coordinated"]},
}


def initial_meta() -> dict[str, Any]:
    return {"version": 1, "wallet": {"credits": 0, "tickets": 0, "up_tickets": 0, "standard_tickets": 0,
                                     "paid_crystals": 0, "medals": 0},
            "owned_ships": [], "ai_profiles": ["adaptive"], "completed_steps": [], "completed_courses": [],
            "stage_progress": {}, "claims": [], "fleets": [], "active_fleet_id": None,
            "draw": {"since_elite": 0, "since_rare": 0, "exchange_points": 0, "history": []}, "transactions": []}


def _read_meta(encoded: str) -> dict:
    state = json.loads(encoded)
    for key in DEDICATED_TICKETS:
        state["wallet"].setdefault(key, 0)
    return state


def _spend_recruit_tickets(wallet: dict, pool_id: str | None, count: int) -> None:
    dedicated = "up_tickets" if pool_id == "missouri-up" else "standard_tickets"
    available = wallet.get(dedicated, 0)
    if available + wallet["tickets"] < count:
        deny("当前卡池征募券不足。")
    spent = min(available, count)
    wallet[dedicated] = available - spent
    wallet["tickets"] -= count - spent


def _recruitable(ship: dict) -> bool:
    return ship.get("recruitable") is not False


def beijing_week(now: int | None = None) -> dict:
    now = int(time.time() * 1000) if now is None else now
    day_ms, offset = 86_400_000, 8 * 3_600_000
    day = (now + offset) // day_ms
    monday = day - (day + 3) % 7
    date = datetime.fromtimestamp(monday * 86_400, tz=timezone.utc)
    start = monday * day_ms - offset
    return {"key": f"{date.year}-{date.month}-{date.day}", "start": start,
            "end": start + 7 * day_ms, "monday_day": monday}


def grant(state: dict, reward: dict, now: int) -> bool:
    """Internal only: callers select the grant from server-owned data."""
    if reward["id"] in state["claims"]:
        return False
    for key in ("credits", "medals", "tickets", *DEDICATED_TICKETS):
        amount = reward.get(key, 0)
        if not isinstance(amount, int) or isinstance(amount, bool) or amount < 0:
            raise ValueError("服务器奖励表数量无效")
        target = "standard_tickets" if key == "tickets" else key
        state["wallet"][target] = state["wallet"].get(target, 0) + amount
    for key in ("owned_ships", "ai_profiles"):
        values = reward.get("ship_ids" if key == "owned_ships" else key, [])
        state[key] = list(dict.fromkeys(state[key] + values))
    state["claims"].append(reward["id"])
    state["transactions"].append({"id": "reward:" + reward["id"], "title": reward["title"], "time": now})
    return True


class Credentials(StrictModel):
    username: str = Field(min_length=3, max_length=40, pattern=r"^[A-Za-z0-9_.-]+$")
    password: str = Field(min_length=10, max_length=128)


class MailAttachments(StrictModel):
    up_tickets: int = Field(default=0, ge=0, le=1_000_000)
    standard_tickets: int = Field(default=0, ge=0, le=1_000_000)


class MailDelivery(StrictModel):
    message_id: str = Field(min_length=1, max_length=100, pattern=r"^[A-Za-z0-9_.:-]+$")
    title: str = Field(min_length=1, max_length=120)
    body: str = Field(max_length=4000)
    sender: str = Field(min_length=1, max_length=80)
    attachments: MailAttachments


class GiftClaim(Mutation):
    course: Literal["bridge", "night", "torpedo"]


class PrologueClaim(Mutation):
    leader_id: str = Field(min_length=1, max_length=100)


class Recruit(Mutation):
    count: int = Field(default=1, ge=1, le=10)
    pool_id: str | None = Field(default=None, max_length=80)


class Purchase(Mutation):
    kind: Literal["ship", "ai", "weekly_ticket", "pool_ship", "ship_bundle"]
    item_id: str = Field(default="", max_length=100)
    currency: Literal["credits", "medals", "exchange_points"] = "credits"
    pool_id: str | None = Field(default=None, max_length=80)


class AccountService:
    def __init__(self, db_path: str | Path, catalog_path: str | Path = CATALOG_FILE):
        self.db_path = Path(db_path).resolve()
        self.catalog = json.loads(Path(catalog_path).read_text(encoding="utf-8"))
        if (self.catalog["combat_catalog_available"] is not False
                or any(ship["combat_ready"] is not False for ship in self.catalog["ships"])):
            raise ValueError("The free economy requires a collection-only catalog")
        self._random = lambda: secrets.randbelow(1_000_000) / 1_000_000

    def connect(self):
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(self.db_path, timeout=30, isolation_level=None)
        conn.row_factory = sqlite3.Row
        try:
            conn.execute("PRAGMA foreign_keys=ON")
            application = conn.execute("PRAGMA application_id").fetchone()[0]
            if application != APPLICATION_ID:
                with conn:
                    conn.execute("BEGIN IMMEDIATE")
                    application = conn.execute("PRAGMA application_id").fetchone()[0]
                    if application != APPLICATION_ID:
                        if application or conn.execute("SELECT 1 FROM sqlite_schema LIMIT 1").fetchone():
                            raise ValueError("CAS_ACCOUNT_DB points to a database that does not belong to CAS")
                        for sql in (SCHEMA + PVE_SCHEMA).split(";"):
                            if sql.strip():
                                conn.execute(sql)
                        conn.execute(f"PRAGMA application_id={APPLICATION_ID}")
                        conn.execute("PRAGMA user_version=2")
                conn.execute("PRAGMA journal_mode=WAL")
            version = conn.execute("PRAGMA user_version").fetchone()[0]
            if version == 1:
                with conn:
                    conn.execute("BEGIN IMMEDIATE")
                    version = conn.execute("PRAGMA user_version").fetchone()[0]
                    if version == 1:
                        for sql in PVE_SCHEMA.split(";"):
                            if sql.strip():
                                conn.execute(sql)
                        conn.execute("PRAGMA user_version=2")
                    elif version != 2:
                        raise ValueError("Unsupported CAS account database schema")
            elif version != 2:
                raise ValueError("Unsupported CAS account database schema")
            return conn
        except BaseException:
            conn.close()
            raise

    @contextmanager
    def write(self):
        conn = self.connect()
        try:
            conn.execute("BEGIN IMMEDIATE")
            yield conn
            conn.commit()
        except BaseException:
            conn.rollback()
            raise
        finally:
            conn.close()

    def _session(self, conn, account_id):
        token = secrets.token_urlsafe(32)
        conn.execute("INSERT INTO sessions VALUES(?,?,?)", (hashlib.sha256(token.encode()).hexdigest(), account_id, int(time.time()) + SESSION_SECONDS))
        return token

    def register(self, data: Credentials):
        username = data.username.casefold()
        salt = secrets.token_hex(16)
        password_hash = hashlib.pbkdf2_hmac("sha256", data.password.encode(), bytes.fromhex(salt), PASSWORD_ROUNDS).hex()
        account_id = "cas-" + secrets.token_hex(16)
        with self.write() as conn:
            try:
                conn.execute("INSERT INTO accounts VALUES(?,?,?,?,?)", (account_id, username, salt, password_hash, int(time.time())))
            except sqlite3.IntegrityError:
                deny("用户名已存在。", 409)
            conn.execute("INSERT INTO assets VALUES(?,?)", (account_id, encode(initial_meta())))
            token = self._session(conn, account_id)
        return {"account_id": account_id, "username": username, "token": token, "token_type": "bearer", "expires_in": SESSION_SECONDS}

    def login(self, data: Credentials):
        with closing(self.connect()) as conn:
            row = conn.execute("SELECT * FROM accounts WHERE username=?", (data.username.casefold(),)).fetchone()
        salt = bytes.fromhex(row["salt"]) if row else bytes(16)
        candidate = hashlib.pbkdf2_hmac("sha256", data.password.encode(), salt, PASSWORD_ROUNDS).hex()
        if not row or not hmac.compare_digest(candidate, row["password_hash"]):
            deny("用户名或密码不正确。", 401)
        with self.write() as conn:
            token = self._session(conn, row["id"])
        return {"account_id": row["id"], "username": row["username"], "token": token, "token_type": "bearer", "expires_in": SESSION_SECONDS}

    def authenticate(self, authorization: str | None):
        if not authorization or not authorization.startswith("Bearer "):
            deny("请先登录。", 401)
        digest = hashlib.sha256(authorization[7:].encode()).hexdigest()
        with closing(self.connect()) as conn:
            row = conn.execute("SELECT account_id,expires FROM sessions WHERE token_hash=?", (digest,)).fetchone()
        if not row or row["expires"] <= time.time():
            deny("登录已失效，请重新登录。", 401)
        return row["account_id"]

    def meta(self, account_id):
        with closing(self.connect()) as conn:
            row = conn.execute("SELECT state FROM assets WHERE account_id=?", (account_id,)).fetchone()
        if not row:
            deny("账号不存在。", 404)
        return _read_meta(row["state"])

    def mutate(self, account_id: str, request_id: str, operation: str, payload: dict,
               action: Callable[[sqlite3.Connection, dict], dict], *, fresh_meta_on_replay: bool = False,
               mutates_assets: bool = True):
        fingerprint = hashlib.sha256(encode({"op": operation, "body": payload}).encode()).hexdigest()
        with self.write() as conn:
            old = conn.execute("SELECT fingerprint,response FROM requests WHERE account_id=? AND request_id=?", (account_id, request_id)).fetchone()
            if old:
                if old["fingerprint"] != fingerprint:
                    deny("请求编号已用于另一项操作，请使用新的编号。", 409)
                response = json.loads(old["response"])
                if fresh_meta_on_replay:
                    row = conn.execute("SELECT state FROM assets WHERE account_id=?", (account_id,)).fetchone()
                    response["meta"] = _read_meta(row["state"])
                return response
            state = _read_meta(conn.execute("SELECT state FROM assets WHERE account_id=?", (account_id,)).fetchone()["state"])
            if not mutates_assets:
                response = action(conn, state)
                conn.execute("INSERT INTO requests VALUES(?,?,?,?)", (account_id, request_id, fingerprint, encode(response)))
                return response
            before = deepcopy(state)
            response = action(conn, state)
            if any(type(n) is not int or n < 0 for n in state["wallet"].values()) or state["wallet"]["paid_crystals"] != 0:
                raise ValueError("资源余额无效，事务已回滚")
            response = {**response, "meta": state}
            if state != before:
                conn.execute("UPDATE assets SET state=? WHERE account_id=?", (encode(state), account_id))
                change = {"wallet_before": before["wallet"], "wallet_after": state["wallet"],
                          "added_ships": [sid for sid in state["owned_ships"] if sid not in before["owned_ships"]],
                          "added_ai": [pid for pid in state["ai_profiles"] if pid not in before["ai_profiles"]]}
                conn.execute("INSERT INTO ledger(account_id,request_id,operation,change_json,created) VALUES(?,?,?,?,?)",
                             (account_id, request_id, operation, encode(change), int(time.time() * 1000)))
            conn.execute("INSERT INTO requests VALUES(?,?,?,?)", (account_id, request_id, fingerprint, encode(response)))
            return response

    @staticmethod
    def _mail_message(row: sqlite3.Row) -> dict:
        def date(value: int) -> str:
            return datetime.fromtimestamp(value / 1000, tz=timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")

        return {"id": row["id"], "title": row["title"], "body": row["body"], "sender": row["sender"],
                "created_at": date(row["created_at"]),
                "claimed_at": None if row["claimed_at"] is None else date(row["claimed_at"]),
                "attachments": {key: row[key] for key in DEDICATED_TICKETS}}

    def deliver_mail(self, account_id: str, message_id: str, *, title: str, body: str,
                     sender: str = "舰桥补给处", attachments: dict[str, int] | None = None) -> dict:
        """Deliver an operator-selected message without changing the recipient wallet."""
        delivery = MailDelivery(message_id=message_id, title=title, body=body, sender=sender,
                                attachments={} if attachments is None else attachments)
        tickets = delivery.attachments.model_dump()
        now = int(time.time() * 1000)
        with self.write() as conn:
            if not conn.execute("SELECT 1 FROM accounts WHERE id=?", (account_id,)).fetchone():
                deny("收件账号不存在。", 404)
            conn.execute(
                "INSERT INTO account_mail(account_id,id,title,body,sender,created_at,up_tickets,standard_tickets) "
                "VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(account_id,id) DO NOTHING",
                (account_id, message_id, title, body, sender, now, tickets["up_tickets"], tickets["standard_tickets"]))
            row = conn.execute("SELECT * FROM account_mail WHERE account_id=? AND id=?", (account_id, message_id)).fetchone()
            message = self._mail_message(row)
            if (message["title"], message["body"], message["sender"], message["attachments"]) != (title, body, sender, tickets):
                deny("此邮件编号已用于其他内容。", 409)
            return message

    def mail(self, account_id: str) -> dict:
        with closing(self.connect()) as conn:
            rows = conn.execute("SELECT * FROM account_mail WHERE account_id=? ORDER BY created_at DESC,id DESC", (account_id,))
            return {"messages": [self._mail_message(row) for row in rows]}

    def claim_mail(self, account_id: str, message_id: str) -> dict:
        # Mail has one authoritative claim per recipient. The slash reserves an
        # internal request key that cannot be submitted to other mutation routes.
        request_id = "mail-claim/" + hashlib.sha256(message_id.encode()).hexdigest()

        def action(conn, state):
            row = conn.execute("SELECT * FROM account_mail WHERE account_id=? AND id=?", (account_id, message_id)).fetchone()
            if not row:
                deny("邮件不存在。", 404)
            if row["claimed_at"] is None:
                now = int(time.time() * 1000)
                grant(state, {"id": "mail:" + message_id, "title": row["title"],
                              **{key: row[key] for key in DEDICATED_TICKETS}}, now)
                row = conn.execute("UPDATE account_mail SET claimed_at=? WHERE account_id=? AND id=? RETURNING *",
                                   (now, account_id, message_id)).fetchone()
            return {"mail": self._mail_message(row)}

        return self.mutate(account_id, request_id, "mail-claim", {"message_id": message_id}, action,
                           fresh_meta_on_replay=True)

    def starter_gift(self, account_id, data: GiftClaim):
        def action(conn, state):
            course_order = ("bridge", "night", "torpedo")
            index = course_order.index(data.course)
            if index and STARTER_GIFTS[course_order[index - 1]]["id"] not in state["claims"]:
                deny("请先领取前一份新手赠礼。")
            claimed = grant(state, STARTER_GIFTS[data.course], int(time.time() * 1000))
            return {"claimed": claimed, "gift_id": STARTER_GIFTS[data.course]["id"], "practice_verified": False}
        return self.mutate(account_id, data.request_id, "starter-gift", data.model_dump(), action)

    @staticmethod
    def _weekly_pve_status(conn, state, account_id, now=None):
        week = beijing_week(now)
        reward_id = "weekly-pve:" + week["key"]
        count = conn.execute("SELECT COUNT(*) FROM pve_clears WHERE account_id=? AND completed_at>=? AND completed_at<?",
                             (account_id, week["start"], week["end"])).fetchone()[0]
        return {"id": reward_id, "count": count, "target": 3, "eligible": count >= 3,
                "claimed": reward_id in state["claims"], "week_start": week["start"], "week_end": week["end"],
                "reward": {"id": reward_id, "title": "每周实战补给", "credits": 500, "tickets": 3}}

    def weekly_pve_status(self, account_id):
        with closing(self.connect()) as conn:
            state = json.loads(conn.execute("SELECT state FROM assets WHERE account_id=?", (account_id,)).fetchone()["state"])
            return self._weekly_pve_status(conn, state, account_id)

    @staticmethod
    def record_authoritative_pve_clear(conn, state, account_id: str, game_id: str, completed_at_ms: int):
        """Internal hook: call only with the CAS battle service's verified terminal facts.

        Requires the caller's account mutation transaction. No HTTP handler accepts
        match completion, timestamps, reward amounts or a client-imported save.
        """
        inserted = conn.execute("INSERT OR IGNORE INTO pve_clears VALUES(?,?,?)",
                                (account_id, game_id, completed_at_ms)).rowcount
        if inserted:
            state["transactions"].append({"id": "battle-clear:" + game_id, "title": "主目标达成", "time": completed_at_ms})
        return bool(inserted)

    def claim_weekly_pve(self, account_id, data: Mutation):
        def action(conn, state):
            now = int(time.time() * 1000)
            mission = self._weekly_pve_status(conn, state, account_id, now)
            if mission["claimed"]:
                return {"claimed": False, "mission": mission}
            if not mission["eligible"]:
                deny("本周还未完成3场主目标达成的服务器PvE任务。", 403)
            grant(state, mission["reward"], now)
            return {"claimed": True, "mission": self._weekly_pve_status(conn, state, account_id, now)}
        return self.mutate(account_id, data.request_id, "weekly-pve-claim", data.model_dump(), action)

    def recruit(self, account_id, data: Recruit):
        if data.pool_id not in (None, "", "legacy-v1"):
            return self.recruit_pool(account_id, data)
        def action(conn, state):
            _spend_recruit_tickets(state["wallet"], data.pool_id, data.count)
            groups = {rarity: [s for s in self.catalog["ships"] if s["rarity"] == rarity and _recruitable(s)]
                      for rarity in ("common", "elite", "rare")}
            if not all(groups.values()):
                deny("征募目录尚未准备完整。", 503)
            draw = state["draw"]
            receipts = []
            index = max((r["index"] for r in draw["history"]), default=0)
            batch = index + 1
            now = int(time.time() * 1000)
            for _ in range(data.count):
                if draw["since_rare"] >= 39:
                    rarity = "rare"
                elif draw["since_elite"] >= 9:
                    rarity = "elite" if self._random() < .8 else "rare"
                else:
                    number = self._random()
                    rarity = "common" if number < .75 else "elite" if number < .95 else "rare"
                group = groups[rarity]
                ship = group[int(self._random() * len(group))]
                duplicate = ship["id"] in state["owned_ships"]
                if duplicate:
                    state["wallet"]["medals"] += DUPLICATE_MEDALS[rarity]
                else:
                    state["owned_ships"].append(ship["id"])
                draw["since_elite"] = draw["since_elite"] + 1 if rarity == "common" else 0
                draw["since_rare"] = 0 if rarity == "rare" else draw["since_rare"] + 1
                draw["exchange_points"] += 1
                index += 1
                receipt = {"id": "draw:" + str(index), "ship_id": ship["id"], "rarity": rarity, "duplicate": duplicate, "time": now, "index": index, "batch": batch}
                receipts.append(receipt)
                draw["history"].append(receipt)
            state["transactions"].append({"id": data.request_id, "title": f"常驻征募{data.count}次", "time": now})
            return {"receipts": receipts}
        return self.mutate(account_id, data.request_id, "recruit", data.model_dump(exclude={"pool_id"}) if data.pool_id is None else data.model_dump(), action)

    def prologue_gift(self, account_id, data: PrologueClaim):
        def action(conn, state):
            if data.leader_id not in PROLOGUE_SHIPS:
                deny("请从五艘序章驱逐舰中选择领舰。")
            reward = {"id": "prologue-v1", "title": "未明的海 · 序章见面礼", "credits": 2000,
                      "up_tickets": 10, "standard_tickets": 10,
                      "ship_ids": PROLOGUE_SHIPS, "ai_profiles": ["rc_coordinated"]}
            claimed = grant(state, reward, int(time.time() * 1000))
            return {"claimed": claimed, "reward": reward, "gift_kind": "fixed-starter-gift", "practice_verified": False}
        return self.mutate(account_id, data.request_id, "prologue-gift", data.model_dump(), action)

    def recruit_pool(self, account_id, data: Recruit):
        def action(conn, state):
            pool = next((p for p in self.catalog.get("recruit_pools", []) if p["id"] == data.pool_id), None)
            if not pool:
                deny("找不到该征募池。")
            _spend_recruit_tickets(state["wallet"], pool["id"], data.count)
            ships = {s["id"]: s for s in self.catalog["ships"] if _recruitable(s)}
            groups = {r: [s for s in ships.values() if s["rarity"] == r] for r in ("common", "elite", "rare")}
            featured_id = pool.get("featured_ship_id")
            off_banner_ids = [sid for sid in dict.fromkeys(pool["ur_ship_ids"])
                              if sid != featured_id and ships.get(sid, {}).get("rarity") == "ur"]
            if (not all(groups.values()) or not off_banner_ids
                    or (featured_id and ships.get(featured_id, {}).get("rarity") != "ur")):
                deny("征募目录尚未准备完整。", 503)
            draw = state.setdefault("pools", {}).setdefault(pool["id"], {"since_elite": 0, "since_rare": 0, "since_ur": 0, "exchange_points": 0, "up_guaranteed": False, "history": []})
            receipts, now = [], int(time.time() * 1000)
            index = max((r["index"] for r in draw["history"]), default=0)
            batch = index + 1
            for _ in range(data.count):
                if draw["since_ur"] >= pool["pity"]["ur"] - 1:
                    rarity = "ur"
                elif draw["since_rare"] >= pool["pity"]["rare"] - 1:
                    rarity = "rare" if self._random() < .6 else "ur"
                elif draw["since_elite"] >= pool["pity"]["elite"] - 1:
                    n = self._random()
                    rarity = "elite" if n < .8 else "rare" if n < .92 else "ur"
                else:
                    n = self._random()
                    rarity = "common" if n < .75 else "elite" if n < .95 else "rare" if n < .98 else "ur"
                if rarity == "ur":
                    featured = featured_id and (draw["up_guaranteed"] or self._random() < .5)
                    ids = [featured_id] if featured else off_banner_ids
                    ship = ships[ids[int(self._random() * len(ids))]]
                    draw["up_guaranteed"] = pool["kind"] == "up" and ship["id"] != featured_id
                else:
                    group = groups[rarity]
                    ship = group[int(self._random() * len(group))]
                duplicate = ship["id"] in state["owned_ships"]
                if duplicate:
                    state["wallet"]["medals"] += DUPLICATE_MEDALS[rarity]
                else:
                    state["owned_ships"].append(ship["id"])
                draw["since_elite"] = draw["since_elite"] + 1 if rarity == "common" else 0
                draw["since_rare"] = 0 if rarity in ("rare", "ur") else draw["since_rare"] + 1
                draw["since_ur"] = 0 if rarity == "ur" else draw["since_ur"] + 1
                draw["exchange_points"] += 1
                index += 1
                receipt = {"id": f"pool:{pool['id']}:{index}", "pool_id": pool["id"], "ship_id": ship["id"], "rarity": rarity, "duplicate": duplicate, "time": now, "index": index, "batch": batch}
                receipts.append(receipt)
                draw["history"].append(receipt)
            state["transactions"].append({"id": data.request_id, "title": pool["name"] + f"征募{data.count}次", "time": now})
            return {"receipts": receipts, "pool_id": pool["id"]}
        return self.mutate(account_id, data.request_id, "recruit", data.model_dump(), action)

    def purchase(self, account_id, data: Purchase):
        def action(conn, state):
            now = int(time.time() * 1000)
            if data.kind == "ship_bundle":
                if data.currency != "credits" or data.pool_id is not None:
                    deny("舰船礼包仅使用补给币。")
                bundle = next((item for item in self.catalog.get("ship_bundles", []) if item["id"] == data.item_id), None)
                if bundle is None:
                    deny("礼包不存在或已下架。", 404)
                key = "shop:ship-bundle:" + bundle["id"]
                if key in state["claims"]:
                    deny("该礼包已购买。", 409)
                ship_ids, price = bundle["ship_ids"], bundle["credits"]
                definitions = {ship["id"]: ship for ship in self.catalog["ships"]}
                if (type(price) is not int or price <= 0 or len(ship_ids) != 3 or len(set(ship_ids)) != 3
                        or any(sid not in definitions or not _recruitable(definitions[sid]) for sid in ship_ids)):
                    deny("礼包内容暂不可用。", 503)
                if all(sid in state["owned_ships"] for sid in ship_ids):
                    deny("礼包内三艘舰船均已拥有。", 409)
                if state["wallet"]["credits"] < price:
                    deny(f"补给币不足，还差{price - state['wallet']['credits']}。")
                state["wallet"]["credits"] -= price
                state["claims"].append(key)
                receipts = []
                for index, sid in enumerate(ship_ids, start=1):
                    rarity = definitions[sid]["rarity"]
                    duplicate = sid in state["owned_ships"]
                    if duplicate:
                        state["wallet"]["medals"] += DUPLICATE_MEDALS[rarity]
                    else:
                        state["owned_ships"].append(sid)
                    receipts.append({"id": f"{key}:{index}", "ship_id": sid, "rarity": rarity, "duplicate": duplicate})
                state["transactions"].append({"id": data.request_id, "title": "礼包入列：" + bundle["name"], "time": now})
                return {"purchased": True, "kind": data.kind, "item_id": bundle["id"], "receipts": receipts}
            if data.kind == "pool_ship":
                pool = next((p for p in self.catalog.get("recruit_pools", []) if p["id"] == data.pool_id), None)
                if not pool or data.currency != "exchange_points":
                    deny("请选择该池的UR进度兑换商品。")
                allowed = pool["ur_ship_ids"] + ([pool["featured_ship_id"]] if pool.get("featured_ship_id") else [])
                if data.item_id not in allowed or data.item_id in state["owned_ships"]:
                    deny("不在此池兑换目录或已永久拥有。")
                ship = next((s for s in self.catalog["ships"] if s["id"] == data.item_id), None)
                if not ship or ship["rarity"] != "ur" or not _recruitable(ship):
                    deny("此舰通过战役等指定奖励获得。")
                draw = state.get("pools", {}).get(pool["id"])
                if not draw or draw["exchange_points"] < pool["exchange_price"]:
                    deny("该池招募进度不足。")
                draw["exchange_points"] -= pool["exchange_price"]
                state["owned_ships"].append(data.item_id)
                state["transactions"].append({"id": data.request_id, "title": "指定UR入列", "time": now})
                return {"purchased": True, "kind": data.kind, "item_id": data.item_id, "pool_id": pool["id"]}
            if data.kind == "weekly_ticket":
                if data.currency != "credits" or data.item_id:
                    deny("每周券商品参数不正确。")
                week = beijing_week(now)
                key = "shop:weekly-ticket:" + week["key"]
                legacy_key = "shop:weekly-ticket:" + str(week["monday_day"])
                if key in state["claims"] or legacy_key in state["claims"]:
                    deny("本周征募券已兑换。")
                currency, price, title = "credits", 500, "每周补给征募券"
            elif data.kind == "ai":
                ai = next((a for a in self.catalog["ai_profiles"] if a["id"] == data.item_id), None)
                if not ai or data.currency != "credits" or not ai.get("cost"):
                    deny("该战术不能通过此商品购买。")
                if ai["id"] in state["ai_profiles"]:
                    deny("已拥有该战术。")
                currency, price, title = "credits", ai["cost"], "解锁战术：" + ai["name"]
            else:
                ship = next((s for s in self.catalog["ships"] if s["id"] == data.item_id), None)
                if not ship:
                    deny("商品不存在。", 404)
                if not _recruitable(ship):
                    deny("此舰通过战役等指定奖励获得。")
                if ship["id"] in state["owned_ships"]:
                    deny("已永久拥有该舰。")
                currency = data.currency
                if currency == "credits" and ship["rarity"] != "common":
                    deny("补给币只用于直购普通舰。")
                if currency == "exchange_points" and ship["rarity"] != "rare":
                    deny("80点招募进度用于指定兑换稀有舰。")
                price = ship["credits_price"] if currency == "credits" else MEDAL_PRICES[ship["rarity"]] if currency == "medals" else 80
                title = "兑换舰船：" + ship["name"]
            source = state["draw"] if currency == "exchange_points" else state["wallet"]
            if source[currency] < price:
                deny("资源不足。")
            source[currency] -= price
            if data.kind == "weekly_ticket":
                state["wallet"]["standard_tickets"] += 1
                state["claims"].append(key)
            elif data.kind == "ai":
                state["ai_profiles"].append(ai["id"])
            else:
                state["owned_ships"].append(ship["id"])
            state["transactions"].append({"id": data.request_id, "title": title, "time": now})
            return {"purchased": True, "kind": data.kind, "item_id": data.item_id}
        return self.mutate(account_id, data.request_id, "purchase", data.model_dump(exclude={"pool_id"}) if data.pool_id is None else data.model_dump(), action)

def create_app(db_path: str | Path | None = None, catalog_path: str | Path = CATALOG_FILE, *,
               sim_path: str | Path | None = None, clock_ms=None, seed_source=None,
               check_in_clock_ms=None, enable_duels: bool | None = None,
               ranked_points_path: str | Path | None = None) -> FastAPI:
    service = AccountService(db_path or os.environ.get("CAS_ACCOUNT_DB", DEFAULT_DB), catalog_path)
    from .account_progression import AccountProgression, mount as mount_progression
    from .battle_pve import CampaignService, NativeCore, mount
    from .duels import DuelService, mount as mount_duels
    from .fleets import FleetService, mount as mount_fleets
    from .rankings import PointTable
    configured_sim = sim_path or os.environ.get("CAS_SIM_PATH")
    core = NativeCore(Path(configured_sim)) if configured_sim else None
    pve = CampaignService(service, core, clock_ms=clock_ms, seed_source=seed_source) if core else None
    want_duels = os.environ.get("CAS_ENABLE_DUELS") == "1" if enable_duels is None else enable_duels
    if want_duels and core is None:
        raise ValueError("CAS_ENABLE_DUELS requires CAS_SIM_PATH")
    if ranked_points_path is None and os.environ.get("CAS_ENABLE_RANKED") == "1":
        ranked_points_path = os.environ.get("CAS_RANKED_POINTS")
        if not ranked_points_path:
            raise ValueError("CAS_ENABLE_RANKED requires CAS_RANKED_POINTS")
    if ranked_points_path and not want_duels:
        raise ValueError("CAS ranked matches require the native duel service")
    points = PointTable(ranked_points_path, service.catalog, PROLOGUE_SHIPS) if ranked_points_path else None
    duels = DuelService(service, core, clock_ms=clock_ms, seed_source=seed_source, points=points) if want_duels else None

    @asynccontextmanager
    async def lifespan(_app):
        with closing(service.connect()):
            pass
        if pve:
            pve.verify_installation()
        if duels:
            duels.initialize()
        yield

    app = FastAPI(title="CAS 账号与免费经济测试服务", version="0.1.0", lifespan=lifespan)
    app.add_middleware(CORSMiddleware,
                       allow_origins=["https://appassets.androidplatform.net", "https://cas-stage0.example"]
                       + [o.strip() for o in os.environ.get("CAS_ACCOUNT_ORIGINS", "").split(",") if o.strip()],
                       allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?",
                       allow_methods=["GET", "POST"], allow_headers=["Authorization", "Content-Type"])
    app.state.accounts = service

    def account(authorization: str | None = Header(default=None)):
        return service.authenticate(authorization)

    app.state.require_account = account
    mount_progression(app, AccountProgression(service, check_in_clock_ms), account)
    mount_fleets(app, FleetService(service, points=points), account)
    if pve:
        mount(app, pve, account)
    if duels:
        mount_duels(app, duels, account)

    @app.get("/health")
    def health():
        return {"ready": True, "version": "0.1.0", "real_payments": False, "ranked_pvp": points is not None,
                "pvp_available": duels is not None, "pve_available": pve is not None, "asset_source": "server",
                "service": "cas-free-economy", "economy_version": service.catalog["version"],
                "starter_gifts_verify_practice": False, "fleet_presets_available": True,
                "fleet_point_table_available": points is not None,
                "ranked_budgets": list(points.budgets) if points else []}

    @app.post("/auth/register")
    def register(data: Credentials):
        return service.register(data)

    @app.post("/auth/login")
    def login(data: Credentials):
        return service.login(data)

    @app.post("/auth/logout")
    def logout(account_id: str = Depends(account), authorization: str | None = Header(default=None)):
        with service.write() as conn:
            conn.execute("DELETE FROM sessions WHERE token_hash=?", (hashlib.sha256(authorization[7:].encode()).hexdigest(),))
        return {"logged_out": True}

    @app.get("/catalog")
    def catalog():
        return service.catalog

    @app.get("/me")
    def me(account_id: str = Depends(account)):
        return {"account_id": account_id, "meta": service.meta(account_id)}

    @app.get("/me/ledger")
    def ledger(account_id: str = Depends(account)):
        with closing(service.connect()) as conn:
            rows = conn.execute("SELECT id,request_id,operation,change_json,created FROM ledger WHERE account_id=? ORDER BY id DESC LIMIT 100", (account_id,)).fetchall()
        return [{"id": r["id"], "request_id": r["request_id"], "operation": r["operation"], "change": json.loads(r["change_json"]), "time": r["created"]} for r in rows]

    @app.get("/mail")
    def mail(account_id: str = Depends(account)):
        return service.mail(account_id)

    @app.post("/mail/{message_id}/claim")
    def claim_mail(message_id: str, data: Mutation | None = None, account_id: str = Depends(account)):
        return service.claim_mail(account_id, message_id)

    @app.post("/starter-gifts/claim")
    def starter_gift(data: GiftClaim, account_id: str = Depends(account)):
        return service.starter_gift(account_id, data)

    @app.post("/prologue/claim")
    def prologue_gift(data: PrologueClaim, account_id: str = Depends(account)):
        return service.prologue_gift(account_id, data)

    @app.post("/recruit")
    def recruit(data: Recruit, account_id: str = Depends(account)):
        return service.recruit(account_id, data)

    @app.get("/missions/weekly-pve")
    def weekly_pve(account_id: str = Depends(account)):
        return service.weekly_pve_status(account_id)

    @app.post("/missions/weekly-pve/claim")
    def claim_weekly_pve(data: Mutation, account_id: str = Depends(account)):
        return service.claim_weekly_pve(account_id, data)

    @app.post("/shop/purchase")
    def purchase(data: Purchase, account_id: str = Depends(account)):
        return service.purchase(account_id, data)

    return app


app = create_app()
