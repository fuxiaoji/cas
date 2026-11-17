extends Control
## Event-driven, non-blocking guidance. Never issues combat commands or grants rewards.
## Saved UI proofs are diagnostics. Public core observations revalidate resumed phases.

signal step_changed(step_id: String, index: int)
signal action_complete(step_id: String, proof: Dictionary)
signal progress_changed(progress: Dictionary)
signal completed
signal help_closed

const VERSION: int = 1
const STEPS: Array[Dictionary] = [
	{"id":"deploy", "text":"把部队卡拖到发光滩头", "from":"deploy_card", "to":"landing_zone"},
	{"id":"approach", "text":"载舰正在驶近滩头", "to":"transport"},
	{"id":"land", "text":"等待登陆艇把部队送上岸", "to":"landing_zone"},
	{"id":"focus_land", "text":"点右上角小地图，查看陆地", "to":"land_minimap", "tap":true},
	{"id":"move", "text":"把部队卡拖到空地，向前移动", "from":"squad_card", "to":"land_move_zone"},
	{"id":"attack", "text":"把部队卡拖到敌人身上，发起攻击", "from":"squad_card", "to":"land_enemy"},
	{"id":"focus_sea", "text":"点右上角小地图，切回海图", "to":"sea_minimap", "tap":true},
	{"id":"aim", "text":"把海图上的舰艇拖向岛屿，调整炮位", "from":"naval_support_card", "to":"naval_target"},
	{"id":"focus_land_support", "text":"点右上角小地图，选择炮援落点", "to":"land_minimap", "tap":true},
	{"id":"support", "text":"把舰炮支援卡拖到岸上目标", "from":"land_support_card", "to":"support_zone"},
	{"id":"search", "text":"把部队卡拖到遗迹，搜索物资", "from":"squad_card", "to":"search_zone"},
	{"id":"withdraw", "text":"把撤收卡拖到部队，返回载舰", "from":"withdraw_card", "to":"withdraw_zone"},
	{"id":"recover", "text":"等待部队实际返回载舰", "to":"transport"},
	{"id":"focus_sea_return", "text":"点右上角小地图，准备舰队返航", "to":"sea_minimap", "tap":true},
	{"id":"return", "text":"把返航卡拖到海上的撤离圈", "from":"return_card", "to":"return_zone"},
	{"id":"sail_home", "text":"等待所有存活舰艇驶入撤离圈", "to":"return_zone"},
	{"id":"extract", "text":"把返航卡拖到撤离圈，完成行动", "from":"return_card", "to":"return_zone"},
]

@export_range(0.0, 0.75, 0.01) var dim_strength: float = 0.34
@export_range(1.5, 5.0, 0.1) var gesture_seconds: float = 2.8
@export var reduced_motion: bool = false
@export var safe_margin: float = 18.0

var active: bool = false
var unit_id: String = ""
var _index: int = 0
var _proofs: Dictionary = {}
var _targets: Dictionary = {}
var _seen_events: Dictionary = {}
var _pending: Dictionary = {}
var _view: Dictionary = {}
var _needs_revalidation: bool = true
var _finished: bool = false
var _gesture: float = 0.0
var _panel: PanelContainer
var _instruction: Label
var _close: Button
var _saved_step: String = "deploy"
var _review_only: bool = false
var _focus: String = ""
var _context_hint: String = ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = get_node_or_null("Hint") as PanelContainer
	if _panel == null:
		_build_hint()
	else:
		_instruction = _panel.get_node("Margin/Row/Instruction") as Label
		_close = _panel.get_node("Margin/Row/Close") as Button
	_instruction.max_lines_visible = 2
	_instruction.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_instruction.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_panel.minimum_size_changed.connect(func() -> void: _layout_hint.call_deferred())
	_close.pressed.connect(close_help)
	resized.connect(_layout_hint)
	_layout_hint()
	_refresh()
	visible = active
	set_process(active and not reduced_motion)

