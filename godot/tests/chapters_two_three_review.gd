extends "res://tests/adventure_presentation_review.gd"
## All unlocks, reward claims and nine battle outcomes are real native/client transactions.
var new_battles:Array=[]
func run()->void:
	output="res://../artifacts/godot/chapters-two-three/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var path:="user://tests/three-chapters-%d.json"%OS.get_process_id()
	app=Main.instantiate();app.boot_to_title=false;app.economy=Economy.new(path);root.add_child(app);app.set_process(false)
	await process_frame
	check(not app.progression.chapter_select("chapter-02").ok,"chapter2 cannot unlock before chapter1 actual ending")
	await super.exercise(path)
	output="res://../artifacts/godot/chapters-two-three/"
	if completed:
		completed=false
		await chapters(path)
	if completed:await local_intel_boundary()
	check(completed,"complete chapters2 and3 through all six actual missions")
	var report:Dictionary={"checks":checks,"passed":checks-failures.size(),"failures":failures,"battles":battles,"new_battles":new_battles,"shots":shots,"terrains":terrain_signatures}
	var file:=FileAccess.open(output+"receipt.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	app.audio.shutdown();app.core.close();app.queue_free();await process_frame
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)

func launch(stage:String)->bool:
	if stage.begins_with("c1-"):return await super.launch(stage)
	app.set_meta("story_route_node",str(app.progression.chapter_status().node));app.show_page("story_route")
	await process_frame
	if not await click("进入作战简报") or not await click("进入作战"):return false
	await Settle.wait_for_route(self,app)
	if not check(app.screen=="battle" and str(app.core.view.chapter.stageId)==stage,"real chapter launch "+stage):return false
	var node:Dictionary=Content.stage(stage)
	var goal:=str(node.get("goal_type",{"c1-breakout":"reach","c1-salvage":"archive","c1-boss":"boss"}.get(stage,"reach")))
	terrain_signatures[stage]={"theme":app.core.view.salvage.terrainTheme,"geometry":hash(app.core.view.islands)}
	await press(app.battle_controller.hud.fleet_cards[int(app.core.view.ships[0].id)].button)
	app.battle_controller.show_tab("fleet");await process_frame
	for control in app.find_children("*","HSlider",true,false):
		if control.is_visible_in_tree():control.value=30 if goal=="boss" else 20;break
	await press(app.battle_controller.hud.tactical_button)
	lesson("plot")
	if not await click("准备画航线"):return false
	var objective:Dictionary=app.core.view.chapter.objective
	var target:Vector2=app.sea.pos(objective.get("beacon") if objective.get("beacon") is Dictionary else {"x":6500,"y":2200})
	if goal=="archive":
		for ruin in app.core.view.salvage.ruins:
			if int(ruin.id)==int(objective.get("archiveRuinId",1)):target=app.sea.pos(ruin.p)
	var points:Array=[Vector2(8000,1200)] if goal=="boss" else [target]
	if goal=="reach":points=[Vector2(target.x+200.0,1200),Vector2(target.x+200.0,target.y)]
	if goal=="archive":points=[Vector2(target.x+1100.0,target.y)]
	if stage=="c1-breakout":points=[Vector2(7400,1200),Vector2(7400,2200)]
	app.sea.zoom=1.2;app.sea.pan=Vector2.ZERO
	app.sea.pan=Vector2(app.sea.size.x*.62,app.sea.size.y*.53)-app.sea.project(points[0])
	for point in points:
		await pointer(app.sea,app.sea.project(point),true);await pointer(app.sea,app.sea.project(point),false)
	if not await click("下达航线"):return false
	if goal=="boss":await manual_gun()
	if not await click("开始") or not step(1):return false
	await teach_entities()
	if goal=="boss":
		await focus_boss()
		app.battle_controller.show_tab("ai");await process_frame
		for control in app.find_children("*","CheckBox",true,false):
			if control.is_visible_in_tree() and control.text=="雷击" and not control.button_pressed:await press(control);break
		await press(app.battle_controller.hud.tactical_button)
	await shot(stage+"-launch")
	return true

