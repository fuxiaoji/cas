extends "res://tests/littoral_drag_v2_review.gd"
## Real native 50-person defense, real Main clock, real native buttons and isolated account.
var measurements:Array=[]
var sample_frames:Array[float]=[]
var previous_usec:int=0
var measuring:bool=false
func _process(_delta:float)->bool:
	if measuring:
		var now:int=Time.get_ticks_usec()
		if previous_usec>0:sample_frames.append((now-previous_usec)/1000.0)
		previous_usec=now
	return false
func quantile(values:Array[float],q:float)->float:
	if values.is_empty():return 0
	var ordered:Array[float]=values.duplicate();ordered.sort();return ordered[mini(ordered.size()-1,int(q*(ordered.size()-1)))]
func run()->void:
	output_dir="res://../artifacts/littoral-motion-v3/presentation/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	profile=output_dir+"isolated-%d.json"%OS.get_process_id()
	var account=load("res://scripts/economy.gd").new(profile);check(account.load_state().get("ok",false),"fresh isolated ordinary UI account")
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.fullscreen_battle=true
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames();app.set_process(false);app.page_motion=false
	var roster:Array=["MCP-034","MCP-009","MCP-011","MCP-018","MCP-052"]
	var request:Dictionary={"op":"new_littoral","version":"cas-littoral-v3","seed":45,"mode":"defense","ships":[{"id":"IBS-U-IJN-NISSHIN","hp":100,"ammo":100},{"id":"IBS-U-USN-ERMA-IOWA","hp":100,"ammo":100}],"roster":roster,"unit_condition":[],"company_transports":[],"transport_preset":"transport","defense":[]}
	for id in roster:request.unit_condition.append({"id":id,"hp":100});request.company_transports.append({"id":id,"kind":"landing_craft"})
	check(app.core.request(request).get("ok",false),"normal native v3 configuration spawns actual five companies")
	app.show_page("battle");controller().set_primary_map("land");app.running=false;app.update_battle();await frames()
	var friendly:Array=app.core.view.littoral.land.entities.filter(func(row):return str(row.side)=="allies")
	check(friendly.size()==50,"native publishes fifty distinct friendly bodies")
	var land:Control=controller().ui.get_node("LandWindow/Map")
	check(land.actors.values().filter(func(row):return row.friendly).size()==50,"all fifty actual bodies rendered without truncation")
	var body_positions:Dictionary={}
	for row in friendly:body_positions[str(row.id)]={"x":row.x,"y":row.y}
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://bin/core-current.json"))
	var path:String=OS.get_environment("CAS_SIM_PATH")
	if path.is_empty():path=ProjectSettings.globalize_path("res://bin/"+str(manifest.executable))
	var runtime:Dictionary={"override":OS.get_environment("CAS_SIM_PATH"),"path":path,"sha256":FileAccess.get_sha256(path),"manifest":manifest,"verified_default":not OS.has_environment("CAS_SIM_PATH"),"version":app.core.view.version}
	for size in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=size;await frames(6)
		var identity_map:Dictionary={}
		for key in land.actors:identity_map[key]=land.actors[key].get_instance_id()
		for speed in [1,2,4,8]:
			var button:Button=controller().ui.get_node("Top/Speeds/Speed%d"%speed)
			var actual_height:float=(root.get_screen_transform()*Vector2(0,button.size.y)-root.get_screen_transform()*Vector2.ZERO).length()
			check(actual_height>=43.9,"native speed target >=44px "+str(size)+" "+str(speed))
			await click(button);check(app.speed==speed,"actual pointer chooses "+str(speed)+"x at "+str(size))
		await shot("fifty-land-%dx%d"%[size.x,size.y])
		await click(controller().ui.get_node("MiniMap"));await shot("fifty-sea-%dx%d"%[size.x,size.y]);await click(controller().ui.get_node("MiniMap"))
		check(land.actors.keys().all(func(key):return identity_map.get(key)==land.actors[key].get_instance_id()),"both map sizes retain fifty original animation instances "+str(size))
		for body in friendly:
			var hit:Dictionary=land.target_at(land.actor_hit_point(int(body.id)))
			check(int(hit.get("id",-1))==int(body.id),"each dispersed real body remains individually targetable "+str(size)+" "+str(body.id))
		for row in app.core.view.littoral.land.entities:
			if str(row.side)=="allies":check(body_positions[str(row.id)]=={"x":row.x,"y":row.y},"visual spread never moves native body "+str(row.id))
	root.size=Vector2i(1280,720);await frames(5)
	for unit in roster:
		var body:Dictionary=friendly.filter(func(row):return str(row.unit_id)==str(unit))[0]
		var point:Vector2=screen_point(global_point(land,land.actor_hit_point(int(body.id))))
		var down:=InputEventMouseButton.new();down.position=point;down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;Input.parse_input_event(down);await process_frame
		var up:=InputEventMouseButton.new();up.position=point;up.button_index=MOUSE_BUTTON_LEFT;Input.parse_input_event(up);inputs+=2;await frames()
		check(controller().selected_unit==unit,"clicking actual dispersed member selects her original company "+str(unit))
	controller().selected_unit="MCP-034";app.update_battle();await frames()
	for speed in [1,2,4,8]:
		app.running=false;controller().set_battle_speed(speed);app.elapsed=0;app.running=true;app.set_process(true)
		var start_tick:float=float(app.core.view.tick);var start:int=Time.get_ticks_usec();sample_frames.clear();previous_usec=0;measuring=true
		await create_timer(2.1).timeout
		measuring=false;var wall:float=(Time.get_ticks_usec()-start)/1000000.0;var advanced:float=float(app.core.view.tick)-start_tick
		app.set_process(false);app.running=false;app.update_battle()
		var measure:Dictionary={"speed":speed,"wall_seconds":wall,"native_seconds":advanced,"actual_ratio":advanced/wall,"frame_ms_p50":quantile(sample_frames,.5),"frame_ms_p95":quantile(sample_frames,.95),"frame_ms_max":sample_frames.max() if not sample_frames.is_empty() else 0,"frames":sample_frames.size(),"clock_debt_seconds":app.elapsed}
		measurements.append(measure);check(absf(advanced-wall*speed)<=maxf(.3,wall*speed*.13),"actual fixed native clock tracks "+str(speed)+"x wall clock")
		check(app.elapsed>=-.00001 and app.elapsed<.21,"native microstep remainder retained at "+str(speed)+"x")
	var paused_tick:float=float(app.core.view.tick);var animation:Dictionary={}
	for key in land.actors:animation[key]=[land.actors[key].position,land.actors[key].animation_time,land.actors[key].frame_index]
	app.set_process(true);await create_timer(.35).timeout;app.set_process(false)
	check(float(app.core.view.tick)==paused_tick,"pause stops authoritative clock at high speed")
	check(land.actors.keys().all(func(key):return animation.get(key)==[land.actors[key].position,land.actors[key].animation_time,land.actors[key].frame_index]),"pause stops all tactical walking and projected positions")
	check(controller().ui.get_node("Top/Status").text.begins_with("已暂停"),"pause is explicitly visible beside current speed")
	app.running=true;app.elapsed=0;var debt_start:float=float(app.core.view.tick);app._process(.4)
	check(absf((float(app.core.view.tick)-debt_start)+app.elapsed-3.2)<.00001,"one slow 8x frame retains all 3.2 native seconds across fixed-step cap")
	app._process(0);app.running=false;app.update_battle()
	check(absf(float(app.core.view.tick)-debt_start-3.2)<.00001 and app.elapsed<.00001,"bounded microstep debt catches up without silently dropping native time")
	var saved:String=app.core.request({"op":"save","serialized":true}).serialized
	app.core.close();check(app.core.request({"op":"load","serialized":saved}).get("ok",false),"same real world restores through a new native process")
	land.prime_visuals();app.update_battle();await frames()
	check(str(app.core.request({"op":"save","serialized":true}).serialized)==saved,"presentation restore preserves complete native save")
	check(land.actors.values().all(func(row):return row.hurt_until<0 and row.fire_until<0 and row.defeated_at<0),"restored first frame does not replay historical hurt or fire")
	FileAccess.open(output_dir+"performance.json",FileAccess.WRITE).store_string(JSON.stringify({"runtime":runtime,"measurements":measurements,"public_friendly_bodies":friendly.size(),"rendered_friendly_bodies":land.actors.values().filter(func(row):return row.friendly).size(),"body_positions":body_positions,"account_scope":"fresh isolated UI account, native fixture only, no rewards claimed","fixed_step_seconds":.1},"  "))
	await shot("fifty-restored-paused")
	finish()