func _build_hint() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Hint"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("183b48")
	style.border_color = Color("c9d9c3")
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.shadow_color = Color(0, 0, 0, .22)
	style.shadow_size = 5
	_panel.add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_"+side, 10 if side in ["top", "bottom"] else 16)
	_panel.add_child(margin)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	_instruction = Label.new()
	_instruction.name = "Instruction"
	_instruction.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_instruction.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_instruction.add_theme_font_size_override("font_size", 20)
	_instruction.add_theme_color_override("font_color", Color("fff6db"))
	row.add_child(_instruction)
	_close = Button.new()
	_close.name = "Close"
	_close.text = "稍后"
	_close.tooltip_text = "收起提示，可在帮助中重新学习"
	_close.custom_minimum_size = Vector2(62, 48)
	_close.add_theme_font_size_override("font_size", 17)
	row.add_child(_close)

func _layout_hint() -> void:
	if _panel == null:
		return
	var panel_width: float = minf(610.0, maxf(250.0, size.x * .65))
	_panel.position = Vector2(maxf(safe_margin, (size.x-panel_width)*.5), safe_margin)
	_panel.size = Vector2(minf(panel_width, maxf(100.0, size.x-safe_margin*2)), clampf(_panel.get_combined_minimum_size().y, 72, 90))
	queue_redraw()

func set_targets(rects: Dictionary) -> void:
	_targets.clear()
	for key: Variant in rects:
		if rects[key] is Rect2 and (rects[key] as Rect2).has_area():
			_targets[str(key)] = rects[key]
	queue_redraw()

func _steps() -> Array[Dictionary]:
	return STEPS

func current_step() -> String:
	return "complete" if _finished else str(_steps()[_index].id)

func instruction_text() -> String:
	return str(_steps()[_index].text) if not _finished else "部队已归队"

func start_tutorial(progress: Dictionary = {}) -> void:
	active = true
	_finished = false
	_index = 0
	_proofs.clear()
	_seen_events.clear()
	_pending.clear()
	# _view may reference the controller's public observation. Detach it before
	# restarting help; clearing that shared Dictionary would erase the battle UI.
	_view = {}
	_focus = ""
	_context_hint = ""
	_needs_revalidation = true
	_saved_step = str(progress.get("step_id", "deploy"))
	_review_only = bool(progress.get("review_only", false))
	unit_id = str(progress.get("unit_id", "")) if int(progress.get("version", VERSION)) == VERSION else ""
	_gesture = 0
	visible = true
	set_process(not reduced_motion)
	_refresh()
	# The controller supplies a fresh core snapshot after start. Never reuse a
	# previous run's recovered view to complete a new run before its first update.

func replay() -> void:
	start_tutorial({"review_only":true})

func close_help() -> void:
	active = false
	visible = false
	set_process(false)
	help_closed.emit()
	progress_changed.emit(snapshot_progress())

func snapshot_progress() -> Dictionary:
	return {"version":VERSION, "step_id":current_step(), "unit_id":unit_id, "proofs":_proofs.duplicate(true), "help_open":active, "review_only":_review_only}

func notify_event(kind: String, data: Dictionary = {}) -> void:
	if not active or _finished or _needs_revalidation or kind == "drag_rejected":
		return
	if not bool(data.get("accepted", false)):
		return
	var event_id: String = str(data.get("event_id", ""))
	if not event_id.is_empty():
		if _seen_events.has(event_id):
			return
		_seen_events[event_id] = true
		if _seen_events.size() > 256:
			_seen_events.erase(_seen_events.keys()[0])
	if not str(data.get("unit_id", "")).is_empty():
		if unit_id.is_empty() or (kind == "deploy_queued" and current_step() == "deploy"):
			unit_id = str(data.unit_id)
		elif unit_id != str(data.unit_id) and kind in ["unit_ordered", "withdraw_ordered"]:
			return
	var step: String = current_step()
	var focus: String = str(data.get("focus", data.get("map_focus", data.get("map", ""))))
	if kind == "focus_changed":
		_focus = focus
		if (step in ["focus_land", "focus_land_support"] and focus == "land") or (step in ["focus_sea", "focus_sea_return"] and focus == "sea"):
			_advance({"source":"interaction", "kind":kind, "focus":focus, "event_id":event_id})
		return
	var action: String = _event_action(data)
	if step == "deploy" and kind == "deploy_queued":
		_advance(_event_proof(kind, data))
	elif step == "aim" and kind == "naval_aimed":
		_advance(_event_proof(kind, data))
	elif step == "return" and kind == "return_ordered":
		_advance(_event_proof(kind, data))
	elif step == "extract" and kind == "extract_ordered":
		_pending = _event_proof(kind, data)
	elif (step in ["move", "attack", "search"] and kind == "unit_ordered" and action == step) or (step == "support" and kind == "naval_support_queued") or (step == "withdraw" and kind == "withdraw_ordered"):
		_pending = _event_proof(kind, data)
		_pending["tick"] = float(_view.get("tick", 0))
		_pending["frame"] = int(_view.get("littoral", {}).get("frame", -1))
		_pending["origin"] = _position(_group())
		_pending["ship"] = data.get("ship", data.get("ship_id", data.get("response", {}).get("ship", -1)))
		_pending["world"] = data.get("world", {})
		_pending["previous_shots"] = _view.get("littoral", {}).get("shots", []).map(func(shot: Dictionary) -> String: return str(shot.get("id", "")))
		_refresh()
	# Consume only the state that the controller has already observed.
	if not _view.is_empty():
		observe_state(_view)

