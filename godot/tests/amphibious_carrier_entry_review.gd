extends SceneTree
## Isolated owned-account acceptance, not catalogue-only carrier coverage.
var failures:Array[String]=[]
var checks:int=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,title:String)->void:
	checks+=1
	if not ok:failures.append(title);push_error(title)
func run()->void:
	var core=load("res://scripts/core_bridge.gd").new()
	var cases:Array=[
		["CAS-H-USN-ENTERPRISE-1942","MCP-001","helicopter"],
		["CAS-H-IJN-SHOKAKU-1942","MCP-076","helicopter"],
		["CAS-O-LHA-RETURNLIGHT","MCP-027","helicopter"],
		["CAS-O-APV-TIDEBRIDGE","MCP-022","amphibious_vehicle"]]
	for i in range(cases.size()):
		var row:Array=cases[i]
		var account=load("res://scripts/economy.gd").new("user://tests/amphibious-carrier-%d-%d.json"%[OS.get_process_id(),i])
		account.new_profile()
		var service=load("res://scripts/amphibious_expedition_service.gd").new(account)
		# Explicit QA ownership; no changes after the actual voyage starts.
		account.state.owned[str(row[0])]=account._new_owned(str(row[0]))
		account.state.owned[str(row[0])].ammo=100
		account.state.wallet.ammo_stock=10000;account.state.wallet.fuel=10000
		load("res://scripts/fleet_manager.gd").new(account).set_members([str(row[0])])
		service.home._own_unit(str(row[1]))
		check(service.set_choices([{"unit_id":row[1],"carrier_identity":row[0],"transport_kind":row[2]}]).get("ok",false),"actual owned carrier choice "+str(row[0]))
		var began:Dictionary=account.begin_sortie(43,false,{"kind":"salvage","id":"calm"})
		check(began.get("ok",false),"actual account prepares carrier "+str(row[0]))
		if not began.get("ok",false):continue
		var opened:Dictionary=core.request({"op":"new_salvage","seed":43,"start":account.native_start(began)})
		check(opened.get("ok",false),"native carrier voyage opens "+str(row[0])+" "+str(opened.get("error","")))
		if not opened.get("ok",false):continue
		check(str(core.view.ships[0].characterId)==str(row[0]),"actual carrier identity preserved "+str(row[0]))
		core.request({"op":"salvage_abandon"})
		var saved:Dictionary=core.request({"op":"save","serialized":true})
		check(service.finish(core.view,str(saved.get("serialized",""))).get("ok",false),"actual carrier terminal proof settles "+str(row[0]))
	core.close();print(JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
