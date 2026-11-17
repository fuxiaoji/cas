extends SceneTree
const Economy=preload("res://scripts/economy.gd")
const Service=preload("res://scripts/home_service.gd")
const Bridge=preload("res://scripts/core_bridge.gd")
const SOURCE:String="user://cas_port_v1.json"
const OUTPUT:String="res://../artifacts/drag-littoral-v2/legacy-account/"
var checks:int=0
var failures:Array[String]=[]
var account
var service
var core
var account_path:String=""
var main_sha:String=""
var backup_sha:String=""
var report:Dictionary={"main_account_written":false,"local_npc_only":true}
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures.append(label);push_error(label)
	return ok
func write(name:String,value:Variant)->void:
	var file:=FileAccess.open(OUTPUT+name,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(value,"  "));file.close()
func ask(command:Dictionary,required:bool=true)->Dictionary:
	var response:Dictionary=core.request(command)
	if required:check(response.get("ok",false),"native "+str(command.get("op",""))+" "+str(response.get("error","")))
	return response
func snapshot()->String:
	var saved:Dictionary=ask({"op":"save","serialized":true});return str(saved.get("serialized",""))
func unchanged(before:Dictionary,disk:String,label:String)->void:
	check(service._same(before,account.state),label+" preserves all account fields")
	check(FileAccess.get_sha256(account_path)==disk,label+" preserves exact durable bytes")
func expect_failure(response:Dictionary,before:Dictionary,disk:String,label:String)->void:
	check(not response.get("ok",false),label+" rejected");unchanged(before,disk,label)
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	main_sha=FileAccess.get_sha256(SOURCE);backup_sha=FileAccess.get_sha256(SOURCE+".bak")
	account_path=OUTPUT+"isolated-home-%d.json"%OS.get_process_id()
	if not check(not FileAccess.file_exists(account_path),"fresh ordinary fixture independent of current active voyage"):return finish()
	account=Economy.new(account_path)
	if not check(account.load_state().get("ok",false),"create normal starter through ordinary account factory"):return finish()
	# Factory creation predates the ordinary fuel migration. Establish the same
	# normal loaded-account schema before asserting byte-for-byte conservation.
	check(account.load_state().get("ok",false) and int(account.state.wallet.get("fuel",0))==2400,"ordinary first-load fuel migration is explicit before conservation baseline")
	check(account.state.active_run.is_empty(),"fresh account has no voyage to discard")
	var normal_before:Dictionary=account.state.duplicate(true)
	account.state.erase("test_account")
	check(account._commit(normal_before,"隔离普通经济守恒测试，不运行测试账号自动补满").get("ok",false),"remove auto-refill marker only from the isolated conservation clone")
	report["normal_conservation_clone"]=true
	service=Service.new(account)
	check(service.catalogue.size()==20 and service.released().size()==20,"all twenty distinct catalogue identities now released")
	check(not service.state().unlocked and service.state().units.is_empty(),"ordinary account migration does not grant island or units")
	var before:Dictionary=account.state.duplicate(true);var disk:String=FileAccess.get_sha256(account_path)
	expect_failure(service.draw_units(1),before,disk,"gacha before island tutorial")
	expect_failure(service.place("turret",Vector2i(5,4)),before,disk,"construction before island ownership")
	var prepared:Dictionary=service.prepare_littoral("tutorial",42,["MCP-034"],["IBS-U-USN-FLETCHER"],"balanced",Service.LEGACY_BATTLE_VERSION)
	if not check(prepared.get("ok",false),"unowned 034 is loaned only for the first real tutorial"):return finish()
	check(not service.state().units.has("MCP-034"),"preparing training does not grant permanent 034")
	check(not service.prepare_littoral("raid",42,["MCP-034"],["IBS-U-USN-FLETCHER"]).get("ok",false),"raid locked before successful tutorial")
	core=Bridge.new()
	if not ask(prepared.request).get("ok",false):return finish()
	var initial_save:String=snapshot()
	var wrong:Dictionary=prepared.request.duplicate(true);wrong.ships[0].hp=1
	expect_failure(service.begin(wrong,initial_save),before,disk,"swapped ship condition in account plan")
	var begun:Dictionary=service.begin(prepared.request,initial_save)
	if not check(begun.get("ok",false),"real native initial snapshot binds to account plan"):return finish()
	check(int(account.state.wallet.ammo_stock)==int(before.wallet.ammo_stock)-int(prepared.loaded_ammo),"entry deducts actual loaded ammunition exactly once")
	check(account.state.active_run.home_frozen.borrowed_tutorial,"tutorial loan is explicitly frozen")
	before=account.state.duplicate(true);disk=FileAccess.get_sha256(account_path)
	expect_failure(service.settle(core.view,initial_save),before,disk,"nonterminal null outcome cannot settle or throw a script error")
	if not play_tutorial():return finish()
	var terminal:Dictionary=core.view.duplicate(true);var terminal_save:String=snapshot()
	write("tutorial-terminal.json",terminal);FileAccess.open(OUTPUT+"tutorial-save.json",FileAccess.WRITE).store_string(terminal_save)
	before=account.state.duplicate(true);disk=FileAccess.get_sha256(account_path)
	var forged:Dictionary=terminal.duplicate(true);forged.littoral.outcome.resources.scrap=int(forged.littoral.outcome.resources.get("scrap",0))+1
	expect_failure(service.settle(forged,terminal_save),before,disk,"forged finite home resource reward")
	forged=terminal.duplicate(true);forged.littoral.outcome.units[0].hp_percent=100
	if not service._same(forged,terminal):expect_failure(service.settle(forged,terminal_save),before,disk,"forged unit readiness")
	var settled:Dictionary=service.settle(terminal,terminal_save)
	if not check(settled.get("ok",false) and settled.receipt.success,"real tutorial victory settles through independent native replay"):return finish()
	check(service.state().unlocked and service.state().tutorial_complete and service.state().units.has("MCP-034"),"real victory grants island and permanent 034")
	check(int(service.state().tickets)==10,"first tutorial grants exactly ten dedicated protocol tickets")
	check(not bool(settled.receipt.borrowed),"result does not describe owned ammunition and damage as a free battle")
	var expected_ammo:int=0
	for row in terminal.littoral.outcome.ships:
		if not bool(row.sunk) and bool(row.recovered):expected_ammo+=int(floor(float(row.ammo_percent)))
	check(int(account.state.wallet.ammo_stock)==int(before.wallet.ammo_stock)+expected_ammo,"only recovered surviving ship ammunition is returned")
	before=account.state.duplicate(true);disk=FileAccess.get_sha256(account_path)
	check(service.settle(terminal,terminal_save).get("duplicate",false),"repeated tutorial settles idempotently");unchanged(before,disk,"repeat settlement")
	write("tutorial-receipt.json",settled)
	account=Economy.new(account_path);check(account.load_state().get("ok",false),"reload completed island account");service=Service.new(account)
	check(service._same(before,account.state),"island, ownership, damage and resources survive a complete account reload")
	transactions()
	finish()

