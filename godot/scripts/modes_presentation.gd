extends RefCounted
## Native menus for the existing single-player modes. No invented combat outcomes.
const Design = preload("res://scripts/ui_design.gd")
const PAPER := Design.INK
const GOLD := Color("987536")
const MUTED := Design.MUTED
const Film=preload("res://scripts/prologue_film.gd")
const Cinema=preload("res://scripts/cinematic_presentation.gd")
const Supply=preload("res://scripts/supply_presentation.gd")
const Missions=preload("res://scripts/mission_presentation.gd")

static func render(app, route: String) -> void:
	match route:
		"academy": academy(app)
		"story": story(app)
		"challenge": challenge(app)
		"activity": activity(app)
		"mail": mail(app)
		"resources", "ladder": Missions.render(app,route)
		"archives": archives(app)
		_: modes(app)

static func _head(app, _title: String, subtitle: String) -> void:
	# The global page bar already names the mode. Keep only useful supporting context.
	app.label(app.page,subtitle,63,137,1440,45,22,MUTED)

static func _launch(app, request: Dictionary, context: Dictionary) -> void:
	if not app.economy.state.get("active_run",{}).is_empty(): app.notify({"ok":false,"message":"请先继续或结束活动航次"}); return
	app.start_local_mode(request, context)

static func _destination(app, title: String, subtitle: String, route: String, asset: String, rect: Rect2, icon: String) -> void:
	var card := Control.new()
	card.clip_contents = true
	app.place(card, app.page, rect.position.x, rect.position.y, rect.size.x, rect.size.y)
	app.picture(card, asset, 0, 0, 1600, 900, true)
	Cinema.gradient(app, card, Rect2(0,0,1600,900), Color(0.04,0.15,0.23,0.05), Color(0.04,0.15,0.23,0.9))
	app.label(app.page, title, rect.position.x+25, rect.end.y-111, rect.size.x-50, 49, 28, Cinema.WHITE)
	app.label(app.page, subtitle, rect.position.x+28, rect.end.y-59, rect.size.x-50, 34, 20, Color("d5e5e6"))
	var hit: Button = app.button(app.page, "", rect.position.x, rect.position.y, rect.size.x, rect.size.y, func():app.show_page(route))
	hit.tooltip_text = title
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(1,1,1,0.06 if state=="hover" else 0)
		box.border_color = Color("e4cb8a")
		box.set_border_width_all(3 if state=="focus" else 0)
		hit.add_theme_stylebox_override(state, box)
	if app.has_method("icon"): app.icon(app.page,icon,rect.position.x+25,rect.position.y+22,44,44,Cinema.WHITE)

static func modes(app) -> void:
	_destination(app,"打捞远征","自有舰队 · 搜索、交战、撤离","expedition","res://assets/backgrounds/harbor-day-v2.png",Rect2(60,145,530,575),"sortie")
	_destination(app,"借来的灯，自己的岸","第五小队 · 航海日志","canon_catalog","res://assets/story/canon-v2/c1-rescue.png",Rect2(612,145,450,278),"story")
	_destination(app,"历史战役","历史借用 · 自有舰演练","campaign","res://assets/backgrounds/harbor-night.png",Rect2(612,445,450,275),"fleet")
	_destination(app,"资源海域","银币、装备与水手","resources","res://assets/backgrounds/harbor-day-v2.png",Rect2(1084,145,456,175),"cargo")
	_destination(app,"天梯挑战","预算对抗 · 每周元词补给","ladder","res://assets/recruit/missouri-up-v1.png",Rect2(1084,340,456,175),"trophy")
	_destination(app,"舰桥学堂","教学与进阶挑战","academy","res://assets/backgrounds/recruit-sky.png",Rect2(1084,535,456,185),"training")
	for i in range(3):
		var route: String = ["arena","activity","archives"][i]
		var label: String = ["人机排位 / 3v3","补给与活动","航次档案"][i]
		var entry: Button = app.button(app.page,label,612+i*315,747,298,55,func():app.show_page(route))
		Design.apply_button(entry, false, true)
	app.button(app.page,"整备出航",60,747,530,55,func():app.show_page("formation"),true)

