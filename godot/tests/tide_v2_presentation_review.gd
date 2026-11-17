extends SceneTree
## Real account, hub controls, 10Hz authoritative battle and retained GPU rendering.
const Main=preload("res://scenes/main.tscn")
const Economy=preload("res://scripts/economy.gd")
const Settle=preload("res://tests/transition_settle.gd")
const SOURCE="res://../artifacts/extraction-stall-20261113/actual-account-refilled.json"
const OUTPUT="res://../artifacts/godot/tide-v2-presentation/"
var app
var path:String
var checks:=0
var failures:Array[String]=[]
var report:Dictionary={"normal_account_modified":false,"synthetic_combat_state":false,"gpu":true}
var choice_rows:Array=[]
var perf:Array=[]
var issue_times:Array=[]
var max_effects:=0
var max_bolts:=0
var max_members:=0
var resumed:=false
var captured:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures.append(label);push_error(label)
	return ok
func stats(values:Array)->Dictionary:
	var sorted:=values.duplicate();sorted.sort()
	return {"p50":sorted[sorted.size()/2],"p95":sorted[int((sorted.size()-1)*.95)],"max":sorted.back()}
func canonical(value:Variant)->Variant:
	if value is Dictionary:
		var keys:Array=value.keys();keys.sort();var result:Array=[]
		for key in keys:result.append([str(key),canonical(value[key])])
		return result
	if value is Array:
		var result:Array=[]
		for item in value:result.append(canonical(item))
		return result
	if value is int or value is float:return float(value)
	return value
func frames(count:int)->void:
	for i in count:await process_frame
func shot(label:String)->void:
	await frames(2);await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT+label+".png"))
func click(node:Control)->void:
	await Settle.wait_for_route(self,app)
	var point:Vector2=node.get_viewport().get_screen_transform()*node.get_global_transform_with_canvas()*(node.size*.5)
	var down:=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;down.position=point;Input.parse_input_event(down);await process_frame
	var up:=InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_LEFT;up.position=point;Input.parse_input_event(up);await frames(2)
func find_text(node:Node,text:String)->Button:
	for child in node.get_children():
		if child is Button and child.text==text:return child
		var found:Button=find_text(child,text)
		if found!=null:return found
	return null
func measure(label:String)->void:
	var was_running:bool=app.running;app.running=false;await frames(25)
	var intervals:Array=[];var draws:Array=[];var objects:Array=[];var process_usec:Array=[];var previous:int=Time.get_ticks_usec()
	for i in 180:
		await process_frame
		var now:int=Time.get_ticks_usec();intervals.append(float(now-previous)/1000.0);previous=now
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME));objects.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME));process_usec.append(app.sea.metrics().update_usec)
	perf.append({"label":label,"tick":app.core.view.tick,"window":DisplayServer.window_get_size(),"members":app.core.view.ships.size(),"foes":app.core.view.contacts.size(),"bolts":app.core.view.shells.size()+app.core.view.torpedoes.size(),"drops":app.core.view.tide.drops.size(),"frame_ms":stats(intervals),"sea_process_usec":stats(process_usec),"draw_calls":stats(draws),"objects":stats(objects)})
	await shot(label);app.running=was_running
func measure_live()->void:
	## Eight actual wall seconds include real 10Hz stepping and periodic disk checkpoints.
	root.size=Vector2i(1280,720);await frames(3);app.running=true;app.set_process(true)
	var intervals:Array=[];var cadence:Array=[];var started:int=Time.get_ticks_usec();var previous:int=started;var last_tick:float=float(app.core.view.tick);var tick_before:float=last_tick;var last_route:=-1.0
	while Time.get_ticks_usec()-started<8000000 and app.screen=="battle":
		if not app.core.view.tide.choices.is_empty():
			await choose();previous=Time.get_ticks_usec();continue
		if float(app.core.view.tick)-last_route>=1:move_policy();last_route=float(app.core.view.tick)
		await process_frame
		var now:int=Time.get_ticks_usec();intervals.append(float(now-previous)/1000.0);previous=now
		var tick:float=float(app.core.view.tick)
		if tick>last_tick:cadence.append(tick-last_tick);last_tick=tick
	app.set_process(false)
	var row:Dictionary={"label":"live-10Hz-1280","wall_seconds":float(Time.get_ticks_usec()-started)/1000000.0,"simulation_seconds":float(app.core.view.tick)-tick_before,"frame_ms":stats(intervals),"cadence_seconds":stats(cadence),"frames":intervals.size(),"window":DisplayServer.window_get_size()}
	perf.append(row)
	check(float(row.frame_ms.p95)<16.667,"actual 10Hz mainloop frame p95 stays within60fps budget")
	check(float(row.cadence_seconds.p50)>.099 and float(row.cadence_seconds.p95)<.101,"production mainloop advances deterministic10Hz microsteps")
	check(row.simulation_seconds>7 and row.simulation_seconds<9,"production loop real seconds stay near wall time")
	print("TIDE_PERFORMANCE_CAPTURE_FINISHED ",JSON.stringify(row))