func chapters(path:String)->void:
	for chapter_id in ["chapter-02","chapter-03"]:
		check(app.progression.chapter_select(chapter_id).ok,"actual preceding ending unlocks "+chapter_id)
		app.show_page("story_catalog");await shot(chapter_id+"-catalog")
		var nodes:Array=Content.data(chapter_id).scenes
		check(nodes.size()==14,"chapter has14 authored route nodes "+chapter_id)
		for node in nodes:
			if str(node.kind)!="battle":continue
			if not check(read_until(str(node.id)),"narrative reaches actual battle gate "+str(node.id)):return
			if not await launch(str(node.stage)):return
			if str(node.stage) in ["c2-convoy","c3-crossing"]:
				var before_tick:int=int(app.core.view.tick);var run_id:String=str(app.run.run_id)
				var before_view:Dictionary=app.core.view.duplicate(true)
				app.save_leave();app.core.close();await process_frame
				var interrupted=Economy.new(path)
				check(interrupted.load_state().ok and str(interrupted.state.active_run.context.chapter_id)==chapter_id,"active chapter session persisted with exact chapter identity")
				app.resume_run();await Settle.wait_for_route(self,app)
				check(app.screen=="battle" and int(app.core.view.tick)==before_tick and str(app.run.run_id)==run_id and app.core.view==before_view,"closed native process resumes exact public chapter state")
			var current:Dictionary=app.core.request({"op":"save","serialized":true})
			check(not app.progression.finish_mode(app.core.view,str(current.serialized)).ok,"no early chapter reward "+str(node.stage))
			await intel_detail()
			if str(node.goal_type)=="boss":
				for i in range(900):
					if app.core.view.get("result")!=null:break
					await evade_or_cruise()
					if not step(1):return
					await teach_entities();await observe_threats(str(node.stage))
			else:
				var event:="archive_recovered" if str(node.goal_type)=="archive" else "beacon_reached"
				for i in range(70):
					if str(node.goal_type)=="archive":
						var ruin:Dictionary=app.core.view.salvage.ruins[0]
						if app.core.view.ships.any(func(ship):return app.sea.pos(ship).distance_to(app.sea.pos(ruin.p))<500):break
					elif app.core.view.chapter.events.has(event):break
					if not step(3):return
					await teach_entities();await observe_threats(str(node.stage))
				if str(node.goal_type)=="archive":
					command({"op":"speed","fleet":1,"speed":0})
					step(7)
					for i in range(10):
						if app.core.view.chapter.events.has(event):break
						if app.core.view.salvage.get("collecting")==null:await context_action("ruin",int(app.core.view.chapter.objective.get("archiveRuinId",1)))
						step(4)
				check(app.core.view.chapter.events.has(event),"actual target evidence "+str(node.stage))
				if not await extract():return
			var serial:Dictionary=app.core.request({"op":"save","serialized":true})
			var before_replay:Dictionary=app.core.view.duplicate(true)
			var replayed:Dictionary=app.core.request({"op":"replay","save":JSON.parse_string(str(serial.serialized))})
			check(replayed.get("ok",false) and replayed.get("data",{})==before_replay,"actual saved native command stream replays exact chapter outcome")
			var frozen:=FileAccess.open(output+str(node.stage)+"-terminal.json",FileAccess.WRITE);frozen.store_string(str(serial.serialized));frozen.close()
			new_battles.append({"stage":node.stage,"tick":app.core.view.tick,"chapter":app.core.view.chapter.duplicate(true)})
			if not await return_after_win(str(node.stage),str(node.next),int(node.rewards.origins)):return
			var disk=Economy.new(path);check(disk.load_state().ok,"account reload after "+str(node.stage))
			var key:="chapter2" if chapter_id=="chapter-02" else "chapter3"
			check(disk.state.progression[key]==JSON.parse_string(JSON.stringify(app.economy.state.progression[key])),"chapter rewards and route survive restart "+str(node.stage))
		check(read_until(chapter_id.replace("chapter-0","c")+"-complete"),"reach chapter ending "+chapter_id)
		check(app.progression.chapter_status().cleared.size()==3,"three real clears in isolated chapter state")
		await visuals(chapter_id)
	completed=true

func intel_detail()->void:
	for contact in app.core.view.contacts:
		if not contact.has("intelligence") or not contact.has("attack"):continue
		app.select_object("contact",contact);await process_frame
		var intel:Control=app.sea.monster_intel;intel.update_observation(app.core.view,str(contact.id),false)
		check(intel.get_node("Card/Margin/Rows/Header/Details").visible,"native detailed intelligence opt-in button")
		await press(intel.get_node("Card/Margin/Rows/Header/Details"))
		check(intel.get_node("DetailPanel").visible,"player opens enemy data panel")
		check(intel.get_node("DetailPanel/Margin/Rows/Content/Stats/Speed").text.contains(str(contact.intelligence.speed_max)),"speed uses actual native public value")
		await shot(str(app.core.view.get("chapter",{}).get("stageId","exercise"))+"-enemy-detail")
		await press(intel.get_node("DetailPanel/Margin/Rows/Header/Close"))
		app.select_object("ship",app.core.view.ships[0]);return

func visuals(chapter_id:String)->void:
	for node in Content.data(chapter_id).scenes:
		if str(node.kind)!="dialogue":continue
		app.set_meta("chapter_replay_node",str(node.id));app.set_meta("chapter_replay_line",1 if str(node.id) in ["c2-rations","c3-lighthouse"] else 0);app.show_page("chapter")
		await process_frame
		if bool(node.get("cg",false)):await shot(str(node.id)+"-cg")
		elif str(node.id) in ["c2-rations","c3-lighthouse"]:
			await create_timer(5.2).timeout
			var animated:=false
			for actor in app.page.get_node("ChapterStage/Cast").get_children():
				var face:Node=actor.get_node_or_null("FaceAnimation")
				if face!=null:animated=animated or (face.blink_count>0 and face.talk_count>0)
			check(animated,"real elapsed blinking and speaking without stage rebuild")
			await shot(str(node.id)+"-actors")
	app.remove_meta("chapter_replay_node");app.remove_meta("chapter_replay_line")

func local_intel_boundary()->void:
	app.start_local_mode({"op":"new","seed":6109,"intel_profile":"open-intel-v1"},{"mode":"exercise","id":"intel-review","title":"敌情观察","side":"allies"})
	await Settle.wait_for_route(self,app)
	check(app.screen=="battle" and app.core.view.get("salvage")==null,"plain nonhistorical exercise really starts without salvage/adventure")
	check(app.core.view.get("contacts",[]).all(func(row):return row.has("intelligence") and row.has("health")),"ordinary naval enemies expose explicit native public intelligence")
	await intel_detail()
	var bridge=preload("res://scripts/core_bridge.gd").new()
	var original:Dictionary=bridge.request({"op":"new_campaign","id":"CAMP-ALLIES-02","difficulty":"standard","seed":6109,"profile":"coord"})
	check(original.get("ok",false) and original.data.get("contacts",[]).all(func(row):return not row.has("intelligence")),"actual historical native observation has no open information extension")
	app.sea.monster_intel.update_observation(original.data,"C01",false)
	check(not app.sea.monster_intel.visible,"real historical observation cannot open enemy detail")
	bridge.close();app.save_leave()

