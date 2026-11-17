extends SceneTree
const Settle=preload("res://tests/transition_settle.gd")
var app
var failures:Array[String]=[]
var checks:int=0
var multi_review:bool=false
func configure_army(service,rows:Array)->Dictionary:
	if not multi_review:return service.set_choices(rows)
	var companies:Array=[]
	for row in rows:
		for company in service.layout(str(row.unit_id)).get("companies",[]):
			var draft:Dictionary=row.duplicate(true);draft["company_id"]=str(company.company_id);companies.append(draft)
	return service.set_choices(companies,true)
func _initialize()->void:call_deferred("run")
func check(ok:bool,title:String)->void:
	checks+=1
	if not ok:failures.append(title);push_error(title)
func drag_pointer(from:Vector2,to:Vector2)->void:
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=from;Input.parse_input_event(event);await process_frame
	for i in range(1,7):
		var move:=InputEventMouseMotion.new();move.position=from.lerp(to,float(i)/6.);move.button_mask=MOUSE_BUTTON_MASK_LEFT;Input.parse_input_event(move);await process_frame
	event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=to;Input.parse_input_event(event);await process_frame;await process_frame
func run()->void:
	root.size=Vector2i(1280,720);root.gui_embed_subwindows=true
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.economy=load("res://scripts/economy.gd").new("user://tests/amphibious-ui-%d.json"%OS.get_process_id())
	root.add_child(app);app.set_process(false);await process_frame;await process_frame;app.page_motion=false
	var service=load("res://scripts/amphibious_expedition_service.gd").new(app.economy);service.home._own_unit("MCP-034")
	var id:String="IBS-U-USN-ERMA-IOWA"
	if not app.economy.state.owned.has(id):app.economy.state.owned[id]=app.economy._new_owned(id)
	app.economy.state.owned[id].ammo=100;app.economy.state.owned[id].hp=100;app.economy.state.wallet.ammo_stock=10000;app.economy.state.wallet.fuel=10000
	app.economy.formation.assign([id]);app.economy.state.formation=[id];app.economy.state.erase("fleets_v1")
	load("res://scripts/fleet_manager.gd").new(app.economy).set_members([id])
	configure_army(service,[{"unit_id":"MCP-034","carrier_identity":id,"transport_kind":"landing_craft"}])
	var began:Dictionary=app.economy.begin_sortie(42,false,{"kind":"salvage","id":"calm"});check(began.get("ok",false),"real voyage preparation")
	if not began.get("ok",false):quit(1);return
	app.run=began.duplicate(true);app.campaign_mode=false
	var opened:Dictionary=app.core.request({"op":"new_salvage","seed":42,"start":app.economy.native_start(began)});check(opened.get("ok",false),"real naval controller data "+str(opened.get("error","")))
	app.fullscreen_battle=true;app.enter_battle();app.running=false;await Settle.wait_for_route(self,app);await process_frame
	var ui:Control=app.page.get_node_or_null("AmphibiousExpedition");check(ui!=null,"land overlay attached to original naval page")
	check(app.battle_controller.get_script().resource_path.ends_with("legacy_battle.gd"),"original naval command workflow retained")
	if ui!=null:
		var card:Control=ui.cards["MCP-034-C01" if multi_review else "MCP-034"];check(card.type_badge.visible,"NATO card identity")
		if multi_review:check(ui.cards.size()==5,"five real company cards");check(not str(card.payload.get("designation","")).is_empty(),"full formation designation payload")
		var task:Dictionary=ui.data().tasks[0];var point:Vector2=ui.land.project(Vector2(float(task.x),float(task.y)))
		var from:Vector2=card.get_viewport().get_screen_transform()*card.get_global_transform_with_canvas()*(card.size*.5)
		var to:Vector2=app.sea.get_viewport().get_screen_transform()*app.sea.get_global_transform_with_canvas()*app.sea.project(Vector2(float(task.x),float(task.y)))
		await drag_pointer(from,to)
		check(str(app.core.view.salvage.amphibious.groups[0].stage) in ["approach","transit"],"actual pointer drag creates real transport command")
		if multi_review:
			var second:Control=ui.cards["MCP-034-C02"]
			await drag_pointer(second.get_viewport().get_screen_transform()*second.get_global_transform_with_canvas()*(second.size*.5),to)
			check(str(app.core.view.salvage.amphibious.groups[1].stage) in ["approach","transit"],"second company separately dragged and deployed")
		ui.land_primary=true;ui._layout();ui._refresh();await process_frame;await process_frame
		check(not app.sea.visible and ui.miniature_sea.visible,"land main map and naval miniature swap")
		app.issue({"op":"ai","fleet":1,"profile":"coord","mode":"auto","move":false,"gun":true,"torpedo":true})
		for i in range(90):
			if app.core.view.get("result")!=null or str(app.core.view.salvage.amphibious.groups[0].stage)=="ground":break
			app.core.request({"op":"step","seconds":1})
		ui._refresh();await process_frame
		var ground:bool=str(app.core.view.salvage.amphibious.groups[0].stage)=="ground";check(ground,"real ship approach and transport reach ground")
		if ground:
			if multi_review:check(int(app.core.view.salvage.amphibious.groups[0].count)==9,"actual company personnel from authoritative table")
			var walk:Vector2=Vector2(float(task.beach.x),float(task.beach.y)).lerp(Vector2(float(task.x),float(task.y)),.28)
			from=card.get_viewport().get_screen_transform()*card.get_global_transform_with_canvas()*(card.size*.5);to=ui.land.get_viewport().get_screen_transform()*ui.land.get_global_transform_with_canvas()*ui.land.project(walk)
			await drag_pointer(from,to);check(str(app.core.view.salvage.amphibious.groups[0].order)=="move","pointer drag orders actual ground movement")
			if multi_review:check(str(app.core.view.salvage.amphibious.groups[1].order)=="hold","second company order remains independent")
			to=ui.land.get_viewport().get_screen_transform()*ui.land.get_global_transform_with_canvas()*ui.land.project(Vector2(float(task.x),float(task.y)))
			await drag_pointer(from,to);check(str(app.core.view.salvage.amphibious.groups[0].order)=="search","drag onto ruin begins real army task")
			for i in range(30):
				if app.core.view.get("result")!=null:break
				app.core.request({"op":"step","seconds":1})
			ui._refresh();await process_frame
			if app.core.view.get("result")==null:
				from=ui.recover.get_viewport().get_screen_transform()*ui.recover.get_global_transform_with_canvas()*(ui.recover.size*.5);await drag_pointer(from,from)
				check(str(app.core.view.salvage.amphibious.groups[0].order)=="retreat","real pointer recover orders return to beach")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../artifacts/amphibious-expedition/"));await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/amphibious-expedition/multi-land-map.png" if multi_review else "res://../artifacts/amphibious-expedition/land-map.png"))
		ui.land_primary=false;ui._layout();ui._refresh();await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/amphibious-expedition/multi-naval-map.png" if multi_review else "res://../artifacts/amphibious-expedition/naval-map.png"))
		if app.core.view.get("result")==null:app.issue({"op":"salvage_abandon"})
		app.finish_battle();check(app.economy.state.active_run.is_empty(),"Main terminal path settles actual navy and land losses")
	await winning_main_path(service)
	app.core.close();app.queue_free();await process_frame
	print(JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)

