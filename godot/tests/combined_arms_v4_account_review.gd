extends SceneTree
const Economy=preload("res://scripts/economy.gd")
const Home=preload("res://scripts/home_service.gd")
const Bridge=preload("res://scripts/core_bridge.gd")
var checks:int=0
var failures:Array[String]=[]
var original:Dictionary={}
var account
var service
var core
var path:String
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures.append(label);push_error(label)
	return ok
func unchanged(before:Dictionary,disk:String,label:String)->void:
	check(service._same(before,account.state),label+" preserves memory")
	check(FileAccess.get_sha256(path)==disk,label+" preserves disk")
func run()->void:
	for name in ["cas_port_v1.json","cas_port_v1.json.bak"]:original[name]=FileAccess.get_sha256("user://"+name)
	path="res://../artifacts/combined-arms-v4/account-%d.json"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../artifacts/combined-arms-v4"))
	account=Economy.new(path);check(account.load_state().get("ok",false),"fresh isolated account");service=Home.new(account);core=Bridge.new()
	check(Home.BATTLE_VERSION=="cas-littoral-v4","default action is v4")
	check(service.aviation_ships.size()==4,"four separately registered new ships")
	var old_pool:Array=[]
	for item in account.catalog:
		if item.get("recruitable",true):old_pool.append(str(item.id))
	var old_raw:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/ships.json"))
	var source:Array=old_raw.get("ships",[]) if old_raw is Dictionary else old_raw
	check(old_pool==source.map(func(row):return str(row.id)),"old recruit catalogue ordering unchanged")
	var before:Dictionary=account.state.duplicate(true);var disk:String=FileAccess.get_sha256(path)
	check(not service.procure_ship("nonexistent","bad").get("ok",false),"unknown procurement rejected");unchanged(before,disk,"unknown procurement")
	account.state.wallet.origins=0;account._commit(before,"isolated insufficient-wallet fixture")
	before=account.state.duplicate(true);disk=FileAccess.get_sha256(path)
	check(not service.procure_ship("CAS-O-LHA-RETURNLIGHT","poor").get("ok",false),"insufficient origins rejected");unchanged(before,disk,"insufficient origins")
	account.state.wallet.origins=10000;account._commit(before,"isolated procurement-funded fixture")
	var paid:int=0
	for card in service.aviation_ships:
		var id:String=str(card.id);before=account.state.duplicate(true)
		var response:Dictionary=service.procure_ship(id,"procure-"+id)
		if not check(response.get("ok",false),"purchase "+id):continue
		paid+=int(card.price_origins)
		check(account.state.owned.has(id) and int(account.state.wallet.origins)==10000-paid,"exact owned asset and debit "+id)
		before=account.state.duplicate(true);disk=FileAccess.get_sha256(path)
		check(service.procure_ship(id,"procure-"+id).get("duplicate",false),"replayed purchase deduplicated "+id);unchanged(before,disk,"duplicate purchase")
	check(service.naval_roster().filter(func(row):return str(row.id).begins_with("CAS-")).size()==4,"new ships selectable from actual owned roster")
	var cap:Dictionary=service.transport_summary(["MCP-034"],["IBS-U-USN-FLETCHER"],"balanced")
	check(cap.fits,"ordinary marines may embark destroyer")
	check(not service.transport_summary(["MCP-022"],["IBS-U-USN-ERMA-IOWA"],"balanced").fits,"armor cannot embark battleship")
	check(not service.transport_summary(["MCP-001"],["IBS-U-IJN-NISSHIN"],"balanced").fits,"AV cannot act as helicopter carrier")
	check(service.transport_summary(["MCP-022"],["CAS-O-APV-TIDEBRIDGE"],"balanced").fits,"armor can embark APV")
	check(not service.transport_summary(["MCP-001"],["CAS-O-APV-TIDEBRIDGE"],"balanced").fits,"APV cannot embark air assault")
	check(service.transport_summary(["MCP-022","MCP-001","MCP-034"],["CAS-O-LHA-RETURNLIGHT"],"balanced",[],Home.BATTLE_VERSION,"").fits,"unchanged single-company LHA supports original mixed landing team")
	check(not service.transport_summary(["MCP-022","MCP-001","MCP-034"],["CAS-O-LHA-RETURNLIGHT"],"balanced").fits,"larger multi-company detachment cannot overfill one LHA")
	check(service.transport_summary(["MCP-022","MCP-001","MCP-034"],["CAS-O-LHA-RETURNLIGHT","CAS-O-APV-TIDEBRIDGE"],"balanced").fits,"multi-company detachment fits suitable additional transport")
	check(int(cap.get("people",0))==45 and int(cap.get("companies",0))==5,"ordinary marine detachment has five real companies of nine")
	before=account.state.duplicate(true);disk=FileAccess.get_sha256(path)
	var training:Dictionary=service.prepare_littoral("tutorial",42)
	if check(training.get("ok",false),"v4 real core accepts default borrowed training"):
		check(training.loan_ships==Home.V4_TRAINING_SHIPS and int(training.loaded_ammo)==0,"v4 training borrows qualified LHA without owned charge")
		unchanged(before,disk,"real native preflight")
		var started:Dictionary=core.request(training.request)
		if check(started.get("ok",false),"native v4 new action"):
			var snapshot:Dictionary=core.request({"op":"save","serialized":true})
			check(service.begin(training.request,str(snapshot.get("serialized",""))).get("ok",false),"account binds actual v4 snapshot")
			check(service._same(before.owned,account.state.owned) and service._same(before.wallet,account.state.wallet),"borrowed action never consumes owned ships or ammo")
			var frozen:Dictionary=account.state.duplicate(true);disk=FileAccess.get_sha256(path)
			check(not service.procure_ship("CAS-O-LHA-RETURNLIGHT","during").get("ok",false),"active voyage blocks procurement");unchanged(frozen,disk,"active procurement")
			check(core.request({"op":"littoral_abandon"}).get("ok",false),"real core abandonment")
			snapshot=core.request({"op":"save","serialized":true})
			var settled:Dictionary=service.settle(core.view,str(snapshot.get("serialized","")),true)
			check(settled.get("ok",false),"actual v4 terminal settles")
			check(service._same(before.owned,account.state.owned) and service._same(before.wallet,account.state.wallet),"terminal loan loss never changes owned fleet")
			check(not service.state().unlocked and not service.state().tutorial_complete,"abandonment cannot unlock island")
			frozen=account.state.duplicate(true);disk=FileAccess.get_sha256(path)
			check(service.settle(core.view,str(snapshot.get("serialized","")),true).get("duplicate",false),"terminal replay deduplicated");unchanged(frozen,disk,"terminal replay")
	core.close()
	for name in original:check(FileAccess.get_sha256("user://"+str(name))==str(original[name]),"normal user "+str(name)+" untouched")
	var receipt:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"normal_save_sha256":original,"isolated_profile":path,"native_override":OS.get_environment("CAS_SIM_PATH"),"scope":"isolated real account/native preflight and terminal; no claimed player victory"}
	FileAccess.open("res://../artifacts/combined-arms-v4/account-review.json",FileAccess.WRITE).store_string(JSON.stringify(receipt,"\t"))
	print("COMBINED_ARMS_V4_ACCOUNT ",checks-failures.size(),"/",checks);quit(0 if failures.is_empty() else 1)
