extends SceneTree
## Menu clicks and combat cues use real account transactions/native observations.
## Presentation edge cases below are explicitly isolated contract fixtures, not simulated victories.
const Main=preload("res://scenes/main.tscn")
const Economy=preload("res://scripts/economy.gd")
const Feedback=preload("res://scenes/ui/battle_feedback.tscn")
const Settle=preload("res://tests/transition_settle.gd")
var app
var checks:=0
var failures:Array[String]=[]
var shots:Array[String]=[]
var inputs:=0
var directory:=""
var profile:=""
func _initialize()->void:call_deferred("run_review")
func check(value:bool,title:String)->bool:
	checks+=1
	if not value:failures.append(title);push_error(title)
	return value
func button_named(node:Node,title:String)->Button:
	if node is Button and node.is_visible_in_tree() and str(node.text).replace(" ","")==title.replace(" ",""):return node
	for child in node.get_children():
		var button:=button_named(child,title)
		if button!=null:return button
	return null
func click_button(button:Button,title:String)->void:
	await Settle.wait_for_route(self,app)
	if not check(is_instance_valid(button) and not button.disabled,"visible actionable "+title):return
	var p:=button.get_viewport().get_screen_transform()*button.get_global_transform_with_canvas()*(button.size*.5)
	var motion:=InputEventMouseMotion.new();motion.position=p;Input.parse_input_event(motion)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=p;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		Input.parse_input_event(event);inputs+=1;await process_frame
	await process_frame
func click(title:String)->void:
	await Settle.wait_for_route(self,app)
	await click_button(button_named(app,title),title)
func capture(name:String)->void:
	await Settle.wait_for_route(self,app)
	if DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw
	var path:=directory.path_join(name+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"saved "+name);shots.append(path)
func contract_edges()->void:
	var feedback=Feedback.instantiate();root.add_child(feedback);await process_frame
	var initial:={"tick":10,"ships":[],"events":[{"id":1,"tick":10,"kind":"hit","x":50,"y":60}]}
	feedback.observe(initial)
	check(feedback.notice_history.is_empty(),"resuming never replays old effects")
	var next:={"tick":11,"ships":[],"events":[{"id":2,"tick":11,"kind":"hit","x":50,"y":60}]}
	var preserved:=JSON.stringify(next)
	feedback.observe(next);feedback.observe(next)
	check(feedback.notice_history.size()==1 and feedback._marks.size()==1,"seat event cursor prevents duplicate hits")
	check(JSON.stringify(next)==preserved,"feedback leaves observed data untouched")
	feedback.observe({"tick":12,"ships":[],"events":[{"id":3,"tick":20,"kind":"torpedo_detected","x":4,"y":5}]})
	check(feedback.notice_history.size()==1,"future event never reveals a threat")
	feedback.observe({"tick":13,"ships":[],"events":[{"id":4,"tick":13,"kind":"hit"},{"id":5,"tick":13,"kind":"torpedo_detected"}]})
	check(feedback.notice_history.back().kind=="torpedo","danger wins over hit confirmation")
	feedback.observe(next,true)
	check(not feedback.notice.visible and feedback._marks.is_empty(),"replay has no live danger alerts")
	feedback.observe({"tick":12,"ships":[],"events":[{"id":20,"tick":12,"kind":"cargo_revealed"}]})
	check(feedback.notice_history.back().kind=="search","partial search reveals a genuine item cue")
	feedback.observe({"tick":13,"ships":[],"events":[{"id":21,"tick":13,"kind":"cargo_revealed"},{"id":22,"tick":13,"kind":"cargo_search_complete"}]})
	check(feedback.notice_history.back().kind=="search_complete" and feedback.caption.text.begins_with("搜索完成"),"completion replaces final reveal even immediately after partial notice")
	feedback.observe({"tick":14,"ships":[],"events":[{"id":23,"tick":14,"kind":"cargo_search_complete"},{"id":24,"tick":14,"kind":"cargo_revealed"}]},true)
	feedback.observe({"tick":15,"ships":[],"events":[{"id":25,"tick":15,"kind":"cargo_search_complete"},{"id":26,"tick":15,"kind":"cargo_revealed"}]})
	check(feedback.notice_history.back().kind=="search_complete","same-tick search cue selection is independent of event order")
	feedback.queue_free();await process_frame