func observe_focus(focus: String) -> void:
	_focus = focus
	if not active or _finished or _needs_revalidation:
		return
	var step: String = current_step()
	if (step in ["focus_land", "focus_land_support"] and focus == "land") or (step in ["focus_sea", "focus_sea_return"] and focus == "sea"):
		_advance({"source":"current_ui_state", "kind":"already_focused", "focus":focus})

func _event_action(data: Dictionary) -> String:
	var response: Dictionary = data.get("response", {}) if data.get("response", {}) is Dictionary else {}
	var command: Dictionary = data.get("command", {}) if data.get("command", {}) is Dictionary else {}
	return str(data.get("action", command.get("action", response.get("action", data.get("op", "")))))

func _event_proof(kind: String, data: Dictionary) -> Dictionary:
	return {"source":"interaction", "kind":kind, "event_id":str(data.get("event_id", "")), "unit_id":unit_id, "target_id":data.get("target_id", data.get("target", "")), "op":str(data.get("op", ""))}

func observe_state(public_view: Dictionary) -> void:
	_view = public_view.duplicate(true)
	if not active or _finished:
		return
	var littoral: Dictionary = _view.get("littoral", {})
	if littoral.is_empty():
		return
	var groups: Array = littoral.get("groups", [])
	if groups.is_empty():
		return
	if _group().is_empty():
		unit_id = str(groups[0].get("id", ""))
	var group: Dictionary = _group()
	var stage: String = str(group.get("stage", "embarked"))
	if _needs_revalidation:
		_needs_revalidation = false
		# Resume by current mechanics. UI checkpoint/proofs alone cannot skip lessons.
		if _successful_outcome():
			_set_step("extract")
		elif stage == "recovered" and _fleet_at_exit():
			_set_step("extract")
		elif stage in ["returning", "recovered"]:
			_set_step("recover")
		elif stage == "ground":
			_set_step("focus_land")
		elif stage == "transit":
			_set_step("land")
		elif _has_pending_deploy(group):
			_set_step("approach")
		else:
			_set_step("deploy")
	var step: String = current_step()
	if step == "attack" and _shore_cleared():
		_advance(_state_proof("enemy_already_cleared"))
		_context_hint = "岸上威胁已清除，点小地图切回海图"
		_refresh()
		step = current_step()
	if step in ["aim", "support"] and _naval_unavailable():
		_advance(_state_proof("naval_unavailable"))
		_context_hint = "舰炮没有可用弹药，切回陆图继续搜索" if current_step() == "focus_land_support" else "舰炮暂不可用，把部队卡拖到遗迹"
		_refresh()
		step = current_step()
	if step == "search" and (_all_ruins_searched() or _search_objective_complete()):
		_advance(_state_proof("already_searched"))
		_context_hint = "遗迹已搜完，把撤收卡拖到部队"
		_refresh()
		step = current_step()
	if step == "deploy" and _has_pending_deploy(group):
		_advance(_state_proof("pending_deploy"))
		step = current_step()
	if step == "approach" and stage in ["transit", "ground"]:
		_advance(_state_proof("transport_launched"))
		step = current_step()
	if step == "land" and stage == "ground":
		_advance(_state_proof("landed"))
	elif step == "move" and not _pending.is_empty() and stage == "ground":
		if _position(group).distance_to(_pending.get("origin", _position(group))) >= 4.0:
			_advance(_state_proof("unit_moved"))
	elif step == "attack" and not _pending.is_empty() and stage == "ground" and str(group.get("order", "")) == "attack":
		_advance(_state_proof("attack_order_confirmed"))
	elif step == "support" and not _pending.is_empty():
		for shot: Dictionary in littoral.get("shots", []):
			var source: String = str(shot.get("source", ""))
			var ship: int = int(_pending.get("ship", -1))
			var unseen: bool = not _pending.get("previous_shots", []).has(str(shot.get("id", "")))
			if unseen and str(shot.get("kind", "")) == "naval" and _shot_matches_target(shot) and source.begins_with("ship:") and (ship < 0 or source == "ship:%d" % ship) and float(shot.get("tick", -1)) >= float(_pending.tick):
				_advance(_state_proof("naval_shot_fired"))
				break
	elif step == "search" and not _pending.is_empty():
		for ruin: Dictionary in littoral.get("land", {}).get("ruins", []):
			var target: String = str(_pending.get("target_id", ""))
			if bool(ruin.get("searched", false)) and (target.is_empty() or target == str(ruin.get("id", ""))):
				_advance(_state_proof("ruin_searched"))
				break
	elif step == "withdraw" and not _pending.is_empty() and (stage in ["returning", "recovered"] or str(group.get("order", "")) == "retreat"):
		_advance(_state_proof("withdraw_order_confirmed"))
		if stage == "recovered":
			_finish_if_recovered()
	elif step == "recover" and stage == "recovered":
		_finish_if_recovered()
	elif step == "return" and _fleet_at_exit():
		_advance(_state_proof("fleet_already_at_exit"))
		_advance(_state_proof("fleet_arrived"))
	elif step == "sail_home" and _fleet_at_exit():
		_advance(_state_proof("fleet_arrived"))
	elif step == "extract" and _successful_outcome():
		_advance(_state_proof("successful_core_outcome"))
	# Focus is real UI state, so a resumed lesson need not switch away and back.
	if not _focus.is_empty():
		observe_focus(_focus)

