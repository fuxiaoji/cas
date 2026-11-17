class_name CasProgression
extends RefCounted
const ChapterProgression=preload("res://scripts/chapter_progression.gd")
## All local mode rewards share the account's atomic commit boundary.
var account
var ai_catalog: Array = []
var challenges: Array = []
var training: Dictionary = {}
var story_data: Dictionary = {}
var rewards: Dictionary = {}

func _init(economy) -> void:
	account = economy
	ai_catalog = _json("res://data/ai-shop.json").get("profiles", [])
	challenges = _json("res://data/challenges.json").get("stages", [])
	training = _json("res://data/training.json").get("courses", {})
	story_data = _json("res://data/prologue.json")
	rewards = _json("res://data/mode-rewards.json")
	_ensure()

func _json(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	return value if value is Dictionary else {}

func _ensure() -> void:
	var defaults:Dictionary={"profiles": ["coord"], "selected_profile": "coord", "courses": [], "lessons": [], "attendance": [], "mail_claimed": [], "campaign": {}, "challenge": {}, "challenge_receipts": {}, "weekly_ticket": "", "weekly_supply": "", "story": {"step": 0, "line": 0, "leaderId": "IBS-U-USN-FLETCHER", "memory": "lost", "flags": {}}, "prologue_reward": false, "legacy_saves": {}, "last_replay": {}}
	# Growth and first-voyage markers may create the shared dictionary before
	# this service. Fill absent leaves without replacing another system's state.
	var progress:Dictionary=account.state.get_or_add("progression",{})
	for key in defaults:progress.get_or_add(key,defaults[key])
	account.state.wallet.get_or_add("up_tickets", 0)

func data() -> Dictionary:
	_ensure()
	return account.state.progression.duplicate(true)

func chapter_status(id:String="") -> Dictionary:return ChapterProgression.new(account,id).state()
func chapter_select(id:String)->Dictionary:return ChapterProgression.new(account).select(id)
func chapter_unlocked(id:String)->bool:return ChapterProgression.new(account).unlocked(id)
func chapter_move(action:String,value:String="") -> Dictionary:return ChapterProgression.new(account).move(action,value)
func chapter_prepare(stage:String) -> Dictionary:return ChapterProgression.new(account,ChapterProgression.CONTENT.chapter_for_stage(stage)).prepare(stage)

func _blocked() -> bool:
	return not account.state.get("active_run", {}).is_empty()

func available_ai_profiles() -> Array[String]:
	var output: Array[String] = []
	for id in data().get("profiles", ["coord"]): output.append(str(id))
	return output

func ai_options() -> Array:
	var output: Array = []
	for item in [{"id":"coord","name":"协同"},{"id":"gunnery","name":"炮战"},{"id":"torpedo","name":"雷击"}] + ai_catalog:
		var row: Dictionary = item.duplicate(true)
		row["owned"] = available_ai_profiles().has(str(row.id))
		output.append(row)
	return output

func selected_profile() -> String:
	return str(data().get("selected_profile", "coord"))

func set_profile(id: String) -> Dictionary:
	if _blocked(): return {"ok":false,"message":"航次进行中，不能更换港口战术预设"}
	if not available_ai_profiles().has(id): return {"ok":false,"message":"该战术尚未拥有"}
	var previous: Dictionary = account.state.duplicate(true)
	account.state.progression.selected_profile = id
	return account._commit(previous, "下次自由演习使用该战术")

func buy_profile(id: String) -> Dictionary:
	if _blocked(): return {"ok":false,"message":"海上行动期间战术采购暂停"}
	if available_ai_profiles().has(id): return {"ok":false,"message":"已拥有该战术，不会重复扣费"}
	var previous: Dictionary = account.state.duplicate(true)
	if id == "gunnery":
		if int(account.wallet().get("medals", 0)) < 6: return {"ok":false,"message":"炮战战术需要6枚舰队勋章"}
		account.state.wallet.medals = int(account.state.wallet.medals) - 6
	else:
		var entry: Dictionary = {}
		for row in ai_catalog:
			if str(row.id) == id: entry = row
		if entry.is_empty(): return {"ok":false,"message":"该战术通过挑战首通解锁"}
		var stage := str(entry.get("stage", str(entry.get("unlock", "")).trim_prefix("campaign:")))
		if int(data().campaign.get(stage, {}).get("stars", 0)) <= 0: return {"ok":false,"message":"先通关%s后开放购买" % str(entry.get("stageName", stage))}
		if int(account.wallet().get("tickets", 0)) < int(entry.cost): return {"ok":false,"message":"常驻征募券不足，还差%d张" % (int(entry.cost) - int(account.wallet().get("tickets", 0)))}
		account.state.wallet.tickets = int(account.state.wallet.tickets) - int(entry.cost)
	account.state.progression.profiles.append(id)
	return account._commit(previous, "战术已入库，战斗AI菜单现可选择")

func day_key(now: int = -1) -> int:
	return int(floor((float(Time.get_unix_time_from_system() if now < 0 else now) + 28800.0) / 86400.0))

func week_key(now: int = -1) -> String:
	var day := day_key(now)
	return str(day - posmod(day + 3, 7))

func claim_mail() -> Dictionary:
	if _blocked(): return {"ok":false,"message":"海上行动期间请先继续或结束航次"}
	if data().mail_claimed.has("welcome-20"): return {"ok":false,"message":"启航邮件已领取"}
	var previous: Dictionary = account.state.duplicate(true)
	account.state.wallet.tickets = int(account.state.wallet.tickets) + 20
	account.state.progression.mail_claimed.append("welcome-20")
	return account._commit(previous, "内测启航补给：常驻征募券20张已到账")

func claim_attendance(now: int = -1) -> Dictionary:
	if _blocked(): return {"ok":false,"message":"航次进行中，签到领取暂停"}
	var attendance: Array = data().attendance
	var schedule: Array = rewards.get("check_in", [])
	if attendance.size() >= schedule.size(): return {"ok":false,"message":"七日签到已经完成"}
	var day := day_key(now)
	if not attendance.is_empty() and day <= int(attendance.back()): return {"ok":false,"message":"今日已领取，日期倒退也不会重复发放"}
	var row: Dictionary = schedule[attendance.size()]
	var previous: Dictionary = account.state.duplicate(true)
	account.state.progression.attendance.append(day)
	_grant({"credits":int(row.get("credits",0)),"tickets":int(row.get("standard_tickets",0)),"up_tickets":int(row.get("up_tickets",0))})
	for identity in row.get("ship_ids", []):
		var id := str(identity)
		if account._cards.has(id) and account._cards[id].get("playable", false):
			if not account.state.owned.has(id): account.state.owned[id] = account._new_owned(id)
			else: account.state.wallet.medals = int(account.state.wallet.medals) + 20
	return account._commit(previous, "第%d天签到补给已到账" % account.state.progression.attendance.size())

func weekly_status(now: int = -1) -> Dictionary:
	var week := week_key(now)
	var clears := 0
	var repeats := 0
	for row in data().challenge_receipts.values():
		if str(row.get("week", "")) == week:
			clears += 1
			if row.get("repeat_reward", false): repeats += 1
	return {"week":week,"clears":clears,"repeats":repeats,"ticket":str(data().weekly_ticket)==week,"supply":str(data().weekly_supply)==week}

func buy_weekly_ticket(now: int = -1) -> Dictionary:
	if _blocked(): return {"ok":false,"message":"航次进行中，补给交易暂停"}
	var status := weekly_status(now)
	if status.ticket: return {"ok":false,"message":"本周配给券已采购"}
	if int(account.wallet().credits) < 500: return {"ok":false,"message":"每周配给券需要500银币"}
	var previous: Dictionary = account.state.duplicate(true)
	account.state.wallet.credits = int(account.state.wallet.credits) - 500
	account.state.wallet.tickets = int(account.state.wallet.tickets) + 1
	account.state.progression.weekly_ticket = status.week
	return account._commit(previous, "每周配给券已入库")

func claim_weekly_supply(now: int = -1) -> Dictionary:
	if _blocked(): return {"ok":false,"message":"航次进行中，补给领取暂停"}
	var status := weekly_status(now)
	if status.supply or int(status.clears) < 3: return {"ok":false,"message":"每周完成3场真实挑战后可领一次补给"}
	var previous: Dictionary = account.state.duplicate(true)
	_grant({"credits":500,"tickets":3})
	account.state.progression.weekly_supply = status.week
	return account._commit(previous, "本周实战补给：500银币与3张常驻券")

func begin_mode(context: Dictionary, serialized: String) -> Dictionary:
	if _blocked(): return {"ok":false,"message":"已有活动航次，请先继续或结束"}
	var mode := str(context.get("mode", "exercise"))
	if mode not in ["exercise","training","story","challenge","campaign","story_chapter"] or serialized.is_empty(): return {"ok":false,"message":"模式或内核快照无效"}
	var snapshot: Variant = JSON.parse_string(serialized)
	if not snapshot is Dictionary or not snapshot.has("version"): return {"ok":false,"message":"原核快照缺少内容版本，航次未提交"}
	var stage_id := str(context.get("id", ""))
	if mode == "campaign" and str(snapshot.get("campaign",{}).get("stageId","")) != stage_id: return {"ok":false,"message":"历史战役快照与关卡身份不符"}
	if mode == "challenge" and (str(snapshot.get("variant","")) != "challenge" or str(snapshot.get("challenge_stage","")) != stage_id): return {"ok":false,"message":"挑战快照与关卡身份不符"}
	if mode == "story" and str(snapshot.get("variant","")) != "prologue": return {"ok":false,"message":"剧情必须使用独立序章想定"}
	if mode == "story_chapter":
		var chapter_error:String=ChapterProgression.new(account,str(context.get("chapter_id","chapter-01"))).validate_start(context,snapshot)
		if not chapter_error.is_empty():return {"ok":false,"message":chapter_error}
	if mode == "challenge":
		var selected: Dictionary = {}
		for stage in challenges:
			if str(stage.id) == str(context.get("id", "")): selected=stage
		if selected.is_empty(): return {"ok":false,"message":"挑战关卡不存在"}
		if selected.get("unlock_after") != null and not data().challenge.get(str(selected.unlock_after), false): return {"ok":false,"message":"请先完成上一挑战关的真实主目标"}
	var previous: Dictionary = account.state.duplicate(true)
	account.state.run_sequence = int(account.state.run_sequence) + 1
	var id := "mode-%d-%s" % [int(account.state.run_sequence), str(context.get("id", mode))]
	var active := {"run_id":id,"mode":mode,"stage_id":stage_id,"context":context.duplicate(true),"snapshot":serialized,"native_variant":str(snapshot.get("variant","")),"evidence":{},"fleet":[],"ruleset":"cas-native-modes-v1"}
	if mode=="exercise" and context.has("tactical_lesson") and str(snapshot.get("version","")) in ["cas-island-war-v3","cas-island-war-v4"]:active.native_variant="cas-littoral-v4"
	account.state.active_run = active.duplicate(true)
	return account._commit(previous, "借用编队已就绪，不消耗个人港口补给", active)

func record_signal(signal_name: String) -> void:
	if account.state.get("active_run", {}).is_empty(): return
	var active: Dictionary = account.state.active_run
	active.get_or_add("evidence", {})[signal_name] = true

func record_command(command: Dictionary, view: Dictionary) -> void:
	var op := str(command.get("op", ""))
	match op:
		"lead": record_signal("lead")
		"route":
			record_signal("syncAccepted" if str(command.get("mode","follow")) == "sync" else "followAccepted")
			if account.state.active_run.get("evidence", {}).get("aiMoveDelegated", false): record_signal("override")
		"fire":
			var weapon:=str(command.get("weapon","gun"))
			record_signal("torpedoOrdered" if weapon == "torpedo" else "gunOrdered")
			if not account.state.get("active_run",{}).is_empty():
				var firing:Dictionary=account.state.active_run.get_or_add("evidence_firing",{})
				var names:Dictionary=firing.get_or_add(weapon,{})
				for ship in view.get("ships",[]):
					if int(ship.get("id",0))==int(command.get("ship",-1)):names[str(ship.get("name",""))]=int(view.get("tick",0))
			var delegated_signal := "aiTorpedoDelegated" if str(command.get("weapon","gun")) == "torpedo" else "aiGunDelegated"
			if account.state.active_run.get("evidence", {}).get(delegated_signal, false): record_signal("override")
		"gun_cancel": record_signal("fireCancelled")
		"ai":
			if str(command.get("mode","manual")) == "auto":
				for key in ["move","gun","torpedo"]:
					if bool(command.get(key,false)):
						record_signal("aiDelegated")
						record_signal({"move":"aiMoveDelegated","gun":"aiGunDelegated","torpedo":"aiTorpedoDelegated"}[key])
		"radar_set": record_signal("radarPowered")
		"illuminate": record_signal("lightAccepted")
	observe(view)

func observe(view: Dictionary) -> void:
	if account.state.get("active_run", {}).is_empty(): return
	var active: Dictionary=account.state.active_run
	if str(active.get("mode",""))=="story":
		var tick:=int(view.get("tick",0))
		var stride:=int(active.get("film_stride",4))
		var frames:Array=active.get_or_add("film_frames",[])
		if frames.is_empty() or tick-int(active.get("film_last_tick",-stride))>=stride:
			frames.append(view.duplicate(true));active["film_last_tick"]=tick
			if frames.size()>180:
				var reduced:Array=[]
				for i in range(0,frames.size(),2):reduced.append(frames[i])
				active.film_frames=reduced;active["film_stride"]=stride*2
	if not view.get("ships", []).is_empty():
		record_signal("fleetViewed")
		record_signal("mapViewed")
	for event in view.get("events", []):
		var kind := str(event.get("kind", ""))
		var text := str(event.get("text", ""))
		if kind in ["gun","torpedo"] and "发射" in text:
			var ordered:Dictionary=active.get("evidence_firing",{}).get(kind,{})
			for name in ordered:
				if not str(name).is_empty() and text.begins_with(str(name)) and int(event.get("tick",0))>=int(ordered[name]):record_signal("gunFired" if kind=="gun" else "torpedoFired")
		if kind == "illumination" and ("照亮" in text or "起亮" in text): record_signal("lightApplied")

func course_status(id: String) -> Dictionary:
	var evidence: Dictionary = account.state.get("active_run", {}).get("evidence", {})
	var steps: Array = training.get(id, {}).get("steps", [])
	var done := 0
	var current: Dictionary = {}
	for step in steps:
		var complete := true
		for signal_name in step.get("require", []):
			if not evidence.get(str(signal_name), false): complete = false
		if complete: done += 1
		elif current.is_empty(): current = step
	return {"done":done,"total":steps.size(),"complete":not steps.is_empty() and done==steps.size(),"current":current,"evidence":evidence.duplicate(true)}

func finish_mode(view: Dictionary, serialized: String = "") -> Dictionary:
	var active: Dictionary = account.state.get("active_run", {})
	if str(active.get("mode",""))=="story_chapter" or (active.is_empty() and str(account.latest_receipt().get("mode",""))=="story_chapter"):
		return ChapterProgression.new(account,str(account.state.get("active_run",{}).get("context",{}).get("chapter_id",view.get("chapter",{}).get("chapterId","chapter-01")))).finish(view,serialized)
	if active.is_empty():
		var latest: Dictionary = account.latest_receipt()
		if latest.get("borrowed", false): return {"ok":true,"duplicate":true,"message":"本地航次已结算，未重复发奖","receipt":latest}
		return {"ok":false,"message":"没有待结算的本地航次"}
	var mode := str(active.get("mode", ""))
	if mode not in ["exercise","training","story","challenge","campaign"]: return {"ok":false,"message":"请按打捞规则结算当前航次"}
	observe(view)
	var context: Dictionary = active.get("context", {})
	if str(view.get("variant","")) != str(active.get("native_variant",view.get("variant",""))): return {"ok":false,"message":"观察所属想定与当前航次不一致，未发放奖励"}
	if mode == "campaign" and str(view.get("campaign",{}).get("stageId","")) != str(active.stage_id): return {"ok":false,"message":"战役结算身份与活动航次不一致"}
	if mode == "challenge" and not serialized.is_empty():
		var terminal: Variant=JSON.parse_string(serialized)
		if not terminal is Dictionary or str(terminal.get("challenge_stage","")) != str(active.stage_id): return {"ok":false,"message":"挑战结算快照不属于当前关卡"}
	var result: Variant = view.get("result")
	var course := str(context.get("course_id", ""))
	var course_done: bool = not course.is_empty() and bool(course_status(course).complete)
	if result == null and not course_done: return {"ok":false,"message":"实际战斗尚未结束，或课程所需操作尚未完成"}
	var side := str(context.get("side", view.get("side", "allies")))
	var success: bool = course_done if not course.is_empty() else (str(result.get("winner", "")) == side if result is Dictionary else false)
	var tactical_training:bool=mode=="exercise" and str(view.get("island_war",{}).get("version","")) in ["cas-island-war-v3","cas-island-war-v4"] and context.has("tactical_lesson")
	if tactical_training:success=result is Dictionary and str(result.get("version",""))==str(context.get("request",{}).get("version","cas-island-war-v3")) and bool(result.get("success",false)) and bool(view.get("littoral",{}).get("outcome",{}).get("success",false))
	if mode == "challenge": success = result is Dictionary and bool(result.get("primary", false))
	var previous: Dictionary = account.state.duplicate(true)
	var stage := str(active.get("stage_id", ""))
	var grade := str(result.get("grade", "none")) if result is Dictionary else "none"
	var stars := 3 if grade == "decisive" else (2 if grade == "tactical" else 0)
	var grant := {"credits":0,"tickets":0,"up_tickets":0,"medals":0,"origins":0,"materials":0}
	var owned_exercise: bool=mode=="campaign" and view.has("ownedGrowth")
	var fictional_taskforce: bool=mode=="campaign" and (owned_exercise or str(context.get("deployment",""))=="taskforce" or context.get("request",{}).has("groups"))
	if owned_exercise:
		for hull in view.ownedGrowth.get("ships",[]):
			var identity:=str(hull.get("id",""))
			if account.state.owned.has(identity): account.state.owned[identity].mastery=mini(1000,int(account.state.owned[identity].get("mastery",0))+clampi(int(hull.get("practice",0)),0,30))
		if success and not data().get("owned_campaign_rewards",{}).has(stage):
			grant.origins=160;grant.materials=16;grant.credits=400
			account.state.progression.get_or_add("owned_campaign_rewards",{})[stage]=true
	if mode == "campaign" and not fictional_taskforce:
		var old: Dictionary = data().campaign.get(stage, {"stars":0,"claimed":0,"best":{}})
		var difficulty := str(context.get("difficulty", "standard"))
		old.get_or_add("best", {})[difficulty] = maxi(int(old.get("best", {}).get(difficulty, 0)), stars)
		old.stars = maxi(int(old.stars), stars)
		for item in rewards.get("campaign", {}).get(stage, []):
			if int(item.stars) > int(old.claimed) and int(item.stars) <= stars:
				grant.credits += int(item.get("credits",0)); grant.tickets += int(item.get("tickets",0)); grant.medals += int(item.get("marks",0)); grant.origins += int(item.get("origins",0)); grant.materials += int(item.get("materials",0))
		old.claimed = maxi(int(old.claimed), stars)
		account.state.progression.campaign[stage] = old
	elif mode == "challenge" and success:
		var first: bool = data().challenge.is_empty()
		account.state.progression.challenge[stage] = true
		var repeat_reward := false
		if first:
			grant.tickets = 2
			if not available_ai_profiles().has("torpedo"): account.state.progression.profiles.append("torpedo")
		elif int(weekly_status().repeats) < 3:
			grant.tickets = 2
			repeat_reward = true
		account.state.progression.challenge_receipts[active.run_id] = {"week":week_key(),"repeat_reward":repeat_reward,"first":first}
	elif mode in ["training","story"] and success and not course.is_empty():
		if not data().courses.has(course):
			grant.origins += 40; grant.materials += 6
		if not data().courses.has(course): account.state.progression.courses.append(course)
		if course=="day" and not bool(data().get("starter_reward",false)):
			grant.tickets+=10;grant.up_tickets+=10
			_starter_ships()
			account.state.progression["starter_reward"]=true
		for step in training.get(course, {}).get("steps", []):
			if not data().lessons.has(str(step.id)): account.state.progression.lessons.append(str(step.id))
		if mode == "story":
			if not serialized.is_empty():account.state.progression["story_battle"]=serialized
			var jump := {"follow":11,"sync":22,"torpedo":28}
			if jump.has(course):
				account.state.progression.story.flags[course] = true
				account.state.progression.story.step = jump[course]
				account.state.progression.story.line = 0
				var film_frames:Array=active.get("film_frames",[])
				if film_frames.is_empty() or int(film_frames.back().get("tick",-1))!=int(view.get("tick",0)):film_frames.append(view.duplicate(true))
				account.state.progression.get_or_add("story_films",{})[course]={"frames":active.get("film_frames",[]).duplicate(true),"snapshot":serialized,"run_id":active.run_id,"course_id":course,"source":"actual seat-visible observations from this user's accepted commands"}
	# Borrowed v3 courses record proof only. Even adding zero would rewrite
	# existing wallet number types, so leave the asset dictionary untouched.
	if not tactical_training:_grant(grant)
	if success and not tactical_training:
		var award:Dictionary=account.grant_player_xp("mode:"+mode+":"+(course if not course.is_empty() else stage),120 if mode=="campaign" else 90)
		if int(award.get("xp",0))>0:grant["commander_xp"]=int(award.xp)
	var summary := {"run_id":active.run_id,"success":success,"mode":mode,"stage_id":stage,"title":str(context.get("title",stage)),"grade":grade,"stars":stars,"coins":int(grant.credits),"loot":{},"lost_loot":{},"xp":0,"ships":[],"rewards":grant,"borrowed":true,"deployment_ammo":0,"returned_ammo":0,"course_complete":course_done}
	if tactical_training:
		var training:Variant=view.get("littoral",{}).get("training")
		summary["tactical_training"]=training.duplicate(true) if training is Dictionary else {}
		summary["snapshot"]=serialized
	if fictional_taskforce:summary["fictional_taskforce"]=true;summary.stars=0;summary["primary"]="特混编成为架空部署，本次不记历史星数或历史奖励"
	if owned_exercise:summary["owned_exercise"]=true;summary["primary"]="自有舰战役演练：成长已生效，历史星数与原阵位模式独立"
	account.state.settled[active.run_id] = summary
	account.state.last_receipt_id = active.run_id
	if not serialized.is_empty():
		account.state.progression.last_replay = {"snapshot":serialized,"context":context.duplicate(true),"run_id":active.run_id}
		account.state.progression.legacy_saves["last-"+mode] = account.state.progression.last_replay.duplicate(true)
	account.state.active_run = {}
	return account._commit(previous, "本地航次已结算，奖励仅提交一次", {"receipt":summary})

func story_move(action: String, value: String = "") -> Dictionary:
	if _blocked(): return {"ok":false,"message":"请先完成或保存当前实操航次"}
	var previous: Dictionary = account.state.duplicate(true)
	var story: Dictionary = account.state.progression.story
	if action == "memory" and int(story.step)==1 and value in ["lost","duty","trust"]: story.memory = value; story.step = 2; story.line = 0
	elif action in ["leader","select_leader"] and int(story.step)==5 and story_data.get("personalities",[]).any(func(row):return str(row.get("id",""))==value):
		story.leaderId=value
		if action=="leader":story.step=6;story.line=0
	elif action=="bind" and int(story.step)==3:story.flags["assistant-bound"]=true;story.step=4;story.line=0
	elif action == "next":
		if int(story.step) in [7,19,24]: return {"ok":false,"message":"请先完成本段真实指挥实操"}
		var lines: Array = story_lines()
		if int(story.line)+1 < lines.size(): story.line=int(story.line)+1
		else: story.step = 18 if int(story.step)==12 else mini(30,int(story.step)+1); story.line=0
	else: return {"ok":false,"message":"未知剧情选择"}
	return account._commit(previous, "剧情进度已保存")

func _starter_ships() -> void:
	for id in ["IBS-U-USN-FLETCHER","IBS-U-USN-PERKINS","IBS-U-USN-MAURY","IBS-U-USN-DRAYTON","IBS-U-USN-LAMSON"]:
		if account._cards.has(id) and not account.state.owned.has(id):account.state.owned[id]=account._new_owned(id)

func claim_prologue() -> Dictionary:
	if _blocked():return {"ok":false,"message":"请先结束当前实操航次"}
	var story:Dictionary=data().story
	if data().prologue_reward:return {"ok":false,"message":"序章奖励已经领取"}
	if int(story.step)<30 or not ["follow","sync","torpedo"].all(func(key):return bool(story.flags.get(key,false))):return {"ok":false,"message":"请先完成三段真实指挥实操和剧情对话"}
	var previous:Dictionary=account.state.duplicate(true)
	var grant:Dictionary=rewards.get("prologue",{}).duplicate(true)
	if bool(data().get("starter_reward",false)):grant.tickets=0;grant.up_tickets=0
	else:_starter_ships();account.state.progression["starter_reward"]=true
	_grant(grant)
	account.state.progression.prologue_reward=true
	if not data().courses.has("prologue"):account.state.progression.courses.append("prologue")
	return account._commit(previous,"序章见面礼已入库：航程、舰娘与补给已经保存")

func story_restart() -> Dictionary:
	if _blocked(): return {"ok":false,"message":"先完成或结束当前航次后再重看剧情"}
	var previous: Dictionary=account.state.duplicate(true)
	account.state.progression.story={"step":0,"line":0,"leaderId":"IBS-U-USN-FLETCHER","memory":"lost","flags":{}}
	account.state.progression["story_battle"]=""
	account.state.progression["story_films"]={}
	return account._commit(previous,"已回到序章开场；既得角色、奖励与结业记录保留")

func cache_story_handover(serialized: String) -> Dictionary:
	if _blocked() or not str(data().get("story_battle","")).is_empty():return {"ok":true,"message":"沿用已保存的序章海图"}
	var parsed:Variant=JSON.parse_string(serialized)
	if not parsed is Dictionary or str(parsed.get("variant",""))!="prologue" or int(parsed.get("tick",0))!=204:return {"ok":false,"message":"序章交接记录与原场次不符"}
	var previous:Dictionary=account.state.duplicate(true)
	account.state.progression["story_battle"]=serialized
	return account._commit(previous,"序章204秒指挥交接已保存")

func abandon_mode(real_view: Dictionary, serialized: String = "") -> Dictionary:
	var active: Dictionary = account.state.get("active_run", {})
	if active.is_empty() or str(active.get("mode", "")) in ["salvage","basic"]: return {"ok":false,"message":"没有可结束的借用航次"}
	var previous: Dictionary = account.state.duplicate(true)
	var context: Dictionary = active.get("context", {})
	var summary := {"run_id":active.run_id,"success":false,"mode":active.mode,"stage_id":str(active.get("stage_id","")),"title":str(context.get("title","借用航次")),"status":"abandoned","primary":"主动结束，本次未产生原核胜负或经济奖励","coins":0,"loot":{},"lost_loot":{},"xp":0,"ships":[],"rewards":{},"borrowed":true,"deployment_ammo":0,"returned_ammo":0,"tick":int(real_view.get("tick",0))}
	account.state.settled[active.run_id] = summary
	account.state.last_receipt_id = active.run_id
	if not serialized.is_empty():account.state.progression.last_replay={"snapshot":serialized,"context":context.duplicate(true),"run_id":active.run_id}
	account.state.active_run={}
	return account._commit(previous,"借用航次已结束；私人舰队与补给保持原状",{"receipt":summary})

func story_lines() -> Array:
	var s: Dictionary = data().story
	var key := str(s.leaderId)+"|"+str(s.memory)
	var steps: Array = story_data.get("variants", {}).get(key, [])
	return steps[clampi(int(s.step),0,steps.size()-1)].get("lines", []) if not steps.is_empty() else []

func _grant(grant: Dictionary) -> void:
	for key in ["credits","tickets","up_tickets","medals","origins","materials"]:
		account.state.wallet[key] = int(account.state.wallet.get(key,0)) + maxi(0,int(grant.get(key,0)))
