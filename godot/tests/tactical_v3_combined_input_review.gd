extends "res://tests/littoral_drag_v2_review.gd"
## Production pointer actions over actual loan battles. No edited seats, HP,
## vehicle positions or observations stand in for a native action.
const CONTROLS=preload("res://scripts/tactical_vehicle_controls_v3.gd")
var account
func run()->void:
	output_dir="res://../artifacts/island-war-v3/presentation/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	account=load("res://scripts/economy.gd").new(output_dir+"combined-input-isolated-%d.json"%OS.get_process_id());account.new_profile();account.state.progression.first_voyage_canon.active=false
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.deferred_startup=false;app.staged_navigation=false;app.immersive_fullscreen=false
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1600,900);root.add_child(app);await frames(6);app.page_motion=false;app.page_transition.cancel();app.set_process(false);AudioServer.set_bus_mute(0,true)
	app.home.development();app.show_page("home");await frames()
	var owned:Dictionary=account.state.duplicate(true);var disk:String=FileAccess.get_sha256(account.save_path)
	var lesson:Dictionary=load("res://scripts/canon_tactical_v3.gd").request("combined_arms")
	if not check(lesson.get("ok",false),"actual exported vehicle loan lesson"):return finish_combined()
	for identity in ["MCP-022","MCP-103","MCP-087","MCP-027","MCP-006"]:
		await app.launch_home_exercise(lesson.request);await frames()
		if not check(app.home_exercise_session.active,"real isolated combined battle "+identity):continue
		controller().tutorial.close_help();events.clear();controller().interaction_event.connect(func(kind,data):events.append({"kind":kind,"data":data.duplicate(true),"tick":app.core.view.tick}))
		if app.running:await click(app.pause_button)
		check(not app.running,"production pause precedes native manual-step review "+identity)
		var selected:Dictionary={}
		for row in app.core.view.littoral.groups:
			if str(row.get("unit_id",""))==identity:selected=row;break
		if not check(not selected.is_empty(),"actual company "+identity):app.close_home_exercise();continue
		var company:String=str(selected.id);controller().selected_unit=company;controller().roster_signature="";app.update_battle();await frames()
		var beach:Dictionary=app.core.view.littoral.beaches[1];var landing:=Vector2(float(beach.land.x),float(beach.land.y))
		var unit:Control=card("Unit_"+company);await reveal(unit)
		await drag(unit,world(landing),true)
		if not check(event_seen("deploy_queued"),"real touch drag deploys fixed transport "+identity):app.close_home_exercise();continue
		var landed:bool=false
		for i in range(150):
			var response:Dictionary=app.core.request({"op":"step","seconds":.5})
			if not response.get("ok",false):check(false,"actual deployment step "+identity);break
			app.update_battle();await process_frame
			if str(find_group(company).get("stage",""))=="ground" and str(CONTROLS.own(controller(),company).get("phase",""))=="active":landed=true;break
		if not check(landed,"actual landing creates independent vehicle "+identity):app.close_home_exercise();await frames();continue
		await pause_for_steps()
		controller().set_primary_map("land");await frames()
		var vehicle:Dictionary=CONTROLS.own(controller(),company)
		var people:Array=people_in(company);var ids:Array=people.map(func(row):return int(row.id));ids.sort()
		check(people.size()==(8 if identity=="MCP-103" else 6),"registered real infantry complement "+identity)
		check(vehicle.get("operator_id")==null and bool(vehicle.get("separate_vehicle_hp",false)),"vehicle is separate from every body "+identity)
		check(people.all(func(row):return int(row.id)!=int(vehicle.id) and str(row.get("physical_class",""))=="infantry"),"unique infantry types and IDs "+identity)
		check(people.all(func(row):return str(row.get("weapon_family_id",""))==("pistol" if identity=="MCP-087" else "carbine" if identity in ["MCP-027","MCP-006"] else "rifle")),"people retain their actual own firearms "+identity)
		check(int(vehicle.magazine_ammo)+int(vehicle.reserve_ammo)==int(vehicle.ammo),"separate finite vehicle magazine "+identity)
		await frame_vehicle(vehicle)
		var sized_map=controller().ui.get_node("LandWindow/Map");var sized_actor=sized_map.actors.get(int(vehicle.id))
		check(sized_actor!=null and sized_actor.display_height*2.1>=sized_map._body_height(true,true)*2.6,"vehicle is visibly larger than SD infantry "+identity)
		if identity=="MCP-022":check(sized_actor.display_height*2.1>=sized_map._body_height(true,true)*3.6-.01,"tank silhouette can shelter several SD infantry")
		check(int(sized_map.target_at(sized_map.actor_hit_point(int(vehicle.id))).get("id",-1))==int(vehicle.id),"rendered vehicle centre remains selectable "+identity)
		check(actual_centres_match(sized_map),"paused native landing and rendered ground centres match "+identity)
		if not vehicle.get("passenger_ids",[]).is_empty():
			await unload(company,identity)
		vehicle=CONTROLS.own(controller(),company)
		check(vehicle.get("passenger_ids",[]).is_empty(),"actual bodies outside after landing "+identity)
		var before:Dictionary={}
		for person in people_in(company):before[int(person.id)]=Vector2(float(person.x),float(person.y))
		var holding:Dictionary=app.issue({"op":"littoral_order","unit_id":identity,"company_id":company,"action":"hold"})
		check(holding.get("ok",false),"actual bodies hold while vehicle moves "+identity+": "+str(holding.get("error","")))
		var destination:Vector2=legal_vehicle_point(vehicle,"move",80)
		var moving:Control=card("Vehicle_"+company);await reveal(moving);events.clear()
		if moving!=null:await drag(moving,world(destination),identity=="MCP-027")
		check(event_seen("vehicle_move_ordered"),"real pointer separately orders vehicle "+identity)
		var start:=Vector2(float(vehicle.x),float(vehicle.y))
		await advance(3)
		vehicle=CONTROLS.own(controller(),company)
		check(Vector2(float(vehicle.x),float(vehicle.y)).distance_to(start)>15,"empty vehicle really travels "+identity)
		check(actual_centres_match(sized_map),"paused native step immediately updates rendered positions "+identity)
		check(people_in(company).all(func(row):return Vector2(float(row.x),float(row.y)).distance_to(before[int(row.id)])<3),"dismounted bodies do not follow an empty vehicle "+identity)
		await frame_vehicle(vehicle)
		check(actual_centres_match(sized_map),"zoom and camera reprojection preserve real ground centres "+identity)
		unit=card("Unit_"+company);await reveal(unit);events.clear()
		var map=controller().ui.get_node("LandWindow/Map")
		var hit:Vector2=global_point(map,map.actor_hit_point(int(vehicle.id)))
		var snapshot:Dictionary=app.core.request({"op":"save","serialized":true})
		if unit!=null:await drag(unit,hit,identity=="MCP-103")
		if identity=="MCP-022":
			check(events.any(func(row):return str(row.kind)=="drag_rejected" and not bool(row.data.get("accepted",true))),"tank has no passenger seats")
			check(str(app.core.request({"op":"save","serialized":true}).serialized)==str(snapshot.serialized),"rejected tank boarding changes no state")
		else:
			check(event_seen("vehicle_embark_ordered"),"real pointer requests company boarding "+identity)
			var boarded:bool=false
			for i in range(120):
				await advance(.2);vehicle=CONTROLS.own(controller(),company)
				if vehicle.get("passenger_ids",[]).size()==ids.size():boarded=true;break
			check(boarded,"all actual bodies walk to their own vehicle "+identity)
			check(people_in(company).all(func(row):return bool(row.get("seated",false)) and int(row.get("in_vehicle",-1))==int(vehicle.id)),"actual seat observations identify the one vehicle "+identity)
			check(people_in(company).all(func(row):return not map.actors.has(int(row.id)) or not map.actors[int(row.id)].visible),"seated bodies are not drawn as extra infantry "+identity)
			await shot("actual-seated-"+identity)
			await unload(company,identity)
		var after_ids:Array=people_in(company).map(func(row):return int(row.id));after_ids.sort()
		check(after_ids==ids,"boarding and unloading preserve real body identity "+identity)
		await shot("actual-independent-"+identity)
		var saved:Dictionary=app.core.request({"op":"save","serialized":true})
		FileAccess.open(output_dir+"manual-vehicle-"+identity+".json",FileAccess.WRITE).store_string(JSON.stringify({"native":saved.get("serialized",""),"events":events,"scope":"Production pointer commands over unedited native state; independent people, vehicle and real seats"}))
		app.close_home_exercise();await frames()
	check(account.state==owned and FileAccess.get_sha256(account.save_path)==disk,"five borrowed vehicle reviews preserve account and disk")
	finish_combined()