static func academy(app) -> void:
	_head(app,"舰桥学堂","从第一道航令开始。教学编队免费借用。")
	var courses := [{"id":"day","name":"昼间实操","variant":"","text":"领舰、尾随、同步、炮击取消、雷击与接管AI。"},{"id":"night","name":"夜海初航","variant":"night-training","text":"建立接触，照明弹实际起亮，再完成炮击和雷击。"},{"id":"radar","name":"雷达与照明","variant":"night-radar-training","text":"开机、获取接触、照明与正式战情。"}]
	for i in range(courses.size()):
		var row: Dictionary = courses[i]
		var x := 60+i*500
		app.panel(app.page,x,270,470,409)
		app.picture(app.page,"res://assets/backgrounds/harbor-day-v2.png" if i==0 else "res://assets/backgrounds/harbor-night.png",x+12,282,446,145,true)
		app.label(app.page,str(row.name),x+25,438,420,55,28,PAPER)
		app.label(app.page,str(row.text),x+25,498,420,70,21,MUTED)
		var done: bool = app.progression.data().courses.has(str(row.id))
		app.label(app.page,"已结业" if done else "等待实操",x+25,565,420,30,19,GOLD)
		app.button(app.page,"复习课程" if done else "开始课程",x+25,594,420,62,func():
			_launch(app,{"op":"new","variant":str(row.variant),"seed":6106,"side":"allies","enemy":"gunnery","profile":"coord","realtime":true},{"mode":"training","id":str(row.id),"course_id":str(row.id),"title":str(row.name),"side":"allies"}),true)
	app.button(app.page,"白昼5对5演习",65,700,340,48,func():_exercise(app,"","白昼演习"))
	app.button(app.page,"夜航接敌",430,700,340,48,func():_exercise(app,"night","夜航演习"))
	app.button(app.page,"1943雷达演习",795,700,340,48,func():_exercise(app,"radar","1943雷达演习"))
	app.button(app.page,"越级挑战",1160,700,370,48,func():app.show_page("challenge"))

static func _exercise(app, variant: String, title: String) -> void:
	_launch(app,{"op":"new","variant":variant,"seed":6106,"side":"allies","enemy":"gunnery","profile":app.progression.selected_profile(),"realtime":true},{"mode":"exercise","id":variant if not variant.is_empty() else "day","title":title,"side":"allies"})

static func challenge(app) -> void:
	_head(app,"越级挑战","五场进阶考验 · 首通奖励与每周补给")
	var stages: Array = app.progression.challenges
	if stages.is_empty(): return
	var chosen := clampi(int(app.get_meta("challenge_focus",0)),0,stages.size()-1)
	var selected: Dictionary = stages[chosen]
	var available: bool = selected.get("unlock_after")==null or bool(app.progression.data().challenge.get(str(selected.unlock_after),false))
	app.picture(app.page,"res://assets/recruit/missouri-up-v1.png",60,260,830,470,true)
	Cinema.gradient(app,app.page,Rect2(60,260,830,470),Color(0.02,0.09,0.15,0.1),Color(0.02,0.09,0.15,0.95))
	app.label(app.page,str(selected.name),90,477,740,65,32,Cinema.WHITE)
	app.label(app.page,str(selected.objective),94,563,740,98,24,Cinema.WHITE)
	var launch: Button = app.button(app.page,"开始挑战",70,750,820,60,func():_launch(app,{"op":"new","variant":"challenge","stage":str(selected.id),"seed":int(selected.seed),"side":"allies","enemy":str(selected.enemy_profile),"profile":str(selected.profile),"leaderSlot":int(selected.player.allies.leader_slot)},{"mode":"challenge","id":str(selected.id),"title":str(selected.name),"side":"allies"}),true)
	launch.disabled = not available
	launch.tooltip_text = str(selected.get("brief","")) if available else "先完成前一场挑战"
	for i in range(stages.size()):
		var row: Dictionary = stages[i]
		var index := i
		var unlocked: bool = row.get("unlock_after")==null or bool(app.progression.data().challenge.get(str(row.unlock_after),false))
		var cleared: bool = app.progression.data().challenge.get(str(row.id),false)
		app.button(app.page,str(row.name),930,266+i*98,600,88,func():app.set_meta("challenge_focus",index);app.show_page("challenge"),i==chosen)
		app.label(app.page,"已通关" if cleared else ("可出击" if unlocked else "待解锁"),1390,286+i*98,120,45,18,PAPER if i==chosen else MUTED)

