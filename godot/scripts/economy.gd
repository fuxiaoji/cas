class_name CasEconomy
extends RefCounted
## Offline campaign layer. Never modifies the authoritative CAS ship definitions.
## Every mutation is committed to one journaled JSON save before it reports success.

const SAVE_VERSION := 1
const CATALOG_PATH := "res://data/ships.json"
const CONFIG_PATH := "res://data/economy.json"
const WALLET_KEYS := ["credits", "tickets", "medals", "materials", "ammo_stock"]
const SALVAGE_KEYS := ["scrap", "alloy", "equipment", "command"]
const Meta = preload("res://scripts/meta_economy.gd")
const CargoService=preload("res://scripts/cargo_service.gd")
const PlayerGrowth = preload("res://scripts/player_growth.gd")

var state: Dictionary = {}
var formation: Array[String] = []
var catalog: Array = []
var config: Dictionary = {}
var save_path: String
var _cards: Dictionary = {}
var _pending_request: Dictionary = {}


func _init(path: String = "user://cas_port_v1.json") -> void:
	save_path = path
	config = _read_dictionary(CONFIG_PATH)
	var raw: Variant = _read_dictionary(CATALOG_PATH).get("ships", [])
	if raw is Array:
		for row in raw:
			if row is Dictionary and row.get("id", "") is String and not str(row.get("id", "")).is_empty():
				catalog.append(row.duplicate(true))
				_cards[str(row.id)] = row.duplicate(true)
	if FileAccess.file_exists("res://data/combined-arms-ships-v4.json"):
		for row in _read_dictionary("res://data/combined-arms-ships-v4.json").get("ships",[]):
			if row is Dictionary and not _cards.has(str(row.get("id",""))):catalog.append(row.duplicate(true));_cards[str(row.id)]=row.duplicate(true)
	if catalog.is_empty():
		# Explicit bootstrap identities, replaced automatically by the imported catalogue.
		for i in range(5):
			var row := {"id": "DEMO-STARTER-%d" % i, "name": "测试舰 %d" % (i + 1), "type": "DD", "side": "allies", "rarity": "common", "playable": true, "points": 500, "portrait": "", "chibi": "", "profile": "", "bootstrap": true}
			catalog.append(row)
			_cards[row.id] = row


func load_state() -> Dictionary:
	var had_save := FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path + ".bak")
	var loaded := _read_dictionary(save_path)
	var recovered := false
	if not _valid_state(loaded):
		loaded = _read_dictionary(save_path + ".bak")
		recovered = _valid_state(loaded)
	if not _valid_state(loaded):
		if had_save:
			return _fail("存档无法读取，已保留原文件；请先修复或恢复备份。")
		return new_profile()
	state = loaded
	state.get_or_add("transactions", {})
	state.get_or_add("item_instances", {})
	state.get_or_add("item_sequence", 0)
	state.get_or_add("last_receipt_id", "")
	state.wallet.get_or_add("up_tickets", 0)
	state.get_or_add("pity_by_pool", {"standard": int(state.get("pity", 0)), "up": 0})
	state.get_or_add("pending_recruit", {})
	state.get_or_add("last_recruit", {})
	_sync_formation()
	Meta.new(self).ensure()
	load("res://scripts/fuel_service.gd").new(self).ensure()
	load("res://scripts/test_account_resources.gd").apply(self)
	return {"ok": true, "message": "已从备份恢复" if recovered else "舰队档案已载入", "recovered": recovered, "active_sortie": state.get("active_run", {}).duplicate(true)}


func save_state() -> Dictionary:
	if state.is_empty():
		return _fail("尚未建立舰队档案")
	state["formation"] = formation.duplicate()
	var absolute := ProjectSettings.globalize_path(save_path)
	var directory := absolute.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return _fail("无法创建存档目录")
	var temporary := absolute + ".tmp"
	var backup := absolute + ".bak"
	var stream := FileAccess.open(temporary, FileAccess.WRITE)
	if stream == null:
		return _fail("无法写入存档，操作未生效")
	stream.store_string(JSON.stringify(state))
	stream.flush()
	stream.close()
	if not _valid_state(_read_dictionary(temporary)):
		return _fail("存档校验失败，操作未生效")
	if FileAccess.file_exists(absolute):
		if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK:
			return _fail("无法更新存档备份，操作未生效")
		if DirAccess.rename_absolute(absolute, backup) != OK:
			return _fail("无法轮换存档，操作未生效")
	if DirAccess.rename_absolute(temporary, absolute) != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, absolute)
		return _fail("存档提交失败，操作未生效")
	return {"ok": true, "message": "舰队档案已保存"}


func new_profile() -> Dictionary:
	var previous := state.duplicate(true)
	var initial: Dictionary = config.get("initial", {"credits": 2400, "tickets": 10, "medals": 0, "materials": 12, "ammo_stock": 250})
	state = {"version": SAVE_VERSION, "ruleset": "cas-exploration-economy-v1", "wallet": initial.duplicate(true), "owned": {}, "formation": [], "inventory": {"scrap": 0, "alloy": 0, "equipment": 0, "command": 0}, "item_instances": {}, "item_sequence": 0, "transactions": {}, "pity": 0, "draw_sequence": 0, "draw_seed": 11092026, "draw_rng_state": 0, "history": [], "run_sequence": 0, "active_run": {}, "settled": {}, "last_receipt_id": "", "sorties": 0, "extractions": 0}
	formation.clear()
	state.wallet.get_or_add("up_tickets", 10)
	state["pity_by_pool"] = {"standard": 0, "up": 0}
	state["pending_recruit"] = {}
	state["last_recruit"] = {}
	var starters: Array = config.get("starter_ids", [])
	for id_value in starters:
		if formation.size() >= 3:
			break
		var id := str(id_value)
		if _cards.has(id) and _cards[id].get("playable", false):
			state.owned[id] = _new_owned(id)
			formation.append(id)
	for card in catalog:
		if formation.size() >= 3:
			break
		if card.get("playable", false) and not formation.has(str(card.id)) and card.get("side", "allies") == "allies":
			state.owned[str(card.id)] = _new_owned(str(card.id))
			formation.append(str(card.id))
	if formation.is_empty():
		for card in catalog:
			if formation.size() >= 3:
				break
			if card.get("playable", false):
				state.owned[str(card.id)] = _new_owned(str(card.id))
				formation.append(str(card.id))
	Meta.new(self).ensure()
	load("res://scripts/first_voyage_onboarding.gd").mark_new_profile(state)
	return _commit(previous, "启航补给已到账：初始舰队、银币与十张征募券")


