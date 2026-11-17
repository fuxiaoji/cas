extends SceneTree
## Production Main clock and actual native bodies; the account remains isolated.
var checks:int=0
var failures:Array[String]=[]
var app
var samples:Array[float]=[]
var measuring:bool=false
var last_usec:int=0
var output:String="res://../artifacts/island-war-v2/presentation/"
func _initialize()->void:call_deferred("run")
func _process(_delta:float)->bool:
	if measuring:
		var now:int=Time.get_ticks_usec()
		if last_usec>0:samples.append(float(now-last_usec)/1000)
		last_usec=now
	return false
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func frames(count:int=4)->void:
	for index in range(count):await process_frame
func percentile(values:Array[float],fraction:float)->float:
	if values.is_empty():return 0
	var ordered:Array[float]=values.duplicate();ordered.sort()
	return ordered[mini(ordered.size()-1,int(fraction*(ordered.size()-1)))]
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var normal:String=FileAccess.get_sha256("user://cas_port_v1.json");var backup:String=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	var path:String=OS.get_environment("CAS_V2_PERF_FIXTURE") if OS.has_environment("CAS_V2_PERF_FIXTURE") else "res://../artifacts/island-war-v2/core/performance-midbattle.json"
	if not FileAccess.file_exists(path):check(false,"actual native performance fixture exists");finish({});return
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var account=load("res://scripts/economy.gd").new(output+"performance-isolated-%d.json"%OS.get_process_id());account.new_profile();account.state.progression.first_voyage_canon.active=false
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.deferred_startup=false;app.staged_navigation=false;app.economy=account;app.immersive_fullscreen=false
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames(7)
	app.page_motion=false;app.page_transition.cancel();app.set_process(false);AudioServer.set_bus_mute(0,true)
	app.home.development();app.show_page("home");await frames()
	var before_account:String=JSON.stringify(account.state);var before_disk:String=FileAccess.get_sha256(account.save_path)
	# Reuse the production isolation lifecycle, then load a documented real native
	# defense fixture into its separate process. No account ownership is claimed.
	var opening:Dictionary=fixture.initial_request
	if str(opening.get("mode",""))!="exercise":opening=JSON.parse_string(FileAccess.get_file_as_string("res://../artifacts/island-war-v2/core/exercise-initial-trial.json")).initial_request
	await app.launch_home_exercise(opening);await frames()
	check(app.home_exercise_session!=null and app.home_exercise_session.active,"independent native test session opened")
	if app.home_exercise_session==null or not app.home_exercise_session.active:finish({"opening_error":app.core.error});return
	check(app.core.request({"op":"load","serialized":str(fixture.serialized)}).get("ok",false),"actual midbattle world loads through the native core")
	app.running=false;app.set_process(false);app.update_battle();await frames()
	var controller=app.battle_controller;controller.set_primary_map("land")
	if controller.tutorial!=null:controller.tutorial.active=false;controller.tutorial.hide()
	controller.tutorial_dismissed=true
	var land=controller.ui.get_node("LandWindow/Map")
	var bodies:Array=app.core.view.littoral.land.entities
	check(bodies.size()>=96,"fixture contains at least ninety-six actual native bodies")
	check(land.display_offsets.is_empty(),"benchmark uses native centers without company display slots")
	var candidates:Array=bodies.filter(func(row):return str(row.get("phase",""))=="ground" and float(row.get("hp",0))>0)
	if not candidates.is_empty():
		land.camera_center=Vector2(float(candidates[0].x),float(candidates[0].y));land.zoom=5;land._camera_updated()
	await frames(12)
	var segments:Array=[]
	for index in range(5):
		var started:int=Time.get_ticks_usec();app.core.request({"op":"step","seconds":.1})
		var native_ms:float=float(Time.get_ticks_usec()-started)/1000
		started=Time.get_ticks_usec();controller.naval_controller.update();var naval_ms:float=float(Time.get_ticks_usec()-started)/1000
		started=Time.get_ticks_usec();app.update_battle();var update_ms:float=float(Time.get_ticks_usec()-started)/1000
		segments.append({"native_ipc_ms":native_ms,"original_naval_update_ms":naval_ms,"full_update_ms":update_ms})
	var measures:Array=[]
	for speed in [1,8]:
		controller.set_battle_speed(speed);app.elapsed=0;app.running=true;app.set_process(true)
		var start:int=Time.get_ticks_usec();var start_tick:float=float(app.core.view.tick)
		samples.clear();last_usec=0;measuring=true
		await create_timer(3.1).timeout
		measuring=false;var wall:float=float(Time.get_ticks_usec()-start)/1000000;var elapsed:float=float(app.core.view.tick)-start_tick
		app.running=false;app.set_process(false);app.update_battle()
		measures.append({"speed":speed,"wall_seconds":wall,"native_seconds":elapsed,"actual_ratio":elapsed/wall,"frames":samples.size(),"frame_ms_p50":percentile(samples,.5),"frame_ms_p95":percentile(samples,.95),"frame_ms_max":samples.max() if not samples.is_empty() else 0,"clock_debt_seconds":app.elapsed,"bodies_end":app.core.view.littoral.land.entities.size(),"static_memory_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),"video_texture_bytes":int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))})
		check(elapsed>0,"production Main advances actual native time at "+str(speed)+"x")
		check(app.elapsed>=-.00001,"simulation debt remains recorded rather than discarded")
		if app.core.view.get("finished",false):break
	var tick:float=float(app.core.view.tick);app.set_process(true);await create_timer(.25).timeout;app.set_process(false)
	check(float(app.core.view.tick)==tick,"pause freezes the actual native world")
	if DisplayServer.get_name()!="headless":
		RenderingServer.force_draw(false);root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output+"actual-native-bodies-performance.png"))
	app.close_home_exercise();await frames()
	check(JSON.stringify(account.state)==before_account and FileAccess.get_sha256(account.save_path)==before_disk,"performance exercise preserves the complete isolated account and disk")
	check(FileAccess.get_sha256("user://cas_port_v1.json")==normal and FileAccess.get_sha256("user://cas_port_v1.json.bak")==backup,"normal account and backup remain untouched")
	finish({"fixture":path,"scope":"actual production Main, native IPC, original naval UI and v2 body renderer; real defense snapshot in the independent test process; isolated offscreen Windows GPU, not Android or account ownership","initial_bodies":bodies.size(),"native_step_and_update_ms":segments,"measures":measures,"adapter":RenderingServer.get_video_adapter_name()})
func finish(data:Dictionary)->void:
	data.merge({"ok":failures.is_empty(),"checks":checks,"failures":failures})
	FileAccess.open(output+"performance-receipt.json",FileAccess.WRITE).store_string(JSON.stringify(data,"\t"));print(JSON.stringify(data))
	if is_instance_valid(app):app.queue_free();await frames()
	quit(0 if failures.is_empty() else 1)
