extends SceneTree
## Production routing, microticks, durable pause/resume and actual terminal settlement.
const Economy=preload("res://scripts/economy.gd")
const Source:String="user://cas_port_v1.json"
const Output:String="res://../artifacts/home-littoral-20261113/main-review/"
var checks:int=0
var failures:Array[String]=[]
var app
var main_sha:String=""
var backup_sha:String=""
var isolated:String=""
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func ready_page()->void:
	await process_frame;await process_frame;await process_frame
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Output))
	main_sha=FileAccess.get_sha256(Source);backup_sha=FileAccess.get_sha256(Source+".bak")
	isolated=Output+"cloned-account-%d.json"%OS.get_process_id()
	# A fresh normal starter profile tests unlock/abandon without touching or
	# trying to settle the user's current voyage through an unrelated service.
	check(not FileAccess.file_exists(isolated),"fresh isolated normal starter profile")
	var account=Economy.new(isolated);check(account.load_state().get("ok",false),"load isolated profile")
	check(account.state.active_run.is_empty(),"completed baseline has no unrelated voyage")
	var before:Dictionary=account.state.duplicate(true);account.state.erase("test_account")
	check(account._commit(before,"Isolated integration conservation profile").get("ok",false),"ordinary resource conservation clone")
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false
	root.add_child(app);app.set_process(false);await ready_page()
	app.page_motion=false;app.set_meta("reduced_motion",true)
	check(app.home!=null and app.page.get_node_or_null("HomeIslandEntry")!=null,"harbor exposes real home service and entry")
	app.show_page("home");await ready_page()
	check(app.page.has_node("HomeIsland"),"home route opens native editable scene")
	app.show_page("home_recruit");await ready_page()
	check(app.page.has_node("TacticalRecruit"),"tactical recruit route opens native scene")
	app.go_back();await ready_page();check(app.screen=="home","back returns one level")
	var prepared:Dictionary=app.home.prepare_littoral("tutorial",42,["MCP-034"],["IBS-U-USN-FLETCHER"],"balanced")
	check(prepared.get("ok",false),"production tutorial preparation succeeds")
	if not prepared.get("ok",false):return finish()
	app.launch_littoral(prepared.request);await ready_page()
	check(app.screen=="battle" and str(app.run.mode)=="littoral","production launch enters littoral battle")
	check(app.page.has_node("LittoralBattle") and app.sea.has_method("focus_fleet"),"linked sea and editable land scene instantiated")
	check(app._fluid_battle() and app.speed==1,"new mode uses fixed 10Hz without changing historical rate")
	check(app.core.view.get("littoral",{}).get("version","")=="cas-littoral-v2","new native explicit version selected")
	var mission:Dictionary=app.economy.state.active_run.duplicate(true)
	app.running=true;app._process(.55)
	check(is_equal_approx(float(app.core.view.tick),.4),"one render frame caps catch-up at four real microticks")
	for i in range(48):app._process(.1)
	check(float(app.core.view.tick)>=5,"production fixed-clock advances real simulation")
	var durable:Variant=JSON.parse_string(str(app.economy.state.active_run.snapshot))
	check(durable is Dictionary and float(durable.get("tick",0))>=5,"five-second production checkpoint is durable")
	var saved:Dictionary=app.core.request({"op":"save","serialized":true})
	var tick:float=float(app.core.view.tick)
	app.save_leave();await ready_page()
	check(app.screen=="home" and str(app.economy.state.active_run.run_id)==str(mission.run_id),"pause returns home preserving one voyage")
	app.core.close();app.queue_free();await ready_page()
	app=load("res://scenes/main.tscn").instantiate();app.economy=Economy.new(isolated);app.boot_to_title=false
	root.add_child(app);app.set_process(false);await ready_page();app.page_motion=false;app.set_meta("reduced_motion",true)
	app.resume_run();await ready_page()
	check(app.screen=="battle" and is_equal_approx(float(app.core.view.tick),tick),"full process close and production resume preserve fractional clock")
	var reloaded:Dictionary=app.core.request({"op":"save","serialized":true})
	check(str(saved.get("serialized",""))==str(reloaded.get("serialized","")),"close and resume preserve exact native bytes")
	check(app.battle_return_route=="home","resumed voyage retains home return destination")
	app.abandon();await ready_page()
	check(app.screen=="result" and app.economy.state.active_run.is_empty(),"real native abandon settles through home ledger")
	check(app.page.has_node("LittoralResult") and not bool(app.last_receipt.get("borrowed",true)),"accurate independent result never claims free naval damage")
	check(not bool(app.home.state().tutorial_complete),"abandon cannot grant island or protocol")
	var reward:Dictionary=app.last_receipt.get("rewards",{})
	check(reward.values().all(func(v):return int(v)==0),"abandon gives no fabricated resource reward")
	app.core.close();app.queue_free();await ready_page()
	finish()
func finish()->void:
	if is_instance_valid(app):app.core.close();app.queue_free()
	check(FileAccess.get_sha256(Source)==main_sha,"normal account byte hash preserved")
	check(FileAccess.get_sha256(Source+".bak")==backup_sha,"normal backup byte hash preserved")
	var report:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"source":ProjectSettings.globalize_path(Source),"source_sha256":main_sha,"backup_sha256":backup_sha,"account":ProjectSettings.globalize_path(isolated),"native_override":OS.get_environment("CAS_SIM_PATH")}
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://bin/core-current.json"))
	report["default_manifest"]=manifest
	report["runtime_sha256"]=FileAccess.get_sha256("res://bin/"+str(manifest.get("executable","")))
	FileAccess.open(Output+"report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("HOME_MAIN "+JSON.stringify(report));quit(0 if failures.is_empty() else 1)
