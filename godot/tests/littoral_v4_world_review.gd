extends "res://tests/littoral_drag_v2_review.gd"
## True v4 World + amphibious integration. No account grants or fake observations.
var weapon_requests:Array=[]
var shell_peak:int=0
var torpedo_peak:int=0
var naval_shots:Array=[]
func shot(title:String)->void:
	if DisplayServer.get_name()=="headless":return
	await super.shot(title)
func advance(seconds:float)->void:
	for i in range(int(round(seconds*10))):
		var reply:Dictionary=app.core.request({"op":"step","seconds":.1})
		if not reply.get("ok",false):check(false,"actual authority advances "+str(reply));return
		shell_peak=maxi(shell_peak,app.core.view.get("shells",[]).size());torpedo_peak=maxi(torpedo_peak,app.core.view.get("torpedoes",[]).size())
		for row in app.core.view.get("presentation",{}).get("shots",[]):
			if not naval_shots.any(func(old):return old.get("id")==row.get("id")):naval_shots.append(row.duplicate(true))
		app.update_battle()
		if i%10==0:await process_frame
func find_group(id:String)->Dictionary:
	for row in app.core.view.littoral.groups:
		if str(row.id)==id:return row
	return {}
func runtime_info()->Dictionary:
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://bin/core-current.json"))
	var path:String=OS.get_environment("CAS_SIM_PATH")
	if path.is_empty():path=ProjectSettings.globalize_path("res://bin/"+str(manifest.executable))
	return {"path":path,"sha256":FileAccess.get_sha256(path),"override":OS.get_environment("CAS_SIM_PATH"),"manifest":manifest}
func command_ok(command:Dictionary,label:String)->Dictionary:
	var reply:Dictionary=app.core.request(command);check(reply.get("ok",false),label+" "+str(reply.get("error","")));return reply
