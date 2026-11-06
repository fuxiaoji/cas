"""Account-owned fleet presets and the migrated 3000/10000 composition checks."""
from __future__ import annotations

from typing import Annotated, Literal, TYPE_CHECKING
import unicodedata

from fastapi import Depends, FastAPI, Path
from pydantic import Field

from .contracts import Mutation, StrictModel, deny

if TYPE_CHECKING:
    from .accounts import AccountService


# Product limits from IBS mobile/progression.py and mobile/src/fleet/ranked.ts.
# The reference point costs and combat profile modes are separate from these.
RANKED_BUDGETS = (3000, 10000)
ESCORTS = frozenset({"DD", "CL", "CA"})
PRESET_LIMIT = 32
ID_PATTERN = r"^[A-Za-z0-9][A-Za-z0-9_.:-]*$"
SHIP_PATTERN = r"^IBS-U-[A-Z0-9]+(?:-[A-Z0-9]+)*$"

FleetId = Annotated[str, Field(min_length=1, max_length=100, pattern=ID_PATTERN)]
FleetPathId = Annotated[str, Path(min_length=1, max_length=100, pattern=ID_PATTERN)]
ShipId = Annotated[str, Field(min_length=8, max_length=100, pattern=SHIP_PATTERN)]


class FleetData(StrictModel):
    id: FleetId
    name: str = Field(min_length=1, max_length=80)
    side: Literal["allies", "axis"]
    budget: Literal[1000, 1500, 2000, 2500, 3000, 5000, 10000]
    ship_ids: list[ShipId] = Field(min_length=1, max_length=12)
    ai_profile: Annotated[str, Field(min_length=1, max_length=80, pattern=ID_PATTERN)]
    leader_id: ShipId | None = None
    # An absent or null point-table version is the only current CAS draft shape.
    cost_version: None = None


class SaveFleet(Mutation):
    fleet: FleetData


def ranked_composition_errors(budget: int, roles: list[str]) -> list[str]:
    errors = []
    if budget == 3000:
        if not 3 <= len(roles) <= 6:
            errors.append("3000分护航战须编入3至6艘舰船")
        if any(role not in ESCORTS for role in roles):
            errors.append("3000分护航战只允许驱逐舰、轻巡洋舰和重巡洋舰")
        if roles.count("DD") < 2 or roles.count("CL") + roles.count("CA") > 2:
            errors.append("3000分护航战至少需要2艘驱逐舰，巡洋舰最多2艘")
    elif budget == 10000:
        if not 3 <= len(roles) <= 8:
            errors.append("10000分战列舰交战须编入3至8艘舰船")
        if any(role not in ESCORTS and role != "BB" for role in roles):
            errors.append("10000分战列舰交战只允许战列舰、驱逐舰、轻巡洋舰和重巡洋舰")
        if not 1 <= roles.count("BB") <= 2:
            errors.append("10000分战列舰交战需要1至2艘战列舰")
        if sum(role in ESCORTS for role in roles) < 2 or roles.count("DD") > 4:
            errors.append("10000分战列舰交战至少需要2艘护航舰，驱逐舰最多4艘")
    return errors


class FleetService:
    def __init__(self, accounts: AccountService):
        self.accounts = accounts
        self.ships = {ship["id"]: ship for ship in accounts.catalog["ships"]}

    def _entry(self, fleet):
        unavailable = [ship_id for ship_id in fleet["ship_ids"]
                       if self.ships.get(ship_id, {}).get("combat_ready") is not True]
        blockers = ["cas_personal_battle_unavailable", "cas_point_table_unavailable"]
        if unavailable:
            blockers.insert(0, "cas_ship_profile_unavailable")
        return {"fleet": fleet, "validation": {
            "structure_valid": True, "combat_ready": False, "ranked_ready": False,
            "unavailable_ship_ids": unavailable, "cost": None, "point_table_version": None,
            "blocking_reasons": blockers,
        }}

    def list(self, account_id):
        state = self.accounts.meta(account_id)
        return {"fleets": [self._entry(fleet) for fleet in state["fleets"]],
                "active_fleet_id": state["active_fleet_id"], "point_table_version": None, "ranked_available": False}

    def get(self, account_id, fleet_id):
        state = self.accounts.meta(account_id)
        fleet = next((fleet for fleet in state["fleets"] if fleet["id"] == fleet_id), None)
        if fleet is None:
            deny("本账号没有此编队预设。", 404)
        return self._entry(fleet)

    def save(self, account_id, data):
        def save(_conn, state):
            fleet = data.fleet.model_dump()
            fleet["name"] = fleet["name"].strip()
            if not fleet["name"] or any(unicodedata.category(char) == "Cc" for char in fleet["name"]):
                deny("舰队名称须为可显示的文字。")

            ship_ids = fleet["ship_ids"]
            if len(set(ship_ids)) != len(ship_ids):
                deny("同一具体舰船只能编入一次。")
            if any(ship_id not in self.ships for ship_id in ship_ids):
                deny("舰队含未知的舰船身份。")
            if not set(ship_ids).issubset(state["owned_ships"]):
                deny("舰队含尚未拥有的舰船。", 403)
            if any(self.ships[ship_id]["side"] != fleet["side"] for ship_id in ship_ids):
                deny("舰队的全部舰船须属于所选阵营。")
            if fleet["ai_profile"] not in state["ai_profiles"]:
                deny("尚未解锁该AI战术。", 403)
            leader = fleet["leader_id"] or ship_ids[0]
            if leader not in ship_ids:
                deny("领舰必须属于当前舰队。")
            fleet["leader_id"] = leader

            budget = fleet["budget"]
            if budget in RANKED_BUDGETS:
                roles = [self.ships[ship_id]["type"] for ship_id in ship_ids]
                errors = ranked_composition_errors(budget, roles)
                if errors:
                    deny("。".join(errors) + "。")
            elif budget <= 2000 and len(ship_ids) > 6:
                deny("该档位最多可编入6艘舰船。")

            fleet_id = fleet["id"]
            others = [saved for saved in state["fleets"] if saved["id"] != fleet_id]
            if len(others) >= PRESET_LIMIT:
                deny("已达到32份预设上限，可以修改已有预设。", 409)
            state["fleets"] = others + [fleet]
            state["active_fleet_id"] = fleet_id
            return {**self._entry(fleet), "active_fleet_id": fleet_id}

        return self.accounts.mutate(account_id, data.request_id, "fleet-save", data.model_dump(), save)


def mount(app: FastAPI, service: FleetService, account):
    @app.get("/fleets")
    def list_fleets(account_id: str = Depends(account)):
        return service.list(account_id)

    @app.get("/fleets/{fleet_id}")
    def get_fleet(fleet_id: FleetPathId, account_id: str = Depends(account)):
        return service.get(account_id, fleet_id)

    @app.post("/fleets")
    def save_fleet(data: SaveFleet, account_id: str = Depends(account)):
        return service.save(account_id, data)