func play_tutorial()->bool:
	var deployed:bool=false;var search_ordered:bool=false;var retreat_ordered:bool=false;var exit_ordered:bool=false;var restored:bool=false
	var beach:Dictionary=core.view.littoral.beaches[1]
	ask({"op":"route","fleet":1,"speed":35,"points":[beach.sea]})
	for second in range(470):
		var view:Dictionary=core.view;var group:Dictionary=view.littoral.groups[0]
		if view.get("result")!=null:break
		if not deployed and Vector2(float(view.ships[0].x),float(view.ships[0].y)).distance_to(Vector2(float(beach.sea.x),float(beach.sea.y)))<800:
			deployed=ask({"op":"littoral_deploy","unit_id":"MCP-034","beach":2,"insertion":"landing"}).get("ok",false)
		if str(group.stage)=="ground" and not search_ordered:search_ordered=ask({"op":"littoral_order","unit_id":"MCP-034","action":"search","target":1}).get("ok",false)
		if bool(view.littoral.land.ruins[0].searched) and not retreat_ordered:retreat_ordered=ask({"op":"littoral_order","unit_id":"MCP-034","action":"retreat"}).get("ok",false)
		if str(group.stage)=="recovered" and not exit_ordered:exit_ordered=ask({"op":"route","fleet":1,"speed":35,"points":[{"x":5500,"y":13500}]}).get("ok",false)
		if exit_ordered:
			ask({"op":"littoral_extract"},false)
			if core.view.get("result")!=null:break
		if not restored and search_ordered:
			var raw:String=snapshot();var observed:Dictionary=core.view.duplicate(true)
			var wallet_before_restart:Dictionary=account.state.wallet.duplicate(true)
			check(account.save_sortie(raw).get("ok",false),"save active real transport and search state")
			core.close();account=Economy.new(account_path);check(account.load_state().get("ok",false),"reload active island account");service=Service.new(account);core=Bridge.new()
			var loaded:Dictionary=ask({"op":"load","serialized":str(account.state.active_run.snapshot)}).get("data",{})
			check(service._same(wallet_before_restart,account.state.wallet),"normal account restart never refills ammunition or other resource balances")
			check(service._same(loaded.littoral,observed.littoral) and service._same(loaded.ships,observed.ships),"native restart exactly preserves landed troops, cargo, carrier and warship state")
			restored=true
		ask({"op":"step","seconds":1})
	report["tutorial_driver"]={"deployed":deployed,"searched":search_ordered,"retreat":retreat_ordered,"exit":exit_ordered,"restarted":restored,"tick":core.view.get("tick"),"terminal":core.view.get("result")}
	return check(core.view.get("result")!=null and core.view.littoral.get("outcome",{}).get("success",false),"actual tutorial finishes by transport, search, physical return and extraction")