func run()->void:
	output_dir="res://../artifacts/littoral-v4-ui/world/";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	profile=output_dir+"isolated-%d.json"%OS.get_process_id()
	var account=load("res://scripts/economy.gd").new(profile);check(account.load_state().get("ok",false),"isolated ordinary UI account")
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.fullscreen_battle=true
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames();app.set_process(false);app.page_motion=false
	var request:Dictionary={"op":"new_littoral","version":"cas-littoral-v4","mode":"tutorial","lesson":"landing","seed":42,"ships":[{"id":"IBS-U-USN-ERMA-IOWA","hp":100,"ammo":100},{"id":"CAS-H-USN-ENTERPRISE-1942","hp":100,"ammo":100},{"id":"IBS-U-USN-FLETCHER","hp":100,"ammo":100}],"roster":["MCP-034","MCP-001"],"unit_condition":[{"id":"MCP-034","hp":100},{"id":"MCP-001","hp":100}],"transport_preset":"balanced","defense":[]}
	if not check(app.core.request(request).get("ok",false),"real native v4 request accepted"):return finish()
	app.show_page("battle");await frames(5)
	var naval=controller().naval_controller
	if not check(naval!=null,"v4 uses the actual original naval controller"):return finish()
	check(app.sea.get_script().resource_path=="res://scripts/littoral_world_sea.gd","v4 extends the original naval interaction map")
	check(not app.core.view.get("fleets",[]).is_empty(),"actual World fleets remain public")
	check(app.core.view.ships.all(func(row):return row.has("systems")),"actual World damage and weapon systems remain public")
	check(app.sea.inspect_command.is_valid(),"original gun/torpedo aim queries reach native authority")
	check(not app.core.view.littoral.aviation.squadrons.is_empty(),"registered carrier produces actual aviation squadrons")
	controller().tutorial_dismissed=true;controller().tutorial.active=false;controller().tutorial.hide()
	controller().interaction_event.connect(func(kind,data):events.append({"kind":kind,"data":data.duplicate(true),"tick":app.core.view.tick}))
	for dimensions in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=dimensions;await frames(5)
		var id:int=int(app.core.view.ships[0].id)
		await click(naval.hud.fleet_cards[id].button)
		check(app.sea.selected_ship==id,"original pointer selects real ship at "+str(dimensions))
		await click(naval.hud.range_button)
		check(not app.sea.ranges_visible,"original range control toggles off at "+str(dimensions))
		await click(naval.hud.range_button);check(app.sea.ranges_visible,"original range control toggles back on")
		naval.show_tab("ship");await frames();check(naval.sidebar.is_visible_in_tree(),"original complete ship-status drawer opens")
		await shot("sea-status-%dx%d"%[dimensions.x,dimensions.y]);await click(naval.hud.tactical_button)
		check(card("Unit_MCP-034")!=null and card("Unit_MCP-034").type_badge!=null,"real tactical NATO drag card remains alongside naval UI")
		var before:String=app.core.request({"op":"save","serialized":true}).serialized
		await click(controller().ui.get_node("MiniMap"));check(controller().primary_map=="land","actual pointer swaps to linked land map")
		await shot("land-%dx%d"%[dimensions.x,dimensions.y]);await click(controller().ui.get_node("MiniMap"))
		check(str(app.core.request({"op":"save","serialized":true}).serialized)==before,"naval/land map switching never changes actual world")
	root.size=Vector2i(1280,720);await frames(4)
	var selected:Dictionary=app.core.view.ships[0]
	var point:=Vector2(float(selected.x),float(selected.y))
	var legal:Vector2=point
	for offset in [Vector2(-800,0),Vector2(800,0),Vector2(0,-800),Vector2(0,800)]:
		var candidate:Vector2=point+offset
		var preview:Dictionary=app.core.request({"op":"preview_route","fleet":int(selected.fleet),"mode":"follow","speed":10,"points":[{"x":candidate.x,"y":candidate.y}]})
		if preview.get("ok",false) and preview.get("data",{}).get("valid",false):legal=candidate;break
	check(legal!=point,"native World provides a real legal route")
	if legal!=point:
		naval.choose_route("follow");await frames();await _click_world(legal)
		check(not app.sea.planned.is_empty() and naval.preview.get("valid",false),"original map pointer builds a real route preview")
		naval.commit_route();check(app.sea.planned.is_empty(),"original controller submits and clears the accepted route")
	var initial:String=app.core.request({"op":"save","serialized":true}).serialized
	await drag(card("Unit_MCP-034"),world(Vector2(2000,2000)))
	check(str(app.core.request({"op":"save","serialized":true}).serialized)==initial,"invalid deployment gesture cannot alter native world")
	check(events.any(func(row):return row.kind=="drag_rejected" and not bool(row.data.get("accepted",true))),"invalid deployment has an explicit rejection")
	# The original World gun/torpedo drag gestures consume the actual registered mounts.
	app.sea.weapon_order.connect(func(command):weapon_requests.append(command.duplicate(true)))
	var contact:Dictionary=app.core.view.contacts[0]
	var destroyer:Dictionary=app.core.view.ships.filter(func(row):return str(row.characterId)=="IBS-U-USN-FLETCHER")[0]
	naval.select("ship",destroyer);await frames()
	var torpedo_range:float=float(destroyer.get("torpedoRange",0))
	var destroyer_position:=Vector2(float(destroyer.x),float(destroyer.y));var contact_position:=Vector2(float(contact.x),float(contact.y))
	if destroyer_position.distance_to(contact_position)>torpedo_range:
		var destination:Vector2=destroyer_position.move_toward(contact_position,destroyer_position.distance_to(contact_position)-torpedo_range*.82)
		var approach:Dictionary=app.core.request({"op":"preview_route","fleet":int(destroyer.fleet),"mode":"follow","speed":30,"points":[{"x":destination.x,"y":destination.y}]})
		if check(approach.get("ok",false) and approach.get("data",{}).get("valid",false),"true-scale torpedo approach has a real legal naval route"):
			naval.cruise=30;naval.choose_route("follow");await _click_world(destination);naval.commit_route()
			for i in range(3000):
				var live_ships:Array=app.core.view.ships.filter(func(row):return int(row.id)==int(destroyer.id))
				var live_contacts:Array=app.core.view.contacts.filter(func(row):return str(row.id)==str(contact.id))
				if not check(not live_ships.is_empty() and not live_contacts.is_empty(),"real torpedo approach retains a live shooter and target"):return finish()
				destroyer=live_ships[0];contact=live_contacts[0]
				if Vector2(float(destroyer.x),float(destroyer.y)).distance_to(Vector2(float(contact.x),float(contact.y)))<=torpedo_range*.9:break
				await advance(.1)
		check(Vector2(float(destroyer.x),float(destroyer.y)).distance_to(Vector2(float(contact.x),float(contact.y)))<=torpedo_range,"Fletcher truly sails into her unchanged native torpedo range")
		app.issue({"op":"speed","fleet":int(destroyer.fleet),"speed":0});naval.select("ship",destroyer);await frames()
	check(not destroyer.systems.radars.is_empty() and float(destroyer.get("radarRange",0))>0,"original Fletcher radar equipment and actual radar range remain available")
	if not destroyer.systems.radars.is_empty():
		var radar:Dictionary=destroyer.systems.radars[0]
		naval.radar_dialog();await frames()
		var toggle:Button=_button_text("关闭 "+str(radar.name))
		if check(toggle!=null,"original radar dialog exposes its actual powered device"):
			await click(toggle)
			var current_ship:Dictionary=app.core.view.ships.filter(func(row):return int(row.id)==int(destroyer.id))[0]
			check(not current_ship.systems.radars[0].powered,"actual radar pointer really powers off the registered device")
			naval.radar_dialog();await frames();toggle=_button_text("开启 "+str(radar.name))
			if check(toggle!=null,"original radar dialog exposes the actual power-on action"):await click(toggle)
			current_ship=app.core.view.ships.filter(func(row):return int(row.id)==int(destroyer.id))[0]
			check(current_ship.systems.radars[0].powered,"actual radar pointer powers the same device back on")
		naval.show_tab("ship");await shot("actual-original-radar-and-ship-status");naval.hud.set_drawer(false)
	var torpedo_before:int=int(destroyer.ammo)
	await _weapon_drag(destroyer,contact,"torpedo")
	check(weapon_requests.any(func(row):return row.weapon=="torpedo"),"original torpedo badge pointer issues the real salvo")
	check(int(app.core.view.ships.filter(func(row):return int(row.id)==int(destroyer.id))[0].ammo)<torpedo_before,"real torpedo mount loses its fired rounds")
	var carrier:Dictionary=app.core.view.ships.filter(func(row):return str(row.characterId)=="CAS-H-USN-ENTERPRISE-1942")[0]
	naval.select("ship",carrier);await frames();await _weapon_drag(carrier,contact,"gun")
	check(weapon_requests.any(func(row):return row.weapon=="gun"),"original gun badge pointer submits real World gunnery")
	await advance(5)
	check(torpedo_peak>0,"native World actually advances fired torpedoes")
	check(shell_peak>0 and not naval_shots.is_empty(),"actual World cannon shells retain their original projectile presentation stream")
	FileAccess.open(output_dir+"naval-fired.json",FileAccess.WRITE).store_string(JSON.stringify({"weapons":weapon_requests,"shots":naval_shots,"shell_peak":shell_peak,"torpedo_peak":torpedo_peak},"  "))
	await shot("actual-world-gun-and-torpedo")
	var beach:Dictionary=app.core.view.littoral.beaches[1];var landing:=Vector2(float(beach.land.x),float(beach.land.y))
	await drag(card("Unit_MCP-034"),world(landing))
	check(event_seen("deploy_queued"),"real tactical card queues actual carrier deployment")
	check(str(find_group("MCP-034").stage)!="ground","accepted deployment does not teleport the company ashore")
	await drag(card("Unit_MCP-001"),world(landing),true)
	check(str(find_group("MCP-001").transport_kind)=="helicopter","airborne company keeps the native carrier-qualified air transport")
	for i in range(400):
		if str(find_group("MCP-034").stage)=="ground" and str(find_group("MCP-001").stage)=="ground":break
		await advance(.1)
	check(str(find_group("MCP-034").stage)=="ground" and str(find_group("MCP-001").stage)=="ground","both real boat and helicopter companies land through authority")
	await click(controller().ui.get_node("MiniMap"));await frames()
	var ground:Dictionary=find_group("MCP-034");var origin:=Vector2(float(ground.position.x),float(ground.position.y))
	controller().selected_unit="MCP-034";controller().roster_signature="";app.update_battle();await frames()
	await click(controller().ui.get_node("FocusMap"));await frames()
	var move_target:Vector2=origin
	var land_map=controller().ui.get_node("LandWindow/Map")
	var elevation_error:float=0
	for row in app.core.view.littoral.land.entities:elevation_error=maxf(elevation_error,absf(land_map._height_at(Vector2(float(row.x),float(row.y)))-float(row.get("elevation_m",0))))
	check(elevation_error<.02,"actual native entities and visual terrain share the same continuous elevation")
	for offset in [Vector2(150,0),Vector2(0,150),Vector2(-150,0),Vector2(0,-150),Vector2(200,-100),Vector2(-200,-200)]:
		var candidate:Vector2=origin+offset
		var screen_target:Vector2=land_map.project(candidate)
		if controller()._island_contains(candidate) and not controller()._ground_blocked(candidate) and Rect2(Vector2(40,150),land_map.size-Vector2(400,180)).has_point(screen_target) and land_map.target_at(screen_target).is_empty():move_target=candidate;break
	check(move_target!=origin,"public native ground geometry provides a clear actual movement target")
	await drag(card("Unit_MCP-034"),world(move_target))
	check(str(find_group("MCP-034").order)=="move","isometric pointer inverse issues a real ground movement order")
	await advance(2)
	var current:Dictionary=find_group("MCP-034").position
	check(Vector2(float(current.x),float(current.y)).distance_to(origin)>4,"company truly moves after the isometric drag")
	await shot("actual-isometric-landed-companies")
	check(land_map.zoom>4 and land_map.zoom<=12,"actual street focus reveals the selected company at a local tactical scale")
	check(controller().ui.get_node("FocusMap").text=="概览","street focus has an explicit overview return action")
	await shot("actual-street-focus")
	var camera_state:Dictionary=controller().serialize_ui_state()
	controller().restore_ui_state(camera_state);await frames()
	check(is_equal_approx(land_map.zoom,float(camera_state.land_view.zoom)),"restoring UI retains actual street camera magnification")
	await click(controller().ui.get_node("FocusMap"));check(is_equal_approx(land_map.zoom,1),"overview pointer restores true full-island fit")
	var before_return:Array=app.core.view.littoral.get("corpses",[]).filter(func(row):return str(row.unit_id)=="MCP-001").map(func(row):return int(row.id))
	check(app.issue({"op":"littoral_order","unit_id":"MCP-001","action":"retreat"}).get("ok",false),"normal airborne recovery order is genuinely accepted")
	for i in range(600):
		if str(find_group("MCP-001").stage)=="recovered":break
		await advance(.1)
	check(str(find_group("MCP-001").stage)=="recovered","actual airborne company safely boards its own carrier")
	var after_return:Array=app.core.view.littoral.get("corpses",[]).filter(func(row):return str(row.unit_id)=="MCP-001").map(func(row):return int(row.id))
	check(before_return==after_return,"normal return does not create any authoritative or visual false casualty")
	await click(controller().ui.get_node("MiniMap"));await frames()
	var squadron:Dictionary=app.core.view.littoral.aviation.squadrons[0]
	var aircraft_card:Control=card("Squadron_"+str(squadron.id))
	check(aircraft_card!=null,"real registered squadron has a distinct draggable card")
	if aircraft_card!=null:
		var target:Vector2=point+Vector2(1000,0)
		var selected_company:String=controller().selected_unit
		await drag(aircraft_card,world(target))
		check(event_seen("squadron_ordered"),"actual pointer accepts a native squadron order")
		check(controller().selected_unit==selected_company,"aircraft task preserves the independently selected ground company")
		await advance(3)
		check(not app.core.view.littoral.aviation.aircraft.is_empty(),"accepted order produces real flying aircraft")
		await shot("actual-aircraft-flight")
		var recall:Dictionary=app.issue({"op":"littoral_air_order","squadron_id":str(squadron.id),"action":"return"})
		check(recall.get("ok",false),"actual aircraft recall is accepted by authority")
		for i in range(300):
			if app.core.view.littoral.aviation.aircraft.is_empty():break
			await advance(.1)
		check(app.core.view.littoral.aviation.aircraft.is_empty(),"actual aircraft return to the registered carrier rather than disappear on command")
	var saved:String=app.core.request({"op":"save","serialized":true}).serialized
	var ui_state:Dictionary=controller().serialize_ui_state()
	app.core.close();check(app.core.request({"op":"load","serialized":saved}).get("ok",false),"actual v4 World and aircraft restore through a new native process")
	controller().restore_ui_state(ui_state);app.update_battle();await frames()
	check(str(app.core.request({"op":"save","serialized":true}).serialized)==saved,"UI restore never alters real World aircraft or landed forces")
	FileAccess.open(output_dir+"runtime.json",FileAccess.WRITE).store_string(JSON.stringify(runtime_info(),"  "))
	finish()
