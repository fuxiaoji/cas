extends "res://tests/littoral_drag_v2_review.gd"
## Real public save and production pointer input; no edited body/vehicle state.
const CONTROLS=preload("res://scripts/tactical_vehicle_controls_v3.gd")
var account
var samples:Array=[]
func run()->void:
	output_dir="res://../artifacts/island-war-v4/presentation/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	account=load("res://scripts/economy.gd").new(output_dir+"controls-isolated-%d.json"%OS.get_process_id());account.new_profile();account.state.progression.first_voyage_canon.active=false
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.deferred_startup=false;app.staged_navigation=false;app.immersive_fullscreen=false
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1600,900);root.add_child(app);await frames(6);app.page_motion=false;app.page_transition.cancel();app.set_process(false);AudioServer.set_bus_mute(0,true)
	app.home.development();app.show_page("home");await frames()
	var owned:Dictionary=account.state.duplicate(true);var disk:String=FileAccess.get_sha256(account.save_path)
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../artifacts/island-war-v3/core/actual-tank-rear-cover.json"))
	await app.launch_home_exercise(fixture.initial_request);await frames();controller().tutorial.close_help()
	check(app.home_exercise_session.active,"real borrowed battle entered")
	for map_name in ["sea","land"]:
		controller().set_primary_map(map_name);await frames()
		app.core.request({"op":"island_autonomy","version":"cas-island-war-v3","enabled":false});app.update_battle();await frames()
		await click(controller().autonomy_button)
		check(bool(app.core.view.littoral.autonomy.enabled),"production header enables actual autonomy on "+map_name)
		check(app.running,"one-click starts simulation on "+map_name)
		await shot("header-autonomy-"+map_name)
		await click(controller().autonomy_button)
		check(not bool(app.core.view.littoral.autonomy.enabled),"production header returns control on "+map_name)
	check(app.core.request({"op":"load","serialized":str(fixture.serialized)}).get("ok",false),"real cover save loaded without modifying observations")
	app.core.request({"op":"island_autonomy","version":"cas-island-war-v3","enabled":false});app.running=false;controller().set_primary_map("land");app.update_battle();await frames()
	var vehicle:Dictionary={}
	for row in app.core.view.littoral.land.combat_vehicles:
		if str(row.get("unit_id",""))=="MCP-022" and str(row.phase)=="active":vehicle=row;break
	if check(not vehicle.is_empty(),"actual independent tank available"):
		var company:String=str(vehicle.company_id);controller().selected_unit=company;controller().roster_signature="";app.update_battle()
		var map=controller().ui.get_node("LandWindow/Map");map.camera_center=Vector2(float(vehicle.x),float(vehicle.y))
		var previous:float=-1
		for scale in [1,2,4,8,12,18,25,40]:
			map.zoom=scale;map._camera_updated();await frames()
			var height:float=map._body_height(true,true)
			check(height+0.001>=previous,"SD visible height does not shrink at zoom "+str(scale));previous=height
			samples.append({"zoom":scale,"body_px":height,"tank_px":map.actors[int(vehicle.id)].display_height*2.1,"world_m_to_px":map._screen_scale()})
		map.zoom=18;map.camera_center=Vector2(float(vehicle.x),float(vehicle.y));map._camera_updated();await frames()
		controller().interaction_event.connect(func(kind,data):events.append({"kind":kind,"data":data.duplicate(true)}))
		var body:Dictionary={}
		for row in app.core.view.littoral.land.entities:
			if str(row.get("company_id",""))==company and not row.has("vehicle_kind") and float(row.get("hp",0))>0:body=row;break
		if check(not body.is_empty(),"real independent infantry available"):
			var target:Vector2=legal_point(Vector2(float(body.x),float(body.y)),map,75)
			var pan_before:Vector2=map.camera_center
			print("BODY_DRAG "+JSON.stringify({"origin":map.actor_hit_point(int(body.id)),"target":map.project(target),"map":map.get_global_rect(),"camera":map.camera_center,"body":body.get("id"),"hit":map.target_at(map.actor_hit_point(int(body.id))).get("id")}))
			await pointer_drag(global_point(map,map.actor_hit_point(int(body.id))),world(target),true)
			print("BODY_EVENTS "+JSON.stringify(events.map(func(e):return {"kind":e.kind,"accepted":e.data.get("accepted"),"reason":e.data.get("reason")})))
			check(event_seen("unit_ordered"),"dragging the actual SD issues a real company order")
			check(map.camera_center.distance_to(pan_before)<.01,"unit drag does not pan the map")
			check(not map.camera_pointer_down and not map.actor_pointer_armed,"map pointer state released after unit drag")
			events.clear()
		var start:=Vector2(float(vehicle.x),float(vehicle.y));var destination:Vector2=legal_point(start,map,100)
		await pointer_drag(global_point(map,map.actor_hit_point(int(vehicle.id))),world(destination),false)
		print("TANK_EVENTS "+JSON.stringify(events.map(func(e):return {"kind":e.kind,"accepted":e.data.get("accepted"),"reason":e.data.get("reason")})))
		check(event_seen("vehicle_move_ordered"),"dragging the actual tank issues an independent vehicle order")
		if app.running:await click(app.pause_button)
		await advance(1)
		var after:Dictionary=CONTROLS.find(controller(),int(vehicle.id))
		check(Vector2(float(after.x),float(after.y)).distance_to(start)>1,"drag command actually moves the native tank")
		await shot("actual-map-unit-and-tank-drag")
		await review_gestures(map,int(vehicle.id))
		controller().replay_mode=true;app.update_battle();await frames()
		check(controller().autonomy_button.disabled and not map.actor_commands_enabled,"replay keeps commands disabled")
		controller().replay_mode=false
	app.close_home_exercise();await frames()
	check(account.state==owned and FileAccess.get_sha256(account.save_path)==disk,"borrowed controls review preserves account and disk")
	check(FileAccess.get_sha256("user://cas_port_v1.json")==main_hash and FileAccess.get_sha256("user://cas_port_v1.json.bak")==backup_hash,"formal account files unchanged")
	var report:Dictionary={"ok":failures.is_empty(),"checks":checks,"failures":failures,"inputs":inputs,"zoom_samples":samples,"scope":"Actual old v3 public save, production sea/land header mouse commands, map SD touch drag, independent tank drag, monotonic SD zoom and read-only replay. New v4 rules validated separately."}
	FileAccess.open(output_dir+"controls-receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify(report));app.queue_free();quit(0 if failures.is_empty() else 1)
func review_gestures(map,vehicle_id:int)->void:
	var blank:=Vector2(170,140)
	for x in [170,400,650,850]:
		var candidate:=Vector2(x,140)
		if map.target_at(candidate).is_empty():blank=candidate;break
	var camera_before:Vector2=map.camera_center
	events.clear()
	await pointer_drag(global_point(map,blank),global_point(map,blank+Vector2(65,35)),false)
	check(map.camera_center.distance_to(camera_before)>1,"empty map mouse drag still pans after actor commands")
	check(not event_seen("unit_ordered") and not event_seen("vehicle_move_ordered"),"camera pan does not command a unit")
	var at:Vector2=screen_point(global_point(map,blank));var zoom_before:float=map.zoom
	var anchor_before:Vector2=map.unproject_base(blank)
	var wheel:=InputEventMouseButton.new();wheel.position=at;wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.pressed=true;Input.parse_input_event(wheel);inputs+=1;await frames()
	check(map.zoom>zoom_before and map.unproject_base(blank).distance_to(anchor_before)<.01,"real wheel zoom preserves its world anchor")
	# Begin on a commandable tank, start a drag, then add a second finger.
	# The gesture must cancel the command before becoming a map pinch.
	var vehicle:Dictionary=CONTROLS.find(controller(),vehicle_id)
	map.camera_center=Vector2(float(vehicle.x),float(vehicle.y))
	map._camera_updated();await frames()
	var first:Vector2=map.actor_hit_point(vehicle_id);var moved:Vector2=first+Vector2(35,0)
	await touch_at(map,3,first,true)
	await touch_move(map,3,moved,Vector2(35,0))
	check(map.actor_pointer_armed and controller().drag_layer.dragging,"actual tank touch arms a map command before pinch")
	var second:Vector2=moved+Vector2(100,0);zoom_before=map.zoom
	await touch_at(map,5,second,true)
	check(not map.actor_pointer_armed and controller().drag_layer.payload.is_empty(),"second finger cancels the pending actor command")
	await touch_move(map,5,second+Vector2(70,0),Vector2(70,0))
	check(map.zoom>zoom_before,"two-finger input zooms the map after cancelling actor drag")
	await touch_at(map,5,second+Vector2(70,0),false)
	await touch_at(map,3,moved,false)
	check(map.camera_touch_points.is_empty() and not map.camera_pointer_down,"pinch releases every map pointer")
	check(not event_seen("unit_ordered") and not event_seen("vehicle_move_ordered"),"pinch cannot accidentally order a unit")
func touch_at(map,index:int,local:Vector2,pressed:bool)->void:
	var touch:=InputEventScreenTouch.new();touch.index=index;touch.position=screen_point(global_point(map,local));touch.pressed=pressed;Input.parse_input_event(touch);inputs+=1;await frames()
func touch_move(map,index:int,local:Vector2,relative:Vector2)->void:
	var touch:=InputEventScreenDrag.new();touch.index=index;touch.position=screen_point(global_point(map,local));touch.relative=relative;Input.parse_input_event(touch);inputs+=1;await frames()
func legal_point(origin:Vector2,map,distance:float)->Vector2:
	for offset in [Vector2(distance,0),Vector2(-distance,0),Vector2(0,distance),Vector2(0,-distance)]:
		var candidate:Vector2=origin+offset
		if controller()._island_contains(candidate) and not controller()._ground_blocked(candidate) and map.target_at(map.project(candidate)).is_empty():return candidate
	return origin+Vector2(distance,0)
func pointer_drag(from:Vector2,to:Vector2,touch:bool)->void:
	var start:Vector2=screen_point(from);var end:Vector2=screen_point(to)
	if touch:
		var down:=InputEventScreenTouch.new();down.index=2;down.position=start;down.pressed=true;Input.parse_input_event(down)
	else:
		var down:=InputEventMouseButton.new();down.position=start;down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;Input.parse_input_event(down)
	inputs+=1;await process_frame
	for i in range(1,9):
		var at:Vector2=start.lerp(end,float(i)/8)
		if touch:
			var move:=InputEventScreenDrag.new();move.index=2;move.position=at;move.relative=(end-start)/8;Input.parse_input_event(move)
		else:
			var move:=InputEventMouseMotion.new();move.position=at;move.relative=(end-start)/8;move.button_mask=MOUSE_BUTTON_MASK_LEFT;Input.parse_input_event(move)
		inputs+=1;await process_frame
	if touch:
		var up:=InputEventScreenTouch.new();up.index=2;up.position=end;Input.parse_input_event(up)
	else:
		var up:=InputEventMouseButton.new();up.position=end;up.button_index=MOUSE_BUTTON_LEFT;Input.parse_input_event(up)
	inputs+=1;await frames()
