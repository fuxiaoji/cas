extends RefCounted
## Versioned account growth and purchases, isolated from historical CAS cards.
var _account: WeakRef
var account:
	get: return _account.get_ref()
var config: Dictionary

func _init(owner) -> void:
	_account = weakref(owner)
	config = JSON.parse_string(FileAccess.get_file_as_string("res://data/meta-economy.json"))

func ensure() -> void:
	var state: Dictionary = account.state
	if state.is_empty(): return
	preload("res://scripts/player_growth.gd").new(account).ensure()
	state.wallet.get_or_add("origins", int(config.initial_origins))
	state.get_or_add("stamina", {"value":int(config.stamina_max),"at":int(Time.get_unix_time_from_system())})
	state.get_or_add("supply_claims", {})
	state.get_or_add("mission_rewards", {})
	state.get_or_add("mastery_reward_claims", {})
	state["meta_version"] = 2
	for row in state.owned.values():
		row.get_or_add("mastery", 0)
		row.get_or_add("crews", {})
		for slot in config.crew_slots: row.crews.get_or_add(slot, "")
	# Older local saves had aggregate inventory counts and literal equipped ids.
	# Materialize those assets once before exposing the instance-based UI.
	for identity in state.owned:
		var row: Dictionary=state.owned[identity]
		for slot in ["equipment","command"]:
			var old_id:=str(row.get(slot,""))
			if not old_id.is_empty() and not state.item_instances.has(old_id):
				var instance_id: String=account._create_item(slot,"gear-v1")
				state.item_instances[instance_id].location=str(identity)
				if slot=="command":
					state.item_instances[instance_id].slot="command"
					state.item_instances[instance_id].name="指挥水手组"
					state.item_instances[instance_id].main.stat="command"
					row.crews.command=instance_id
				row[slot]=instance_id
	for kind in ["equipment","command"]:
		var actual:=0
		for item in state.item_instances.values():
			if str(item.get("kind",""))==kind and str(item.get("location","warehouse"))=="warehouse":actual+=1
		for unused in range(maxi(0,int(state.inventory.get(kind,0))-actual)):account._create_item(kind,"gear-v1")
	for item in state.get("item_instances", {}).values():
		if not item.has("bonus_bp"): decorate(item)
		if str(item.get("kind",""))=="equipment" and str(item.get("gear_type",""))=="": item.main.stat="all"
	for row in state.owned.values():
		var old_id := str(row.get("command", ""))
		if not old_id.is_empty() and row.crews.command == "": row.crews.command = old_id

func stamina(now: int = -1) -> Dictionary:
	ensure()
	var time := int(Time.get_unix_time_from_system()) if now < 0 else now
	var saved: Dictionary = account.state.stamina
	var elapsed := maxi(0, time-int(saved.at))
	var value := mini(int(config.stamina_max), int(saved.value)+int(elapsed/int(config.stamina_regen_seconds)))
	return {"value":value,"max":int(config.stamina_max),"now":maxi(time,int(saved.at)),"next_seconds":0 if value==int(config.stamina_max) else int(config.stamina_regen_seconds)-elapsed%int(config.stamina_regen_seconds)}

func spend_stamina(amount: int) -> void:
	var current := stamina()
	var elapsed := maxi(0,int(current.now)-int(account.state.stamina.at))
	var remainder := 0 if int(current.value)==int(config.stamina_max) else elapsed%int(config.stamina_regen_seconds)
	account.state.stamina={"value":int(current.value)-amount,"at":int(current.now)-remainder}

func supply_catalog() -> Array:
	ensure()
	var out: Array = []
	for entry in config.items:
		var row: Dictionary = entry.duplicate(true)
		if row.has("ship_ids") and not row.ship_ids.all(func(id):return account._cards.has(str(id)) and account._cards[str(id)].get("playable",false)): continue
		row["owned"] = row.get("ship_ids",[]).size()>0 and row.ship_ids.all(func(id):return account.state.owned.has(str(id)))
		row["limit_remaining"] = maxi(0,int(row.get("limit",999999))-int(account.state.supply_claims.get(str(row.id),0)))
		out.append(row)
	return out

