extends RefCounted
## Explicit, prepaid orders on existing facilities. Reads never migrate an old account.
## checkpoint() mutates only memory; call it inside the caller's account transaction,
## BEFORE changing facility HP/kind or active_run. The enclosing commit owns rollback.
const VERSION: String = "cas-home-economy-v2"
const CONFIG_PATH: String = "res://data/home-economy-v2.json"
const WALLET_KEYS: Array[String] = ["credits", "materials", "training_t2", "training_t3", "core_t1", "core_t2", "core_t3"]
var home
var account
var config: Dictionary = {}
var recipes: Dictionary = {}

class ClockFacade extends RefCounted:
	## Commit hooks must not construct HomeService, import catalogs or run ensure().
	const RESOURCE_NAMES: Dictionary = {"scrap": "浮材", "alloy": "合金", "energy": "能源", "protocols": "协议片", "credits": "岛屿补给"}
	var account
	func _init(owner) -> void: account = owner
	func state() -> Dictionary: return account.state.get("home_v1", {})
	func _idle() -> bool: return account.state.get("active_run", {}).is_empty()

static func checkpoint_account_transition(owner, before: Dictionary, at: int = -1) -> void:
	if OS.get_environment("CAS_WORLD3D") != "1": return
	var source: Variant = owner.state.get("home_v1", {})
	if not source is Dictionary or not source.get("economy_v2") is Dictionary or source.economy_v2.is_empty(): return
	var facade := ClockFacade.new(owner)
	var clock = load("res://scripts/home_economy_v2.gd").new(facade)
	clock.checkpoint_transition(before, at)

func _init(owner) -> void:
	home = owner
	account = home.account
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH)) if FileAccess.file_exists(CONFIG_PATH) else null
	if raw is Dictionary and str(raw.get("version", "")) == VERSION:
		config = raw
		for row: Dictionary in config.get("recipes", []):
			if _valid_recipe(row): recipes[str(row.id)] = row.duplicate(true)

func enabled() -> bool:
	return OS.get_environment("CAS_WORLD3D") == "1"

func _now(at: int = -1) -> int:
	return int(Time.get_unix_time_from_system()) if at < 0 else at

func _ledger() -> Dictionary:
	return home.state().get("economy_v2", {})

func _ensure() -> void:
	home.state().get_or_add("economy_v2", {"version": VERSION, "sequence": 0, "jobs": {}, "closed": {}})

func _ledger_valid() -> bool:
	var ledger: Dictionary = _ledger()
	if ledger.is_empty(): return true
	if str(ledger.get("version", "")) != VERSION or not ledger.get("jobs") is Dictionary or not ledger.get("closed") is Dictionary: return false
	if not _whole(ledger.get("sequence"), 0, 2147483647): return false
	for id: String in ledger.jobs:
		var entry: Variant = ledger.jobs[id]
		if not entry is Dictionary or str(entry.get("facility_id", "")) != id or str(entry.get("job_id", "")).is_empty() or not _valid_recipe(entry): return false
		if not _whole(entry.get("batches"), 1, 480) or int(entry.batches) * int(entry.seconds) > 28800: return false
		if not _whole(entry.get("work_seconds"), 0, int(entry.batches) * int(entry.seconds)) or not _whole(entry.get("claimed_batches"), 0, int(entry.batches)): return false
		if not _whole(entry.get("checkpoint_at"), 0, 999999999999) or not _whole(entry.get("started_at"), 0, 999999999999): return false
		if int(entry.claimed_batches) * int(entry.seconds) > int(entry.work_seconds): return false
	return true

func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum and floor(float(value)) == float(value)

func _valid_amounts(value: Variant, wallet: bool) -> bool:
	if not value is Dictionary: return false
	for key: String in value:
		if wallet and not WALLET_KEYS.has(key): return false
		if not wallet and not home.RESOURCE_NAMES.has(key): return false
		var amount: Variant = value[key]
		if not (amount is int or amount is float) or not is_finite(float(amount)) or float(amount) <= 0 or float(amount) > 100000 or floor(float(amount)) != float(amount): return false
	return true

