extends SceneTree
const OUTPUT:String="res://../artifacts/island-war-v1/home-account/"
const VERSION:String="cas-island-war-v1"
var checks:int=0
var failures:Array[String]=[]
var account
var home
var core
var main_hash:String
var backup_hash:String
var runs:Array=[]
func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->bool:
	checks+=1
	if not value:failures.append(message);push_error(message)
	return value
func ask(request:Dictionary)->Dictionary:
	var response:Dictionary=core.request(request);check(response.get("ok",false),str(request.op)+" accepted: "+str(response.get("error","")));return response
func snapshot()->String:return str(ask({"op":"save","serialized":true}).get("serialized",""))
func restore_fixture()->void:
	for id in ["IBS-U-USN-ERMA-IOWA","CAS-H-USN-ENTERPRISE-1942"]:
		account.state.owned[id]=account._new_owned(id);account.state.owned[id].hp=100;account.state.owned[id].ammo=100
	for id in ["MCP-034","MCP-001","MCP-009"]:home._own_unit(id);home.state().units[id].condition=100;home.state().units[id].at=int(Time.get_unix_time_from_system())
	home.state().garrison=["IBS-U-USN-ERMA-IOWA","CAS-H-USN-ENTERPRISE-1942"];home.state().tactical_garrison=["MCP-034","MCP-001","MCP-009"]
	account.state.wallet.ammo_stock=10000