func purchase(id: String, count: int = 1, request_id: String = "") -> Dictionary:
	ensure()
	var replay: Dictionary = account._request(request_id,["purchase",id,count])
	if not replay.is_empty(): return replay
	if not account.state.active_run.is_empty(): return account._fail("海上行动期间不能交易")
	var item: Dictionary = {}
	for row in supply_catalog():
		if str(row.id)==id: item=row
	if item.is_empty() or count<1 or count>100: return account._fail("采购项目或数量无效")
	if bool(item.owned) or count>int(item.limit_remaining): return account._fail("该舰已拥有或礼包已达限购次数")
	var currency := str(item.currency)
	var price := int(item.cost)*count
	if int(account.state.wallet.get(currency,0))<price: return account._fail("元词不足" if currency=="origins" else "银币不足")
	var previous: Dictionary=account.state.duplicate(true)
	account.state.wallet[currency]=int(account.state.wallet[currency])-price
	for key in item.get("grants",{}): account.state.wallet[key]=int(account.state.wallet.get(key,0))+int(item.grants[key])*count
	for identity in item.get("ship_ids",[]):
		if not account.state.owned.has(str(identity)): account.state.owned[str(identity)]=account._new_owned(str(identity))
		else: account.state.wallet.medals=int(account.state.wallet.medals)+int(account.config.gacha.duplicate_medals.get(account._rarity(account._cards[str(identity)]),1))
	account.state.supply_claims[id]=int(account.state.supply_claims.get(id,0))+count
	return account._commit(previous,"%s已入库"%str(item.name),{"item":id,"count":count,"cost":price,"currency":currency})

func decorate(item: Dictionary, version: String = "gear-v1") -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(str(item.id).hash()) ^ 517203
	var equipment := str(item.get("kind",""))=="equipment"
	var quality := rng.randi_range(1,5)
	if version=="gear-v2" or version.begins_with("gear-v3"):
		var draw := rng.randi_range(1,1000)
		var cumulative := 0
		for tier in config.gear_tiers:
			cumulative += int(tier.weight)
			if draw <= cumulative:
				quality = int(tier.quality)
				break
	if version=="gear-v3-t2":quality=maxi(2,quality)
	if version=="gear-v3-t3":quality=maxi(3,quality)
	item["drop_table_version"] = version
	item["quality"]=quality
	item["slot"]="equipment" if equipment else str(config.crew_slots[rng.randi_range(0,3)])
	# Existing command-team instances retain their old legal slot on migration.
	if not equipment and str(item.get("location","warehouse"))!="warehouse": item.slot="command"
	item["name"]="精调舰装" if equipment else str(config.crew_names[item.slot])
	item["bonus_bp"]=quality*20 if equipment else 5+quality*4
	if version=="gear-v2" or version.begins_with("gear-v3"):
		var tier: Dictionary = config.gear_tiers[quality-1]
		item["rarity_name"] = str(tier.name)
		item["drop_weight"] = int(tier.weight)
		item["bonus_bp"] = int(tier.equipment_bp if equipment else tier.crew_bp)
		item["name"] = str(tier.name) + ("舰装" if equipment else str(config.crew_names[item.slot]))
	var primary := "all" if equipment else str({"helmsman":"speed","gunnery":"firepower","damage_control":"hp","command":"command"}[item.slot])
	var secondary := str(["hp","speed","firepower","command"][rng.randi_range(0,3)])
	if secondary==primary: secondary="speed" if primary!="speed" else "hp"
	var sub := 0 if equipment else mini(7,quality+2)
	item["main"]={"stat":primary,"bp":int(item.bonus_bp)-sub}
	item["sub"]={"stat":secondary,"bp":sub}
	if equipment and version.begins_with("gear-v3"):
		var types:Array=preload("res://data/player-growth.tres").gear_types
		var type:Dictionary=types[rng.randi_range(0,types.size()-1)]
		item["gear_type"]=str(type.id);item["art_index"]=int(type.atlas)
		item.name=str(item.get("rarity_name",""))+str(type.name)
		item.main={"stat":str(type.stat),"bp":int(item.bonus_bp)}

func gear_drop_table() -> Array:
	return config.gear_tiers.duplicate(true)

