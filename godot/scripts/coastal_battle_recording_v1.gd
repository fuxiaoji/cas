extends SceneTree
## P1 sample-battle recording: real Main battle screen, real coastal core raid,
## 1x wall clock, one capture every two seconds. No forged state is submitted;
## the core advances through the app itself and the HUD is the genuine one.
const VERSION:String="cas-island-war-coastal-v1"
const ROOT:String="res://../artifacts/coastal-combat-v2-20261116/"
var app:Control
var frames:int=0
var outcome:String=""
func _initialize()->void:call_deferred("run")
func frames_wait(count:int=3)->void:
	for i in range(count):await process_frame
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
func capture(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await frames_wait(2)
	var path:String=ROOT+"recording/"+name+".png"
	root.get_texture().get_image().save_png(path)
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT+"recording"))
	var normal_hashes:Dictionary={}
	for name in ["cas_port_v1.json","cas_port_v1.json.bak"]:normal_hashes[name]=FileAccess.get_sha256("user://"+name)
	var profile:String=ProjectSettings.globalize_path(ROOT+"recording-player-%d.json"%OS.get_process_id())
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://../artifacts/coastal-rebuild-20261116/player.json"),profile)
	app=load("res://scenes/main.tscn").instantiate()
	app.economy=load("res://scripts/economy.gd").new(profile)
	app.immersive_fullscreen=false;app.boot_to_title=false;app.page_motion=false
	root.size=Vector2i(1600,900);root.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ok:bool=await app.startup_ready
	print("REC startup ",ok)
	app.page_motion=false;app.set_meta("reduced_motion",true)
	app.show_page("home");await frames_wait(6)
	var home=app.page.get_node_or_null("HomeIsland")
	if home==null:print("REC no home");quit(1);return
	# Enter a real battle screen first (combined arms lesson gives the HUD),
	# then swap the core to the raid assault so the same screen renders it.
	var prepared:Dictionary=home.service.latest_training("combined_arms")
	if not prepared.get("ok",false):print("REC training prepare failed");quit(1);return
	await frames_wait(2)
	var train_button:Control=home.get_node("Layout/Top/Training");await frames_wait(2)
	var point:Vector2=train_button.get_global_rect().get_center()
	var motion:InputEventMouseMotion=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
	var down:InputEventMouseButton=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;down.position=point;down.global_position=point;root.push_input(down,true)
	var up:InputEventMouseButton=InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_LEFT;up.pressed=false;up.position=point;up.global_position=point;root.push_input(up,true)
	await frames_wait(4)
	var lesson:Control=app.modal.find_child("Lesson-combined_arms",true,false) if app.modal!=null else null
	if lesson==null:print("REC lesson button missing");quit(1);return
	var lp:Vector2=lesson.get_global_rect().get_center()
	var lm:InputEventMouseMotion=InputEventMouseMotion.new();lm.position=lp;lm.global_position=lp;root.push_input(lm,true)
	var ld:InputEventMouseButton=InputEventMouseButton.new();ld.button_index=MOUSE_BUTTON_LEFT;ld.pressed=true;ld.position=lp;ld.global_position=lp;root.push_input(ld,true)
	var lu:InputEventMouseButton=InputEventMouseButton.new();lu.button_index=MOUSE_BUTTON_LEFT;lu.pressed=false;lu.position=lp;lu.global_position=lp;root.push_input(lu,true)
	await frames_wait(5)
	for i:int in range(60):
		if app.battle_controller!=null:break
		await create_timer(.025).timeout
	var battle=app.battle_controller
	if battle==null:print("REC no battle controller");quit(1);return
	battle.set_primary_map("land")
	if battle.tutorial!=null and battle.tutorial.active:
		var close:Control=battle.tutorial._close
		var cp:Vector2=close.get_global_rect().get_center()
		var cm:InputEventMouseMotion=InputEventMouseMotion.new();cm.position=cp;cm.global_position=cp;root.push_input(cm,true)
		var cd:InputEventMouseButton=InputEventMouseButton.new();cd.button_index=MOUSE_BUTTON_LEFT;cd.pressed=true;cd.position=cp;cd.global_position=cp;root.push_input(cd,true)
		var cu:InputEventMouseButton=InputEventMouseButton.new();cu.button_index=MOUSE_BUTTON_LEFT;cu.pressed=false;cu.position=cp;cu.global_position=cp;root.push_input(cu,true)
		await frames_wait(3)
	# Swap the battle behind the same screen to the real raid assault.
	var spec:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"p1-recording-request.json"))
	var request:Dictionary=spec.get("request_core",{})
	request["geography"]=JSON.parse_string(FileAccess.get_file_as_string("res://data/coastal-demo-v1-714.json"))
	var sim=load("res://scripts/core_bridge.gd").new()
	var response:Dictionary=sim.request(request)
	if not response.get("ok",false):
		print("REC raid request rejected ",JSON.stringify(response.get("error","")));quit(1);return
	app.running=false
	sim.request({"op":"island_autonomy","version":VERSION,"enabled":true})
	app.core=sim;app.run={};app.campaign_mode=true;app.battle_return_route="home";app.elapsed=0
	app.speed=1;app.running=true
	battle.set_primary_map("land");battle.update()
	var map:Control=battle.ui.get_node("LandWindow/Map")
	map.zoom=3.5;map._camera_updated()
	await frames_wait(4)
	print("REC swapped to raid; starting 1x wall recording")
	var started:int=Time.get_ticks_msec()
	while Time.get_ticks_msec()-started<1150000:
		var view:Dictionary=app.core.view
		var ow:Variant=view.get("island_war",{}).get("outcome")
		# Camera follows the assault: allied centroid, else the beach water.
		var ents:Array=view.get("littoral",{}).get("land",{}).get("entities",[])
		var sum:=Vector2();var count:int=0
		for e:Dictionary in ents:
			if str(e.get("side"))=="allies" and float(e.get("hp",0))>0:
				sum+=Vector2(float(e.get("x",0)),float(e.get("y",0)));count+=1
		# Camera priority: allied ground centroid -> naval contact point ->
		# beach water, so the frame always carries the ongoing action.
		var target:=Vector2.ZERO
		var zoom:=2.4
		if count>0:
			target=sum/float(count);zoom=3.5
		else:
			# Naval phase: follow the fighting hulls; fall back to the beach.
			var ssum:=Vector2();var sn:int=0
			for s:Dictionary in view.get("ships",[]):
				if not bool(s.get("alive",true)):continue
				ssum+=Vector2(float(s.get("x",0)),float(s.get("y",0)));sn+=1
			if sn>0:
				target=ssum/float(sn);zoom=2.6
			else:
				for b:Dictionary in view.get("littoral",{}).get("beaches",[]):
					var sea:Dictionary=b.get("sea",{})
					if sea.has("x"):target=Vector2(float(sea.get("x")),float(sea.get("y")));break
				if target==Vector2.ZERO:target=Vector2(14600,12400)
		map.camera_center=target;map.zoom=zoom;map._camera_updated()
		frames+=1
		await capture("frame-%04d"%frames)
		await create_timer(2.0).timeout
		if ow!=null and str(ow).strip_edges()!="":
			outcome="settled";break
	var view:Dictionary=app.core.view
	var report:Dictionary={"frames":frames,"outcome_seen":outcome!="","tick":app.core.view.get("tick"),
		"duration_s":float(app.core.view.get("tick",0.0)),
		"core_sha256":FileAccess.get_sha256(OS.get_environment("CAS_SIM_PATH")),
		"mode":"real Main battle screen, real raid core, 1x wall clock, autonomy driver",
		"normal_profile_unchanged":true,"hud":"genuine battle screen"}
	for name in normal_hashes:report["normal_profile_unchanged"]=report["normal_profile_unchanged"] and FileAccess.get_sha256("user://"+str(name))==normal_hashes[name]
	var file=FileAccess.open(ROOT+"recording/recording-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close()
	print("COASTAL_BATTLE_RECORDING ",JSON.stringify(report))
	if is_instance_valid(app):app.running=false;app.core.close();app.queue_free()
	await frames_wait(2);quit(0)
