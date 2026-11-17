extends SceneTree
const Economy=preload("res://scripts/economy.gd")
const Service=preload("res://scripts/home_service.gd")
const Bridge=preload("res://scripts/core_bridge.gd")
const OUTPUT:String="res://../artifacts/home-v3-20261114/"
var account
var service
var core
var checks:int=0
var failures:Array[String]=[]
var main_sha:String
var backup_sha:String
var path:String
var win_sources:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,message:String)->bool:
	checks+=1
	if not ok:failures.append(message);push_error(message)
	return ok
func ask(value:Dictionary)->Dictionary:
	var result:Dictionary=core.request(value);check(result.get("ok",false),"core "+str(value.op)+" "+str(result.get("error","")));return result
func save()->String:return str(ask({"op":"save","serialized":true}).get("serialized",""))
func conserved(before:Dictionary,disk:String,message:String)->void:
	check(service._same(before,account.state),message+" preserves complete memory ledger")
	check(FileAccess.get_sha256(path)==disk,message+" preserves disk bytes")
func reject(result:Dictionary,before:Dictionary,disk:String,message:String)->void:
	check(not result.get("ok",false),message+" rejected");conserved(before,disk,message)
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	main_sha=FileAccess.get_sha256("user://cas_port_v1.json");backup_sha=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	path="C:/Users/fwj/AppData/Local/Temp/CAS-home-v3-account-%d.json"%OS.get_process_id();account=Economy.new(path)
	check(account.load_state().get("ok",false),"ordinary isolated account factory");account.load_state();account.state.erase("test_account");service=Service.new(account);core=Bridge.new()
	check(Service.BATTLE_VERSION=="cas-littoral-v3" and service.profiles.size()==20,"default v3 and all real twenty profiles")
	check(service.state().tactical_garrison.is_empty() and not service.state().unlocked,"ordinary migration grants no tactical garrison or island")
	var before:Dictionary=account.state.duplicate(true);var disk:String=FileAccess.get_sha256(path)
	var training:Dictionary=service.prepare_littoral("tutorial",42)
	check(training.get("ok",false) and training.request.roster==["MCP-034","MCP-001"] and training.request.lesson=="landing","default lesson borrows true two-company landing roster")
	check(training.loan_ships==Service.TRAINING_SHIPS and int(training.loaded_ammo)==0,"loan fleet with no owned ammunition charge")
	conserved(before,disk,"training preview/cancel")
	if not training.get("ok",false):return finish()
	if not ask(training.request).get("ok",false):return finish()
	check(service.begin(training.request,save()).get("ok",false),"v3 exact native configuration begins")
	check(account.state.active_run.home_frozen.loan_units==training.request.roster,"loan identity set frozen")
	check(service._same(account.state.owned,before.owned) and service._same(account.state.wallet,before.wallet),"begin loans preserve owned fleet and wallet")
	ask({"op":"littoral_abandon"});var terminal:String=save();var result:Dictionary=service.settle(core.view,terminal,true)
	check(result.get("ok",false),"real native abandoned tutorial settles")
	check(service._same(account.state.owned,before.owned) and service._same(account.state.wallet,before.wallet),"loan damage and ammo never modify or mint owned assets")
	check(service.state().units.is_empty() and not service.state().unlocked,"abandoned training grants no identities or island")
	before=account.state.duplicate(true);disk=FileAccess.get_sha256(path)
	check(service.settle(core.view,terminal,true).get("duplicate",false),"duplicate loan settlement deduplicated");conserved(before,disk,"duplicate settlement")
	# Ordinary progressed fixture: only the isolated account gains known owned identities.
	service.state().unlocked=true;service.state().tutorial_complete=true
	for id in ["MCP-034","MCP-001","MCP-022","MCP-009","MCP-076","MCP-011"]:service._own_unit(id)
	for id in Service.TRAINING_SHIPS:account.state.owned[id]=account._new_owned(id);account.state.owned[id].hp=43;account.state.owned[id].ammo=12
	account._commit(before,"isolated progressed ordinary fixture")
	before=account.state.duplicate(true);disk=FileAccess.get_sha256(path)
	reject(service.set_tactical_garrison(["MCP-034"]),before,disk,"one-company garrison")
	reject(service.set_tactical_garrison(["MCP-034","MCP-034"]),before,disk,"duplicate garrison")
	reject(service.set_tactical_garrison(["MCP-034","MCP-240"]),before,disk,"unowned garrison")
	reject(service.set_tactical_garrison(["MCP-034","MCP-001","MCP-022","MCP-009","MCP-076","MCP-011"]),before,disk,"six-company v3 garrison")
	service.state().units["MCP-001"].condition=0;service.state().units["MCP-001"].at=int(Time.get_unix_time_from_system());account._commit(before,"isolated condition edge")
	before=account.state.duplicate(true);disk=FileAccess.get_sha256(path)
	reject(service.set_tactical_garrison(["MCP-034","MCP-001"]),before,disk,"unready garrison")
	service.state().units["MCP-001"].condition=75;account._commit(before,"restore fixture readiness")
	check(service.set_garrison(["IBS-U-USN-FLETCHER"]).get("ok",false),"existing ship garrison retained")
	check(service.set_tactical_garrison(["MCP-034","MCP-001"]).get("ok",false),"independent tactical garrison saved")
	check(service.state().garrison==["IBS-U-USN-FLETCHER"],"tactical selection never overwrites ships")
	var prepared:Dictionary=service.prepare_littoral("defense",16,[],["IBS-U-USN-FLETCHER"])
	check(prepared.get("ok",false) and prepared.request.roster==service.state().tactical_garrison,"defense uses exactly saved tactical identities")
	if not prepared.get("ok",false):return finish()
	if not ask(prepared.request).get("ok",false):return finish()
	check(core.view.littoral.groups.size()==2,"real defense creates selected two companies")
	for group in core.view.littoral.groups:check(str(group.get("id","")) in prepared.request.roster and str(group.stage)=="ground","real selected company begins on shore")
	check(service.begin(prepared.request,save()).get("ok",false),"native defense freeze binds")
	check(account.state.active_run.request.roster==["MCP-034","MCP-001"],"frozen defense identity roster")
	before=account.state.duplicate(true);disk=FileAccess.get_sha256(path)
	reject(service.set_tactical_garrison(["MCP-022","MCP-009"]),before,disk,"mid-voyage garrison swap")
	ask({"op":"littoral_abandon"});check(service.settle(core.view,save(),true).get("ok",false),"defense real terminal settlement")
	# Existing same-ID owned bodies must also remain untouched by replayed borrowed training.
	before=account.state.duplicate(true);training=service.prepare_littoral("tutorial",42,[],[],"balanced",Service.BATTLE_VERSION,"combined")
	check(training.get("ok",false) and training.request.roster.size()==3,"combined uses its three true loan companies")
	if training.get("ok",false) and ask(training.request).get("ok",false):
		check(service.begin(training.request,save()).get("ok",false),"retraining loan freezes with same-ID owned assets")
		ask({"op":"littoral_abandon"});check(service.settle(core.view,save(),true).get("ok",false),"retraining native settle")
		check(service._same(before.owned,account.state.owned) and service._same(before.home_v1.units,service.state().units) and service._same(before.wallet,account.state.wallet),"same-ID owned condition hp ammo wallet preserved through loan battle")
	var cap:Dictionary=service.transport_summary(["MCP-034","MCP-001"],["IBS-U-IJN-NISSHIN"],"balanced")
	check(int(cap.used)==8 and int(cap.available)==17,"capacity reads native profile default slots and ship catalogue")
	for version in [Service.LEGACY_BATTLE_VERSION,Service.PREVIOUS_BATTLE_VERSION]:
		var old:Dictionary=service.prepare_littoral("raid",16,["MCP-022"],[Service.TRAINING_SHIPS[0]],"balanced",version)
		check(old.get("ok",false) and not old.request.has("company_transports") and not old.request.has("lesson"),"explicit "+version+" retains single-unit old request schema")
	review_wins()
	finish()