func prepare_service(ids: Array, ammo_target: int = 100, service: String = "both") -> Dictionary:
	if not account.state.active_run.is_empty(): return account._fail("请返港后整备")
	if ids.is_empty() or ammo_target<10 or ammo_target>100 or service not in ["repair","ammo","both"]: return account._fail("请选择舰娘与10–100份弹药计划")
	var seen: Dictionary={}
	var rows: Array=[]
	var repair_cost:=0
	for identity in ids:
		var id:=str(identity)
		if seen.has(id) or not account.state.owned.has(id): return account._fail("整备舰娘重复或未拥有")
		seen[id]=true
		var hull: Dictionary=account.state.owned[id]
		var missing:=maxi(0,100-int(hull.hp))
		if bool(hull.get("protected",false)) or not bool(hull.get("canNavigate",true)):missing=maxi(1,missing)
		var price:=missing*int(account.config.get("repair_credit_per_percent",2)) if service!="ammo" else 0
		repair_cost+=price
		rows.append({"id":id,"hp_before":int(hull.hp),"hp_after":100 if service!="ammo" else int(hull.hp),"ammo_before":int(hull.ammo),"ammo_after":ammo_target if service!="repair" else int(hull.ammo),"repair_cost":price})
	var required:=0
	for row in rows: required+=int(row.ammo_after)
	var stock:=int(account.state.wallet.ammo_stock)
	var packs:=int(ceil(float(maxi(0,required-stock))/100.0)) if service!="repair" else 0
	var ammo_cost:=packs*160
	var cost:=repair_cost+ammo_cost
	return {"ok":true,"service":service,"ships":rows,"repair_cost":repair_cost,"ammo_cost":ammo_cost,"cost":cost,"currency":"credits","ammo_purchase":packs*100,"ammo_stock_before":stock,"ammo_stock_after":stock+packs*100,"planned_ammo":required,"affordable":int(account.state.wallet.credits)>=cost,"message":"弹药按100份/160银币补足仓库；确认出航时扣除装载量"}

func service_all(ids: Array, ammo_target: int = 100, request_id: String = "", service: String = "both") -> Dictionary:
	var replay: Dictionary=account._request(request_id,["service_all",ids,ammo_target,service])
	if not replay.is_empty():return replay
	var preview:=prepare_service(ids,ammo_target,service)
	if not bool(preview.ok):return preview
	if not bool(preview.affordable):return account._fail("整备需要%d银币"%int(preview.cost))
	var previous: Dictionary=account.state.duplicate(true)
	account.state.wallet.credits=int(account.state.wallet.credits)-int(preview.cost)
	account.state.wallet.ammo_stock=int(preview.ammo_stock_after)
	for row in preview.ships:
		var hull: Dictionary=account.state.owned[str(row.id)]
		if service!="ammo": hull.hp=100;hull.protected=false;hull.canNavigate=true
		if service!="repair": hull.ammo=ammo_target
	return account._commit(previous,"舰队整备完成；装载计划已备齐",{"preview":preview,"cost":preview.cost})

func item_for(id: String) -> Dictionary:
	return account.state.get("item_instances",{}).get(id,{}).duplicate(true)

func gear_inventory(ship_id: String, slot: String) -> Array:
	ensure()
	var out: Array=[]
	for item in account.state.item_instances.values():
		if str(item.get("slot",""))==slot and str(item.get("location","warehouse")) in ["warehouse",ship_id]: out.append(item.duplicate(true))
	return out

func assign_item(ship_id: String, slot: String, instance_id: String) -> Dictionary:
	ensure()
	if not account._can_service(ship_id) or (slot!="equipment" and not config.crew_slots.has(slot)): return account._fail("该舰或装配槽不可用")
	var ship: Dictionary=account.state.owned[ship_id]
	var current := str(ship.get("equipment","")) if slot=="equipment" else str(ship.crews.get(slot,""))
	if current==instance_id: return account._fail("该槽位已经采用此配置")
	if not instance_id.is_empty():
		var item:=item_for(instance_id)
		if item.is_empty() or str(item.slot)!=slot or str(item.location)!="warehouse": return account._fail("装备不存在、槽位不符或已被其他舰娘使用")
	var previous: Dictionary=account.state.duplicate(true)
	if not current.is_empty():
		account.state.item_instances[current].location="warehouse"
		var kind:=str(account.state.item_instances[current].kind)
		account.state.inventory[kind]=int(account.state.inventory.get(kind,0))+1
	if not instance_id.is_empty():
		account.state.item_instances[instance_id].location=ship_id
		var kind:=str(account.state.item_instances[instance_id].kind)
		account.state.inventory[kind]=maxi(0,int(account.state.inventory.get(kind,0))-1)
	if slot=="equipment": ship.equipment=instance_id
	else:
		ship.crews[slot]=instance_id
		if slot=="command": ship.command=instance_id
	return account._commit(previous,"装配已更新" if not instance_id.is_empty() else "已卸下并退回仓库")

