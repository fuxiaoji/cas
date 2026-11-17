extends "res://tests/littoral_drag_v2_review.gd"
## Isolated normal Boot, authored graph and native action outcomes. Accelerated
## reading is an engineering check, never a claim about human chapter duration.
const BootScene=preload("res://scenes/boot.tscn")
const Service=preload("res://scripts/canon_story_service.gd")
const Data=preload("res://scripts/canon_story_data.gd")
const Actions=preload("res://scripts/canon_story_actions.gd")
const Economy=preload("res://scripts/economy.gd")
var boot
var service
var records:Array=[]
var legacy:Dictionary={}
var completed:Array=[]
var node_counts:Dictionary={}
var full:bool=false
var dodged:Dictionary={}
func selected_chapters()->Array:
	var requested:String=OS.get_environment("CAS_CANON_CHAPTERS")
	return requested.split(",") if not requested.is_empty() else Data.IDS

func go(route:String)->bool:
	app.show_page(route)
	return check(await app.wait_for_page(route),"normal staged page "+route)

func run()->void:
	output_dir="res://../artifacts/story-modernization-v3/runtime-%d/"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	profile=output_dir+"ordinary.json"
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720)
	root.position=Vector2i(6000,6000)
	var results:Array=[]
	boot=BootScene.instantiate();boot.profile_override=ProjectSettings.globalize_path(profile)
	boot.immersive_fullscreen=false
	boot.boot_completed.connect(func(value):results.append(value));root.add_child(boot)
	var deadline:int=Time.get_ticks_msec()+60000
	while results.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	if not check(not results.is_empty() and results[0].get("ok",false),"formal Boot loads isolated ordinary account"):await finish();return
	app=boot.app;app.set_process(false);app.page_motion=false
	app.immersive_fullscreen=false
	service=Service.new(app.economy)
	legacy=app.economy.state.progression.duplicate(true)
	if not graph():await finish();return
	if not await go("canon_catalog"):await finish();return
	check(service.enabled() and str(service.node().id)=="v2c1-drifting","fresh ordinary account has begun actual first-person chapter one")
	check(not service.select("chapter-02").ok,"new canon chapter two initially locked")
	check(service.select("chapter-01").ok,"explicit new canon start succeeds")
	if not await go("canon_story"):await finish();return
	check(app.page.get_node_or_null("CanonStory")!=null,"editable canon stage instantiated")
	full=OS.get_environment("CAS_CANON_FULL")=="1"
	await walk()
	if full:check(completed.size()==selected_chapters().size(),"full walk actually reaches selected authored endings")
	for key in ["chapter1","chapter2","chapter3","story","campaign"]:
		if legacy.has(key):check(app.economy.state.progression.get(key)==legacy.get(key),"frozen legacy progress unchanged: "+key)
		elif app.economy.state.progression.has(key):check(app.economy.state.progression[key].get("cleared",{}).is_empty() and app.economy.state.progression[key].get("claimed",{}).is_empty(),"old default state initialized by existing menu without old clear/reward "+key)
	await finish()

func graph()->bool:
	var allowed:Array=["native_battle","harbor_tour","arena_ranked","arena_3v3","growth","salvage_tutorial","littoral_sea","littoral_landing","littoral_combined","home_build","home_garrison","fixed_recruit","island_defense"]
	for id in selected_chapters():
		var data:Dictionary=Data.chapter(id)
		if not check(not data.is_empty(),"authored JSON exists "+id):return false
		var found:Dictionary={}
		for node in data.scenes:
			check(not found.has(str(node.id)),"unique node "+str(node.id));found[str(node.id)]=true
			var action:String=Data.action(node)
			if not action.is_empty():check(allowed.has(action),"implemented action "+action)
		check(found.has(str(data.entry)),"entry resolves "+id)
		for node in data.scenes:
			for key in ["next","success_next","failure_next"]:
				if node.has(key) and not str(node[key]).is_empty():check(found.has(str(node[key])),"edge resolves "+str(node.id)+" "+key)
			for next in node.get("choice_next",{}).values():check(found.has(str(next)),"choice resolves "+str(node.id))
		node_counts[id]=found.size()
	return failures.is_empty()