func run_review()->void:
	directory=ProjectSettings.globalize_path("res://../artifacts/godot/expedition-feedback-v4")
	DirAccess.make_dir_recursive_absolute(directory)
	profile="user://tests/expedition-feedback-%d.json"%OS.get_process_id()
	await contract_edges()
	app=Main.instantiate();app.boot_to_title=false;app.economy=Economy.new(profile)
	root.add_child(app);app.set_process(false);await process_frame
	app.show_page("expedition");await Settle.wait_for_route(self,app)
	var menu=app.page.get_node("ExpeditionSelect")
	check(menu.content.difficulties.size()==3 and menu.choices.size()==13,"three risks, four environments, four weather options and five voyage scenes are editable data")
	check(menu.get_node("Cards/Calm/Margin/Body/Select").has_focus(),"initial menu focus supports keyboard selection")
	check(menu.get_node("Hint").text.begins_with("消耗 8 体力"),"selected voyage shows actual stamina cost")
	for card in menu.get_node("Cards").get_children():
		check(card.get_node("Margin/Body/Art").texture!=null,"illustration for "+str(card.name))
		check(card.get_global_rect().end.y<menu.get_node("TerrainRow").get_global_rect().position.y,"risk card leaves terrain unobstructed "+str(card.name))
	await capture("01-difficulty-nearshore")
	await click_button(menu.get_node("Cards/Hazard/Margin/Body/Select"),"深渊禁区")
	await click("淹没都市");await click("海雾")
	check(menu.selection=={"difficulty":"hazard","environment":"drowned_city","weather":"fog","scene":"sunken_metropolis"},"actual menu buttons select voyage options and preserve the chosen scene")
	check(menu.get_node("Hint").text.begins_with("消耗 20 体力"),"risk choice refreshes its actual cost")
	await capture("02-difficulty-abyss-city-fog")
	await click("编成舰队")
	check(app.screen=="formation","difficulty action opens real formation")
	check(app.economy.state.salvage_options=={"difficulty":"hazard","environment":"drowned_city","weather":"fog"},"voyage options persist by account transaction")
	var reopened=Economy.new(profile)
	check(reopened.load_state().get("ok",false) and reopened.state.get("salvage_options",{})==app.economy.state.salvage_options,"voyage selection survives account reload")
	await click("‹ 返回")
	check(app.screen=="expedition","formation back returns to voyage choice")
	# Real native night exercise: AI has the same seat's contacts and legal orders.
	var response:Dictionary=app.core.request({"op":"new","variant":"night","seed":6106,"side":"allies","enemy":"torpedo","profile":"coord","realtime":true})
	check(response.get("ok",false),"real native night exercise starts")
	app.enter_battle();DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);app.fullscreen_battle=false
	await Settle.wait_for_route(self,app)
	var controller=app.battle_controller
	check(is_instance_valid(controller.feedback),"battle owns native editable feedback scene")
	for fleet in app.core.view.get("fleets",[]):app.core.request({"op":"ai","fleet":int(fleet.id),"mode":"auto","profile":"coord","move":true,"gun":true,"torpedo":true})
	var observed:Dictionary={};var torpedo_shot:=false
	for i in range(1600):
		app.core.request({"op":"step","seconds":1})
		for event in app.core.view.get("events",[]):
			var cue:Dictionary=controller.feedback._cue(event)
			if not cue.is_empty() and not observed.has(str(cue.kind)):observed[str(cue.kind)]=event.duplicate(true)
		controller.update()
		if controller.feedback.notice.visible and controller.feedback.notice_history.back().kind=="torpedo" and not torpedo_shot:
			await capture("03-real-torpedo-warning");torpedo_shot=true
		if i%30==0:await process_frame
		if observed.has("torpedo") and observed.has("hit") and observed.has("damage"):break
		if app.core.view.get("result")!=null:break
	check(observed.has("torpedo"),"real seat-visible torpedo danger is recognized")
	check(observed.has("hit"),"real native hit is recognized")
	check(observed.has("damage") or observed.has("critical"),"real own damage is recognized")
	check(controller.feedback.notice_history.any(func(row):return str(row.kind)=="torpedo"),"real torpedo event reaches rendered live notice")
	check(controller.feedback.caption.size.x>200 and not controller.feedback.caption.text.is_empty(),"live warning has readable text width beside its icon")
	var before:String=str(app.core.request({"op":"save","serialized":true}).serialized)
	for i in range(4):controller.update();await process_frame
	check(str(app.core.request({"op":"save","serialized":true}).serialized)==before,"feedback refresh does not alter authority or simulation time")
	check(controller.feedback._marks.size()<=controller.feedback.maximum_marks,"combat marks remain capped")
	await capture("04-real-battle-clean")
	var native_receipt:={"tick":app.core.view.get("tick",0),"recognized_events":observed,"displayed_notices":controller.feedback.notice_history.duplicate(true)}
	app.core.close();app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(profile+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(profile+suffix))
	var report:={"checks":checks,"passed":checks-failures.size(),"failures":failures,"input_events":inputs,"screenshots":shots,"native_combat":native_receipt,"scope":"real menu/account transaction and native night-exercise combat; separate presentation fixtures are explicitly labeled; no fabricated loot, health, victory or settlement"}
	var file:=FileAccess.open(directory.path_join("receipt.json"),FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
