extends "res://tests/island_v4_controls_review.gd"
## A real command-replayed casualty save. No observation or health is edited.
func run()->void:
	output_dir="res://../artifacts/island-war-v4/presentation/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	account=load("res://scripts/economy.gd").new(output_dir+"bodyless-isolated-%d.json"%OS.get_process_id());account.new_profile();account.state.progression.first_voyage_canon.active=false
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.deferred_startup=false;app.staged_navigation=false;app.immersive_fullscreen=false
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1600,900);root.add_child(app);await frames(6);app.page_motion=false;app.page_transition.cancel();app.set_process(false);AudioServer.set_bus_mute(0,true)
	app.home.development();app.show_page("home");await frames()
	var owned:Dictionary=account.state.duplicate(true);var disk:String=FileAccess.get_sha256(account.save_path)
	var snapshot:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../artifacts/island-war-v4/core/022-bodyless-snapshot.json"))
	var request:Dictionary=snapshot.config.duplicate(true);request["op"]="new_island_battle";request["version"]=snapshot.version;request["seed"]=snapshot.seed
	await app.launch_home_exercise(request);await frames();controller().tutorial.close_help()
	check(app.home_exercise_session.active,"production v4 borrowed exercise opened")
	check(not app.running,"new battle opens safely paused with its actual native autonomy state")
	await click(controller().autonomy_button)
	check(bool(app.core.view.littoral.autonomy.enabled) and app.running,"one actual click enables and starts native autonomy")
	await click(controller().naval_pause)
	check(bool(app.core.view.littoral.autonomy.enabled) and not app.running,"actual pause preserves the enabled native plan")
	await click(controller().autonomy_button)
	check(bool(app.core.view.littoral.autonomy.enabled) and app.running,"one actual click resumes a paused plan without turning it off")
	var loaded:Dictionary=app.core.request({"op":"load","save":snapshot})
	check(bool(loaded.get("ok",false)),"actual casualty command replay loads "+str(loaded.get("error","")))
	app.running=false;controller().set_primary_map("land");app.update_battle();await frames()
	var tank:Dictionary={}
	for row in app.core.view.littoral.land.combat_vehicles:
		if str(row.get("unit_id",""))=="MCP-022" and str(row.phase)=="active" and float(row.hp)>0:tank=row;break
	if check(not tank.is_empty(),"native tank survives infantry losses"):
		var company:String=str(tank.company_id)
		check(app.core.view.littoral.land.entities.filter(func(row):return str(row.get("company_id",""))==company and not row.has("vehicle_kind") and float(row.get("hp",0))>0).is_empty(),"every body in this tank company is truly dead")
		controller().selected_unit=company;controller().roster_signature="";app.update_battle();await frames()
		var vehicle_card:Control=card("Vehicle_"+company)
		check(is_instance_valid(vehicle_card) and vehicle_card.enabled,"surviving tank replaces the dead-body tray card and is enabled")
		var map=controller().ui.get_node("LandWindow/Map");var start:=Vector2(float(tank.x),float(tank.y));map.camera_center=start;map.zoom=12;map._camera_updated();await frames()
		var persistent_count:int=0
		for corpse in map.land.get("corpses",[]):
			var key:int=int(corpse.id);var death_tick:float=float(corpse.death_tick)
			if not map.actors.has(key) or float(map.land.tick)-death_tick<.5:continue
			persistent_count+=1
			check(absf(map.actors[key].defeated_at-death_tick)<.001 and map.actors[key].frame_index==11,"loaded casualty keeps its real death time and settled pose "+str(key))
		check(persistent_count>0,"real casualty save includes settled fallen bodies")
		check(str(map.land.get("equipment_version",""))=="tactical-vehicles-v4","renderer consumes the real v4 equipment version")
		check(map.actors.has(int(tank.id)) and map.actors[int(tank.id)].visible,"independent surviving tank is rendered at its public entity")
		controller().interaction_event.connect(func(kind,data):events.append({"kind":kind,"data":data.duplicate(true)}))
		var point:Vector2=legal_point(start,map,100)
		await pointer_drag(global_point(map,map.actor_hit_point(int(tank.id))),world(point),false)
		check(event_seen("vehicle_face_ordered"),"direct tank drag issues a native fire-direction order")
		var face_start:Dictionary=CONTROLS.find(controller(),int(tank.id));await advance(1)
		var faced:Dictionary=CONTROLS.find(controller(),int(tank.id))
		check(Vector2(float(faced.x),float(faced.y)).distance_to(Vector2(float(face_start.x),float(face_start.y)))<.1,"fire-direction order turns the tank without driving it")
		events.clear();point=legal_point(start,map,160)
		await drag(vehicle_card,world(point))
		check(event_seen("vehicle_move_ordered"),"bodyless tank tray card still orders independent movement")
		await advance(2)
		var moved:Dictionary=CONTROLS.find(controller(),int(tank.id))
		check(Vector2(float(moved.x),float(moved.y)).distance_to(start)>10,"bodyless tank really moves after a tray command")
		await shot("v4-bodyless-tank-command")
		for map_name in ["land","sea"]:
			controller().set_primary_map(map_name);await frames()
			app.core.request({"op":"island_autonomy","version":"cas-island-war-v4","enabled":false});app.update_battle();await frames()
			await click(controller().autonomy_button)
			print("AUTONOMY_INPUT "+JSON.stringify({"map":map_name,"enabled":app.core.view.littoral.autonomy.enabled,"button":controller().autonomy_button.get_global_rect(),"disabled":controller().autonomy_button.disabled,"hovered":str(root.gui_get_hovered_control().get_path()) if root.gui_get_hovered_control()!=null else "","parent":str(controller().autonomy_button.get_parent().get_path()),"result":app.core.view.get("result")}))
			await shot("v4-bodyless-autonomy-"+map_name)
			check(bool(app.core.view.littoral.autonomy.enabled),"real v4 one-click autonomy works on "+map_name)
			await click(controller().autonomy_button)
			check(not bool(app.core.view.littoral.autonomy.enabled),"v4 manual takeover works on "+map_name)
	app.close_home_exercise();await frames()
	await review_default_cover()
	app.close_home_exercise();await frames()
	check(account.state==owned and FileAccess.get_sha256(account.save_path)==disk,"isolated borrowed exercise preserves account and disk")
	check(FileAccess.get_sha256("user://cas_port_v1.json")==main_hash and FileAccess.get_sha256("user://cas_port_v1.json.bak")==backup_hash,"formal account remains unchanged")
	var report:Dictionary={"ok":failures.is_empty(),"checks":checks,"failures":failures,"inputs":inputs,"native_path":OS.get_environment("CAS_SIM_PATH"),"scope":"Production v4 exercise, real public-command replay of all-six-body loss with living tank, persistent death timing; actual direct-map fire-direction drag, tray movement, sea/land autonomy buttons; all 74 live bodies and independent vehicles at true native centers during default manual cover. No edited damage, positions or observation fixture."}
	FileAccess.open(output_dir+"bodyless-receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify(report));app.queue_free();quit(0 if failures.is_empty() else 1)
func review_default_cover()->void:
	var snapshot:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../artifacts/island-war-v4/core/manual-default-cover-snapshot.json"))
	var request:Dictionary=snapshot.config.duplicate(true);request["op"]="new_island_battle";request["version"]=snapshot.version;request["seed"]=snapshot.seed
	await app.launch_home_exercise(request);await frames();controller().tutorial.close_help()
	check(bool(app.core.request({"op":"load","save":snapshot}).get("ok",false)),"actual manual default-cover save replays")
	app.running=false;controller().set_primary_map("land");app.update_battle();await frames()
	check(not bool(app.core.view.littoral.autonomy.enabled),"armored infantry cover works while total autonomy is off")
	var map=controller().ui.get_node("LandWindow/Map")
	for id in ["MCP-022","MCP-103","MCP-304","MCP-305"]:
		var vehicle:Dictionary={}
		for row in CONTROLS.rows(controller()):
			if str(row.get("unit_id",""))==id and float(row.get("hp",0))>0:vehicle=row;break
		if not check(not vehicle.is_empty(),"actual independent armored vehicle "+id):continue
		var bodies:Array=app.core.view.littoral.land.entities.filter(func(row):return str(row.get("unit_id",""))==id and not row.has("vehicle_kind") and float(row.get("hp",0))>0)
		check(bodies.any(func(body):return int(body.get("cover_vehicle_id",-1))==int(vehicle.id)),"native bodies automatically use their actual vehicle for cover "+id)
		controller().selected_unit=str(vehicle.company_id);controller().roster_signature="";app.update_battle();await frames()
		map.camera_center=Vector2(float(vehicle.x),float(vehicle.y));map.zoom=25;map._camera_updated();await frames()
		check(map.actors.has(int(vehicle.id)) and map.actors[int(vehicle.id)].position.distance_to(map.project(Vector2(float(vehicle.x),float(vehicle.y))))<.1,"rendered vehicle center matches native position "+id)
		for body in bodies:
			if not map.actors.has(int(body.id)):continue
			check(map.actors[int(body.id)].position.distance_to(map.project(Vector2(float(body.x),float(body.y))))<.1,"rendered body feet match native independent center %s/%s"%[id,body.id])
		await shot("v4-manual-cover-"+id.to_lower())
		if id=="MCP-304":
			var origin:=Vector2(float(vehicle.x),float(vehicle.y));var nearest:=Vector2.ZERO;var gap:float=INF
			for building in map.land.get("town",{}).get("buildings",[]):
				var footprint:PackedVector2Array=load("res://scripts/procedural_amphibious_terrain.gd").points(building.get("footprint",[]))
				if footprint.is_empty():continue
				var center:=Vector2.ZERO
				for p in footprint:center+=p
				center/=footprint.size()
				if origin.distance_to(center)<gap:gap=origin.distance_to(center);nearest=center
			map.camera_center=(origin+nearest)*.5;map.zoom=9;map._camera_updated();await frames();await shot("v4-people-vehicle-building-scale")
	map.reset_camera();await frames();await shot("v4-terrain-overview")
	var pictured:Dictionary={}
	for feature in map.land.get("terrain",{}).get("features",[]):
		if str(feature.get("kind","")) not in ["highland","ford"] or pictured.has(str(feature.kind)):continue
		var polygon:PackedVector2Array=load("res://scripts/procedural_amphibious_terrain.gd").points(feature.get("polygon",[]));var center:=Vector2.ZERO
		for point in polygon:center+=point
		center/=maxi(1,polygon.size());map.camera_center=center;map.zoom=7;map._camera_updated();await frames();await shot("v4-terrain-"+str(feature.kind));pictured[str(feature.kind)]=true