func wallet() -> Dictionary:
	var output: Dictionary=state.get("wallet", {}).duplicate(true)
	if not state.is_empty():
		var energy: Dictionary=Meta.new(self).stamina()
		output["origins"]=int(state.wallet.get("origins",0))
		output["stamina"]=energy.value
		output["stamina_max"]=energy.max
		output["stamina_next_seconds"]=energy.next_seconds
	return output

func supply_catalog() -> Array: return Meta.new(self).supply_catalog()
func purchase(id: String, count: int = 1, request_id: String = "") -> Dictionary: return Meta.new(self).purchase(id,count,request_id)
func growth_profile(id: String) -> Dictionary: return Meta.new(self).growth_profile(id)
func mastery_rewards(id: String) -> Array: return Meta.new(self).mastery_rewards(id)
func claim_mastery_reward(id: String, threshold: int) -> Dictionary: return Meta.new(self).claim_mastery_reward(id,threshold)
func gear_inventory(id: String, slot: String) -> Array: return Meta.new(self).gear_inventory(id,slot)
func assign_item(id: String, slot: String, instance_id: String) -> Dictionary: return Meta.new(self).assign_item(id,slot,instance_id)
func mission_catalog(kind: String) -> Array: return Meta.new(self).mission_catalog(kind)
func prepare_service(ids: Array, ammo_target: int = 100, service: String = "both") -> Dictionary: return Meta.new(self).prepare_service(ids,ammo_target,service)
func service_all(ids: Array, ammo_target: int = 100, request_id: String = "", service: String = "both") -> Dictionary: return Meta.new(self).service_all(ids,ammo_target,request_id,service)
func gear_drop_table() -> Array: return Meta.new(self).gear_drop_table()
func native_start(run: Dictionary) -> Dictionary: return Meta.new(self).native_start(run)
func player_profile() -> Dictionary:return PlayerGrowth.new(self).profile()
func grant_player_xp(key:String,amount:int) -> Dictionary:return PlayerGrowth.new(self).grant(key,amount)
func material_catalog() -> Array:return PlayerGrowth.new(self).materials()
func ascend_preview(id:String) -> Dictionary:return PlayerGrowth.new(self).ascent_preview(id)
func ascend_ship(id:String,request_id:String="") -> Dictionary:return PlayerGrowth.new(self).ascend(id,request_id)
func train_material(id:String,tier:int,count:int=1,request_id:String="") -> Dictionary:return PlayerGrowth.new(self).train(id,tier,count,request_id)
func gear_types() -> Array:return PlayerGrowth.new(self).config.gear_types.duplicate(true)
func refit_equipment(instance_id:String,type_id:String,request_id:String="") -> Dictionary:return PlayerGrowth.new(self).refit(instance_id,type_id,request_id)
func refit_cost() -> Dictionary:
	var rules=preload("res://data/player-growth.tres")
	return {"credits":rules.refit_silver,"core_t1":rules.refit_cores}
func fuse_material(id:String,count:int=1) -> Dictionary:return PlayerGrowth.new(self).fuse(id,count)
func payment_status() -> Dictionary: return {"enabled":false,"message":"充值与PVP账户服务尚未开放，不会模拟支付到账"}


func roster() -> Array:
	var result: Array = []
	for card in catalog:
		var id := str(card.id)
		if state.get("owned", {}).has(id):
			var row: Dictionary = card.duplicate(true)
			row.merge(state.owned[id], true)
			row["selected"] = formation.has(id)
			row["xp_next"] = _xp_threshold(int(row.get("level", 1)))
			result.append(row)
	return result


func shop_items() -> Array:
	return config.get("shop", []).duplicate(true)


func set_formation(ids: Array) -> Dictionary:
	if not state.get("active_run", {}).is_empty():
		return _fail("海上行动期间不能调整编队")
	if ids.is_empty():
		return _fail("请至少选择一艘舰娘")
	var unique: Array[String] = []
	for value in ids:
		var id := str(value)
		if unique.has(id) or not state.get("owned", {}).has(id) or not _cards.get(id, {}).get("playable", false):
			return _fail("编队包含重复、未拥有或不可出战舰娘")
		unique.append(id)
	var previous := state.duplicate(true)
	formation = unique
	if state.has("fleet_book"):
		var active_id:=str(state.get("active_fleet_id",""))
		for group in state.fleet_book:
			if str(group.id)==active_id: group.ships=unique.duplicate()
		state["sortie_fleet_ids"]=[active_id]
	return _commit(previous, "打捞编队已保存")


func buy(item_id: String, count: int = 1, request_id: String = "") -> Dictionary:
	var replay := _request(request_id, ["buy", item_id, count])
	if not replay.is_empty():
		return replay
	if not state.get("active_run", {}).is_empty():
		return _fail("海上行动期间军需交易已锁定，请先继续或结束航次")
	if count < 1 or count > 100:
		return _fail("采购数量须为 1–100")
	if item_id == "emergency":
		return emergency_supply()
	var aliases := {"ammo": "ammo_pack", "materials": "material_pack", "recruit_ticket": "ticket"}
	var wanted: String = aliases.get(item_id, item_id)
	for item in shop_items():
		if str(item.id) != wanted:
			continue
		var price := int(item.cost) * count
		if int(state.get("wallet", {}).get("credits", 0)) < price:
			return _fail("银币不足")
		var previous := state.duplicate(true)
		state.wallet.credits = int(state.wallet.credits) - price
		state.wallet[str(item.grant)] = int(state.wallet.get(str(item.grant), 0)) + int(item.amount) * count
		return _commit(previous, "%s ×%d 已入库" % [str(item.name), count], {"item": wanted, "count": count, "cost": price})
	return _fail("军需处没有该商品")


func repair(ship_id: String, request_id: String = "") -> Dictionary:
	var replay := _request(request_id, ["repair", ship_id])
	if not replay.is_empty():
		return replay
	if not _can_service(ship_id):
		return _fail("舰娘未拥有，或正在海上执行任务")
	var ship: Dictionary = state.owned[ship_id]
	var missing := 100 - int(ship.hp)
	if bool(ship.get("protected", false)) or not bool(ship.get("canNavigate", true)):
		missing = maxi(1, missing)
	if missing <= 0:
		return _fail("舰体状况良好，无需维修")
	var price := missing * int(config.get("repair_credit_per_percent", 2))
	if int(state.wallet.credits) < price:
		return _fail("维修需要 %d 银币" % price)
	var previous := state.duplicate(true)
	state.wallet.credits = int(state.wallet.credits) - price
	ship.hp = 100
	ship["protected"] = false
	ship["canNavigate"] = true
	return _commit(previous, "维修完毕，舰娘已恢复出航状态", {"cost": price})


