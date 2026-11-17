extends SceneTree
const Service=preload("res://scripts/cargo_service.gd")
const Settle=preload("res://tests/transition_settle.gd")
var app
var checks:int=0
var failures:Array[String]=[]
var output:String="res://../artifacts/godot/expedition-v2/"
func _initialize()->void:call_deferred("run")
func check(ok:bool,title:String)->void:
	checks+=1
	if not ok:failures.append(title);push_error(title)
func click(node:Control)->void:
	await Settle.wait_for_route(self,app)
	check(is_instance_valid(node) and node.is_visible_in_tree(),"visible pointer target "+node.name)
	if not is_instance_valid(node):return
	var point:Vector2=node.get_viewport().get_screen_transform()*node.get_global_transform_with_canvas()*(node.size*.5)
	var motion:=InputEventMouseMotion.new();motion.position=point;Input.parse_input_event(motion)
	var down:=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;down.position=point;Input.parse_input_event(down)
	await process_frame
	var up:=InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_LEFT;up.position=point;Input.parse_input_event(up)
	await process_frame;await process_frame;await Settle.wait_for_route(self,app)
func key(code:int,window_id:int=0)->void:
	var event:=InputEventKey.new();event.keycode=code;event.window_id=window_id;event.pressed=true;Input.parse_input_event(event);await process_frame
	event=InputEventKey.new();event.keycode=code;event.window_id=window_id;Input.parse_input_event(event);await process_frame
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output+name+".png"))==OK,"capture "+name)
func fit(node:Control,ancestor:Control)->bool:return ancestor.get_global_rect().grow(1).encloses(node.get_global_rect())
func has_label(node:Node,text:String)->bool:
	if node is Label and node.text==text:return true
	for child in node.get_children():
		if has_label(child,text):return true
	return false
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output));root.size=Vector2i(1280,720);root.gui_embed_subwindows=true
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false
	app.economy=load("res://scripts/economy.gd").new("user://tests/expedition-v2-%d.json"%OS.get_process_id())
	root.add_child(app);app.set_process(false);await process_frame;await process_frame;app.page_motion=false
	var service:=Service.new(app.economy)
	var original:Dictionary=app.economy.state.duplicate(true)
	for scene in Service.SCENES:
		check(service.set_options({"scene":scene}).get("ok",false),"persist valid scene "+scene)
		check(service.expedition_config(app.economy.roster()).scene==scene,"scene in frozen expedition config "+scene)
		check(not service.start_config("calm").has("scene"),"scene absent from strict legacy cargo config")
	check(not service.set_expedition_options({"scene":"foreign"}).get("ok",false),"reject unknown scene")
	check(not service.set_expedition_options({"munitions":{"foreign":{"shell":"ap","torpedo":"heavy","reserve_reloads":2}}}).get("ok",false),"reject foreign owned identity")
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Service.LOOT))
	for spec in catalog.items:
		var item:Dictionary=spec.duplicate(true);item.loot_id=str(spec.id);item.id="test-"+str(spec.id);item.placement=[0,0,0]
		var loot:Dictionary={};loot[str(spec.kind)]=1
		check(Service.validate_receipt([item],loot,true,"calm",true),"accept catalog receipt "+str(spec.id))
		check(not Service.validate_receipt([item],loot,true,"calm",false),"old profile rejects v2 item "+str(spec.id))
		item.value=int(item.value)+1;check(not Service.validate_receipt([item],loot,true,"calm",true),"reject forged price "+str(spec.id))
		check(ResourceLoader.exists(Service.art_path(item)),"distinct inventory art "+str(spec.id))
	var owned_id:String=str(app.economy.formation[0])
	var json_plan:Dictionary=JSON.parse_string(JSON.stringify({"munitions":{owned_id:{"shell":"ap","torpedo":"heavy","reserve_reloads":2}}}))
	check(service.set_expedition_options(json_plan).get("ok",false),"JSON-loaded integer reserve plan can be edited again")
	json_plan.munitions[owned_id].reserve_reloads=1.5
	check(not service.set_expedition_options(json_plan).get("ok",false),"reject fractional reserve count")
	var tiny:Dictionary={"id":"test","shape":[[0,0]]}
	check(service.can_fit([],tiny,[4,2,0],8,3,21) and not service.can_fit([],tiny,[5,2,0],8,3,21),"reserved tail cells are really unavailable")
	check(service.can_fit([],tiny,[7,2,0],8,3),"old grids without usable cap preserve all cells")
	for id in ["navigation_gyro","memory_core","sealed_gear","crew_archive"]:
		var spec:Dictionary=Service.catalog_item(id);var item:Dictionary=spec.duplicate(true);item.loot_id=id;item.id="consume-"+id;item.placement=null
		service.stash().items.append(item)
		var credits:int=int(app.economy.wallet().credits);var instances:int=app.economy.state.get("item_instances",{}).size()
		check(service.consume(str(item.id)).get("ok",false),"consume actual catalog item "+id)
		check(int(app.economy.wallet().credits)==credits+int(spec.value) if spec.use=="sell" else app.economy.state.get("item_instances",{}).size()==instances+1,"sale versus unpack follows catalog "+id)
	app.economy.state=original;service=Service.new(app.economy)
	app.show_page("expedition");await Settle.wait_for_route(self,app)
	var select:Control=app.page.get_node("ExpeditionSelect")
	check(select.get_node("SceneRow").get_child_count()==6,"five scene choices are visible")
	await click(select.choices["scene:cult_relay"])
	check(select.selection.scene=="cult_relay","pointer chooses actual scene draft")
	for dimensions in [Vector2i(1280,720),Vector2i(960,540),Vector2i(1600,720)]:
		root.size=dimensions;await process_frame;await process_frame
		for node in [select.get_node("Continue"),select.get_node("SceneRow"),select.get_node("Cards")]:check(fit(node,select),"preparation fits "+str(dimensions))
		check(select.get_node("Cards").get_global_rect().end.y<=select.get_node("SceneRow").get_global_rect().position.y,"difficulty cards do not overlap scene choices "+str(dimensions))
		await shot("preparation-%dx%d"%[dimensions.x,dimensions.y])
	root.size=Vector2i(1280,720);await process_frame
	await click(select.get_node("Continue"));check(app.screen=="formation","scene choice enters real formation")
	await click(app.page.get_node("SortieMunitions"))
	var setup:Control=app.modal.get_node("MunitionSetup")
	check(setup.get_node("Scroll/Ships").get_child_count()>0,"real sortie ships can configure munitions")
	var row:Control=setup.get_node("Scroll/Ships").get_child(0)
	var shell:OptionButton=row.get_node("Margin/Body/Choices/Shell")
	await click(shell);await key(KEY_DOWN);await key(KEY_DOWN);await key(KEY_DOWN);await key(KEY_ENTER)
	check(shell.selected==2,"keyboard chooses high explosive shell through real popup")
	check(fit(row,setup),"munition row stays within modal content")
	var first:String=str(row.get_meta("ship_identity"))
	await shot("munition-config")
	await click(setup.get_node("Done"));check(app.modal==null,"munition commit closes modal")
	check(service.expedition_config(app.economy.roster()).munitions[first].shell=="he","chosen shell is atomically persisted")
	app.set_meta("next_sortie_seed",42);app.launch(false,{"kind":"salvage","id":"calm"});await Settle.wait_for_route(self,app)
	check(app.screen=="battle" and app.core.view.get("salvage",{}).has("expedition"),"production launch initializes actual expedition v2")
	check(str(app.run.get("gameplay_profile",""))=="cas-adventure-v2" and app.speed==1,"versioned extraction uses actual movement boost with 1x clock")
	check(app.core.view.salvage.expedition.scene=="cult_relay","native run uses chosen world scene")
	var chosen:Array=app.core.view.ships.filter(func(ship):return str(ship.get("characterId",""))==first)
	check(chosen.size()==1 and chosen[0].expedition_munitions.shell=="he","native ship uses chosen ammunition")
	check(int(app.core.view.salvage.cargo_grid.max_kg)==int(app.economy.cargo_budget().max_kg),"native actual cargo and UI reserve budget agree")
	var frozen:Dictionary=app.economy.state.expedition_v2.duplicate(true)
	check(not service.set_expedition_options({"scene":"storm_wrecks"}).get("ok",false) and app.economy.state.expedition_v2==frozen,"active voyage blocks configuration mutation")
	var operations:Control=app.page.get_node("ExpeditionOperations")
	await click(operations.get_node("Tasks"))
	var task:Dictionary=app.core.view.salvage.expedition.tasks[0]
	var task_row:Control=operations.task_rows[str(task.id)]
	await click(task_row.get_node("Margin/Body/Actions/Act"))
	check(app.core.view.salvage.expedition.tasks[0].status=="accepted","pointer task accept changes actual native state")
	await shot("operations-board")
	await click(task_row.get_node("Margin/Body/Actions/Locate"))
	check(app.modal==null and app.sea.project(Vector2(task.x,task.y)).distance_to(app.sea.size*.5)<2,"task locate centers actual public coordinates")
	await click(operations.get_node("Auto"))
	await click(operations.board.get_node("Toggle"));app.running=false
	check(app.core.view.salvage.expedition.autopilot.enabled,"real pointer toggle starts native automated extraction")
	var response:Dictionary=app.core.request({"op":"step","seconds":10});app.update_battle()
	check(response.get("ok",false) and int(app.core.view.tick)==10,"AI steps actual simulated seconds")
	check(int(app.core.view.salvage.expedition.autopilot.commands_issued)>0,"native AI issued real legal commands")
	await shot("automated-sea")
	response=app.issue({"op":"speed","fleet":app.first_fleet(),"speed":0})
	check(response.get("ok",false) and not app.core.view.salvage.expedition.autopilot.enabled,"manual legal command takes over AI")
	var saved:Dictionary=app.core.request({"op":"save","serialized":true});app.save_leave();await Settle.wait_for_route(self,app);app.close_modal()
	app.resume_run();await Settle.wait_for_route(self,app)
	var restored:Dictionary=app.core.request({"op":"save","serialized":true})
	check(not str(saved.get("serialized","")).is_empty() and str(saved.serialized)==str(restored.get("serialized","")),"v2 tasks/ammo/AI survive exact production save and resume")
	check(app.issue({"op":"extraction_autopilot","enabled":true,"policy":"balanced"}).get("ok",false),"resume can explicitly restart automated expedition")
	app.running=true;app.elapsed=0
	for i in range(600):
		if app.screen!="battle":break
		app._process(1.0)
		if i%8==0:await process_frame
	await Settle.wait_for_route(self,app)
	check(app.screen=="result" and app.last_receipt.get("success",false),"complete real production AI voyage reaches success result")
	check(app.economy.state.get("active_run",{}).is_empty(),"production settlement clears only completed voyage")
	var warehouse=load("res://scripts/fleet_warehouse.gd").new(app.economy)
	var carried:Array=warehouse.hold().items
	var completed_tick:int=int(app.core.view.get("tick",0));var returned_items:int=carried.size()
	check(not carried.is_empty() and carried.all(func(item):return not str(item.get("loot_id","")).is_empty()),"real v2 physical loot arrives in port stash")
	check(not carried.is_empty() and has_label(app.page,str(carried[0].name)),"result displays earned object name rather than misleading family reward")
	await shot("actual-ai-extraction-result")
	var sold:bool=false
	for item in carried.duplicate():
		if not Service.can_unpack(item):
			var credits:int=int(app.economy.wallet().credits)
			var result:Dictionary=Service.new(app.economy).consume(str(item.id),"fleet")
			check(result.get("ok",false) and int(app.economy.wallet().credits)==credits+int(item.value),"actual carried relic sells at its native price")
			sold=true;break
	check(sold,"real voyage returned a sellable world object")
	var reloaded=load("res://scripts/economy.gd").new(app.economy.save_path);reloaded.load_state()
	check(int(reloaded.wallet().credits)==int(app.economy.wallet().credits),"actual relic sale wallet persists across account reload")
	var canonical_items:Variant=JSON.parse_string(JSON.stringify(warehouse.hold().items))
	check(load("res://scripts/fleet_warehouse.gd").new(reloaded).hold().items==canonical_items,"settled physical fleet stash persists across JSON account reload")
	app.core.close();app.queue_free();await process_frame
	var core_path:String=OS.get_environment("CAS_SIM_PATH")
	if core_path.is_empty():
		var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://bin/core-current.json"));core_path=ProjectSettings.globalize_path("res://bin/"+str(manifest.executable))
	var report:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"core":core_path,"core_sha256":FileAccess.get_sha256(core_path),"production_extraction_tick":completed_tick,"actual_items_returned":returned_items,"reloaded_items_after_sale":canonical_items.size()}
	FileAccess.open(output+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
