extends "res://tests/littoral_drag_v2_review.gd"
## Follow visible teaching hands, not hidden precomputed battle commands.
var tutorial_completed: bool = false
var followed: Array = []
var lesson: String = "landing"
var realtime: bool = false
func shot(title: String) -> void:
	if DisplayServer.get_name() == "headless":return
	await super.shot(title)
func run() -> void:
	lesson=OS.get_environment("CAS_TRAINING_LESSON")
	if lesson.is_empty():lesson="landing"
	realtime=OS.get_environment("CAS_TRAINING_REALTIME")=="1"
	output_dir="res://../artifacts/littoral-v4-ui/training/"+lesson+("-realtime/" if realtime else "/")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	profile=output_dir+"ordinary-%d.json"%OS.get_process_id()
	var account=load("res://scripts/economy.gd").new(profile)
	if not check(account.load_state().get("ok",false),"fresh isolated ordinary training profile"):return finish()
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.fullscreen_battle=true
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames();app.set_process(false);app.page_motion=false
	var prepared:Dictionary=app.home.prepare_littoral("tutorial",42,[],[],"balanced","cas-littoral-v4",lesson)
	if not check(prepared.get("ok",false),"normal service prepares actual borrowed "+lesson+": "+str(prepared)):return finish()
	app.set_meta("littoral_drag_help",true);app.launch_littoral(prepared.request);await frames()
	if not check(app.screen=="battle" and controller().tutorial.active,"actual progressive overlay opens for "+lesson):return finish()
	var initially_at_exit:bool=controller()._inside_exit()
	controller().interaction_event.connect(func(kind,data):events.append({"kind":kind,"data":data.duplicate(true),"tick":app.core.view.tick}))
	controller().tutorial.step_changed.connect(func(id,_index):steps.append({"step":id,"unit":controller().tutorial.unit_id,"tick":app.core.view.tick}))
	controller().tutorial.completed.connect(func():tutorial_completed=true)
	check(app.home.state().units.is_empty(),"training loans do not permanently grant units before victory")
	check(controller().tutorial.get_node("Hint").size.y<=92,"guidance stays compact with production font")
	await shot("00-first-visible-hand")
	if realtime:app.set_process(true)
	var attempted: Dictionary={};var deadline: int=Time.get_ticks_msec()+360000
	while app.screen=="battle" and float(app.core.view.tick)<1200 and Time.get_ticks_msec()<deadline:
		var tutorial=controller().tutorial;var step: String=tutorial.current_step()
		var descriptor: Dictionary=tutorial._steps()[tutorial._index]
		var from: String=str(descriptor.get("from",""));var to: String=str(descriptor.get("to",""))
		var attempt_key: String=step+":"+str(tutorial.unit_id)
		var actionable: bool=bool(descriptor.get("tap",false)) or not from.is_empty()
		if actionable and not attempted.has(attempt_key):
			await frames();controller()._update_tutorial_targets()
			var targets: Dictionary=tutorial._targets
			if not check(targets.has(to) and (from.is_empty() or targets.has(from)),"visible gesture has real targets "+attempt_key):break
			var end: Vector2=(targets[to] as Rect2).get_center();var start: Vector2=(targets[from] as Rect2).get_center() if not from.is_empty() else end
			attempted[attempt_key]=true;followed.append({"step":step,"unit":tutorial.unit_id,"from":from,"to":to,"start":{"x":start.x,"y":start.y},"end":{"x":end.x,"y":end.y},"tick":app.core.view.tick})
			print("TRAINING_PLAYER "+lesson+" "+attempt_key+" "+str(app.core.view.tick))
			await shot("hand-%02d-%s"%[followed.size(),step])
			if bool(descriptor.get("tap",false)):
				var down:=InputEventMouseButton.new();down.position=screen_point(end);down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;Input.parse_input_event(down);await process_frame
				var up:=InputEventMouseButton.new();up.position=screen_point(end);up.button_index=MOUSE_BUTTON_LEFT;Input.parse_input_event(up);inputs+=2;await frames()
			else:await drag_from(start,end)
			if app.screen=="battle" and not events.is_empty() and str(events.back().kind)=="drag_rejected":check(false,"visible hand drag accepted "+attempt_key+": "+str(events.back().data));break
		if app.screen!="battle":break
		if realtime:await create_timer(.1).timeout
		else:await advance(.1)
	check(app.screen=="result" and app.core.view.get("result")!=null,"only visible gestures reach real terminal outcome "+lesson)
	check(tutorial_completed,"teaching completion waits for actual native extraction")
	check(app.home.state().tutorial_complete and app.home.state().unlocked,"actual training victory unlocks island")
	check((event_seen("return_ordered") or initially_at_exit) and event_seen("extract_ordered"),"actual fleet reaches extraction region, including a genuinely already-docked initial fleet")
	await shot("real-result")
	FileAccess.open(output_dir+"followed-hands.json",FileAccess.WRITE).store_string(JSON.stringify({"lesson":lesson,"realtime":realtime,"followed":followed,"steps":steps,"completed":tutorial_completed,"last_view":app.core.view},"  "))
	finish()