func growth_profile(ship_id: String) -> Dictionary:
	ensure()
	var ship: Dictionary=account.state.owned.get(ship_id,{})
	if ship.is_empty(): return {}
	var equipment:=item_for(str(ship.get("equipment","")))
	var crew: Dictionary={}
	var stats: Dictionary={"hp":0,"speed":0,"firepower":0,"command":0}
	for slot in config.crew_slots:
		var item:=item_for(str(ship.crews.get(slot,"")))
		crew[slot]=item
		for affix in [item.get("main",{}),item.get("sub",{})]:
			if stats.has(str(affix.get("stat",""))): stats[str(affix.stat)]+=int(affix.bp)
	var level:=clampi(int(ship.level),0,30)
	var growth:=0.05*float(level)/30.0
	var gear:=float(equipment.get("bonus_bp",0))/10000.0
	var bonuses: Dictionary={}
	var profile:=str(equipment.get("gear_type",""))
	for stat in ["hp","speed","firepower"]: bonuses[stat]=1.0+growth+gear*_gear_weight(profile,stat)+float(stats[stat])/10000.0
	bonuses["base_hit"]=1.0+0.1*float(clampi(int(ship.mastery),0,1000))/1000.0+gear*_gear_weight(profile,"base_hit")
	bonuses["command"]=0.35+float(stats.command)/10000.0
	return {"level":level,"max_level":30,"level_cap":preload("res://scripts/player_growth.gd").new(account).cap(ship),"ascension":int(ship.get("ascension",0)),"xp":int(ship.xp),"xp_next":account._xp_threshold(level),"mastery":int(ship.mastery),"mastery_max":1000,"bonuses":bonuses,"equipment":equipment,"crews":crew,"scope":"自有舰PvE；同步概率仅打捞生效，历史借用维持原卡"}

func _gear_weight(profile:String,stat:String) -> float:
	if profile=="":return 1.0 if stat in ["hp","speed","firepower"] else 0.0
	if profile=="balanced":return float({"hp":.34,"speed":.33,"firepower":.33}.get(stat,0.0))
	return 1.0 if {"fire_control":"base_hit","propulsion":"speed","bulkhead":"hp","ballistics":"firepower"}.get(profile,"")==stat else 0.0

func mastery_rewards(ship_id: String) -> Array:
	ensure()
	if not account.state.owned.has(ship_id): return []
	var claims: Dictionary=account.state.mastery_reward_claims.get(ship_id,{})
	var mastery:=int(account.state.owned[ship_id].get("mastery",0))
	var out: Array=[]
	for threshold in [250,500,750,1000]:
		var claimed:=bool(claims.get(str(threshold),false))
		var available:bool=mastery>=int(threshold) and not claimed
		out.append({"threshold":threshold,"status":"claimed" if claimed else ("ready" if available else "locked"),"claimed":claimed,"available":available,"grants":{"origins":5,"credits":50}})
	return out

func claim_mastery_reward(ship_id: String, threshold: int) -> Dictionary:
	ensure()
	if not account._can_service(ship_id): return account._fail("请返港后为已拥有舰娘领取熟练奖励")
	var entry: Dictionary={}
	for row in mastery_rewards(ship_id):
		if int(row.threshold)==threshold: entry=row
	if entry.is_empty(): return account._fail("熟练里程碑不存在")
	if bool(entry.claimed): return {"ok":true,"duplicate":true,"message":"该舰的熟练里程碑已领取，未重复发奖"}
	if not bool(entry.available): return account._fail("尚未达到该熟练度")
	var previous: Dictionary=account.state.duplicate(true)
	for currency in entry.grants: account.state.wallet[currency]=int(account.state.wallet.get(currency,0))+int(entry.grants[currency])
	account.state.mastery_reward_claims.get_or_add(ship_id,{})[str(threshold)]=true
	return account._commit(previous,"熟练奖励已到账：5元词与50银币",{"ship_id":ship_id,"threshold":threshold,"grants":entry.grants})

func week_key() -> String:
	var day:=int(floor((Time.get_unix_time_from_system()+28800.0)/86400.0))
	return str(day-posmod(day+3,7))

func mission_catalog(kind: String) -> Array:
	ensure()
	var out: Array=[]
	var used:=int(account.state.mission_rewards.get("ladder:"+week_key(),0))
	for mission in config.missions:
		if str(mission.kind)!=kind: continue
		var row: Dictionary=mission.duplicate(true)
		row["unlocked"]=int(account.player_profile().level)>=int(row.get("player_level",1))
		row["remaining"]=maxi(0,int(row.get("limit",0))-used) if kind=="ladder" else -1
		out.append(row)
	return out

func mission(raw: Dictionary = {}) -> Dictionary:
	var kind:=str(raw.get("kind","salvage"))
	if kind=="salvage" and str(raw.get("id","salvage")) in ["salvage","calm","standard","hazard"]:
		var difficulty:String=str(raw.get("id","calm"))
		if difficulty=="salvage":difficulty=str(account.state.get("salvage_options",{}).get("difficulty","calm"))
		return {"kind":"salvage","id":difficulty,"loot_kind":"scrap","cost_stamina":int({"calm":8,"standard":14,"hazard":20}.get(difficulty,8)),"rewards":{},"unlocked":true}
	var id:=str(raw.get("id","salvage"))
	for row in mission_catalog(kind):
		if str(row.id)==id: return row
	return {}

