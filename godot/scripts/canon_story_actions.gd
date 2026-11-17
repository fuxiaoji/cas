extends RefCounted
const Service=preload("res://scripts/canon_story_service.gd")
const Data=preload("res://scripts/canon_story_data.gd")
const FIFTH:Array[String]=["IBS-U-USN-FLETCHER","IBS-U-USN-PERKINS","IBS-U-USN-MAURY","IBS-U-USN-DRAYTON","IBS-U-USN-LAMSON"]
static func launch(app)->Dictionary:
	var service=Service.new(app.economy);var node:Dictionary=service.node();var action:String=Data.action(node)
	if not app.economy.state.get("active_run",{}).is_empty():
		# Recover the narrow crash window after the native departure was saved but
		# before its animated page transition finished and the story bound the ID.
		if not service.state().pending.is_empty() and str(service.state().pending.get("run_id","")).is_empty():service.bind_run()
		if str(service.state().pending.get("run_id",""))==str(app.economy.state.active_run.get("run_id","")):
			await app.resume_run();app.battle_return_route="canon_story";return {"ok":true}
		return {"ok":false,"message":"先继续或结束已有行动，故事进度仍会保留"}
	if action=="harbor_tour":
		for route in Service.TOUR:
			if not service.state().tour_seen.has(route):
				if route=="ship_detail":app.set_meta("detail_ship_id",str(app.economy.formation[0]))
				app.show_page(route);return {"ok":true}
		return service.check_action(app.home)
	if action=="growth":
		app.set_meta("detail_ship_id",str(app.economy.formation[0]));app.show_page("ship_detail");return {"ok":true}
	if action in ["home_build","home_garrison"]:app.show_page("home");return {"ok":true}
	if action=="fixed_recruit":
		var redeemed:Dictionary=service.redeem_protocol(app.home)
		if redeemed.get("ok",false):
			var identity:Dictionary=app.home.unit("MCP-011").duplicate(true)
			identity["duplicate"]=false;identity["status_text"]="返还的同一份协议 · 灯鲨已同步";identity["ownership_text"]="唯一故事协议 · 无重复兑换"
			var reveal=load("res://scenes/ui/protocol_reveal.tscn").instantiate()
			app.page.add_child(reveal);reveal.bind(app,[identity])
			await reveal.finished
		return redeemed
	var armed:Dictionary=service.arm()
	if not armed.get("ok",false):return armed
	var seed:int=Data.seed(node)
	if action in ["native_battle","salvage_tutorial"]:
		var stage:String=str(node.get("native_stage","c1-salvage" if action=="salvage_tutorial" else "c1-breakout"))
		await app.start_local_mode({"op":"new_chapter","id":stage,"seed":seed,"chapter_profile":"canon-missions-v3","gameplay_profile":"cas-adventure-v1","intel_profile":"open-intel-v1"},{"mode":"exercise","id":str(node.id),"title":str(node.get("title","故事行动")),"side":"allies","canon_version":Service.VERSION,"canon_node":str(node.id),"chapter_profile":"canon-missions-v3","return_route":"canon_story","template_native_stage":stage})
	elif action in ["arena_ranked","arena_3v3"]:
		# Teaching loan: the fifth squad is used regardless of account wealth. This
		# is an actual native bot match, separate from permanent ranking rewards.
		var mode:String="ranked" if action=="arena_ranked" else "team3"
		await app.start_local_mode({"op":"new_arena","arena_version":app.ArenaService.VERSION,"mode":mode,"seed":seed,"groups":[{"id":"canon-fifth","name":"第五驱逐舰小队","ships":FIFTH.duplicate()}]},{"mode":"exercise","id":str(node.id),"title":"战网教学 · 人机排位" if mode=="ranked" else "战网教学 · 3v3人机","side":"allies","canon_version":Service.VERSION,"return_route":"canon_story"})
	elif action in ["littoral_sea","littoral_landing","littoral_combined"]:
		if node.has("tactical_lesson"):
			var training:Dictionary=load("res://scripts/canon_tactical_v3.gd").request(str(node.tactical_lesson),str(service.state().pending.get("mechanics_version","cas-island-war-v3")))
			if not training.get("ok",false):service.cancel_empty_pending();return training
			await app.start_local_mode(training.request,{"mode":"exercise","id":str(node.id),"title":str(node.get("title","联合武器训练")),"side":"allies","canon_version":Service.VERSION,"canon_node":str(node.id),"tactical_lesson":str(node.tactical_lesson),"return_route":"canon_story"})
		else:
			var lesson:String={"littoral_sea":"sea_control","littoral_landing":"landing","littoral_combined":"combined"}[action]
			var plan:Dictionary=app.home.prepare_littoral("tutorial",seed,[],[],"balanced","cas-littoral-v4",lesson)
			if not plan.get("ok",false):service.cancel_empty_pending();return plan
			await app.launch_littoral(plan.request)
	elif action=="island_defense":
		# Keep the native saved defense selection intact. The player configures it
		# in the island UI; there is no temporary fabricated ownership or auto-win.
		var plan:Dictionary=app.home.prepare_littoral("defense",seed,[],[],"balanced","cas-littoral-v4")
		if not plan.get("ok",false):
			service.cancel_empty_pending()
			if app.home.state().tactical_garrison.size()<2:
				app.show_page("home")
				if await app.wait_for_page("home"):app.notify({"message":"打开「驻防 → 战术驻防」，选中灯鲨与另一支部队并保存，再返回故事迎敌。"})
			return plan
		await app.launch_littoral(plan.request)
	else:
		service.cancel_empty_pending();return {"ok":false,"message":"这段行动尚在制作，日志与选择已保留"}
	if app.economy.state.get("active_run",{}).is_empty():
		service.cancel_empty_pending();return {"ok":false,"message":"行动未能开始，请检查整备或重试"}
	app.battle_return_route="canon_story"
	var bound:Dictionary=service.bind_run()
	if is_instance_valid(app.page):render_guide(app,app.screen)
	return bound

