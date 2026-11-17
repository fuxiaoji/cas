extends SceneTree
const Economy=preload("res://scripts/economy.gd")
const OUTPUT:String="res://../artifacts/home-review/"
var app
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var source:String="user://cas_port_v1.json";var source_hash:String=FileAccess.get_sha256(source);var backup_hash:String=FileAccess.get_sha256(source+".bak")
	var directory:String="C:/Users/fwj/AppData/Local/Temp/CAS-home-mobile-review/";DirAccess.make_dir_recursive_absolute(directory)
	var profile:String=directory+"isolated-legacy-ui-%d.json"%OS.get_process_id()
	check(not FileAccess.file_exists(profile),"new normal fixture does not borrow or abandon the user's active voyage")
	var economy=Economy.new(profile);check(economy.load_state().get("ok",false),"create ordinary new account through the unmodified factory")
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.economy=economy;app.page_motion=false
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app)
	await process_frame;app.page_motion=false
	for path in ["home_island","tactical_recruit","littoral_battle","littoral_result"]:
		var packed:PackedScene=load("res://scenes/ui/"+path+".tscn")
		check(packed!=null,"native editable scene "+path)
		var preview:Node=packed.instantiate();check(preview!=null,"instantiate authored scene "+path);preview.free()
	app.show_page("home");await process_frame
	var home:Node=app.page.find_child("HomeIsland",true,false)
	check(home!=null,"home route binds authored island scene")
	if home!=null:
		check(home.find_child("Island",true,false)!=null,"editable procedural island canvas")
		check(home.find_child("Island",true,false).has_method("observe"),"procedural island script compiles and exposes observation binding")
		check(home.find_child("Collect",true,false)!=null,"visible native collect action")
		check(home.find_child("Sortie",true,false)!=null,"visible native sea-land action")
		var island:Control=home.find_child("Island",true,false)
		check(island.rect().position.y>=0 and island.rect().end.y+60<=island.size.y,"complete coast and moored fleet stay inside the island viewport")
	app.show_page("home_recruit");await process_frame
	var pool:Node=app.page.find_child("TacticalRecruit",true,false)
	check(pool!=null,"protocol route binds authored recruit scene")
	if pool!=null:
		check(pool.get_node("Layout/FeaturedScroll/Featured").get_child_count()==20,"all twenty released candidates offered in scrolling row")
		check(pool.get_node("Layout/Actions/DrawOne").disabled,"locked island cannot consume paid recruitment")
	check(app.economy.rearm("IBS-U-USN-FLETCHER").get("ok",false),"use real normal-stock rearm to match the recorded tutorial's 100-percent request")
	var prepared:Dictionary=app.home.prepare_littoral("tutorial",42,["MCP-034"],["IBS-U-USN-FLETCHER"],"balanced","cas-littoral-v1")
	check(prepared.get("ok",false),"UI prepares legitimate training request")
	if prepared.get("ok",false):
		app.launch_littoral(prepared.request);await process_frame;await process_frame
		check(app.screen=="battle" and str(app.core.view.get("littoral",{}).get("version",""))=="cas-littoral-v1","main launch binds real sea-land native observation")
		check(app.battle_controller!=null and app.battle_controller.ui!=null,"dedicated native HUD controller builds")
		if app.battle_controller!=null and app.battle_controller.ui!=null:
			var hud:Control=app.battle_controller.ui
			check(hud.has_node("Tray/Scroll/Cards") and app.core.view.littoral.groups.size()==1,"single drag row presents the real borrowed tutorial group")
			check(hud.get_node("LandWindow/Map").size.x>0,"linked land map has a real authored layout")
			check(not hud.get_node("LandWindow/Controls").visible,"obsolete permanent land controls remain hidden")
			check(hud.get_node("Actions/Naval") is Button and hud.get_node("Actions/Extract") is Button,"real support and extraction commands are reachable")
			app.battle_controller.open_pause_menu();check(app.modal!=null,"dedicated pause menu opens")
			app.close_modal();check(app.checkpoint(),"normal UI checkpoint stores exact littoral log")
			app.core.request({"op":"step","seconds":.3});app.update_battle();check(app.checkpoint(),"persist exact fractional live clock")
			var live_save:String=str(app.core.request({"op":"save","serialized":true}).serialized)
			var wallet_before:Dictionary=app.economy.state.wallet.duplicate(true)
			app.battle_controller.begin_replay()
			check(app.battle_controller.replay_mode and is_equal_approx(app.battle_controller.replay_duration,.3),"live replay preserves fractional duration")
			app.battle_controller.seek_littoral(.3)
			check(is_equal_approx(float(app.core.view.tick),.3),"replay can seek to fractional last microstep")
			app.battle_controller.open_pause_menu()
			var slider:HSlider=app.modal.find_child("LittoralReplaySeek",true,false)
			check(slider!=null and is_equal_approx(slider.step,.1),"native readonly replay exposes a microstep slider")
			app.close_modal();app.battle_controller.end_replay()
			check(not app.battle_controller.replay_mode and not app.running,"ending replay keeps live combat paused")
			check(str(app.core.request({"op":"save","serialized":true}).serialized)==live_save,"ending replay restores exact live native log")
			check(app.economy.state.wallet==wallet_before,"readonly replay cannot spend or grant account resources")
			var recorded:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUTPUT+"tutorial-save.json"))
			if not recorded.commands.is_empty() and str(recorded.commands[-1].request.get("op",""))=="littoral_extract":recorded.commands.pop_back()
			var fixture:Dictionary=app.core.request({"op":"load","serialized":JSON.stringify(load("res://tests/home_runtime_evidence.gd").integral_json(recorded))})
			check(fixture.get("ok",false),"load actual recorded search and recovered-fleet voyage just before extraction "+str(fixture.get("error","")))
			app.running=false;app.update_battle()
			check(app.core.view.get("result")==null and app.core.view.littoral.objectives.all(func(row):return bool(row.complete)),"paused extraction starts with actual searched objective and no fabricated terminal")
			hud.get_node("Actions/Extract").pressed.emit()
			check(app.screen=="result" and app.economy.state.active_run.is_empty(),"paused player extraction settles immediately without waiting for another process frame")
			var final_state:Dictionary=app.economy.state.duplicate(true)
			var final_save:String=str(app.core.request({"op":"save","serialized":true}).serialized)
			check(app.home.settle(app.core.view,final_save).get("duplicate",false) and app.economy.state==final_state,"paused extraction reward is committed exactly once")
	var runtime:Dictionary=load("res://tests/home_runtime_evidence.gd").capture(app.core)
	if not OS.has_environment("CAS_SIM_PATH"):check(bool(runtime.verified_default),"UI uses actual default native PID and manifest SHA without override")
	app.core.close();app.queue_free();await process_frame
	check(FileAccess.get_sha256(source)==source_hash,"main UI account bytes untouched")
	check(FileAccess.get_sha256(source+".bak")==backup_hash,"main UI account backup untouched")
	var receipt:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"headless":true,"visual_gpu_claim":false,"runtime":runtime,"source_sha256":source_hash,"backup_sha256":backup_hash,"profile":ProjectSettings.globalize_path(profile)}
	FileAccess.open(directory+"legacy-ui-receipt.json",FileAccess.WRITE).store_string(JSON.stringify(receipt,"  "))
	print("HOME_UI "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
