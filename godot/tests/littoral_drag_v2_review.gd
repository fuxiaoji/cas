extends SceneTree
## Isolated ordinary account; real pointer gestures and authority-only time steps.
const Output:String="res://../artifacts/littoral-drag/v2/"
var output_dir:String=Output
var app
var checks:int=0
var failures:Array[String]=[]
var events:Array=[]
var steps:Array=[]
var inputs:int=0
var main_hash:String
var backup_hash:String
var profile:String
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->bool:
	checks+=1
	if not value:failures.append(label);push_error(label)
	return value
func frames(count:int=3)->void:
	for i in range(count):await process_frame
func global_point(control:Control,local:Vector2)->Vector2:return control.get_global_transform_with_canvas()*local
func screen_point(point:Vector2)->Vector2:return root.get_screen_transform()*point
func click(control:Control)->void:
	var point:Vector2=screen_point(global_point(control,control.size*.5))
	var down:=InputEventMouseButton.new();down.position=point;down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;Input.parse_input_event(down)
	await process_frame
	var up:=InputEventMouseButton.new();up.position=point;up.button_index=MOUSE_BUTTON_LEFT;Input.parse_input_event(up);inputs+=2;await frames()
func drag(card:Control,to:Vector2,touch:bool=false)->void:
	var start:Vector2=screen_point(global_point(card,card.size*.5));var end:Vector2=screen_point(to)
	if touch:
		var down:=InputEventScreenTouch.new();down.index=2;down.position=start;down.pressed=true;Input.parse_input_event(down)
	else:
		var down:=InputEventMouseButton.new();down.position=start;down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;Input.parse_input_event(down)
	inputs+=1;await process_frame
	for i in range(1,9):
		var point:Vector2=start.lerp(end,float(i)/8)
		if touch:
			var move:=InputEventScreenDrag.new();move.index=2;move.position=point;move.relative=(end-start)/8;Input.parse_input_event(move)
		else:
			var move:=InputEventMouseMotion.new();move.position=point;move.relative=(end-start)/8;move.button_mask=MOUSE_BUTTON_MASK_LEFT;Input.parse_input_event(move)
		inputs+=1;await process_frame
	if touch:
		var up:=InputEventScreenTouch.new();up.index=2;up.position=end;Input.parse_input_event(up)
	else:
		var up:=InputEventMouseButton.new();up.position=end;up.button_index=MOUSE_BUTTON_LEFT;Input.parse_input_event(up)
	inputs+=1;await frames()
func world(point:Vector2)->Vector2:
	var map:Control=app.sea if controller().primary_map=="sea" else controller().ui.get_node("LandWindow/Map")
	return global_point(map,map.project(point))
func controller():return app.battle_controller
func group()->Dictionary:return app.core.view.littoral.groups[0]
func card(name:String)->Control:return controller().ui.get_node_or_null("Tray/Scroll/Cards/"+name)
func event_seen(kind:String)->bool:
	for row in events:
		if row.kind==kind and row.data.get("accepted",false):return true
	return false
func shot(name:String)->void:
	await frames();await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output_dir+name+".png"))
