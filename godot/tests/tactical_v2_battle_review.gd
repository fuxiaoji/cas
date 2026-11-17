extends SceneTree
## Replay real native observations through the shipped controls and projections.
var checks:int=0
var failures:Array[String]=[]
var output:String="res://../artifacts/island-war-v2/presentation/"
var app
func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func frames(count:int=4)->void:
	for index in range(count):await process_frame
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await frames(3);RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output+name+".png"))==OK,"GPU "+name)
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var normal:String=FileAccess.get_sha256("user://cas_port_v1.json");var backup:String=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	var fixture_path:String=OS.get_environment("CAS_V2_FIXTURE") if OS.has_environment("CAS_V2_FIXTURE") else "res://../artifacts/island-war-v2/core/exercise-initial-trial.json"
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	var account=load("res://scripts/economy.gd").new(output+"battle-isolated-%d.json"%OS.get_process_id());account.new_profile();account.state.progression.first_voyage_canon.active=false
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.deferred_startup=false;app.staged_navigation=false;app.economy=account;app.immersive_fullscreen=false
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1600,900);root.add_child(app);await frames(7);app.page_motion=false;app.page_transition.cancel();app.set_process(false);AudioServer.set_bus_mute(0,true)
	app.home.development();app.show_page("home");await frames()
	var disk:String=FileAccess.get_sha256(account.save_path)
	app.home_replay_session=load("res://scripts/home_replay_session.gd").new()
	check(app.home_replay_session.open(app,{"snapshot":str(fixture.serialized)}).get("ok",false),"actual v2 native replay opens independently")
	await app.enter_battle();await frames()
	var controller=app.battle_controller;var land=controller.ui.get_node("LandWindow/Map")
	check(controller.replay_mode,"native recording uses read-only controller")
	check(str(app.core.view.island_war.version)=="cas-island-war-v2","new rules explicitly observed")
	check(land.land.get("art_version","")=="tactical-art-v2","new actors selected only in new rules")
	check(land.display_offsets.is_empty(),"real body positions are never replaced by screen-space formation slots")
	check(app.core.view.littoral.land.get("entities",[]).all(func(row):return float(row.get("collision_radius_m",0))>0),"actual native bodies expose individual collision footprints")
	check(land.land.get("terrain",{}).get("features",[]).size()>=8,"native terrain regions consumed")
	controller.set_primary_map("land");await frames()
	await shot("native-v2-terrain-overview")
	var airborne_tick:float=-1;var gunship_tick:float=-1;var fire_tick:float=-1;var big_launch:Dictionary={};var max_tick:float=float(JSON.parse_string(str(fixture.serialized)).get("tick",800))
	for second in range(1,mini(400,int(max_tick))):
		controller.seek_littoral(float(second),true)
		for row in app.core.view.littoral.land.get("entities",[]):
			if str(row.get("unit_id",""))=="MCP-088" and str(row.get("phase",""))=="parachuting" and airborne_tick<0:airborne_tick=second
			if str(row.get("unit_id",""))=="MCP-006" and str(row.get("physical_class",""))=="air" and gunship_tick<0:gunship_tick=second
		for launch in app.core.view.littoral.get("shots",[]):
			if float(launch.get("caliber_mm",0))>=300 and big_launch.is_empty():big_launch=launch.duplicate(true);fire_tick=second
		if airborne_tick>=0 and fire_tick>=0 and gunship_tick>=0:break
	check(airborne_tick>=0,"actual 88th descent exists in replay")
	if airborne_tick>=0:
		controller.seek_littoral(airborne_tick,true);var count:int=0;var target:Dictionary={}
		for row in app.core.view.littoral.land.entities:
			if str(row.get("unit_id",""))=="MCP-088" and str(row.get("phase",""))=="parachuting":count+=1;target=row
		check(count>0,"descent is actual native bodies")
		if not target.is_empty():
			land.zoom=20;land.camera_center=Vector2(float(target.x),float(target.y));land._camera_updated();await frames()
			var actor=land.actors.get(int(target.id));check(actor!=null and actor.art_v2 and actor.visual_lift()>0,"descent drives own SD above ground")
			check(load("res://scripts/tactical_art_v2.gd").available("MCP-088"),"88th uses approved own SD instead of unknown identity placeholder")
			if actor!=null:check(actor.target_position.distance_to(land.project(Vector2(float(target.x),float(target.y))))<.001,"88th drawing stays anchored to its actual independent body")
			if actor!=null:check(land.actor_hit_point(int(target.id)).y<actor.position.y-actor.display_height*.4,"airborne pointer target follows raised body")
			await shot("native-88-parachuting")
	check(gunship_tick>=0,"actual six-body helicopter company is deployed")
	controller.seek_littoral(gunship_tick if gunship_tick>=0 else minf(170,max_tick),true);await frames()
	var gunships:int=0
	for row in app.core.view.littoral.land.entities:
		if str(row.get("unit_id",""))=="MCP-006":
			gunships+=1
			check(str(row.get("physical_class",""))=="air","006 body operates actual combat helicopter")
		var actor=land.actors.get(int(row.id))
		if actor!=null and str(row.get("side",""))=="axis" and not bool(row.get("visible",true)) and float(row.get("hp",1))>0:check(not actor.visible,"unseen enemy movement is not revealed by renderer")
	check(gunships==6,"six helicopter bodies do not create a second free infantry company")
	await shot("native-v2-ground-cooperation")
	check(not big_launch.is_empty(),"real battleship caliber is published")
	if not big_launch.is_empty():
		var end:=Vector2(float(big_launch.get("target_x",0)),float(big_launch.get("target_y",0)));var launch:float=float(big_launch.get("tick",fire_tick));var flight:float=float(big_launch.get("flight_seconds",.1))
		land.zoom=7;land.camera_center=end;land._camera_updated()
		controller.seek_littoral(minf(max_tick,launch+flight*.6),true);await frames();await shot("native-battleship-shell-trajectories")
		controller.seek_littoral(minf(max_tick,launch+flight+.12),true);await frames();await shot("native-battleship-blast")
		var exact:Dictionary=app.core.view.duplicate(true);land.motion_strength=0;land.support_fx.strength=0;land.playing=true
		await frames(20);land.playing=false
		check(app.core.view==exact,"rendering never creates damage or changes real body coordinates")
		check(land.support_fx.last_offset.length()<.001,"zero motion preference keeps map still")
	app.close_home_replay();await frames()
	check(FileAccess.get_sha256(account.save_path)==disk,"replaying v2 never writes account")
	check(FileAccess.get_sha256("user://cas_port_v1.json")==normal and FileAccess.get_sha256("user://cas_port_v1.json.bak")==backup,"normal account and backup remain unchanged")
	var receipt:Dictionary={"ok":failures.is_empty(),"checks":checks,"failures":failures,"fixture":fixture_path,"airborne_tick":airborne_tick,"caliber_mm":big_launch.get("caliber_mm",0)}
	FileAccess.open(output+"battle-receipt.json",FileAccess.WRITE).store_string(JSON.stringify(receipt,"\t"));print(JSON.stringify(receipt));app.queue_free();await frames();quit(0 if failures.is_empty() else 1)
