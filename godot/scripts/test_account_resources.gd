extends RefCounted
## Explicit opt-in on one existing test profile; normal new accounts stay unchanged.
const MARKER: String = "cas-local-qa-2026-11-12"
const GRANT_VERSION: String = "cas-test-resources-2026-11-13"
const WALLET_FLOORS: Dictionary = {
	"credits": 999999999, "origins": 999999999,
	"ammo_stock": 999999999, "fuel": 999999999,
	"tickets": 999999, "up_tickets": 999999, "medals": 999999,
	"materials": 999999, "training_t2": 999999, "training_t3": 999999,
	"core_t1": 999999, "core_t2": 999999, "core_t3": 999999,
	"tide_tokens": 999999,
}
# Equipment/command counts describe actual instances. Inflating them would cause
# Meta.ensure() to manufacture equipment/crew and mutate the player's possessions.
const INVENTORY_FLOORS: Dictionary = {"scrap": 999999, "alloy": 999999}

static func apply(account, mark: bool = false) -> Dictionary:
	if account.state.is_empty():
		return account._fail("测试档案未载入")
	if not mark and str(account.state.get("test_account", "")) != MARKER:
		return {"ok": true, "skipped": true}
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/meta-economy.json"))
	var stamina_max: int = int(meta.get("stamina_max", 0))
	if stamina_max <= 0:
		return account._fail("无法确认体力上限，测试补给未生效")
	# Read only the resource schema: account.wallet() also runs asset migrations.
	var changed: bool = str(account.state.get("test_account", "")) != MARKER
	for currency in WALLET_FLOORS:
		changed = changed or int(account.state.wallet.get(currency, 0)) < int(WALLET_FLOORS[currency])
	for material in INVENTORY_FLOORS:
		changed = changed or int(account.state.inventory.get(material, 0)) < int(INVENTORY_FLOORS[material])
	changed = changed or int(account.state.get("stamina", {}).get("value", 0)) < stamina_max
	if not changed:
		return {"ok": true, "unchanged": true, "message": "测试账号补给已满"}
	var before: Dictionary = account.state.duplicate(true)
	account.state["test_account"] = MARKER
	for currency in WALLET_FLOORS:
		account.state.wallet[currency] = maxi(int(account.state.wallet.get(currency, 0)), int(WALLET_FLOORS[currency]))
	for material in INVENTORY_FLOORS:
		account.state.inventory[material] = maxi(int(account.state.inventory.get(material, 0)), int(INVENTORY_FLOORS[material]))
	var now: int = int(Time.get_unix_time_from_system())
	account.state.stamina = {"value": stamina_max, "at": now}
	account.state["test_resource_grant"] = {
		"version": GRANT_VERSION, "at": now,
		"scope": "explicit local profile only; preserve ships, growth, fleets, progress, actual items and complete active_run",
	}
	return account._commit(before, "测试账号补给已补满")
