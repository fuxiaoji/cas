extends SceneTree
## Real default-core firing and Tide damage; synthetic terminal/cursor cases are labeled fixtures.
const Core=preload("res://scripts/core_bridge.gd")
var core=Core.new()
var sea:Control
var feedback:Control
var checks:=0
var failures:Array[String]=[]
var results:Array[Dictionary]=[]
var clicked:=Vector2.INF
var output:="res://../artifacts/godot/combat-feel/"
func _initialize()->void:call_deferred("run")
func check(value:bool,title:String)->void:
	checks+=1
	if not value:failures.append(title);push_error(title)
func show_view(view:Dictionary)->void:
	sea.view=view;feedback.observe(view);sea.queue_redraw()
func shot(name:String)->void:
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output+name+".png"))
func fire_case(identity:String,expected_mm:float,name:String)->void:
	var ships:Array[String]=[identity]
	for id in ["IBS-U-USN-FLETCHER","IBS-U-USN-HONOLULU","IBS-U-USN-SAN-FRANCISCO","IBS-U-USN-WASHINGTON","IBS-U-USN-PERKINS"]:
		if id!=identity:ships.append(id)
	var response:Dictionary=core.request({"op":"new","seed":6106,"side":"allies","enemy":"gunnery","profile":"gunnery","realtime":true,"ships":ships})
	check(response.get("ok",false),"real native start "+name)
	if not response.get("ok",false):print(response);return
	sea.view=core.view;sea.selected_ship=1;sea.focus_fleet();feedback._reset(core.view)
	var count:int=feedback.impact.history.size()
	var fire:Dictionary=core.request({"op":"fire","ship":1,"weapon":"gun","target":"C01"})
	check(fire.get("ok",false),"real fire order "+name)
	for second in range(20):
		core.request({"op":"step","seconds":1});show_view(core.view)
		if feedback.impact.history.slice(count).any(func(row):return str(row.kind)=="fire" and str(row.ship)=="1"):break
	check(feedback.impact.history.size()>count,"real gun event reaches recoil "+name)
	var item:Dictionary=feedback.impact.history.back().duplicate(true) if feedback.impact.history.size()>count else {}
	check(is_equal_approx(float(item.get("caliber_mm",0)),expected_mm),"verified own caliber "+name)
	var saved:String=str(core.request({"op":"save","serialized":true}).serialized)
	var stable_view:String=JSON.stringify(core.view)
	var previous_pan:Vector2=sea.pan
	var peaks:=0.0
	var trace:Array=[]
	for frame in range(72):
		feedback._process(1.0/120.0)
		peaks=maxf(peaks,sea.combat_offset.length());trace.append([sea.combat_offset.x,sea.combat_offset.y])
		if frame==1:
			check(sea.combat_offset.length()>.05,"visible recoil "+name)
			var world:Vector2=sea.unproject(Vector2(940,680))
			check(sea.unproject(sea.project(world)).distance_to(world)<.00001,"projection remains invertible under recoil "+name)
			clicked=Vector2.INF
			var screen:Vector2=sea.get_viewport().get_screen_transform()*sea.get_global_transform_with_canvas()*sea.project(world)
			for pressed in [true,false]:
				var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=screen;Input.parse_input_event(event);await process_frame
			check(clicked.distance_to(world)<.001,"actual pointer selects displayed world point during shake "+name)
			await shot(name+"-recoil")
	check(sea.combat_offset==Vector2.ZERO and feedback.impact.pulses.is_empty(),"recoil returns exactly to rest "+name)
	check(sea.pan==previous_pan,"recoil never drifts persistent camera "+name)
	check(str(core.request({"op":"save","serialized":true}).serialized)==saved,"recoil and pointer observation leave core save/time unchanged "+name)
	check(JSON.stringify(core.view)==stable_view,"rendering leaves published observation byte-stable "+name)
	var after:int=feedback.impact.history.size();feedback.observe(core.view);feedback.observe(core.view)
	check(feedback.impact.history.size()==after,"same observation never repeats salvo "+name)
	results.append({"identity":identity,"native_tick":core.view.tick,"actual_event":core.view.get("events",[]).filter(func(row):return str(row.get("kind",""))=="gun"),"impulse":item,"peak_pixels":peaks,"offset_trace":trace})
func tide_case()->void:
	check(core.request({"op":"new_tide","seed":45,"character_id":"IBS-U-USN-FLETCHER","difficulty":"normal","intel_profile":"open-intel-v1"}).get("ok",false),"real Tide starts")
	sea.view=core.view;sea.selected_ship=1;sea.focus_fleet();feedback._reset(core.view)
	var before:int=feedback.impact.history.size()
	var hurt:=false
	for tick in range(35):
		core.request({"op":"step","seconds":1});show_view(core.view)
		if feedback.impact.history.slice(before).any(func(row):return str(row.kind)=="damage"):
			hurt=true;break
		feedback._process(.05)
	check(hurt,"real Tide HP loss triggers received-hit shake")
	check(feedback.impact.history.slice(before).any(func(row):return str(row.kind)=="fire"),"new real friendly Tide projectile triggers recoil")
	feedback._process(.008);check(sea.combat_offset.length()>.05,"Tide hit moves sea presentation")
	await shot("tide-received-hit")
	results.append({"mode":"actual_tide","tick":core.view.tick,"ships":core.view.ships,"impulses":feedback.impact.history.slice(before).duplicate(true)})
	var count:int=feedback.impact.history.size()
	feedback.observe(core.view,true)
	check(sea.combat_offset==Vector2.ZERO and feedback.impact.pulses.is_empty(),"read-only replay cancels transient feedback")
	feedback.observe(core.view)
	check(feedback.impact.history.size()==count,"resume seeds current projectile IDs without replaying them")