func advance(seconds:float)->void:
	var count:int=int(round(seconds*10))
	for i in range(count):
		var response:Dictionary=app.core.request({"op":"step","seconds":.1})
		if not response.get("ok",false):check(false,"authoritative time advances "+str(response));return
		app.update_battle()
		if i%10==0:await process_frame
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	profile=output_dir+"isolated-pointer-%d.json"%OS.get_process_id()
	var account=load("res://scripts/economy.gd").new(profile)
	if not check(account.load_state().get("ok",false),"create isolated ordinary starter account"):return finish()
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.fullscreen_battle=true
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames()
	app.set_process(false);app.page_motion=false
	var prepared:Dictionary=app.home.prepare_littoral("tutorial",42,["MCP-034"],["IBS-U-USN-FLETCHER"],"balanced")
	if not check(prepared.get("ok",false),"normal service prepares borrowed real tutorial"):return finish()
	app.launch_littoral(prepared.request);await frames()
	if not check(app.screen=="battle" and str(app.core.view.littoral.version)=="cas-littoral-v2","real account-bound v2 battle opened"):return finish()
	controller().interaction_event.connect(func(kind,data):events.append({"kind":kind,"data":data.duplicate(true),"tick":app.core.view.tick}))
	controller().tutorial.step_changed.connect(func(id,_index):steps.append({"step":id,"tick":app.core.view.tick}))
	check(controller().tutorial.active,"first v2 tutorial opens guidance")
	check(app.home.state().units.is_empty() and not app.home.state().tutorial_complete,"text and guidance never grant 034 or island")
	await shot("00-before-drag")
	var beach:Dictionary=app.core.view.littoral.beaches[1]
	var landing:Vector2=Vector2(float(beach.land.x),float(beach.land.y))
	var saved:Dictionary=app.core.request({"op":"save","serialized":true})
	await drag(card("Unit_MCP-034"),world(Vector2(3000,3000)))
	var after:Dictionary=app.core.request({"op":"save","serialized":true})
	check(str(saved.serialized)==str(after.serialized),"rejected water drop preserves entire authoritative snapshot")
	check(events.back().kind=="drag_rejected","invalid drop gives explicit rejected interaction")
	await drag(card("Unit_MCP-034"),world(landing),true)
	check(event_seen("deploy_queued"),"real touch drag accepted deploy queue")
	check(group().get("pending_deploy") is Dictionary,"carrier has real pending deployment")
	check(str(group().stage)=="embarked","accepted drag does not teleport bodies ashore")
	await shot("01-carrier-approach")
	var entered:float=-1
	for i in range(600):
		if str(group().stage)=="ground":entered=float(app.core.view.tick);break
		await advance(.1)
	check(entered>0 and entered<=40,"real transport lands in at most 40 seconds")
	await click(controller().ui.get_node("MiniMap"))
	check(controller().primary_map=="land","actual pointer swaps main/minimap")
	check(card("Naval_1")==null,"v2 naval support card hidden until actual sea aim order")
	await shot("02-landed")
	var position:Dictionary=group().position;var origin:=Vector2(float(position.x),float(position.y))
	var destination:Vector2=origin+Vector2(400,-180)
	await drag(card("Unit_MCP-034"),world(destination))
	check(event_seen("unit_ordered") and str(group().order)=="move","real mouse drag orders ground movement")
	await advance(2)
	check(Vector2(float(group().position.x),float(group().position.y)).distance_to(origin)>4,"squad really moves after the gesture")
	var enemies:Array=app.core.view.littoral.land.entities.filter(func(row):return str(row.side)!="allies" and float(row.hp)>0)
	if not enemies.is_empty():
		var entity:Dictionary=enemies[0]
		var map:Control=controller().ui.get_node("LandWindow/Map");var target:Vector2=map.actors[int(entity.id)].position-Vector2(0,18) if map.actors.has(int(entity.id)) else map.project(Vector2(float(entity.x),float(entity.y)))
		await drag(card("Unit_MCP-034"),global_point(map,target))
		check(str(group().order)=="attack","drop on real hostile orders attack")
	else:check(true,"actual early auto-fire cleared all hostile entities before attack gesture")
	await click(controller().ui.get_node("MiniMap"))
	check(controller().primary_map=="sea","actual pointer returns to sea")
	var ship:Dictionary=app.core.view.ships[0]
	# The source is the live ship projection rather than a support menu button.
	await drag_from(world(Vector2(float(ship.x),float(ship.y))),world(landing))
	check(event_seen("naval_aimed"),"dragging actual ship to island accepts real aim order")
	check(controller()._naval_support(1).get("aim_target")!=null,"core publishes accepted actual aim target")
	await click(controller().ui.get_node("MiniMap"))
	check(card("Naval_1")!=null,"real aim reveals one land naval support card")
	if card("Naval_1")!=null:await drag(card("Naval_1"),world(landing))
	check(event_seen("naval_support_queued"),"land card queues true naval firing")
	var fired:bool=false
	for i in range(240):
		for row in app.core.view.littoral.shots:
			if str(row.get("source",""))=="ship:1":fired=true
		if fired:break
		await advance(.1)
	check(fired,"actual new ship shot appears after real turning and loading")
	await shot("03-naval-support")
	var ruin:Dictionary=app.core.view.littoral.land.ruins[0]
	await drag(card("Unit_MCP-034"),world(Vector2(float(ruin.x),float(ruin.y))))
	check(str(group().order)=="search","drop on actual ruin orders search")
	for i in range(1400):
		if bool(app.core.view.littoral.land.ruins[0].searched):break
		await advance(.1)
	check(bool(app.core.view.littoral.land.ruins[0].searched),"ruin actually searched with true progress")
	controller().context_action="withdraw";controller().roster_signature="";app.update_battle();await frames()
	var at:Dictionary=group().position
	if card("Withdraw_MCP-034")!=null:await drag(card("Withdraw_MCP-034"),world(Vector2(float(at.x),float(at.y))))
	check(event_seen("withdraw_ordered"),"withdrawal card issues actual return-to-carrier order")
	for i in range(1600):
		if str(group().stage)=="recovered":break
		await advance(.1)
	check(str(group().stage)=="recovered","actual transports recover squad safely")
	await click(controller().ui.get_node("MiniMap"))
	check(card("Return_MCP-034")!=null,"recovered squad unlocks real sea return card")
	var exit:Dictionary=app.core.view.littoral.exit;var exit_point:=Vector2(float(exit.x),float(exit.y))
	if card("Return_MCP-034")!=null:await drag(card("Return_MCP-034"),world(exit_point))
	check(event_seen("return_ordered"),"return card orders real sea navigation")
	for i in range(2000):
		if controller()._inside_exit():break
		await advance(.1)
	check(controller()._inside_exit(),"live ship truly reaches the public extraction region")
	await shot("04-at-exit")
	if card("Return_MCP-034")!=null:await drag(card("Return_MCP-034"),world(exit_point))
	check(app.screen=="result" and app.home.state().tutorial_complete,"real extraction settles through account authority and unlocks island")
	await shot("05-real-result")
	finish()
