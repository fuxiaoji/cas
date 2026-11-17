extends "res://scripts/coastal_play_review_v1.gd"
## Actual Main continuous playback plus separately labelled renderer fixtures.
const OUT:String="res://../artifacts/coastal-rebuild-20261116/motion-review/"
var samples:Array=[]
var fixture_checks:int=0
var live_walk_frames:int=0
var direction_failures:int=0
var maximum_anchor_error:float=0
var maximum_fallen_penetration:float=0
var landing_samples:Array=[]
var vehicle_fire_samples:Array=[]
var captured_shots:Dictionary={}
var native_speed_samples:Array[float]=[]
var native_speed_worst:Array=[]
var previous_native_rows:Dictionary={}
var previous_native_tick:float=-1
var public_velocity_max:float=0
func capture(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await frames(3)
	var path:String=OUT+name+".png";root.get_texture().get_image().save_png(path);images.append(ProjectSettings.globalize_path(path))
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for name in ["cas_port_v1.json","cas_port_v1.json.bak"]:normal_hashes[name]=FileAccess.get_sha256("user://"+name)
	if OS.get_environment("CAS_MOTION_FIXTURE_ONLY")=="1":
		root.size=Vector2i(1600,900)
		var observed:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"battle-observation.json"))
		var source:Dictionary=observed.littoral.land.duplicate(true)
		var fixture:Control=spawn_renderer_fixture()
		fixture.observe(source,false);fixture.set_camera(fixture.surface.origin,8);await frames(3)
		await direction_and_motion_fixture(fixture,source,fixture.surface.origin)
		await corpse_fixture(fixture,source)
		await vehicle_weapon_fixture(fixture,source)
		fixture.get_parent().queue_free();await frames(2);finish();return
	var profile:String=ProjectSettings.globalize_path(OUT+"review-player-%d.json"%OS.get_process_id())
	DirAccess.copy_absolute(ProjectSettings.globalize_path(ROOT+"player.json"),profile)
	app=load("res://scenes/main.tscn").instantiate();app.economy=load("res://scripts/economy.gd").new(profile)
	app.immersive_fullscreen=false;app.boot_to_title=false;app.page_motion=false
	root.size=Vector2i(1600,900);root.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	check(app.startup_ready,"real Main starts with copied account")
	app.page_motion=false;app.set_meta("reduced_motion",true)
	app.show_page("home");await frames(6)
	var home=app.page.get_node_or_null("HomeIsland")
	check(home!=null,"actual home opens")
	if home==null:finish();return
	var lesson_key:String=OS.get_environment("CAS_MOTION_LESSON");if lesson_key.is_empty():lesson_key="landing"
	var prepared:Dictionary=home.service.latest_training(lesson_key);check(prepared.get("ok",false),"native coastal training accepts published account")
	FileAccess.open(OUT+"training-request.json",FileAccess.WRITE).store_string(JSON.stringify(prepared))
	await capture("main-home-ready")
	await click(home.get_node("Layout/Top/Training"));await frames(3)
	var lesson:Control=app.modal.find_child("Lesson-"+lesson_key,true,false) if app.modal!=null else null
	check(lesson!=null,"actual lesson button found")
	if lesson==null:finish();return
	await capture("main-lesson-menu")
	await click(lesson);await frames(5)
	for i:int in range(60):
		if app.battle_controller!=null:break
		await create_timer(.025).timeout
	var battle=app.battle_controller
	print("MOTION_ENTER ",app.screen," lesson rect ",lesson.get_global_rect() if is_instance_valid(lesson) else Rect2()," modal ",app.modal)
	if battle==null and app.home_exercise_session!=null:
		print("MOTION_OPEN_DIAGNOSTIC ",JSON.stringify(app.home_exercise_session.open(app,prepared.request)))
	await capture("main-after-lesson")
	check(battle!=null,"actual battle controller entered")
	if battle==null:finish();return
	battle.set_primary_map("land")
	if battle.tutorial!=null and battle.tutorial.active:await click(battle.tutorial._close)
	var map=battle.ui.get_node("LandWindow/Map")
	var groups:Array=app.core.view.littoral.groups
	var selected:Dictionary={}
	var unit:String="MCP-022" if lesson_key=="combined_arms" else "MCP-034"
	for group:Dictionary in groups:
		if str(group.unit_id)==unit:selected=group;break
	check(not selected.is_empty(),"own native company present "+unit)
	if selected.is_empty():finish();return
	var card:Control=company_card(battle,str(selected.company_id))
	var beach:Dictionary={}
	for candidate:Dictionary in app.core.view.littoral.beaches:
		if int(candidate.id)==2:beach=candidate.land;break
	check(card!=null and not beach.is_empty(),"native legal beach and real drag card found")
	if card==null or beach.is_empty():finish();return
	var replay_path:String=OS.get_environment("CAS_MOTION_LOAD_SAVE")
	if not replay_path.is_empty() and FileAccess.file_exists(replay_path):
		var replay:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(replay_path))
		var restored:Dictionary=app.core.request({"op":"load","serialized":str(replay.serialized)})
		check(restored.get("ok",false),"actual Main restores genuine native checkpoint, no invented state")
	else:await drag(card.get_global_rect().get_center(),map.get_global_transform()*map.project(Vector2(float(beach.x),float(beach.y))))
	app.running=false
	# Wait using authority microsteps, stopping when actual bodies disembark.
	var landed_ids:Dictionary={}
	var expected_count:int=int(selected.get("initial_count",1))+int(selected.get("combat_vehicle_count",0))
	for i:int in range(300):
		var response:Dictionary=app.core.request({"op":"step","seconds":.5})
		check(response.get("ok",false),"native landing step %d"%i)
		var ashore:bool=false
		for row:Dictionary in app.core.view.littoral.land.entities:
			if str(row.get("company_id",""))==str(selected.company_id) and str(row.get("phase",""))=="active" and row.get("carried_by")==null and not bool(row.get("seated",false)) and float(row.get("hp",0))>0:
				ashore=true
				if landed_ids.has(str(row.id)):continue
				landed_ids[str(row.id)]=true
				var transport_gap:float=INF
				for transport:Dictionary in app.core.view.littoral.transports:
					if str(transport.get("company_id",""))==str(selected.company_id):transport_gap=minf(transport_gap,Vector2(float(row.x),float(row.y)).distance_to(Vector2(float(transport.x),float(transport.y))))
				landing_samples.append({"tick":app.core.view.tick,"id":row.id,"phase":row.get("phase"),"transport_gap_m":transport_gap,"x":row.x,"y":row.y,"deployment_origin":row.get("deployment_origin"),"first_visible":row.get("first_visible"),"first_visible_frame":row.get("first_visible_frame")})
		if ashore and landed_ids.size()>=expected_count:break
	check(not landing_samples.is_empty(),"native selected company truly unloads before movement review")
	battle.selected_unit=str(selected.company_id);battle.update();map.selected_unit=str(selected.company_id);map.zoom=1;map.focus_selected()
	if not landing_samples.is_empty():map.camera_center=Vector2(float(landing_samples[0].x),float(landing_samples[0].y))+Vector2(6,5)
	map.zoom=18;map._camera_updated();await frames(3)
	var world=map.world3d
	var serialized:Dictionary=app.core.request({"op":"save","serialized":true})
	FileAccess.open(OUT+"landed-native-save-response.json",FileAccess.WRITE).store_string(JSON.stringify(serialized))
	check(world.actors.size()>0,"native bodies consumed by real renderer")
	await capture("main-landed-before-continuous")
	app.speed=1;app.running=true;battle.update()
	var started:int=Time.get_ticks_msec();var next_image:int=0
	while Time.get_ticks_msec()-started<6500:
		await process_frame
		record_native_speeds(app.core.view)
		var moving:int=0
		for record:Dictionary in world.actors.values():
			if record.model!=null:
				if is_instance_valid(record.get("flash")) and record.flash.visible and not captured_shots.has(str(record.get("shot_id",-1))):
					captured_shots[str(record.shot_id)]=true
					vehicle_fire_samples.append({"operator_id":record.row.id,"shot":record.get("last_visible_shot",{}),"model":record.model_id,"node":str(record.node.position),"flash":str(record.flash.position)})
					if DisplayServer.get_name()!="headless":
						await RenderingServer.frame_post_draw
						var path:String=OUT+"actual-main-vehicle-shot-%d.png"%int(record.shot_id);root.get_texture().get_image().save_png(path);images.append(ProjectSettings.globalize_path(path))
				continue
			if not record.node.visible or float(record.row.get("hp",0))<=0:continue
			if bool(record.get("moving",false)):
				moving+=1;live_walk_frames+=1
				var direction:Vector2=record.direction;var at:Vector3=record.node.position
				var dx:float=(world.camera.unproject_position(at+Vector3(direction.x,0,direction.y))-world.camera.unproject_position(at)).x
				if dx*( -1 if record.sprite.flip_h else 1)<-.00001:direction_failures+=1
		var elapsed:int=Time.get_ticks_msec()-started
		samples.append({"wall_ms":elapsed,"tick":app.core.view.tick,"moving_bodies":moving})
		if elapsed>=next_image:
			await capture("live-%02d"%(next_image/1000));next_image+=1000
	app.running=false;battle.update();await frames(2)
	check(live_walk_frames>0 or lesson_key=="combined_arms","continuous real Main playback contains moving own bodies or independent stationary tank")
	check(direction_failures==0,"all live walk facings agree with camera-projected native motion")
	check(not native_speed_samples.is_empty(),"actual phase-stable disembarked bodies supply measured motion")
	var max_speed:float=native_speed_samples.max() if not native_speed_samples.is_empty() else 0.0
	check(max_speed<=4.0,"actual stable infantry displacement stays below 4m/s including modest buffs")
	FileAccess.open(OUT+"actual-main-observation.json",FileAccess.WRITE).store_string(JSON.stringify(app.core.view))
	# Isolated display fixture: never sends a forged body/state into the core.
	var native:Dictionary=map.land.duplicate(true)
	var fixture:Control=spawn_renderer_fixture()
	fixture.observe(native,false);fixture.set_camera(Vector2(float(beach.x),float(beach.y)),8)
	await frames(2)
	await direction_and_motion_fixture(fixture,native,Vector2(float(beach.x),float(beach.y)))
	await corpse_fixture(fixture,native)
	await vehicle_weapon_fixture(fixture,native)
	fixture.get_parent().queue_free();await frames(2)
	finish()