func rearm(ship_id: String, request_id: String = "") -> Dictionary:
	var replay := _request(request_id, ["rearm", ship_id])
	if not replay.is_empty():
		return replay
	if not _can_service(ship_id):
		return _fail("舰娘未拥有，或正在海上执行任务")
	var ship: Dictionary = state.owned[ship_id]
	var missing := 100 - int(ship.ammo)
	var amount := mini(missing, int(state.wallet.ammo_stock))
	if amount <= 0:
		return _fail("无需补弹，或库存弹药不足")
	var previous := state.duplicate(true)
	ship.ammo = int(ship.ammo) + amount
	return _commit(previous, "装载计划增加 %d 份；确认出航时从库存扣除" % amount, {"amount": amount})


func plan_ammo(ship_id: String, amount: int, request_id: String = "") -> Dictionary:
	var replay := _request(request_id, ["plan_ammo", ship_id, amount])
	if not replay.is_empty():
		return replay
	if not _can_service(ship_id) or amount < 10 or amount > 100:
		return _fail("计划装载须为10–100份，且仅可在港口修改")
	var previous := state.duplicate(true)
	state.owned[ship_id].ammo = amount
	return _commit(previous, "装载计划已调整为%d份；出航前不扣库存" % amount)


func train(ship_id: String, request_id: String = "") -> Dictionary:
	var replay := _request(request_id, ["train", ship_id])
	if not replay.is_empty():
		return replay
	if not _can_service(ship_id):
		return _fail("舰娘未拥有，或正在海上执行任务")
	if int(state.owned[ship_id].level) >= int(config.get("max_level", 30)):
		return _fail("舰历等级已达上限")
	PlayerGrowth.new(self).ensure()
	if int(state.owned[ship_id].level)>=PlayerGrowth.new(self).cap(state.owned[ship_id]):return _fail("当前等级已满，请先突破")
	var price := int(config.get("train_credits", 100))
	var materials := int(config.get("train_materials",2))
	if int(state.wallet.credits) < price or int(state.wallet.materials) < materials:
		return _fail("训练需要 %d 银币与2份训练材料" % price)
	var previous := state.duplicate(true)
	state.wallet.credits = int(state.wallet.credits) - price
	state.wallet.materials = int(state.wallet.materials) - materials
	_add_xp(state.owned[ship_id], int(config.get("train_xp", 80)))
	return _commit(previous, "训练完成，舰历经验已增加；熟练度通过实际参战获得", {"level": state.owned[ship_id].level, "xp": state.owned[ship_id].xp})


func equip(ship_id: String, item_id: String, request_id: String = "") -> Dictionary:
	var replay := _request(request_id, ["equip", ship_id, item_id])
	if not replay.is_empty(): return replay
	if not _can_service(ship_id) or item_id not in ["equipment", "command"]: return _fail("舰娘或装配物不可用")
	var meta=Meta.new(self)
	meta.ensure()
	for key in state.item_instances:
		var item: Dictionary=state.item_instances[key]
		var slot:=str(item.get("slot",""))
		if str(item.kind)!=item_id or str(item.location)!="warehouse": continue
		var occupied:=str(state.owned[ship_id].get("equipment","")) if slot=="equipment" else str(state.owned[ship_id].crews.get(slot,""))
		if occupied.is_empty(): return meta.assign_item(ship_id,slot,str(key))
	return _fail("没有适配空槽位的仓库装配物")


func sell(item_id: String, count: int = 1, request_id: String = "") -> Dictionary:
	var replay := _request(request_id, ["sell", item_id, count])
	if not replay.is_empty():
		return replay
	if not state.get("active_run", {}).is_empty():
		return _fail("海上行动期间仓库交易已锁定")
	var prices: Dictionary = config.get("salvage_prices", {"scrap": 25, "alloy": 60, "equipment": 200, "command": 250})
	if not prices.has(item_id) or count < 1 or count > int(state.get("inventory", {}).get(item_id, 0)):
		return _fail("出售数量无效，或仓库物品不足")
	var previous := state.duplicate(true)
	var income := count * int(prices[item_id])
	state.inventory[item_id] = int(state.inventory[item_id]) - count
	if item_id in ["equipment", "command"]:
		var remaining := count
		for key in state.get("item_instances", {}).keys():
			if remaining <= 0:
				break
			var item: Dictionary = state.item_instances[key]
			if str(item.get("kind", "")) == item_id and str(item.get("location", "")) == "warehouse":
				state.item_instances.erase(key)
				remaining -= 1
	state.wallet.credits = int(state.wallet.credits) + income
	return _commit(previous, "战利品已兑换 %d 银币" % income, {"income": income})


