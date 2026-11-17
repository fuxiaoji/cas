extends SceneTree
## Isolated QA ownership fixture; all voyage commands and settlement are real.
const Economy=preload("res://scripts/economy.gd")
const Home=preload("res://scripts/home_service.gd")
const Bridge=preload("res://scripts/core_bridge.gd")
var checks:int=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures.append(label);push_error(label)
	return ok
func group(view:Dictionary,id:String)->Dictionary:
	for row in view.get("littoral",{}).get("groups",[]):
		if str(row.get("company_id",""))==id:return row
	return {}
func _initialize()->void:call_deferred("run")
func run()->void:
	var ordinary:Dictionary={}
	for name in ["cas_port_v1.json","cas_port_v1.json.bak"]:ordinary[name]=FileAccess.get_sha256("user://"+name)
	var path:String="res://../artifacts/combined-arms-v4/multi-account-%d.json"%OS.get_process_id()
	var account=Economy.new(path);check(account.load_state().get("ok",false),"isolated fresh profile")
	var service=Home.new(account);var core=Bridge.new();var before:Dictionary=account.state.duplicate(true)
	account.state.wallet.origins=10000;account.state.wallet.ammo_stock=1000;service.state().unlocked=true
	service._own_unit("MCP-034");service._own_unit("MCP-001")
	account._commit(before,"QA owned-unit/island fixture, not claimed normal progression")
	check(service.procure_ship("CAS-O-LHA-RETURNLIGHT","multi-LHA").get("ok",false),"actual paid carrier procurement")
	check(service.set_tactical_garrison(["MCP-034","MCP-001"]).get("ok",false),"actual garrison selection")
	before=account.state.duplicate(true);var disk:String=FileAccess.get_sha256(path)
	var plan:Dictionary=service.prepare_littoral("defense",42,["MCP-034","MCP-001"],["CAS-O-LHA-RETURNLIGHT"])
	if not check(plan.get("ok",false),"real multi-company account preflight "+str(plan.get("message",""))):return finish(core,path,ordinary)
	check(plan.request.get("company_layout","")==Home.COMPANY_LAYOUT,"new ordinary sortie explicitly freezes multi layout")
	check(service._same(before,account.state) and FileAccess.get_sha256(path)==disk,"multi preflight does not debit or mutate ownership")
	if not check(core.request(plan.request).get("ok",false),"actual native multi-company departure"):return finish(core,path,ordinary)
	check(core.view.littoral.groups.size()==8,"five marine and three air assault companies")
	var friendly:Array=core.view.littoral.land.entities.filter(func(row):return row.get("side")=="allies")
	check(friendly.size()==69,"all 69 actual friendly bodies exist on garrison island")
	check(friendly.filter(func(row):return row.get("company_id")=="MCP-034-C01").size()==9,"marine first company has nine actual bodies")
	check(friendly.filter(func(row):return row.get("company_id")=="MCP-034-C02").size()==9,"marine second company has its own nine bodies")
	var snapshot:Dictionary=core.request({"op":"save","serialized":true})
	check(service.begin(plan.request,str(snapshot.serialized)).get("ok",false),"account binds exact actual multi-company snapshot")
	check(int(account.state.wallet.ammo_stock)==int(before.wallet.ammo_stock)-int(plan.loaded_ammo),"ship ammunition is charged once for all companies")
	var command:Dictionary={"op":"littoral_order","unit_id":"MCP-034","action":"move","x":12250,"y":12420}
	check(not core.request(command).get("ok",false),"ambiguous parent identity cannot command every company")
	check(str(core.request({"op":"save","serialized":true}).serialized)==str(snapshot.serialized),"rejected ambiguous command preserves actual state")
	command["company_id"]="MCP-001-C01"
	check(not core.request(command).get("ok",false),"spoofed company and parent identity rejected")
	var first:Dictionary=group(core.view,"MCP-034-C01");var other:Dictionary=group(core.view,"MCP-034-C02").duplicate(true)
	var accepted:bool=false
	for offset in [Vector2(80,0),Vector2(-80,0),Vector2(0,80),Vector2(0,-80),Vector2(140,140)]:
		command={"op":"littoral_order","company_id":"MCP-034-C01","unit_id":"MCP-034","action":"move","x":float(first.position.x)+offset.x,"y":float(first.position.y)+offset.y}
		if core.request(command).get("ok",false):accepted=true;break
	check(accepted,"actual first-company movement command accepted")
	check(service._same(group(core.view,"MCP-034-C02"),other),"sibling company retains its own order and position")
	check(core.request({"op":"step","seconds":1.0}).get("ok",false),"real combat and movement advance")
	check(group(core.view,"MCP-034-C01").position!=first.position,"first company actually moves")
	snapshot=core.request({"op":"save","serialized":true})
	var observed:Dictionary=core.view.duplicate(true);var restored=Bridge.new()
	check(restored.request({"op":"load","serialized":str(snapshot.serialized)}).get("ok",false),"fresh process restores actual multi-company voyage")
	check(service._same(restored.view,observed),"restored companies, bodies, terrain and real presentation match")
	restored.close()
	check(core.request({"op":"littoral_abandon"}).get("ok",false),"explicit actual voyage abandonment")
	var result:Dictionary=core.view.littoral.outcome
	check(result.get("companies",[]).size()==8 and result.get("units",[]).size()==2,"terminal has eight company records and only two parent identities")
	snapshot=core.request({"op":"save","serialized":true})
	var settled:Dictionary=service.settle(core.view,str(snapshot.serialized),true)
	check(settled.get("ok",false),"actual multi-company loss settles atomically")
	for row in result.get("units",[]):
		var expected:float=0 if row.get("missing",false) or row.get("incapacitated",false) else float(row.hp_percent)
		check(absf(float(service.state().units[str(row.id)].condition)-expected)<.00001,"weighted parent condition posted once "+str(row.id))
	check(service.state().units.keys().all(func(id):return not str(id).contains("-C")),"company identifiers never become duplicate owned personalities")
	check(int(account.state.wallet.origins)==int(before.wallet.origins),"company count grants no extra origins")
	before=account.state.duplicate(true);disk=FileAccess.get_sha256(path)
	check(service.settle(core.view,str(snapshot.serialized),true).get("duplicate",false),"repeated multi settlement deduplicates")
	check(service._same(before,account.state) and disk==FileAccess.get_sha256(path),"repeated settlement preserves account and disk")
	finish(core,path,ordinary)
func finish(core,path:String,ordinary:Dictionary)->void:
	core.close()
	for name in ordinary:check(FileAccess.get_sha256("user://"+str(name))==ordinary[name],"ordinary user save untouched "+str(name))
	var report:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"native_override":OS.get_environment("CAS_SIM_PATH"),"profile":path,"normal_save_sha256":ordinary,"scope":"QA ownership fixture, actual native independent companies and atomic loss settlement"}
	FileAccess.open("res://../artifacts/combined-arms-v4/multi-account-review.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("MULTI_COMPANY_ACCOUNT ",checks-failures.size(),"/",checks);quit(0 if failures.is_empty() else 1)