func winning_main_path(service)->void:
	if not app.economy.state.active_run.is_empty():return
	# Isolated scenario setup; no gameplay state is edited after the sortie begins.
	var heavy:String="IBS-U-USN-ERMA-IOWA";var light:String="IBS-U-USN-FLETCHER"
	for id in [heavy,light]:
		app.economy.state.owned[id]=app.economy._new_owned(id);app.economy.state.owned[id].ammo=100
	for unit in ["MCP-034","MCP-009"]:
		service.home._own_unit(unit);service.home.state().units[unit].condition=100.;service.home.state().units[unit].at=int(Time.get_unix_time_from_system())
	app.economy.state.wallet.ammo_stock=10000;app.economy.state.wallet.fuel=10000
	var fleets=load("res://scripts/fleet_manager.gd").new(app.economy);fleets.set_members([heavy]);fleets.create("第二护送队");fleets.set_members([light]);fleets.select(str(fleets.active().id),true)
	app.economy.set_salvage_options({"difficulty":"calm","environment":"atoll","weather":"clear","scene":"sunken_metropolis"})
	check(configure_army(service,[{"unit_id":"MCP-034","carrier_identity":heavy,"transport_kind":"landing_craft"},{"unit_id":"MCP-009","carrier_identity":light,"transport_kind":"landing_craft"}]).get("ok",false),"two distinct owned protocols configured")
	var began:Dictionary=app.economy.begin_sortie(43,false,{"kind":"salvage","id":"calm"});check(began.get("ok",false),"two fleet resource escrow")
	if not began.get("ok",false):return
	app.run=began.duplicate(true)
	var opened:Dictionary=app.core.request({"op":"new_salvage","seed":43,"start":app.economy.native_start(began)});check(opened.get("ok",false),"two fleet actual naval extraction")
	if not opened.get("ok",false):return
	app.enter_battle();app.running=false;await Settle.wait_for_route(self,app)
	app.issue({"op":"extraction_autopilot","enabled":true,"policy":"balanced","version":"cas-extraction-pilot-v3"})
	var advanced:Dictionary=app.core.request({"op":"step","seconds":1000});check(advanced.get("ok",false),"two fleet actual army/naval pilot simulation")
	check(app.core.view.get("result")!=null and bool(app.core.view.get("salvage",{}).get("extracted",false)),"true terminal victory without mutating ships or enemies")
	var tasks:Array=app.core.view.get("salvage",{}).get("amphibious",{}).get("tasks",[])
	check(tasks.filter(func(t):return str(t.status)=="complete").size()>=2,"actual repeated land mission completion")
	if app.core.view.get("result")!=null:
		var native_save:Dictionary=app.core.request({"op":"save","serialized":true})
		var artifact:=FileAccess.open("res://../artifacts/amphibious-expedition/multi-main-run.serialized.json" if multi_review else "res://../artifacts/amphibious-expedition/main-win.serialized.json",FileAccess.WRITE)
		if artifact!=null:artifact.store_string(str(native_save.get("serialized","")));artifact.close()
		app.finish_battle();check(app.economy.state.active_run.is_empty(),"Main victorious finish clears atomic voyage")
		check(bool(app.economy.latest_receipt().get("success",false)),"Main real extraction awards actual cargo")
		check(app.economy.latest_receipt().get("amphibious",{}).get("units",[]).size()==2,"same receipt includes both true army losses")
		if multi_review:check(app.economy.latest_receipt().get("amphibious",{}).get("companies",[]).size()==7,"seven companies settle once as two protocols")
		if multi_review:
			var receipt:Dictionary=app.economy.latest_receipt()
			var receipt_file:=FileAccess.open("res://../artifacts/amphibious-expedition/multi-main-receipt.json",FileAccess.WRITE)
			if receipt_file!=null:receipt_file.store_string(JSON.stringify(receipt,"\t"));receipt_file.close()
			for unit in receipt.amphibious.units:check(float(app.economy.state.home_v1.units[str(unit.id)].condition)==float(unit.condition_percent),"weighted protocol condition applied once "+str(unit.id))
			var committed:Dictionary=app.economy.state.duplicate(true)
			var repeated:Dictionary=app.economy.settle_sortie({"run_id":str(receipt.run_id)})
			check(bool(repeated.get("duplicate",false)) and service.same(committed,app.economy.state),"repeated settlement preserves all resources and losses")
			var reloaded=load("res://scripts/economy.gd").new(app.economy.save_path)
			reloaded.load_state()
			check(service.same(reloaded.state.get("settled",{}),app.economy.state.get("settled",{})),"seven-company receipt survives account reload")