func recruit(count: int = 1, request_id: String = "", pool: String = "standard") -> Dictionary:
	var replay := _request(request_id, ["recruit", count, pool])
	if not replay.is_empty():
		return replay
	if not state.get("active_run", {}).is_empty():
		return _fail("海上行动期间征募已锁定")
	if pool not in ["standard", "up"]:
		return _fail("请选择常驻或UP征募池")
	# Reopening a committed animation never performs another draw. A new draw
	# remains possible; the previous result is retained in history/last_recruit.
	var currency := "up_tickets" if pool == "up" else "tickets"
	if count not in [1, 10]:
		return _fail("请选择单次或十次征募")
	if int(state.get("wallet", {}).get(currency, 0)) < count:
		return _fail("%s不足，还差%d张" % ["UP征募券" if pool == "up" else "征募券", count - int(state.wallet.get(currency, 0))])
	var playable: Array = catalog.filter(func(row: Dictionary) -> bool: return bool(row.get("playable", false)) and bool(row.get("recruitable",true)))
	if playable.is_empty():
		return _fail("舰娘目录尚未准备就绪")
	var previous := state.duplicate(true)
	var random := RandomNumberGenerator.new()
	random.seed = int(state.get("draw_seed", 11092026))
	if int(state.get("draw_rng_state", 0)) != 0:
		random.state = int(state.draw_rng_state)
	var draws: Array = []
	var pity: Dictionary = state.get("pity_by_pool", {"standard": int(state.get("pity", 0)), "up": 0}).duplicate(true)
	for i in range(count):
		var gacha: Dictionary = config.get("gacha", {})
		var guaranteed := int(pity.get(pool, 0)) >= int(gacha.get("rare_or_better_after_common", 9))
		var weights: Dictionary = gacha.get("weights", {"ur": 2, "elite": 8, "rare": 20, "common": 70})
		var total := 0.0
		for tier in ["ur", "elite", "rare", "common"]:
			if tier != "common" or not guaranteed:
				total += maxf(0.0, float(weights.get(tier, 0)))
		var roll := random.randf() * total
		var rarity := "rare" if guaranteed else "common"
		for tier in ["ur", "elite", "rare", "common"]:
			if tier == "common" and guaranteed:
				continue
			roll -= maxf(0.0, float(weights.get(tier, 0)))
			if roll < 0.0:
				rarity = tier
				break
		var choices: Array = playable.filter(func(row: Dictionary) -> bool: return _rarity(row) == rarity)
		if choices.is_empty():
			# Bootstrap catalogue has no rarity spectrum; clearly marked in the draw record.
			choices = playable
		var featured := str(gacha.get("featured_id", "IBS-U-USN-ERMA-MISSOURI"))
		if pool == "up" and rarity == "ur" and _cards.has(featured):
			if random.randf() < float(gacha.get("featured_ur_share", 0.5)):
				choices = [_cards[featured]]
			else:
				var others: Array = choices.filter(func(row: Dictionary) -> bool: return str(row.id) != featured)
				if not others.is_empty():
					choices = others
		var card: Dictionary = choices[random.randi_range(0, choices.size() - 1)]
		var actual_rarity := _rarity(card)
		var id := str(card.id)
		var duplicate: bool = state.owned.has(id)
		if duplicate:
			var compensation: Dictionary = config.get("gacha", {}).get("duplicate_credits", {"ur": 500, "elite": 200, "rare": 100, "common": 50})
			state.wallet.credits = int(state.wallet.credits) + int(compensation.get(actual_rarity, 50))
			var medals: Dictionary = config.get("gacha", {}).get("duplicate_medals", {"ur": 5, "elite": 3, "rare": 2, "common": 1})
			state.wallet.medals = int(state.wallet.medals) + int(medals.get(actual_rarity, 1))
		else:
			state.owned[id] = _new_owned(id)
		pity[pool] = int(pity.get(pool, 0)) + 1 if actual_rarity == "common" else 0
		state.draw_sequence = int(state.draw_sequence) + 1
		var draw := {"sequence": state.draw_sequence, "id": id, "name": card.get("name", id), "rarity": actual_rarity, "portrait": card.get("portrait", ""), "duplicate": duplicate, "guaranteed": guaranteed, "bootstrap": card.get("bootstrap", false), "pool": pool, "featured": pool == "up" and id == featured}
		draws.append(draw)
		state.history.push_front(draw)
		if state.history.size() > 100:
			state.history.pop_back()
	# Godot JSON parses numbers as doubles. Preserve 64-bit RNG state as text.
	state.draw_rng_state = str(random.state)
	state.wallet[currency] = int(state.wallet.get(currency, 0)) - count
	state.pity_by_pool = pity
	state.pity = int(pity.get("standard", 0))
	var batch := {"batch_id": "recruit-%d" % int(state.draw_sequence), "draws": draws, "results": draws, "pool": pool, "phase": "signal", "index": 0, "pity": int(pity[pool])}
	state.pending_recruit = batch.duplicate(true)
	state.last_recruit = batch.duplicate(true)
	return _commit(previous, "%d 位舰娘回应了征募信号" % count, batch)


func recruit_animation(phase: String, index: int = 0) -> Dictionary:
	if phase not in ["signal", "approach", "reveal", "complete"]:
		return _fail("未知到港阶段")
	if state.get("pending_recruit", {}).is_empty():
		return {"ok": true, "message": "到港结果已经保存"}
	var previous := state.duplicate(true)
	state.pending_recruit.phase = phase
	state.pending_recruit.index = maxi(0, index)
	if phase == "complete":
		state.last_recruit = state.pending_recruit.duplicate(true)
		state.pending_recruit = {}
	return _commit(previous, "到港演出进度已保存")


func campaign_growth(request: Dictionary) -> Dictionary:
	if str(request.get("op",""))!="new_campaign" or str(request.get("difficulty",""))!="story": return _fail("自有舰演练仅用于剧情难度自定义编成")
	var identities: Array=[]
	if request.has("groups"):
		for group in request.groups: identities.append_array(group.get("ships",[]))
	else: identities=request.get("fleet",[]).duplicate()
	if identities.is_empty(): return _fail("请选择自有舰演练编成")
	var seen: Dictionary={}
	var hulls: Array=[]
	for identity in identities:
		var id:=str(identity)
		if seen.has(id) or not state.owned.has(id): return _fail("演练编成必须全部为不重复的自有舰身份")
		seen[id]=true
		var row: Dictionary=state.owned[id].duplicate(true)
		row.merge({"id":id,"hp":100,"ammo":100},true)
		hulls.append(row)
	var meta=Meta.new(self)
	meta.enrich_fleet(hulls)
	var prepared: Dictionary=request.duplicate(true)
	prepared["ownedGrowth"]={"version":"cas-owned-growth-v1","hulls":meta.native_start({"fleet":hulls,"owned_growth":"cas-owned-growth-v1"}).fleet}
	return {"ok":true,"request":prepared}

func set_salvage_options(options:Dictionary) -> Dictionary:return CargoService.new(self).set_options(options)
func cargo_budget() -> Dictionary:return CargoService.new(self).budget(roster().filter(func(row):return formation.has(str(row.id))))
func set_cargo_loadout(id:String,ammo:int,torpedoes:bool) -> Dictionary:return CargoService.new(self).set_loadout(id,ammo,torpedoes)