func _button_text(text:String)->Button:
	for node in app.find_children("*","Button",true,false):
		if node.text==text and node.is_visible_in_tree():return node
	return null
func _weapon_drag(ship:Dictionary,contact:Dictionary,weapon:String)->void:
	var start:Vector2=world(Vector2(float(ship.x),float(ship.y)))+app.sea.get_global_transform_with_canvas().basis_xform(Vector2(-24 if weapon=="gun" else 24,-48))
	var end:Vector2=world(Vector2(float(contact.x),float(contact.y)))
	var down:=InputEventMouseButton.new();down.position=screen_point(start);down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;Input.parse_input_event(down);inputs+=1;await process_frame
	for i in range(1,9):
		var move:=InputEventMouseMotion.new();move.position=screen_point(start.lerp(end,float(i)/8));move.button_mask=MOUSE_BUTTON_MASK_LEFT;move.relative=screen_point((end-start)/8);Input.parse_input_event(move);inputs+=1;await process_frame
	if weapon=="torpedo":await create_timer(.35).timeout;await frames()
	var up:=InputEventMouseButton.new();up.position=screen_point(end);up.button_index=MOUSE_BUTTON_LEFT;Input.parse_input_event(up);inputs+=1;await frames()
func _click_world(point:Vector2)->void:
	var at:Vector2=screen_point(world(point))
	var down:=InputEventMouseButton.new();down.position=at;down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;Input.parse_input_event(down);await process_frame
	var up:=InputEventMouseButton.new();up.position=at;up.button_index=MOUSE_BUTTON_LEFT;Input.parse_input_event(up);inputs+=2;await frames()
