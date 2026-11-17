extends SceneTree
const OUTPUT:String="res://../artifacts/island-war-v4/home/"
var checks:int=0
var failures:Array[String]=[]
var account
var home
var app
var inputs:int=0
func benchmark(label:String,canvas:Control,redraw:bool)->Dictionary:
	canvas.set_process(redraw)
	await frames(12)
	var times:Array[float]=[]
	var previous:int=Time.get_ticks_usec()
	for index in range(120):
		await process_frame
		var now:int=Time.get_ticks_usec();times.append(float(now-previous)/1000.0);previous=now
	times.sort()
	var sum:float=0
	for value in times:sum+=value
	return {"label":label,"continuous_canvas_redraw":redraw,"frames":times.size(),"mean_ms":sum/times.size(),"p50_ms":times[60],"p95_ms":times[114],"max_ms":times[-1],"method":"process-frame intervals; Windows owned offscreen1280x720 window; no concurrent GPU suite; shader water and actual SD continue"}
func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func frames(count:int=4)->void:
	for index in range(count):await process_frame
func click(node:Control,touch:bool=false)->void:
	check(node!=null,"requested actual control exists")
	if node==null:return
	var ancestor:Node=node.get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer:ancestor.ensure_control_visible(node)
		ancestor=ancestor.get_parent()
	await frames(3)
	var point:Vector2=node.get_global_transform_with_canvas()*(node.size*.5)
	for pressed in [true,false]:
		if touch:
			var event:=InputEventScreenTouch.new();event.position=point;event.pressed=pressed;event.index=0;root.push_input(event,true)
		else:
			var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
		inputs+=1;await process_frame
	await frames(4)