func preview_sortie(seed: int, basic: bool = false, mission: Dictionary = {}) -> Dictionary:
	var meta=Meta.new(self)
	meta.ensure()
	if not state.get("active_run",{}).is_empty(): return _fail("已有未结算海上行动")
	var task: Dictionary=meta.mission(mission)
	if not basic and not bool(task.get("unlocked",true)):return _fail("指挥官等级不足，先完成基础资源海域或剧情")
	if task.is_empty(): return _fail("资源航线或天梯不存在")
	if basic: task={"kind":"salvage","id":"salvage","cost_stamina":0,"rewards":{}}
	if not basic and int(wallet().stamina)<int(task.cost_stamina): return _fail("体力不足，恢复后可再出航")
	var fleet: Array=[]
	var groups: Array=[]
	var points:=0
	var ammo:=0
	if basic:
		var id:=str(config.starter_ids[0])
		var row: Dictionary=_cards[id].duplicate(true)
		row.merge({"id":id,"hp":100,"ammo":100,"level":0,"equipment":"","command":"","borrowed":true},true)
		fleet.append(row)
		groups=[{"id":"borrowed","name":"借用打捞编队","ships":[id]}]
	else:
		if formation.is_empty(): return _fail("请先配置出航舰队")
		var unique: Dictionary={}
		for id in formation:
			if unique.has(id) or not state.owned.has(id) or not _cards.get(id,{}).get("playable",false): return _fail("编队包含重复或未拥有舰娘")
			unique[id]=true
			var row: Dictionary=_cards[id].duplicate(true)
			row.merge(state.owned[id],true)
			if int(row.hp)<=0 or bool(row.get("protected",false)) or not bool(row.get("canNavigate",true)) or int(row.ammo)<int(config.sortie_ammo_cost): return _fail("%s需要维修或补充弹药"%str(row.name))
			fleet.append(row);ammo+=int(row.ammo);points+=int(row.get("points",0))
		if ammo>int(state.wallet.ammo_stock): return _fail("库存弹药不足，请减少装载或补充库存")
		if int(task.get("player_budget",0))>0 and points>int(task.player_budget): return _fail("舰队基础分%d超过本层%d分预算"%[points,int(task.player_budget)])
		if ResourceLoader.exists("res://scripts/fleet_manager.gd"):
			groups=load("res://scripts/fleet_manager.gd").new(self).groups()
			if groups.is_empty(): return _fail("请至少勾选一支出航编队")
		else: groups=[{"id":"legacy","name":"出航编队","ships":formation.duplicate()}]
		meta.enrich_fleet(fleet)
	var preview:=formation_preview()
	var prepared:Dictionary={"ok":true,"seed":seed,"mode":"basic" if basic else "salvage","fleet":fleet,"groups":groups,"content":"salvage-v3","owned_growth":"" if basic else "cas-owned-growth-v1","mission":task,"score":points,"capacity":preview.capacity,"search_seconds":preview.search_seconds,"weather":"salvage-weather-v1"}

	if not basic and str(task.get("kind",""))=="salvage":
		var service=CargoService.new(self)
		for hull in fleet:
			if int(hull.ammo)<20:return _fail("新打捞航次至少装载20份炮弹")
		prepared["content"]="salvage-v4"
		prepared["gameplay_profile"]="cas-adventure-v2"
		prepared["expedition_v2"]=service.expedition_config(fleet)
		var army:Dictionary=load("res://scripts/amphibious_expedition_service.gd").new(self).prepare(fleet)
		if not army.get("ok",false):return army
		if not army.companies.is_empty():prepared["gameplay_profile"]="cas-adventure-v3";prepared["amphibious_expedition"]={"companies":army.companies}
		if army.has("company_layout") and not army.companies.is_empty():prepared.amphibious_expedition["company_layout"]=army.company_layout
		for hull in fleet:
			if hull.has("special_mode_scope") and str(prepared.gameplay_profile)!="cas-adventure-v3":return _fail("新增航空与运输舰需携带陆军，参加海陆搜打撤")
		prepared["cargo_v4"]=service.start_config(str(task.id))
		var cargo:Dictionary=service.budget(fleet)
		prepared["capacity"]=int(cargo.cols)*int(cargo.rows)
		prepared["search_seconds"]=int({"calm":8,"standard":12,"hazard":16}.get(str(task.id),8))
		var fuel:Dictionary=load("res://scripts/fuel_service.gd").new(self).preview(fleet)
		if int(fuel.stock)<int(fuel.initial):return _fail("油料不足，请在整备中采购或降低装油比例")
		prepared["fuel_v1"]={"version":"fleet-fuel-v1","initial":int(fuel.initial)}
		prepared["intel_profile"]="open-intel-v1"
		prepared["cargo_warehouse_key"]=load("res://scripts/fleet_warehouse.gd").new(self).key()
		var transfer:Dictionary=load("res://scripts/fleet_warehouse.gd").new(self).prepare("salvage-%d-%d"%[int(state.run_sequence)+1,seed])
		if not bool(transfer.get("ok",false)):return transfer
		transfer.erase("ok");prepared["cargo_transfer_v1"]=transfer
	elif not basic:
		for hull in fleet:
			if hull.has("special_mode_scope"):return _fail("新增航空与运输舰仅用于海陆搜打撤与家园两栖战")
		prepared["intel_profile"]="open-intel-v1"
	if basic:prepared["intel_profile"]="open-intel-v1"
	return prepared

func begin_sortie(seed: int, basic: bool = false, mission: Dictionary = {}) -> Dictionary:
	var prepared:=preview_sortie(seed,basic,mission)
	if not prepared.get("ok",false): return prepared
	var previous:=state.duplicate(true)
	state.run_sequence=int(state.run_sequence)+1
	var run_id:="%s-%d-%d"%["basic" if basic else "salvage",int(state.run_sequence),seed]
	prepared["run_id"]=run_id;prepared["sortie_id"]=run_id
	prepared["ruleset"]="cas-exploration-economy-v2"
	prepared["typed_gear"]=true
	if not basic:
		var ammo:=0
		for row in prepared.fleet: ammo+=int(row.ammo)
		state.wallet.ammo_stock=int(state.wallet.ammo_stock)-ammo
		Meta.new(self).spend_stamina(int(prepared.mission.cost_stamina))
		if prepared.has("fuel_v1"):state.wallet.fuel=int(state.wallet.fuel)-int(prepared.fuel_v1.initial)
		if prepared.has("cargo_transfer_v1"):load("res://scripts/fleet_warehouse.gd").new(self).hold(str(prepared.cargo_warehouse_key)).items=[]
	state.active_run=prepared.duplicate(true)
	return _commit(previous,"出航补给已确认",prepared)

func resume_sortie() -> Dictionary:
	var active: Dictionary = state.get("active_run", {})
	if active.is_empty():
		return _fail("没有待恢复的海上行动")
	var result := active.duplicate(true)
	result.merge({"ok": true, "message": "继续同一海上行动，沿用原地图、损伤、弹药及容器状态"})
	return result


func save_sortie(core_save: Variant, ui_state:Dictionary={}) -> Dictionary:
	if state.get("active_run", {}).is_empty():
		return _fail("没有可保存的海上行动")
	if not (core_save is Dictionary or core_save is String) or core_save.is_empty():
		return _fail("内核快照为空，已保留上次行动状态")
	if not ui_state.is_empty() and (str(state.active_run.get("mode",""))!="littoral" or JSON.stringify(ui_state).length()>32768):
		return _fail("界面进度无效，已保留上次行动状态")
	if not (ui_state.get("drag_tutorial",{}) is Dictionary):
		return _fail("教学进度无效，已保留上次行动状态")
	var previous := state.duplicate(true)
	# Prefer the native bridge's serialized String so u64 RNG state stays exact.
	state.active_run["snapshot"] = core_save.duplicate(true) if core_save is Dictionary else core_save
	if not ui_state.is_empty():
		state.active_run["ui_state"]=ui_state.duplicate(true)
		# This is only a help preference. Island ownership/rewards still require
		# HomeService's native terminal evidence, never a tutorial UI flag.
		if bool(ui_state.get("drag_tutorial",{}).get("completed",false)) and state.has("home_v1"):
			state.home_v1["drag_tutorial_completed"]=true
	return _commit(previous, "海上行动已保存")


