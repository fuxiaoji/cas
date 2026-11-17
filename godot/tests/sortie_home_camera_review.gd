extends SceneTree
var OUTPUT:String="res://../artifacts/godot/sortie-home-camera-20261114/"
var app
var checks:int=0
var failures:Array[String]=[]
var screenshots:Array=[]
var user_hash:String
var backup_hash:String
var camera_clicks:int=0
func _initialize()->void:
	var requested:String=OS.get_environment("CAS_SORTIE_REVIEW_OUTPUT")
	if not requested.is_empty():OUTPUT=requested.trim_suffix("/")+"/"
	call_deferred("run")
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func frames(count:int=3)->void:
	for index in range(count):await process_frame
func location(node:Control,point:Vector2)->Vector2:return node.get_viewport().get_screen_transform()*(node.get_global_transform_with_canvas()*point)
func click(node:Control)->void:
	var point:Vector2=location(node,node.size*.5)
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;Input.parse_input_event(event);await process_frame
	await frames()
func drag(source:Control,target:Control)->void:
	var start:Vector2=location(source,source.size*.5);var end:Vector2=location(target,target.size*.5)
	await drag_between(start,end)
func drag_between(start:Vector2,end:Vector2)->void:
	var press:=InputEventMouseButton.new();press.position=start;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;Input.parse_input_event(press);await frames(2)
	var previous:Vector2=start
	for index in range(1,12):
		var point:Vector2=start.lerp(end,float(index)/11);var motion:=InputEventMouseMotion.new();motion.position=point;motion.relative=point-previous;motion.button_mask=MOUSE_BUTTON_MASK_LEFT;Input.parse_input_event(motion);previous=point;await process_frame
	await frames(2);var release:=InputEventMouseButton.new();release.position=end;release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;Input.parse_input_event(release);await frames(4)