func shot(name:String)->void:
	name+=OS.get_environment("CAS_HOME_V4_CAPTURE_SUFFIX")
	if DisplayServer.get_name()=="headless":return
	await frames(3);RenderingServer.force_draw()
	check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT+name+".png"))==OK,"GPU capture "+name)
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var formal:String=FileAccess.get_sha256("user://cas_port_v1.json");var backup:String=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	account=load("res://scripts/economy.gd").new(OUTPUT+"isolated-%d.json"%OS.get_process_id());check(account.new_profile().ok,"isolated ordinary profile created")
	home=load("res://scripts/home_service.gd").new(account)
	for id in ["MCP-301","MCP-302","MCP-303","MCP-304","MCP-305"]:check(not home.state().units.has(id),"new personality is not silently gifted "+id)
	var Archive=load("res://scripts/home_carrier_archive.gd");var source:Dictionary=Archive.data()
	check(source.ships.size()==7 and source.characters.size()==7,"seven source-only ship identities are separate from account")
	for card in source.characters.values():
		check(not account._cards.has(str(card.id)) and not account.state.owned.has(str(card.id)),"source-only identity cannot be recruited or fielded "+str(card.id))
		check(ResourceLoader.exists(str(card.portrait)) and ResourceLoader.exists(str(card.chibi)),"source-only own portrait and SD both exist "+str(card.id))
	var Daily=load("res://scripts/home_daily_art.gd")
	check(not Daily.available({"id":"qa-portrait-only","portrait":"res://assets/ships/aviation-v4/CAS-H-USN-ENTERPRISE-1942.png"}),"home never substitutes a portrait for missing SD")
	var daily:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Daily.PATH))
	var approved:int=0
	for id in daily.units:
		var row:Dictionary=daily.units[id]
		if not bool(row.get("approved",false)):check(Daily.entry(str(id)).is_empty(),"pending daily art is not consumed "+str(id));continue
		approved+=1
		for pose in row.get("frames",[]):check(ResourceLoader.exists(str(pose.source)) and pose.rect.size()==4 and pose.pivot.size()==2 and float(pose.reference_height)>0,"identity daily frame source and anchor are usable "+str(id))
	check(approved>0,"at least one own authored animation is available")
	account.state.active_run={};account.state.progression.first_voyage_canon.active=false;home.state().unlocked=true;home.state().tutorial_complete=true;home.state().drag_tutorial_completed=true
	if OS.get_environment("CAS_HOME_V4_FORMAL_LAYOUT")=="1":
		var layout_source:Variant=JSON.parse_string(FileAccess.get_file_as_string("user://cas_port_v1.json"))
		if layout_source is Dictionary:home.state().buildings=layout_source.get("home_v1",{}).get("buildings",[]).duplicate(true)
	if OS.get_environment("CAS_HOME_V4_HQ")=="5":home.state().buildings[0].level=5
	for id in ["CAS-H-USN-ENTERPRISE-1942","CAS-H-IJN-SHOKAKU-1942","CAS-O-LHA-RETURNLIGHT","CAS-O-APV-TIDEBRIDGE","IBS-U-USN-UNNAMED-T01-R03","IBS-U-USN-WASHINGTON"]:account.state.owned[id]=account._new_owned(id)
	home.state().garrison=["CAS-H-USN-ENTERPRISE-1942","CAS-H-IJN-SHOKAKU-1942","CAS-O-LHA-RETURNLIGHT","CAS-O-APV-TIDEBRIDGE","IBS-U-USN-UNNAMED-T01-R03","IBS-U-USN-WASHINGTON"]
	home._own_unit("MCP-034");home.state().tactical_garrison=["MCP-034"];account.save_state()
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.deferred_startup=false;app.staged_navigation=false;app.immersive_fullscreen=false;app.economy=account;app.fullscreen_battle=false;root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames(8);app.page_motion=false;app.page_transition.cancel();AudioServer.set_bus_mute(0,true);app.show_page("home");await frames(8)
	var island:Node=app.page.find_child("HomeIsland",true,false);check(island!=null,"ordinary home page renders")
	var before:Dictionary=account.state.duplicate(true);var disk:String=FileAccess.get_file_as_string(account.save_path)
	for id in island.ship_residents:
		var resident=island.ship_residents[id].actor
		check(str(resident.card.id)==id and Daily.available(resident.card),"resident uses exact identity SD "+str(id))
		var routine0:Dictionary=resident.routine(108-resident.phase*9.71+2);var routine1:Dictionary=resident.routine(108-resident.phase*9.71+43)
		check(bool(routine0.walking) and not bool(routine1.walking) and str(routine1.state)=="sit","daily walk and rest are distinct timed phases "+str(id))
	if OS.get_environment("CAS_HOME_V4_PERF")=="1":
		var metrics:Array=[]
		metrics.append(await benchmark("near24x-normal",island.canvas,true))
		metrics.append(await benchmark("near24x-retained-canvas",island.canvas,false))
		island.canvas.reset_camera();await frames(10)
		metrics.append(await benchmark("overview-normal",island.canvas,true))
		metrics.append(await benchmark("overview-retained-canvas",island.canvas,false))
		island.canvas.set_process(true);island.canvas.focus_base();await frames(6)
		FileAccess.open(OUTPUT+"home-performance-211d.json",FileAccess.WRITE).store_string(JSON.stringify(metrics,"  "))
	await shot("home-daily-first")
	if island.canvas.has_native_geometry():
		await shot("home-native-base-211d");await click(island.get_node("Layout/Top/ResetView"));await shot("home-native-overview-211d");await click(island.get_node("Layout/Top/ResetView"))
	if not island.ship_residents.is_empty():
		# Choose a resident a player can actually touch. The first roster entry
		# may currently walk behind the resource bar; an occluded click is not
		# evidence about her Button or animation.
		var resident:Control=island.ship_residents.values()[0].actor
		var delta:Vector2=island.canvas.get_global_rect().get_center()-resident.get_global_rect().get_center()
		if delta.length()>40:
			# Real camera drag brings the actual world-space resident into view.
			# Her path, identity, node position and account are never rewritten.
			var transform:Transform2D=island.canvas.get_global_transform_with_canvas()
			var from:Vector2=island.canvas.size*.5-delta*.5;var to:Vector2=from+delta
			var motion:=InputEventMouseMotion.new();motion.position=transform*from;root.push_input(motion,true);inputs+=1;await process_frame
			var press:=InputEventMouseButton.new();press.position=transform*from;press.button_index=MOUSE_BUTTON_LEFT;press.button_mask=MOUSE_BUTTON_MASK_LEFT;press.pressed=true;root.push_input(press,true);inputs+=1;await process_frame
			motion=InputEventMouseMotion.new();motion.position=transform*to;motion.relative=delta;motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true);inputs+=1;await process_frame
			var release:=InputEventMouseButton.new();release.position=transform*to;release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;root.push_input(release,true);inputs+=1;await frames(4)
		var hover:=InputEventMouseMotion.new();hover.position=resident.get_global_transform_with_canvas()*(resident.size*.5);root.push_input(hover,true);inputs+=1;await process_frame
		check(root.gui_get_hovered_control()==resident,"actual camera drag exposes the own resident for direct interaction")
		await click(resident);check(resident.greeting_until>resident.clock,"clicking own resident greets her");resident.greeting_until=-1;await click(resident,true);check(resident.greeting_until>resident.clock,"touching own resident greets her");await shot("home-daily-greeting")
	await click(island.get_node("Layout/Top/IslandAffairs"));await click(app.modal.find_child("HomeCarrierArchiveEntry",true,false));check(str(app.modal.name)=="HomeCarrierArchive","ordinary home reaches source-only archive")
	await shot("source-only-seven-ships")
	for id in source.characters:
		await click(app.modal.find_child("Archive_"+str(id),true,false));check(str(app.modal.name)=="HomeCarrierCharacter" and bool(app.modal.get_meta("source_only",false)) and str(app.modal.get_meta("identity",""))==str(id),"actual archive pointer opens correct own identity "+str(id))
		check(app.modal.find_child("SourceOnlyPortrait",true,false).texture!=null and app.modal.find_child("SourceOnlySD",true,false).texture!=null,"archive GPU controls bind both pictures "+str(id))
		await click(app.modal.find_child("BackCarrierArchive",true,false))
	await shot("source-only-return-list");await click(app.modal.find_child("CarrierArchiveBack",true,false));check(str(app.modal.name)=="HomeConflictPanel","archive returns one layer to island affairs")
	check(home._same(account.state,before) and FileAccess.get_file_as_string(account.save_path)==disk,"daily interaction and source archive preserve complete account and exact disk")
	app.core.close();app.queue_free();await frames()
	check(FileAccess.get_sha256("user://cas_port_v1.json")==formal and FileAccess.get_sha256("user://cas_port_v1.json.bak")==backup,"formal account and backup remain read-only")
	var report:Dictionary={"checks":checks,"failures":failures,"core_sha256":FileAccess.get_sha256(OS.get_environment("CAS_SIM_PATH")),"published_catalogue_sha256":FileAccess.get_sha256("res://data/island-war-v4-published.json"),"daily_manifest_sha256":FileAccess.get_sha256(Daily.PATH),"input_transport":"Owned rootViewport.push_input with explicit viewport-local actual mouse/touch events","inputs":inputs,"approved_daily_identities":approved,"scope":"Own-identity daily animation, pending art rejection, seven source-only archive navigation, ordinary-account isolation. Native geometry camera screenshots are included; paid/exercise account paths are covered by the separate901-check suite.","formal_sha256":formal,"backup_sha256":backup}
	FileAccess.open(OUTPUT+"daily-archive-receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print("HOME_V4_DAILY ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