func abandon_sortie() -> Dictionary:
	var active: Dictionary = state.get("active_run", {})
	if str(active.get("gameplay_profile",""))=="cas-adventure-v3":return _fail("请继续本次行动，在战场选择放弃，以记录真实陆军伤亡")
	if active.is_empty():
		return _fail("没有待放弃的海上行动")
	var receipt:Dictionary={"run_id":active.run_id,"success":false,"fleet":[]}
	if active.has("fuel_v1"):receipt["fuel_receipt"]={"version":"fleet-fuel-v1","loaded":int(active.fuel_v1.initial),"remaining":0,"consumed":int(active.fuel_v1.initial)}
	return settle_sortie(receipt)


func settle_sortie(receipt: Dictionary) -> Dictionary:
	var run_id := str(receipt.get("run_id", receipt.get("sortie_id", "")))
	if run_id.is_empty():
		return _fail("行动回执缺少编号")
	if state.get("settled", {}).has(run_id):
		return {"ok": true, "message": "该行动已结算，未重复发奖", "duplicate": true, "receipt": state.settled[run_id].duplicate(true)}
	var active: Dictionary = state.get("active_run", {})
	if active.is_empty() or str(active.get("run_id", "")) != run_id:
		return _fail("行动回执与当前海上行动不符")
	var army_outcome:Dictionary={}
	if str(active.get("gameplay_profile",""))=="cas-adventure-v3":
		var proof:Dictionary=load("res://scripts/amphibious_expedition_service.gd").new(self).verify_terminal(str(receipt.get("amphibious_serialized","")))
		if not proof.get("ok",false):return proof
		var real:Dictionary=proof.view.salvage
		if not load("res://scripts/amphibious_expedition_service.gd").same(receipt.get("ships",[]),real.ships) or not load("res://scripts/amphibious_expedition_service.gd").same(receipt.get("loot",{}),real.loot) or bool(receipt.get("success",false))!=bool(real.get("extracted",false)):return _fail("回执与真实战损不一致")
		var actual_items:Array=real.get("cargo_grid",{}).get("items",[]).filter(func(item):return item.get("placement")!=null)
		if not load("res://scripts/amphibious_expedition_service.gd").same(receipt.get("cargo_items",[]),actual_items) or not load("res://scripts/amphibious_expedition_service.gd").same(receipt.get("fuel_receipt",{}),proof.view.get("fuel_receipt",{})):return _fail("货舱或油料回执与真实撤离不一致")
		army_outcome=proof.outcome
	var success := bool(receipt.get("success", receipt.get("extracted", false)))
	var coins := int(receipt.get("coins", 0))
	var experience := int(receipt.get("xp", int(config.get("extracted_xp", 40)) if success else 0))
	if str(active.get("mode", "salvage")) == "basic":
		experience = 0
	if coins < 0 or coins > 1000000 or experience < 0 or experience > 10000:
		return _fail("行动奖励超出有效范围")
	var loot: Variant = receipt.get("loot", {})
	var normalized_loot: Dictionary = {}
	var lost_loot: Dictionary = {}
	if loot is Dictionary:
		for key in SALVAGE_KEYS:
			var amount := int(loot.get(key, 0))
			if amount < 0 or amount > 10000:
				return _fail("战利品数量无效")
			normalized_loot[key] = amount if success else 0
			if not success and amount > 0:
				lost_loot[key] = amount
	else:
		return _fail("战利品回执格式无效")
	if str(active.get("content",""))=="salvage-v4" and not CargoService.validate_receipt(receipt.get("cargo_items",[]),normalized_loot,success,str(active.get("cargo_v4",{}).get("difficulty","calm")),str(active.get("gameplay_profile","")) in ["cas-adventure-v2","cas-adventure-v3"],active.get("cargo_transfer_v1",{}).get("items",[])):
		return _fail("货舱物件与结算数量不一致；行动已保留，请重新同步回执")
	var fuel_return:Dictionary={}
	if active.has("fuel_v1"):
		fuel_return=receipt.get("fuel_receipt",{})
		if str(fuel_return.get("version",""))!="fleet-fuel-v1" or int(fuel_return.get("loaded",-1))!=int(active.fuel_v1.initial):return _fail("油料回执与出航记录不符")
		for field in ["loaded","remaining","consumed"]:
			var amount:Variant=fuel_return.get(field,-1)
			if not (amount is int or amount is float) or not is_finite(float(amount)) or float(amount)!=floor(float(amount)) or int(amount)<0:return _fail("油料结算值无效")
		if int(fuel_return.remaining)+int(fuel_return.consumed)!=int(active.fuel_v1.initial):return _fail("油料结算不守恒")
	var reported: Variant = receipt.get("ships", receipt.get("fleet", []))
	if not reported is Array:
		return _fail("舰队状态回执格式无效")
	var reported_by_id: Dictionary = {}
	var active_ids: Dictionary = {}
	for row in active.fleet:
		active_ids[str(row.id)] = row
	for row in reported:
		if not row is Dictionary or not active_ids.has(str(row.get("id", ""))) or reported_by_id.has(str(row.get("id", ""))):
			return _fail("舰队回执包含陌生或重复身份")
		for field in ["hp", "ammo"]:
			if not (row.get(field, -1) is int or row.get(field, -1) is float) or not is_finite(float(row.get(field, -1))):
				return _fail("舰队状态值无效")
		reported_by_id[str(row.id)] = row
	var newly_recovered:Dictionary=normalized_loot.duplicate(true)
	if active.has("cargo_transfer_v1"):
		var prior_ids:Dictionary={}
		for item in active.cargo_transfer_v1.items:prior_ids[str(item.id)]=true
		for item in receipt.get("cargo_items",[]):
			if item.get("placement")!=null and prior_ids.has(str(item.id)):
				var kind:String=str(item.kind)
				newly_recovered[kind]=maxi(0,int(newly_recovered.get(kind,0))-1)
	if str(active.get("content","")) in ["salvage-v2","salvage-v3","salvage-v4"] and str(active.get("mission",{}).get("kind",""))!="ladder" and not newly_recovered.values().any(func(amount):return int(amount)>0): experience=0
	var previous := state.duplicate(true)
	var ships: Array = []
	if not fuel_return.is_empty() and success:state.wallet.fuel=int(state.wallet.get("fuel",0))+int(fuel_return.remaining)
	var deployment_ammo := 0
	var returned_ammo := 0
	var borrowed_ammo := 0
	var borrowed := str(active.get("mode", "salvage")) == "basic"
	for id in active_ids:
		var start: Dictionary = active_ids[id]
		var returned: Dictionary = reported_by_id.get(id, {"hp": 0, "ammo": 0})
		var hp := clampi(int(returned.hp), 0, int(start.hp))
		var ammo := clampi(int(returned.ammo), 0, int(start.ammo))
		var can_return := hp > 0 and not bool(returned.get("protected", false)) and bool(returned.get("canNavigate", true))
		var refunded := ammo if success and can_return and not borrowed else 0
		var missing_hp := 100 - hp
		if not can_return:
			missing_hp = maxi(1, missing_hp)
		ships.append({"id": str(id), "name": str(start.get("name", _cards.get(id, {}).get("name", id))), "hp": hp, "hp_before": int(start.hp), "damage": maxi(0, int(start.hp) - hp), "ammo": ammo, "ammo_before": int(start.ammo), "ammo_spent": maxi(0, int(start.ammo) - ammo), "ammo_returned": refunded, "ammo_lost": ammo - refunded if not borrowed else 0, "protected": not can_return, "canNavigate": can_return, "borrowed": borrowed, "repair_cost": missing_hp * int(config.get("repair_credit_per_percent", 2)) if not borrowed else 0})
		if borrowed:
			borrowed_ammo += int(start.ammo)
			continue
		deployment_ammo += int(start.ammo)
		returned_ammo += refunded
		state.owned[id].hp = hp
		state.owned[id]["protected"] = not can_return
		state.owned[id]["canNavigate"] = can_return
		state.owned[id].ammo = refunded
		state.wallet.ammo_stock = int(state.wallet.ammo_stock) + refunded
		if success:
			_add_xp(state.owned[id], experience)
	var meta_rewards: Dictionary=Meta.new(self).settle(active,success,reported,newly_recovered)
	if success:
		if str(active.get("mode", "salvage")) == "basic":
			normalized_loot = {"scrap": mini(4, int(normalized_loot.get("scrap", 0)) + int(normalized_loot.get("alloy", 0))), "alloy": 0, "equipment": 0, "command": 0}
			coins = 0
		state.wallet.credits = int(state.wallet.credits) + coins
		if str(active.get("content",""))=="salvage-v4":
			CargoService.new(self).receive(receipt.get("cargo_items",[]),active)
		for key in normalized_loot:
			if str(active.get("content",""))=="salvage-v4":continue
			state.inventory[key] = int(state.inventory.get(key, 0)) + int(normalized_loot[key])
			if key in ["equipment", "command"]:
				for i in range(int(normalized_loot[key])):
					var table:="gear-v3" if str(active.get("content",""))=="salvage-v3" and bool(active.get("typed_gear",false)) else "gear-v2" if str(active.get("content",""))=="salvage-v3" else "gear-v1"
					var resource_tier:=int(active.get("mission",{}).get("tier",1))
					if table=="gear-v3" and str(active.get("mission",{}).get("kind",""))=="resources" and resource_tier>1:table+="-t%d"%resource_tier
					_create_item(key,table)
		state.extractions = int(state.extractions) + 1
	state.sorties = int(state.sorties) + 1
	if not army_outcome.is_empty():
		var now:int=int(Time.get_unix_time_from_system())
		for row in army_outcome.units:
			var id:String=str(row.id)
			state.home_v1.units[id].condition=float(row.condition_percent);state.home_v1.units[id].at=now
			if float(row.condition_percent)<=0:state.home_v1.units[id].losses=int(state.home_v1.units[id].get("losses",0))+1
	var summary := {"run_id": run_id, "success": success, "coins": coins if success else 0, "loot": normalized_loot, "lost_loot": lost_loot, "xp": experience if success else 0, "ships": ships, "deployment_ammo": deployment_ammo, "returned_ammo": returned_ammo, "borrowed_deployment_ammo": borrowed_ammo, "mode": "basic" if borrowed else "salvage", "score": int(active.get("score", 0))}
	if str(active.get("content",""))=="salvage-v4":summary["content"]="salvage-v4"
	if active.has("cargo_transfer_v1"):summary["cargo_transfer_v1"]={"version":"fleet-cargo-v1","carried":active.cargo_transfer_v1.items.size()}
	if not fuel_return.is_empty():summary["fuel_receipt"]=fuel_return.duplicate(true)
	if not army_outcome.is_empty():summary["amphibious"]=army_outcome.duplicate(true)
	summary["rewards"]=meta_rewards
	summary["mission"]=active.get("mission",{}).duplicate(true)
	state.settled[run_id] = summary
	state["last_receipt_id"] = run_id
	state.active_run = {}
	return _commit(previous, "撤离成功，战利品已入库" if success else "行动失利，舰娘已救援；本次战利品遗失", {"receipt": summary, "duplicate": false})