static func activity(app) -> void:
	_head(app, "回港礼物", "每天靠港，都有一份新的补给。")
	var claimed: int = app.progression.data().attendance.size()
	var days: Array = app.progression.rewards.get("check_in",[])
	for i in range(days.size()):
		var row: Dictionary = days[i]
		var x := 60 + i * 213
		app.panel(app.page,x,265,199,265,Color(1,0.97,0.87,0.95) if i==claimed else Color(0.96,0.98,0.96,0.85))
		app.label(app.page,"第 %d 天"%(i+1),x+17,280,165,37,21,GOLD)
		if row.has("ship_ids"):
			Cinema.card_art(app,app.page,str(app.cards.get(str(row.ship_ids[0]),{}).get("portrait","")),x+20,325,159,90)
		elif app.has_method("icon"):
			app.icon(app.page,"coin" if row.has("credits") else "ticket",x+65,339,70,70,GOLD)
		var rewards: PackedStringArray = []
		if row.has("credits"): rewards.append("%d 银币" % int(row.credits))
		if row.has("standard_tickets"): rewards.append("%d 常驻券" % int(row.standard_tickets))
		if row.has("up_tickets"): rewards.append("%d UP券" % int(row.up_tickets))
		if row.has("ship_ids"): rewards.append("北卡罗来纳")
		app.label(app.page,"\n".join(rewards),x+16,423,175,65,20,PAPER)
		app.label(app.page,"已领取" if i<claimed else ("今日可领" if i==claimed else "待开启"),x+17,488,165,27,18,MUTED)
	app.button(app.page,"领取今日签到",60,559,350,62,func():_refresh(app,"activity",app.progression.claim_attendance()),true)
	app.button(app.page,"查看邮件",440,559,440,62,func():app.show_page("mail"))
	var week: Dictionary = app.progression.weekly_status()
	app.label(app.page,"本周实战 %d / 3 场"%int(week.clears),65,680,450,42,25,PAPER)
	app.label(app.page,"每日北京时间刷新 · 漏签顺延",65,754,460,34,18,MUTED)
	app.button(app.page,"采购周配给券 · 500银币",570,682,470,59,func():_refresh(app,"activity",app.progression.buy_weekly_ticket()))
	app.button(app.page,"领取3场实战周补给",1070,682,470,59,func():_refresh(app,"activity",app.progression.claim_weekly_supply()))

static func mail(app) -> void:
	var claimed:bool=app.progression.data().mail_claimed.has("welcome-20")
	app.panel(app.page,60,150,435,610,Color(1,1,1,0.76))
	app.icon(app.page,"supply",85,185,64,64,Design.ACCENT)
	app.label(app.page,"启航补给",175,189,285,50,25,PAPER)
	app.label(app.page,"已领取" if claimed else "待领取",177,249,285,38,20,MUTED)
	app.panel(app.page,525,150,1015,610,Color(1,1,1,0.85))
	app.label(app.page,"给指挥官的第一份补给",570,190,900,65,30,PAPER)
	app.label(app.page,"新的航程即将开始。\n请收下征募券，邀请更多同行者加入舰队。",575,291,865,135,24,MUTED)
	app.icon(app.page,"ticket",580,485,92,92,Design.ACCENT)
	app.label(app.page,"常驻征募券 ×20",701,495,700,55,26,PAPER)
	var claim:Button=app.button(app.page,"已领取" if claimed else "领取附件",1155,650,330,62,func():_refresh(app,"mail",app.progression.claim_mail()),true)
	claim.disabled=claimed or not app.economy.state.get("active_run",{}).is_empty()