func _valid_recipe(row: Dictionary) -> bool:
	var duration: float = float(row.get("seconds", 0))
	if str(row.get("id", "")).is_empty() or not is_finite(duration) or duration < 60 or duration > 28800 or floor(duration) != duration: return false
	if not row.get("facility_kinds") is Array or row.facility_kinds.is_empty(): return false
	for field: String in ["home_cost", "wallet_cost", "home_output", "wallet_output"]:
		if not _valid_amounts(row.get(field), field.begins_with("wallet")): return false
	if row.home_cost.is_empty() and row.wallet_cost.is_empty(): return false
	if row.home_output.is_empty() and row.wallet_output.is_empty(): return false
	# Only real, already consumed growth materials are eligible, never recruitment currency.
	var material_ids: Array[String] = ["credits"]
	var growth = load("res://data/player-growth.tres")
	for material: Dictionary in growth.materials: material_ids.append(str(material.get("id", "")))
	for key: String in row.wallet_output:
		if not material_ids.has(key): return false
	return true

func _building(id: String) -> Dictionary:
	for building: Dictionary in home.state().buildings:
		if str(building.get("id", "")) == id: return building
	return {}

func _operating(id: String, allowed: Array = []) -> bool:
	var building: Dictionary = _building(id)
	return not building.is_empty() and int(building.get("hp", 100)) > 0 and home._idle() and (allowed.is_empty() or allowed.has(str(building.get("kind", ""))))

func _multiply(value: Dictionary, count: int) -> Dictionary:
	var result: Dictionary = {}
	for key: String in value: result[key] = int(value[key]) * count
	return result

func _afford(home_cost: Dictionary, wallet_cost: Dictionary) -> bool:
	for key: String in home_cost:
		if int(home.state().resources.get(key, 0)) < int(home_cost[key]): return false
	for key: String in wallet_cost:
		if int(account.state.wallet.get(key, 0)) < int(wallet_cost[key]): return false
	return true

func _job_view(job: Dictionary, at: int) -> Dictionary:
	var result: Dictionary = job.duplicate(true)
	var duration: int = int(job.seconds)
	var work: int = clampi(int(job.get("work_seconds", 0)), 0, int(job.batches) * duration)
	if not bool(job.get("cancelled", false)) and _operating(str(job.facility_id), job.facility_kinds):
		work = mini(int(job.batches) * duration, work + maxi(0, at - int(job.checkpoint_at)))
	result.work_seconds = work
	result["completed_batches"] = mini(int(job.batches), work / duration)
	result["claimable_batches"] = maxi(0, int(result.completed_batches) - int(job.get("claimed_batches", 0)))
	result["remaining_seconds"] = maxi(0, int(job.batches) * duration - work)
	result["paused"] = not _operating(str(job.facility_id), job.facility_kinds) and work < int(job.batches) * duration
	result["pause_reason"] = "行动期间暂停加工" if not home._idle() else "设施受损或已移除" if result.paused else ""
	result["claimable_home"] = _multiply(job.home_output, int(result.claimable_batches))
	result["claimable_wallet"] = _multiply(job.wallet_output, int(result.claimable_batches))
	return result

func overview(at: int = -1) -> Dictionary:
	if not _ledger_valid(): return {"ok": false, "version": VERSION, "enabled": enabled(), "jobs": [], "recipes": [], "message": "加工账本无法校验，已保留原数据，请先修复。"}
	var rows: Array = []
	var now: int = _now(at)
	for job: Dictionary in _ledger().get("jobs", {}).values(): rows.append(_job_view(job, now))
	var choices: Array = []
	for building: Dictionary in home.state().buildings:
		for recipe: Dictionary in recipes.values():
			if recipe.facility_kinds.has(str(building.kind)):
				var row: Dictionary = recipe.duplicate(true)
				row["facility_id"] = str(building.id)
				row["facility_kind"] = str(building.kind)
				row["max_batches"] = 28800 / int(recipe.seconds)
				row["preview"] = preview(str(building.id), str(recipe.id), 1, now)
				choices.append(row)
	return {"ok": true, "version": VERSION, "enabled": enabled(), "jobs": rows, "recipes": choices, "max_order_seconds": 28800, "scope": "每座设施一个预付订单；最多8小时批量，完成后停止，不自动续单。行动中暂停。"}

