extends "res://scripts/littoral_drag_tutorial.gd"
## Three practical lessons. Completion always comes from the public native world.
var lesson: String = "landing"
var _lesson_steps: Array[Dictionary] = []
var _primary: String = "MCP-034"
var _secondary: String = "MCP-001"
var _world_naval:bool=false

func _steps() -> Array[Dictionary]:
	if _lesson_steps.is_empty(): _make_steps()
	return _lesson_steps

func _make_steps() -> void:
	_lesson_steps.clear()
	if lesson == "sea_control":
		_lesson_steps = [
			{"id":"sea_approach","text":"把战舰拖向敌舰附近，进入交战距离","from":"naval_support_card","to":"sea_enemy"},
			{"id":"sea_fight","text":"战舰正在交战；击沉守舰后才能安全登陆","to":"sea_enemy"},
			{"id":"return","text":"制海权已取得，把返航卡拖进撤离圈","from":"return_card","to":"return_zone"},
			{"id":"sail_home","text":"等待所有存活舰艇驶入撤离圈","to":"return_zone"},
			{"id":"extract","text":"把返航卡拖到撤离圈，完成制海训练","from":"return_card","to":"return_zone"}]
		if _world_naval:_lesson_steps[1]={"id":"sea_fight","text":"拖舰旁「炮」到敌舰下令射击；鱼雷需停留瞄准，击沉守舰再返航","from":"gun_badge","to":"sea_enemy"}
		return
	for original: Dictionary in STEPS:
		var step: Dictionary = original.duplicate(true)
		if step.id == "deploy": step.text = "先把陆战队卡拖到滩头；登陆艇慢，但能多载人"
		if step.id == "land": step.text = "载舰靠岸后投送；可用右上方倍速缩短航行等待"
		if step.id == "support": step.text = "把舰炮卡拖到岸防炮台，为登陆部队清出通道"
		_lesson_steps.append(step)
		if lesson == "combined" and step.id == "land":
			_lesson_steps.append({"id":"focus_sea_second","text":"点右上角小地图，安排另一支部队登陆","to":"sea_minimap","tap":true})
			_lesson_steps.append({"id":"deploy_second","text":"再把空突连拖到滩头；直升机快，但耐久较低","from":"deploy_card","to":"landing_zone"})
			_lesson_steps.append({"id":"land_second","text":"等待第二连真实落地；两支部队可以分别指挥","to":"transport"})
		if lesson == "combined" and step.id == "support":
			_lesson_steps.append({"id":"support_hit","text":"等待炮弹命中岸上威胁，再让部队向前推进","to":"support_zone"})
			_lesson_steps.append({"id":"cooperate","text":"把空突连拖向敌人或空地，与陆战队共同推进","from":"squad_card","to":"land_enemy"})

func start_tutorial(progress: Dictionary = {}) -> void:
	lesson = str(progress.get("lesson", "landing"))
	if lesson not in ["sea_control", "landing", "combined"]: lesson = "landing"
	_make_steps()
	super.start_tutorial(progress)
	unit_id = _primary

func snapshot_progress() -> Dictionary:
	var value: Dictionary = super.snapshot_progress()
	value["lesson"] = lesson
	return value

func notify_event(kind: String, data: Dictionary = {}) -> void:
	if not active or _finished or _needs_revalidation or not bool(data.get("accepted", false)): return
	var step: String = current_step()
	if step == "focus_sea_second" and kind == "focus_changed" and str(data.get("focus","")) == "sea":
		_focus = "sea"
		_advance(_event_proof(kind,data))
		return
	if step == "sea_approach" and kind == "ship_moved":
		_advance(_event_proof(kind, data))
		return
	if step == "deploy_second" and kind == "deploy_queued" and str(data.get("unit_id", "")) == _secondary:
		unit_id = _secondary
		_advance(_event_proof(kind, data))
		return
	if step == "cooperate" and kind == "unit_ordered" and str(data.get("unit_id", "")) == _secondary and _event_action(data) in ["move", "attack"]:
		_pending = _event_proof(kind, data)
		_pending["action"] = _event_action(data)
		return
	super.notify_event(kind, data)