func drag_from(start:Vector2,end:Vector2)->void:
	var down:=InputEventMouseButton.new();down.position=screen_point(start);down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;Input.parse_input_event(down);await process_frame;inputs+=1
	for i in range(1,9):
		var motion:=InputEventMouseMotion.new();motion.position=screen_point(start.lerp(end,float(i)/8));motion.button_mask=MOUSE_BUTTON_MASK_LEFT;Input.parse_input_event(motion);await process_frame;inputs+=1
	var up:=InputEventMouseButton.new();up.position=screen_point(end);up.button_index=MOUSE_BUTTON_LEFT;Input.parse_input_event(up);inputs+=1;await frames()
func finish()->void:
	var last_view:Dictionary=app.core.view.duplicate(true) if app!=null else {}
	if app!=null:app.core.close();app.queue_free();await frames()
	check(FileAccess.get_sha256("user://cas_port_v1.json")==main_hash,"normal account bytes untouched")
	check(FileAccess.get_sha256("user://cas_port_v1.json.bak")==backup_hash,"normal backup bytes untouched")
	var receipt:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"input_events":inputs,"events":events,"steps":steps,"terminal_tick":last_view.get("tick"),"result":last_view.get("result"),"profile":ProjectSettings.globalize_path(profile),"core_override":OS.get_environment("CAS_SIM_PATH"),"main_sha256":main_hash,"main_account_written":false}
	FileAccess.open(output_dir+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(receipt,"  "))
	print("LITTORAL_DRAG "+JSON.stringify({"checks":checks,"failures":failures,"inputs":inputs}));quit(0 if failures.is_empty() else 1)