func _finish_if_recovered() -> void:
	# Returning, inactive and lost are intentionally not success states.
	if str(_group().get("stage", "")) != "recovered":
		return
	for group: Dictionary in _view.get("littoral", {}).get("groups", []):
		if float(group.get("hp_percent", 100)) > 0 and not str(group.get("stage", "")) in ["embarked", "recovered"]:
			_context_hint = "还有部队在岸上，先用撤收卡接回她们"
			_refresh()
			return
	var searched: bool = false
	for ruin: Dictionary in _view.get("littoral", {}).get("land", {}).get("ruins", []):
		searched = searched or bool(ruin.get("searched", false))
	if searched:
		_advance(_state_proof("unit_recovered"))

func _shore_cleared() -> bool:
	var land: Dictionary = _view.get("littoral", {}).get("land", {})
	if not land.has("entities") or not land.has("buildings"):
		return false
	for row: Dictionary in land.entities + land.buildings:
		if str(row.get("side", "")) in ["axis", "hostile", "enemy"] and float(row.get("hp", 0)) > 0:
			return false
	return str(_group().get("stage", "")) == "ground"

func _all_ruins_searched() -> bool:
	var ruins: Array = _view.get("littoral", {}).get("land", {}).get("ruins", [])
	return not ruins.is_empty() and ruins.all(func(ruin: Dictionary) -> bool: return bool(ruin.get("searched", false)))

func _search_objective_complete() -> bool:
	for objective: Dictionary in _view.get("littoral", {}).get("objectives", []):
		if str(objective.get("kind", "")) == "search_ruin" and bool(objective.get("complete", false)):
			for ruin: Dictionary in _view.get("littoral", {}).get("land", {}).get("ruins", []):
				if bool(ruin.get("searched", false)):
					return true
	return false