func preview(facility_id: String, recipe_id: String, batches: int = 1, at: int = -1) -> Dictionary:
	if not enabled(): return {"ok": false, "message": "加工订单仅在三维候选版开放"}
	if not bool(home.state().get("unlocked", false)): return {"ok": false, "message": "请先完成海岛入驻引导"}
	if not _ledger_valid(): return {"ok": false, "message": "加工账本无法校验，已保留原数据"}
	var recipe: Dictionary = recipes.get(recipe_id, {})
	var building: Dictionary = _building(facility_id)
	if recipe.is_empty() or building.is_empty() or not recipe.facility_kinds.has(str(building.kind)): return {"ok": false, "message": "此设施不能执行该配方"}
	if batches < 1 or batches > 28800 / int(recipe.seconds): return {"ok": false, "message": "订单批量不能超过8小时"}
	var home_cost: Dictionary = _multiply(recipe.home_cost, batches)
	var wallet_cost: Dictionary = _multiply(recipe.wallet_cost, batches)
	var occupied: bool = _ledger().get("jobs", {}).has(facility_id)
	var reason: String = "请先返航" if not home._idle() else "设施已损坏，请先维修" if int(building.get("hp", 100)) <= 0 else "此设施已有订单，请先领取或取消" if occupied else "资源不足" if not _afford(home_cost, wallet_cost) else ""
	return {"ok": true, "ready": reason.is_empty(), "message": reason, "facility_id": facility_id, "recipe_id": recipe_id, "name": str(recipe.name), "batches": batches, "seconds": int(recipe.seconds), "total_seconds": batches * int(recipe.seconds), "home_cost": home_cost, "wallet_cost": wallet_cost, "home_output": _multiply(recipe.home_output, batches), "wallet_output": _multiply(recipe.wallet_output, batches), "max_batches": 28800 / int(recipe.seconds), "at": _now(at)}

func start(facility_id: String, recipe_id: String, batches: int = 1, request_id: String = "", confirmed_cost: Dictionary = {}, at: int = -1) -> Dictionary:
	var replay: Dictionary = account._request(request_id, ["home_order_start_v2", facility_id, recipe_id, batches])
	if not replay.is_empty(): return replay
	var quote: Dictionary = preview(facility_id, recipe_id, batches, at)
	if not quote.get("ok", false): return account._fail(str(quote.message))
	if not quote.ready: return account._fail(str(quote.message))
	if not confirmed_cost.is_empty() and not home._same(confirmed_cost, {"home": quote.home_cost, "wallet": quote.wallet_cost}): return account._fail("配方投入已变化，请重新预览")
	var before: Dictionary = account.state.duplicate(true)
	_ensure()
	var ledger: Dictionary = _ledger()
	ledger.sequence = int(ledger.sequence) + 1
	for key: String in quote.home_cost: home.state().resources[key] = int(home.state().resources[key]) - int(quote.home_cost[key])
	for key: String in quote.wallet_cost: account.state.wallet[key] = int(account.state.wallet.get(key, 0)) - int(quote.wallet_cost[key])
	var job: Dictionary = recipes[recipe_id].duplicate(true)
	job.merge({"job_id": "order-%d" % int(ledger.sequence), "facility_id": facility_id, "batches": batches, "claimed_batches": 0, "work_seconds": 0, "checkpoint_at": _now(at), "started_at": _now(at), "cancelled": false}, true)
	ledger.jobs[facility_id] = job
	return account._commit(before, "加工订单已安排 · 投入只扣一次", {"job": _job_view(job, _now(at)), "cost": {"home": quote.home_cost, "wallet": quote.wallet_cost}})

