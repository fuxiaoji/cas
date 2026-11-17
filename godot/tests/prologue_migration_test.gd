extends SceneTree
const TransitionSettle=preload("res://tests/transition_settle.gd")
const Main=preload("res://scenes/main.tscn")
const Economy=preload("res://scripts/economy.gd")
const Film=preload("res://scripts/prologue_film.gd")
var app
var checks:=0
var failures:Array[String]=[]
var screenshots:Array=[]
var inputs:=0
var directory:="res://../artifacts/godot/prologue-migration/"

func _initialize() -> void:call_deferred("_run")
func check(value:bool,text:String) -> bool:
	checks+=1
	if not value:failures.append(text);push_error(text)
	return value
func _button(text:String) -> Button:
	for node in app.find_children("*","Button",true,false):
		if node.text==text and node.is_visible_in_tree():return node
	return null
func pointer(position:Vector2,pressed:bool) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=position;Input.parse_input_event(motion)
	var event:=InputEventMouseButton.new();event.position=position;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;Input.parse_input_event(event);inputs+=2;await process_frame
func move(position:Vector2) -> void:
	var event:=InputEventMouseMotion.new();event.position=position;Input.parse_input_event(event);inputs+=1;await process_frame
func click(text:String) -> bool:
	await TransitionSettle.wait_for_route(self,app)
	await process_frame
	var control:=_button(text)
	# The command drawer is optional in the quiet HUD; navigate through its
	# visible entry before exercising the same original curriculum controls.
	if control==null and app.screen=="battle" and text in ["编队","完成本段实操"]:
		if app.battle_controller.collapsed:
			if not await click("战术"):return false
		if text=="完成本段实操" and app.battle_controller.tab!="fleet":
			if not await click("编队"):return false
		await process_frame
		control=_button(text)
	if not check(control!=null,"visible action "+text):return false
	var ancestor=control.get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer:ancestor.ensure_control_visible(control)
		ancestor=ancestor.get_parent()
	await process_frame;await process_frame
	var position:Vector2=control.get_viewport().get_screen_transform()*control.get_global_transform_with_canvas()*(control.size*.5)
	await pointer(position,true);await pointer(position,false);await process_frame;await process_frame
	return true
func map_point(world:Vector2) -> Vector2:return app.sea.get_viewport().get_screen_transform()*app.sea.get_global_transform_with_canvas()*app.sea.project(world)
func map_click(world:Vector2) -> void:
	var position:=map_point(world);await pointer(position,true);await pointer(position,false);await process_frame
func shot(name:String) -> void:
	await TransitionSettle.wait_for_route(self,app)
	await process_frame;await RenderingServer.frame_post_draw
	var path:=ProjectSettings.globalize_path(directory+name+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"screenshot "+name);screenshots.append(path)
func film():
	for child in app.page.get_children():
		if child.get_script()==Film:return child
	return null
func step(seconds:int) -> void:
	var response:Dictionary=app.issue({"op":"step","seconds":seconds})
	check(response.get("ok",false),"native simulated time advances")
func routes(mode:String,cancel_first:bool=false) -> bool:
	app.sea.zoom=.9;app.sea.pan=Vector2.ZERO
	var leader:Dictionary=app.core.view.ships[0]
	for ship in app.core.view.ships:
		if int(ship.id)==int(app.core.view.fleets[0].leader):leader=ship
	var origin:=Vector2(leader.x,leader.y)
	if cancel_first:
		if not await click("编队") or not await click("领舰移动"):return false
		await map_click(origin+Vector2(1000,0))
		var before:String=str(app.core.request({"op":"save","serialized":true}).serialized)
		if not await click("取消草稿"):return false
		check(str(app.core.request({"op":"save","serialized":true}).serialized)==before,"explicit draft cancel never changes authority")
	if not await click("编队") or not await click("同步移动" if mode=="sync" else "领舰移动"):return false
	await map_click(origin+Vector2(1100,0));await map_click(origin+Vector2(2400,600))
	if not check(app.battle_controller.preview.get("valid",false),"real "+mode+" multi-ship preview"):return false
	return await click("下达航线")
func fire(weapon:String) -> bool:
	var own:Dictionary={}
	var contact:Dictionary={}
	var last_reason:=""
	for attempt in range(20):
		for candidate in app.core.view.get("ships",[]):
			if int(candidate.get("fleet",0))!=1:continue
			for row in app.core.view.get("contacts",[]):
				var aim:Dictionary=app.core.request({"op":"aim","ship":int(candidate.id),"weapon":weapon,"target":str(row.id)})
				if aim.get("ok",false) and aim.data.get("valid",false):contact=row;own=candidate;break
				last_reason=str(aim.get("error",aim.get("data",{}).get("error","no legal arc")))
			if not contact.is_empty():break
		if not contact.is_empty():break
		await step(12)
	if contact.is_empty():print("NO_LEGAL ",weapon," tick=",app.core.view.get("tick")," reason=",last_reason)
	if not check(not contact.is_empty(),"actual legal "+weapon+" contact"):return false
	app.battle_controller.select("ship",own);app.sea.zoom=.9;app.sea.pan=Vector2.ZERO;await process_frame
	var badge:Vector2=app.sea.get_viewport().get_screen_transform()*app.sea.get_global_transform_with_canvas()*(app.sea.project(Vector2(own.x,own.y))+Vector2(-24 if weapon=="gun" else 24,-48))
	var target:=map_point(Vector2(contact.x,contact.y))
	await pointer(badge,true);await move(target)
	if weapon=="torpedo":
		await create_timer(.3).timeout
		check(app.sea.gesture.has("anchor"),"actual 250ms torpedo lock")
		await move(target+Vector2(0,12));await create_timer(.1).timeout
		check(absf(float(app.sea.gesture.get("heading",0))-float(app.sea.gesture.get("base_heading",0)))>.15,"actual torpedo heading adjustment")
	await pointer(target+(Vector2(0,12) if weapon=="torpedo" else Vector2.ZERO),false)
	await step(12)
	check(app.economy.state.active_run.evidence.get("gunFired" if weapon=="gun" else "torpedoFired",false),"only ordered ship actual "+weapon+" launch marks evidence")
	return true
