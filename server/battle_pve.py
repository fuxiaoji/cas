"""Seat-bound authority for the local CAS Cape St. George PvE trial."""
from __future__ import annotations

from contextlib import closing
from hashlib import sha256
import json
from pathlib import Path
import secrets
import subprocess
import time
from typing import Annotated, Literal, TYPE_CHECKING

from fastapi import Depends, FastAPI, Path as RoutePath
from pydantic import Field

from .contracts import Mutation, StrictModel, deny, encode

if TYPE_CHECKING:
    from .accounts import AccountService


RULE_VERSIONS = ("cas-campaign-v5", "cas-campaign-v6", "cas-campaign-v7", "cas-campaign-v8", "cas-campaign-v9")
SIM_TICK_MS = 250  # 4×; the client never supplies elapsed time.
MAX_TICKS = 120
MAX_ACTIVE = 4
MAX_ORDERS = 1000
PIPE_DEADLINE = 4
VIEW_KEYS = set("""tick limit width height side scenario variant settling realtimeGunnery environment
campaign ships fleets contacts radarContacts illuminations torpedoes shells events result islands version torpedoDepths""".split())
STARS = {"none": 0, "tactical": 2, "decisive": 3}
REWARDS = (
    ("CLEAR", "首通补给", {"credits": 400, "tickets": 1}),
    ("STAR2", "保存舰队", {"credits": 200, "tickets": 1}),
    ("STAR3", "战术星章", {"tickets": 2, "medals": 10}),
)
AI_UNLOCK = {"gunnery": "fleet", "torpedo": "rc_torpedo_wings"}
Stage = Literal["CAMP-ALLIES-03", "CAMP-AXIS-03"]
Difficulty = Literal["story", "standard", "challenge"]
UnitId = Annotated[int, Field(gt=0, le=10000)]
ContactId = Annotated[str, Field(min_length=1, max_length=24, pattern=r"^[A-Za-z0-9_.:-]+$")]
Heading = Annotated[float, Field(ge=0, le=360, allow_inf_nan=False)]


class Launch(Mutation):
    stage_id: Stage
    difficulty: Difficulty


class Point(StrictModel):
    x: float = Field(ge=0, le=64000, allow_inf_nan=False)
    y: float = Field(ge=0, le=40000, allow_inf_nan=False)


class Course(StrictModel):
    fleet: UnitId
    mode: Literal["follow", "sync"]
    speed: float | None = Field(default=None, gt=0, le=60, allow_inf_nan=False)
    points: list[Point] = Field(min_length=1, max_length=10)


class Route(Course):
    op: Literal["route"]


class PreviewCourse(Course):
    op: Literal["preview_route"]


class WeaponTarget(StrictModel):
    ship: UnitId
    weapon: Literal["gun", "torpedo"]
    target: ContactId
    heading: Heading | None = None
    depth: Literal["shallow", "deep"] | None = None
    mount: int | None = Field(default=None, ge=0, le=64)
    count: int | None = Field(default=None, ge=1, le=6)


class Fire(WeaponTarget):
    op: Literal["fire"]


class Aim(WeaponTarget):
    op: Literal["aim"]


class ShipCommand(StrictModel):
    op: Literal["gun_cancel"]
    ship: UnitId


class ShipWithFleet(StrictModel):
    op: Literal["lead", "detach"]
    ship: UnitId
    fleet: UnitId


class Reform(StrictModel):
    op: Literal["reform"]
    fleet: UnitId


class FleetInspection(StrictModel):
    op: Literal["preview_reform", "suggest"]
    fleet: UnitId


class AI(StrictModel):
    op: Literal["ai"]
    fleet: UnitId
    profile: Literal["coord", "gunnery", "torpedo"]
    mode: Literal["manual", "suggest", "auto"]
    move: bool
    gun: bool
    torpedo: bool


class Radar(StrictModel):
    op: Literal["radar_set"]
    ship: UnitId
    radar: Annotated[str, Field(pattern=r"^[a-z][a-z0-9_]{0,40}$")]
    powered: bool


class Illuminate(StrictModel):
    op: Literal["illuminate"]
    ship: UnitId
    target: ContactId


class LightPreview(StrictModel):
    op: Literal["illumination_preview"]
    ship: UnitId
    target: ContactId