func checkpoint(at: int = -1) -> void:
	if not enabled() or _ledger().is_empty() or not _ledger_valid(): return
	var now: int = _now(at)
	for job: Dictionary in _ledger().get("jobs", {}).values():
		job.work_seconds = int(_job_view(job, now).work_seconds)
		job.checkpoint_at = maxi(now, int(job.checkpoint_at))

func _facility(source: Dictionary, id: String) -> Dictionary:
	for building: Dictionary in source.get("buildings", []):
		if str(building.get("id", "")) == id: return building
	return {}

func checkpoint_transition(before: Dictionary, at: int = -1) -> void:
	# Called by the ACCOUNT _commit(previous) before saving. previous is the full
	# account snapshot, not only home_v1. No ledger is created and only current job
	# clocks change. The caller's normal failed-save rollback restores these too.
	if not enabled() or _ledger().is_empty() or not _ledger_valid(): return
	var old_home: Dictionary = before.get("home_v1", {})
	var old_jobs: Dictionary = old_home.get("economy_v2", {}).get("jobs", {})
	var was_idle: bool = before.get("active_run", {}).is_empty()
	var is_idle: bool = home._idle()
	var now: int = _now(at)
	for id: String in _ledger().jobs:
		var job: Dictionary = _ledger().jobs[id]
		var old: Dictionary = old_jobs.get(id, {})
		if old.is_empty() or str(old.get("job_id", "")) != str(job.job_id): continue
		var previous_facility: Dictionary = _facility(old_home, id)
		var current_facility: Dictionary = _building(id)
		var changed: bool = previous_facility.is_empty() != current_facility.is_empty() or str(previous_facility.get("kind", "")) != str(current_facility.get("kind", "")) or int(previous_facility.get("hp", 100)) != int(current_facility.get("hp", 100))
		if was_idle == is_idle and not changed: continue
		# Explicit start/claim/cancel/checkpoint has already advanced this job.
		if int(job.checkpoint_at) != int(old.get("checkpoint_at", -1)) or int(job.work_seconds) != int(old.get("work_seconds", -1)) or int(job.batches) != int(old.get("batches", -1)): continue
		var operating_before: bool = was_idle and not previous_facility.is_empty() and int(previous_facility.get("hp", 100)) > 0 and job.facility_kinds.has(str(previous_facility.get("kind", "")))
		var work: int = int(job.work_seconds)
		if operating_before and not bool(job.get("cancelled", false)):
			work += maxi(0, now - int(job.checkpoint_at))
		job.work_seconds = mini(int(job.batches) * int(job.seconds), work)
		job.checkpoint_at = maxi(now, int(job.checkpoint_at))

func _capacity_batches(job: Dictionary, wanted: int) -> int:
	var result: int = wanted
	for key: String in job.home_output:
		result = mini(result, maxi(0, home.RESOURCE_CAP - int(home.state().resources.get(key, 0))) / int(job.home_output[key]))
	for key: String in job.wallet_output:
		result = mini(result, maxi(0, int(config.wallet_output_cap) - int(account.state.wallet.get(key, 0))) / int(job.wallet_output[key]))
	return result

func _close(facility_id: String, job: Dictionary, receipt: Dictionary) -> void:
	var ledger: Dictionary = _ledger()
	ledger.closed[str(job.job_id)] = receipt.duplicate(true)
	while ledger.closed.size() > 64: ledger.closed.erase(ledger.closed.keys()[0])
	ledger.jobs.erase(facility_id)