func touch_drag(source:Control,target:Control)->void:
	var start:Vector2=location(source,source.size*.5);var end:Vector2=location(target,target.size*.5)
	var touch:=InputEventScreenTouch.new();touch.index=0;touch.position=start;touch.pressed=true;Input.parse_input_event(touch);await frames(2)
	var previous:Vector2=start
	for index in range(1,10):
		var point:Vector2=start.lerp(end,float(index)/9);var motion:=InputEventScreenDrag.new();motion.index=0;motion.position=point;motion.relative=point-previous;Input.parse_input_event(motion);previous=point;await process_frame
	touch=InputEventScreenTouch.new();touch.index=0;touch.position=end;touch.pressed=false;Input.parse_input_event(touch);await frames(4)
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await frames();await RenderingServer.frame_post_draw
	var path:String=ProjectSettings.globalize_path(OUTPUT+name+".png");check(root.get_texture().get_image().save_png(path)==OK,"GPU screenshot "+name);screenshots.append(path)
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT));user_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	var path:String=OUTPUT+"isolated-%d.json"%OS.get_process_id();var account=load("res://scripts/economy.gd").new(path);check(account.new_profile().ok,"isolated profile created")
	account.state.progression.first_voyage_canon.active=false
	var ids:Array=["IBS-U-USN-ERMA-MISSOURI","IBS-U-USN-HELENA"]
	for row in account.catalog:
		if ids.size()>=9:break
		if row.get("playable",false) and not row.has("special_mode_scope") and not ids.has(str(row.id)):ids.append(str(row.id))
	for id in ids:account.state.owned[id]=account._new_owned(id);account.state.owned[id].ammo=100;account.state.owned[id].level=30
	for key in account.state.wallet:account.state.wallet[key]=1000000
	account.state.fleet_book=[{"id":"qa-alpha","name":"第一测试编队","ships":ids.slice(0,4)},{"id":"qa-bravo","name":"第二测试编队","ships":ids.slice(4,7)}];account.state.active_fleet_id="qa-alpha";account.state.sortie_fleet_ids=["qa-alpha","qa-bravo"];account.state.formation=ids.slice(0,7);account.formation.assign(account.state.formation)
	var home=load("res://scripts/home_service.gd").new(account);home.state().unlocked=true;home.state().tutorial_complete=true;home.state().drag_tutorial_completed=true;home.state().garrison=ids.slice(0,2)
	for id in ["MCP-034","MCP-001","MCP-022"]:home._own_unit(id)
	load("res://scripts/ship_appearance_service.gd").new(account).choose(ids[0],"military");check(account.save_state().ok,"only isolated fixture saved")
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.deferred_startup=false;app.staged_navigation=false;app.economy=account;app.fullscreen_battle=false
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames(8);app.page_motion=false;app.page_transition.cancel();AudioServer.set_bus_mute(0,true)
	app.show_page("formation");await frames(5)
	var composer=app.page.find_child("SortieFormation",true,false);check(composer!=null,"production Main uses independent new composer")
	if composer==null:return finish()
	var wallet_before:Dictionary=account.state.wallet.duplicate(true);var stamina_before:int=int(account.wallet().stamina)
	check(composer.current.ships.size()==4,"four-ship current fleet is not capped at three");check(account.formation.size()==7,"multiple real selected fleets merge uniquely")
	var member:String=ids[3];await click(composer.find_child("FleetMember_"+member,true,false));check(not app.fleets.active().ships.has(member),"actual mouse removes selected member")
	await drag(composer.find_child("Available_"+member,true,false),composer.find_child("AddFleetMember",true,false));check(app.fleets.active().ships.has(member),"actual native drag adds owned member")
	await drag(composer.find_child("FleetMember_"+member,true,false),composer.find_child("RemoveMemberDropZone",true,false));check(not app.fleets.active().ships.has(member),"actual native drag removes member to bank")
	composer._add(member);await frames();check(account.state.wallet==wallet_before and int(account.wallet().stamina)==stamina_before,"editing and previews never consume resources")
	composer._add(ids[4]);await frames();check(not app.fleets.active().ships.has(ids[4]) and account.formation.size()==7,"real FleetManager rejects duplicate ships across selected fleets")
	await touch_drag(composer.find_child("Available_"+ids[8],true,false),composer.find_child("AddFleetMember",true,false));check(app.fleets.active().ships.has(ids[8]),"actual touch drag adds a ship without mouse emulation dependency");composer._remove(ids[8])
	for dimensions in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=dimensions;await frames(5);check(composer.launch.get_global_rect().end.y<=850,"launch remains inside logical viewport "+str(dimensions));await shot("formation-%dx%d"%[dimensions.x,dimensions.y])
	composer._army();await frames();var saved:Dictionary=account.state.get("amphibious_expedition_v1",{}).duplicate(true)
	await click(app.modal.find_child("ArmyUnit_MCP-001",true,false));await click(app.modal.find_child("Embark_MCP-001-C01",true,false));check(app.modal.find_child("SaveArmyLoadout",true,false).disabled,"air company cannot embark on ordinary battleship")
	app.close_modal();check(account.state.get("amphibious_expedition_v1",{})==saved and account.state.wallet==wallet_before,"cancel changed land draft neither saves nor charges")
	composer._army();await frames();await click(app.modal.find_child("ArmyUnit_MCP-034",true,false));await click(app.modal.find_child("Embark_MCP-034-C01",true,false))
	check(not app.modal.find_child("SaveArmyLoadout",true,false).disabled,"ordinary marine company fits actual selected battleship")
	await shot("army-company-loadout");await click(app.modal.find_child("SaveArmyLoadout",true,false))
	check(account.state.get("amphibious_expedition_v1",{}).get("companies",[]).size()==1 and account.state.wallet==wallet_before,"save exact one-company transport plan without spending resources")
	app.show_page("home");await frames(6);var island=app.page.find_child("HomeIsland",true,false)
	check(island.ship_residents.size()==2,"exact garrison naval residents appear on island")
	var resident=island.ship_residents[ids[0]].actor;check(str(resident.card.id)==ids[0] and str(resident.card.appearance_id)=="military","resident uses own currently selected military art")
	await click(resident);check(resident.greeting_until>resident.clock,"real pointer greets garrison shipgirl without modal")
	check(account.state.wallet==wallet_before,"resident greetings are visual only");await shot("garrison-shipgirls")
	var before_home_sortie:Dictionary=account.state.wallet.duplicate(true);island._sortie();await frames();check(app.modal.find_child("SavedDeploymentFleet",true,false)!=null,"home sortie can select a genuine saved fleet")
	await shot("home-amphibious-deployment");app.close_modal();check(account.state.wallet==before_home_sortie,"cancel home deployment consumes no ammunition")
	check(home.set_garrison([ids[1]]).get("ok",false),"isolated garrison roster can change");island.refresh();check(island.ship_residents.size()==1 and not island.ship_residents.has(ids[0]),"removed naval resident leaves island immediately")
	home.set_garrison(ids.slice(0,2));load("res://scripts/ship_appearance_service.gd").new(account).choose(ids[0],"base");load("res://scripts/ship_appearance_service.gd").refresh(app);island.refresh();check(str(island.ship_residents[ids[0]].actor.card.appearance_id)=="base","existing garrison refresh follows same-person outfit changes")
	# A standalone real production land map receives synthetic viewport input.
	app.page.visible=false;var ground=load("res://scripts/littoral_land.gd").new();ground.name="CameraReview";ground.size=Vector2(1280,720);root.add_child(ground)
	ground.land={"persistent_corpses":true,"bounds":{"x":0,"y":0,"width":6000,"height":5000},"polygon":[{"x":500,"y":600},{"x":5500,"y":500},{"x":5700,"y":4300},{"x":400,"y":4400}],"entities":[],"terrain":{}}
	ground.point_selected.connect(func(_point,_target,_kind):camera_clicks+=1);await frames()
	for dimensions in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=dimensions;ground.size=Vector2(1600,900);ground.reset_camera();await frames(3)
		var anchor:Vector2=ground.size*Vector2(.55,.55);var original:Vector2=ground.unproject_base(anchor)
		for pressed in [true,false]:
			var wheel:=InputEventMouseButton.new();wheel.position=location(ground,anchor);wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.pressed=pressed;Input.parse_input_event(wheel);await process_frame
		check(ground.zoom>1,"real wheel zooms land "+str(dimensions));check(ground.unproject_base(anchor).distance_to(original)<.01,"zoom stays anchored at cursor "+str(dimensions))
		ground.zoom_at(2,ground.size*.5);var before:Vector2=ground.camera_center;var clicks_before:int=camera_clicks
		await drag(ground,ground) # No distance remains a tap, deliberately.
		check(camera_clicks==clicks_before+1,"tap still selects only on release")
		await drag_between(location(ground,anchor),location(ground,anchor+Vector2(90,65)));check(ground.camera_center.distance_to(before)>1,"real viewport drag pans after threshold");check(camera_clicks==clicks_before+1,"map pan never sends an attack/move click")
		var view:Dictionary={"zoom":ground.zoom,"center":ground.camera_center};ground.set_miniature(true);ground.set_miniature(false);check(ground.zoom==view.zoom and ground.camera_center==view.center,"main/minimap swap preserves camera")
		ground.show_drag_target=true;var blocked_zoom:float=ground.zoom;ground.zoom_at(1.5,anchor);check(ground.zoom==blocked_zoom,"troop drag preview cannot pan/zoom map");ground.show_drag_target=false
		await shot("land-camera-%dx%d"%[dimensions.x,dimensions.y])
	# Touch pinch tests use the same production _gui_input routing, no world commands.
	var center:Vector2=ground.size*.5;var zoom_before:float=ground.zoom
	for index in range(2):
		var touch:=InputEventScreenTouch.new();touch.index=index;touch.position=location(ground,center+Vector2((index*2-1)*50,0));touch.pressed=true;Input.parse_input_event(touch);await process_frame
	for index in range(2):
		var motion:=InputEventScreenDrag.new();motion.index=index;motion.position=location(ground,center+Vector2((index*2-1)*100,0));Input.parse_input_event(motion);await process_frame
	for index in range(2):
		var touch:=InputEventScreenTouch.new();touch.index=index;touch.position=location(ground,center);touch.pressed=false;Input.parse_input_event(touch);await process_frame
	check(ground.zoom>zoom_before,"two-finger pinch magnifies production land map")
	var home_key:=InputEventKey.new();home_key.keycode=KEY_HOME;home_key.pressed=true;Input.parse_input_event(home_key);await process_frame;check(ground.zoom==1,"keyboard focus camera reset")
	var joy:=InputEventJoypadButton.new();joy.button_index=JOY_BUTTON_RIGHT_SHOULDER;joy.pressed=true;ground._gui_input(joy);check(ground.zoom>1,"focused controller shoulder zoom")
	ground.queue_free();app.page.visible=true;await frames()
	var preview:Dictionary=account.preview_sortie(20261114,false,{"kind":"salvage","id":"calm"});check(preview.get("ok",false),"real sortie preview validates full plan")
	check(preview.get("amphibious_expedition",{}).get("companies",[]).size()==1,"native sortie plan contains exact chosen marine company")
	var exact_ammo:int=0
	for ship in preview.get("fleet",[]):exact_ammo+=int(ship.ammo)
	var before_launch:Dictionary=account.state.wallet.duplicate(true);var before_energy:int=int(account.wallet().stamina)
	await app.launch(false,{"kind":"salvage","id":"calm"});await frames(5)
	check(not account.state.active_run.is_empty() and app.screen=="battle","actual Main launch enters real naval simulation")
	check(int(account.state.wallet.ammo_stock)==int(before_launch.ammo_stock)-exact_ammo,"only launch debits previewed real ammunition")
	check(int(account.state.wallet.fuel)==int(before_launch.fuel)-int(preview.get("fuel_v1",{}).get("initial",0)),"only launch debits previewed real fuel")
	check(int(account.wallet().stamina)==before_energy-int(preview.get("mission",{}).get("cost_stamina",0)),"only launch debits previewed real stamina")
	finish()
func finish()->void:
	if is_instance_valid(app):app.core.close()
	check(FileAccess.get_sha256("user://cas_port_v1.json")==user_hash and FileAccess.get_sha256("user://cas_port_v1.json.bak")==backup_hash,"formal account and backup unchanged")
	var receipt:Dictionary={"checks":checks,"failures":failures,"screenshots":screenshots,"scope":"actual isolated GPU inputs, native fleet ledger, production land camera"};FileAccess.open(OUTPUT+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(receipt,"  "));print("SORTIE_HOME_CAMERA ",JSON.stringify(receipt));quit(0 if failures.is_empty() else 1)