static func on_page(app,route:String)->void:
	var service=Service.new(app.economy)
	if not service.enabled():return
	if route=="battle" and not service.state().pending.is_empty() and not app.economy.state.get("active_run",{}).is_empty():
		if str(service.state().pending.get("run_id","")).is_empty():service.bind_run()
		if str(service.state().pending.get("run_id",""))==str(app.economy.state.active_run.get("run_id","")):app.battle_return_route="canon_story"
	service.visit(route)
	if route not in ["canon_story","canon_catalog","title"]:render_guide(app,route)

static func render_guide(app,route:String)->void:
	# Battle owns a compact, state-driven teaching overlay. Never stack a second
	# large narrative objective panel over the player's map and drag targets.
	if route=="battle":return
	if not is_instance_valid(app.page) or app.page.has_node("CanonActionGuide"):return
	var service=Service.new(app.economy);var node:Dictionary=service.node()
	if Data.action(node).is_empty():return
	var panel:=PanelContainer.new();panel.name="CanonActionGuide"
	app.place(panel,app.page,29,108,735,100)
	panel.add_theme_stylebox_override("panel",app.Design.panel_style())
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",14);panel.add_child(row)
	var instruction:=Label.new();instruction.text=Data.objective(node)
	if Data.action(node)=="harbor_tour":instruction.text=str({"roster":"她们的名字与身体，都记在这里。","campaign":"这是前文明战斗影像的训练档案。","arena":"联盟战网目前提供人机训练。","ship_detail":"看看她的等级、熟练度和舰装。","shop":"日常补给和军需在这里。","warehouse":"安全带回的物资保存在这里。"}.get(route,instruction.text))
	if Data.action(node)=="home_build" and route=="home":instruction.text="从建设栏选设施，再拖到合法地块。先建生产和防御，至少实际建好两座。已建好的可以直接检查。"
	if Data.action(node)=="home_garrison" and route=="home":instruction.text="打开「驻防」选一位留守舰娘；再进「战术驻防」，保存礁刃与灯鲨。舰队和岸上都要有人守。"
	if Data.action(node)=="island_defense" and route=="home":instruction.text="打开「驻防 → 战术驻防」，安排灯鲨与另一支部队并保存。然后返回故事迎敌。"
	instruction.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;instruction.custom_minimum_size=Vector2(490,82);instruction.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(instruction)
	var back:=Button.new();back.text="返回故事";back.custom_minimum_size=Vector2(175,66);row.add_child(back)
	if Data.action(node)=="harbor_tour":
		back.text="下一站 ›"
		back.pressed.connect(func():
			for next_route in Service.TOUR:
				if not service.state().tour_seen.has(next_route):
					if next_route=="ship_detail":app.set_meta("detail_ship_id",str(app.economy.formation[0]))
					app.show_page(next_route)
					return
			app.show_page("canon_story"))
	else:
		back.pressed.connect(func():app.show_page("canon_story"))
