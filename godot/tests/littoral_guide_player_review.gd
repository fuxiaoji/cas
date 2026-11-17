extends "res://tests/littoral_drag_v2_review.gd"
## A player follows only the displayed teaching hand, never a better hidden route.
var tutorial_completed:bool=false
var followed:Array=[]
var realtime:bool=false
func run()->void:
	output_dir="res://../artifacts/littoral-drag/guide-player/"
	realtime=OS.get_environment("CAS_GUIDE_REALTIME")=="1"
	if realtime:output_dir="res://../artifacts/littoral-drag/guide-player-realtime/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	profile=output_dir+"isolated-guide-%d.json"%OS.get_process_id()
	var account=load("res://scripts/economy.gd").new(profile)
	if not check(account.load_state().get("ok",false),"fresh isolated ordinary player account"):return finish()
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.fullscreen_battle=true
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames();app.set_process(false);app.page_motion=false
	var prepared:Dictionary=app.home.prepare_littoral("tutorial",42,["MCP-034"],["IBS-U-USN-FLETCHER"],"balanced")
	if not check(prepared.get("ok",false),"normal borrowed tutorial plan"):return finish()
	app.launch_littoral(prepared.request);await frames()
	if not check(app.screen=="battle" and controller().tutorial.active,"actual first v2 tutorial and real overlay"):return finish()
	controller().interaction_event.connect(func(kind,data):events.append({"kind":kind,"data":data.duplicate(true),"tick":app.core.view.tick}))
	controller().tutorial.step_changed.connect(func(id,_index):steps.append({"step":id,"tick":app.core.view.tick}))
	controller().tutorial.completed.connect(func():tutorial_completed=true)
	check(controller().tutorial.get_node("Hint").size.y<=92,"real game theme keeps hint compact instead of hiding the island")
	await shot("00-player-sees-first-hand")
	if realtime:app.set_process(true)
	var attempted:Dictionary={};var deadline:int=Time.get_ticks_msec()+360000
	while app.screen=="battle" and float(app.core.view.tick)<330 and Time.get_ticks_msec()<deadline:
		var tutorial=controller().tutorial;var step:String=tutorial.current_step()
		var descriptor:Dictionary=tutorial.STEPS[tutorial._index]
		var from:String=str(descriptor.get("from",""));var to:String=str(descriptor.get("to",""))
		var actionable:bool=bool(descriptor.get("tap",false)) or not from.is_empty()
		if actionable and not attempted.has(step):
			await frames();controller()._update_tutorial_targets()
			var targets:Dictionary=tutorial._targets
			if not check(targets.has(to) and (from.is_empty() or targets.has(from)),"visible teaching hand has genuine from/to targets for "+step):break
			var end:Vector2=(targets[to] as Rect2).get_center();var start:Vector2=(targets[from] as Rect2).get_center() if not from.is_empty() else end
			attempted[step]=true;followed.append({"step":step,"from":from,"to":to,"start":{"x":start.x,"y":start.y},"end":{"x":end.x,"y":end.y},"tick":app.core.view.tick})
			print("GUIDE_PLAYER action "+step+" "+str(app.core.view.tick))
			await shot("hand-"+step)
			if bool(descriptor.get("tap",false)):
				var down:=InputEventMouseButton.new();down.position=screen_point(end);down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;Input.parse_input_event(down);await process_frame
				var up:=InputEventMouseButton.new();up.position=screen_point(end);up.button_index=MOUSE_BUTTON_LEFT;Input.parse_input_event(up);inputs+=2;await frames()
			else:await drag_from(start,end)
			if app.screen=="battle" and not events.is_empty() and str(events.back().kind)=="drag_rejected":check(false,"following real hand accepted at "+step+": "+str(events.back().data));break
		if app.screen!="battle":break
		if realtime:await create_timer(.1).timeout
		else:await advance(.1)
	check(app.screen=="result" and app.core.view.get("result")!=null,"following only teaching hand reaches actual terminal result")
	check(tutorial_completed,"guide completed signal waits for real extraction outcome")
	check(app.home.state().tutorial_complete and app.home.state().unlocked and app.home.state().units.has("MCP-034"),"true victory alone grants island and permanent 034")
	check(event_seen("return_ordered") and event_seen("extract_ordered"),"teaching hand includes actual sailing home and extraction gestures")
	await shot("player-real-result")
	FileAccess.open(output_dir+"followed-hands.json",FileAccess.WRITE).store_string(JSON.stringify({"realtime":realtime,"followed":followed,"steps":steps,"completed":tutorial_completed},"  "))
	finish()
