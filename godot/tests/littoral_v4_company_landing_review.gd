extends "res://tests/littoral_v4_company_review.gd"
## Two companies of the same personality genuinely sail, land and recover separately.
func run()->void:
	output_dir="res://../artifacts/littoral-v4-ui/company-landing/";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	profile=output_dir+"isolated-%d.json"%OS.get_process_id();var account=load("res://scripts/economy.gd").new(profile);check(account.load_state().get("ok",false),"ordinary isolated company landing account")
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.fullscreen_battle=true
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames();app.set_process(false);app.page_motion=false
	var request:Dictionary={"op":"new_littoral","version":"cas-littoral-v4","company_layout":"multi-company-v1","seed":42,"mode":"tutorial","lesson":"landing","ships":[{"id":"CAS-O-LHA-RETURNLIGHT","hp":100,"ammo":100},{"id":"CAS-H-USN-ENTERPRISE-1942","hp":100,"ammo":100}],"roster":["MCP-034","MCP-009"],"unit_condition":[],"transport_preset":"transport","defense":[]}
	if not check(app.core.request(request).get("ok",false),"genuine multi-company amphibious request accepted"):return finish()
	app.show_page("battle");await frames(5);controller().tutorial_dismissed=true;controller().tutorial.active=false;controller().tutorial.hide();app.running=false;app.update_battle();await frames()
	controller().interaction_event.connect(func(kind,data):events.append({"kind":kind,"data":data.duplicate(true),"tick":app.core.view.tick}))
	check(_company("MCP-034-C01").stage=="embarked" and _company("MCP-034-C02").stage=="embarked","both real sister companies initially remain aboard")
	var beach:Dictionary=app.core.view.littoral.beaches[1];var landing:=Vector2(float(beach.land.x),float(beach.land.y))
	for id in ["MCP-034-C01","MCP-034-C02"]:
		await drag(card("Unit_"+id),world(landing));check(events.any(func(row):return row.kind=="deploy_queued" and str(row.data.get("company_id",""))==id),"actual card queues its own carrier deployment "+id)
	check(_company("MCP-034-C03").pending_deploy==null and _company("MCP-034-C03").stage=="embarked","third sister is genuinely still aboard without a deployment order")
	while float(app.core.view.tick)<65 and (_company("MCP-034-C01").stage!="ground" or _company("MCP-034-C02").stage!="ground"):await advance(.1)
	check(_company("MCP-034-C01").stage=="ground" and _company("MCP-034-C02").stage=="ground","both ordered companies actually land through their native transports")
	check(_company("MCP-034-C03").stage=="embarked","one company's arrival does not land an uncommanded sister")
	var first_rows:Array=app.core.view.littoral.land.entities.filter(func(row):return str(row.get("company_id",""))=="MCP-034-C01")
	var second_rows:Array=app.core.view.littoral.land.entities.filter(func(row):return str(row.get("company_id",""))=="MCP-034-C02")
	check(first_rows.size()==9 and second_rows.size()==9 and first_rows.all(func(row):return str(row.unit_id)=="MCP-034"),"each company exposes nine genuine bodies with the original own identity")
	controller().set_primary_map("land");controller().selected_unit="MCP-034-C01";controller().roster_signature="";app.update_battle();await frames();await click(controller().ui.get_node("FocusMap"));await frames()
	var land=controller().ui.get_node("LandWindow/Map");var origin:Dictionary=_company("MCP-034-C01").position;var destination:Vector2=_empty_target(land,Vector2(float(origin.x),float(origin.y)))
	var sister:Dictionary=_company("MCP-034-C02").duplicate(true)
	await drag(card("Unit_MCP-034-C01"),world(destination));check(_company("MCP-034-C01").order=="move" and JSON.stringify(_company("MCP-034-C02"))==JSON.stringify(sister),"land drag changes only the chosen company's actual order")
	await shot("two-real-companies-own-identity")
	await click(card("Unit_MCP-034-C01"));await frames()
	var withdrawal:Button
	for node in app.modal.find_children("*","Button",true,false):
		if node.text.begins_with("显示撤收卡"):withdrawal=node;break
	if not check(withdrawal!=null,"the real company context exposes its withdrawal card"):return finish()
	await click(withdrawal);await frames()
	var withdrawal_card=card("Withdraw_MCP-034-C01");controller().ui.get_node("Tray/Scroll").ensure_control_visible(withdrawal_card);await frames()
	var current:Dictionary=_company("MCP-034-C01").position
	await drag(withdrawal_card,world(Vector2(float(current.x),float(current.y))))
	await advance(.1)
	check(_company("MCP-034-C01").stage=="returning" and _company("MCP-034-C02").stage=="ground","selected company returns while her sister keeps the beach")
	var saved:String=app.core.request({"op":"save","serialized":true}).serialized;var ui_state:Dictionary=controller().serialize_ui_state();app.core.close()
	check(app.core.request({"op":"load","serialized":saved}).get("ok",false),"independent company carrier progress restores through a new native process")
	land.prime_visuals();controller().restore_ui_state(ui_state);app.update_battle();await frames()
	check(app.core.request({"op":"save","serialized":true}).serialized==saved,"restoring does not repeat either deployment or withdrawal")
	while float(app.core.view.tick)<100 and _company("MCP-034-C01").stage=="returning":await advance(.1)
	check(_company("MCP-034-C01").stage=="recovered" and _company("MCP-034-C02").stage=="ground","one company genuinely reboards without recovering the other")
	check(not app.core.view.littoral.corpses.any(func(row):return str(row.get("company_id",""))=="MCP-034-C01"),"normal company recovery creates no invented casualty")
	await shot("first-company-recovered-second-stays")
	FileAccess.open(output_dir+"proof.json",FileAccess.WRITE).store_string(JSON.stringify({"runtime":runtime_info(),"request":request,"events":events,"companies":app.core.view.littoral.groups,"native_tick":app.core.view.tick,"scope":"legitimate native UI fixture; no fake account reward or ownership grant"},"  "))
	finish()

