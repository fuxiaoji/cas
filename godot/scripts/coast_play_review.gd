extends SceneTree
## Real application/controllers, disposable account and original published core.
const ROOT:String="res://../artifacts/world3d-integration-20261116/"
var app:Control
var checks:int=0
var failures:Array[String]=[]
var images:Array[String]=[]
var normal_hashes:Dictionary={}
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
	for building in home.service.state().buildings:
		if str(building.kind)=="forge":
			canvas.focus_cell(Vector2i(int(building.cell.x),int(building.cell.y)),32)
			home._cell(Vector2i(int(building.cell.x),int(building.cell.y)));break
	await capture("home-facility")
	# Use the public, shipped lesson request. No synthetic combat/modified save.
	var lessons:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/tactical-training-v4.json"))
	var request:Dictionary=lessons.lessons.landing.request.duplicate(true)
	var started:Dictionary=app.core.request(request)
	check(started.get("ok",false),"published landing training starts")
	app.run={};app.campaign_mode=true;app.show_page("battle");await frames(5)
	var battle=app.battle_controller
	check(battle!=null,"real combined arms controller retained")
	if battle==null:finish();return
	battle.set_primary_map("land")
	var land= battle.ui.get_node("LandWindow/Map")
	check(is_instance_valid(land.world3d),"land battle consumes shared renderer")
	check(land.land==land.world3d.land,"battle native geography/entity positions unchanged")
	await capture("battle-land-overview")
	var groups:Array=app.core.view.littoral.groups
	if not groups.is_empty():
		var group:Dictionary=groups[0]
		var result:Dictionary=app.core.request({"op":"littoral_deploy","company_id":str(group.company_id),"beach":2})
		check(result.get("ok",false),"real company landing order accepted")
		for i in range(24):
			var stepped:Dictionary=app.core.request({"op":"step","seconds":5})
			check(stepped.get("ok",false),"real simulation step %d"%i)
			if app.core.view.get("result")!=null:break
		battle.selected_unit=str(group.company_id);battle.update()
		land.selected_unit=str(group.company_id);land.zoom=1;land.focus_selected();await frames(4)
		await capture("battle-company-close")
		var maximum_error:float=0
		for row in land.land.get("entities",[]):
			var at:=Vector2(float(row.x),float(row.y))
			maximum_error=maxf(maximum_error,at.distance_to(land.unproject(land.project(at))))
		check(maximum_error<.5,"battle terrain pick roundtrip below 0.5m")
		var selected_id:String=str(battle.selected_unit)
		battle.set_primary_map("sea");await frames();battle.set_primary_map("land");await frames()
		check(battle.selected_unit==selected_id,"sea land swap preserves selected company")
		check(land.land==land.world3d.land,"sea land swap preserves same native map")
	app.running=false;app.core.close();app.run={};app.show_page("home");await frames(3)
	check(app.screen=="home","return from battle to home works")
	app.show_page("harbor");await frames(3);check(app.screen=="harbor","direct return to harbour works")
	finish()
func finish()->void:
	for name in normal_hashes:check(FileAccess.get_sha256("user://"+str(name))==normal_hashes[name],"normal profile unchanged "+str(name))
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"images":images,"render_backend":RenderingServer.get_current_rendering_method(),"headless":DisplayServer.get_name()=="headless","normal_profile_written":false}
	var file=FileAccess.open(ROOT+("play-headless.json" if DisplayServer.get_name()=="headless" else "play-gpu.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close();print("COAST_PLAY_REVIEW ",JSON.stringify(report))
	if is_instance_valid(app):app.core.close();app.queue_free()
	await frames(2);quit(0 if failures.is_empty() else 1)
