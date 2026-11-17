extends SceneTree
const Economy=preload("res://scripts/economy.gd")
const OUTPUT:String="res://../artifacts/home-review/"
var app
var shots:Array[String]=[]
var checks:int=0
var failures:Array[String]=[]
var support_report:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func settle()->void:
	for frame in range(5):await process_frame
func windowed()->void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);app.fullscreen_battle=false;root.size=Vector2i(1280,720)
func shot(label:String)->void:
	await settle();await RenderingServer.frame_post_draw
	var path:String=ProjectSettings.globalize_path(OUTPUT+label+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"actual GPU capture "+label);shots.append(path)
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var source:String="user://cas_port_v1.json";var source_sha:String=FileAccess.get_sha256(source);var backup_sha:String=FileAccess.get_sha256(source+".bak")
	var previous:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUTPUT+"receipt.json"))
	var isolated_source:String=str(previous.get("profile",""));var profile:String=OUTPUT+"isolated-visual-%d.json"%OS.get_process_id()
	check(FileAccess.file_exists(isolated_source),"previous real tutorial profile is available for visual review")
	check(DirAccess.copy_absolute(isolated_source,ProjectSettings.globalize_path(profile))==OK,"clone completed real tutorial profile for visual review")
	var economy=Economy.new(profile);check(economy.load_state().get("ok",false),"load real completed tutorial and test-unlocked collection")
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.economy=economy;root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await settle();app.page_motion=false;windowed()
	app.show_page("home");await settle();await shot("home-island-gpu")
	var home:Control=app.page.find_child("HomeIsland",true,false)
	if home!=null:
		home._units();await shot("home-unit-cards-gpu");app.close_modal()
		home._sortie();await shot("home-deployment-gpu");app.close_modal()
	app.show_page("home_recruit");await settle()
	var pool:Control=app.page.find_child("TacticalRecruit",true,false)
	if pool!=null:pool.focus_id="MCP-034";pool.refresh()
	await shot("home-protocol-pool-gpu")
	if pool!=null:
		for dimensions in [Vector2i(960,540),Vector2i(1920,1080)]:
			root.size=dimensions;await settle()
			var portrait:TextureRect=pool.get_node("Portrait")
			check(portrait.texture!=null and portrait.stretch_mode==TextureRect.STRETCH_KEEP_ASPECT_CENTERED,"full head and face preserved by complete-image fit at "+str(dimensions))
			check(pool.get_node("Layout/Actions/DrawTen").get_global_rect().end.y<=root.content_scale_size.y,"primary recruitment action remains within viewport at "+str(dimensions))
			await shot("home-protocol-pool-gpu-%dx%d"%[dimensions.x,dimensions.y])
		root.size=Vector2i(1280,720);await settle()
	var prepared:Dictionary=app.home.prepare_littoral("tutorial",42,["MCP-034"],["IBS-U-USN-FLETCHER"],"balanced")
	check(prepared.get("ok",false),"real battle preparation for GPU review")
	if prepared.get("ok",false):
		app.launch_littoral(prepared.request);await settle();windowed()
		app.issue({"op":"route","fleet":1,"speed":35,"points":[{"x":13000,"y":11500}]})
		var deployed:bool=false
		for second in range(100):
			var view:Dictionary=app.core.view
			if view.get("result")!=null:break
			var ship:Dictionary=view.ships[0]
			if not deployed and Vector2(float(ship.x),float(ship.y)).distance_to(Vector2(13000,11500))<800:
				deployed=app.issue({"op":"littoral_deploy","unit_id":"MCP-034","beach":2,"insertion":"landing"}).get("ok",false)
			if str(app.core.view.littoral.groups[0].stage)=="ground":break
			app.core.request({"op":"step","seconds":1})
		app.running=false;app.update_battle();await shot("home-sea-land-battle-gpu")
		check(deployed,"GPU sample really transports and deploys the unit")
		check(app.checkpoint(),"visual sample preserves its exact real voyage")
		# Finish only this isolated sample before creating the support interaction run.
		app.core.request({"op":"littoral_abandon"})
		var ended:Dictionary=app.core.request({"op":"save","serialized":true})
		check(app.home.settle(app.core.view,str(ended.serialized),true).get("ok",false),"end cloned visual sample through actual zero-reward abandonment")
		await support_sample()
	var runtime:Dictionary=load("res://tests/home_runtime_evidence.gd").capture(app.core)
	if not OS.has_environment("CAS_SIM_PATH"):check(bool(runtime.verified_default),"GPU uses actual default native PID path and manifest SHA without override")
	app.core.close();app.queue_free();await process_frame
	check(FileAccess.get_sha256(source)==source_sha,"main account unchanged during GPU review")
	check(FileAccess.get_sha256(source+".bak")==backup_sha,"main backup unchanged during GPU review")
	var receipt:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"actual_gpu":true,"shots":shots,"support":support_report,"runtime":runtime,"renderer":RenderingServer.get_video_adapter_name(),"profile":ProjectSettings.globalize_path(profile),"source_sha256":source_sha,"backup_sha256":backup_sha,"native":OS.get_environment("CAS_SIM_PATH")}
	FileAccess.open(OUTPUT+"visual-receipt.json",FileAccess.WRITE).store_string(JSON.stringify(receipt,"  "))
	print("HOME_VISUAL "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)