func _naval_unavailable() -> bool:
	var naval: Variant = _view.get("littoral", {}).get("support", {}).get("naval")
	if not naval is Array or not _view.has("ships"):
		return false
	for ship: Dictionary in _view.ships:
		if float(ship.get("hp", 0)) <= 0 or not bool(ship.get("gun", false)):
			continue
		for gun: Dictionary in naval:
			if int(gun.get("ship", -1)) == int(ship.get("id", -2)) and int(gun.get("ammo", 0)) > 0:
				return false
	return true

func _fleet_at_exit() -> bool:
	var exit: Dictionary = _view.get("littoral", {}).get("exit", {})
	if not exit.has("radius") or not _view.has("ships"):
		return false
	var center := Vector2(float(exit.get("x", 0)), float(exit.get("y", 0)))
	var radius: float = float(exit.radius)
	var alive: int = 0
	for ship: Dictionary in _view.ships:
		if float(ship.get("hp", 0)) <= 0:
			continue
		alive += 1
		if center.distance_to(Vector2(float(ship.get("x", 0)), float(ship.get("y", 0)))) > radius:
			return false
	for group: Dictionary in _view.get("littoral", {}).get("groups", []):
		if float(group.get("hp_percent", 100)) > 0 and not str(group.get("stage", "")) in ["embarked", "recovered"]:
			return false
	return alive > 0 and radius > 0

func _successful_outcome() -> bool:
	var outcome: Variant = _view.get("littoral", {}).get("outcome")
	return outcome is Dictionary and bool(outcome.get("success", false)) and not bool(outcome.get("abandoned", false))

func _position(group: Dictionary) -> Vector2:
	var point: Variant = group.get("position", {})
	if point is Vector2:
		return point
	if point is Dictionary:
		return Vector2(float(point.get("x", 0)), float(point.get("y", 0)))
	return Vector2.ZERO

func _has_pending_deploy(group: Dictionary) -> bool:
	var pending: Variant = group.get("pending_deploy", {})
	return pending is Dictionary and not pending.is_empty()

func _shot_matches_target(shot: Dictionary) -> bool:
	var world: Variant = _pending.get("world", {})
	var point: Vector2
	if world is Vector2:
		point = world
	elif world is Dictionary and world.has("x") and world.has("y"):
		point = Vector2(float(world.x), float(world.y))
	else:
		return true
	return point.distance_to(Vector2(float(shot.get("target_x", 0)), float(shot.get("target_y", 0)))) < 2.0

func _group() -> Dictionary:
	for group: Dictionary in _view.get("littoral", {}).get("groups", []):
		if str(group.get("id", "")) == unit_id:
			return group
	return {}

func _state_proof(kind: String) -> Dictionary:
	return {"source":"public_core", "kind":kind, "unit_id":unit_id, "stage":str(_group().get("stage", "")), "tick":_view.get("tick", 0), "frame":_view.get("littoral", {}).get("frame", 0)}

func _advance(proof: Dictionary) -> void:
	if _finished:
		return
	var step: String = current_step()
	_proofs[step] = proof.duplicate(true)
	action_complete.emit(step, proof.duplicate(true))
	_pending.clear()
	if _index == _steps().size()-1:
		_finished = true
		active = false
		visible = false
		set_process(false)
		progress_changed.emit(snapshot_progress())
		if not _review_only:
			completed.emit()
		return
	_index += 1
	_gesture = 0
	_context_hint = ""
	_refresh()
	step_changed.emit(current_step(), _index)
	progress_changed.emit(snapshot_progress())

func _set_step(id: String) -> void:
	for index: int in _steps().size():
		if str(_steps()[index].id) == id:
			_index = index
			break
	_pending.clear()
	_refresh()
	step_changed.emit(current_step(), _index)

func _refresh() -> void:
	if _instruction != null:
		var text: String = _context_hint if not _context_hint.is_empty() else instruction_text()
		if not _pending.is_empty():
			text = str({"move":"部队正在向落点移动", "attack":"部队正在接敌", "support":"等待舰炮装填并实际开火", "search":"部队正在搜索遗迹", "withdraw":"部队正在撤向接驳点"}.get(current_step(), text))
		_instruction.text = text
	queue_redraw()

