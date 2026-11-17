extends SceneTree
## Production historical voyages and exact old-asset registration, without authority changes.
const Settle = preload("res://tests/transition_settle.gd")
const Map = preload("res://scripts/historical_map.gd")
const Core = preload("res://scripts/core_bridge.gd")
var app
var checks := 0
var failures: Array[String] = []
var evidence: Array[Dictionary] = []
var shots: Array[String] = []
var selected := -1
var output := "res://../artifacts/godot/historical-satellite/"

func _initialize() -> void: call_deferred("run")
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok: failures.append(title); push_error(title)
func capture(name: String) -> void:
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(output+name+".png")
	check(root.get_texture().get_image().save_png(path) == OK, "actual GPU image "+name)
	shots.append(path)
func event_position(local: Vector2) -> Vector2:
	return app.sea.get_viewport().get_screen_transform()*app.sea.get_global_transform_with_canvas()*local
func mouse(button: int, pressed: bool, at: Vector2) -> void:
	var event := InputEventMouseButton.new(); event.button_index=button; event.pressed=pressed; event.position=event_position(at)
	Input.parse_input_event(event); await process_frame
func move_pointer(at: Vector2) -> void:
	var event := InputEventMouseMotion.new(); event.position=event_position(at)
	Input.parse_input_event(event); await process_frame
func start(id: String) -> void:
	app=load("res://scenes/main.tscn").instantiate(); app.boot_to_title=false
	app.economy=load("res://scripts/economy.gd").new("user://tests/historical-satellite-%d-%s.json"%[OS.get_process_id(),id])
	root.add_child(app); app.set_process(false); await process_frame; app.page_motion=false
	app.start_local_mode({"op":"new_campaign","id":id,"difficulty":"standard","seed":6106,"profile":"coord"},{"mode":"campaign","id":id,"difficulty":"standard","title":"卫星海图实测","side":"allies"})
	await Settle.wait_for_route(self,app)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED); app.fullscreen_battle=false; root.size=Vector2i(1280,720)
	await process_frame; await process_frame
func close_app() -> void:
	app.core.close(); app.queue_free(); await process_frame
func map_case(id: String, variant: String, origin: Vector2) -> void:
	await start(id)
	check(app.screen=="battle" and str(app.core.view.get("variant",""))==variant,"real historical voyage "+variant)
	if app.screen!="battle": await close_app(); return
	var sea: Control = app.sea
	check(sea.is_historical_chart() and sea.has_satellite_chart(),"registered satellite chosen "+variant)
	check(not sea.uses_anime_environment() and not sea.environment_layer.visible and not sea.sea_background.visible,"no procedural clouds/islands over original chart "+variant)
	check(str(app.core.view.environment.light)=="night","historical night remains authoritative "+variant)
	check(Map.geo_to_world(app.core.view,origin.x,origin.y).length()<1.5,"original west/south registration anchor "+variant)
	# The exact legacy constants are independently retained here, and not fitted to pixels.
	var legacy_origin: Dictionary = {"savo":[159.5834,-9.417],"esperance":[159.5894,-9.3419],"tassafaronga":[159.6902,-9.3545]}
	var field: Array = legacy_origin[variant]
	var expected := Vector2((159.82320-float(field[0]))*111320.0*cos(deg_to_rad(float(field[1]))),(-9.13042-float(field[1]))*110574.0)
	check(Map.geo_to_world(app.core.view,159.82320,-9.13042).distance_to(expected)<.02,"Savo landmark matches old Web affine transform "+variant)
	var saved: String = str(app.core.request({"op":"save","serialized":true}).serialized)
	var observed: String = JSON.stringify(app.core.request({"op":"observe"}).data)
	sea.zoom=1.0; sea.pan=Vector2.ZERO; sea.queue_redraw()
	await capture(variant+"-overview-1280x720")
	var own: Dictionary = app.core.view.ships[0]
	sea.zoom=2.2; sea.pan=Vector2.ZERO; sea.pan=sea.size*.5-sea.project(sea.pos(own)); sea.queue_redraw()
	await process_frame
	sea.object_selected.connect(func(kind,row):
		if kind=="ship": selected=int(row.id))
	selected=-1
	await mouse(MOUSE_BUTTON_LEFT,true,sea.project(sea.pos(own))); await mouse(MOUSE_BUTTON_LEFT,false,sea.project(sea.pos(own)))
	check(selected==int(own.id),"actual click selects own hull over registered photo "+variant)
	var pointer := sea.size*Vector2(.43,.42)
	var world: Vector2 = sea.unproject(pointer)
	await mouse(MOUSE_BUTTON_WHEEL_UP,true,pointer)
	check(sea.unproject(pointer).distance_to(world)<.04,"wheel zoom keeps point anchored "+variant)
	var before: Rect2 = Map.screen_bounds(sea)
	var start := sea.size*Vector2(.48,.42)
	await mouse(MOUSE_BUTTON_RIGHT,true,start); await move_pointer(start+Vector2(37,21)); await mouse(MOUSE_BUTTON_RIGHT,false,start+Vector2(37,21))
	check((Map.screen_bounds(sea).position-before.position-Vector2(37,21)).length()<.1,"photo follows actual right-drag exactly "+variant)
	before=Map.screen_bounds(sea); sea.combat_offset=Vector2(5,-3)
	check((Map.screen_bounds(sea).position-before.position-Vector2(5,-3)).length()<.1,"photo and units share recoil transform "+variant)
	check(sea.unproject(sea.project(sea.pos(own))).distance_to(sea.pos(own))<.04,"recoil input inverse remains valid "+variant)
	sea.combat_offset=Vector2.ZERO
	sea.zoom=1.0; sea.pan=Vector2.ZERO
	for window in [Vector2i(960,540),Vector2i(1600,900),Vector2i(1600,720)]:
		root.size=window; sea.queue_redraw(); await capture(variant+"-overview-%dx%d"%[window.x,window.y])
		check(Map.screen_bounds(sea).has_area(),"satellite remains georegistered at "+str(window)+" "+variant)
	root.size=Vector2i(1280,720)
	sea.historical_satellite_enabled=false; sea.queue_redraw(); await process_frame
	check(not sea.uses_anime_environment(),"tactical toggle never returns historical map to anime "+variant)
	sea.historical_satellite_enabled=true; sea.queue_redraw(); await process_frame
	check(str(app.core.request({"op":"save","serialized":true}).serialized)==saved,"render/input/zoom leave exact historical save unchanged "+variant)
	check(JSON.stringify(app.core.request({"op":"observe"}).data)==observed,"public historical observation unchanged "+variant)
	evidence.append({"variant":variant,"stage":id,"ships":app.core.view.ships.size(),"width":app.core.view.width,"height":app.core.view.height,"environment":app.core.view.environment,"source_image_sha256":FileAccess.get_sha256("res://assets/maps/ironbottom.jpg"),"registration":Map.registration(app.core.view),"savo_landmark_m":[expected.x,expected.y]})
	if variant=="esperance":
		for fleet in app.core.view.get("fleets",[]):
			app.core.request({"op":"ai","fleet":int(fleet.id),"mode":"auto","profile":"coord","move":true,"gun":true,"torpedo":true})
		var found := false
		for i in range(320):
			app.core.request({"op":"step","seconds":5})
			if not app.core.view.get("shells",[]).is_empty(): found=true; break
			if app.core.view.get("result")!=null: break
		check(found,"real historical fire produces public shell flight")
		if found:
			app.update_battle(); sea.zoom=1; sea.pan=Vector2.ZERO; sea.queue_redraw(); await capture("esperance-real-shells")
			var barrels := 0
			for shell in app.core.view.shells: barrels+=maxi(1,int(shell.get("barrels",1)))
			check(sea.projectiles.rounds().filter(func(row):return not bool(row.secondary)).size()==barrels,"latest per-barrel artillery remains on restored satellite")
			evidence.append({"real_artillery_tick":app.core.view.tick,"shells":app.core.view.shells,"rendered_main_rounds":barrels})
	await close_app()