func return_story() -> void:
	if _button("继续剧情")!=null:await click("继续剧情")
	else:app.show_page("story");await process_frame
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path:="user://tests/prologue-%d.json"%OS.get_process_id()
	app=Main.instantiate();app.economy=Economy.new(path);root.add_child(app);app.set_process(false)
	await create_timer(.2).timeout
	app.show_page("story");await process_frame
	var movie=film()
	check(movie!=null and movie.frames.size()==52,"opening captures exactly 0..204 at four-second intervals")
	if movie!=null:
		check(int(movie.frames.front().tick)==0 and int(movie.frames.back().tick)==204,"source handover time preserved")
		check(movie.frames.any(func(frame):return not frame.get("shells",[]).is_empty()),"opening film contains real native shells")
		await create_timer(9.45).timeout
		check(movie.cursor==51 and movie.observed_ticks.has(188) and movie.focused,"real film clock plays through 204 and automatically cuts camera at188")
		await click("重播");await click("暂停回放")
		check(not movie.playing,"film replay and pause are real controls")
		await shot("01-opening-handover")
	await click("进入舰桥");await click("继续对话");await click("先告诉我舰队情况")
	check(app.progression.data().story.memory=="duty","memory branch persists source answer")
	await click("继续对话");await click("继续对话");await click("接入辅助")
	check(app.progression.data().story.flags.get("assistant-bound",false),"Baixi binding follows original trigger")
	for i in range(5):await click("继续对话")
	await click("帕金斯");await click("任命领舰")
	check(app.progression.data().story.leaderId=="IBS-U-USN-PERKINS","leader selected then separately appointed")
	await click("继续对话");await click("继续对话");await click("进入指挥实操")
	check(DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN and app.fullscreen_battle and not app.fullscreen_story,"follow handover enters actual native fullscreen battle")
	check(int(app.core.view.tick)==204,"first course starts from actual handover, not a fresh opening")
	check(str(app.battle_controller._fleet().get("leader",0))!="1","chosen leader changes through real native lead command")
	if await routes("follow") and await fire("gun"):
		check(app.progression.course_status("follow").complete,"follow course genuinely complete")
		await shot("02-follow-complete");await click("完成本段实操");await return_story()
	else:await finish(false,path);return
	movie=film();check(movie!=null and not movie.opening and not movie.voice_live and not movie.frames.is_empty(),"step11 replays actual player frames without voice or reward")
	await shot("03-follow-film");await click("返回剧情")
	for i in range(5):await click("继续对话")
	var saved_tick:=int(JSON.parse_string(str(app.progression.data().story_battle)).tick)
	await click("进入指挥实操")
	check(DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN and app.fullscreen_battle and not app.fullscreen_story,"sync handover retains actual native fullscreen battle")
	check(int(app.core.view.tick)==saved_tick,"sync continues same damaged, armed and positioned world")
	if await routes("sync",true):
		await step(4)
		check(app.progression.course_status("sync").complete,"explicit cancelled draft and true sync preview/commit complete course")
		await click("完成本段实操");await return_story()
	else:await finish(false,path);return
	check(film()!=null and not film().frames.is_empty(),"step22 has true sync recording")
	await shot("04-sync-film");await click("返回剧情")
	for i in range(2):await click("继续对话")
	saved_tick=int(JSON.parse_string(str(app.progression.data().story_battle)).tick)
	await click("进入指挥实操")
	check(DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN and app.fullscreen_battle and not app.fullscreen_story,"torpedo handover retains actual native fullscreen battle")
	check(int(app.core.view.tick)==saved_tick,"torpedo continues same story battle")
	if await fire("torpedo"):
		check(app.progression.course_status("torpedo").complete,"hover, adjustment, accepted order and actual launch complete course")
		await shot("05-torpedo-complete");await click("完成本段实操");await return_story()
	else:await finish(false,path);return
	check(film()!=null and not film().frames.is_empty(),"step28 replays actual torpedo action")
	await shot("06-torpedo-film");await click("返回剧情")
	for i in range(3):await click("继续对话")
	check(int(app.progression.data().story.step)==30 and not app.progression.data().prologue_reward,"final image reached without premature reward")
	var coins:=int(app.economy.wallet().credits)
	await shot("07-dawn-return");await click("领取序章奖励")
	check(app.progression.data().prologue_reward and int(app.economy.wallet().credits)==coins+2000,"source prologue gift committed only on explicit claim")
	check(not app.progression.claim_prologue().ok,"prologue gift cannot duplicate")
	await finish(true,path)
func finish(success:bool,path:String) -> void:
	check(success,"three original story courses and four films completed")
	var report:={"checks":checks,"passed":checks-failures.size(),"failures":failures,"inputs":inputs,"input_method":"application Input.parse_input_event, never OS mouse","screenshots":screenshots,"story":app.progression.data().story,"courses":app.progression.data().courses}
	app.audio.shutdown();app.core.close();app.queue_free();await process_frame
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	var file:=FileAccess.open(directory+"receipt.json",FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
