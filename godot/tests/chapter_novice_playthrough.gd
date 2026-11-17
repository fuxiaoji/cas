extends "res://tests/chapter_integration_test.gd"
## Fresh account, actual pointer routing/collection/extraction, native time batches only.
const Settle=preload("res://tests/transition_settle.gd")
var lessons:Array[Dictionary]=[]
var shots:Array[String]=[]
func pointer(control:Control,local:Vector2,pressed:bool)->void:
	var point:Vector2=control.get_viewport().get_screen_transform()*control.get_global_transform_with_canvas()*local
	var motion:=InputEventMouseMotion.new();motion.position=point;Input.parse_input_event(motion)
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;Input.parse_input_event(event)
	await process_frame
func press(control:Control)->bool:
	if not check(control!=null and control.is_visible_in_tree(),"actual pointer target visible"):return false
	await pointer(control,control.size*.5,true);await pointer(control,control.size*.5,false);await process_frame
	return true
func click(title:String)->bool:
	await Settle.wait_for_route(self,app)
	for item in app.find_children("*","Button",true,false):
		if item.is_visible_in_tree() and item.text==title and not item.disabled:return await press(item)
	return check(false,"missing enabled action "+title)
func lesson(expected:String="")->void:
	var guide=app.page.get_node_or_null("ChapterBattleGuide")
	if not check(guide!=null,"actual guide is attached in native battle"):return
	guide._observe()
	lessons.append({"stage":str(app.core.view.chapter.stageId),"tick":int(app.core.view.tick),"step":guide.step_id,"title":str(guide.get_node("Card/Title").text)})
	if not expected.is_empty():check(guide.step_id==expected,"just-in-time lesson "+expected+" (actual "+guide.step_id+")")
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	var neutral:=InputEventMouseMotion.new();neutral.position=Vector2(4,4);Input.parse_input_event(neutral)
	await Settle.wait_for_route(self,app);await create_timer(.55).timeout;await RenderingServer.frame_post_draw
	var path:=ProjectSettings.globalize_path(output+name+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"window capture "+name);shots.append(path)
func launch(stage:String)->bool:
	app.set_meta("story_route_node",str(app.progression.chapter_status().node));app.show_page("story_route");await process_frame
	if not await click("进入作战简报"):return false
	if not check(app.screen=="chapter","specific route node opens original mission briefing"):return false
	if not await click("进入作战"):return false
	await Settle.wait_for_route(self,app)
	if not check(app.screen=="battle" and str(app.core.view.chapter.stageId)==stage,"real chapter mission "+stage):return false
	lesson();await shot(stage+"-01-select")
	if not await press(app.battle_controller.hud.fleet_cards[int(app.core.view.ships[0].id)].button):return false
	lesson("plot")
	# Edit the same visible cruise slider the player uses; do not issue a route outside UI.
	app.battle_controller.show_tab("fleet");await process_frame
	var speed:HSlider
	for item in app.find_children("*","HSlider",true,false):
		if item.is_visible_in_tree():speed=item;break
	if not check(speed!=null,"fleet drawer has editable cruise control"):return false
	speed.value=24 if stage=="c1-boss" else 20
	await press(app.battle_controller.hud.tactical_button)
	if not await click("准备画航线"):return false
	check(app.sea.editing,"guide action enters the real route editor")
	var points:Array=[Vector2(7400,1200),Vector2(7400,2200)] if stage=="c1-breakout" else [Vector2(7600,2200)] if stage=="c1-salvage" else [Vector2(8000,1200)]
	# Camera pan is observation only. Place route points at an unobstructed sea location.
	app.sea.zoom=1.2
	var center:Vector2=points[0]
	app.sea.pan+=Vector2(app.sea.size.x*.62,app.sea.size.y*.53)-app.sea.project(center)
	for point in points:
		await pointer(app.sea,app.sea.project(point),true);await pointer(app.sea,app.sea.project(point),false)
	check(app.sea.planned.size()==points.size(),"pointer clicks create actual route draft")
	lesson("commit");await shot(stage+"-02-route")
	if not await click("下达航线"):return false
	check(bool(app.economy.state.active_run.evidence.get("followAccepted",false)),"actual UI commits native follow command")
	if stage=="c1-boss":
		lesson("boss_fire");await manual_gun();lesson("time")
	else:lesson("time")
	if not await click("开始"):return false
	check(app.running,"actual clock button starts play")
	# App processing is disabled for deterministic accelerated native time, never fabricated results.
	if not command({"op":"step","seconds":1}):return false
	lesson()
	if stage=="c1-boss":
		lesson("boss_handover");await click("恢复舰队自动炮击");lesson("boss_fight")
	await click("暂停")
	return true
func return_after_win(stage:String,next:String,origins:int)->bool:
	lesson("finished")
	await shot(stage+"-03-terminal")
	if not settle(stage,next,origins):return false
	if not await click("返回章节路线"):return false
	check(app.screen=="story_route" and app.page.get_node("StoryRoute/Graph").current==next,"result returns to route with actual next node "+next)
	check(app.page.get_node("StoryRoute").selected==next,"result focuses newly unlocked node instead of previous launch node")
	return true
func extract()->bool:
	lesson("extract")
	if not await click("定位并选择归航区"):return false
	var expected:Vector2=app.sea.pos(app.core.view.salvage.exits[0])
	check(app.sea.project(expected).distance_to(app.sea.size*.5)<1.0,"exit locator centers actual public exit, not world origin")
	if not await click("开始撤离"):return false
	check(app.core.view.salvage.get("extracting") is Dictionary,"actual pointer starts native extraction timer")
	lesson("extract_wait")
	return step(12)