func claim(facility_id: String, request_id: String = "", at: int = -1) -> Dictionary:
	var replay: Dictionary = account._request(request_id, ["home_order_claim_v2", facility_id])
	if not replay.is_empty(): return replay
	if not enabled() or not home._idle(): return account._fail("请在候选版返航后领取加工产物")
	if not _ledger_valid(): return account._fail("加工账本无法校验，已保留原数据")
	var job: Dictionary = _ledger().get("jobs", {}).get(facility_id, {})
	if job.is_empty(): return account._fail("此设施没有待领取订单")
	var progress: Dictionary = _job_view(job, _now(at))
	var count: int = _capacity_batches(job, int(progress.claimable_batches))
	if count <= 0: return account._fail("尚无完成批次，或产物仓容不足；已完成产物会保留")
	var before: Dictionary = account.state.duplicate(true)
	checkpoint(at)
	var home_output: Dictionary = _multiply(job.home_output, count)
	var wallet_output: Dictionary = _multiply(job.wallet_output, count)
	for key: String in home_output: home.state().resources[key] = int(home.state().resources.get(key, 0)) + int(home_output[key])
	for key: String in wallet_output: account.state.wallet[key] = int(account.state.wallet.get(key, 0)) + int(wallet_output[key])
	job.claimed_batches = int(job.claimed_batches) + count
	var receipt: Dictionary = {"job_id": str(job.job_id), "batches": count, "home_output": home_output, "wallet_output": wallet_output, "remaining_batches": int(job.batches) - int(job.claimed_batches)}
	if int(job.claimed_batches) >= int(job.batches): _close(facility_id, job, receipt)
	return account._commit(before, "加工产物已入库", receipt)

func cancel_preview(facility_id: String, at: int = -1) -> Dictionary:
	if not _ledger_valid(): return {"ok": false, "message": "加工账本无法校验，已保留原数据"}
	var job: Dictionary = _ledger().get("jobs", {}).get(facility_id, {})
	if not enabled() or job.is_empty(): return {"ok": false, "message": "此设施没有可取消的订单"}
	var progress: Dictionary = _job_view(job, _now(at))
	var completed: int = int(progress.completed_batches)
	var started: int = mini(int(job.batches), completed + (1 if int(progress.work_seconds) % int(job.seconds) > 0 else 0))
	var refundable: int = maxi(0, int(job.batches) - started)
	return {"ok": true, "ready": home._idle() and not bool(job.get("cancelled", false)) and completed < int(job.batches), "job_id": str(job.job_id), "completed_batches": completed, "refund_batches": refundable, "lost_batches": started - completed, "home_refund": _multiply(job.home_cost, refundable), "wallet_refund": _multiply(job.wallet_cost, refundable), "message": "未开工批次全退；正在加工批次消耗保留，已完成产物仍可领取。退还投入不受生产仓容截断。"}

func cancel(facility_id: String, request_id: String = "", at: int = -1, confirmed_refund: Dictionary = {}) -> Dictionary:
	var replay: Dictionary = account._request(request_id, ["home_order_cancel_v2", facility_id])
	if not replay.is_empty(): return replay
	var now: int = _now(at)
	var quote: Dictionary = cancel_preview(facility_id, now)
	if not quote.get("ok", false): return account._fail(str(quote.message))
	if not quote.ready: return account._fail("当前订单不能取消，请先返航或领取已完成产物")
	if not confirmed_refund.is_empty():
		for field: String in ["job_id", "completed_batches", "refund_batches", "lost_batches", "home_refund", "wallet_refund"]:
			if not home._same(quote.get(field), confirmed_refund.get(field)):
				var changed: Dictionary = account._fail("订单进度已变化，请重新确认当前退款")
				changed["quote_changed"] = true
				return changed
	var before: Dictionary = account.state.duplicate(true)
	checkpoint(now)
	var job: Dictionary = _ledger().jobs[facility_id]
	for key: String in quote.home_refund: home.state().resources[key] = int(home.state().resources.get(key, 0)) + int(quote.home_refund[key])
	for key: String in quote.wallet_refund: account.state.wallet[key] = int(account.state.wallet.get(key, 0)) + int(quote.wallet_refund[key])
	job.batches = int(quote.completed_batches)
	job.work_seconds = int(job.batches) * int(job.seconds)
	job.cancelled = true
	if int(job.claimed_batches) >= int(job.batches): _close(facility_id, job, quote)
	return account._commit(before, "未开工投入已退还 · 已完成产物保留", quote)
