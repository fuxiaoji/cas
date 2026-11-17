extends SceneTree
const Economy=preload("res://scripts/economy.gd")
const Service=preload("res://scripts/amphibious_expedition_service.gd")
const Core=preload("res://scripts/core_bridge.gd")
var failures:Array[String]=[]
var checks:int=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,title:String)->void:
	checks+=1
	if not ok:failures.append(title);push_error(title)
func run()->void:
	var account=Economy.new("user://tests/amphibious-expedition-%d.json"%OS.get_process_id());check(account.new_profile().get("ok",false),"isolated QA account")
	var service=Service.new(account);service.home._own_unit("MCP-034")
	var hull:String="IBS-U-USN-FLETCHER"
	if not account.state.owned.has(hull):account.state.owned[hull]=account._new_owned(hull)
	account.state.owned[hull].hp=100;account.state.owned[hull].ammo=100;account.state.wallet.ammo_stock=10000;account.state.wallet.fuel=10000
	account.formation.assign([hull]);account.state.formation=[hull]
	var fleet_service=load("res://scripts/fleet_manager.gd").new(account)
	# The normal fleet manager consumes this same owned formation.
	account.state.erase("fleets_v1")
	check(service.set_choices([{"unit_id":"MCP-034","carrier_identity":hull,"transport_kind":"landing_craft"}]).get("ok",false),"owned marine transport plan")
	var prepared:Dictionary=account.preview_sortie(42,false,{"kind":"salvage","id":"calm"})
	check(prepared.get("ok",false),"prepare regular extraction with army: "+str(prepared.get("message","")))
	if not prepared.get("ok",false):print(JSON.stringify({"checks":checks,"failures":failures}));quit(1);return
	check(prepared.get("gameplay_profile")==Service.VERSION,"new profile opt-in")
	var raw:Dictionary=account.native_start(prepared);check(raw.has("amphibious_expedition") and raw.has("expedition_v2"),"strict native extensions")
	var old:Dictionary=prepared.duplicate(true);old.gameplay_profile="cas-adventure-v2";old.erase("amphibious_expedition")
	check(not account.native_start(old).has("amphibious_expedition"),"old raw start has no new null key")
	var core=Core.new();var opened:Dictionary=core.request({"op":"new_salvage","seed":42,"start":raw});check(opened.get("ok",false),"real naval engine accepts owned land plan: "+str(opened.get("error","")))
	if opened.get("ok",false):
		var began:Dictionary=account.begin_sortie(42,false,{"kind":"salvage","id":"calm"});check(began.get("ok",false),"atomic ammo/fuel/stamina embark")
		var initial:Dictionary=core.request({"op":"save","serialized":true});check(account.save_sortie(str(initial.get("serialized",""))).get("ok",false),"save same land/naval voyage")
		var frozen:Dictionary=account.state.duplicate(true)
		check(not account.settle_sortie({"run_id":began.get("run_id",""),"success":true,"loot":{},"ships":[]}).get("ok",false),"forged outcome rejected")
		check(Service.same(frozen,account.state),"forged receipt leaves account unchanged")
		check(core.request({"op":"salvage_abandon"}).get("ok",false),"actual naval abandonment")
		var ended:Dictionary=core.request({"op":"save","serialized":true});var finish:Dictionary=service.finish(core.view,str(ended.get("serialized","")))
		check(finish.get("ok",false),"native terminal proof settles army and navy: "+str(finish.get("message","")))
		check(account.state.active_run.is_empty(),"one atomic cleared voyage")
		check(account.state.home_v1.units.has("MCP-034"),"protocol identity retained after loss")
	core.close()
	check(account.catalog.filter(func(c):return c.get("special_mode_scope")!=null).size()==4,"four special ships visible without changing recruit pool")
	print(JSON.stringify({"checks":checks,"failures":failures,"save":account.save_path}))
	quit(0 if failures.is_empty() else 1)
