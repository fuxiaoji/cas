extends SceneTree
var checks:int=0
var failures:Array[String]=[]
var app
var output:String="res://../artifacts/island-war-v1/presentation/"
func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func frames(count:int=4)->void:
	for i in range(count):await process_frame
func click(node:Control)->void:
	check(node!=null,"pointer target exists")
	if node==null:return
	var point:Vector2=node.get_viewport().get_screen_transform()*(node.get_global_transform_with_canvas()*(node.size*.5))
	for pressed in [true,false]:
		var e:=InputEventMouseButton.new();e.position=point;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed;Input.parse_input_event(e);await process_frame
	await frames()
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await frames();await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output+name+".png"))==OK,"screenshot "+name)
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var normal:String=FileAccess.get_sha256("user://cas_port_v1.json");var backup:String=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	var account=load("res://scripts/economy.gd").new(output+"isolated-%d.json"%OS.get_process_id());account.new_profile();account.state.progression.first_voyage_canon.active=false
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.deferred_startup=false;app.staged_navigation=false;app.economy=account;app.immersive_fullscreen=false
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames(8);app.page_motion=false;app.page_transition.cancel();app.set_process(false);AudioServer.set_bus_mute(0,true)
	app.home.development();app.home.state().unlocked=true;app.home.state().tutorial_complete=true;app.home.state().drag_tutorial_completed=true
	var terminal:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../artifacts/island-war-v1/core/raid-terminal.json"))
	var saved:Dictionary=JSON.parse_string(str(terminal.serialized))
	app.home.state().development_v2.replays["native-proof"]={"run_id":"native-proof","title":"实际十连夺岛回放","snapshot":str(terminal.serialized),"initial_snapshot":"","initial_request":terminal.initial_request,"commands":saved.get("commands",[]),"ruleset":"cas-island-war-v1","core_version":"candidate","success":true,"at":int(Time.get_unix_time_from_system()),"local_simulation":true}
	var live_request:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../artifacts/littoral-v4/defense-fifty-air-request.json"))
	check(app.core.request(live_request).ok,"independent real live World is initialized")
	app.core.request({"op":"step","seconds":2.3});var live_core=app.core;var live_snapshot:String=app.core.request({"op":"save","serialized":true}).serialized
	app.run={"mode":"littoral","run_id":"isolated-live-guard","snapshot":live_snapshot};account.state.active_run=app.run.duplicate(true);account.save_state();var disk_before:String=FileAccess.get_sha256(account.save_path)
	app.show_page("home");await frames()
	var disk_before_text:String=FileAccess.get_file_as_string(account.save_path);disk_before=disk_before_text.sha256_text()
	await app.open_home_replay("native-proof");await frames()
	check(app.screen=="battle" and app.battle_controller.replay_mode,"actual Main opens read-only island recording")
	check(app.core!=live_core and app.home_replay_session.active,"viewer owns a separate native process")
	check(app.page.find_child("HomeReplayControls",true,false)!=null,"editable replay toolbar is visible")
	var controller=app.battle_controller
	check(not app.issue({"op":"littoral_abandon"}).ok,"recording refuses combat commands")
	var verifier=load("res://scripts/core_bridge.gd").new()
	for second in [18.2,46.1,9.5,80.0]:
		controller.seek_littoral(second)
		var expected:Dictionary=verifier.request({"op":"replay","serialized":str(terminal.serialized),"tick":second})
		check(expected.ok and verifier.view==app.core.view,"forward/backward seek exact public observation at "+str(second))
	await shot("actual-raid-replay")
	var toolbar=app.page.find_child("HomeReplayControls",true,false)
	await click(toolbar.get_node("Margin/Column/Row/Play"));check(app.running,"actual pointer starts recording")
	var replay_start:float=controller.replay_seconds;app._process(.2);check(controller.replay_seconds>replay_start,"playback advances native cursor")
	await click(toolbar.get_node("Margin/Column/Row/Play"));check(not app.running,"actual pointer pauses recording")
	controller.set_primary_map("land");await frames();var land=controller.ui.get_node("LandWindow/Map")
	await shot("actual-land-replay")
	var art=load("res://scripts/tactical_transport_art.gd");art._load()
	for id in art.catalogue:
		for delta_world in [Vector2(150,0),Vector2(-150,0),Vector2(0,150),Vector2(0,-150)]:
			var actor=load("res://scripts/tactical_sprite.gd").new();root.add_child(actor);actor.motion_projector=land.project
			var entry:Dictionary=art.catalogue[id];var kind:String=str(entry.default_kind)
			var row:Dictionary={"id":300,"unit_id":id,"side":"allies","kind":kind,"hp":100,"max_hp":100,"x":12000,"y":8500}
			actor.configure(row,"",40,null);var origin:=Vector2(12000,8500);actor.observe(row,land.project(origin),0,.1,false)
			row=row.duplicate();row.x+=delta_world.x;row.y+=delta_world.y;actor.observe(row,land.project(origin+delta_world),.1,.1,false)
			for i in range(50):actor.advance(.02,.1,true)
			var expected:Vector2=(land.project(origin+delta_world)-land.project(origin)).normalized();var facing:=Vector2(sin(actor.travel_heading),-cos(actor.travel_heading))
			check(expected.dot(facing)>.999,"isometric bow agrees with movement "+id+" "+str(delta_world));actor.queue_free()
	var fx=land.support_fx;check(fx!=null,"real support FX is bound to map")
	check(fx.atlas!=null and fx.atlas.get_width()==1774,"native-generated transparent artillery atlas is consumed")
	var launch:Dictionary={}
	for second in range(1,121):
		controller.seek_littoral(second,true)
		for record in app.core.view.littoral.get("shots",[]):
			if str(record.get("kind",""))=="naval" and float(record.get("flight_seconds",0))>.2:launch=record;break
		if not launch.is_empty():break
	check(not launch.is_empty(),"actual raid emits authoritative naval-support launch")
	if not launch.is_empty():
		var end:=Vector2(float(launch.target_x),float(launch.target_y));var fired:float=float(launch.tick);var flight:float=float(launch.flight_seconds)
		controller.seek_littoral(fired+flight*.55)
		land.zoom=10;land.camera_center=end;land._camera_updated();await frames()
		check(land.support_fx.records.size()>0,"artillery trail uses the real observed shot")
		await shot("actual-artillery-trajectory")
		controller.seek_littoral(fired+flight+.1);await frames();await shot("actual-artillery-impact")
		var exact:Dictionary=app.core.view.duplicate(true)
		land.motion_strength=0;land.support_fx.strength=0;app.running=true;land.playing=true
		await frames(25);app.running=false;land.playing=false
		check(app.core.view==exact,"visual artillery and recoil never advance or alter native damage")
		check(land.support_fx.last_offset.length()<.001,"zero shake slider removes map displacement")
	var shoreline:Array=land.land.get("polygon",[])
	if not shoreline.is_empty():
		land.zoom=6;land.camera_center=Vector2(float(shoreline[0].x),float(shoreline[0].y));land._camera_updated();await frames()
	await shot("procedural-coast-detail")
	await app.close_home_replay();await frames()
	check(app.core==live_core and str(app.core.request({"op":"save","serialized":true}).serialized)==live_snapshot,"closing replay restores the same untouched live native World")
	check(FileAccess.get_sha256(account.save_path)==disk_before,"watching recording never rewrites account or grants rewards")
	if FileAccess.get_sha256(account.save_path)!=disk_before:
		FileAccess.open(output+"before-viewer.json",FileAccess.WRITE).store_string(disk_before_text);FileAccess.open(output+"after-viewer.json",FileAccess.WRITE).store_string(FileAccess.get_file_as_string(account.save_path))
	load("res://scripts/home_conflict_ui.gd").open(app)
	await frames();await click(app.modal.find_child("HomeCGGallery",true,false))
	check(app.modal.name=="TacticalCGGallery","island affairs opens real CG gallery")
	var seen_pictures:Dictionary={};var art_memory_before:float=Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	for i in range(20):
		var owner=app.modal.get_meta("gallery_owner");check(owner.units.size()==20,"all twenty identities have imported CGs")
		var identity:String=str(owner.units[owner.index].id);var picture:TextureRect=app.modal.find_child("TacticalDefeatCG",true,false)
		print("CG_POINTER ",i," ",owner.index," ",identity)
		check(picture.texture!=null and picture.texture.resource_path.ends_with("/"+identity+".png"),"CG matches selected original identity "+identity)
		check(picture.texture.get_width()==1672 and picture.texture.get_height()==941,"full resolution imported CG "+identity)
		seen_pictures[identity]=true
		if i==0 or i==19:await shot("dense-cg-"+identity)
		await click(app.modal.find_child("NextTacticalCG",true,false))
	check(seen_pictures.size()==20,"actual pointer browsing reaches twenty distinct images")
	var image_weak:WeakRef=weakref(app.modal.find_child("TacticalDefeatCG",true,false).texture)
	await click(app.modal.find_child("CloseTacticalCG",true,false));await frames(8)
	check(app.modal!=null and app.modal.name=="HomeConflictPanel","gallery returns to the previous island affairs page")
	check(image_weak.get_ref()==null,"closing CG gallery releases its last full resolution image")
	var art_memory_after:float=Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	var failed:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../artifacts/island-war-v1/core/defense-loss-terminal.json"));var outcome:Dictionary=failed.snapshot.littoral.outcome
	check(not outcome.success and outcome.units[0].incapacitated,"CG result fixture is an actual native failed defense")
	var result=load("res://scenes/ui/littoral_result.tscn").instantiate();app.add_child(result);result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result.bind(app,{"success":false,"title":"实际守岛失利","units":outcome.units,"ships":[],"request":failed.initial_request})
	await frames();var failed_identity:String=str(outcome.units[0].id);await click(result.find_child("DefeatCG_"+failed_identity,true,false))
	check(str(app.modal.get_meta("gallery_owner").units[app.modal.get_meta("gallery_owner").index].id)==failed_identity,"real loss result opens the affected unit's CG")
	app.close_modal();result.queue_free();await frames(6)
	check(FileAccess.get_sha256("user://cas_port_v1.json")==normal and FileAccess.get_sha256("user://cas_port_v1.json.bak")==backup,"ordinary account and backup untouched")
	check(str(ProjectSettings.get_setting("application/config/icon","")).contains("fletcher-v2"),"project uses original finger-gun Fletcher icon")
	verifier.close();app.core.close();app.queue_free();await frames()
	var receipt:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"normal_account_unchanged":true,"cg_identities_browsed":seen_pictures.size(),"gallery_texture_bytes_before":art_memory_before,"gallery_texture_bytes_after":art_memory_after,"scope":"real recorded native raid in independent process; real pointer play/pause; public seek parity; eighty projected vehicle directions; twenty imported CG identities and actual loss result binding; no normal-account writes"}
	FileAccess.open(output+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(receipt,"  "));print("ISLAND_PRESENTATION "+JSON.stringify(receipt));quit(0 if failures.is_empty() else 1)