func measure_command_path()->void:
	## Split the same legal move path; this does not change time or the world directly.
	var transport:Array=[];var presentation:Array=[]
	for i in 12:
		var began:int=Time.get_ticks_usec()
		var response:Dictionary=app.core.request({"op":"route","fleet":1,"mode":"follow","speed":60,"points":[{"x":12000+i*10,"y":7000}]})
		transport.append(float(Time.get_ticks_usec()-began)/1000.0);began=Time.get_ticks_usec();app.update_battle();presentation.append(float(Time.get_ticks_usec()-began)/1000.0)
		check(response.get("ok",false),"profiled legal movement command "+str(i))
	report["movement_path"]={"bridge_roundtrip_ms":stats(transport),"battle_update_ms":stats(presentation),"tick":app.core.view.tick,"members":app.core.view.ships.size(),"bolts":app.core.view.shells.size()+app.core.view.torpedoes.size()}
func move_policy()->void:
	var view:Dictionary=app.core.view;var tick:float=float(view.tick)
	var target:Vector2=Vector2(12000,7000)+Vector2.from_angle(tick*.13)*1500
	var began:int=Time.get_ticks_usec();app.battle_controller.move(target);issue_times.append(float(Time.get_ticks_usec()-began)/1000.0)
func choose()->void:
	var tide:Dictionary=app.core.view.tide;var choices:Array=tide.choices.duplicate()
	var reinforcement:bool=str(tide.get("offer_kind",""))=="reinforcement"
	var priorities:Array=["chain","orbit","multishot","haste","magnet","blast","damage","shield","repair","torpedo","maneuver"]
	if float(tide.team_hp)<float(tide.team_max_hp)*.5:priorities=["repair","shield"]+priorities
	if reinforcement:
		choices=choices.filter(func(choice):return str(choice.get("kind",""))=="reinforcement")
		var desired:String=["heavy","barrage","torpedo","barrage","torpedo"][mini(4,app.core.view.ships.size()-1)]
		var roles:Array=[desired]+["heavy","barrage","torpedo"]
		choices.sort_custom(func(a,b):return roles.find(str(a.get("role","barrage")))<roles.find(str(b.get("role","barrage"))))
	else:choices.sort_custom(func(a,b):return priorities.find(str(a.id))<priorities.find(str(b.id)))
	var selected:Dictionary=choices[0];var container:Node=app.page.get_node("TideBattleHud/Upgrades/ReserveScroll/CrewGrid" if reinforcement else "TideBattleHud/Upgrades/Choices")
	var button:Button=null
	for child in container.get_children():
		if str(child.get_meta("tide_choice_id",""))==str(selected.id):button=child;break
	if not check(button!=null,"actual offered choice button "+str(selected.id)):return
	if reinforcement:
		var scroll:ScrollContainer=app.page.get_node("TideBattleHud/Upgrades/ReserveScroll");scroll.ensure_control_visible(button);await frames(2)
		check(button.get_global_rect().intersection(scroll.get_global_rect()).size.x>=button.size.x-1,"reinforcement card fits scroll viewport")
		if not captured.has("reserve"):
			await shot("reinforcement-offer");captured.reserve=true
	var prior:int=int(tide.offer_id);var before_members:int=app.core.view.ships.size()
	await click(button)
	check(int(app.core.view.tide.offer_id)!=prior or app.core.view.tide.choices.is_empty(),"pointer commits offered "+str(selected.id))
	choice_rows.append({"tick":app.core.view.tick,"id":selected.id,"kind":tide.offer_kind,"character_id":selected.get("character_id",""),"role":selected.get("role","")})
	if reinforcement:
		check(app.core.view.ships.size()==before_members+1,"real reinforcement increases authoritative team")
		var ship:Dictionary=app.core.view.ships.back();check(str(ship.characterId)==str(selected.character_id),"recruit keeps exact selected identity")
		var avatar:TextureRect=app.page.get_node("TideBattleHud/Team/Member_"+str(int(ship.id)));check(str(avatar.get_meta("character_id"))==str(selected.character_id) and avatar.texture!=null,"team avatar is recruit本人")
		check(app.page.get_node("TideBattleHud/JoinToast").visible,"new recruit gets one arrival toast")