func manual_gun()->void:
	var diagnostics:Array=[]
	for own in app.core.view.ships:
		for contact in app.core.view.contacts:
			var aim:Dictionary=app.core.request({"op":"aim","ship":int(own.id),"target":str(contact.id),"weapon":"gun"})
			diagnostics.append({"ship":own.id,"target":contact.id,"aim":aim})
			if not aim.get("ok",false) or not aim.get("data",{}).get("valid",false):continue
			await press(app.battle_controller.hud.fleet_cards[int(own.id)].button)
			var middle:Vector2=(app.sea.pos(own)+app.sea.pos(contact))*.5
			app.sea.zoom=1.4;app.sea.pan+=Vector2(app.sea.size.x*.66,app.sea.size.y*.55)-app.sea.project(middle)
			var badge:Vector2=app.sea.project(app.sea.pos(own))+Vector2(-24,-48)
			await pointer(app.sea,badge,true)
			var at:Vector2=app.sea.project(app.sea.pos(contact))
			var point:Vector2=app.sea.get_viewport().get_screen_transform()*app.sea.get_global_transform_with_canvas()*at
			var motion:=InputEventMouseMotion.new();motion.position=point;Input.parse_input_event(motion);await process_frame
			await pointer(app.sea,at,false)
			check(bool(app.economy.state.active_run.evidence.get("gunOrdered",false)),"actual gun-badge drag accepted by native aim and fire")
			return
	print("GUN_DIAGNOSTICS "+JSON.stringify(diagnostics));check(false,"at least one public valid gun solution before boss death")
func exercise(_path:String)->void:
	var wallet:Dictionary=app.economy.wallet().duplicate(true)
	app.show_page("story_catalog");await click("查看章节路线")
	if not check(read_until("breakout"),"novice reads rescue and waking"):return
	if not await launch("c1-breakout"):return
	if not step(799):return
	lesson();await shot("c1-breakout-beacon")
	if not await extract() or not await return_after_win("c1-breakout","silence",40):return
	if not check(read_until("salvage"),"hearing and optional tour preserve stage order"):return
	if not await launch("c1-salvage"):return
	lesson("approach_archive")
	if not await click("定位档案残骸"):return
	check(app.selection_kind=="ruin" and int(app.selected.id)==1,"guide selects only already discovered archive")
	if not step(699):return
	lesson()
	if app.page.get_node("ChapterBattleGuide").step_id=="slow_search":
		await click("编队减速至6节");step(15)
	lesson()
	if app.page.get_node("ChapterBattleGuide").step_id=="select_archive":await click("选择档案残骸")
	lesson("collect_archive");await shot("c1-salvage-search")
	if not await click("打捞残骸"):return
	lesson("search_wait")
	if not step(8):return
	if not app.core.view.chapter.events.has("archive_recovered"):
		await click("打捞残骸");step(8)
	check(app.core.view.chapter.events.has("archive_recovered"),"real timed archive recovery event")
	if not await extract() or not await return_after_win("c1-salvage","archive",60):return
	if not check(read_until("boss"),"archive choices and antagonist lead to boss"):return
	if not await launch("c1-boss"):return
	if not step(99):return
	lesson();await shot("c1-boss-fire")
	var warning_seen:=false
	for i in range(30):
		if not app.core.view.salvage.get("telegraphs",[]).is_empty():
			warning_seen=true;lesson("boss_evade");await click("定位攻击预警");await shot("c1-boss-warning");break
		if not step(10):return
	check(warning_seen,"boss tutorial reacts to a real public attack telegraph")
	if not step(800):return
	if not await return_after_win("c1-boss","afterboss",100):return
	check(read_until("complete"),"ending follows actual third victory")
	check(app.progression.chapter_status().cleared.size()==3 and int(app.economy.wallet().origins)==int(wallet.origins)+200,"three real clears, exact 200 first-clear origins")
	app.show_page("chapter");await click("返回章节路线")
	check(app.screen=="story_route" and app.page.get_node("StoryRoute/Graph").current=="complete","chapter ending returns to completed route")
	check(app.page.get_node("StoryRoute").selected=="complete","ending detail displays the completed chapter, not previous boss")
	await shot("chapter-complete-route")
	completed=true
func run()->void:
	output="res://../artifacts/godot/chapter-navigation/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var path:="user://tests/chapter-novice-%d.json"%OS.get_process_id()
	var binary:="res://../target/cargo-v4-baseline/cas-sim.exe"
	if not FileAccess.file_exists(binary):binary="res://../target/release/cas-sim.exe"
	OS.set_environment("CAS_SIM_PATH",ProjectSettings.globalize_path(binary))
	app=Main.instantiate();app.boot_to_title=false;app.economy=Economy.new(path);root.add_child(app);app.set_process(false);await process_frame
	await exercise(path)
	check(completed,"complete new-player route and all three actual native missions")
	app.audio.shutdown();app.core.close();app.queue_free();await process_frame
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	var report:={"checks":checks,"passed":checks-failures.size(),"failures":failures,"battles":battles,"lessons":lessons,"screenshots":shots,"scope":"actual window pointer to route/card/sea/commit/clock/collect/extract/fire; real native time batches; no fabricated results or unlocks"}
	var file:=FileAccess.open(output+"novice-receipt.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close();print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