func observe_focus(focus: String) -> void:
	if active and not _finished and not _needs_revalidation and current_step()=="focus_sea_second" and focus=="sea":
		_focus=focus
		_advance({"source":"current_ui_state","kind":"already_focused","focus":focus})
		return
	super.observe_focus(focus)

func observe_state(public_view: Dictionary) -> void:
	var littoral: Dictionary = public_view.get("littoral", {})
	if str(littoral.get("version", "")) not in ["cas-littoral-v3","cas-littoral-v4","cas-littoral-coastal-v1"]: return
	var actual_world:bool=str(littoral.get("version","")) in ["cas-littoral-v4","cas-littoral-coastal-v1"]
	if actual_world!=_world_naval:_world_naval=actual_world;_make_steps();_needs_revalidation=true
	var training_value:Variant=littoral.get("training")
	var training:Dictionary=training_value if training_value is Dictionary else {}
	var native_lesson: String = str(training.get("lesson", "landing"))
	if lesson != native_lesson:
		lesson = native_lesson
		_make_steps()
		_index = 0
		_needs_revalidation = true
	if lesson == "sea_control":
		_view = public_view.duplicate(true)
		if not active or _finished: return
		if _needs_revalidation:
			_needs_revalidation = false
			_set_step("return" if bool(training.get("complete", false)) else "sea_approach")
		if current_step() in ["sea_approach", "sea_fight"] and bool(training.get("complete", false)):
			_set_step("return")
		if current_step() == "return" and _fleet_at_exit():
			_advance(_state_proof("fleet_already_at_exit"))
			_advance(_state_proof("fleet_arrived"))
		elif current_step() == "sail_home" and _fleet_at_exit(): _advance(_state_proof("fleet_arrived"))
		elif current_step() == "extract" and _successful_outcome(): _advance(_state_proof("successful_core_outcome"))
		return
	if lesson == "combined":
		_view = public_view.duplicate(true)
		if not active or _finished: return
		if _needs_revalidation and training.get("landed_company_ids",[]).size()==1:
			unit_id=_primary
			if str(_group().get("stage",""))=="ground":
				_needs_revalidation=false
				_set_step("focus_sea_second")
				return
		var step: String = current_step()
		if step in ["deploy_second", "land_second"]:
			unit_id = _secondary
			var secondary: Dictionary = _group()
			if step == "deploy_second" and (_has_pending_deploy(secondary) or str(secondary.get("stage", "")) in ["transit", "ground"]): _advance(_state_proof("second_transport_launched"))
			if current_step() == "land_second" and str(secondary.get("stage", "")) == "ground": _advance(_state_proof("second_company_landed"))
			return
		if step == "support_hit":
			if int(training.get("shore_support_hits", 0)) > 0: _advance(_state_proof("actual_shore_hit"))
			elif _naval_unavailable():
				_context_hint = "炮援弹药不足：请从菜单重新开始协同训练"
				_refresh()
			return
		if step == "cooperate":
			unit_id = _secondary
			if not _pending.is_empty() and str(_group().get("order", "")) == str(_pending.get("action", "")):
				_advance(_state_proof("second_company_order_confirmed"))
			return
		if step == "recover":
			for group: Dictionary in littoral.get("groups", []):
				if float(group.get("hp_percent", 0)) > 0 and str(group.get("stage", "")) == "ground" and str(group.get("order", "")) != "retreat":
					unit_id = str(group.id)
					_set_step("withdraw")
					_context_hint = "还有部队在岸上，把撤收卡拖回这支连队"
					_refresh()
					return
	super.observe_state(public_view)

func _advance(proof: Dictionary) -> void:
	super._advance(proof)
	if not _finished:
		if current_step() in ["focus_sea_second", "deploy_second", "land_second", "cooperate"]: unit_id = _secondary
		elif current_step() not in ["withdraw", "recover"]: unit_id = _primary

func _naval_unavailable()->bool:
	if not _world_naval:return super._naval_unavailable()
	for ship in _view.get("ships",[]):
		if float(ship.get("hp",0))<=0:continue
		var intact:bool=ship.get("systems",{}).get("guns",[]).any(func(row):return not bool(row.get("destroyed",false)))
		if not intact:continue
		for support in _view.get("littoral",{}).get("support",{}).get("naval",[]):
			if int(support.get("ship",-1))==int(ship.id) and float(support.get("ammo",0))>0:return false
	return true