func transactions()->void:
	var before:Dictionary=account.state.duplicate(true);var disk:String=FileAccess.get_sha256(account_path)
	var history:Dictionary=account.state.owned.duplicate(true);var wallet:Dictionary=account.state.wallet.duplicate(true)
	var draw:Dictionary=service.draw_units(10,"review-home-draw-1")
	check(draw.get("ok",false) and draw.results.size()==10,"dedicated real ten-draw transaction returns ten results")
	for row in draw.get("results",[]):check(Service.RELEASED.has(str(row.id)),"paid recruitment never returns an unimplemented unit")
	check(int(service.state().tickets)==0 and int(account.state.wallet.origins)==int(wallet.origins),"ten tutorial tickets pay first, without charging origins")
	check(service._same(history,account.state.owned),"recruitment never duplicates or rewrites naval identities")
	var after:Dictionary=account.state.duplicate(true)
	check(service.draw_units(10,"review-home-draw-1").get("ok",false),"repeating draw request returns original receipt")
	check(service._same(after,account.state),"repeated draw receipt does not charge or add units twice")
	account.state.erase("test_account");before=account.state.duplicate(true);disk=FileAccess.get_sha256(account_path)
	expect_failure(service.unlock_test_units(),before,disk,"normal profile cannot use test unlock")
	account.state.test_account="cas-local-qa-2026-11-12"
	check(service.unlock_test_units().get("ok",false),"explicit marked clone unlocks twenty implemented units")
	account.state.erase("test_account")
	check(service.state().units.size()==20,"all twenty completed personalities available in marked clone")
	before=account.state.duplicate(true);disk=FileAccess.get_sha256(account_path)
	expect_failure(service.place("solar",Vector2i(0,0)),before,disk,"building outside actual seeded island")
	check(service.place("solar",Vector2i(5,4)).get("ok",false),"build a real power generator on an empty island tile")
	before=account.state.duplicate(true);disk=FileAccess.get_sha256(account_path)
	expect_failure(service.place("turret",Vector2i(5,4)),before,disk,"overlapping occupied tile")
	var at:int=int(service.state().last_collect)
	var rates:Dictionary=service.production();var energy:int=int(service.state().resources.energy)
	var collected:Dictionary=service.collect(at+86400)
	check(collected.get("ok",false) and int(service.state().resources.energy)==energy+int(rates.energy)*8,"offline gathering is capped at eight hours")
	check(service.collect(at+86400).get("ok",false),"collecting at same instant is legal")
	check(int(service.state().resources.energy)==energy+int(rates.energy)*8,"same elapsed interval cannot be collected twice")
	var saved_path:String=account.save_path;var blocker:String=OUTPUT+"blocked-directory-%d"%OS.get_process_id()
	FileAccess.open(blocker,FileAccess.WRITE).store_string("regular file blocks save directory")
	before=account.state.duplicate(true);disk=FileAccess.get_sha256(account_path);account.save_path=blocker+"/account.json"
	expect_failure(service.place("forge",Vector2i(7,4)),before,disk,"real failed durable building commit")
	account.save_path=saved_path
	check(service.set_garrison(["IBS-U-USN-FLETCHER"]).get("ok",false),"owned single garrison persists")
	before=account.state.duplicate(true);disk=FileAccess.get_sha256(account_path)
	expect_failure(service.set_garrison(["IBS-U-USN-FLETCHER","IBS-U-USN-FLETCHER"]),before,disk,"duplicate garrison identity")
	service.state().units["MCP-034"].condition=0;service.state().units["MCP-034"].at=at
	check(is_equal_approx(service.condition("MCP-034",at+1800),1.0),"lost body recovers exactly one percent per thirty minutes without a clinic")
	check(service.state().units.has("MCP-034"),"a zero-readiness loss never deletes its personality core")
	write("transaction-state.json",account.state.home_v1)

func finish()->void:
	if core!=null:
		report["runtime"]=load("res://tests/home_runtime_evidence.gd").capture(core)
		if not OS.has_environment("CAS_SIM_PATH"):check(bool(report.runtime.verified_default),"actual native PID path and SHA match default manifest without override")
		core.close()
	if not main_sha.is_empty():check(FileAccess.get_sha256(SOURCE)==main_sha,"actual main profile bytes remain untouched")
	if not backup_sha.is_empty():check(FileAccess.get_sha256(SOURCE+".bak")==backup_sha,"actual main backup bytes remain untouched")
	report.merge({"checks":checks,"failures":failures,"passed":failures.is_empty(),"source":ProjectSettings.globalize_path(SOURCE),"source_sha256":main_sha,"source_after_sha256":FileAccess.get_sha256(SOURCE),"backup_sha256":backup_sha,"backup_after_sha256":FileAccess.get_sha256(SOURCE+".bak"),"profile":ProjectSettings.globalize_path(account_path),"native_override":OS.get_environment("CAS_SIM_PATH")})
	write("receipt.json",report);print("HOME_ACCOUNT "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
