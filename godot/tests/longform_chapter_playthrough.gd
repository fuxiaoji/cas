extends "res://tests/chapters_two_three_review.gd"
## Final default native core, an isolated new account and actual victory/reward transactions.
## Reading is accelerated for this engineering check; this is not a human reading-time trial.
var duration_by_chapter:Dictionary={}
var route_counts:Dictionary={}
func extract()->bool:
	var exit:Dictionary=app.core.view.salvage.exits[0].duplicate(true);exit["index"]=0
	var bounds:Dictionary=exit.get("bounds",{})
	if not bounds.is_empty():
		var region:=Rect2(Vector2(float(bounds.min_x),float(bounds.min_y)),Vector2(float(bounds.max_x)-float(bounds.min_x),float(bounds.max_y)-float(bounds.min_y)))
		if not app.core.view.ships.all(func(ship):return region.has_point(app.sea.pos(ship))):
			if not await player_route(Vector2(float(bounds.max_x)-400.0,region.get_center().y)):return false
			for wait in range(180):
				if app.core.view.ships.all(func(ship):return region.has_point(app.sea.pos(ship))):break
				if not step(1):return false
		command({"op":"speed","fleet":1,"speed":0});step(2)
	app.select_object("exit",exit);await process_frame
	if not await click("开始撤离"):return false
	check(app.core.view.salvage.get("extracting") is Dictionary,"real extraction starts after regrouping")
	return step(12)

