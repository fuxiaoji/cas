extends SceneTree
const Economy=preload("res://scripts/economy.gd")
const Bridge=preload("res://scripts/core_bridge.gd")
const Ware=preload("res://scripts/fleet_warehouse.gd")
const Fuel=preload("res://scripts/fuel_service.gd")
var account
var core
var checks:int=0
var failures:Array=[]
var runs:Array=[]
var current:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures.append(label);push_error(label)
	return ok
func issue(q:Dictionary)->Dictionary:
	var r:Dictionary=core.request(q)
	check(r.get("ok",false),"native "+str(q.op)+" "+str(r.get("error","")))
	return r.get("data",{})
func start(seed:int,percent:int=100)->bool:
	check(account.service_all(account.formation,100,"","both").get("ok",false),"real paid repair and ammo preparation")
	check(Fuel.new(account).configure(percent).get("ok",false),"save fuel percentage "+str(percent))
	var stock:int=int(account.state.wallet.fuel)
	current=account.begin_sortie(seed,false,{"kind":"salvage","id":"calm"})
	if not check(current.get("ok",false),"production begin sortie "+str(current.get("message",""))):return false
	check(int(account.state.wallet.fuel)==stock-int(current.fuel_v1.initial),"actual initial fuel debit")
	check(Ware.new(account).hold().items.is_empty(),"carried items locked out of port hold while deployed")
	var v:Dictionary=issue({"op":"new_salvage","seed":seed,"start":account.native_start(current)})
	return check(v.has("fuel"),"production native start has versioned real fuel")
func settle(label:String)->Dictionary:
	var v:Dictionary=core.view
	var receipt:Dictionary={"run_id":str(current.run_id),"success":bool(v.salvage.extracted),"loot":v.salvage.loot,"ships":v.salvage.ships,"cargo_items":v.salvage.cargo_grid.items.filter(func(item):return item.get("placement")!=null),"fuel_receipt":v.fuel_receipt}
	var before:int=int(account.state.wallet.fuel)
	var result:Dictionary=account.settle_sortie(receipt)
	check(result.get("ok",false),"production settlement "+label+" "+str(result.get("message","")))
	var expected:int=int(v.fuel_receipt.remaining) if bool(v.salvage.extracted) else 0
	check(int(account.state.wallet.fuel)==before+expected,"fuel refund only from successful real remaining "+label)
	var after:Dictionary=account.state.duplicate(true)
	check(account.settle_sortie(receipt).get("duplicate",false),"repeat receipt idempotent "+label)
	check(JSON.stringify(account.state)==JSON.stringify(after),"repeat receipt changes nothing "+label)
	runs.append({"label":label,"tick":int(v.tick),"success":bool(v.salvage.extracted),"fuel":v.fuel_receipt,"returnedOil":expected,"carried":int(current.cargo_transfer_v1.items.size()),"returnedItems":receipt.cargo_items.size()})
	return result
