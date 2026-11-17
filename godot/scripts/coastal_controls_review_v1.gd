extends SceneTree
## Actual Main and real core, isolated account. Pointer input drives the new controls.
const ROOT:String="res://../artifacts/coastal-controls-20261116/"
var app:Control
var checks:int=0
var inputs:int=0
var failures:Array[String]=[]
var evidence:Array=[]
var normal:Dictionary={}
var commands:Array=[]
var ui_events:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func frames(count:int=2)->void:
	for i:int in range(count):await process_frame
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
func inject(event:InputEvent)->void:root.push_input(event,true);inputs+=1;await frames()
func click_point(point:Vector2)->void:
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;await inject(motion)
	for pressed:bool in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;await inject(event)
func click(node:Control)->void:await click_point(node.get_global_rect().get_center())
func drag(from:Vector2,to:Vector2,cancel:bool=false)->void:
	var down:=InputEventMouseButton.new();down.position=from;down.global_position=from;down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;await inject(down)
	var previous:Vector2=from
	for index:int in range(1,7):
		var point:Vector2=from.lerp(to,float(index)/6);var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;motion.relative=point-previous;motion.button_mask=MOUSE_BUTTON_MASK_LEFT;await inject(motion);previous=point
	if cancel:
		var key:=InputEventKey.new();key.keycode=KEY_ESCAPE;key.pressed=true;await inject(key)
	var up:=InputEventMouseButton.new();up.position=to;up.global_position=to;up.button_index=MOUSE_BUTTON_LEFT;up.pressed=false;await inject(up)
func company_card(battle,id:String)->Control:
	for node in battle.ui.get_node("Tray/Scroll/Cards").get_children():
		if str(node.payload.get("company_id",""))==id:return node
	return null
func chip(battle,id:String)->Control:return battle.coastal_commands.find_child("Command_"+id,true,false)
func world_point(map:Control,p:Vector2)->Vector2:return map.get_global_transform()*map.project(p)
func event(kind:String,data:Dictionary)->void:
	ui_events.append({"kind":kind,"reason":str(data.get("reason","")),"command":data.get("command",{})})
	if bool(data.get("accepted",false)) and data.has("command"):commands.append({"kind":kind,"command":data.command})