func run()->void:
	output="res://../artifacts/godot/story-longform/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var path:="user://tests/story-longform-%d.json"%OS.get_process_id()
	app=Main.instantiate();app.boot_to_title=false;app.economy=Economy.new(path);root.add_child(app);app.set_process(false)
	await process_frame
	check(not app.progression.chapter_select("chapter-02").ok,"later chapter remains locked before real preceding ending")
	await whole_story(path)
	var report:Dictionary={"checks":checks,"passed":checks-failures.size(),"failures":failures,"completed":completed,"battles":new_battles,"simulated_seconds":duration_by_chapter,"route_counts":route_counts,"shots":shots,"scope":"18 actual native missions and client chapter progress; accelerated dialogue, not measured human reading"}
	var file:=FileAccess.open(output+"receipt.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	app.audio.shutdown();app.core.close();app.queue_free();await process_frame
	print(JSON.stringify(report));quit(0 if failures.is_empty() and completed else 1)

func launch(stage:String)->bool:
	var node:Dictionary=Content.stage(stage)
	app.set_meta("story_route_node",str(app.progression.chapter_status().node));app.show_page("story_route")
	await process_frame
	if not await click("进入作战简报") or not await click("进入作战"):return false
	await Settle.wait_for_route(self,app)
	if not check(app.screen=="battle" and str(app.core.view.chapter.stageId)==str(node.get("native_stage",stage)),"real native mapping "+stage):return false
	check(str(app.run.context.id)==stage,"logical stage stays in frozen client context "+stage)
	check(int(JSON.parse_string(str(app.economy.state.active_run.snapshot)).seed)==int(node.get("seed",6109)),"declared seeded mission variant "+stage)
	var goal:=str(node.get("goal_type",{"c1-breakout":"reach","c1-salvage":"archive","c1-boss":"boss"}.get(stage,"reach")))
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
	if str(node.get("native_stage",stage))=="c1-breakout":points=[Vector2(7400,1200),Vector2(7400,2200)]
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
	return true

func whole_story(path:String)->void:
	for chapter_id in ["chapter-01","chapter-02","chapter-03"]:
		check(app.progression.chapter_select(chapter_id).ok,"preceding ending genuinely unlocks "+chapter_id)
		var nodes:Array=Content.data(chapter_id).scenes
		route_counts[chapter_id]=nodes.size();duration_by_chapter[chapter_id]=0
		check(nodes.filter(func(n):return str(n.kind)=="battle").size()==6,"six actual action gates "+chapter_id)
		for node in nodes:
			if str(node.kind)!="battle":continue
			var stage:=str(node.stage)
			if not check(read_until(str(node.id)),"readable route reaches "+stage):return
			if not await launch(stage):return
			if node.has("native_stage") and stage in ["c1-rear-escort","c2-late-escort","c3-rescue-signal"]:
				var old_view:Dictionary=app.core.view.duplicate(true);var run_id:=str(app.run.run_id)
				app.save_leave();app.core.close();await process_frame
				var disk=Economy.new(path)
				check(disk.load_state().ok and str(disk.state.active_run.context.id)==stage,"logical mission identity survives disk save "+stage)
				app.resume_run();await Settle.wait_for_route(self,app)
				check(app.screen=="battle" and app.core.view==old_view and str(app.run.run_id)==run_id,"variant resumes exact native public snapshot "+stage)
			var initial:Dictionary=app.core.request({"op":"save","serialized":true})
			check(not app.progression.finish_mode(app.core.view,str(initial.serialized)).ok,"no reward before real terminal result "+stage)
			if str(node.get("goal_type",""))=="boss":
				for i in range(900):
					if app.core.view.get("result")!=null:break
					await evade_or_cruise()
					if not step(1):return
					await teach_entities()
			else:
				var archive:bool=str(node.get("goal_type",""))=="archive"
				var event:="archive_recovered" if archive else "beacon_reached"
				var rejoin_tick:int=-1
				for i in range(300):
					if archive:
						var ruin:Dictionary=app.core.view.salvage.ruins[0]
						if app.core.view.ships.any(func(ship):return app.sea.pos(ship).distance_to(app.sea.pos(ruin.p))<500):break
					elif app.core.view.chapter.events.has(event):break
					var threatened:bool=app.core.view.salvage.get("telegraphs",[]).any(func(w):return preload("res://scripts/monster_renderer.gd").threatens_fleet(app.core.view,w))
					if threatened and stage=="c2-maintenance-escort":
						await evade_or_cruise();rejoin_tick=int(app.core.view.tick)+4
					elif rejoin_tick>=0 and int(app.core.view.tick)>=rejoin_tick:
						var target:Vector2=app.sea.pos(app.core.view.chapter.objective.get("beacon",{}))
						if archive:target=app.sea.pos(app.core.view.salvage.ruins[0].p)+Vector2(450,0)
						if not await player_route(target):return
						rejoin_tick=-1
					if not step(1):return
					await teach_entities()
				if archive:
					command({"op":"speed","fleet":1,"speed":0});step(7)
					for i in range(10):
						if app.core.view.chapter.events.has(event):break
						if app.core.view.salvage.get("collecting")==null:await context_action("ruin",int(app.core.view.chapter.objective.get("archiveRuinId",1)))
						step(4)
				check(app.core.view.chapter.events.has(event),"native objective evidence "+stage)
				if not await extract():return
			var serial:Dictionary=app.core.request({"op":"save","serialized":true})
			var before:Dictionary=app.core.request({"op":"observe"}).data.duplicate(true)
			var replayed:Dictionary=app.core.request({"op":"replay","save":JSON.parse_string(str(serial.serialized))})
			check(replayed.get("ok",false) and replayed.get("data",{})==before,"command stream replays exact final world "+stage)
			new_battles.append({"stage":stage,"native_stage":node.get("native_stage",stage),"tick":app.core.view.tick,"seed":JSON.parse_string(str(serial.serialized)).seed,"chapter":app.core.view.chapter.duplicate(true)})
			duration_by_chapter[chapter_id]+=int(app.core.view.tick)
			var frozen:=FileAccess.open(output+stage+"-terminal.json",FileAccess.WRITE);frozen.store_string(str(serial.serialized));frozen.close()
			if not await return_after_win(stage,str(node.next),int(node.get("rewards",{}).get("origins",0))):return
			var saved_account=Economy.new(path)
			check(saved_account.load_state().ok,"disk read after actual settlement "+stage)
		var terminal:String="complete" if chapter_id=="chapter-01" else str(chapter_id).replace("chapter-0","c")+"-complete"
		check(read_until(terminal),"longform authored ending "+chapter_id)
		check(app.progression.chapter_status().cleared.size()==6,"six real wins persist "+chapter_id)
		app.show_page("story_route");await Settle.wait_for_route(self,app);await shot(chapter_id+"-route-complete")
	completed=true
