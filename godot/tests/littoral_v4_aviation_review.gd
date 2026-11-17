extends "res://tests/littoral_v4_world_review.gd"
## Real raid enemy carrier and real public aircraft; no injected targets or health.
var air_shots:Array=[]
func advance(seconds:float)->void:
	for i in range(int(round(seconds*10))):
		var reply:Dictionary=app.core.request({"op":"step","seconds":.1})
		if not reply.get("ok",false):check(false,"aviation time advances "+str(reply));return
		for shot in app.core.view.littoral.get("shots",[]):
			if str(shot.get("kind",""))=="air_weapon" and not air_shots.any(func(old):return old.id==shot.id):air_shots.append(shot.duplicate(true))
		app.update_battle()
		if i%10==0:await process_frame
func squadron(type:String)->Dictionary:
	for row in app.core.view.littoral.aviation.squadrons:
		if str(row.visual_type)==type:return row
	return {}
func run()->void:
	output_dir="res://../artifacts/littoral-v4-ui/aviation/";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	profile=output_dir+"isolated-%d.json"%OS.get_process_id();var account=load("res://scripts/economy.gd").new(profile)
	check(account.load_state().get("ok",false),"isolated real aviation review profile")
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.fullscreen_battle=true
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames();app.set_process(false);app.page_motion=false
	var config:Dictionary={"op":"new_littoral","version":"cas-littoral-v4","mode":"raid","seed":42,"ships":[{"id":"IBS-U-USN-ERMA-IOWA","hp":100,"ammo":100},{"id":"CAS-H-USN-ENTERPRISE-1942","hp":100,"ammo":100},{"id":"IBS-U-USN-FLETCHER","hp":100,"ammo":100}],"roster":["MCP-034","MCP-001"],"unit_condition":[{"id":"MCP-034","hp":100},{"id":"MCP-001","hp":100}],"transport_preset":"balanced","defense":[]}
	if not check(app.core.request(config).get("ok",false),"native raid starts with a registered carrier"):return finish()
	app.show_page("battle");await frames(6);controller().tutorial_dismissed=true;controller().tutorial.active=false;controller().tutorial.hide();app.sea.focus_fleet();await frames()
	controller().interaction_event.connect(func(kind,data):events.append({"kind":kind,"data":data.duplicate(true),"tick":app.core.view.tick}))
	if not check(app.core.view.contacts.any(func(row):return str(row.get("classId",""))=="CAS-H-IJN-SHOKAKU-1942"),"actual raid exposes a real hostile carrier contact"):return finish()
	await click(controller().ui.get_node("MiniMap"));await frames()
	var aa:Dictionary=app.core.view.littoral.land.buildings.filter(func(row):return str(row.id)=="aa")[0]
	var ground:=Vector2(float(aa.x),float(aa.y));var before:String=app.core.request({"op":"save","serialized":true}).serialized
	await drag(card("Squadron_"+str(squadron("TBD").id)),world(ground))
	check(app.core.request({"op":"save","serialized":true}).serialized==before,"torpedo aircraft cannot bomb land or consume anything on a rejected gesture")
	check(events.back().kind=="drag_rejected" and str(events.back().data.reason).contains("鱼雷机"),"invalid aircraft target explains its actual role restriction")
	var land_stock:int=int(squadron("SBD").ammunition)
	await drag(card("Squadron_"+str(squadron("SBD").id)),world(ground))
	check(event_seen("squadron_ordered"),"actual isometric building drag orders a true land strike")
	check(int(squadron("SBD").ammunition)==land_stock-3,"real land strike loads exactly three finite aircraft weapons")
	check(app.core.view.littoral.aviation.aircraft.all(func(row):return str(row.target_kind)=="land"),"authority records actual aircraft land targets")
	await advance(8);await click(controller().ui.get_node("MiniMap"));await frames()
	var contact:Dictionary=app.core.view.contacts.filter(func(row):return str(row.get("classId",""))=="CAS-H-IJN-SHOKAKU-1942")[0]
	var ship_target:=Vector2(float(contact.x),float(contact.y));var naval_stock:int=int(squadron("TBD").ammunition)
	await drag(card("Squadron_"+str(squadron("TBD").id)),world(ship_target))
	check(int(squadron("TBD").ammunition)==naval_stock-3,"real pointer strike on a hostile carrier loads the registered torpedo squadron")
	check(app.core.view.littoral.aviation.aircraft.any(func(row):return str(row.target_kind)=="ship" and str(row.target_id)==str(contact.id)),"native aircraft actually track that public hostile ship")
	var saved:String=app.core.request({"op":"save","serialized":true}).serialized
	app.core.close();check(app.core.request({"op":"load","serialized":saved}).get("ok",false),"in-flight ship and land strikes restore through a new process")
	app.update_battle();await frames();check(app.core.request({"op":"save","serialized":true}).serialized==saved,"in-flight restore preserves the exact native command log")
	for i in range(900):
		if app.core.view.littoral.aviation.aircraft.any(func(row):return str(row.side)=="axis"):break
		await advance(.1)
	var enemies:Array=app.core.view.littoral.aviation.aircraft.filter(func(row):return str(row.side)=="axis")
	if check(not enemies.is_empty(),"real enemy carrier launches physical aircraft"):
		var enemy:Dictionary=enemies[0];var air_target:=Vector2(float(enemy.x),float(enemy.y));var fighter_stock:int=int(squadron("F4F").ammunition)
		await drag(card("Squadron_"+str(squadron("F4F").id)),world(air_target))
		check(int(squadron("F4F").ammunition)==fighter_stock-3,"actual pointer intercepts a hostile aircraft with finite fighter weapons")
		check(app.core.view.littoral.aviation.aircraft.any(func(row):return str(row.side)=="allies" and str(row.target_kind)=="aircraft" and int(row.target_id)==int(enemy.id)),"native fighter mission names the actual public enemy aircraft ID")
		await shot("actual-land-sea-air-missions")
	await advance(90)
	check(not air_shots.is_empty(),"aircraft truly reach targets and use actual weapons")
	for row in app.core.view.littoral.aviation.squadrons:
		if int(row.airborne)>0:check(app.issue({"op":"littoral_air_order","squadron_id":str(row.id),"action":"return"}).get("ok",false),"recall remaining actual squadron "+str(row.id))
	for i in range(1200):
		if not app.core.view.littoral.aviation.aircraft.any(func(row):return str(row.side)=="allies"):break
		await advance(.1)
	check(not app.core.view.littoral.aviation.aircraft.any(func(row):return str(row.side)=="allies"),"all remaining friendly aircraft genuinely return or record a real loss")
	check(app.core.view.littoral.aviation.squadrons.all(func(row):return int(row.available)+int(row.airborne)+int(row.lost)==int(row.total)),"aircraft count remains conserved across attack, recovery and losses")
	await shot("actual-aviation-recovery")
	FileAccess.open(output_dir+"runtime.json",FileAccess.WRITE).store_string(JSON.stringify(runtime_info(),"  "))
	FileAccess.open(output_dir+"proof.json",FileAccess.WRITE).store_string(JSON.stringify({"request":config,"shots":air_shots,"aviation":app.core.view.littoral.aviation,"tick":app.core.view.tick},"  "))
	finish()