func resume_review()->void:
	var before:Dictionary=app.core.view.duplicate(true);var before_save:String=str(app.core.request({"op":"save","serialized":true}).serialized);var id:String=str(app.run.run_id)
	app.save_leave();await frames(2)
	check(app.screen=="tide_event","pause leave returns to event hub")
	app.core.close();app.core=load("res://scripts/core_bridge.gd").new()
	app.resume_run();await Settle.wait_for_route(self,app)
	check(str(app.run.run_id)==id and JSON.stringify(app.core.view)==JSON.stringify(before),"resume restores exact team/bolts/XP/frame")
	check(str(app.core.request({"op":"save","serialized":true}).serialized)==before_save,"resume serialization is exact")
	check(app.sea.drain_joins().is_empty() and app.sea.effects.is_empty() and not app.page.get_node("TideBattleHud/JoinToast").visible,"resume never replays arrival/explosion feedback")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);app.fullscreen_battle=false;root.size=Vector2i(1280,720);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);await frames(3)
	app.running=true;resumed=true
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT));root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var source_sha:String=FileAccess.get_sha256(SOURCE)
	path="user://tests/tide-v2-gpu-%d.json"%OS.get_process_id();DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir());check(DirAccess.copy_absolute(ProjectSettings.globalize_path(SOURCE),ProjectSettings.globalize_path(path))==OK,"read-only43-owned account clone")
	app=Main.instantiate();app.boot_to_title=false;app.economy=Economy.new(path);root.add_child(app);app.set_process(false);await Settle.wait_for_route(self,app);app.page_motion=false;app.fullscreen_battle=false
	check(app.economy.abandon_sortie().get("ok",false),"normal clone abandonment before activity")
	app.show_page("tide_event");await Settle.wait_for_route(self,app)
	var hub:Control=app.page.find_child("TideEventHub",true,false)
	if hub==null:
		for child in app.page.get_children():
			if child.has_method("reserve_ids"):hub=child;break
	if not check(hub!=null,"native editable event hub"):await finish();return
	var leader:OptionButton=hub.get_node("BriefScroll/Body/Deployment/EventShip")
	var difficulty:OptionButton=hub.get_node("BriefScroll/Body/Deployment/EventDifficulty")
	leader.select(1);leader.item_selected.emit(1);difficulty.select(1)
	var selected_leader:String=str(leader.get_item_metadata(1))
	await click(hub.get_node("BriefScroll/Body/ReserveFormation"));check(app.modal!=null,"hub roster opens by pointer")
	var crew:GridContainer=app.modal.get_node("ReserveScroll/Crew");var excluded:String=str(crew.get_child(0).name).trim_prefix("Reserve_");await click(crew.get_child(0));await shot("hub-reserves-1280")
	check(not crew.get_child(0).button_pressed,"normal toggle deselects one reserve")
	root.size=Vector2i(1920,1080);await frames(4);await shot("hub-reserves-1920");root.size=Vector2i(1280,720);await frames(4)
	await click(find_text(app.modal,"确认阵容"));check(not app.get_meta("tide_reserves").has(excluded),"confirmed roster retains deselection")
	check(leader.selected==1 and str(leader.get_item_metadata(leader.selected))==selected_leader and difficulty.selected==1,"reserve confirmation preserves nonfirst leader and hard difficulty")
	for index in leader.item_count:
		if str(leader.get_item_metadata(index))=="IBS-U-USN-FLETCHER":leader.select(index);leader.item_selected.emit(index);break
	difficulty.select(0);var expected_reserves:Array=hub.reserve_ids("IBS-U-USN-FLETCHER")
	app.set_meta("next_tide_seed",42);var launch:Button=find_text(hub,"驶入回响海域");await click(launch)
	if not check(app.screen=="battle" and str(app.core.view.get("tide",{}).get("version",""))=="cas-event-tide-v2","normal hub starts explicit native v2"):await finish();return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);root.size=Vector2i(1280,720);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	check(app.run.request.roster==expected_reserves and not app.run.request.roster.has(excluded),"native roster exactly confirmed owned reserves")
	await measure("battle-000-1280");app.running=true
	var hud:Control=app.page.get_node("TideBattleHud")
	var key:=InputEventKey.new();key.physical_keycode=KEY_D;key.pressed=true;Input.parse_input_event(key);await frames(2);hud._process(.11)
	check(not app.core.view.fleets[0].points.is_empty(),"held physical key issues real v2 movement")
	var sea=app.sea;sea.set_process(false);app._process(.1)
	var actor
	for value in sea.actors.values():
		if value.kind=="ship" and int(value.row.id)==1:actor=value;break
	sea._sample_age=0;sea._process(.05)
	check(actor.world_now.distance_to(actor.world_from)>1 and actor.world_now.distance_to(actor.world_to)>1,"visual movement interpolates between two real10Hz positions")
	var age_before:float=sea._sample_age;move_policy();check(is_equal_approx(sea._sample_age,age_before) and is_equal_approx(sea._sample_span,.1),"same-tick movement intent does not shorten visual interpolation")
	sea._process(.05);sea.set_process(true)
	key=InputEventKey.new();key.physical_keycode=KEY_D;key.pressed=false;Input.parse_input_event(key);await frames(2)
	check(float(app.core.view.fleets[0].speed)==0,"key release sends real zero-speed intent")
	var original_motion:float=app.battle_motion_strength;sea.motion_strength=0;sea._trauma=1;sea._process(.016);check(sea.combat_offset==Vector2.ZERO,"zero motion setting suppresses shake");sea.motion_strength=original_motion
	var iterations:=0;var last_route:=-1.0
	while app.core.view.get("result")==null and iterations<2000:
		iterations+=1;var view:Dictionary=app.core.view;var tick:float=float(view.tick)
		if not view.tide.choices.is_empty():await choose();continue
		if tick-last_route>=.99:move_policy();last_route=tick
		app._process(.1);await process_frame
		max_members=maxi(max_members,app.core.view.ships.size());max_bolts=maxi(max_bolts,app.core.view.shells.size()+app.core.view.torpedoes.size());max_effects=maxi(max_effects,app.sea.effects.size() if is_instance_valid(app.sea) else 0)
		if app.screen!="battle":break
		for sample in [30,90,150]:
			if tick>=sample and not captured.has(str(sample)):
				await measure("battle-%03d-1280"%sample);captured[str(sample)]=true
				if sample==150:
					root.size=Vector2i(1920,1080);await measure("battle-150-1920");root.size=Vector2i(1280,720)
					measure_command_path()
					await measure_live()
		if tick>=90 and not resumed:await resume_review()
	if app.screen=="battle" and app.core.view.get("result")!=null:app.finish_battle();await frames(3)
	check(app.screen=="result" and bool(app.last_receipt.get("success",false)),"real 180s victory settles through main")
	check(max_members==6 and app.last_receipt.get("members",[]).size()==6,"six real shipgirls joined and receipt preserves identities")
	check(int(app.last_receipt.get("kills",0))>=500,"true authoritative horde clearing exceeds500")
	check(max_effects<=24,"visual explosions remain bounded24")
	check(app.economy.state.active_run.is_empty(),"terminal reward closes real account run")
	await shot("battle-victory")
	var receipt:Dictionary=app.last_receipt.duplicate(true);var wallet:Dictionary=app.economy.wallet().duplicate(true);var disk=Economy.new(path)
	check(disk.load_state().get("ok",false),"normal account service reloads terminal save")
	report["wallet_before_reload"]=wallet;report["wallet_after_reload"]=disk.wallet()
	check(JSON.stringify(canonical(disk.wallet()))==JSON.stringify(canonical(wallet)),"settled wallet survives disk reload")
	app.start_replay(receipt);await Settle.wait_for_route(self,app);app.battle_controller.seek_tide(150.1);await frames(3)
	check(absf(float(app.core.view.tick)-150.1)<.001,"archive replay accepts fractional-second v2 time")
	check(app.sea.effects.is_empty() and app.sea.drain_joins().is_empty() and not app.page.get_node("TideBattleHud/JoinToast").visible,"replay never replays recruit/hit feedback")
	check(app.economy.wallet()==wallet,"replay cannot award currency")
	app.battle_controller.advance_tide_replay(.1);check(absf(float(app.core.view.tick)-150.2)<.001,"v2 replay advances one microstep")
	app.battle_controller.end_replay();await frames(3)
	check(FileAccess.get_sha256(SOURCE)==source_sha,"read-only account source remained byte-identical")
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://bin/core-current.json"));var override:String=OS.get_environment("CAS_SIM_PATH")
	var effective:String=override if not override.is_empty() else ProjectSettings.globalize_path("res://bin/"+str(manifest.executable))
	report.merge({"receipt":receipt,"route_issue_ms":stats(issue_times),"performance":perf,"choices":choice_rows,"max_members":max_members,"max_bolts":max_bolts,"max_effects":max_effects,"source_sha":source_sha,"candidate":effective,"candidate_sha":FileAccess.get_sha256(effective),"override":override,"manifest":manifest,"renderer":RenderingServer.get_video_adapter_name()})
	await finish()
func finish()->void:
	report.merge({"checks":checks,"failures":failures,"passed":failures.is_empty()})
	FileAccess.open(OUTPUT+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	if app!=null:app.audio.shutdown();app.core.close();app.queue_free();await frames(2)
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	print("TIDE_V2_GPU ",JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty(),"performance":perf,"max_members":max_members}));quit(0 if failures.is_empty() else 1)
