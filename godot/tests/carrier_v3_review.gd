extends "res://tests/littoral_v4_world_review.gd"
func button_named(value:String)->Button:
	for b in app.find_children("*","Button",true,false):
		if b.name==value:return b
	return null
func support_card(carrier:int)->Control:
	for c in controller().ui.get_node("Tray/Scroll/Cards").get_children():
		if str(c.payload.kind)=="aviation_support" and int(c.payload.carrier)==carrier:return c
	return null
func mode(value:String)->void:
	await click(controller().ui.get_node("CarrierCommandDesk"));await frames()
	if value=="high":await shot("00-three-level-selector")
	var b:Button=button_named("CarrierLevel_"+value)
	if check(b!=null,"actual three-level selector exposes "+value):await click(b);await frames()
	check(str(app.core.view.littoral.carrier_ops.automation.level)==value,"pointer chooses "+value)
func run()->void:
	output_dir="res://../artifacts/carrier-v3/ui/";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	profile=output_dir+"isolated-%d.json"%OS.get_process_id();var account=load("res://scripts/economy.gd").new(profile);account.load_state()
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.fullscreen_battle=true
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames();app.set_process(false);app.page_motion=false
	var config:Dictionary={"op":"new_littoral","version":"cas-littoral-v4","mode":"raid","seed":42,"ships":[{"id":"CAS-H-USN-ENTERPRISE-1942","hp":100,"ammo":100},{"id":"CAS-H-IJN-SHOKAKU-1942","hp":100,"ammo":100}],"roster":["MCP-034","MCP-001"],"unit_condition":[],"transport_preset":"combat","defense":[]}
	if not check(app.core.request(config).get("ok",false),"isolated actual sea-land carrier battle starts"):return finish()
	app.show_page("battle");await frames(6);controller().tutorial_dismissed=true;controller().tutorial.active=false;controller().tutorial.hide();app.sea.focus_fleet();await frames()
	controller().interaction_event.connect(func(kind,data):events.append({"kind":kind,"data":data.duplicate(true),"tick":app.core.view.tick}))
	await mode("high")
	check(controller().ui.get_node("Tray/Scroll/Cards").get_children().filter(func(c):return str(c.payload.kind)=="aviation_support").size()==2,"high shows one support card per mother")
	check(controller().ui.get_node("Tray/Scroll/Cards").get_children().all(func(c):return str(c.payload.kind) not in ["squadron","flight","wing"]),"high hides detailed squadron controls")
	await advance(8);check(not app.core.view.littoral.aviation.aircraft.is_empty(),"high starts real flights without target input")
	await shot("01-high-automatic")
	await mode("medium")
	var before:Dictionary=app.core.request({"op":"save"}).data
	var target:Dictionary=app.core.view.littoral.land.entities.filter(func(e):return str(e.side)=="axis" and float(e.hp)>0)[0]
	var point:=Vector2(float(target.x),float(target.y))
	var c:Control=support_card(1);controller().ui.get_node("Tray/Scroll").ensure_control_visible(c);await frames();await drag(c,world(point));await frames()
	check(app.core.view.littoral.carrier_ops.automation.missions.size()==1,"sea-map support drag installs one actual objective")
	check(app.core.request({"op":"save"}).data!=before,"accepted objective is recorded")
	await click(controller().ui.get_node("CarrierMapSwitch"));await frames();check(controller().primary_map=="land","pointer switches to actual land map")
	c=support_card(2);controller().ui.get_node("Tray/Scroll").ensure_control_visible(c);await frames();await drag(c,world(point));await frames()
	check(app.core.view.littoral.carrier_ops.automation.missions.size()==2,"same support card works directly on actual land map")
	await shot("02-medium-land-support")
	await advance(12);check(app.core.view.littoral.aviation.aircraft.any(func(a):return str(a.kind)=="SBD" and str(a.target_kind)=="land"),"objective auto-selects actual land-capable bombers")
	await mode("low")
	check(support_card(1)==null,"low replaces broad support cards with concrete formations")
	var specific:Control=null
	for card_row in controller().ui.get_node("Tray/Scroll/Cards").get_children():
		if str(card_row.payload.kind)=="squadron" and str(card_row.payload.air_role)=="fighter":specific=card_row;break
	if check(specific!=null,"low exposes actual fighter squadron"):
		await click(controller().ui.get_node("CarrierMapSwitch"));await frames();check(controller().primary_map=="sea","pointer switches back to actual sea map")
		for card_row in controller().ui.get_node("Tray/Scroll/Cards").get_children():
			if str(card_row.payload.kind)=="squadron" and str(card_row.payload.air_role)=="fighter":specific=card_row;break
		controller().ui.get_node("Tray/Scroll").ensure_control_visible(specific);await frames()
		var carrier:Dictionary=app.core.view.ships[0];await drag(specific,world(Vector2(float(carrier.x)-1800,float(carrier.y)-1200)));await frames()
		check(app.core.view.littoral.carrier_ops.queue.size()==1,"low drag queues one concrete squadron")
	await shot("03-low-specific-formations")
	await mode("medium");await frames()
	var mother:Dictionary=app.core.view.ships[0];c=support_card(1);controller().ui.get_node("Tray/Scroll").ensure_control_visible(c);await frames();await drag(c,world(Vector2(float(mother.x),float(mother.y))));await frames()
	check(app.core.view.littoral.carrier_ops.automation.stopped_carriers.any(func(id):return int(id)==1),"support drag home recalls and holds only actual mother")
	var replay_before:Dictionary=app.core.request({"op":"save"}).data
	controller().replay_mode=true;await click(controller().ui.get_node("CarrierCommandDesk"));await frames()
	check(button_named("CarrierLevel_high")!=null and button_named("CarrierLevel_high").disabled and button_named("CarrierLevel_low").disabled,"replay mode selector is read-only")
	app.close_modal();controller().replay_mode=false
	check(app.core.request({"op":"save"}).data==replay_before,"viewing selector does not mutate replay")
	finish()