func spawn_renderer_fixture()->Control:
	var layer:=CanvasLayer.new();layer.name="IsolatedRendererFixture";layer.layer=80;root.add_child(layer)
	var fixture:Control=load("res://scripts/world3d/world3d_view.gd").new();fixture.name="RendererFixtureOnly";layer.add_child(fixture);fixture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return fixture
func record_native_speeds(view:Dictionary)->void:
	var tick:float=float(view.get("tick",0));var elapsed:float=tick-previous_native_tick
	if elapsed<=.00001:return
	var next:Dictionary={}
	for row:Dictionary in view.get("littoral",{}).get("land",{}).get("entities",[]):
		if not str(row.get("vehicle_kind","")).is_empty():continue
		var id:String=str(row.get("id",0));next[id]=row
		if not previous_native_rows.has(id) or elapsed>.8 or previous_native_tick<0:continue
		var old:Dictionary=previous_native_rows[id]
		if str(row.get("phase",""))!="active" or str(old.get("phase",""))!="active" or bool(row.get("seated",false)) or bool(old.get("seated",false)):continue
		if row.get("in_vehicle")!=null or old.get("in_vehicle")!=null or row.get("carried_by")!=null or old.get("carried_by")!=null:continue
		if row.get("knockback")!=null or old.get("knockback")!=null or float(row.get("hp",0))<=0 or float(old.get("hp",0))<=0:continue
		if row.get("first_visible_frame")!=null and tick-float(row.first_visible_frame)*.1<1.0:continue
		var distance:float=Vector2(float(row.x)-float(old.x),float(row.y)-float(old.y)).length();var speed:float=distance/elapsed
		var velocity:Dictionary=row.get("velocity",{}) if row.get("velocity") is Dictionary else {}
		public_velocity_max=maxf(public_velocity_max,Vector2(float(velocity.get("x",0)),float(velocity.get("y",0))).length())
		native_speed_samples.append(speed)
		if speed>3.0:native_speed_worst.append({"tick":tick,"id":row.id,"unit":row.get("unit_id"),"side":row.get("side"),"speed_mps":speed,"displacement_m":distance,"native_elapsed_s":elapsed,"velocity":velocity})
	previous_native_rows=next;previous_native_tick=tick