func walk()->void:
	for id in selected_chapters():
		if not check(service.select(id).ok,"select after actual preceding ending "+id):return
		for iteration in range(350):
			var node:Dictionary=service.node();var kind:String=str(node.get("kind",""));var action:String=Data.action(node)
			if kind=="complete":
				check(service.move("complete").ok,"chapter ending persists "+id);completed.append(id);break
			if kind=="dialogue":
				service.move("skip")
				if str(service.node().id)!=str(node.id):continue
				if not node.get("choices",[]).is_empty():check(service.move("choice",str(node.choices[0].id)).ok,"actual authored choice "+str(node.id))
				else:check(service.move("next").ok,"dialogue reads "+str(node.id))
				continue
			check(not service.move("skip").ok,"dialogue skip cannot complete action "+str(node.id))
			if action in ["arena_ranked","arena_3v3"]:
				# Optional path must remain possible without a forced PvP match.
				check(bool(node.get("optional",false)) and service.move("defer").ok,"optional PvP defer persists "+action);continue
			if not await perform(node):return
			if not full and action=="salvage_tutorial":return

func perform(node:Dictionary)->bool:
	var action:String=Data.action(node);var id:String=str(node.id)
	print("CANON_ACTION "+id+" "+action)
	if action=="harbor_tour":
		for route in Service.TOUR:
			if route=="ship_detail":app.set_meta("detail_ship_id",str(app.economy.formation[0]))
			if not await go(route):return false
	elif action=="growth":
		app.set_meta("detail_ship_id",str(app.economy.formation[0]))
		if not await go("ship_detail"):return false
	elif action=="home_build":
		for kind in ["recycler","solar"]:
			var built:bool=false
			for x in range(3,9):
				for y in range(2,7):
					if not built and app.home.is_land(Vector2i(x,y)) and app.home.building_at(Vector2i(x,y)).is_empty():
						built=bool(app.home.place(kind,Vector2i(x,y)).get("ok",false))
			if not check(built,"actual ordinary island construction "+kind):return false
	elif action=="home_garrison":
		if not check(app.home.set_garrison([str(app.economy.formation[0])]).ok,"actual saved naval garrison"):return false
		if not check(app.home.set_tactical_garrison(["MCP-034","MCP-011"]).ok,"actual saved tactical garrison"):return false
	elif action=="fixed_recruit":
		var currency:Dictionary=app.economy.wallet().duplicate(true)
		if not check(service.redeem_protocol(app.home).ok,"fixed unique MCP011 redemption after return"):return false
		check(not service.redeem_protocol(app.home).ok and currency==app.economy.wallet(),"cannot redeem same protocol twice or duplicate-currency it")
		records.append({"node":id,"action":action,"transaction":service.state().transactions.duplicate(true)});return true
	else:
		if not await go("canon_story"):return false
		if action=="island_defense":
			if not check(app.home.set_tactical_garrison(["MCP-034","MCP-011"]).ok,"two actual owned units garrison island"):return false
		var launched:Dictionary=await Actions.launch(app)
		if not check(launched.get("ok",false),"real launch "+id+": "+str(launched.get("message",""))):return false
		if not check(app.screen=="battle" and is_instance_valid(app.sea) and app.battle_controller!=null,"native map ready after staged launch "+id):return false
		check(not app.page.has_node("CanonActionGuide"),"no extra objective panel over battlefield")
		var pending:Dictionary=service.state().pending
		check(str(pending.run_id)==str(app.economy.state.active_run.run_id),"story is bound to actual run "+id)
		check(not service.check_action(app.home).ok,"no receipt means no story completion "+id)
		if action in ["native_battle","salvage_tutorial"]:
			if not await solve_native(node):return false
		elif action in ["littoral_sea","littoral_landing","littoral_combined"]:
			if not await solve_tutorial():return false
		elif action=="island_defense":
			# An explicitly saved actual retreat is allowed ONLY for this dramatic
			# defense. It never fabricates a win or awards victory resources.
			await advance(4.0)
			if not check(app.issue({"op":"littoral_abandon"}).get("ok",false),"actual island retreat command"):return false
			if not app.run.is_empty():app.finish_battle()
		else:return check(false,"missing test player for "+action)
		await app.wait_for_page("result")
		if not check(app.economy.state.active_run.is_empty(),"actual terminal settlement "+id):return false
		var receipt:Dictionary=app.last_receipt.duplicate(true)
		records.append({"node":id,"action":action,"run_id":receipt.get("run_id"),"actual_success":receipt.get("success"),"tick":app.core.view.get("tick"),"events":app.core.view.get("chapter",{}).get("events",[])})
	var advanced:Dictionary=service.check_action(app.home)
	if not check(advanced.get("ok",false),"verified actual action proof "+id+": "+str(advanced.get("message",""))):return false
	var disk=Economy.new(profile)
	check(disk.load_state().ok and disk.state.progression.get(Service.KEY)==JSON.parse_string(JSON.stringify(service.state())),"new canon proof and choices survive real file reload "+id)
	return true