func voyage(mode:String,abandon:bool=false,weak:bool=false)->void:
	restore_fixture();var units:Array=["MCP-034","MCP-001","MCP-009"];var ships:Array=home.state().garrison.duplicate()
	if weak:
		ships=["CAS-O-APV-TIDEBRIDGE"];units=["MCP-034","MCP-009"];account.state.owned[ships[0]]=account._new_owned(ships[0]);account.state.owned[ships[0]].hp=10;account.state.owned[ships[0]].ammo=0
		home.state().garrison=ships.duplicate();home.state().tactical_garrison=units.duplicate()
		for id in units:home.state().units[id].condition=10;home.state().units[id].at=int(Time.get_unix_time_from_system())
		# Explicit QA legacy layout puts its depot in front of the unprotected command post.
		for building in home.state().buildings:building.cell={"x":9 if str(building.kind)=="hq" else 5,"y":4}
	var before_stock:Dictionary=home.state().resources.duplicate(true);var before_ammo:int=int(account.state.wallet.ammo_stock)
	var plan:Dictionary=home.prepare_island(mode,"old_arsenal" if weak else "shoal_watch",units,ships,"combat",[],714)
	if not check(plan.get("ok",false),"real native "+mode+" preview: "+str(plan.get("message",""))):return
	check(home.state().resources==before_stock and int(account.state.wallet.ammo_stock)==before_ammo,"native preview and cancel are read-only")
	if not ask(plan.request).get("ok",false):return
	var initial:String=snapshot()
	FileAccess.open(OUTPUT+mode+"-initial.json",FileAccess.WRITE).store_string(initial)
	FileAccess.open(OUTPUT+mode+"-request.json",FileAccess.WRITE).store_string(JSON.stringify(plan.request,"  "))
	var begun:Dictionary=home.begin(plan.request,initial)
	if not check(begun.get("ok",false),"exact native "+mode+" plan binds: "+str(begun.get("message",""))):return
	check(int(account.state.wallet.ammo_stock)==before_ammo-int(plan.loaded_ammo),"launch charges exactly previewed ammunition")
	check(not home.development().replenish("MCP-034",100,"qa-active").ok,"active real action blocks paid replacements")
	ask({"op":"littoral_autonomy","version":VERSION,"enabled":true});ask({"op":"step","seconds":20})
	var midway:String=snapshot();check(account.save_sortie(midway).ok,"island action saves midway with initial recording intact")
	var loaded=load("res://scripts/economy.gd").new(account.save_path);check(loaded.load_state().ok and str(loaded.state.active_run.home_replay.initial_snapshot)==initial,"midway save/load preserves initial snapshot and current action")
	var saved_view:Dictionary=core.view.duplicate(true);core.close();core=load("res://scripts/core_bridge.gd").new();ask({"op":"load","serialized":midway});check(home._same(saved_view.get("island_war"),core.view.get("island_war")),"native restore retains actual island state")
	if abandon:ask({"op":"littoral_abandon"})
	else:
		for index in range(90):
			if core.view.get("result")!=null:break
			ask({"op":"step","seconds":10})
	if not check(core.view.get("result")!=null,"real native "+mode+" reaches terminal state"):return
	var terminal:String=snapshot();var actual:Dictionary=core.view.duplicate(true);var frozen:Dictionary=account.state.active_run.home_frozen.duplicate(true)
	var forged:Dictionary=actual.duplicate(true);forged["tick"]=float(actual.tick)+1
	var ledger_before:Dictionary=account.state.duplicate(true);check(not home.settle(forged,terminal,abandon).ok and home._same(account.state,ledger_before),"forged result cannot charge or reward account")
	var result:Dictionary=home.settle(actual,terminal,abandon)
	if not check(result.get("ok",false),"native "+mode+" result settles atomically: "+str(result.get("message",""))):return
	var receipt:Dictionary=result.receipt
	check(int(account.state.wallet.ammo_stock)==before_ammo-int(plan.loaded_ammo)+int(receipt.ammo_returned),"loaded/returned ammunition conservation")
	for row in receipt.units:
		var expected:float=0 if bool(row.get("missing",false)) or bool(row.get("incapacitated",false)) else float(row.get("hp_percent",0))
		check(absf(home.condition(str(row.id))-expected)<.01,"actual own-person loss persisted "+str(row.id))
	for key in receipt.home_losses:check(int(receipt.home_losses[key])<=int(frozen.storage.exposed.get(key,0)),"actual plunder bounded by frozen exposed stock "+key)
	for key in home.RESOURCE_NAMES:check(int(home.state().resources[key])==int(before_stock[key])-int(receipt.home_losses.get(key,0))+int(receipt.rewards.get(key,0)),"resource conservation "+key)
	if abandon:check(receipt.rewards.is_empty(),"abandonment never grants NPC loot")
	elif weak:
		var total_loss:int=0
		for amount in receipt.home_losses.values():total_loss+=int(amount)
		check(not receipt.success and total_loss>0,"weak real defense is lost with actual positive warehouse plunder")
		check(int(home.state().resources.scrap)>=int(frozen.storage.protected.scrap),"actual failed defense preserves public resource floor")
	else:check(bool(receipt.success),"autonomous "+mode+" succeeds on real reachable objectives")
	var replay:Dictionary=home.replay_record(str(receipt.run_id));check(replay.ok and str(replay.record.initial_snapshot)==initial and str(replay.record.snapshot)==terminal and replay.record.commands.size()>0,"complete real commands and both snapshots exposed for replay")
	check(not home.state().development_v2.replays[str(receipt.run_id)].has("commands"),"command log is derived without duplicate account storage")
	var old:Dictionary=account.state.duplicate(true);check(home.settle(actual,terminal,abandon).get("duplicate",false) and home._same(account.state,old),"repeated settlement cannot heal, gain XP or pay rewards twice")
	var viewer=load("res://scripts/core_bridge.gd").new();check(viewer.request({"op":"replay","serialized":terminal,"tick":0}).get("ok",false),"record can replay from exact initial tick");viewer.close();check(home._same(account.state,old),"read-only replay preserves whole account")
	check(account.save_state().ok,"settled recording saves");loaded=load("res://scripts/economy.gd").new(account.save_path);loaded.load_state();var reopened=load("res://scripts/home_service.gd").new(loaded);check(reopened.replay_record(str(receipt.run_id)).ok,"complete replay survives account reload")
	runs.append({"mode":mode,"abandon":abandon,"success":receipt.success,"tick":actual.tick,"run_id":receipt.run_id,"loaded":plan.loaded_ammo,"returned":receipt.ammo_returned,"rewards":receipt.rewards,"losses":receipt.home_losses})
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT));main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	account=load("res://scripts/economy.gd").new(OUTPUT+"isolated-%d.json"%OS.get_process_id());check(account.new_profile().ok,"isolated ordinary account factory")
	account.state.commander.level=20;home=load("res://scripts/home_service.gd").new(account);home.state().unlocked=true;home.state().tutorial_complete=true
	for key in home.RESOURCE_NAMES:home.state().resources[key]=10000
	check(home.place("depot",Vector2i(6,3)).ok,"real own warehouse built before defense")
	core=load("res://scripts/core_bridge.gd").new();voyage("raid");voyage("defense");voyage("raid",true);voyage("defense",false,true);core.close()
	check(FileAccess.get_sha256("user://cas_port_v1.json")==main_hash and FileAccess.get_sha256("user://cas_port_v1.json.bak")==backup_hash,"formal main and backup unchanged")
	var receipt:Dictionary={"checks":checks,"failures":failures,"runs":runs,"core_sha256":FileAccess.get_sha256(OS.get_environment("CAS_SIM_PATH")),"scope":"actual native local island attack/defense/abandon, exact account settlement, save/load/replay"};FileAccess.open(OUTPUT+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(receipt,"  "));print("HOME_ISLAND_WAR ",JSON.stringify(receipt));quit(0 if failures.is_empty() else 1)
