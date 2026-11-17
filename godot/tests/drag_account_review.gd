extends SceneTree
## New v2 account boundary plus UI metadata durability, using only isolated profiles.
const Economy=preload("res://scripts/economy.gd")
const Service=preload("res://scripts/home_service.gd")
const Bridge=preload("res://scripts/core_bridge.gd")
const OUTPUT:String="res://../artifacts/drag-littoral-v2/account/"
var checks:int=0
var failures:Array[String]=[]
var core
var account
var service
var profile:String=""
var receipts:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures.append(label);push_error(label)
	return ok
func ask(command:Dictionary)->Dictionary:
	var response:Dictionary=core.request(command)
	check(response.get("ok",false),"native "+str(command.op)+" "+str(response.get("error","")))
	return response
func snapshot()->String:return str(ask({"op":"save","serialized":true}).get("serialized",""))
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var source:String="user://cas_port_v1.json";var main_sha:String=FileAccess.get_sha256(source);var backup_sha:String=FileAccess.get_sha256(source+".bak")
	var baseline:String="res://../artifacts/home-review/isolated-npc-64232.json";profile=OUTPUT+"isolated-v2-%d.json"%OS.get_process_id()
	if not check(DirAccess.copy_absolute(ProjectSettings.globalize_path(baseline),ProjectSettings.globalize_path(profile))==OK,"clone completed NPC profile with legitimately recruited transport"):quit(1);return
	account=Economy.new(profile);check(account.load_state().get("ok",false),"load isolated account")
	check(account.state.active_run.is_empty(),"no unrelated active voyage discarded");account.state.erase("test_account");service=Service.new(account)
	var before:Dictionary=account.state.duplicate(true)
	check(not service.unlock_test_units().get("ok",false) and service._same(before,account.state),"ordinary profile denies QA unlock without state change")
	account.state.test_account="cas-local-qa-2026-11-12";check(service.unlock_test_units().get("ok",false),"explicit isolated QA action grants twenty implemented units")
	account.state.erase("test_account");before=account.state.duplicate(true);check(account._commit(before,"Persist isolated ordinary verification profile").get("ok",false),"remove isolated QA marker")
	core=Bridge.new();var published:Dictionary=ask({"op":"littoral_catalogue","version":"cas-littoral-v2"}).get("data",{})
	var content:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/tactical-profiles-v2.json"))
	check(service._same(published.get("cards"),content.get("cards")),"all twenty numerical profiles exactly match native catalogue")
	check(service.released().size()==20 and service.released("cas-littoral-v1").size()==5,"new pool twenty, legacy pool five")
	var ships:Array=[]
	for identity in ["IBS-U-IJN-NISSHIN","IBS-U-IJN-CHITOSE"]:
		if account.state.owned.has(identity):ships.append(identity)
	if not check(not ships.is_empty(),"baseline genuinely owns at least one registered transport"):core.close();quit(1);return
	for row in service.released():
		var id:String=str(row.id);var plan:Dictionary=service.prepare_littoral("salvage",42,[id],ships,"transport")
		if not check(plan.get("ok",false),"owned profile can prepare "+id):continue
		var response:Dictionary=ask(plan.request)
		if not response.get("ok",false):continue
		var group:Dictionary=core.view.littoral.groups[0]
		check(str(group.id)==id and str(core.view.littoral.version)=="cas-littoral-v2","real new-world identity "+id)
		check(group.get("carrier")!=null,"real transport allocated to "+id)
		receipts.append({"id":id,"group":group.duplicate(true),"profile":service.profile(id)})
	before=account.state.duplicate(true);var disk:String=FileAccess.get_sha256(profile)
	var first_six:Array=Service.RELEASED.slice(0,6)
	check(service.prepare_littoral("defense",42,first_six,ships,"transport").get("ok",false),"v2 accepts six distinct ready squads")
	check(not service.prepare_littoral("defense",42,Service.RELEASED.slice(0,7),ships,"transport").get("ok",false),"seventh squad rejected")
	check(not service.prepare_littoral("defense",42,["MCP-034","MCP-034"],ships,"transport").get("ok",false),"duplicate personality rejected")
	check(not service.prepare_littoral("defense",42,["MCP-240"],ships,"transport","cas-littoral-v1").get("ok",false),"new identity never enters legacy rules")
	check(service._same(before,account.state) and FileAccess.get_sha256(profile)==disk,"twenty previews and rejected choices never charge resources")
	var plan:Dictionary=service.prepare_littoral("tutorial",42,["MCP-034"],["IBS-U-USN-FLETCHER"],"balanced")
	if check(plan.get("ok",false),"repeat handholding lesson prepares legitimate v2 loan"):
		ask(plan.request);var raw:String=snapshot();var wrong:Dictionary=plan.request.duplicate(true);wrong.version="cas-littoral-v1"
		check(not service.begin(wrong,raw).get("ok",false),"v2 snapshot cannot bind a legacy account request")
		check(service.begin(plan.request,raw).get("ok",false),"v2 request binds exact native new-world snapshot")
		var wallet:Dictionary=account.state.wallet.duplicate(true);var units:Dictionary=service.state().units.duplicate(true)
		var ui_state:Dictionary={"primary_map":"land","selected_unit":"MCP-034","drag_tutorial":{"version":1,"step_id":"move","proofs":{},"completed":false}}
		check(account.save_sortie(raw,ui_state).get("ok",false),"actual snapshot and UI help state commit together")
		var reloaded=Economy.new(profile);check(reloaded.load_state().get("ok",false),"reload complete v2 account")
		check(str(reloaded.state.active_run.snapshot)==raw and service._same(reloaded.state.active_run.ui_state,ui_state),"fractional native bytes and map/help state survive disk reload")
		before=account.state.duplicate(true);disk=FileAccess.get_sha256(profile)
		check(not account.save_sortie(raw,{"drag_tutorial":"invalid"}).get("ok",false),"malformed help cannot throw or replace durable snapshot")
		check(service._same(before,account.state) and FileAccess.get_sha256(profile)==disk,"malformed UI metadata preserves exact state and disk")
		var original_path:String=account.save_path;var blocker:String=OUTPUT+"blocked-%d"%OS.get_process_id();FileAccess.open(blocker,FileAccess.WRITE).store_string("regular file")
		account.save_path=blocker+"/profile.json"
		check(not account.save_sortie(raw,{"primary_map":"sea","drag_tutorial":{"completed":true}}).get("ok",false),"real write failure rejects snapshot and completed help preference")
		check(service._same(before,account.state) and FileAccess.get_sha256(profile)==disk,"failed commit rolls all UI and account fields back")
		account.save_path=original_path
		check(account.save_sortie(raw,{"primary_map":"land","drag_tutorial":{"completed":true}}).get("ok",false),"completed-help preference commits without reward")
		check(service._same(wallet,account.state.wallet) and service._same(units,service.state().units),"help completion never grants currency, repairs or units")
		ask({"op":"littoral_abandon"});var terminal:String=snapshot();var settled:Dictionary=service.settle(core.view,terminal,true)
		check(settled.get("ok",false) and str(settled.get("receipt",{}).get("ruleset",""))=="cas-littoral-v2","real v2 abandonment uses versioned receipt")
		check(service._same(units,service.state().units),"repeat tutorial loan never heals or harms owned tactical personality")
		before=account.state.duplicate(true);check(service.settle(core.view,terminal,true).get("duplicate",false) and service._same(before,account.state),"v2 terminal settles exactly once")
	var runtime:Dictionary=load("res://tests/home_runtime_evidence.gd").capture(core)
	if OS.has_environment("CAS_SIM_PATH"):
		check(str(runtime.actual_sha256)==FileAccess.get_sha256(OS.get_environment("CAS_SIM_PATH")),"candidate test uses exact supplied native SHA")
	else:check(runtime.get("verified_default",false),"default installed native path and SHA actually used")
	core.close();check(FileAccess.get_sha256(source)==main_sha and FileAccess.get_sha256(source+".bak")==backup_sha,"normal account and backup preserved byte for byte")
	var report:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"runtime":runtime,"profile":ProjectSettings.globalize_path(profile),"unit_evidence":receipts,"source_sha256":main_sha,"backup_sha256":backup_sha,"isolated_qa_grant":true}
	FileAccess.open(OUTPUT+"report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print("DRAG_ACCOUNT "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