func review_wins()->void:
	# Reuse saved terminal states from the team's actual visible-hand player runs;
	# each is loaded/replayed by the installed native core, never a forged result.
	for lesson in ["sea_control","landing","combined"]:
		var source:String="res://../artifacts/littoral-training-v3/"+lesson+"/receipt.json"
		if not check(FileAccess.file_exists(source),lesson+" real player receipt exists"):continue
		var player:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source))
		if not check(bool(player.get("passed",false)),lesson+" actual visible-hand run passed"):continue
		var played:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(str(player.profile)));var record:Dictionary=played.get("settled",{}).get(str(played.get("last_receipt_id","")),{})
		var terminal:String=str(record.get("snapshot",""));var request:Dictionary=record.get("request",{})
		if not check(not terminal.is_empty() and str(request.get("lesson",""))==lesson and bool(record.get("success",false)),lesson+" terminal is real same-lesson victory"):continue
		win_sources.append({"lesson":lesson,"receipt":source,"receipt_sha256":FileAccess.get_sha256(source),"profile":str(player.profile),"profile_sha256":FileAccess.get_sha256(str(player.profile)),"terminal_tick":player.get("terminal_tick",0)})
		path="C:/Users/fwj/AppData/Local/Temp/CAS-home-v3-win-"+lesson+"-%d.json"%OS.get_process_id();account=Economy.new(path);account.load_state();account.load_state();account.state.erase("test_account");service=Service.new(account);account._commit(account.state.duplicate(true),"ordinary real training reward conservation")
		var owned_before:Dictionary=account.state.owned.duplicate(true);var wallet_before:Dictionary=account.state.wallet.duplicate(true)
		if not ask(request).get("ok",false):continue
		if not check(service.begin(request,save()).get("ok",false),lesson+" first real training begin"):continue
		ask({"op":"load","serialized":terminal});var result:Dictionary=service.settle(core.view,terminal)
		check(result.get("ok",false) and result.receipt.success,lesson+" actual victory settles")
		check(bool(service.state().unlocked) and service.state().units.has("MCP-034") and int(service.state().tickets)==10,lesson+" first ordinary victory unlocks island and once-only gifts")
		check(service._same(owned_before,account.state.owned) and service._same(wallet_before,account.state.wallet),lesson+" borrowed battle preserves real wallet and fleet")
		var reward_before:Dictionary=service.state().resources.duplicate(true);var units_before:Dictionary=service.state().units.duplicate(true)
		if not ask(request).get("ok",false):continue
		if not check(service.begin(request,save()).get("ok",false),lesson+" real repeat begins without permanent loan gift"):continue
		ask({"op":"load","serialized":terminal});result=service.settle(core.view,terminal)
		check(result.get("ok",false) and result.receipt.success,lesson+" real repeat victory settles")
		check(service._same(reward_before,service.state().resources) and int(service.state().tickets)==10 and result.receipt.rewards.is_empty(),lesson+" repeat victory cannot farm resource or tickets")
		check(service._same(units_before,service.state().units) and service._same(owned_before,account.state.owned) and service._same(wallet_before,account.state.wallet),lesson+" repeat borrowed identities cannot damage or mint owned assets")
		var before:Dictionary=account.state.duplicate(true);var disk:String=FileAccess.get_sha256(path);check(service.settle(core.view,terminal).get("duplicate",false),lesson+" repeat settlement idempotent");conserved(before,disk,lesson+" repeated winning settlement")
func finish()->void:
	check(FileAccess.get_sha256("user://cas_port_v1.json")==main_sha and FileAccess.get_sha256("user://cas_port_v1.json.bak")==backup_sha,"main account and backup untouched")
	var report:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"isolated_path":path,"runtime":OS.get_environment("CAS_SIM_PATH"),"main_account_written":false,"source_sha":FileAccess.get_sha256("res://scripts/home_service.gd"),"real_winning_player_sources":win_sources}
	FileAccess.open(OUTPUT+"account-receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify(report))
	if core!=null:core.close()
	quit(0 if failures.is_empty() else 1)
