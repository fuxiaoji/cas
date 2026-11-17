extends SceneTree
## Real default launcher, autonomous field decisions, account settlement and reload.
const Settle=preload("res://tests/transition_settle.gd")
const Economy=preload("res://scripts/economy.gd")
var app
var checks:=0
var failures:Array[String]=[]
var shots:Array[String]=[]
var output:="res://../artifacts/godot/extraction-autonomy-ui/"
func _initialize()->void:call_deferred("run")
func check(ok:bool,title:String)->void:
	checks+=1
	if not ok:failures.append(title);push_error(title)
func frame()->void:
	await process_frame;await process_frame
func shot(name:String)->void:
	await frame();await RenderingServer.frame_post_draw
	var path:=ProjectSettings.globalize_path(output+name+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"actual GPU capture "+name);shots.append(path)
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720)
	var path:="user://tests/extraction-autonomy-%d.json"%OS.get_process_id()
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.economy=Economy.new(path)
	root.add_child(app);app.set_process(false);await frame();app.page_motion=false
	app.set_meta("next_sortie_seed",40);app.show_page("expedition");await Settle.wait_for_route(self,app)
	var stamina:int=int(app.economy.wallet().stamina)
	app.launch(false,{"kind":"salvage","id":"calm"});await Settle.wait_for_route(self,app)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);app.fullscreen_battle=false;root.size=Vector2i(1280,720)
	check(app.screen=="battle" and app.running and app.speed==1,"production expedition enters running at actual 1x simulation")
	var pilot:Dictionary=app.core.view.salvage.expedition.autopilot
	check(pilot.get("enabled",false) and str(pilot.get("version",""))=="cas-extraction-pilot-v3","latest pilot is authorized by default without field commands")
	check(int(app.economy.wallet().stamina)==stamina-8,"one real entry spends exactly one voyage cost")
	await shot("default-autonomous-departure")
	var run_id:String=str(app.economy.state.active_run.run_id)
	var raw:String=str(app.core.request({"op":"save","serialized":true}).serialized)
	app.go_home();await Settle.wait_for_route(self,app);app.close_modal()
	check(app.screen=="harbor" and str(app.economy.state.active_run.snapshot)==raw,"direct home pauses and saves exact ongoing autonomous voyage")
	app.resume_run();await Settle.wait_for_route(self,app)
	check(app.running and str(app.core.request({"op":"save","serialized":true}).serialized)==raw,"resume continues saved authorization without new commands or double entry cost")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);app.fullscreen_battle=false
	var phases:Array[String]=[]
	var accepted:bool=false
	var tick:int=0
	for second in range(600):
		if app.screen!="battle":break
		app._process(1.0)
		var voyage:Dictionary=app.core.view.get("salvage",{}).get("expedition",{})
		var phase:String=str(voyage.get("autopilot",{}).get("phase",""))
		if not phases.has(phase):phases.append(phase)
		for task in voyage.get("tasks",[]):
			if str(task.get("status",""))!="offered":accepted=true
		tick=int(app.core.view.tick)
		if second==15:await shot("automatic-search-and-routing")
		if second%12==0:await frame()
	check(app.screen=="result" and app.last_receipt.get("success",false),"pilot reaches true extraction and production account settlement without field input")
	check(accepted,"pilot independently accepts a feasible optional task")
	check(phases.has("search") or phases.has("collect") or phases.has("travel"),"pilot actually searches or travels rather than granting synthetic loot")
	check(phases.has("extract"),"pilot independently chooses the extraction phase")
	check(app.last_receipt.get("cargo_items",[]).size()>0,"actual recovered physical items appear on the result")
	check(app.economy.state.active_run.is_empty() and app.economy.state.settled.has(run_id),"one completed voyage clears active state and journals a receipt")
	await shot("autonomous-extraction-result")
	var account:=Economy.new(path)
	check(account.load_state().get("ok",false),"actual journal reload succeeds")
	check(account.state.active_run.is_empty() and account.state.settled.has(run_id) and int(account.state.extractions)==1,"true rewards and completion survive full account reload")
	check(int(account.wallet().stamina)==stamina-8,"save and resume never charge a second entry")
	var receipt:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"tick":tick,"phases":phases,"accepted_optional_task":accepted,"recovered":app.last_receipt.get("cargo_items",[]).size(),"screenshots":shots,"commands":"production launch, save/home, resume and process ticks only; no field navigation, task, search, cargo or withdrawal commands supplied by test"}
	FileAccess.open(output+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(receipt,"  "))
	app.core.close();print("EXTRACTION_AUTONOMY_UI ",JSON.stringify(receipt));quit(0 if failures.is_empty() else 1)
