extends SceneTree
## Actual Main clock, durable route navigation and native resume on ordinary loans.
const Economy=preload("res://scripts/economy.gd")
const Output:String="res://../artifacts/littoral-v3-main/"
var app
var checks:int=0
var failures:Array[String]=[]
var source_sha:String
var backup_sha:String
var isolated:String
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func frames()->void:
	await process_frame;await process_frame;await process_frame
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Output))
	source_sha=FileAccess.get_sha256("user://cas_port_v1.json");backup_sha=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	isolated=Output+"ordinary-%d.json"%OS.get_process_id()
	var account=Economy.new(isolated);check(account.load_state().get("ok",false),"fresh isolated ordinary profile")
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;root.add_child(app);app.set_process(false);await frames()
	app.page_motion=false;app.set_meta("reduced_motion",true)
	var prepared:Dictionary=app.home.prepare_littoral("tutorial",42,[],[],"balanced","cas-littoral-v3","combined")
	check(prepared.get("ok",false),"ordinary combined lesson loan plan")
	if not prepared.get("ok",false):return finish()
	app.launch_littoral(prepared.request);await frames()
	check(app.screen=="battle" and app._fluid_battle(),"Main launches v3 fixed microclock")
	check(app.core.view.littoral.version=="cas-littoral-v3","native version is explicit v3")
	var roster:Array=app.core.view.littoral.groups
	check(roster.size()==3,"combined training has three actual companies")
	app.running=true;app.speed=1;app._process(.55)
	check(is_equal_approx(float(app.core.view.tick),.5),"1x .55-second frame consumes five exact .1 steps")
	check(app.elapsed>=.04 and app.elapsed<=.06,"unconsumed fractional clock debt remains")
	app.speed=8
	for i in range(10):app._process(.1)
	check(is_equal_approx(float(app.core.view.tick),8.5),"8x real Main clock advances eight simulation seconds per render-second input")
	var paused_tick:float=float(app.core.view.tick);app.running=false
	app._process(1.0);check(float(app.core.view.tick)==paused_tick,"paused Main does not advance combat")
	check(app.checkpoint(),"current native and teaching UI state checkpoint succeeds")
	var serialized:String=app.core.request({"op":"save","serialized":true}).serialized
	var run_id:String=app.economy.state.active_run.run_id
	app.go_home();await frames()
	check(app.screen=="harbor" and not app.economy.state.active_run.is_empty(),"direct harbor preserves ongoing exact voyage")
	check(app.economy.state.active_run.run_id==run_id,"harbor navigation never creates another voyage")
	app.core.close();app.queue_free();await frames()
	app=load("res://scenes/main.tscn").instantiate();app.economy=Economy.new(isolated);app.boot_to_title=false;root.add_child(app);app.set_process(false);await frames();app.page_motion=false
	app.resume_run();await frames()
	check(app.screen=="battle" and float(app.core.view.tick)==paused_tick,"full close and Main resume retain fractional native time")
	check(app.core.request({"op":"save","serialized":true}).serialized==serialized,"full resume native bytes identical")
	check(app.run.request.lesson=="combined","lesson identity remains frozen after reload")
	check(app.battle_controller.tutorial.lesson=="combined","resumed guidance revalidates actual native lesson")
	check(app.issue({"op":"littoral_deploy","unit_id":"MCP-034","beach":2,"insertion":"landing","queue":true}).get("ok",false),"first company can queue actual landing before checkpoint")
	for index in 450:
		if str(app.core.view.littoral.groups[0].stage)=="ground":break
		app.core.request({"op":"step","seconds":.1});app.update_battle()
	check(str(app.core.view.littoral.groups[0].stage)=="ground","first company really ashore before resume scenario")
	app.battle_controller.set_primary_map("land");await frames()
	check(app.checkpoint(),"save after first landing while land is main map")
	var landed_tick:float=float(app.core.view.tick)
	app.core.close();app.queue_free();await frames()
	app=load("res://scenes/main.tscn").instantiate();app.economy=Economy.new(isolated);app.boot_to_title=false;root.add_child(app);app.set_process(false);await frames();app.page_motion=false
	app.resume_run();await frames()
	check(float(app.core.view.tick)==landed_tick and app.battle_controller.primary_map=="land","actual first landing and map focus survive full reload")
	check(app.battle_controller.tutorial.current_step()=="focus_sea_second","resumed combined guidance first returns to sea before deploying second company")
	app.battle_controller.set_primary_map("sea");await frames()
	check(app.battle_controller.tutorial.current_step()=="deploy_second" and app.battle_controller.tutorial.unit_id=="MCP-001","actual map change directs the correct second company after resume")
	app.abandon();await frames()
	check(app.screen=="result" and app.economy.state.active_run.is_empty(),"abandon uses actual terminal settlement")
	check(not app.home.state().tutorial_complete and app.home.state().units.is_empty(),"abandon never unlocks island or grants temporary units")
	check(app.last_receipt.home_tutorial_loan and app.last_receipt.ammo_loaded==0 and app.last_receipt.ammo_returned==0,"borrowed training settles without stock ammunition side effects")
	finish()
func finish()->void:
	if is_instance_valid(app):app.core.close();app.queue_free()
	check(source_sha==FileAccess.get_sha256("user://cas_port_v1.json"),"user main account unchanged")
	check(backup_sha==FileAccess.get_sha256("user://cas_port_v1.json.bak"),"user backup unchanged")
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"profile":ProjectSettings.globalize_path(isolated),"source_sha256":source_sha,"backup_sha256":backup_sha,"runtime":JSON.parse_string(FileAccess.get_file_as_string("res://bin/core-current.json")),"override":OS.get_environment("CAS_SIM_PATH")}
	FileAccess.open(Output+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print("V3_MAIN "+JSON.stringify(report));quit(0 if failures.is_empty() else 1)
