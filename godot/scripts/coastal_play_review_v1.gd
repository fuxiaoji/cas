extends SceneTree
## New procedural map in the real application. Separate profile and candidate core.
const ROOT:String="res://../artifacts/coastal-rebuild-20261116/"
var app:Control
var checks:int=0
var failures:Array[String]=[]
var images:Array[String]=[]
var normal_hashes:Dictionary={}
var projection_samples:Array=[]
var occluded_entities:int=0
var input_events:int=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func frames(count:int=3)->void:
	for i in range(count):await process_frame
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
func capture(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await frames(4)
	var path:String=ROOT+name+".png"
	root.get_texture().get_image().save_png(path);images.append(ProjectSettings.globalize_path(path))
func inject(event:InputEvent)->void:
	root.push_input(event,true);input_events+=1
	await frames(2)
func click(control:Control)->void:
	var point:Vector2=control.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;await inject(motion)
	for down:bool in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;await inject(event)
func drag(from:Vector2,to:Vector2)->void:
	var down:=InputEventMouseButton.new();down.position=from;down.global_position=from;down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;await inject(down)
	var previous:Vector2=from
	for index:int in range(1,9):
		var point:Vector2=from.lerp(to,float(index)/8)
		var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;motion.relative=point-previous;motion.button_mask=MOUSE_BUTTON_MASK_LEFT;await inject(motion);previous=point
	var up:=InputEventMouseButton.new();up.position=to;up.global_position=to;up.button_index=MOUSE_BUTTON_LEFT;up.pressed=false;await inject(up)
func company_card(battle,identity:String)->Control:
	for node:Node in battle.ui.find_children("*","PanelContainer",true,false):
		if node.get_script()!=null and node.get_script().resource_path.ends_with("littoral_drag_card.gd") and str(node.payload.get("company_id",""))==identity and str(node.payload.get("kind",""))=="unit":return node
	return null
func capture_native_terrain(canvas:Control)->void:
	if DisplayServer.get_name()=="headless":return
	var grid=canvas.world3d.surface.native_grid
	for entry:Dictionary in [{"biome":"mountain","image":"home-highland"},{"biome":"swamp","image":"home-wetland"},{"biome":"sand","image":"home-coast"}]:
		var candidates:Array[Vector2]=[]
		var centroid:Vector2=Vector2.ZERO
		for index:int in range(grid.biomes.size()):
			if str(grid.biomes[index])!=entry.biome:continue
			var point:Vector2=grid.origin+Vector2(index%grid.columns,floori(float(index)/grid.columns))*grid.cell_size
			candidates.append(point);centroid+=point
		if candidates.is_empty():continue
		centroid/=candidates.size()
		candidates.sort_custom(func(a:Vector2,b:Vector2)->bool:return a.distance_squared_to(centroid)<b.distance_squared_to(centroid))
		canvas.world3d_center=candidates[0];canvas.zoom=canvas._world3d_zoom_for_span(120.0)
		canvas._sync_world3d_camera();canvas.queue_redraw()
		await capture(str(entry.image))
func run()->void:
	for name in ["cas_port_v1.json","cas_port_v1.json.bak"]:normal_hashes[name]=FileAccess.get_sha256("user://"+name)
	var profile:String=ProjectSettings.globalize_path(ROOT+"review-player-%d.json"%OS.get_process_id())
	DirAccess.copy_absolute(ProjectSettings.globalize_path(ROOT+"player.json"),profile)
	app=load("res://scenes/main.tscn").instantiate()
	app.economy=load("res://scripts/economy.gd").new(profile)
	app.immersive_fullscreen=false;app.boot_to_title=false;app.page_motion=false
	root.size=Vector2i(1600,900);root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	check(app.startup_ready,"real app startup accepted isolated profile")
	app.page_motion=false;app.set_meta("reduced_motion",true)
	app.show_page("home");await frames(5)
	var home=app.page.get_node_or_null("HomeIsland")
	check(home!=null,"real home page built")
	if home==null:finish();return
	var canvas=home.canvas
	check(is_instance_valid(canvas.world3d),"home consumes shared 3D renderer")
	check(home.service.state().units.size()==27,"published 27 unit account retained")
	check(canvas.native_projection.land==canvas.world3d.land,"home passes native land unchanged")
	var home_exercise:Dictionary=home.service.prepare_latest_exercise(["MCP-034"],["CAS-H-USN-ENTERPRISE-1942","CAS-O-APV-TIDEBRIDGE"],"balanced")
	check(home_exercise.get("ok",false),"all actual home defense facilities fit the new combat geography")
	if not home_exercise.get("ok",false):failures.append(str(home_exercise))
	canvas.reset_camera();await capture("home-overview")
	canvas.focus_base();await frames()
	var anchor:Vector2=canvas.size*.5
	var before:Vector2=canvas.world3d.unproject(anchor)
	canvas.zoom_at(1.25,anchor)
	check(before.distance_to(canvas.world3d.unproject(anchor))<.5,"home anchored zoom preserves command metres")
	for building in home.service.state().buildings:
		var cell:=Vector2i(int(building.cell.x),int(building.cell.y))
		var projected:Vector2=canvas.point(Vector2(cell))
		check(canvas.cell_at(projected)==cell,"home 3D building pick "+str(building.id))
	await capture("home-base")
	await capture_native_terrain(canvas)
	for building in home.service.state().buildings:
		if str(building.kind)=="forge":
			canvas.focus_cell(Vector2i(int(building.cell.x),int(building.cell.y)),32)
			home._cell(Vector2i(int(building.cell.x),int(building.cell.y)));break
	await capture("home-facility")
	# Use the public, shipped lesson request. No synthetic combat/modified save.
	var prepared:Dictionary=home.service.latest_training("landing")
	check(prepared.get("ok",false),"new coastal lesson locates real buildable targets")
	if not prepared.get("ok",false):finish();return
	await click(home.get_node("Layout/Top/Training"))
	var lesson:Control=app.modal.find_child("Lesson-landing",true,false) if app.modal!=null else null
	check(lesson!=null,"training menu reachable by pointer")
	if lesson==null:finish();return
	await click(lesson);await frames(5)
	check(app.screen=="battle" and app.home_exercise_session!=null and app.home_exercise_session.active,"training pointer enters real disposable coastal session")
	if app.screen!="battle":finish();return
	check(str(app.core.view.get("island_war",{}).get("combat_tuning",{}).get("version",""))==preload("res://scripts/coastal_map_settings.gd").COMBAT_TUNING,"new operation explicitly selects current coastal combat tuning")
	check(app.core.view.get("littoral",{}).get("land",{}).get("geography",{}).get("heightfield",{}).get("heights",[]).size()==32761,"client enriches native header with frozen grid")
	var raw:Dictionary=app.core.request({"op":"observe"})
	check(not raw.get("data",{}).get("littoral",{}).get("land",{}).get("geography",{}).has("heightfield"),"ordinary raw observation retains light geography header")
	var battle=app.battle_controller
	check(battle!=null,"real combined arms controller retained")
	if battle==null:finish();return
	battle.set_primary_map("land")
	var land= battle.ui.get_node("LandWindow/Map")
	check(is_instance_valid(land.world3d),"land battle consumes shared renderer")
	check(land.land==land.world3d.land,"battle native geography/entity positions unchanged")
	await capture("battle-land-overview")
	if battle.tutorial!=null and battle.tutorial.active:
		await click(battle.tutorial._close)
		check(not battle.tutorial.active,"help can close without completing native training")
	var groups:Array=app.core.view.littoral.groups
	if not groups.is_empty():
		var group:Dictionary=groups[0]
		for row:Dictionary in groups:
			if str(row.get("unit_id",""))=="MCP-034":group=row;break
		var card:Control=company_card(battle,str(group.company_id))
		check(card!=null,"real company card found in command tray")
		var coast:Array=app.core.view.littoral.get("beaches",[])
		var landing:Dictionary={}
		for slot:Dictionary in coast:
			if int(slot.get("id",0))==2:landing=slot.get("land",{});break
		check(not landing.is_empty(),"native public landing slot available")
		if card!=null and not landing.is_empty():
			var at:=Vector2(float(landing.x),float(landing.y))
			await drag(card.get_global_rect().get_center(),land.get_global_transform()*land.project(at))
			var changed:Dictionary={}
			for row:Dictionary in app.core.view.littoral.groups:
				if str(row.company_id)==str(group.company_id):changed=row;break
			check(str(changed.get("stage",""))!="embarked" or changed.get("pending_deploy")!=null,"pointer drag submits actual company landing plan")
		for i in range(24):
			var stepped:Dictionary=app.core.request({"op":"step","seconds":5})
			check(stepped.get("ok",false),"real simulation step %d"%i)
			if app.core.view.get("result")!=null:break
		battle.selected_unit=str(group.company_id);battle.update()
		FileAccess.open(ROOT+"battle-observation.json",FileAccess.WRITE).store_string(JSON.stringify(app.core.view))
		land.selected_unit=str(group.company_id);land.zoom=1;land.focus_selected();await frames(4)
		var camera_anchor:Vector2=land.size*Vector2(.42,.54)
		var anchored:Vector2=land.unproject(camera_anchor)
		var zoom_before:float=land.zoom
		var wheel:=InputEventMouseButton.new();wheel.position=land.get_global_transform()*camera_anchor;wheel.global_position=wheel.position;wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.pressed=true;await inject(wheel)
		check(land.zoom>zoom_before,"pointer wheel zooms real land camera")
		check(anchored.distance_to(land.unproject(camera_anchor))<.5,"land pointer zoom preserves visible terrain anchor")
		var camera_before:Vector2=land.camera_center
		var pan_from:Vector2=land.get_global_transform()*(land.size*Vector2(.30,.75))
		var pan_down:=InputEventMouseButton.new();pan_down.button_index=MOUSE_BUTTON_MIDDLE;pan_down.position=pan_from;pan_down.global_position=pan_from;pan_down.pressed=true;await inject(pan_down)
		var pan_event:=InputEventMouseMotion.new();pan_event.position=pan_from+Vector2(45,12);pan_event.global_position=pan_event.position;pan_event.relative=Vector2(45,12);pan_event.button_mask=MOUSE_BUTTON_MASK_MIDDLE;await inject(pan_event)
		pan_down=pan_down.duplicate();pan_down.pressed=false;pan_down.position=pan_event.position;pan_down.global_position=pan_event.position;await inject(pan_down)
		check(land.camera_center.distance_to(camera_before)>1,"pointer drag pans real land camera")
		await capture("battle-company-close")
		var maximum_error:float=0
		for row in land.land.get("entities",[]):
			var at:=Vector2(float(row.x),float(row.y))
			var hit:Vector2=land.unproject(land.project(at));var error:float=at.distance_to(hit)
			if not land.world3d.is_point_visible(at):
				occluded_entities+=1;continue
			if error>.5:projection_samples.append({"id":row.get("id"),"side":row.get("side"),"x":at.x,"y":at.y,"seated":row.get("seated"),"phase":row.get("phase"),"hp":row.get("hp"),"screen":str(land.project(at)),"error_m":error,"hit":str(hit)})
			maximum_error=maxf(maximum_error,error)
		check(maximum_error<.5,"visible battle surface pick roundtrip below 0.5m")
		var selected_id:String=str(battle.selected_unit)
		battle.set_primary_map("sea");await frames();await capture("battle-sea")
		if DisplayServer.get_name()!="headless" and is_instance_valid(app.sea.world3d):
			app.sea.world3d.viewport.get_texture().get_image().save_png(ROOT+"sea-viewport.png")
		battle.set_primary_map("land");await frames()
		check(battle.selected_unit==selected_id,"sea land swap preserves selected company")
		check(land.land==land.world3d.land,"sea land swap preserves same native map")
	app.running=false;app.close_home_exercise();await frames(3)
	check(app.screen=="home","return from battle to home works")
	app.show_page("harbor");await frames(3);check(app.screen=="harbor","direct return to harbour works")
	finish()
func finish()->void:
	for name in normal_hashes:check(FileAccess.get_sha256("user://"+str(name))==normal_hashes[name],"normal profile unchanged "+str(name))
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"input_events":input_events,"failures":failures,"occluded_entities":occluded_entities,"projection_samples":projection_samples,"images":images,"render_backend":RenderingServer.get_current_rendering_method(),"headless":DisplayServer.get_name()=="headless","normal_profile_written":false}
	var file=FileAccess.open(ROOT+("play-headless.json" if DisplayServer.get_name()=="headless" else "play-gpu.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close();print("COASTAL_REBUILD_PLAY_REVIEW ",JSON.stringify(report))
	if is_instance_valid(app):app.core.close();app.queue_free()
	await frames(2);quit(0 if failures.is_empty() else 1)