func _process(delta: float) -> void:
	_gesture = fmod(_gesture+delta, gesture_seconds)
	queue_redraw()

func target_rect(key: String) -> Rect2:
	if not _targets.has(key):
		return Rect2()
	var inverse: Transform2D = get_global_transform_with_canvas().affine_inverse()
	var local: Rect2 = inverse * (_targets[key] as Rect2)
	return local.intersection(Rect2(Vector2.ZERO, size))

func _holes() -> Array[Rect2]:
	var holes: Array[Rect2] = []
	var step: Dictionary = _steps()[_index]
	for key: String in [str(step.get("from", "")), str(step.get("to", ""))]:
		var rect: Rect2 = target_rect(key)
		if rect.has_area():
			holes.append(rect.grow(9).intersection(Rect2(Vector2.ZERO, size)))
	return holes

func _draw() -> void:
	if not active or _finished:
		return
	var holes: Array[Rect2] = _holes()
	# Partition the mask around the union of holes. No stacked alpha or input shield.
	var xs: Array[float] = [0.0, size.x]
	var ys: Array[float] = [0.0, size.y]
	for hole: Rect2 in holes:
		xs.append(hole.position.x)
		xs.append(hole.end.x)
		ys.append(hole.position.y)
		ys.append(hole.end.y)
	xs.sort()
	ys.sort()
	for x: int in xs.size()-1:
		for y: int in ys.size()-1:
			var cell := Rect2(Vector2(xs[x], ys[y]), Vector2(xs[x+1]-xs[x], ys[y+1]-ys[y]))
			var in_hole: bool = false
			for hole: Rect2 in holes:
				in_hole = in_hole or hole.has_point(cell.get_center())
			if not in_hole and cell.has_area():
				draw_rect(cell, Color(.02, .08, .11, dim_strength))
	var pulse: float = 1.0 if reduced_motion else .75+.25*sin(_gesture*TAU/gesture_seconds)
	for hole: Rect2 in holes:
		draw_rect(hole, Color(1, .88, .56, pulse), false, 3.0)
	var step: Dictionary = _steps()[_index]
	var from: Rect2 = target_rect(str(step.get("from", "")))
	var to: Rect2 = target_rect(str(step.get("to", "")))
	if not to.has_area() or not _pending.is_empty():
		return
	if from.has_area():
		var begin: Vector2 = from.get_center()
		var end: Vector2 = to.get_center()
		var vector: Vector2 = end-begin
		if vector.length() > 2:
			var direction: Vector2 = vector.normalized()
			draw_dashed_line(begin, end, Color(1, .95, .76, .75), 2.0, 10.0)
			draw_polyline(PackedVector2Array([end-direction.rotated(.55)*14, end, end-direction.rotated(-.55)*14]), Color("ffe7aa"), 3.0, true)
		var phase: float = .48 if reduced_motion else smoothstep(.16, .78, _gesture/gesture_seconds)
		_draw_hand(begin.lerp(end, phase), phase > .03 and phase < .99)
	elif bool(step.get("tap", false)):
		var center: Vector2 = to.get_center()
		draw_arc(center, 23+5*pulse, 0, TAU, 32, Color(1, .9, .63, .8), 2.0, true)
		_draw_hand(center, false)

func _draw_hand(point: Vector2, grabbing: bool) -> void:
	var ink := Color("fff8dc")
	var shadow := Color(.08, .16, .2, .75)
	var palm: Vector2 = point+Vector2(9, 21)
	for offset: Vector2 in [Vector2(2, 3), Vector2.ZERO]:
		var color: Color = shadow if offset != Vector2.ZERO else ink
		draw_circle(palm+offset, 11 if grabbing else 12, color)
		draw_line(point+Vector2(3, 22)+offset, point+offset, color, 9.0, true)
		draw_line(palm+Vector2(-3, 2)+offset, palm+Vector2(-13, -6)+offset, color, 8.0, true)