func latest_receipt() -> Dictionary:
	var settled: Dictionary = state.get("settled", {})
	var latest_id := str(state.get("last_receipt_id", ""))
	if settled.has(latest_id):
		return settled[latest_id].duplicate(true)
	# Older v1 saves have no pointer. The monotonic sequence in each run ID is
	# reliable even though JSON object keys are sorted when the save is written.
	var latest_sequence := -1
	for run_id in settled:
		var fields := str(run_id).split("-")
		var sequence := int(fields[1]) if fields.size() >= 3 and fields[1].is_valid_int() else -1
		if sequence > latest_sequence:
			latest_sequence = sequence
			latest_id = str(run_id)
	return settled.get(latest_id, {}).duplicate(true)


func emergency_supply() -> Dictionary:
	return _fail("请从作战入口选择基础打捞：借用舰队完成真实航行与撤离后可兑换废料，不要求自有舰适航。")


func _new_owned(id: String) -> Dictionary:
	return {"id": id, "level": 0, "xp": 0, "mastery":0,"crews":{}, "hp": 100, "ammo": 60, "equipment": "", "command": "", "protected": false, "canNavigate": true}


func formation_preview() -> Dictionary:
	var preview := {"base_points": 0, "growth_points": 0, "equipment_points": 0, "command_points": 0, "score": 0, "capacity": 8, "search_seconds": 6, "ammo_required": 0, "slots": formation.size(), "max_slots": 0, "threat": 1}
	var levels := 0
	var commanders := 0
	for id in formation:
		var owned: Dictionary = state.get("owned", {}).get(id, {})
		preview.base_points += int(_cards.get(id, {}).get("points", 0))
		levels += maxi(0, int(owned.get("level", 0)))
		preview.ammo_required += int(owned.get("ammo", 0))
		if not str(owned.get("equipment", "")).is_empty():
			preview.equipment_points += 75
			preview.capacity += 2
		if not str(owned.get("command", "")).is_empty():
			preview.command_points += 50
			commanders += 1
	preview.growth_points = levels * 20
	preview.score = int(preview.base_points) + int(preview.growth_points) + int(preview.equipment_points) + int(preview.command_points)
	preview.search_seconds = int(ceil(maxf(3.0, 6.0 - 0.1 * levels - commanders)))
	preview.threat = 1 if int(preview.score) < 1500 else (2 if int(preview.score) < 3000 else (3 if int(preview.score) < 6000 else 4))
	return preview