static func _refresh(app, route: String, response: Dictionary) -> void:
	app.show_page(route);app.notify(response)

static func render_shop(app) -> void:
	Supply.render(app)

static func ship_detail(app, ship: Dictionary) -> void:
	app.set_meta("detail_ship_id",str(ship.get("id","")))
	app.show_page("ship_detail")

static func _story_chrome(app, controls := true) -> void:
	var dark := int(app.progression.data().story.step) != 5
	Cinema.quiet_button(app, app.page, "‹ 返回", 42, 28, 140, func(): app.go_back(), dark)
	Cinema.quiet_button(app, app.page, "母港", 195, 28, 112, app.go_home, dark).name="NavigateHome"
	Cinema.quiet_button(app, app.page, "对白回顾", 1150, 28, 130, func(): Cinema.backlog(app), dark)
	if controls:
		Cinema.quiet_button(app, app.page, "自动：开" if bool(app.get_meta("story_auto", false)) else "自动", 1300, 28, 105, func(): app.set_meta("story_auto", not bool(app.get_meta("story_auto", false))); app.show_page("story"), dark)
		Cinema.quiet_button(app, app.page, "跳过本段", 1420, 28, 140, func(): _skip_dialogue(app), dark)

static func _skip_dialogue(app) -> void:
	var saved: Dictionary = app.progression.data().story
	var step := int(saved.step)
	# Never choose a branch, appoint a leader, grant a reward or skip a course.
	if step in [0,3,5,7,11,19,22,24,28,30]: return
	for i in range(40):
		var state: Dictionary = app.progression.data().story
		var lines: Array = app.progression.story_lines()
		if int(state.step) != step: break
		if step == 1 and int(state.line) >= lines.size() - 1: break
		if not lines.is_empty():
			var line: Dictionary = lines[clampi(int(state.line), 0, lines.size()-1)]
			Cinema.remember(app, str(line.get("speaker", "")), str(line.get("text", "")))
		var result: Dictionary = app.progression.story_move("next")
		if not result.get("ok", false): break
	app.show_page("story")