func run()->void:
	var path:String="user://tests/fleet-roundtrip-%d.json"%OS.get_process_id()
	account=Economy.new(path);check(account.new_profile().get("ok",false),"isolated production profile")
	account.state.wallet.credits=100000;account.state.wallet.ammo_stock=10000;account.state.wallet.fuel=10000
	var fm=load("res://scripts/fleet_manager.gd").new(account)
	check(fm.set_members(["IBS-U-USN-FLETCHER"]).get("ok",false),"actual saved single ship fleet")
	core=Bridge.new()
	if not start(40):return finish(path)
	var p:Dictionary=core.view.ships[0]
	issue({"op":"route","fleet":1,"mode":"follow","speed":6,"points":[{"x":float(p.x)+400,"y":float(p.y)}]});issue({"op":"step","seconds":8});issue({"op":"search_salvage","ruin":1});issue({"op":"step","seconds":8})
	var item:Dictionary=core.view.salvage.cargo_grid.items[0].duplicate(true)
	issue({"op":"cargo_place","item":str(item.id),"x":0,"y":0,"rotation":0})
	var opaque:Dictionary=core.request({"op":"save","serialized":true});check(account.save_sortie(str(opaque.serialized)).get("ok",false),"real account stores opaque exact core snapshot")
	var before_view:String=JSON.stringify(core.view);var charged:int=int(account.state.wallet.fuel)
	core.close();account=Economy.new(path);check(account.load_state().get("ok",false),"reload account midway with charged fuel and locked cargo")
	var resumed:Dictionary=account.resume_sortie();core=Bridge.new();issue({"op":"load","serialized":str(resumed.snapshot)})
	check(JSON.stringify(core.view)==before_view,"snapshot restores exact real cargo and oil")
	check(int(account.state.wallet.fuel)==charged,"resume does not debit oil twice")
	issue({"op":"salvage_extract","exit":0});issue({"op":"step","seconds":12});settle("first-search-and-return")
	var original_id:String=str(item.id);var warehouse=Ware.new(account)
	check(warehouse.hold().items.any(func(row):return str(row.id)==original_id),"first real loot returns to exact fleet hold")
	check(warehouse.transfer(original_id,"fleet").get("ok",false),"actual unload to base")
	check(warehouse.transfer(original_id,"base").get("ok",false),"actual load from base")
	if not start(41):return finish(path)
	check(core.view.salvage.cargo_grid.items.any(func(row):return str(row.id)==original_id and row.get("placement")!=null),"next voyage actually carries original id and grid placement")
	check(int(core.view.salvage.cargo_grid.kg)>0,"next voyage cargo has actual weight")
	issue({"op":"salvage_extract","exit":0});issue({"op":"step","seconds":12});var no_new:Dictionary=settle("same-owned-item-no-new-search")
	check(no_new.get("receipt",{}).get("rewards",{}).is_empty() and int(no_new.get("receipt",{}).get("xp",0))==0,"carried-only return grants no new XP or mission rewards")
	check(Ware.new(account).hold().items.filter(func(row):return str(row.id)==original_id).size()==1,"successful carried return exists exactly once")
	if not start(42,1):return finish(path)
	issue({"op":"extraction_autopilot","enabled":true,"policy":"balanced"});issue({"op":"step","seconds":1})
	check(str(core.view.salvage.expedition.autopilot.reason).contains("油料"),"low real fuel makes public-only autopilot return")
	issue({"op":"step","seconds":30});check(bool(core.view.result.primary),"low oil actual automated exit succeeds");settle("low-oil-ai-return")
	if not start(43,1):return finish(path)
	issue({"op":"route","fleet":1,"mode":"follow","speed":30,"points":[{"x":12000,"y":2200}]});issue({"op":"step","seconds":200})
	check(core.view.result!=null and not bool(core.view.result.primary),"empty oil actual rescue loses voyage")
	check(str(core.view.fuel.state)=="empty" and int(core.view.fuel_receipt.remaining)==0,"real fuel exhausted, no invented refill")
	settle("oil-exhaustion-rescue")
	check(not Ware.new(account).hold().items.any(func(row):return str(row.id)==original_id),"failed carried item lost from fleet")
	check(not load("res://scripts/cargo_service.gd").new(account).stash().items.any(func(row):return str(row.id)==original_id),"failed carried item not duplicated into base")
	if not start(44,100):return finish(path)
	issue({"op":"salvage_abandon"});check(int(core.view.fuel_receipt.remaining)>0,"abandon retains real unused oil in terminal evidence")
	settle("abandon-loses-unused-sea-oil")
	finish(path)
func finish(path:String)->void:
	if core!=null:core.close()
	var output:String=OS.get_environment("CAS_AUDIT_OUTPUT") if OS.has_environment("CAS_AUDIT_OUTPUT") else "res://../artifacts/tide-account-audit/roundtrip.json"
	var native:String=OS.get_environment("CAS_SIM_PATH")
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"passed":checks-failures.size(),"failures":failures,"runs":runs,"native":native,"nativeSha256":FileAccess.get_sha256(native) if FileAccess.file_exists(native) else ""},"  "));file.close()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	print("FLEET_PRODUCTION_ROUNDTRIP "+JSON.stringify({"checks":checks,"failures":failures,"runs":runs}));quit(0 if failures.is_empty() else 1)