func unequip(ship_id: String, slot: String, request_id: String = "") -> Dictionary:
	var replay := _request(request_id, ["unequip", ship_id, slot])
	if not replay.is_empty():
		return replay
	if not _can_service(ship_id):
		return _fail("舰娘未拥有，或正在海上执行任务")
	if slot not in ["equipment", "command"] or str(state.owned[ship_id].get(slot, "")).is_empty():
		return _fail("该槽位没有装配")
	var previous := state.duplicate(true)
	var instance_id := str(state.owned[ship_id][slot])
	if state.get("item_instances", {}).has(instance_id):
		state.item_instances[instance_id].location = "warehouse"
	state.owned[ship_id][slot] = ""
	if slot=="command": state.owned[ship_id].get_or_add("crews",{})["command"]=""
	state.inventory[slot] = int(state.inventory.get(slot, 0)) + 1
	return _commit(previous, "装配物已移回仓库")


func sell_common(request_id: String = "") -> Dictionary:
	var replay := _request(request_id, ["sell_common"])
	if not replay.is_empty():
		return replay
	if not state.get("active_run", {}).is_empty():
		return _fail("海上行动期间仓库交易已锁定")
	var previous := state.duplicate(true)
	var income := 0
	for key in ["scrap", "alloy"]:
		income += int(state.inventory.get(key, 0)) * int(config.get("salvage_prices", {}).get(key, 0))
		state.inventory[key] = 0
	if income <= 0:
		return _fail("仓库没有可兑换的普通货物")
	state.wallet.credits = int(state.wallet.credits) + income
	return _commit(previous, "普通货物已兑换 %d 银币" % income, {"income": income})


func _create_item(kind: String, gear_version: String = "gear-v3") -> String:
	state.item_sequence = int(state.get("item_sequence", 0)) + 1
	var id := "%s-%d" % [kind, int(state.item_sequence)]
	state.get_or_add("item_instances", {})[id] = {"id": id, "kind": kind, "location": "warehouse"}
	Meta.new(self).decorate(state.item_instances[id],gear_version)
	return id


func _can_service(id: String) -> bool:
	return state.get("active_run", {}).is_empty() and state.get("owned", {}).has(id)


func _xp_threshold(level: int) -> int:
	return 60 + level * 20


func _add_xp(ship: Dictionary, amount: int) -> void:
	ship.xp = int(ship.xp) + amount
	var maximum := PlayerGrowth.new(self).cap(ship)
	while int(ship.level) < maximum and int(ship.xp) >= _xp_threshold(int(ship.level)):
		ship.xp = int(ship.xp) - _xp_threshold(int(ship.level))
		ship.level = int(ship.level) + 1
	if int(ship.level) >= 30:
		ship.xp = 0


func _rarity(card: Dictionary) -> String:
	return str(card.get("gachaRarity", card.get("gacha_rarity", card.get("rarity", "common"))))


func _commit(previous: Dictionary, message: String, extra: Dictionary = {}) -> Dictionary:
	# Orders account for the state *before* departure, return or facility damage.
	# The opt-in hook is a no-op for accounts without an explicit order ledger.
	load("res://scripts/home_economy_v2.gd").checkpoint_account_transition(self,previous)
	var result := {"ok": true, "message": message}
	result.merge(extra, true)
	if not _pending_request.is_empty():
		state.get_or_add("transactions", {})[str(_pending_request.id)] = {"signature": _pending_request.signature, "result": result.duplicate(true)}
	_pending_request.clear()
	var saved := save_state()
	if not saved.ok:
		state = previous
		_sync_formation()
		return saved
	return result


func _sync_formation() -> void:
	formation.clear()
	for id in state.get("formation", []):
		formation.append(str(id))


func _read_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var stream := FileAccess.open(path, FileAccess.READ)
	if stream == null:
		return {}
	var parser := JSON.new()
	if parser.parse(stream.get_as_text()) != OK or not parser.data is Dictionary:
		return {}
	return parser.data


func _valid_state(value: Dictionary) -> bool:
	if int(value.get("version", -1)) != SAVE_VERSION or not value.get("wallet") is Dictionary or not value.get("owned") is Dictionary or not value.get("formation") is Array:
		return false
	for key in WALLET_KEYS:
		var amount: Variant = value.wallet.get(key, -1)
		if not (amount is int or amount is float) or not is_finite(float(amount)) or float(amount) < 0 or floor(float(amount)) != float(amount):
			return false
	for key in ["inventory", "active_run", "settled"]:
		if not value.get(key) is Dictionary:
			return false
	for key in ["history", "formation"]:
		if not value.get(key) is Array:
			return false
	for key in SALVAGE_KEYS:
		var amount: Variant = value.inventory.get(key, -1)
		if not (amount is int or amount is float) or not is_finite(float(amount)) or float(amount) < 0 or floor(float(amount)) != float(amount):
			return false
	if value.wallet.has("origins") and (not is_finite(float(value.wallet.origins)) or float(value.wallet.origins)<0 or floor(float(value.wallet.origins))!=float(value.wallet.origins)): return false
	if value.has("stamina") and (not value.stamina is Dictionary or int(value.stamina.get("value",-1))<0 or int(value.stamina.get("value",121))>120 or int(value.stamina.get("at",-1))<0): return false
	var unique_formation: Dictionary = {}
	for identity in value.formation:
		if not value.owned.has(str(identity)) or unique_formation.has(str(identity)):
			return false
		unique_formation[str(identity)] = true
	for id in value.owned:
		if not value.owned[id] is Dictionary:
			return false
		var row: Dictionary = value.owned[id]
		for key in ["hp", "ammo", "level", "xp"]:
			if not (row.get(key) is int or row.get(key) is float) or not is_finite(float(row.get(key, -1))):
				return false
		if int(row.get("mastery",0))<0 or int(row.get("mastery",0))>1000: return false
		if int(row.hp) < 0 or int(row.hp) > 100 or int(row.ammo) < 0 or int(row.ammo) > 100 or int(row.level) < 0 or int(row.level) > 30 or int(row.xp) < 0:
			return false
	return true


func _request(id: String, args: Array) -> Dictionary:
	_pending_request.clear()
	if id.is_empty():
		return {}
	if id.length() > 128:
		return _fail("交易编号过长")
	var signature := JSON.stringify(args)
	var old: Dictionary = state.get("transactions", {}).get(id, {})
	if not old.is_empty():
		if str(old.get("signature", "")) != signature:
			return _fail("交易编号已用于其他操作")
		var result: Dictionary = old.result.duplicate(true)
		result["duplicate"] = true
		return result
	_pending_request = {"id": id, "signature": signature}
	return {}


func _fail(message: String) -> Dictionary:
	_pending_request.clear()
	return {"ok": false, "message": message}