func native_start(run: Dictionary) -> Dictionary:
	var fleet: Array=[]
	var growth:=str(run.get("owned_growth",""))
	for row in run.get("fleet",[]):
		var hull: Dictionary={"id":str(row.id),"hp":int(row.hp),"ammo":int(row.ammo),"level":int(row.get("level",0)),"equipment":not str(row.get("equipment","")).is_empty(),"command":not str(row.get("command","")).is_empty()}
		if not growth.is_empty():
			hull["mastery"]=int(row.get("mastery",0))
			hull["equipment_bonus_bp"]=int(row.get("equipment_bonus_bp",0))
			if not str(row.get("equipment_profile","")).is_empty():hull["equipment_profile"]=str(row.equipment_profile)
			hull["crew"]=row.get("crew",{}).duplicate(true)
		fleet.append(hull)
	var task: Dictionary=run.get("mission",{})
	var prepared:Dictionary={"content":str(run.get("content","salvage-v2")),"fleet":fleet,"groups":run.get("groups",[]).duplicate(true),"weather":"salvage-weather-v1","owned_growth":growth,"mission":{"kind":str(task.get("kind","salvage")),"id":str(task.get("id","salvage")),"player_budget":int(task.get("player_budget",0)),"enemy_budget":int(task.get("enemy_budget",0)),"loot_kind":str(task.get("loot_kind","scrap"))}}

	if str(run.get("content",""))=="salvage-v4":prepared["cargo_v4"]=run.cargo_v4.duplicate(true)
	if not str(run.get("gameplay_profile", "")).is_empty():prepared["gameplay_profile"]=str(run.gameplay_profile)
	if str(run.get("gameplay_profile", "")) in ["cas-adventure-v2","cas-adventure-v3"]:prepared["expedition_v2"]=run.expedition_v2.duplicate(true)
	if str(run.get("gameplay_profile", ""))=="cas-adventure-v3":prepared["amphibious_expedition"]=run.amphibious_expedition.duplicate(true)
	for extension in ["fuel_v1","cargo_transfer_v1"]:
		if run.has(extension):prepared[extension]=run[extension].duplicate(true)
	if run.has("intel_profile"):prepared["intel_profile"]=str(run.intel_profile)
	return prepared

func enrich_fleet(fleet: Array) -> void:
	for row in fleet:
		var growth:=growth_profile(str(row.id))
		row["mastery"]=int(growth.get("mastery",0))
		row["equipment_bonus_bp"]=int(growth.get("equipment",{}).get("bonus_bp",0))
		row["equipment_profile"]=str(growth.get("equipment",{}).get("gear_type",""))
		row["crew"]={}
		for slot in config.crew_slots:
			var item: Dictionary=growth.get("crews",{}).get(slot,{})
			if not item.is_empty(): row.crew[slot]={"primary":str(item.main.stat),"primary_bp":int(item.main.bp),"secondary":str(item.sub.stat),"secondary_bp":int(item.sub.bp)}

func settle(active: Dictionary, success: bool, returned: Array, loot: Dictionary = {}) -> Dictionary:
	ensure()
	if str(active.get("content","")) not in ["salvage-v2","salvage-v3","salvage-v4"] or str(active.get("mode",""))=="basic": return {}
	for hull in returned:
		var id:=str(hull.get("id",""))
		if account.state.owned.has(id):
			var earned:=clampi(int(hull.get("practice",0)),0,30)
			account.state.owned[id].mastery=mini(1000,int(account.state.owned[id].get("mastery",0))+earned)
	if not success: return {}
	var task: Dictionary=active.get("mission",{}).duplicate(true)
	if str(task.get("kind",""))!="ladder" and not loot.values().any(func(amount):return int(amount)>0): return {}
	var rewards: Dictionary=task.get("rewards",{}).duplicate(true)
	if str(task.get("kind",""))=="ladder":
		var key:="ladder:"+week_key()
		var used:=int(account.state.mission_rewards.get(key,0))
		if used>=int(task.get("limit",3)): rewards.origins=0
		account.state.mission_rewards[key]=used+1
	for key in rewards: account.state.wallet[key]=int(account.state.wallet.get(key,0))+int(rewards[key])
	var earned:Dictionary=account.grant_player_xp("voyage:"+str(active.get("run_id","")),int(task.get("commander_xp",60)))
	if int(earned.get("xp",0))>0:rewards["commander_xp"]=int(earned.xp)
	return rewards