func find_group(id:String)->Dictionary:
	for row in app.core.view.littoral.groups:
		if str(row.id)==id:return row
	return {}
func people_in(company:String)->Array:
	return app.core.view.littoral.land.entities.filter(func(row):return str(row.get("company_id",""))==company and str(row.get("vehicle_kind","")).is_empty() and str(row.get("side",""))=="allies" and float(row.get("hp",0))>0)
func actual_centres_match(map)->bool:
	if map.playing:return false
	for row in app.core.view.littoral.land.entities:
		var actor=map.actors.get(int(row.id))
		if actor!=null and actor.visible and float(row.get("hp",0))>0 and actor.position.distance_to(map.project(Vector2(float(row.x),float(row.y))))>.02:
			print("CENTRE_CONTEXT "+JSON.stringify({"row":row,"actor":actor.public_row,"position":actor.position,"projected":map.project(Vector2(float(row.x),float(row.y))),"target":actor.target_position,"playing":map.playing,"actual_tick":map.previous_tick}));return false
	return true
func pause_for_steps()->void:
	if app.running:await click(app.pause_button)
	app.update_battle();await frames()
func advance(seconds:float)->void:
	await pause_for_steps();await super.advance(seconds)
func reveal(item:Control)->void:
	if item==null:return
	controller().ui.get_node("Tray/Scroll").ensure_control_visible(item);await frames()
