extends SceneTree
const Economy=preload("res://scripts/economy.gd")
const Tide=preload("res://scripts/tide_event_service.gd")
const Cargo=preload("res://scripts/cargo_service.gd")
var findings:Array=[]
func _initialize()->void:call_deferred("run")
func run()->void:
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../artifacts/tide-account-audit/fixtures.json"))
	var account=Economy.new("user://tests/independent-tide-audit-%d.json"%OS.get_process_id())
	account.new_profile();account.state.wallet.ammo_stock=100000;account.state.wallet.credits=100000;account.state.wallet.fuel=100000
	load("res://scripts/fleet_manager.gd").new(account).ensure()
	var prepared:Dictionary=account.preview_sortie(40,false,{"kind":"salvage","id":"calm"})
	prepared["mission"]=preload("res://scripts/meta_economy.gd").new(account).mission({"kind":"salvage","id":"calm"})
	prepared["content"]="salvage-v4";prepared["gameplay_profile"]="cas-adventure-v2";prepared["mode"]="salvage";prepared["cargo_v4"]=fixture.start.cargo_v4
	prepared.merge({"run_id":"audit-carried-only","fleet":[{"id":"IBS-U-USN-FLETCHER","name":"弗莱彻","hp":100,"ammo":100}],"cargo_transfer_v1":fixture.start.cargo_transfer_v1,"fuel_v1":fixture.start.fuel_v1},true)
	account.state.active_run=prepared.duplicate(true)
	var receipt:Dictionary={"run_id":prepared.run_id,"success":true,"coins":0,"loot":{"scrap":0,"alloy":0,"equipment":0,"command":0},"cargo_items":fixture.carried_view.salvage.cargo_grid.items,"fuel_receipt":fixture.carried_view.fuel_receipt,"ships":fixture.carried_view.salvage.ships}
	for item in receipt.cargo_items:receipt.loot[str(item.kind)]+=1
	var credits:int=int(account.state.wallet.credits);var origins:int=int(account.state.wallet.origins)
	var result:Dictionary=account.settle_sortie(receipt)
	findings.append({"case":"carried-only-no-new-search","ok":result.get("ok",false),"actualNewSearches":fixture.carried_view.salvage.cargo_grid.completed.size(),"rewards":result.get("receipt",{}).get("rewards",{}),"creditsDelta":int(account.state.wallet.credits)-credits,"originsDelta":int(account.state.wallet.origins)-origins,"bug":result.get("ok",false) and (int(account.state.wallet.credits)>credits or int(account.state.wallet.origins)>origins or result.get("receipt",{}).get("rewards",{}).has("commander_xp"))})
	var tide=Tide.new(account)
	var request:Dictionary={"op":"new_tide","seed":44,"character_id":"IBS-U-USN-FLETCHER","difficulty":"normal","intel_profile":"open-intel-v1"}
	var begin:Dictionary=tide.begin(request,str(fixture.normal_serialized))
	var swapped:Dictionary=tide.settle(fixture.hard_view,str(fixture.hard_serialized))
	findings.append({"case":"normal-active-hard-terminal-config-swap","begin":begin.get("ok",false),"accepted":swapped.get("ok",false),"bug":begin.get("ok",false) and swapped.get("ok",false)})
	var partial:Dictionary=fixture.start.cargo_transfer_v1.items[0].duplicate(true)
	partial.placement=[0.75,0,0]
	findings.append({"case":"fractional-placement-validation","accepted":Cargo.validate_receipt([partial],{partial.kind:1},true,"calm",true,fixture.start.cargo_transfer_v1.items),"bug":Cargo.validate_receipt([partial],{partial.kind:1},true,"calm",true,fixture.start.cargo_transfer_v1.items)})
	prepared.run_id="audit-fuel-fraction";account.state.active_run=prepared.duplicate(true)
	var fractional_fuel:Dictionary=receipt.duplicate(true);fractional_fuel.run_id=prepared.run_id;fractional_fuel.fuel_receipt.loaded=float(fractional_fuel.fuel_receipt.loaded)+0.25
	var fuel_result:Dictionary=account.settle_sortie(fractional_fuel)
	findings.append({"case":"fractional-fuel-loaded-receipt","accepted":fuel_result.get("ok",false),"bug":fuel_result.get("ok",false)})
	account.state.active_run={};account.state.wallet.tide_tokens=1000
	var rejected:=0
	for args in [["unknown",1],["origins",0],["origins",-1],["origins",101],["origins",6]]:
		var before:Dictionary=account.state.duplicate(true);var r:Dictionary=tide.purchase(str(args[0]),int(args[1]))
		if not r.get("ok",false) and JSON.stringify(account.state)==JSON.stringify(before):rejected+=1
	var max_purchase:Dictionary=tide.purchase("origins",5);var after_max:Dictionary=account.state.duplicate(true);var beyond:Dictionary=tide.purchase("origins",1)
	findings.append({"case":"event-shop-boundaries","fiveInvalidAtomic":rejected==5,"maxPurchase":max_purchase.get("ok",false),"limitAtomic":not beyond.get("ok",false) and JSON.stringify(after_max)==JSON.stringify(account.state),"bug":rejected!=5 or not max_purchase.get("ok",false) or beyond.get("ok",false)})
	var old_path:String=account.save_path;var blocker:String="user://tests/audit-write-blocker-%d"%OS.get_process_id()
	var block_file:=FileAccess.open(blocker,FileAccess.WRITE);block_file.store_string("isolated rollback probe");block_file.close();account.save_path=blocker+"/save.json"
	var before_failure:Dictionary=account.state.duplicate(true);var blocked:Dictionary=load("res://scripts/fuel_service.gd").new(account).purchase(100)
	findings.append({"case":"fuel-commit-failure-rollback","rejected":not blocked.get("ok",false),"walletAndStateRestored":JSON.stringify(account.state)==JSON.stringify(before_failure),"bug":blocked.get("ok",false) or JSON.stringify(account.state)!=JSON.stringify(before_failure)})
	account.save_path=old_path;DirAccess.remove_absolute(ProjectSettings.globalize_path(blocker))
	account.state.active_run={};request.difficulty="hard"
	var hard_begin:Dictionary=tide.begin(request,str(fixture.hard_initial_serialized));var token_before:int=int(account.state.wallet.tide_tokens)
	for variant in ["tick","primary","duration","fractional_tokens","success_without_boss"]:
		var altered:Dictionary=fixture.hard_view.duplicate(true)
		if variant=="tick":altered.tick=int(altered.tick)-1
		if variant=="primary":altered.result.primary=false
		if variant=="duration":altered.tide.outcome.duration=int(altered.tick)-1
		if variant=="fractional_tokens":altered.tide.outcome.event_tokens=float(altered.tide.outcome.event_tokens)+0.25
		if variant=="success_without_boss":altered.tide.outcome.boss_defeated=false
		var frozen:Dictionary=account.state.duplicate(true);var mismatch:Dictionary=tide.settle(altered,str(fixture.hard_serialized))
		findings.append({"case":"event-terminal-mismatch-"+variant,"rejected":not mismatch.get("ok",false),"atomic":JSON.stringify(account.state)==JSON.stringify(frozen),"bug":mismatch.get("ok",false) or JSON.stringify(account.state)!=JSON.stringify(frozen)})
		account.state=frozen
	var proper:Dictionary=tide.settle(fixture.hard_view,str(fixture.hard_serialized));var token_after:int=int(account.state.wallet.tide_tokens)
	var duplicate:Dictionary=tide.settle(fixture.hard_view,str(fixture.hard_serialized))
	var restored=Economy.new(account.save_path);var loaded:Dictionary=restored.load_state()
	findings.append({"case":"real-hard-win-correct-config-settle-and-reload","begin":hard_begin.get("ok",false),"settled":proper.get("ok",false),"tokensDelta":token_after-token_before,"expectedTokens":int(fixture.hard_view.tide.outcome.event_tokens),"duplicate":duplicate.get("duplicate",false),"reloadExactTokens":loaded.get("ok",false) and int(restored.state.wallet.tide_tokens)==token_after,"bug":not proper.get("ok",false) or token_after-token_before!=int(fixture.hard_view.tide.outcome.event_tokens) or not duplicate.get("duplicate",false) or int(account.state.wallet.tide_tokens)!=token_after})
	var warehouse=load("res://scripts/fleet_warehouse.gd").new(account)
	var original_id:String=str(fixture.start.cargo_transfer_v1.items[0].id)
	var unloaded:Dictionary=warehouse.transfer(original_id,"fleet");var back:Dictionary=warehouse.transfer(original_id,"base")
	var transfer:Dictionary=warehouse.prepare("audit-native-roundtrip");transfer.erase("ok")
	var native_start:Dictionary=fixture.start.duplicate(true);native_start.cargo_transfer_v1=transfer
	var bridge=load("res://scripts/core_bridge.gd").new();var launch:Dictionary=bridge.request({"op":"new_salvage","seed":40,"start":native_start});bridge.close()
	var physically_loaded:int=int(launch.get("data",{}).get("salvage",{}).get("cargo_grid",{}).get("kg",0))
	findings.append({"case":"warehouse-transfer-back-into-actual-native-hold","unload":unloaded.get("ok",false),"reload":back.get("ok",false),"nativeAccepted":launch.get("ok",false),"physicalKg":physically_loaded,"bug":not unloaded.get("ok",false) or not back.get("ok",false) or not launch.get("ok",false) or physically_loaded<=0})
	var passed:int=findings.filter(func(row):return not bool(row.get("bug",false))).size()
	var path:="res://../artifacts/tide-account-audit/review.json";var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify({"checks":findings.size(),"passed":passed,"findings":findings},"  "));file.close()
	print("INDEPENDENT_TIDE_ACCOUNT "+JSON.stringify(findings))
	for suffix in ["",".bak",".tmp"]:
		var target:String=account.save_path+suffix
		if FileAccess.file_exists(target):DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
	quit(0 if passed==findings.size() else 1)