static func story(app) -> void:
	var saved: Dictionary = app.progression.data().story
	var step := int(saved.step)
	if step in [0,11,22,28]:
		story_film(app, step)
		return
	Cinema.background(app, app.page, step < 4)
	if step == 30:
		app.picture(app.page, "res://assets/story/prologue-victory-pov.png", 0, 0, 1600, 900, true)
		Cinema.gradient(app, app.page, Rect2(0, 0, 1600, 900), Color(0.02,0.1,0.16,0), Color(0.02,0.1,0.16,0.88))
		app.label(app.page, "我们，一起回港", 90, 590, 1100, 70, 40, Cinema.WHITE)
		app.label(app.page, "五艘驱逐舰，和一个新的开始。", 96, 697, 900, 55, 25, Cinema.WHITE)
		var claimed: bool = app.progression.data().prologue_reward
		app.label(app.page, "序章见面礼  2000银币  ·  初航舰队  10常驻券 / 10UP券", 96, 775, 970, 40, 20, Cinema.WHITE)
		app.button(app.page, "返回母港" if claimed else "领取序章奖励", 1180, 774, 330, 65, func(): app.show_page("harbor") if claimed else _refresh(app,"story",app.progression.claim_prologue()), true)
		return
	if step == 3:
		var actor:TextureRect=app.picture(app.page, "res://assets/story/baixi.png", 700, 126, 780, 690)
		actor.texture=load("res://scripts/story_actor_layout.gd").portrait(actor.texture,"baixi")
		load("res://scripts/story_actor_layout.gd").fade(actor)
		actor.set_meta("story_actor",true)
		Cinema.dialogue(app, "白汐", "我会为你整理舰队情报、核对航路和火力。\n每一道命令，仍由你决定。", true)
		_story_chrome(app, false)
		app.button(app.page, "接入辅助", 1260, 833, 250, 48, func(): _refresh(app,"story",app.progression.story_move("bind")), true)
		return
	var lines: Array = app.progression.story_lines()
	var line: Dictionary = lines[clampi(int(saved.line),0,lines.size()-1)] if not lines.is_empty() else {}
	var personality: Dictionary = app.cards.get(str(line.get("shipId",saved.leaderId)), {})
	var asset := "res://assets/story/baixi.png" if str(line.get("speaker", "")).begins_with("白汐") else str(personality.get("portrait", "res://assets/backgrounds/login-instructor.png"))
	if step != 5:
		var actor:TextureRect=app.picture(app.page, asset, 700, 126, 780, 690)
		actor.texture=load("res://scripts/story_actor_layout.gd").portrait(actor.texture,asset)
		load("res://scripts/story_actor_layout.gd").fade(actor)
		actor.set_meta("story_actor",true)
	if step in [7,19,24]:
		var course := "follow" if step==7 else ("sync" if step==19 else "torpedo")
		Cinema.dialogue(app, {"follow":"沿领舰航迹横切","sync":"改令同步机动","torpedo":"编队雷击"}[course], "指挥官，接下来交给你。")
		_story_chrome(app, false)
		app.button(app.page, "进入指挥实操", 1170, 837, 340, 56, func():launch_story(app,course,str(saved.leaderId)), true)
		return
	if step == 5:
		Cinema.gradient(app, app.page, Rect2(0, 110, 1600, 790), Color(0.98,0.98,0.94,0.2), Color(0.98,0.98,0.94,0.98))
		app.label(app.page, "由谁带领我们？", 80, 142, 1000, 70, 32, PAPER)
		var people: Array = app.progression.story_data.get("personalities", [])
		for i in range(people.size()):
			var row: Dictionary = people[i]
			var x := 85 + i * 291
			var chosen := str(saved.leaderId) == str(row.id)
			app.panel(app.page, x, 274, 265, 437, Color(1,0.97,0.87,0.94) if chosen else Color(0.95,0.98,0.98,0.8))
			Cinema.card_art(app, app.page, str(app.cards.get(str(row.id),{}).get("portrait","")), x+5, 280, 255, 350)
			app.button(app.page, str(row.name), x+12, 642, 241, 55, func():_refresh(app,"story",app.progression.story_move("select_leader",str(row.id))), chosen)
		_story_chrome(app, false)
		app.button(app.page, "任命领舰", 1180, 785, 330, 65, func():_refresh(app,"story",app.progression.story_move("leader",str(saved.leaderId))), true)
		return
	var speaker := str(line.get("speaker", "白汐"))
	var message := str(line.get("text", "本段航迹与战果都已记入舰历。"))
	Cinema.dialogue(app, speaker, message, step < 4)
	Cinema.remember(app, speaker, message)
	_story_chrome(app)
	var choosing := step==1 and int(saved.line)>=lines.size()-1
	if choosing:
		var options := ["什么都想不起来","先告诉我舰队情况","你是谁？我能相信你吗"]
		for i in range(3):
			var key: String = ["lost","duty","trust"][i]
			app.button(app.page, options[i], 110+i*465, 837, 445, 47, func():_refresh(app,"story",app.progression.story_move("memory",key)))
	else:
		Cinema.quiet_button(app, app.page, "继续对话", 1320, 833, 190, func():_refresh(app,"story",app.progression.story_move("next")), true)
		if bool(app.get_meta("story_auto", false)):
			var timer := Timer.new()
			timer.one_shot = false
			timer.wait_time = clampf(float(message.length()) * 0.13, 3.5, 12.0)
			app.page.add_child(timer)
			timer.timeout.connect(func():
				if not is_instance_valid(app.modal): _refresh(app, "story", app.progression.story_move("next")))
			timer.start()