func boundaries() -> void:
	var core = Core.new()
	var response: Dictionary = core.request({"op":"new_campaign","id":"CAMP-ALLIES-04","difficulty":"standard","seed":6106,"profile":"coord"})
	check(response.get("ok",false),"real Kula no-satellite historical voyage loads")
	if response.get("ok",false):
		check(Map.is_historical(core.view) and Map.registration(core.view).is_empty(),"Kula retains old flat chart without a guessed geographic anchor")
	response=core.request({"op":"new","variant":"empress","side":"allies","seed":6106,"enemy":"coord","profile":"coord","realtime":true})
	check(response.get("ok",false) and str(core.view.get("variant",""))=="empress" and Map.is_historical(core.view) and Map.registration(core.view).is_empty(),"Empress retains original tactical map, not mismatched Iron Bottom imagery")
	response=core.request({"op":"new_salvage","seed":6106,"start":{"content":"salvage-v1","fleet":[{"id":"IBS-U-USN-FLETCHER","hp":100,"ammo":60,"level":1,"equipment":false,"command":false}]}})
	check(response.get("ok",false) and core.view.has("salvage") and not Map.is_historical(core.view) and Map.registration(core.view).is_empty(),"actual salvage voyage keeps procedural sea without a historical photo")
	for command in [{"op":"new_chapter","id":"c1-breakout","seed":6109,"gameplay_profile":"cas-adventure-v1","intel_profile":"open-intel-v1"},{"op":"new_tide","seed":42,"character_id":"IBS-U-USN-FLETCHER"},{"op":"new","seed":6106,"side":"allies","realtime":true}]:
		response=core.request(command)
		check(response.get("ok",false) and not Map.is_historical(core.view) and Map.registration(core.view).is_empty(),"procedural mode never receives historical photo "+str(command.op))
	core.close()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.content_scale_size=Vector2i(1600,900); root.size=Vector2i(1280,720)
	check(FileAccess.get_sha256("res://assets/maps/ironbottom.jpg")==FileAccess.get_sha256("res://../client/public/maps/ironbottom.jpg"),"original cached image copied byte-for-byte")
	await map_case("CAMP-ALLIES-02","esperance",Vector2(159.5894,-9.3419))
	await map_case("CAMP-ALLIES-10","savo",Vector2(159.5834,-9.417))
	await map_case("CAMP-ALLIES-05","tassafaronga",Vector2(159.6902,-9.3545))
	boundaries()
	var report := {"checks":checks,"failures":failures,"passed":failures.is_empty(),"evidence":evidence,"screenshots":shots,"renderer":RenderingServer.get_video_adapter_name(),"scope":"Production native historical campaigns; exact old satellite source/affine registration. Other historical regions retain old tactical chart. No authority, coastline, ship card, scenario or native code is modified."}
	FileAccess.open(output+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("HISTORICAL_SATELLITE ",JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()})); quit(0 if failures.is_empty() else 1)