func native_command(value:Dictionary)->bool:
	var reply:Dictionary=app.issue(value)
	if not reply.get("ok",false):FileAccess.open(output_dir+"command-failure.json",FileAccess.WRITE).store_string(JSON.stringify({"command":value,"reply":reply,"view":app.core.view},"\t"))
	return check(reply.get("ok",false),"accepted native command "+str(value.get("op",""))+" "+str(reply.get("error","")))

func native_step(seconds:int)->bool:
	var remaining:int=seconds
	while remaining>0 and app.core.view.get("result")==null:
		if not native_command({"op":"step","seconds":mini(remaining,180)}):return false
		remaining-=180
	return true

func solve_native(node:Dictionary)->bool:
	var stage:String=str(node.get("native_stage",""))
	if str(app.core.view.get("chapter",{}).get("missionProfile",""))=="canon-missions-v3":
		return await solve_current_native(stage)
	var goal:String=str(preload("res://scripts/chapter_story_data.gd").stage(stage).get("goal_type","reach"))
	if not check(app.page.has_node("ChapterBattleGuide"),"existing state-driven native chapter guide retained"):return false
	if stage=="c1-breakout":
		if not native_command({"op":"route","fleet":1,"mode":"follow","speed":20,"points":[{"x":7400,"y":1200},{"x":7400,"y":2200}]}):return false
		if not native_step(360):return false
		var run_id:String=str(app.run.run_id);var tick:int=int(app.core.view.tick)
		app.save_leave();await app.wait_for_page("canon_story");app.core.close()
		var disk=Economy.new(profile);check(disk.load_state().ok and str(disk.state.active_run.run_id)==run_id,"actual paused run persists alongside story")
		await Actions.launch(app)
		check(app.screen=="battle" and int(app.core.view.tick)==tick and str(app.run.run_id)==run_id,"same native tick and identity resume after process close")
		# Do not idle under monster fire after reaching the real extraction gate.
		for retry in range(180):
			if app.core.view.chapter.events.has("beacon_reached"):break
			if not native_step(1):return false
	elif goal=="boss":
		if not native_command({"op":"route","fleet":1,"mode":"follow","speed":24,"points":[{"x":8000,"y":1200}]}):return false
		for retry in range(1100):
			if app.core.view.get("result")!=null:break
			evade()
			if not native_step(1):return false
	elif goal=="archive" or stage=="c1-salvage":
		var ruin:Dictionary=app.core.view.salvage.ruins[0]
		for row in app.core.view.salvage.ruins:
			if int(row.id)==int(app.core.view.chapter.objective.get("archiveRuinId",1)):ruin=row
		if not native_command({"op":"route","fleet":1,"mode":"follow","speed":20,"points":[{"x":float(ruin.p.x)+1100,"y":float(ruin.p.y)}]}):return false
		for retry in range(1000):
			if app.core.view.ships.any(func(ship):return app.sea.pos(ship).distance_to(app.sea.pos(ruin.p))<500):break
			if not native_step(1):return false
		if not native_command({"op":"speed","fleet":1,"speed":0}) or not native_step(7):return false
		for retry in range(4):
			if app.core.view.chapter.events.has("archive_recovered"):break
			if not native_command({"op":"salvage_collect","ruin":int(ruin.id)}):return false
			if not native_step(8):return false
	else:
		var beacon:Dictionary=app.core.view.chapter.objective.get("beacon",{"x":6500,"y":2200})
		if not native_command({"op":"route","fleet":1,"mode":"follow","speed":20,"points":[{"x":float(beacon.x)+200,"y":1200},{"x":float(beacon.x)+200,"y":float(beacon.y)}]}):return false
		for retry in range(1000):
			if app.core.view.chapter.events.has("beacon_reached") or app.core.view.get("result")!=null:break
			evade()
			if not native_step(1):return false
	if app.core.view.get("result")==null:
		var bounds:Dictionary=app.core.view.salvage.exits[0].get("bounds",{})
		if not bounds.is_empty():
			var region:=Rect2(Vector2(float(bounds.min_x),float(bounds.min_y)),Vector2(float(bounds.max_x)-float(bounds.min_x),float(bounds.max_y)-float(bounds.min_y)))
			# The last destroyer may be just outside the box while the current legal
			# route already takes her inside. Allow her to close up before replotting.
			for retry in range(12):
				if app.core.view.ships.all(func(ship):return region.has_point(app.sea.pos(ship))):break
				if not native_step(1):return false
			if not app.core.view.ships.all(func(ship):return region.has_point(app.sea.pos(ship))):
				var target:Vector2=Vector2(float(bounds.max_x)-400,region.get_center().y)
				var origin:Vector2=app.sea.pos(app.core.view.ships[0]);var chosen:Dictionary={}
				for offset in [0.0,1500.0,-1500.0,2600.0,-2600.0]:
					var points:Array=[{"x":target.x,"y":target.y}] if offset==0 else [{"x":clampf(origin.x+offset,2500,15000),"y":700 if origin.y>1400 else 2400},{"x":target.x,"y":target.y}]
					var request:Dictionary={"op":"preview_route","fleet":1,"mode":"follow","speed":20,"points":points}
					var preview:Dictionary=app.core.request(request)
					if preview.get("ok",false) and preview.get("data",{}).get("valid",false):chosen=request;chosen.op="route";break
				if not check(not chosen.is_empty(),"legal turning route back into extraction region") or not native_command(chosen):return false
				for retry in range(220):
					if app.core.view.ships.all(func(ship):return region.has_point(app.sea.pos(ship))):break
					if not native_step(1):return false
			if not native_command({"op":"speed","fleet":1,"speed":0}) or not native_step(2):return false
		if not native_command({"op":"salvage_extract","exit":0}) or not native_step(12):return false
	if not check(app.core.view.get("result") is Dictionary and app.core.view.result.get("winner")=="allies","native victory "+stage):
		FileAccess.open(output_dir+stage+"-failed-view.json",FileAccess.WRITE).store_string(JSON.stringify(app.core.view,"\t"));return false
	if not app.run.is_empty():app.finish_battle()
	return true