static func story_film(app, step: int) -> void:
	var film = Film.new()
	film.app = app
	film.opening = step == 0
	if step != 0:
		var course := "follow" if step==11 else ("sync" if step==22 else "torpedo")
		var record: Dictionary = app.progression.data().get("story_films",{}).get(course,{})
		film.recording = record.get("frames",[])
		film.replay_snapshot = str(record.get("snapshot",""))
	app.place(film, app.page, 0, 0, 1600, 900)
	Cinema.gradient(app, app.page, Rect2(0, 630, 1600, 270), Color(0.02,0.09,0.15,0), Color(0.02,0.09,0.15,0.92))
	var text: String = "海面正在燃烧，而你的记忆停在了炮声之前。" if step==0 else {11:"沿着她的航迹，我们穿过这片海。",22:"所有舰艇，按同一时刻转向。",28:"鱼雷离管。愿我们都能平安归航。"}.get(step, "")
	app.label(app.page, text, 95, 738, 1030, 90, 28, Cinema.WHITE).add_theme_font_override("font",Design.font(400))
	Cinema.quiet_button(app, app.page, "‹ 返回", 42, 28, 140, func():app.go_back(), true)
	Cinema.quiet_button(app, app.page, "母港", 195, 28, 112, app.go_home, true).name="NavigateHome"
	app.label(app.page, "未明的海  ·  序章" if step==0 else "航迹回望", 72, 111, 1100, 52, 24, Cinema.WHITE)
	if step==0: app.label(app.page, "架空故事", 75, 165, 700, 35, 17, Color("b1ccd2"))
	app.button(app.page, "进入舰桥" if step==0 else "返回剧情", 1210, 793, 300, 62, func():_refresh(app,"story",app.progression.story_move("next")), true)

static func launch_story(app,course:String,leader_id:String) -> void:
	if not app.economy.state.get("active_run",{}).is_empty():app.notify({"ok":false,"message":"请先继续或结束当前航次"});return
	var snapshot:=str(app.progression.data().get("story_battle",""))
	var response:Dictionary
	if snapshot.is_empty():
		response=app.core.request({"op":"new","variant":"prologue","seed":6106,"side":"allies","enemy":"gunnery","profile":"coord","realtime":true})
		if response.get("ok",false):response=app.core.request({"op":"step","seconds":204})
	else:response=app.core.request({"op":"load","serialized":snapshot})
	if not response.get("ok",false):app.notify(response);return
	if course=="follow" and int(app.core.view.get("tick",0))==204:
		var squadron:Dictionary=app.core.view.get("fleets",[{}])[0]
		for ship in app.core.view.get("ships",[]):
			if str(ship.get("characterId",""))==leader_id and int(squadron.get("leader",0))!=int(ship.id):
				response=app.core.request({"op":"lead","fleet":int(squadron.get("id",1)),"ship":int(ship.id)})
				if not response.get("ok",false):app.notify(response);return
	var save:Dictionary=app.core.request({"op":"save","serialized":true})
	if not save.get("ok",false):app.notify(save);return
	app.start_local_mode({"op":"load","serialized":str(save.serialized)},{"mode":"story","id":"prologue-"+course,"course_id":course,"title":"未明的海 · "+course,"side":"allies"})

static func archives(app) -> void:
	_head(app,"航次档案","回到上次停泊的地方，或重温一场战斗。")
	var active:Dictionary=app.economy.state.get("active_run",{})
	app.label(app.page,"保存的航程" if not active.is_empty() else "尚无未完成的航程",65,265,1400,60,27,GOLD)
	if not active.is_empty():app.button(app.page,"继续保存的航次",65,347,600,64,app.resume_run,true)
	var replay:Dictionary=app.progression.data().get("last_replay",{})
	app.label(app.page,str(replay.get("context",{}).get("title","尚无可回看的航迹")),65,470,1400,60,27,PAPER)
	if not replay.is_empty():
		app.button(app.page,"打开只读重演",65,551,600,64,func():
			if app.has_method("start_replay"):app.start_replay(replay)
			else:app.notify({"ok":false,"message":"请从战斗战情页的重演入口查看"}),true)
	app.button(app.page,"查看最近战果",65,659,600,64,func():app.last_receipt=app.economy.latest_receipt();app.show_page("result"))