func edge_contracts()->void:
	var ship:Dictionary={"id":99,"name":"契约测试舰","x":6000,"y":5000,"hp":100,"maxHp":100,"characterId":"IBS-U-USN-WASHINGTON"}
	var initial:Dictionary={"tick":10,"ships":[ship],"events":[]}
	feedback._reset(initial)
	feedback.observe({"tick":11,"ships":[],"events":[{"tick":11,"id":777,"kind":"damage","text":"契约测试舰 中弹受损 100 DP","x":6000,"y":5000}]})
	check(feedback.impact.pulses.any(func(row):return str(row.kind)=="damage"),"fixture: lethal damage still shakes after own hull leaves live roster")
	feedback.observe(initial,true)
	check(sea.combat_offset==Vector2.ZERO and feedback.impact.pulses.is_empty(),"backward/replay observation returns camera to rest")
	var buffed:Dictionary=ship.duplicate(true);buffed.maxHp=150
	feedback.observe({"tick":11,"ships":[buffed],"events":[]})
	check(feedback.impact.pulses.is_empty(),"fixture: increasing max HP without losing hull HP is not a received hit")
	for i in range(80):feedback.impact.hurt({"id":i,"x":0,"y":0},1.0)
	check(feedback.impact.pulses.size()<=8,"fixture: simultaneous fleet hits have bounded effect pool")
	for frame in range(90):
		feedback._process(1.0/120.0)
		check(sea.combat_offset.length()<=11*.75+.001,"fixture: dense attacks stay inside screen-pixel motion budget")
	check(sea.combat_offset==Vector2.ZERO,"fixture: dense effects fully decay")
	feedback.configure_motion(0);feedback.impact.hurt(ship,.5);feedback._process(.008)
	check(sea.combat_offset==Vector2.ZERO and not feedback.impact.pulses.is_empty(),"zero slider disables camera motion while preserving local hit art")
	feedback.configure_motion(.75)
func monster_terminal_case()->void:
	check(core.request({"op":"new_chapter","id":"c1-breakout","seed":6109,"gameplay_profile":"cas-adventure-v1","intel_profile":"open-intel-v1"}).get("ok",false),"real creature protection scenario starts")
	sea.view=core.view;feedback._reset(core.view)
	var protected_hit:Dictionary={}
	for step in range(160):
		var previous:Dictionary=core.view.duplicate(true)
		core.request({"op":"step","seconds":1});show_view(core.view)
		var vanished:Array=[]
		for ship in previous.get("ships",[]):
			if not core.view.get("ships",[]).any(func(row):return str(row.id)==str(ship.id)):vanished.append(ship)
		for ship in vanished:
			if core.view.get("events",[]).any(func(event):return int(event.get("tick",-1))==int(core.view.tick) and str(event.get("kind",""))=="creature_hit"):
				protected_hit={"tick":core.view.tick,"previous_hp":ship.hp,"ship":ship.id,"events":core.view.get("events",[]).filter(func(event):return int(event.get("tick",-1))==int(core.view.tick))}
				check(feedback.impact.pulses.any(func(pulse):return str(pulse.kind)=="damage" and str(pulse.ship)==str(ship.id)),"real creature protection/removal still receives final hit recoil")
		if not protected_hit.is_empty():break
		feedback._process(.6)
	check(not protected_hit.is_empty(),"actual creature hit removes an own protected hull")
	results.append({"mode":"actual_creature_protection","receipt":protected_hit})
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1600,900)
	sea=load("res://scripts/sea_map.gd").new();root.add_child(sea);sea.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	feedback=load("res://scenes/ui/battle_feedback.tscn").instantiate();root.add_child(feedback);feedback.bind(sea);feedback.set_process(false)
	sea.cards=feedback.impact.catalog
	sea.point_selected.connect(func(point):clicked=point)
	await process_frame
	await fire_case("IBS-U-USN-FLETCHER",127,"light-127mm")
	await fire_case("IBS-U-USN-HONOLULU",152.4,"medium-152mm")
	await fire_case("IBS-U-USN-SAN-FRANCISCO",203,"medium-203mm")
	await fire_case("IBS-U-USN-WASHINGTON",406,"capital-406mm")
	if results.size()==4:
		check(float(results[2].peak_pixels)>float(results[1].peak_pixels),"actual 203mm recoil is stronger than 152mm within its tier")
		check(float(results[3].peak_pixels)>float(results[0].peak_pixels)*2,"actual capital salvo is visibly heavier than destroyer salvo")
		check(float(results[3].impulse.get("duration",0))>float(results[0].impulse.get("duration",0))*2,"capital salvo has longer settling weight")
	await tide_case();await monster_terminal_case();edge_contracts()
	var report:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"real_native_results":results,"fixture_scope":"terminal own-hull removal, bounded simultaneous hits, rewind and zero-strength; fixtures do not create authority results or rewards"}
	FileAccess.open(output+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("COMBAT_FEEL ",JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty(),"actual_caliber_peak_pixels":results.slice(0,4).map(func(row):return [row.impulse.get("caliber_mm",0),row.peak_pixels])}))
	core.close();sea.queue_free();feedback.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