class Order(Mutation):
    revision: int = Field(ge=0, le=MAX_ORDERS)
    command: Annotated[Route | Fire | ShipCommand | ShipWithFleet | Reform | AI | Radar | Illuminate,
                       Field(discriminator="op")]


class Inspect(StrictModel):
    command: Annotated[PreviewCourse | Aim | FleetInspection | LightPreview, Field(discriminator="op")]


class NativeCore:
    def __init__(self, path: Path):
        self.path = path.resolve(strict=True)
        self.stat = self.signature()
        digest = sha256()
        with self.path.open("rb") as binary:
            for block in iter(lambda: binary.read(1024 * 1024), b""):
                digest.update(block)
        self.sha256 = digest.hexdigest()

    def signature(self):
        stat = self.path.stat()
        return (stat.st_mtime_ns, stat.st_size)

    def request(self, *ops):
        """Each bounded request owns a child process; run kills and waits on timeout."""
        try:
            if self.signature() != self.stat:
                deny("原生内核已变更，请重启本机服务。", 503)
            raw = ("\n".join(encode(op) for op in ops) + "\n").encode("utf-8")
            run = subprocess.run([str(self.path)], input=raw, capture_output=True, timeout=PIPE_DEADLINE,
                                 creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            if run.returncode != 0 or len(run.stdout) > 2_000_000:
                deny("原生战斗未返回有效结果。", 503)
            result = [json.loads(line) for line in run.stdout.decode("utf-8").splitlines()]
        except subprocess.TimeoutExpired:
            deny("原生战斗响应超时，本次未提交。", 504)
        except (OSError, UnicodeError, ValueError):
            deny("无法读取原生战斗，本次未提交。", 503)
        if len(result) != len(ops) or any(not isinstance(row, dict) or type(row.get("ok")) is not bool for row in result):
            deny("原生战斗协议不匹配。", 503)
        return result


def verified(response):
    if not response["ok"] or "data" not in response:
        deny("原生战斗版本或服务器存档不匹配。", 503)
    return response["data"]


def player_response(response):
    if not response["ok"]:
        deny(str(response.get("error", "命令不可用"))[:200], 409)
    return verified(response)


def projected_view(raw, stage, difficulty):
    seat = "allies" if stage == "CAMP-ALLIES-03" else "axis"
    if (raw.get("version") not in RULE_VERSIONS or raw.get("side") != seat or not isinstance(raw.get("tick"), int)
            or raw.get("campaign", {}).get("stageId") != stage or raw["campaign"].get("difficulty") != difficulty):
        deny("原生战斗未返回指定席位的观察。", 503)
    return {k: v for k, v in raw.items() if k in VIEW_KEYS}


class CampaignService:
    def __init__(self, accounts: AccountService, core: NativeCore, *, clock_ms=None, seed_source=None):
        self.accounts = accounts
        self.core = core
        self.clock_ms = clock_ms or (lambda: time.time_ns() // 1_000_000)
        self.seed_source = seed_source or (lambda: secrets.randbits(32))

    def verify_installation(self):
        for stage in ("CAMP-ALLIES-03", "CAMP-AXIS-03"):
            response, = self.core.request({"op": "new_campaign", "id": stage, "difficulty": "story", "seed": 6106})
            view = projected_view(verified(response), stage, "story")
            if view["tick"] != 0 or len(view["ships"]) != 5:
                raise ValueError("Native Cape St. George cannot initialize both player seats")

    def _row(self, conn, account_id, battle_id):
        row = conn.execute("SELECT * FROM pve_battles WHERE id=? AND account_id=?", (battle_id, account_id)).fetchone()
        if not row:
            deny("本账号没有此对局。", 404)
        return row

    def _load(self, row):
        if row["core_sha"] != self.core.sha256:
            deny("此战局需要开局时冻结的原生内核。", 409)
        return {"op": "load", "save": json.loads(row["snapshot"])}

    @staticmethod
    def _summary(row):
        view = json.loads(row["view"])
        return {"battle_id": row["id"], "stage_id": row["stage_id"], "difficulty": row["difficulty"],
                "revision": row["revision"], "status": "active" if row["completed_at"] is None else "complete",
                "tick": view["tick"], "result": view["result"]}

    def _public(self, row):
        return {**self._summary(row), "view": json.loads(row["view"])}

    @staticmethod
    def _pve_progress(state, row, view):
        stage = row["stage_id"]
        history = state.setdefault("campaign_progress", {}).setdefault(stage, {"best": {}, "claimed": 0})
        difficulty, stars = row["difficulty"], STARS[view["result"]["grade"]]
        history["best"][difficulty] = max(history["best"].get(difficulty, 0), stars)

    def start(self, account_id, data):
        def launch(conn, _state):
            active = conn.execute("SELECT COUNT(*) FROM pve_battles WHERE account_id=? AND completed_at IS NULL",
                                  (account_id,)).fetchone()[0]
            if active >= MAX_ACTIVE:
                deny("请先完成已有对局。", 409)
            seed = self.seed_source()
            start, save = self.core.request({"op": "new_campaign", "id": data.stage_id, "difficulty": data.difficulty,
                                              "seed": seed, "profile": "coord"}, {"op": "save"})
            view = projected_view(verified(start), data.stage_id, data.difficulty)
            snapshot = verified(save)
            if snapshot.get("seed") != seed or snapshot.get("tick") != 0 or view["tick"] != 0:
                deny("原生战斗没有确认服务器的开局参数。", 503)
            battle_id, now = "cape-" + secrets.token_hex(16), self.clock_ms()
            conn.execute("""INSERT INTO pve_battles
                (id,account_id,stage_id,difficulty,core_sha,revision,clock_ms,created_at,snapshot,view)
                VALUES(?,?,?,?,?,0,?,?,?,?)""", (battle_id, account_id, data.stage_id, data.difficulty, self.core.sha256,
                                                 now, now, encode(snapshot), encode(view)))
            return self._public(self._row(conn, account_id, battle_id))
        return self._mutation(account_id, data.request_id, "battle-start", data.model_dump(), launch)

    def _refresh(self, account_id, battle_id):
        def owed(row, now):
            return min(MAX_TICKS, max(0, now - row["clock_ms"]) // SIM_TICK_MS)
        with closing(self.accounts.connect()) as conn:
            row = self._row(conn, account_id, battle_id)
            if row["completed_at"] is not None or not owed(row, self.clock_ms()):
                return row
        with self.accounts.write() as conn:
            row = self._row(conn, account_id, battle_id)
            elapsed = owed(row, self.clock_ms())
            if row["completed_at"] is not None or not elapsed:
                return row
            loaded, step, save, report = self.core.request(
                self._load(row), {"op": "step", "seconds": elapsed}, {"op": "save"}, {"op": "report"})
            before = projected_view(verified(loaded), row["stage_id"], row["difficulty"])
            view = projected_view(verified(step), row["stage_id"], row["difficulty"])
            snapshot, evidence = verified(save), verified(report)
            delta = view["tick"] - before["tick"]
            final = evidence.get("result")
            if (not 1 <= delta <= elapsed or view["tick"] != snapshot.get("tick") or final != view.get("result")
                    or (final is not None and final.get("grade") not in STARS)):
                deny("原生战斗推进或结算结果不一致。", 503)
            advanced_clock = row["clock_ms"] + delta * SIM_TICK_MS
            conn.execute("UPDATE pve_battles SET clock_ms=?,snapshot=?,view=?,report=?,completed_at=? WHERE id=?",
                         (advanced_clock, encode(snapshot), encode(view), encode(evidence) if final is not None else None,
                          advanced_clock if final is not None else None, battle_id))
            if final is not None:
                state = json.loads(conn.execute("SELECT state FROM assets WHERE account_id=?", (account_id,)).fetchone()["state"])
                self._pve_progress(state, row, view)
                if STARS[final["grade"]]:
                    self.accounts.record_authoritative_pve_clear(conn, state, account_id, battle_id, advanced_clock)
                conn.execute("UPDATE assets SET state=? WHERE account_id=?", (encode(state), account_id))
            return self._row(conn, account_id, battle_id)

    def _mutation(self, account_id, request_id, op, payload, action, *, include_meta=False):
        return self.accounts.mutate(account_id, request_id, op, payload, action, mutates_assets=include_meta)

    def list(self, account_id):
        with closing(self.accounts.connect()) as conn:
            rows = conn.execute("""SELECT * FROM pve_battles WHERE account_id=?
                ORDER BY (completed_at IS NULL) DESC,created_at DESC,id DESC LIMIT 50""", (account_id,))
            return [self._summary(row) for row in rows]

    def view(self, account_id, battle_id):
        return self._public(self._refresh(account_id, battle_id))

    def order(self, account_id, battle_id, data):
        self._refresh(account_id, battle_id)

        def execute(conn, state):
            row = self._row(conn, account_id, battle_id)
            if row["completed_at"] is not None or row["revision"] != data.revision or row["revision"] >= MAX_ORDERS:
                deny("本方对局已结束、超过命令上限或修订号变化，请刷新。", 409)
            cmd = data.command.model_dump(exclude_none=True)
            required = AI_UNLOCK.get(cmd.get("profile"))
            if required and required not in state["ai_profiles"]:
                deny("请先解锁此指挥风格。", 403)
            loaded, result, save = self.core.request(self._load(row), cmd, {"op": "save"})
            before = projected_view(verified(loaded), row["stage_id"], row["difficulty"])
            view = projected_view(player_response(result), row["stage_id"], row["difficulty"])
            snapshot = verified(save)
            if view["tick"] != before["tick"] or snapshot.get("tick") != before["tick"]:
                deny("命令结果未在同一模拟秒提交。", 503)
            conn.execute("UPDATE pve_battles SET revision=revision+1,snapshot=?,view=? WHERE id=?",
                         (encode(snapshot), encode(view), battle_id))
            return self._public(self._row(conn, account_id, battle_id))
        return self._mutation(account_id, data.request_id, "battle-command",
                              {"battle_id": battle_id, **data.model_dump()}, execute)

    def inspect(self, account_id, battle_id, data):
        row = self._refresh(account_id, battle_id)
        first, response = self.core.request(self._load(row), data.command.model_dump(exclude_none=True))
        projected_view(verified(first), row["stage_id"], row["difficulty"])
        return player_response(response)

    def report(self, account_id, battle_id):
        row = self._refresh(account_id, battle_id)
        if row["report"] is not None:
            evidence = json.loads(row["report"])
        else:
            first, report = self.core.request(self._load(row), {"op": "report"})
            projected_view(verified(first), row["stage_id"], row["difficulty"])
            evidence = verified(report)
        return {"result": evidence["result"], "events": evidence["events"]}

    def claim(self, account_id, battle_id, data):
        from .accounts import grant

        self._refresh(account_id, battle_id)

        def claim(conn, state):
            row = self._row(conn, account_id, battle_id)
            if row["completed_at"] is None or row["report"] is None:
                deny("对局尚未完成服务器裁决。", 409)
            grade = json.loads(row["report"])["result"]["grade"]
            stars, rewards = STARS[grade], []
            for suffix, title, assets in REWARDS[:stars]:
                reward = {"id": f"{row['stage_id']}-{suffix}", "title": title, **assets}
                if grant(state, reward, self.clock_ms()):
                    rewards.append(reward)
            stage = state["campaign_progress"][row["stage_id"]]
            stage["claimed"] = max(stars, stage["claimed"])
            return {"battle_id": battle_id, "grade": grade, "stars": stars, "claimed": bool(rewards), "rewards": rewards}
        return self._mutation(account_id, data.request_id, "battle-claim",
                              {"battle_id": battle_id, **data.model_dump()}, claim, include_meta=True)


BattleId = Annotated[str, RoutePath(pattern=r"^cape-[a-f0-9]{32}$")]


def mount(app: FastAPI, service: CampaignService, account):
    @app.post("/battles")
    def start(data: Launch, account_id: str = Depends(account)):
        return service.start(account_id, data)

    @app.get("/battles")
    def list_battles(account_id: str = Depends(account)):
        return service.list(account_id)

    @app.get("/battles/{battle_id}")
    def view(battle_id: BattleId, account_id: str = Depends(account)):
        return service.view(account_id, battle_id)

    @app.post("/battles/{battle_id}/commands")
    def order(battle_id: BattleId, data: Order, account_id: str = Depends(account)):
        return service.order(account_id, battle_id, data)

    @app.post("/battles/{battle_id}/inspect")
    def inspect(battle_id: BattleId, data: Inspect, account_id: str = Depends(account)):
        return service.inspect(account_id, battle_id, data)

    @app.get("/battles/{battle_id}/report")
    def report(battle_id: BattleId, account_id: str = Depends(account)):
        return service.report(account_id, battle_id)

    @app.post("/battles/{battle_id}/claim")
    def claim(battle_id: BattleId, data: Mutation, account_id: str = Depends(account)):
        return service.claim(account_id, battle_id, data)
