extends "res://tests/chapter_novice_playthrough.gd"
## Real new-adventure chapter launches, pointer controls, native victories and public-only overlays.
var terrain_signatures:Dictionary={}
var threat_kinds:Dictionary={}
var dodged:Dictionary={}
var captured_warnings:Dictionary={}

func run()->void:
	output="res://../artifacts/godot/adventure-presentation/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var path:="user://tests/adventure-presentation-%d.json"%OS.get_process_id()
	app=Main.instantiate();app.boot_to_title=false;app.economy=Economy.new(path);root.add_child(app);app.set_process(false)
	await process_frame
	await exercise(path)
	check(completed,"complete adventure first chapter through three actual missions")
	app.audio.shutdown();app.core.close();app.queue_free();await process_frame
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	var report:={"checks":checks,"passed":checks-failures.size(),"failures":failures,"battles":battles,"terrains":terrain_signatures,"attacks":threat_kinds,"lessons":lessons,"shots":shots,"scope":"actual pointer UI/native/client chapter chain, public-only monster intelligence"}
	var file:=FileAccess.open(output+"receipt.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)

func launch(stage:String)->bool:
	app.set_meta("story_route_node",str(app.progression.chapter_status().node));app.show_page("story_route")
	await process_frame
	if not await click("进入作战简报") or not await click("进入作战"):return false
	await Settle.wait_for_route(self,app)
	if not check(app.screen=="battle" and str(app.core.view.chapter.stageId)==stage,"real adventure launch "+stage):return false
	check(app.core.view.salvage.get("adventure",{}).get("version")=="cas-adventure-v1","new explicit adventure profile")
	terrain_signatures[stage]={"theme":app.core.view.salvage.terrainTheme,"layout":app.core.view.salvage.adventure.terrain_layout,"geometry":hash(app.core.view.islands)}
	lesson("select")
	await press(app.battle_controller.hud.fleet_cards[int(app.core.view.ships[0].id)].button)
	app.battle_controller.show_tab("fleet");await process_frame
	for control in app.find_children("*","HSlider",true,false):
		if control.is_visible_in_tree():control.value=30 if stage=="c1-boss" else 20;break
	await press(app.battle_controller.hud.tactical_button)
	lesson("plot")
	if not await click("准备画航线"):return false
	var points:Array=[Vector2(7400,1200),Vector2(7400,2200)] if stage=="c1-breakout" else [Vector2(7600,2200)] if stage=="c1-salvage" else [Vector2(8000,1200)]
	app.sea.zoom=1.2;app.sea.pan+=Vector2(app.sea.size.x*.62,app.sea.size.y*.53)-app.sea.project(points[0])
	for point in points:
		await pointer(app.sea,app.sea.project(point),true);await pointer(app.sea,app.sea.project(point),false)
	lesson("commit")
	if not await click("下达航线"):return false
	if stage=="c1-boss":await manual_gun()
	lesson("time")
	if not await click("开始") or not step(1):return false
	await teach_entities()
	if stage=="c1-boss":
		await focus_boss()
		app.battle_controller.show_tab("ai");await process_frame
		for control in app.find_children("*","CheckBox",true,false):
			if control.is_visible_in_tree() and control.text=="雷击" and not control.button_pressed:
				await press(control);break
		await press(app.battle_controller.hud.tactical_button)
		check(bool(app.core.view.fleets[0].ai.torpedo),"player explicitly authorizes automatic torpedo support for boss")
	await shot(stage+"-01-adventure")
	return true

func focus_boss()->void:
	for own in app.core.view.ships.duplicate():
		for contact in app.core.view.contacts:
			if not bool(contact.get("boss",false)):continue
			var aim:Dictionary=app.core.request({"op":"aim","ship":int(own.id),"target":str(contact.id),"weapon":"gun"})
			if not aim.get("ok",false) or not aim.get("data",{}).get("valid",false):continue
			await press(app.battle_controller.hud.fleet_cards[int(own.id)].button)
			app.sea.zoom=1.4;app.sea.pan=Vector2.ZERO
			app.sea.pan=Vector2(app.sea.size.x*.66,app.sea.size.y*.55)-app.sea.project(app.sea.pos(own).lerp(app.sea.pos(contact),.5))
			await pointer(app.sea,app.sea.project(app.sea.pos(own))+Vector2(-24,-48),true)
			var target:Vector2=app.sea.get_viewport().get_screen_transform()*app.sea.get_global_transform_with_canvas()*app.sea.project(app.sea.pos(contact))
			var motion:=InputEventMouseMotion.new();motion.position=target;Input.parse_input_event(motion);await process_frame
			await pointer(app.sea,app.sea.project(app.sea.pos(contact)),false)

func teach_entities()->void:
	var guide:Control=app.page.get_node("ChapterBattleGuide")
	for count in range(6):
		guide._observe()
		if not guide.step_id.begins_with("entity_") or guide.step_id=="entity_evade":break
		var key:String=guide.step_id
		lessons.append({"stage":str(app.core.view.chapter.stageId),"tick":int(app.core.view.tick),"step":key,"title":str(guide.get_node("Card/Title").text)})
		check(not guide.get_node("Card/Body").text.is_empty(),"public entity has an actionable short counter "+key)
		if not await click("记住攻击方式"):break
		check(guide.learned_entities.has(key.trim_prefix("entity_")),"player acknowledges learned attack "+key)

func observe_threats(stage:String)->void:
	var guide:Control=app.page.get_node("ChapterBattleGuide")
	guide._observe()
	for warning in app.core.view.salvage.get("telegraphs",[]):
		threat_kinds[str(warning.kind)]=true
		check(warning.has_all(["shape","counter","source_contact"]),"native publishes actual hazard geometry/counter")
		if preload("res://scripts/monster_renderer.gd").threatens_fleet(app.core.view,warning):check(guide.step_id in ["boss_evade","entity_evade"],"guide reacts to actual visible danger against own fleet")
		if not captured_warnings.has(stage):
			captured_warnings[stage]=true;guide._pan(app.sea.pos(warning));await shot(stage+"-warning")

func extract()->bool:
	# A threat may legitimately take tutorial priority. The real exit action stays available.
	var exit:Dictionary=app.core.view.salvage.exits[0].duplicate(true);exit["index"]=0
	var bounds:Dictionary=exit.get("bounds",{})
	if not bounds.is_empty():
		var region:=Rect2(Vector2(float(bounds.min_x),float(bounds.min_y)),Vector2(float(bounds.max_x)-float(bounds.min_x),float(bounds.max_y)-float(bounds.min_y)))
		if not app.core.view.ships.all(func(ship):return region.has_point(app.sea.pos(ship))):
			if not await player_route(Vector2(float(bounds.max_x)-120.0,region.get_center().y)):return false
			for wait in range(120):
				if app.core.view.ships.all(func(ship):return region.has_point(app.sea.pos(ship))):break
				if not step(1):return false
	app.select_object("exit",exit);await process_frame
	for retry in range(8):
		if not await click("开始撤离"):return false
		if app.core.view.salvage.get("extracting") is Dictionary:break
		if retry==0:print("EXTRACT_GATE "+str(app.toast_label.text))
		step(3)
	check(app.core.view.salvage.get("extracting") is Dictionary,"player explicitly begins native extraction during ongoing danger")
	return step(12)

func player_route(destination:Vector2)->bool:
	if app.core.view.ships.is_empty():return false
	await press(app.battle_controller.hud.fleet_cards[int(app.core.view.ships[0].id)].button)
	app.battle_controller.cancel_draft(false);app.battle_controller.choose_route("follow");await process_frame
	app.sea.zoom=.9;app.sea.pan=Vector2.ZERO
	app.sea.pan=Vector2(app.sea.size.x*.62,app.sea.size.y*.53)-app.sea.project(destination)
	await pointer(app.sea,app.sea.project(destination),true);await pointer(app.sea,app.sea.project(destination),false)
	if not app.battle_controller.preview.get("valid",false) and str(app.battle_controller.preview.get("error","")).contains("航速"):
		app.page.get_node("ChapterBattleGuide")._observe();await click("按可用航速重新预览")
	if not check(app.battle_controller.preview.get("valid",false),"player route actually legal "+str(app.battle_controller.preview)):return false
	return await click("下达航线")

func evade_or_cruise()->void:
	if app.core.view.ships.is_empty():return
	var point:Vector2=app.sea.pos(app.core.view.ships[0])
	var destination:=Vector2(3600 if point.x>6500 else 10700,650 if point.y>1400 else 2300)
	var reroute:=false
	for warning in app.core.view.salvage.get("telegraphs",[]):
		if not preload("res://scripts/monster_renderer.gd").threatens_fleet(app.core.view,warning):continue
		var key:=str(warning.get("id",warning.get("start_tick",0)))
		if dodged.has(key):continue
		dodged[key]=true;reroute=true;break
	if not reroute and float(app.core.view.ships[0].speed)<2.0:reroute=true
	if not reroute:return
	await press(app.battle_controller.hud.fleet_cards[int(app.core.view.ships[0].id)].button)
	# Use the same public route preview as the player; a reversal needs a real side waypoint.
	var travel_speed:=float(app.battle_controller.cruise)
	for ship in app.core.view.ships:travel_speed=minf(travel_speed,floorf(float(ship.get("systems",{}).get("maxSpeed",travel_speed))))
	var paths:Array=[[destination]]
	for x in [-1500.0,1500.0,2600.0,-2600.0]:
		paths.append([Vector2(clampf(point.x+x,2300,15000),650 if point.y>1400 else 2400),destination])
	var chosen:Array=[]
	for path in paths:
		var query:Dictionary=app.core.request({"op":"preview_route","fleet":1,"mode":"follow","speed":maxf(4,travel_speed),"points":path.map(func(p):return {"x":p.x,"y":p.y})})
		if query.get("ok",false) and query.get("data",{}).get("valid",false):chosen=path;break
	if chosen.is_empty():return
	if travel_speed<float(app.battle_controller.cruise):
		app.battle_controller.show_tab("fleet");await process_frame
		for control in app.find_children("*","HSlider",true,false):
			if control.is_visible_in_tree():control.value=maxf(4,travel_speed);break
		await press(app.battle_controller.hud.tactical_button)
	app.battle_controller.cancel_draft(false)
	app.battle_controller.choose_route("follow");await process_frame
	app.sea.zoom=.90;app.sea.pan=Vector2.ZERO
	app.sea.pan=Vector2(app.sea.size.x*.62,app.sea.size.y*.53)-app.sea.project(destination)
	for waypoint in chosen:
		app.sea.pan+=Vector2(app.sea.size.x*.62,app.sea.size.y*.53)-app.sea.project(waypoint)
		await pointer(app.sea,app.sea.project(waypoint),true);await pointer(app.sea,app.sea.project(waypoint),false)
	if not app.battle_controller.preview.get("valid",false) and str(app.battle_controller.preview.get("error","")).contains("航速"):
		app.page.get_node("ChapterBattleGuide")._observe()
		await click("按可用航速重新预览")
	if not app.battle_controller.preview.get("valid",false):
		print("EVASION_PREVIEW "+JSON.stringify({"tick":app.core.view.tick,"from":point,"to":destination,"preview":app.battle_controller.preview,"points":app.sea.planned}))
		app.battle_controller.cancel_draft(false)
		return
	await click("下达航线")

func presentation_boundary()->void:
	var intel:Control=app.sea.monster_intel
	var saved:Dictionary=app.core.request({"op":"save","serialized":true})
	for contact in app.core.view.contacts:
		if not contact.has("attack"):continue
		app.select_object("contact",contact);app.sea.queue_redraw();await process_frame
		intel.update_observation(app.core.view,str(contact.id),false)
		check(intel.visible and intel.observed_id==str(contact.id),"selected visible monster exposes public HP/intention")
		intel.update_observation(app.core.view,str(contact.id),false,true)
		check(intel.visible,"explicit player selection keeps intelligence even during tutorial")
		intel.update_observation(app.core.view,"",false,true)
		check(not intel.visible,"expanded entity tutorial suppresses duplicate automatic intelligence")
		intel.update_observation(app.core.view,str(contact.id),false)
		check(intel.get_node("Card/Margin/Rows/Header/Vital").text.contains(" / "),"selected monster exact public HP display")
		var denied:Dictionary=app.core.view.duplicate(true);denied.contacts=[]
		intel.update_observation(denied,str(contact.id),false)
		check(not intel.visible,"hidden contact cannot be recovered from old selection or telegraph")
		var legacy:Dictionary=app.core.view.duplicate(true);legacy.salvage.erase("adventure")
		for legacy_contact in legacy.get("contacts",[]):legacy_contact.erase("intelligence")
		intel.update_observation(legacy,str(contact.id),false)
		check(not intel.visible,"legacy/history do not acquire adventure intelligence")
		intel.update_observation(app.core.view,str(contact.id),false)
		app.select_object("ship",app.core.view.ships[0]);await process_frame
		check(app.sea.intel_contact.is_empty(),"friendly selection closes monster intelligence while retaining firing target")
		break
	check(str(app.core.request({"op":"save","serialized":true}).serialized)==str(saved.serialized),"rendering/selecting/inspecting never mutates native simulation")
	# Explicit public-rule fixture: immunity removes only the exempt ship, never nearby escorts.
	var ward:Dictionary={"shape":"circle","x":1000,"y":1000,"radius":400,"exempt_ship_id":1}
	var solo:Dictionary={"ships":[{"id":1,"hp":100,"x":1000,"y":1000}]}
	check(not preload("res://scripts/monster_renderer.gd").threatens_fleet(solo,ward),"aversion warning does not mislead the immune flagship")
	solo.ships.append({"id":2,"hp":100,"x":1100,"y":1000})
	check(preload("res://scripts/monster_renderer.gd").threatens_fleet(solo,ward),"nearby unprotected escort still receives actual aversion danger")

func exercise(_path:String)->void:
	output="res://../artifacts/godot/adventure-presentation/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	if not check(read_until("breakout"),"read awakening before real breakout") or not await launch("c1-breakout"):return
	await presentation_boundary()
	for i in range(60):
		if app.core.view.chapter.events.has("beacon_reached"):break
		if not step(5):return
		await teach_entities();await observe_threats("c1-breakout")
	check(app.core.view.chapter.events.has("beacon_reached"),"new accelerated fleet actually reaches beacon")
	await teach_entities()
	# The tutorial still asks the player to explicitly collect all ships into the exit.
	for i in range(12):
		if app.core.view.ships.all(func(ship):return float(ship.speed)<1.0):break
		step(5)
	if not await extract() or not await return_after_win("c1-breakout","silence",40):return
	if not check(read_until("salvage"),"read hearing before archive mission") or not await launch("c1-salvage"):return
	for i in range(60):
		var ruin:Dictionary=app.core.view.salvage.ruins[0]
		var nearby:bool=app.core.view.ships.any(func(ship):return app.sea.pos(ship).distance_to(app.sea.pos(ruin.p))<650.0)
		if nearby:break
		if not step(5):return
		await teach_entities();await observe_threats("c1-salvage")
	command({"op":"speed","fleet":1,"speed":0})
	for i in range(8):
		if app.core.view.ships.any(func(ship):return float(ship.speed)<=8.0):break
		step(3)
	await teach_entities()
	await click("定位档案残骸") if app.page.get_node("ChapterBattleGuide").step_id=="approach_archive" else await process_frame
	if not await context_action("ruin",1):return
	for i in range(10):
		if app.core.view.chapter.events.has("archive_recovered"):break
		step(4);await observe_threats("c1-salvage")
		if app.core.view.salvage.get("collecting")==null and not app.core.view.chapter.events.has("archive_recovered"):await context_action("ruin",1)
	check(app.core.view.chapter.events.has("archive_recovered"),"actual timed archive search in varied drowned city")
	await shot("c1-salvage-search")
	if not await extract() or not await return_after_win("c1-salvage","archive",60):return
	if not check(read_until("boss"),"read antagonist clues before boss") or not await launch("c1-boss"):return
	for i in range(900):
		if app.core.view.get("result")!=null:break
		await evade_or_cruise()
		if not step(1):return
		await teach_entities();await observe_threats("c1-boss")
	if not await return_after_win("c1-boss","afterboss",100):return
	check(read_until("complete"),"real third victory unlocks chapter ending")
	check(terrain_signatures["c1-breakout"].theme!=terrain_signatures["c1-salvage"].theme and terrain_signatures["c1-salvage"].theme!=terrain_signatures["c1-boss"].theme,"three actual chapter maps have distinct biomes")
	check(threat_kinds.size()>0,"native attacks observed in player walkthrough")
	completed=true
	var report:=FileAccess.open(output+"adventure-detail.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"terrains":terrain_signatures,"attacks":threat_kinds,"lessons":lessons,"shots":shots},"\t"));report.close()