func solve_current_native(stage:String)->bool:
	# These are reviewed real public player commands from the nine-stage native
	# playthrough, never snapshots with fabricated hull positions or outcomes.
	var path:String="res://../artifacts/story-modernization-v3/%s-commands.json"%stage
	if not check(FileAccess.file_exists(path),"current story legal playthrough exists "+stage):return false
	var calls:Array=JSON.parse_string(FileAccess.get_file_as_string(path))
	for request in calls:
		var op:String=str(request.get("op",""))
		if op in ["new_chapter","observe","save","load","replay","preview_route"]:continue
		# The transcript deliberately verifies that seeing an archive cannot
		# bypass stowing it. Those expected rejections are checked by the native
		# test and do not count as errors in this UI playthrough.
		if op=="salvage_extract" and not bool(app.core.view.get("salvage",{}).get("cargo_grid",{}).get("items",[]).is_empty()):
			var carried:bool=app.core.view.salvage.cargo_grid.items.any(func(item):return item.get("kind")=="archive" and item.get("placement")!=null)
			if not carried and str(app.core.view.chapter.objective.kind)=="search_stow_extract":continue
		if app.core.view.get("result")!=null:break
		if not native_command(request):return false
		if op=="step" and int(app.core.view.tick)%12==0:await process_frame
	if not check(app.core.view.get("result") is Dictionary and bool(app.core.view.result.get("primary",false)),"current native real victory "+stage):return false
	if not app.run.is_empty():app.finish_battle()
	return true