func body(id:int,at:Vector2,hp:float=440)->Dictionary:
	return {"id":id,"unit_id":"MCP-034","company_id":"MCP-034-C01","x":at.x,"y":at.y,"hp":hp,"max_hp":440,"side":"allies","phase":"active","velocity":{"x":0,"y":0},"kind":"marine","ready_in":4.0}
func fixture_value(native:Dictionary,rows:Array,tick:float)->Dictionary:
	var value:Dictionary=native.duplicate();value["entities"]=rows;value["corpses"]=[];value["transports"]=[];value["shots"]=[];value["tick"]=tick;return value
func direction_and_motion_fixture(world:Control,native:Dictionary,at:Vector2)->void:
	world.set_process(false)
	var tick:float=100
	for direction:Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,1),Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1)]:
		var first:Dictionary=fixture_value(native,[body(9000,at)],tick);world.observe(first,false);world.observe(first,true)
		var destination:Vector2=at+direction.normalized()*.8
		var next:Dictionary=fixture_value(native,[body(9000,destination)],tick+.1);world.observe(next,true)
		var record:Dictionary=world.actors["entity:9000"]
		var before:Vector3=record.node.position;world._process(.025)
		var quarter:Vector3=record.node.position
		world.observe(next,true);world._process(.025)
		var half:Vector3=record.node.position;world._process(.025)
		var third:Vector3=record.node.position;world._process(.025)
		var target:Vector3=record.node.position
		var delta_a:float=Vector2(quarter.x-before.x,quarter.z-before.z).length()
		var delta_b:float=Vector2(half.x-quarter.x,half.z-quarter.z).length()
		var delta_c:float=Vector2(third.x-half.x,third.z-half.z).length()
		check(absf(delta_a-delta_b)<.002 and absf(delta_a-delta_c)<.002,"constant measured between-sample speed "+str(direction))
		check(target.distance_to(record.target)<.001,"interpolation reaches exact actual sample "+str(direction))
		check(str(record.state)=="walk","reload timer cannot override locomotion "+str(direction))
		var dx:float=(world.camera.unproject_position(target)-world.camera.unproject_position(before)).x
		check(dx*(-1 if record.sprite.flip_h else 1)>=0,"projected face matches travel "+str(direction))
		var old_clock:float=world._clock;world.observe(next,false);world._process(.1)
		check(is_equal_approx(old_clock,world._clock) and record.node.position.distance_to(record.target)<.001,"pause snaps correctly and freezes clock")
		tick+=1;fixture_checks+=5
	var row:Dictionary=body(9000,at);world.observe(fixture_value(native,[row],200),true)
	row=body(9000,at+Vector2(4,3));row.phase="aboard";row.seated=true
	world.observe(fixture_value(native,[row],200.1),true)
	check(not world.actors["entity:9000"].node.visible,"embarked body hidden at authoritative carrier position")
	row=body(9000,at+Vector2(8,5));world.observe(fixture_value(native,[row],200.2),true)
	check(world.actors["entity:9000"].node.position.distance_to(world.surface.world(at+Vector2(8,5)))<.001,"redeploy snaps without sweeping across shore")
	world.observe(fixture_value(native,[body(9000,at)],90),true)
	check(world.actors["entity:9000"].node.position.distance_to(world.surface.world(at))<.001,"seek backwards resets interpolator")
