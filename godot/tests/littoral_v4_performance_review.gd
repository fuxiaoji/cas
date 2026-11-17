extends "res://tests/littoral_v4_world_review.gd"
## Actual native fifty-body defense, registered aircraft and production Main clock.
var samples:Array[float]=[]
var measuring:bool=false
var last_usec:int=0
class TerrainProbe extends Control:
	var map
	var elapsed_ms:float=0
	func _draw()->void:
		var started:int=Time.get_ticks_usec()
		load("res://scripts/procedural_amphibious_terrain.gd").paint(self,map.land.get("polygon",[]),map.project,int(map.land.get("seed",0)),float(map.land.get("tick",0)),2,[],map.land.get("town",{}),map.land.get("terrain",{}),map.project_base)
		elapsed_ms=float(Time.get_ticks_usec()-started)/1000
func _process(_delta:float)->bool:
	if measuring:
		var now:int=Time.get_ticks_usec()
		if last_usec>0:samples.append(float(now-last_usec)/1000)
		last_usec=now
	return false
func quantile(values:Array[float],q:float)->float:
	if values.is_empty():return 0
	var sorted:Array[float]=values.duplicate();sorted.sort();return sorted[mini(sorted.size()-1,int(q*(sorted.size()-1)))]
func run()->void:
	output_dir="res://../artifacts/littoral-v4-ui/performance/";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	profile=output_dir+"isolated-%d.json"%OS.get_process_id();var account=load("res://scripts/economy.gd").new(profile);check(account.load_state().get("ok",false),"ordinary isolated fifty-body UI account")
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.fullscreen_battle=true
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames();app.set_process(false);app.page_motion=false
	var request:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../artifacts/littoral-v4/defense-fifty-air-request.json"))
	if not check(app.core.request(request).get("ok",false),"native legal five-company fifty-body defense"):return finish()
	app.show_page("battle");await frames(6);controller().tutorial_dismissed=true;controller().tutorial.active=false;controller().tutorial.hide();controller().selected_unit="MCP-034";controller().set_primary_map("land");app.running=false;app.update_battle();await frames()
	var land=controller().ui.get_node("LandWindow/Map");var native:Array=app.core.view.littoral.land.entities.filter(func(row):return str(row.side)=="allies")
	check(native.size()==50,"fifty real friendly bodies are publicly observed")
	check(land.actors.values().filter(func(actor):return actor.friendly).size()==50,"all fifty real friendly bodies have independent visuals")
	var elevation_error:float=0;var inverse_error:float=0;var edge_cases:int=0
	for row in app.core.view.littoral.land.entities:
		var point:=Vector2(float(row.x),float(row.y));elevation_error=maxf(elevation_error,absf(land._height_at(point)-float(row.get("elevation_m",0))))
	for zone in app.core.view.littoral.land.terrain.elevation_zones:
		if float(zone.get("height_m",0))<=0:continue
		var polygon:PackedVector2Array=land._terrain_points(zone.polygon);var center:Vector2=Vector2.ZERO
		for vertex in polygon:center+=vertex
		center/=polygon.size()
		for index in range(polygon.size()):
			for offset in [-3.0,0.0,3.0,60.0,119.9,120.1]:
				var midpoint:Vector2=(polygon[index]+polygon[(index+1)%polygon.size()])*.5;var point:Vector2=midpoint+midpoint.direction_to(center)*offset
				inverse_error=maxf(inverse_error,land.unproject(land.project(point)).distance_to(point));edge_cases+=1
	check(elevation_error<.02,"every actual native body elevation agrees with the rendered continuous surface")
	check(inverse_error<.02,"all actual native highland edges and slopes retain reversible drag coordinates")
	for dimensions in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=dimensions;await frames(5)
		var identities:Dictionary={}
		for key in land.actors:identities[key]=land.actors[key].get_instance_id()
		check(native.all(func(row):return int(land.target_at(land.actor_hit_point(int(row.id))).get("id",-1))==int(row.id)),"all fifty actual bodies remain independently targetable at "+str(dimensions))
		await shot("actual-fifty-land-%dx%d"%[dimensions.x,dimensions.y]);await click(controller().ui.get_node("MiniMap"));await shot("actual-fifty-sea-%dx%d"%[dimensions.x,dimensions.y]);await click(controller().ui.get_node("MiniMap"))
		check(land.actors.keys().all(func(key):return identities.get(key)==land.actors[key].get_instance_id()),"main/mini swap retains each actual body identity at "+str(dimensions))
	root.size=Vector2i(1280,720);await frames(5)
	var terrace:Dictionary=app.core.view.littoral.land.terrain.elevation_zones.filter(func(zone):return int(zone.get("level",0))==1)[0]
	var terrain_points:PackedVector2Array=land._terrain_points(terrace.polygon);var terrace_bounds:=Rect2(terrain_points[0],Vector2.ZERO)
	for vertex in terrain_points:terrace_bounds=terrace_bounds.expand(vertex)
	var high_target:Vector2=Vector2(terrace_bounds.position.x+85,terrace_bounds.end.y-90)
	check(app.issue({"op":"littoral_order","unit_id":"MCP-034","action":"move","x":high_target.x,"y":high_target.y}).get("ok",false),"actual company receives a legal move onto the native terrace")
	await advance(30)
	var actual_high:float=0
	for row in app.core.view.littoral.land.entities:
		actual_high=maxf(actual_high,float(row.get("elevation_m",0)));elevation_error=maxf(elevation_error,absf(land._height_at(Vector2(float(row.x),float(row.y)))-float(row.get("elevation_m",0))))
	check(actual_high>20 and elevation_error<.02,"actual moving bodies really reach high ground and match its exact native elevation")
	# Three actual carrier squadrons patrol native open water, not fabricated icons.
	var aircraft_count:int=0
	for squad in app.core.view.littoral.aviation.squadrons:
		if str(squad.visual_type) not in ["F4F","SBD","TBD"]:continue
		var mother:Dictionary=app.core.view.ships.filter(func(row):return int(row.id)==int(squad.carrier))[0]
		var response:Dictionary=app.issue({"op":"littoral_air_order","squadron_id":str(squad.id),"action":"patrol","x":float(mother.x)-4500,"y":float(mother.y)-1500})
		check(response.get("ok",false),"registered "+str(squad.visual_type)+" really launches for the performance sample")
		await advance(6.1)
	aircraft_count=app.core.view.littoral.aviation.aircraft.size();check(aircraft_count>=9,"three squadrons produce at least nine physical aircraft")
	var segments:Dictionary={"native_bridge_step_ms":[],"original_naval_update_ms":[],"full_amphibious_update_ms":[],"actual_terrain_paint_ms":[]}
	for index in range(5):
		var started:int=Time.get_ticks_usec();app.core.request({"op":"step","seconds":.1});segments.native_bridge_step_ms.append(float(Time.get_ticks_usec()-started)/1000)
		started=Time.get_ticks_usec();controller().naval_controller.update();segments.original_naval_update_ms.append(float(Time.get_ticks_usec()-started)/1000)
		started=Time.get_ticks_usec();app.update_battle();segments.full_amphibious_update_ms.append(float(Time.get_ticks_usec()-started)/1000)
	var probe:=TerrainProbe.new();probe.map=land;probe.mouse_filter=Control.MOUSE_FILTER_IGNORE;probe.size=land.size;land.add_child(probe)
	for index in range(5):probe.queue_redraw();await process_frame;await RenderingServer.frame_post_draw;segments.actual_terrain_paint_ms.append(probe.elapsed_ms)
	land.remove_child(probe);probe.queue_free();await frames()
	var measures:Array=[]
	for speed in [1,8]:
		controller().set_battle_speed(speed);app.elapsed=0;app.running=true;app.set_process(true)
		var start:int=Time.get_ticks_usec();var start_tick:float=float(app.core.view.tick);samples.clear();last_usec=0;measuring=true
		await create_timer(3.1).timeout
		measuring=false;var wall:float=float(Time.get_ticks_usec()-start)/1000000;var elapsed:float=float(app.core.view.tick)-start_tick;app.running=false;app.set_process(false);app.update_battle()
		measures.append({"speed":speed,"wall_seconds":wall,"native_seconds":elapsed,"actual_ratio":elapsed/wall,"frames":samples.size(),"frame_ms_p50":quantile(samples,.5),"frame_ms_p95":quantile(samples,.95),"frame_ms_max":samples.max() if not samples.is_empty() else 0,"clock_debt_seconds":app.elapsed,"friendly_bodies_start":native.size(),"friendly_bodies_end":app.core.view.littoral.land.entities.filter(func(row):return str(row.side)=="allies").size(),"aircraft":app.core.view.littoral.aviation.aircraft.size()})
		check(absf(elapsed-wall*speed)<maxf(.35,wall*speed*.15),"production Main fixed-step clock tracks actual "+str(speed)+"x wall time")
		check(app.elapsed>=-.00001 and app.elapsed<.21,"actual high-speed sample retains microstep remainder")
	var tick:float=float(app.core.view.tick);app.set_process(true);await create_timer(.3).timeout;app.set_process(false);check(float(app.core.view.tick)==tick,"explicit pause freezes the actual fifty-body native world")
	var saved:String=app.core.request({"op":"save","serialized":true}).serialized;app.core.close();check(app.core.request({"op":"load","serialized":saved}).get("ok",false),"actual fifty-body air-defense world restores through a new native process")
	land.prime_visuals();app.update_battle();await frames();check(app.core.request({"op":"save","serialized":true}).serialized==saved,"presentation and highland camera restore never mutate the native world")
	await shot("actual-fifty-air-defense-restored")
	FileAccess.open(output_dir+"performance.json",FileAccess.WRITE).store_string(JSON.stringify({"runtime":runtime_info(),"request":request,"scope":"direct legitimate native UI fixture, no account ownership or rewards claimed","measures":measures,"segments":segments,"native_elevation_max_error_m":elevation_error,"native_highest_observed_body_m":actual_high,"native_highland_inverse_max_error_m":inverse_error,"highland_edge_cases":edge_cases,"initial_physical_aircraft":aircraft_count},"  "))
	finish()