func evade()->void:
	if app.core.view.ships.is_empty():return
	var warning_seen:bool=false
	for warning in app.core.view.salvage.get("telegraphs",[]):
		var key:String=str(app.run.get("run_id",""))+":"+str(warning.get("id",warning.get("resolve_at",0)))
		if not dodged.has(key) and preload("res://scripts/monster_renderer.gd").threatens_fleet(app.core.view,warning):
			dodged[key]=true;warning_seen=true
	if not warning_seen:return
	var point:Vector2=app.sea.pos(app.core.view.ships[0]);var destination:Vector2=Vector2(3600 if point.x>6500 else 10700,650 if point.y>1400 else 2300)
	var speed:float=24
	for ship in app.core.view.ships:speed=minf(speed,floorf(float(ship.get("systems",{}).get("maxSpeed",speed))))
	for x in [0.0,-1500.0,1500.0,2600.0,-2600.0]:
		var points:Array=[{"x":destination.x,"y":destination.y}] if x==0 else [{"x":clampf(point.x+x,2300,15000),"y":650 if point.y>1400 else 2400},{"x":destination.x,"y":destination.y}]
		var request:Dictionary={"op":"preview_route","fleet":1,"mode":"follow","speed":maxf(4,speed),"points":points}
		var preview:Dictionary=app.core.request(request)
		if preview.get("ok",false) and preview.get("data",{}).get("valid",false):
			request.op="route";native_command(request);return

func solve_tutorial()->bool:
	var attempted:Dictionary={};var deadline:int=Time.get_ticks_msec()+240000
	while app.screen=="battle" and float(app.core.view.tick)<1200 and Time.get_ticks_msec()<deadline:
		var tutorial=controller().tutorial
		var descriptor:Dictionary=tutorial._steps()[tutorial._index]
		var from:String=str(descriptor.get("from",""));var to:String=str(descriptor.get("to",""))
		var key:String=tutorial.current_step()+":"+str(tutorial.unit_id)
		if (bool(descriptor.get("tap",false)) or not from.is_empty()) and not attempted.has(key):
			await frames()
			if app.core.view.get("result")!=null or app.screen!="battle" or not is_instance_valid(tutorial):break
			controller()._update_tutorial_targets()
			var targets:Dictionary=tutorial._targets
			if not check(targets.has(to) and (from.is_empty() or targets.has(from)),"teaching targets exist "+key):return false
			var end:Vector2=(targets[to] as Rect2).get_center();var start:Vector2=(targets[from] as Rect2).get_center() if not from.is_empty() else end
			attempted[key]=true
			if bool(descriptor.get("tap",false)):
				var down:=InputEventMouseButton.new();down.position=screen_point(end);down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;Input.parse_input_event(down);await process_frame
				var up:=InputEventMouseButton.new();up.position=screen_point(end);up.button_index=MOUSE_BUTTON_LEFT;Input.parse_input_event(up);await frames()
			else:await drag_from(start,end)
		if app.screen!="battle":break
		await advance(.1)
	return check(app.core.view.get("result")!=null and app.last_receipt.get("success",false),"visible tutorial gestures reach actual victory")

func finish()->void:
	if is_instance_valid(app):app.running=false;app.core.close()
	if is_instance_valid(boot):boot.queue_free();await frames(5)
	check(FileAccess.get_sha256("user://cas_port_v1.json")==main_hash,"normal main account untouched")
	check(FileAccess.get_sha256("user://cas_port_v1.json.bak")==backup_hash,"normal backup account untouched")
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"records":records,"completed_chapters":completed,"node_counts":node_counts,"profile":ProjectSettings.globalize_path(profile),"full_walk":full,"display_server":DisplayServer.get_name(),"scope":"isolated real Boot, production scenes, actual tutorial gestures and native outcomes; accelerated reading and command-driven naval playthrough, not measured human duration or full manual UI coverage"}
	FileAccess.open(output_dir+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CANON_V2 "+JSON.stringify(report));quit(0 if failures.is_empty() else 1)