func corpse_fixture(world:Control,native:Dictionary)->void:
	var grid=world.surface.native_grid
	var slope:Vector2=world.surface.origin
	for index:int in range(grid.heights.size()):
		var x:int=index%grid.columns;var y:int=floori(float(index)/grid.columns)
		if x<3 or y<3 or x>=grid.columns-3 or y>=grid.rows-3:continue
		if grid.heights[index]>5 and grid.heights[index]<28 and grid.normal_at(x,y).y>.78 and grid.normal_at(x,y).y<.95:
			slope=grid.origin+Vector2(x,y)*grid.cell_size;break
	var rows:Array=[]
	for i:int in range(9):rows.append(body(9100+i,slope+Vector2((i%3-1)*4,(floori(float(i)/3)-1)*4),0))
	rows.append(body(9200,slope+Vector2(-8,0)))
	var tank:Dictionary=body(9300,slope+Vector2(6,0));tank["vehicle_kind"]="tank";tank["heading"]=40;rows.append(tank)
	world.observe(fixture_value(native,rows,300),false);world.set_camera(slope,18)
	for record:Dictionary in world.actors.values():
		if not is_instance_valid(record.get("fallen")):continue
		var fallen:Sprite3D=record.fallen
		check(not fallen.no_depth_test,"corpse retains building/hill occlusion")
		check(fallen.texture!=null and fallen.region_enabled,"fallen keep the authored 2D defeat frame")
		var half:Vector2=fallen.region_rect.size*fallen.pixel_size*.5
		var lean:float=deg_to_rad(62.0)
		for corner:Vector2 in [Vector2(-half.x,-half.y),Vector2(half.x,-half.y),Vector2(-half.x,half.y),Vector2(half.x,half.y)]:
			var local:Vector3=fallen.global_transform.basis*Vector3(corner.x,corner.y,0)+fallen.position
			var actual:Vector3=record.node.global_position+local
			maximum_fallen_penetration=maxf(maximum_fallen_penetration,world.surface.surface_at(Vector2(actual.x,actual.z)+world.surface.origin)-actual.y)
		var head:Vector3=record.node.global_position+fallen.global_transform.basis*Vector3(0,half.y*2.,0)+fallen.position
		check(head.y>record.node.global_position.y,"lying 2D corpse leans back above the ground, not into it")
	check(maximum_fallen_penetration<.001,"every lying 2D corpse corner stays above the real slope")
	await capture("renderer-fixture-slope-corpses-and-tank")
	world.set_camera(slope,28);await capture("renderer-fixture-slope-close")
