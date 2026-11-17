extends "res://tests/littoral_drag_v2_review.gd"
## Observe real autonomous movement; no positions, damage or tactical labels edited.
func run()->void:
	output_dir="res://../artifacts/island-war-v3/presentation/"
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	var account=load("res://scripts/economy.gd").new(output_dir+"cover-isolated-%d.json"%OS.get_process_id());account.new_profile();account.state.progression.first_voyage_canon.active=false
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.deferred_startup=false;app.staged_navigation=false;app.immersive_fullscreen=false
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1600,900);root.add_child(app);await frames(6);app.page_motion=false;app.page_transition.cancel();app.set_process(false);AudioServer.set_bus_mute(0,true)
	app.home.development();app.show_page("home");await frames()
	var owned:Dictionary=account.state.duplicate(true);var disk:String=FileAccess.get_sha256(account.save_path)
	for spec in [["MCP-022","actual-tank-rear-cover.json",6],["MCP-103","actual-ifv-rear-cover.json",8]]:
		await review_cover(str(spec[0]),str(spec[1]),int(spec[2]))
	check(account.state==owned and FileAccess.get_sha256(account.save_path)==disk,"borrowed autonomous battles preserve account and disk")
	check(FileAccess.get_sha256("user://cas_port_v1.json")==main_hash and FileAccess.get_sha256("user://cas_port_v1.json.bak")==backup_hash,"formal account remains unchanged")
	var report:Dictionary={"ok":failures.is_empty(),"checks":checks,"failures":failures,"scope":"Two genuine native autonomous saves replayed through production IPC. Infantry reaches actual cover goals; GPU centres, vehicle size and person count checked. Damage, side-exit and pressure fallback are checked separately in core tests. No claim of full mission victory."}
	FileAccess.open(output_dir+"cover-receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify(report));app.queue_free();quit(0 if failures.is_empty() else 1)
func review_cover(identity:String,filename:String,expected_members:int)->void:
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../artifacts/island-war-v3/core/"+filename))
	await app.launch_home_exercise(fixture.initial_request);await frames();controller().tutorial.close_help()
	check(app.core.request({"op":"load","serialized":str(fixture.serialized)}).get("ok",false),"real autonomous save replays without edited observations "+identity)
	var body:Dictionary={};var vehicle:Dictionary={};var members:Array=[]
	var land:Dictionary=app.core.view.littoral.land
	for row in land.entities:
		if str(row.get("unit_id",""))!=identity or str(row.get("tactical_state",""))!="covered" or float(row.get("hp",0))<=0:continue
		var goal:Dictionary=row.get("tactical_goal",{})
		if goal.is_empty() or Vector2(float(row.x),float(row.y)).distance_to(Vector2(float(goal.x),float(goal.y)))>3:continue
		for item in land.combat_vehicles:
			if int(item.id)==int(row.get("cover_vehicle_id",-1)) and str(item.phase)=="active" and item.get("carried_by")==null:body=row;vehicle=item;break
		if not body.is_empty():break
	check(not body.is_empty(),"actual infantry reaches a legal native position behind its vehicle "+identity)
	if not body.is_empty():
		var company:String=str(body.company_id)
		members=app.core.view.littoral.land.entities.filter(func(row):return str(row.get("company_id",""))==company and not row.has("vehicle_kind") and float(row.get("hp",0))>0)
		check(members.size()==expected_members,"cover manoeuvre keeps original independent infantry "+identity)
		check(members.filter(func(row):return str(row.get("tactical_state",""))=="flanking").size()<=2,"no more than two simultaneous flanking infantry")
		controller().selected_unit=company;controller().set_primary_map("land");app.running=false;app.update_battle();await frames()
		var map=controller().ui.get_node("LandWindow/Map");map.zoom=18;map.camera_center=Vector2(float(vehicle.x),float(vehicle.y));map._camera_updated();await frames()
		check(map.display_offsets.is_empty(),"cover is real positioning rather than screen-space slots")
		for person in members:
			var actor=map.actors.get(int(person.id))
			check(actor!=null and actor.visible and actor.position.distance_to(map.project(Vector2(float(person.x),float(person.y))))<.02,"rendered infantry ground point equals native centre "+str(person.id))
		if identity=="MCP-022":check(map.actors[int(vehicle.id)].display_height*2.1>=map._body_height(true,true)*3.6-.01,"cover tank retains the enlarged visual silhouette")
		await shot("actual-autonomous-cover-"+identity)
		var saved:Dictionary=app.core.request({"op":"save","serialized":true})
		FileAccess.open(output_dir+"actual-autonomous-cover-"+identity+".json",FileAccess.WRITE).store_string(JSON.stringify({"serialized":saved.get("serialized",""),"tick":app.core.view.tick,"vehicle":vehicle,"members":members,"scope":"Unedited public autonomous movement; actual cover goal reached. Damage and line interception are checked separately in core tests."}))
	app.close_home_exercise();await frames()
