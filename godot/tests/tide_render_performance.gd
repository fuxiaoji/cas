extends SceneTree
## Actual native samples, uncapped GPU frames and the real account command path.
const Main=preload("res://scenes/main.tscn")
const Economy=preload("res://scripts/economy.gd")
const Settle=preload("res://tests/transition_settle.gd")
const OUTPUT="res://../artifacts/godot/tide-performance/"
var app
var rows:Array=[]
var failures:Array=[]
var path:String
func _initialize()->void:call_deferred("run")
func check(ok:bool,text:String)->void:
	if not ok:failures.append(text);push_error(text)
func stats(values:Array)->Dictionary:
	var sorted:Array=values.duplicate();sorted.sort()
	return {"p50":sorted[sorted.size()/2],"p95":sorted[int((sorted.size()-1)*.95)],"max":sorted.back(),"mean":sorted.reduce(func(sum,value):return sum+value,0.0)/sorted.size()}
func frames(count:int)->void:
	for index in count:await process_frame
func measure(label:String)->void:
	await frames(30)
	var elapsed:Array=[];var process:Array=[];var draws:Array=[];var objects:Array=[];var previous:int=Time.get_ticks_usec()
	for index in 180:
		await process_frame
		var now:int=Time.get_ticks_usec();elapsed.append(float(now-previous)/1000.0);previous=now
		process.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME));objects.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var view:Dictionary=app.core.view
	rows.append({"label":label,"window":DisplayServer.window_get_size(),"tick":view.tick,"contacts":view.contacts.size(),"drops":view.tide.drops.size(),"frame_ms":stats(elapsed),"process_ms":stats(process),"draw_calls":stats(draws),"render_objects":stats(objects)})
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT+label+".png"))
	print("TIDE_FRAME ",JSON.stringify(rows.back()))
func run()->void:
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);Engine.max_fps=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUTPUT+"v1-actual-samples.json"))
	path="user://tests/tide-performance-%d.json"%OS.get_process_id();DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	check(DirAccess.copy_absolute(ProjectSettings.globalize_path("res://../artifacts/extraction-stall-20261113/actual-account-refilled.json"),ProjectSettings.globalize_path(path))==OK,"clone actual43 profile")
	app=Main.instantiate();app.boot_to_title=false;app.economy=Economy.new(path);root.add_child(app);app.set_process(false);await Settle.wait_for_route(self,app);app.page_motion=false
	check(app.economy.abandon_sortie().get("ok",false),"normal isolated abandonment")
	app.core.request({"op":"load","serialized":fixture.samples["0"].serialized})
	var prepared:Dictionary=load("res://scripts/tide_event_service.gd").new(app.economy).begin(fixture.request,str(fixture.samples["0"].serialized))
	check(prepared.get("ok",false),"real versioned account activity begins")
	app.run=app.economy.resume_sortie();app.enter_battle();await Settle.wait_for_route(self,app)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);app.fullscreen_battle=false;await frames(3)
	for resolution in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=resolution;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		for tick in ["0","150"]:
			check(app.core.request({"op":"load","serialized":fixture.samples[tick].serialized}).get("ok",false),"load captured native tick"+tick)
			app.update_battle();app.running=false;app.sea.focus_fleet()
			await measure("%dx%d-t%s"%[resolution.x,resolution.y,tick])
	var input_times:Array=[];var snapshot_times:Array=[]
	for index in 12:
		var began:int=Time.get_ticks_usec()
		app.issue({"op":"route","fleet":1,"mode":"follow","speed":60,"points":[{"x":12000+index*20,"y":7000}]})
		input_times.append(float(Time.get_ticks_usec()-began)/1000.0)
		began=Time.get_ticks_usec();app.checkpoint();snapshot_times.append(float(Time.get_ticks_usec()-began)/1000.0)
	var hashes:Dictionary={}
	for source in ["tide_sea.gd","tide_battle.gd","tide_battle_hud.gd","main.gd","core_bridge.gd"]:hashes[source]=FileAccess.get_sha256("res://scripts/"+source)
	var label:String="after" if "--after" in OS.get_cmdline_user_args() else "baseline"
	var report:Dictionary={"rows":rows,"route_issue_ms":stats(input_times),"checkpoint_ms":stats(snapshot_times),"source_hashes":hashes,"manifest":fixture.manifest,"failures":failures,"native_samples":true,"account_owned":app.economy.state.owned.size(),"normal_account_modified":false,"vsync":"disabled","renderer":RenderingServer.get_video_adapter_name()}
	FileAccess.open(OUTPUT+label+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	app.audio.shutdown();app.core.close();app.queue_free();await frames(2)
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	print("TIDE_PERFORMANCE ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