func support_sample()->void:
	var prepared:Dictionary=app.home.prepare_littoral("tutorial",42,["MCP-001"],["IBS-U-USN-ERMA-MISSOURI"],"transport")
	if not check_prepare(prepared):return
	app.launch_littoral(prepared.request);await settle();windowed();app.running=false
	var controller=app.battle_controller
	check(controller.ui.get_node("LandWindow/Controls/Insertion").text=="舟艇登陆","insertion control has a visible initial label")
	check(controller.ui.get_node("LandWindow/Controls/Order").text=="移动","ground order control has a visible initial label")
	var target:Dictionary=app.core.view.littoral.land.buildings.filter(func(row):return str(row.side)=="axis")[0]
	var point:Vector2=Vector2(float(target.x),float(target.y))
	controller.ui.get_node("Actions/Naval").pressed.emit();controller._land_click(point,str(target.id),"buildings");app.running=false
	check(app.core.view.littoral.support.naval[0].get("pending_target")!=null,"player click really queues one authority-owned naval target")
	var queued_save:String=str(app.core.request({"op":"save","serialized":true}).serialized)
	var queued_view:Dictionary=app.core.view.duplicate(true)
	app.core.request({"op":"load","serialized":queued_save});app.update_battle()
	check(app.home._same(app.core.view.littoral,queued_view.littoral),"pending naval support and gradual facing restore exactly")
	controller.ui.get_node("Actions/Naval").pressed.emit();app.running=false
	check(app.core.view.littoral.support.naval[0].get("pending_target")==null,"same visible action cancels the real queued support")
	controller.ui.get_node("Actions/Naval").pressed.emit();controller._land_click(point,str(target.id),"buildings");app.running=false
	var fired:bool=false;var air_deployed:bool=false;var air_arrived:bool=false;var helicopter_fired:bool=false
	for frame in range(180):
		app.core.request({"op":"step","seconds":.1});app.update_battle()
		for shot_record in app.core.view.littoral.get("shots",[]):
			if str(shot_record.kind)=="naval" and str(shot_record.source)=="ship:1" and Vector2(float(shot_record.target_x),float(shot_record.target_y)).distance_to(point)<1:fired=true
		if fired:break
	check(fired,"queued real naval support fires on the chosen land target after true turning and loading")
	await shot("home-naval-support-gpu")
	app.issue({"op":"route","fleet":1,"speed":30,"points":[{"x":13000,"y":11500}]});app.running=false
	controller.selected_unit="MCP-001";controller.selected_beach=2;controller.insertion="air"
	for second in range(140):
		if app.core.view.get("result")!=null:break
		var beach:Dictionary=app.core.view.littoral.beaches[1]
		var ship:Dictionary=app.core.view.ships[0]
		if not air_deployed and Vector2(float(ship.x),float(ship.y)).distance_to(Vector2(float(beach.land.x),float(beach.land.y)))<=5900:
			controller.ui.get_node("Actions/Land").pressed.emit();app.running=false
			air_deployed=str(app.core.view.littoral.groups[0].stage)=="transit"
		if str(app.core.view.littoral.groups[0].stage)=="ground":
			air_arrived=true;break
		app.core.request({"op":"step","seconds":1});app.update_battle()
	check(air_deployed and air_arrived,"player air insertion really transports owned 001 and creates actual land bodies")
	var air_entities:Array=app.core.view.littoral.land.entities.filter(func(row):return str(row.unit_id)=="MCP-001" and bool(row.get("airborne",false)) and float(row.hp)>0)
	if not air_entities.is_empty():
		var entity:Dictionary=air_entities[0]
		var air_point:Vector2=Vector2(float(entity.x),float(entity.y))
		controller.ui.get_node("Actions/Helicopter").pressed.emit();controller._land_click(air_point,0,"");app.running=false
		for record in app.core.view.littoral.get("shots",[]):
			if str(record.kind)=="air_support" and str(record.source)=="MCP-001":helicopter_fired=true
	check(helicopter_fired,"player helicopter support launches a real native projectile from the deployed air unit")
	await shot("home-air-insertion-gpu")
	check(app.checkpoint(),"save exact true naval and air support sample")
	FileAccess.open(OUTPUT+"support-save.json",FileAccess.WRITE).store_string(str(app.core.request({"op":"save","serialized":true}).serialized))
	FileAccess.open(OUTPUT+"support-view.json",FileAccess.WRITE).store_string(JSON.stringify(app.core.view,"  "))
	support_report={"naval_fired":fired,"air_inserted":air_deployed,"air_arrived":air_arrived,"helicopter_fired":helicopter_fired,"tick":app.core.view.tick}

func check_prepare(prepared:Dictionary)->bool:
	check(prepared.get("ok",false),"legitimate owned Missouri and 001 support request")
	return bool(prepared.get("ok",false))