func vehicle_weapon_fixture(world:Control,native:Dictionary)->void:
	var at:Vector2=world.surface.origin
	var row:Dictionary=body(9400,at);row["vehicle_kind"]="tank";row["heading"]=90
	var sample:Dictionary=fixture_value(native,[row],400)
	world.observe(sample,false);world.set_camera(at,24)
	var record:Dictionary=world.actors["entity:9400"]
	check(record.get("flash")==null,"vehicle reload/ready timer cannot fabricate muzzle flash")
	sample["tick"]=400.1;sample["shots"]=[{"id":79000,"operator_id":9400,"source":"MCP-034-C01","tick":400.1,"kind":"tank","weapon_id":"fixture-only","target_x":at.x+40,"target_y":at.y+10}]
	world.observe(sample,true)
	check(is_instance_valid(record.flash) and record.flash.visible,"published individual vehicle shot alone triggers flash")
	world._process(.02);world._process(.04)
	check(record.turret.position.distance_to(record.turret_rest)>.03,"actual gun assembly recoils independent of native body anchor")
	check(record.node.position.distance_to(record.target)<.001,"weapon recoil cannot move vehicle selection/physics anchor")
	await capture("renderer-fixture-tank-real-shot-contract")
	world._process(.3)
	check(not record.flash.visible and record.turret.position.distance_to(record.turret_rest)<.001,"short muzzle flash/recoil recover automatically")
	var age:float=record.weapon_age;world.observe(sample,true)
	check(record.weapon_age==age,"duplicate observation cannot retrigger same vehicle shot")
func finish()->void:
	for name in normal_hashes:check(FileAccess.get_sha256("user://"+str(name))==normal_hashes[name],"normal profile unchanged "+str(name))
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixture_checks":fixture_checks,"live_walk_frames":live_walk_frames,"direction_failures":direction_failures,"maximum_fallen_penetration_m":maximum_fallen_penetration,"body_height_m":2.2,"vehicle_scale":1,"input_events":input_events,"images":images,"continuous_main_samples":samples,"landing_samples":landing_samples,"vehicle_fire_samples":vehicle_fire_samples,"core_path":OS.get_environment("CAS_SIM_PATH"),"core_sha256":FileAccess.get_sha256(OS.get_environment("CAS_SIM_PATH")),"fixture_note":"Only renderer fixtures after actual native gameplay; never submitted to core or normal profile","gpu":DisplayServer.get_name()!="headless"}
	var sorted:Array[float]=native_speed_samples.duplicate();sorted.sort()
	report["native_infantry_speed"]={"count":sorted.size(),"median_mps":sorted[sorted.size()/2] if not sorted.is_empty() else 0,"p95_mps":sorted[mini(sorted.size()-1,int(sorted.size()*.95))] if not sorted.is_empty() else 0,"max_mps":sorted[-1] if not sorted.is_empty() else 0,"public_velocity_max_mps":public_velocity_max,"above_3mps":native_speed_worst,"selection":"native positions per native tick; stable active phase, alive, unseated, no vehicle/knockback, at least 1s since first visibility"}
	FileAccess.open(OUT+("fixture-report.json" if OS.get_environment("CAS_MOTION_FIXTURE_ONLY")=="1" else "motion-report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	var summary:Dictionary=report.duplicate();summary["continuous_main_samples"]=samples.size();print("COASTAL_MOTION_REVIEW ",JSON.stringify(summary))
	if is_instance_valid(app):app.core.close();app.queue_free()
	await frames(2);quit(0 if failures.is_empty() else 1)