func frame_vehicle(vehicle:Dictionary)->void:
	var map=controller().ui.get_node("LandWindow/Map");map.zoom=14;map.camera_center=Vector2(float(vehicle.x),float(vehicle.y));map._camera_updated();await frames()
func legal_vehicle_point(vehicle:Dictionary,action:String,distance:float)->Vector2:
	var origin:=Vector2(float(vehicle.x),float(vehicle.y))
	for offset in [Vector2(distance,0),Vector2(-distance,0),Vector2(0,distance),Vector2(0,-distance),Vector2.ZERO]:
		var point:Vector2=origin+offset
		var response:Dictionary=app.core.request({"op":"littoral_vehicle_preview","vehicle_id":int(vehicle.id),"action":action,"x":point.x,"y":point.y})
		if response.get("ok",false) and response.get("data",{}).get("valid",false):return point
	check(false,"no lawful nearby vehicle "+action);return origin
func unload(company:String,identity:String)->void:
	var vehicle:Dictionary=CONTROLS.own(controller(),company);await frame_vehicle(vehicle)
	var destination:Vector2=legal_vehicle_point(vehicle,"disembark",45)
	var unloading:Control=card("Vehicle Unload_"+company);await reveal(unloading);events.clear()
	if unloading!=null:await drag(unloading,world(destination),true)
	if not check(unloading!=null and event_seen("vehicle_disembark_ordered"),"real touch card orders unloading "+identity):return
	for i in range(120):
		await advance(.2);vehicle=CONTROLS.own(controller(),company)
		if vehicle.get("passenger_ids",[]).is_empty():break
	check(vehicle.get("passenger_ids",[]).is_empty() and people_in(company).all(func(row):return not bool(row.get("seated",false)) and bool(row.get("active",true))),"bodies actually dismount on legal ground "+identity)
func finish_combined()->void:
	check(FileAccess.get_sha256("user://cas_port_v1.json")==main_hash and FileAccess.get_sha256("user://cas_port_v1.json.bak")==backup_hash,"formal account files unchanged")
	var report:Dictionary={"ok":failures.is_empty(),"checks":checks,"failures":failures,"inputs":inputs,"scope":"Five real borrowed platform battles; production mouse/touch deployment, independent movement, tank seat rejection, walk-to-board, actual unloading and render visibility. No synthetic HP/seats, no claim of full mission victory."}
	FileAccess.open(output_dir+"combined-input-receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify(report));app.queue_free();quit(0 if failures.is_empty() else 1)
