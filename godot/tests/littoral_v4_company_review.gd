extends "res://tests/littoral_v4_performance_review.gd"
## True multi-company authority, individual cards and actual independent commands.
func run()->void:
	output_dir="res://../artifacts/littoral-v4-ui/companies/";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	profile=output_dir+"isolated-%d.json"%OS.get_process_id();var account=load("res://scripts/economy.gd").new(profile);check(account.load_state().get("ok",false),"ordinary isolated multi-company UI account")
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.fullscreen_battle=true
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames();app.set_process(false);app.page_motion=false
	var request:Dictionary={"op":"new_littoral","version":"cas-littoral-v4","company_layout":"multi-company-v1","seed":42,"mode":"defense","ships":[{"id":"CAS-O-LHA-RETURNLIGHT","hp":100,"ammo":100},{"id":"CAS-H-USN-ENTERPRISE-1942","hp":100,"ammo":100}],"roster":["MCP-034","MCP-116","MCP-167","MCP-011","MCP-103"],"unit_condition":[],"transport_preset":"transport","defense":[]}
	if not check(app.core.request(request).get("ok",false),"native new multi-company defense accepted"):return finish()
	app.show_page("battle");await frames(5);controller().tutorial_dismissed=true;controller().tutorial.active=false;controller().tutorial.hide();controller().selected_unit="MCP-034-C01";controller().set_primary_map("land");app.running=false;app.update_battle();await frames(5)
	controller().interaction_event.connect(func(kind,data):events.append({"kind":kind,"data":data.duplicate(true),"tick":app.core.view.tick}))
	var land=controller().ui.get_node("LandWindow/Map");var native:Array=app.core.view.littoral.land.entities.filter(func(row):return str(row.side)=="allies")
	check(app.core.view.littoral.groups.size()==21 and native.size()==181,"authority creates twenty-one genuine companies and one hundred eighty-one distinct bodies")
	check(land.actors.values().filter(func(actor):return actor.friendly).size()==181,"all one hundred eighty-one actual friendly bodies render without a hidden cap")
	check(app.sea.view.get("presentation",{}).get("version","")=="projectile-fx-v1","embedded stream retains the original actual naval projectile presentation")
	var first=card("Unit_MCP-034-C01");var second=card("Unit_MCP-034-C02")
	check(first!=null and second!=null and first.payload.unit_id==second.payload.unit_id and first.payload.company_id!=second.payload.company_id,"two same-personality cards carry different actual company IDs")
	check(first.designation_label.visible and not first.designation_label.text.is_empty() and first.company_label.text.contains("1/5") and second.company_label.text.contains("2/5"),"complete formation title and distinct company ordinal are visible on the actual cards")
	var scroll:ScrollContainer=controller().ui.get_node("Tray/Scroll")
	for dimensions in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=dimensions;await frames(5);scroll.scroll_horizontal=0;await frames()
		first=card("Unit_MCP-034-C01")
		check(first.status.get_global_rect().end.y<=scroll.get_global_rect().end.y+1,"full card information fits the tray at "+str(dimensions))
		check(native.all(func(row):return int(land.target_at(land.actor_hit_point(int(row.id))).get("id",-1))==int(row.id)),"every actual company body retains an individual hit target at "+str(dimensions))
		await shot("actual-twenty-one-companies-%dx%d"%[dimensions.x,dimensions.y]);await click(controller().ui.get_node("MiniMap"));await shot("actual-company-naval-%dx%d"%[dimensions.x,dimensions.y]);await click(controller().ui.get_node("MiniMap"))
	root.size=Vector2i(1280,720);await frames(5)
	var native_before:String=app.core.request({"op":"save","serialized":true}).serialized
	var scroll_start:Vector2=global_point(card("Unit_MCP-034-C02"),card("Unit_MCP-034-C02").size*.5)
	await drag_from(scroll_start,scroll_start-Vector2(260,0));check(scroll.scroll_horizontal>100,"horizontal pointer swipe genuinely scrolls the company tray")
	check(app.core.request({"op":"save","serialized":true}).serialized==native_before,"scrolling the company tray emits no native battlefield order")
	scroll.scroll_horizontal=0;await frames();await click(card("Unit_MCP-034-C01"));await frames()
	if app.modal!=null:app.close_modal()
	controller().selected_unit="MCP-034-C01";controller().roster_signature="";app.update_battle();await frames();await click(controller().ui.get_node("FocusMap"));await frames()
	var old_second:Dictionary=_company("MCP-034-C02").duplicate(true)
	var origin:Dictionary=_company("MCP-034-C01").position;var origin_point:=Vector2(float(origin.x),float(origin.y));var target:Vector2=_empty_target(land,origin_point)
	check(target!=origin_point,"selected company has a real visible walkable street target")
	await drag(card("Unit_MCP-034-C01"),world(target));check(events.any(func(row):return row.kind=="unit_ordered" and row.data.get("accepted",false) and row.data.get("company_id","")=="MCP-034-C01"),"first company card sends its own true company command")
	check(str(_company("MCP-034-C01").order)=="move" and JSON.stringify(_company("MCP-034-C02"))==JSON.stringify(old_second),"first company order does not commandeer her sister company")
	await advance(2);check(Vector2(float(_company("MCP-034-C01").position.x),float(_company("MCP-034-C01").position.y)).distance_to(origin_point)>4,"first company truly advances under native movement")
	scroll.ensure_control_visible(card("Unit_MCP-034-C02"));await frames();await click(card("Unit_MCP-034-C02"));await frames();check(controller().selected_unit=="MCP-034-C02","second independent company card becomes the selected company")
	check(card("Unit_MCP-034-C02").payload.selected and not card("Unit_MCP-034-C01").payload.selected,"gold selection highlight belongs only to the selected company")
	var second_origin:Dictionary=_company("MCP-034-C02").position;var second_point:=Vector2(float(second_origin.x),float(second_origin.y));target=_empty_target(land,second_point)
	await drag(card("Unit_MCP-034-C02"),world(target));check(str(_company("MCP-034-C02").order)=="move","second company accepts its different actual movement order")
	var before_charges:int=int(_company("MCP-034-C02").ability.charges);var other_charges:int=int(_company("MCP-034-C01").ability.charges)
	var ability=card("Ability_MCP-034-C02");scroll.ensure_control_visible(ability);await frames()
	await drag(ability,world(second_point));check(int(_company("MCP-034-C02").ability.charges)==before_charges-1 and int(_company("MCP-034-C01").ability.charges)==other_charges,"finite specialty is consumed only by the chosen company")
	await shot("actual-independent-company-move-and-ability")
	var saved:String=app.core.request({"op":"save","serialized":true}).serialized;var ui:Dictionary=controller().serialize_ui_state();app.core.close();check(app.core.request({"op":"load","serialized":saved}).get("ok",false),"all real independent companies restore after fully closing the authority")
	land.prime_visuals();controller().restore_ui_state(ui);app.update_battle();await frames();check(app.core.request({"op":"save","serialized":true}).serialized==saved and controller().selected_unit=="MCP-034-C02","selected company and exact native log survive restore without repeating ability")
	controller().set_primary_map("land");scroll.scroll_horizontal=0;await frames()
	var segments:Dictionary={"native_bridge_step_ms":[],"original_naval_update_ms":[],"full_amphibious_update_ms":[],"company_slot_layout_ms":[],"land_observe_ms":[],"actor_advance_ms":[]}
	for index in range(5):
		var started:int=Time.get_ticks_usec();app.core.request({"op":"step","seconds":.1});segments.native_bridge_step_ms.append(float(Time.get_ticks_usec()-started)/1000)
		started=Time.get_ticks_usec();controller().naval_controller.update();segments.original_naval_update_ms.append(float(Time.get_ticks_usec()-started)/1000)
		started=Time.get_ticks_usec();app.update_battle();segments.full_amphibious_update_ms.append(float(Time.get_ticks_usec()-started)/1000)
		started=Time.get_ticks_usec();land._spread_positions(land.land.get("entities",[]));segments.company_slot_layout_ms.append(float(Time.get_ticks_usec()-started)/1000)
		started=Time.get_ticks_usec();land.observe(land.land,false);segments.land_observe_ms.append(float(Time.get_ticks_usec()-started)/1000)
		started=Time.get_ticks_usec();land._process(.016);segments.actor_advance_ms.append(float(Time.get_ticks_usec()-started)/1000)
	var measures:Array=[]
	for speed in [1,8]:
		controller().set_battle_speed(speed);app.elapsed=0;app.running=true;app.set_process(true);var start:int=Time.get_ticks_usec();var start_tick:float=float(app.core.view.tick);samples.clear();last_usec=0;measuring=true;await create_timer(2.1).timeout;measuring=false
		var wall:float=float(Time.get_ticks_usec()-start)/1000000;var elapsed:float=float(app.core.view.tick)-start_tick;app.running=false;app.set_process(false);app.update_battle()
		measures.append({"speed":speed,"wall_seconds":wall,"native_seconds":elapsed,"frame_ms_p50":quantile(samples,.5),"frame_ms_p95":quantile(samples,.95),"frame_ms_max":samples.max() if not samples.is_empty() else 0,"frames":samples.size(),"native_bodies":app.core.view.littoral.land.entities.filter(func(row):return str(row.side)=="allies").size()})
		check(absf(elapsed-wall*speed)<maxf(.4,wall*speed*.18),"production fixed clock tracks actual multi-company "+str(speed)+"x wall time")
	FileAccess.open(output_dir+"proof.json",FileAccess.WRITE).store_string(JSON.stringify({"runtime":runtime_info(),"request":request,"initial_bodies":native.size(),"actual_companies":app.core.view.littoral.groups,"measures":measures,"segments":segments,"selected_company":controller().selected_unit,"scope":"direct legitimate native UI fixture; not an account grant or reward proof"},"  "))
	finish()
func _company(id:String)->Dictionary:
	for group in app.core.view.littoral.groups:
		if str(group.id)==id:return group
	return {}
func _empty_target(land:Control,origin:Vector2)->Vector2:
	for distance in [100,150,200,250]:
		for angle in range(12):
			var point:Vector2=origin+Vector2.from_angle(angle*TAU/12)*distance;var at:Vector2=land.project(point)
			if controller()._island_contains(point) and not controller()._ground_blocked(point) and Rect2(Vector2(40,150),land.size-Vector2(400,180)).has_point(at) and land.target_at(at).is_empty():return point
	return origin