func screenshot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await frames(3);var path:String=ROOT+name+".png";root.get_texture().get_image().save_png(path);evidence.append(ProjectSettings.globalize_path(path))
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	for name:String in ["cas_port_v1.json","cas_port_v1.json.bak"]:normal[name]=FileAccess.get_sha256("user://"+name)
	var profile:String=ProjectSettings.globalize_path(ROOT+"player-%d.json"%OS.get_process_id());DirAccess.copy_absolute(ProjectSettings.globalize_path("res://../artifacts/coastal-rebuild-20261116/player.json"),profile)
	app=load("res://scenes/main.tscn").instantiate();app.economy=load("res://scripts/economy.gd").new(profile);app.immersive_fullscreen=false;app.boot_to_title=false;app.page_motion=false
	root.size=Vector2i(1600,900);root.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);app.set_meta("reduced_motion",true);app.show_page("home");await frames(5)
	var home=app.page.get_node("HomeIsland")
	await click(home.get_node("Layout/Top/Training"));await click(app.modal.find_child("Lesson-combined_arms",true,false));await frames(5)
	check(app.screen=="battle","real training pointer enters battle")
	if app.screen!="battle":await finish();return
	var battle=app.battle_controller;battle.interaction_event.connect(event);battle.set_primary_map("land");var map=battle.ui.get_node("LandWindow/Map")
	if battle.tutorial!=null and battle.tutorial.active:await click(battle.tutorial._close)
	check(is_instance_valid(battle.coastal_commands),"coastal-only contextual commands present")
	var beach:Dictionary=app.core.view.littoral.beaches[1].land;var shore:=Vector2(float(beach.x),float(beach.y))
	for identity:String in ["MCP-022","MCP-103"]:
		var id:String=identity+"-C01";var card:Control=company_card(battle,id);check(card!=null,"company card "+id)
		if card!=null:
			battle.ui.get_node("Tray/Scroll").ensure_control_visible(card);await frames(3)
			await drag(card.get_global_rect().get_center(),world_point(map,shore));app.running=false
	for step:int in range(240):
		var reply:Dictionary=app.core.request({"op":"step","seconds":5});check(reply.get("ok",false),"native landing step %d"%step)
		var vehicles:Array=app.core.view.littoral.land.get("combat_vehicles",[]).filter(func(v):return str(v.get("side",""))=="allies" and str(v.get("phase","")) in ["active","loading","unloading"])
		if vehicles.any(func(v):return str(v.vehicle_kind)=="tank"):break
	var vehicles:Array=app.core.view.littoral.land.get("combat_vehicles",[]).filter(func(v):return str(v.get("side",""))=="allies" and str(v.get("phase","")) in ["active","loading","unloading"])
	check(not vehicles.is_empty(),"real tank arrived")
	if vehicles.is_empty():
		FileAccess.open(ROOT+"landing-failure.json",FileAccess.WRITE).store_string(JSON.stringify(app.core.view));await finish();return
	var tank:Dictionary=vehicles[0]
	for row:Dictionary in vehicles:
		if str(row.vehicle_kind)=="tank":tank=row
	var first_visibility:Array=app.core.view.littoral.land.get("entities",[]).filter(func(r):return str(r.get("company_id",""))=="MCP-022-C01" and not r.has("vehicle_kind") and r.get("first_visible")!=null)
	if not first_visibility.is_empty():
		check(first_visibility.all(func(r):return float(r.get("disembark_distance_m",99999))<=38.1 and Vector2(float(r.first_visible.x),float(r.first_visible.y)).distance_to(shore)<=12.1),"ordinary heavy-lander first bodies remain within 12m of actual shore and 38m of waterborne hull centre")
		evidence.append({"type":"ordinary_landing_first_visibility","bodies":first_visibility})
	battle.selected_unit=str(tank.company_id);battle.selected_vehicle_id=0;battle.update();map.zoom=2.25;map.camera_center=Vector2(float(tank.x),float(tank.y))+Vector2(25,35);map._sync_world3d_camera();await frames(3)
	await click(chip(battle,"vehicle"));check(battle.selected_vehicle_id==int(tank.id),"click selects independent vehicle")
	check(chip(battle,"fire")!=null and chip(battle,"face")!=null,"explicit fire and facing are separate")
	var at:=Vector2(float(tank.x),float(tank.y));var destination:Vector2=at+Vector2(75,0)
	var acceptable:bool=false
	for offset:Vector2 in [Vector2(75,0),Vector2(-75,0),Vector2(0,75),Vector2(0,-75)]:
		var preview:Dictionary=app.core.request({"op":"littoral_vehicle_preview","vehicle_id":int(tank.id),"action":"move","x":at.x+offset.x,"y":at.y+offset.y})
		if bool(preview.get("data",{}).get("valid",false)):destination=at+offset;acceptable=true;break
	check(acceptable,"native vehicle movement location found")
	var before:int=commands.size();await drag(chip(battle,"move").get_global_rect().get_center(),world_point(map,destination));app.running=false
	check(commands.size()>before and str(commands[-1].command.get("action",""))=="move","drag move commits native vehicle move")
	check(commands.size()>before and at.distance_to(Vector2(float(commands[-1].command.get("x",at.x)),float(commands[-1].command.get("y",at.y))))>30,"movement drop differs from actual current vehicle position")
	before=commands.size();await drag(world_point(map,at),world_point(map,destination));app.running=false
	check(commands.size()>before and str(commands[-1].command.get("action",""))=="move","drag actual map vehicle defaults to move rather than face")
	await click(chip(battle,"face"));check(not battle.coastal_pending.is_empty(),"tap face waits for point")
	await click_point(world_point(map,destination+Vector2(20,0)));app.running=false
	check(not commands.is_empty() and str(commands[-1].command.get("action",""))=="face","tap map commits native facing")
	before=commands.size();await click(chip(battle,"attack"));await click(battle.coastal_commands.cancel_button);check(battle.coastal_pending.is_empty() and commands.size()==before,"cancel aim sends no command")
	await drag(chip(battle,"move").get_global_rect().get_center(),world_point(map,destination),true);check(commands.size()==before,"Escape during drag sends no command")
	var enemies:Array=app.core.view.littoral.land.get("entities",[]).filter(func(r):return str(r.get("side","allies"))!="allies" and float(r.get("hp",0))>0)
	enemies.append_array(app.core.view.littoral.land.get("buildings",[]).filter(func(r):return str(r.get("side","allies"))!="allies" and float(r.get("hp",0))>0))
	var attack_target:Dictionary={}
	for enemy:Dictionary in enemies:
		var preview:Dictionary=app.core.request({"op":"littoral_vehicle_preview","vehicle_id":int(tank.id),"action":"attack","x":float(enemy.x),"y":float(enemy.y)})
		if bool(preview.get("data",{}).get("valid",false)):attack_target=enemy;break
	if not attack_target.is_empty():
		var enemy_point:=Vector2(float(attack_target.x),float(attack_target.y));before=commands.size()
		await drag(chip(battle,"attack").get_global_rect().get_center(),world_point(map,enemy_point));app.running=false
		check(commands.size()>before and str(commands[-1].command.get("action",""))=="attack","drag attack sends actual vehicle attack command")
	else:check(false,"native living attack target available")
	await click(chip(battle,"fire"));before=commands.size();await click_point(world_point(map,destination));app.running=false
	check(commands.size()>before or not str(battle.ui.get_node("Hint").text).is_empty(),"native fire either accepted or explains real unavailable reason")
	battle._coastal_cancel_command(false)
	await click(chip(battle,"body"));check(battle.selected_vehicle_id==0,"body selection switches away from vehicle")
	var ability=chip(battle,"ability");check(ability!=null,"selected company skill visible with real charges")
	if ability!=null:
		check(ability.detail.text.contains("余"),"skill count is readable")
		var charges:int=int(battle._group().get("ability",{}).get("charges",0));before=commands.size();await click(ability);app.running=false
		check(commands.size()>before and int(battle._group().get("ability",{}).get("charges",0))==charges-1,"self buff clicks through native preview and spends one charge")
		check(chip(battle,"ability").detail.text.contains("冷却"),"real skill cooldown is readable")
		before=commands.size();await click(chip(battle,"ability"));app.running=false;check(commands.size()==before,"cooldown skill click does not fabricate success")
	for node in battle.ui.get_node("Tray/Scroll/Cards").get_children():check(str(node.payload.kind) not in ["ability","vehicle_unload"],"no repeated ability or unload portrait card")
	await click(chip(battle,"vehicle"));await screenshot("tank-controls")
	# Actual amphibious seating is separate from issuing a movement/attack order.
	var amphibious:Dictionary={}
	for step:int in range(240):
		for row:Dictionary in app.core.view.littoral.land.get("combat_vehicles",[]):
			if str(row.get("company_id",""))=="MCP-103-C01" and str(row.get("phase",""))=="active":amphibious=row;break
		if not amphibious.is_empty():break
		app.core.request({"op":"step","seconds":5})
	check(not amphibious.is_empty(),"real amphibious vehicle landed for seating test")
	if not amphibious.is_empty():
		var card:Control=company_card(battle,"MCP-103-C01");battle.ui.get_node("Tray/Scroll").ensure_control_visible(card);await frames();await click(card);battle.update()
		var load_chip:Control=chip(battle,"load");check(load_chip!=null,"load action visible without opening a modal")
		if load_chip!=null:
			before=commands.size();await click(load_chip);app.running=false;check(commands.size()>before and str(commands[-1].command.get("action",""))=="embark","tap load sends real embark command")
			for step:int in range(30):
				app.core.request({"op":"step","seconds":2});amphibious=load("res://scripts/tactical_vehicle_controls_v3.gd").find(battle,int(amphibious.id))
				if not amphibious.get("passenger_ids",[]).is_empty():break
			check(not amphibious.get("passenger_ids",[]).is_empty(),"bodies actually walk into vehicle seats")
			battle.update();map.zoom=2.25;map.camera_center=Vector2(float(amphibious.x),float(amphibious.y))+Vector2(20,30);map._sync_world3d_camera();await frames()
			var unload_chip:Control=chip(battle,"unload");check(unload_chip!=null,"unload action replaces load when seats fill")
			if unload_chip!=null:
				var unload_point:Vector2=Vector2(float(amphibious.x),float(amphibious.y));var found:bool=false
				for offset:Vector2 in [Vector2(0,80),Vector2(80,0),Vector2(-80,0),Vector2(0,-80)]:
					var p:Vector2=unload_point+offset;var preview:Dictionary=app.core.request({"op":"littoral_vehicle_preview","vehicle_id":int(amphibious.id),"action":"disembark","x":p.x,"y":p.y})
					if bool(preview.get("data",{}).get("valid",false)):unload_point=p;found=true;break
				check(found,"native valid inland unloading destination found")
				before=commands.size();await drag(unload_chip.get_global_rect().get_center(),world_point(map,unload_point));app.running=false
				check(commands.size()>before and str(commands[-1].command.get("action",""))=="disembark","drag unload sends actual vehicle landing destination")
				amphibious=load("res://scripts/tactical_vehicle_controls_v3.gd").find(battle,int(amphibious.id))
				check(not amphibious.get("passenger_ids",[]).is_empty(),"inland unload does not teleport bodies to destination on commit")
				evidence.append({"type":"unload_commit","vehicle":amphibious,"destination":str(unload_point)})
				var passengers:Array=amphibious.get("passenger_ids",[]).duplicate();var first_exit:Array=[]
				for step:int in range(40):
					app.core.request({"op":"step","seconds":1});amphibious=load("res://scripts/tactical_vehicle_controls_v3.gd").find(battle,int(amphibious.id))
					for body:Dictionary in app.core.view.littoral.land.get("entities",[]):
						if passengers.has(body.get("id")) and not bool(body.get("seated",false)) and float(body.get("hp",0))>0:first_exit.append(body)
					if not first_exit.is_empty():break
				check(not first_exit.is_empty(),"actual vehicle arrival releases living passengers")
				if not first_exit.is_empty():
					var position:=Vector2(float(amphibious.x),float(amphibious.y));var largest:float=0
					for body:Dictionary in first_exit:largest=maxf(largest,position.distance_to(Vector2(float(body.x),float(body.y))))
					check(largest<25,"unloaded bodies appear next to actual vehicle rather than remote goal")
					evidence.append({"type":"first_passengers_exit","largest_distance_m":largest,"bodies":first_exit,"vehicle":amphibious})
				battle.update()
	await screenshot("contextual-controls")
	FileAccess.open(ROOT+"observation.json",FileAccess.WRITE).store_string(JSON.stringify(app.core.view))
	app.running=false;app.close_home_exercise();await frames();check(app.screen=="home","return from battle works");app.show_page("harbor");await frames();check(app.screen=="harbor","direct harbour works")
	await finish()
func finish()->void:
	for name:String in normal:check(normal[name]==FileAccess.get_sha256("user://"+name),"normal account unchanged "+name)
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"input_events":inputs,"failures":failures,"commands":commands,"ui_events":ui_events,"images":evidence,"headless":DisplayServer.get_name()=="headless"}
	FileAccess.open(ROOT+("headless.json" if DisplayServer.get_name()=="headless" else "gpu.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print("COASTAL_CONTROLS_REVIEW ",JSON.stringify(report))
	if is_instance_valid(app):app.core.close();app.queue_free()
	await frames();quit(0 if failures.is_empty() else 1)
