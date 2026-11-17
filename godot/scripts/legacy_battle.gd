extends RefCounted
## Original CAS command-desk workflow, adapted to native Controls and the same JSON authority.
const BattleMap = preload("res://scripts/battle_map.gd")
const Design = preload("res://scripts/ui_design.gd")
const Art = preload("res://scripts/character_art.gd")
const INK := Design.INK
const MUTED := Design.MUTED
const GOLD := Design.ACCENT
var app
var tab := "fleet"
var fleet_id := 0
var ship_id := 0
var target_id := ""
var route_mode := "follow"
var cruise := 15.0
var preview: Dictionary = {}
var reform: Dictionary = {}
var suggestion: Dictionary = {}
var torpedo: Dictionary = {}
var collapsed := true
var hud
const QuietHud = preload("res://scripts/battle_hud.gd")
const FeedbackScene=preload("res://scenes/ui/battle_feedback.tscn")
var feedback
var body: VBoxContainer
var scroll: ScrollContainer
var sidebar: Panel
var tabs: HBoxContainer
var state_label: Label
var sidebar_toggle: Button
var clock_label: Label
var signal_label: Label
var replay_label: Label
var replay_slider: HSlider
var replay_mode := false
var archive_replay := false
var replay_save := ""
var replay_tick := 0
var replay_limit := 0
var last_live_view: Dictionary = {}
var replay_back_running := false
var refresh_lock := false

func _init(owner) -> void:
	app = owner

func _clock(tick: int) -> String:
	return "%02d:%02d" % [tick / 60, tick % 60]

func _fleet() -> Dictionary:
	for fleet in app.core.view.get("fleets", []):
		if int(fleet.id) == fleet_id:
			return fleet
	var rows: Array = app.core.view.get("fleets", [])
	if not rows.is_empty():
		fleet_id = int(rows[0].id)
		return rows[0]
	return {}

func _ship() -> Dictionary:
	for ship in app.core.view.get("ships", []):
		if int(ship.id) == ship_id:
			return ship
	var fleet := _fleet()
	var leader: int = int(fleet.get("leader", 0))
	for ship in app.core.view.get("ships", []):
		if int(ship.id) == leader:
			ship_id = leader
			return ship
	return {}

func _closed() -> bool:
	return replay_mode or app.core.view.get("result") != null or bool(app.core.view.get("settling", false)) or _ai_ally(int(_fleet().get("id",0)))

func _ai_ally(id:int)->bool:
	var arena:Dictionary=app.core.view.get("arena",{})
	if arena.is_empty():return false
	return not arena.get("player_fleets",[]).any(func(value):return int(value)==id)

func _label(text: String, size := 20, color := INK) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", clampi(size, 18, 28))
	label.add_theme_font_override("font", Design.font(600 if size >= 24 else 400))
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(label)
	return label

func _button(text: String, callback: Callable, disabled := false, reason := "") -> Button:
	var button: Button = app.button(app.page, text, 0, 0, 1, 1, callback)
	app.page.remove_child(button)
	body.add_child(button)
	button.custom_minimum_size = Vector2(0, 42)
	button.add_theme_font_size_override("font_size", 20)
	button.disabled = disabled
	button.tooltip_text = reason
	if disabled and not reason.is_empty():
		_label(reason, 16, MUTED)
	return button

func _choice(title: String, labels: Array, values: Array, current: Variant, callback: Callable, disabled := false) -> OptionButton:
	_label(title, 18, MUTED)
	var option := OptionButton.new()
	option.custom_minimum_size.y = 40
	option.add_theme_font_size_override("font_size", 20)
	for i in range(labels.size()):
		option.add_item(str(labels[i]))
		if str(values[i]) == str(current):
			option.select(i)
	option.disabled = disabled
	option.item_selected.connect(func(index: int): callback.call(values[index]))
	body.add_child(option)
	return option

func _section(title: String) -> void:
	var space := HSeparator.new()
	body.add_child(space)
	_label(title, 24, INK)

func create_map()->Control:
	return BattleMap.new()

func build() -> void:
	hud = QuietHud.new(self)
	hud.build()
	feedback=FeedbackScene.instantiate()
	app.page.add_child(feedback)
	feedback.bind(app.sea)
	feedback.configure_motion(app.battle_motion_strength)
	signal_label.hide()
	update()

func toggle_sidebar() -> void:
	hud.set_drawer(collapsed)
	rebuild()

func open_pause_menu() -> void:
	if app.get("home_exercise_session")!=null and app.home_exercise_session.active and app.battle_controller!=self:
		app.battle_controller.open_pause_menu();return
	app.running = false
	if app.audio != null:
		app.audio.set_paused(true)
	record_signal("paused")
	update()
	var layer: Control = app.open_modal("航行暂停")
	hud.action(layer, "继续行动", 405, 255, 790, 70, func(): app.close_modal(); app.toggle_pause(), true)
	hud.action(layer, "保存进度", 405, 350, 370, 62, export_save).disabled = replay_mode
	hud.action(layer, "保存暂离", 825, 350, 370, 62, func(): app.close_modal(); app.save_leave()).disabled = replay_mode
	hud.action(layer, "战情记录", 405, 440, 370, 62, func(): app.close_modal(); show_tab("log"))
	hud.action(layer, "视图设置", 825, 440, 370, 62, hud.view_menu)
	var arena_mode:bool=app.core.view.has("arena")
	hud.action(layer, "认输并结算" if arena_mode else "结束行动", 405, 560, 790, 62, func(): app.confirm_action("认输会扣除竞技积分，本次没有对局奖励。确定认输？" if arena_mode else "结束行动会失去未撤出的货物。确定结束？", app.abandon)).disabled = replay_mode
	var home:Button=hud.action(layer,"保存并返回母港" if not replay_mode else "返回母港",405,650,790,52,app.go_home)
	home.name="NavigateHome"

func close_context() -> void:
	app.selection_kind = ""
	app.selected = {}
	app.sea.intel_contact = ""
	hud.refresh()

func show_tab(next: String) -> void:
	hud.set_drawer(true)
	if next != tab:
		scroll.scroll_vertical = 0
	if next == "log":
		record_signal("reportViewed")
	tab = next
	rebuild()

func one_step() -> void:
	app.running = false
	var before := int(app.core.view.get("tick", 0))
	if replay_mode:
		seek(replay_tick + 1)
	else:
		var response: Dictionary = app.issue({"op": "step", "seconds": 1})
		if response.get("ok", false) and int(app.core.view.get("tick", 0)) == before + 1:
			record_signal("stepped")
			rebuild()
		if app.core.view.get("result") != null:
			app.finish_battle()

func add_point(point: Vector2) -> void:
	if _closed():
		app.notify({"ok": false, "message": "回放或终局不能修改航路。"})
		return
	if app.sea.planned.size() >= 10:
		app.notify({"ok": false, "message": "最多10个航点，请先下达当前草稿。"})
		return
	app.sea.planned.append(point)
	refresh_preview()

func refresh_preview() -> void:
	if app.sea.planned.is_empty():
		preview = {}
	else:
		var points: Array = []
		for point in app.sea.planned:
			points.append({"x": point.x, "y": point.y})
		var response: Dictionary = app.core.request({"op": "preview_route", "fleet": int(_fleet().get("id", 0)), "mode": route_mode, "speed": cruise, "points": points})
		preview = response.get("data", {}) if response.get("ok", false) else {"valid": false, "error": response.get("error", "航线不可用")}
	app.sea.preview = preview
	if preview.get("valid", false):
		record_signal("syncPreview" if route_mode == "sync" else "followPreview")
	app.sea.queue_redraw()
	rebuild()

func choose_route(mode: String) -> void:
	route_mode = mode
	app.sea.editing = true
	refresh_preview()
	app.notify({"message": "点击海图添加航点；拖动已画航点可修改，确认前不改变舰队命令。"})

func cancel_draft(record_user := true) -> void:
	if record_user and not app.sea.planned.is_empty():
		record_signal("draftCancelled")
	app.sea.planned.clear()
	app.sea.editing = false
	preview = {}
	reform = {}
	app.sea.preview = {}
	app.sea.reform_preview = {}
	app.sea.queue_redraw()
	rebuild()

func commit_route() -> void:
	if not preview.get("valid", false):
		app.notify({"ok": false, "message": preview.get("error", "先选择机动方式并在海图添加航点。")})
		return
	var points: Array = []
	for point in app.sea.planned:
		points.append({"x": point.x, "y": point.y})
	var response: Dictionary = app.issue({"op": "route", "fleet": fleet_id, "mode": route_mode, "speed": cruise, "points": points})
	if response.get("ok", false):
		cancel_draft(false)

func select(kind: String, object: Dictionary) -> void:
	app.selection_kind = kind
	app.selected = object
	# The retained firing target is distinct from explicitly opening monster intelligence.
	app.sea.intel_contact = str(object.get("id", "")) if kind=="contact" else ""
	if kind == "ship":
		ship_id = int(object.id)
		fleet_id = int(object.get("fleet", fleet_id))
		app.sea.selected_ship = ship_id
		tab = "ship"
	elif kind == "contact":
		if str(object.id).begins_with("R"):
			if object.get("usableForShipIds", []).has(ship_id):
				record_signal("radarContactViewed")
		else:
			record_signal("contactViewed")
		target_id = str(object.id)
		app.sea.selected_contact = target_id
		app.sea.queue_redraw()
		tab = "ship"
	else:
		tab = "fleet"
	app.sea.readonly = _closed()
	rebuild()

func update() -> void:
	if not is_instance_valid(app.sea):
		return
	app.sea.view = app.core.view
	app.sea.projectile_rate = float(app.speed) if app.running else 0.0
	app.sea.projectile_readonly = replay_mode
	app.sea.projectile_epoch = app.core.observation_epoch
	app.sea.selected_contact = target_id
	app.sea.readonly = _closed()
	app.sea.selected_ship = int(_ship().get("id", 0))
	app.sea.draft_leader = int(_fleet().get("leader", app.sea.selected_ship))
	app.sea.torpedo_settings = torpedo
	app.sea.queue_redraw()
	var tick := int(app.core.view.get("tick", 0))
	clock_label.text = _clock(tick)
	clock_label.tooltip_text = "行动时限 " + _clock(int(app.core.view.get("limit", 0)))
	app.pause_button.text = "暂停" if app.running else "开始"
	state_label.text = "只读复盘" if replay_mode else "" if app.running else "已暂停"
	var events: Array = app.core.view.get("events", [])
	signal_label.text = recent_alert(events, tick)
	if is_instance_valid(feedback):
		feedback.configure_motion(app.battle_motion_strength)
		feedback.observe(app.core.view,replay_mode)
	if hud != null:
		hud.refresh()
	var service = app.get("progression")
	if service != null and not replay_mode and not _exercise_active():
		service.observe(app.core.view)
	if app.audio != null:
		app.audio.ingest_events(events, app.core.view.get("ships", []), app.core.view.get("contacts", []), not replay_mode, tick)
	rebuild()

func recent_alert(events: Array, tick: int) -> String:
	var alert := ""
	var priority := 0
	for event in events:
		if tick - int(event.get("tick", 0)) > 12:
			continue
		var kind := str(event.get("kind", ""))
		var cue := str(event.get("voiceCue", event.get("voice_cue", "")))
		var importance := 4 if kind == "torpedo_detected" or cue.begins_with("torpedo_warning") else 3 if kind == "critical" else 2 if kind in ["damage", "fire", "flood", "exposed"] else 1 if kind == "contact" else 0
		if importance > 0 and importance >= priority:
			priority = importance
			alert = str(event.get("text", ""))
	return alert

func rebuild() -> void:
	if hud != null:
		hud.refresh()
	if not is_instance_valid(body) or refresh_lock:
		return
	# Keep an open selector or text edit usable while the simulation advances.
	for child in body.get_children():
		if child is OptionButton and child.get_popup().visible:
			return
	var focus: Control = app.get_viewport().gui_get_focus_owner()
	if focus is LineEdit and body.is_ancestor_of(focus):
		return
	refresh_lock = true
	for i in range(tabs.get_child_count()):
		var button: Button = tabs.get_child(i)
		var selected: bool = ["fleet", "ship", "ai", "log"][i] == tab
		button.add_theme_font_override("font", Design.font(600 if selected else 400))
		button.add_theme_color_override("font_color", INK if selected else MUTED)
		for state in ["normal", "hover", "pressed", "focus"]:
			var style := Design.box(Color(1,1,1,0) if state == "normal" else Color("dceef2"), 0)
			style.content_margin_left = 4
			style.content_margin_right = 4
			style.border_color = GOLD
			style.border_width_bottom = 3 if selected else (1 if state == "focus" else 0)
			button.add_theme_stylebox_override(state, style)
	var position := scroll.scroll_vertical
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	if replay_mode:
		_label("只读回放", 23, GOLD)
		_label("%s / %s" % [_clock(replay_tick), _clock(replay_limit)], 18, MUTED)
		replay_slider = HSlider.new()
		replay_slider.max_value = replay_limit
		replay_slider.step = 1
		replay_slider.value = replay_tick
		body.add_child(replay_slider)
		_button("定位回放", func(): seek(int(replay_slider.value)))
		_button("结束回放", end_replay)
	render_course()
	if app.selection_kind == "ruin":
		_section("残骸 %d" % int(app.selected.get("id", 0)))
		_label("靠近750米且航速不高于8节后，可连续搜索。", 18, MUTED)
		if app.core.view.get("salvage",{}).has("cargo_grid"):
			_button("搜索物资", func(): app.issue({"op": "search_salvage", "ruin": int(app.selected.id)}), _closed())
			_button("打开货舱 · 拖入装载", app.cargo_manifest)
		else:
			_button("打捞残骸", func(): app.issue({"op": "salvage_collect", "ruin": int(app.selected.id)}), _closed())
	elif app.selection_kind == "exit":
		_section("撤离点 %d" % (int(app.selected.get("index", 0)) + 1))
		_label("所有仍可航行舰须进入标出的集结区域。" if app.selected.get("bounds") is Dictionary else "所有仍可航行舰必须进入同一1000米范围。", 18, MUTED)
		_button("开始撤离", func(): app.issue({"op": "salvage_extract", "exit": int(app.selected.index)}), _closed())
	var salvage: Dictionary = app.core.view.get("salvage", {})
	if not salvage.is_empty():
		_label("货舱 %d/%d   威胁 %d" % [salvage.get("cargo", []).size(), int(salvage.get("capacity", 0)), int(salvage.get("threat", 1))], 19, MUTED)
		for key in ["collecting", "extracting"]:
			if salvage.get(key) is Dictionary:
				_label("%s %d / %d秒" % ["搜索" if key == "collecting" else "撤离", int(salvage[key].get("progress", 0)), int(salvage[key].get("duration", 0))], 20, GOLD)
		_button("航次货舱", app.cargo_manifest)
	match tab:
		"fleet": render_fleet()
		"ship": render_ship()
		"ai": render_ai()
		"log": render_log()
	scroll.set_deferred("scroll_vertical", position)
	refresh_lock = false

func render_fleet() -> void:
	var fleets: Array = app.core.view.get("fleets", [])
	var names: Array = []
	var ids: Array = []
	for fleet in fleets:
		names.append(str(fleet.name)+(" · AI队友" if _ai_ally(int(fleet.id)) else ""))
		ids.append(int(fleet.id))
	var fleet := _fleet()
	if fleet.is_empty():
		_label("当前没有可指挥编队。")
		return
	_choice("选择编队", names, ids, fleet_id, func(value): fleet_id = int(value); ship_id = int(_fleet().leader); cancel_draft(false))
	_label("%s   %d艘在队" % [str(fleet.name), fleet.get("members", []).size()], 25, GOLD)
	if _ai_ally(int(fleet.id)):_label("AI队友独立指挥 · 可查看舰况",18,MUTED)
	_label("当前 %.1f节   可用上限 %.1f节" % [float(fleet.get("actual", 0)), float(fleet.get("maxSpeed", 0))], 18, MUTED)
	var speed_value:=Label.new()
	body.add_child(speed_value)
	var speed_box := HSlider.new()
	speed_box.custom_minimum_size=Vector2(220,32)
	speed_box.min_value = 0
	speed_box.max_value = float(fleet.get("maxSpeed", 60))
	speed_box.step = 1
	speed_box.value = cruise
	body.add_child(speed_box)
	speed_value.text="巡航 %d / %d 节"%[int(cruise),int(speed_box.max_value)]
	speed_box.value_changed.connect(func(value): cruise = value;speed_value.text="巡航 %d / %d 节"%[int(value),int(speed_box.max_value)])
	_button("调整编队航速", func(): app.issue({"op": "speed", "fleet": fleet_id, "speed": cruise}), _closed())
	if fleet.get("notice") != null:
		_label(str(fleet.notice), 18, Color("e4a185"))
	_section("编队航线")
	_button("领舰移动", func(): choose_route("follow"), _closed())
	_button("同步移动", func(): choose_route("sync"), _closed())
	_label("%d个途经点 · %s" % [app.sea.planned.size(), "航线可用" if preview.get("valid", false) else "未提交草稿"], 18, GOLD)
	if preview.has("error"):
		_label(str(preview.error), 18, Color("e4a185"))
	_button("撤销一点", func(): app.sea.planned.pop_back(); refresh_preview(), app.sea.planned.is_empty())
	_button("取消草稿", cancel_draft)
	_button("下达航线", commit_route, not preview.get("valid", false) or _closed())
	_button("预览重整纵队", preview_reform, _closed())
	if not reform.is_empty():
		_label(str(reform.get("error", "重整航路可用")), 18, MUTED)
		_button("下达重整", func(): app.issue({"op": "reform", "fleet": fleet_id}); cancel_draft(false), not reform.get("valid", false) or _closed())
	_button("脱离接触", func(): app.issue({"op": "resume", "fleet": fleet_id}), _closed())
	_section("编队舰艇")
	for ship in app.core.view.get("ships", []):
		if int(ship.get("fleet", 0)) != fleet_id:
			continue
		var selected: Dictionary = ship
		_button("%s%s  %.0f%%" % [str(ship.name), " · 领舰" if int(ship.id) == int(fleet.leader) else "", float(ship.hp) / maxf(1, float(ship.maxHp)) * 100], func(): select("ship", selected))

func preview_reform() -> void:
	var response: Dictionary = app.core.request({"op": "preview_reform", "fleet": fleet_id})
	reform = response.get("data", {}) if response.get("ok", false) else {"valid": false, "error": response.get("error", "无法重整")}
	app.sea.reform_preview = reform
	app.sea.queue_redraw()
	rebuild()

func render_ship() -> void:
	var ship := _ship()
	if ship.is_empty():
		_label("本席没有可查看的可航舰艇。")
		return
	var names: Array = []
	var ids: Array = []
	for own in app.core.view.get("ships", []):
		names.append(str(own.name)+(" · AI队友" if _ai_ally(int(own.get("fleet",0))) else ""))
		ids.append(int(own.id))
	_choice("查看舰艇", names, ids, ship_id, func(value): ship_id = int(value);fleet_id=int(_ship().get("fleet",fleet_id));app.sea.selected_ship = ship_id;app.sea.readonly=_closed();rebuild())
	if not ship.get("systems", {}).get("radars", []).is_empty():
		_button("查看舰上雷达", radar_dialog)
	_label("舰体耐久 %.1f / %.1f DP" % [float(ship.hp), float(ship.maxHp)], 18, MUTED)
	var hp := ProgressBar.new()
	hp.max_value = float(ship.maxHp)
	hp.value = float(ship.hp)
	hp.show_percentage = false
	hp.custom_minimum_size.y = 9
	body.add_child(hp)
	var overview := HBoxContainer.new()
	body.add_child(overview)
	var resolved:=Art.resolve(app.cards,ship)
	var card:Dictionary=resolved.card
	var representative:bool=resolved.representative
	var portrait := TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(120, 220)
	if not str(card.get("portrait", "")).is_empty():
		portrait.texture = load(str(card.portrait))
	overview.add_child(portrait)
	var schematic := HullDiagram.new()
	schematic.ship = ship
	schematic.custom_minimum_size = Vector2(188, 220)
	overview.add_child(schematic)
	if representative:
		_label("舰型代表立绘 · " + str(card.get("name", "")), 16, MUTED)
	elif card.is_empty():
		_label("该舰无匹配立绘，保留舰体示意。", 16, MUTED)
	_label("舰体俯视 · 北向上   航向%03d°" % (int(round(float(ship.heading))) % 360), 17, MUTED)
	_label("位置 %.0f, %.0f   现速 %.1f节" % [float(ship.x), float(ship.y), float(ship.speed)], 17, MUTED)
	var systems: Dictionary = ship.get("systems", {})
	var expedition_munitions: Dictionary = ship.get("expedition_munitions",{})
	_section("主炮状态")
	if not expedition_munitions.is_empty():
		_label("选用弹种 · "+str({"balanced":"通用弹","ap":"穿甲弹","he":"高爆弹"}.get(str(expedition_munitions.get("shell","")),"—")),17,GOLD)
	if ship.get("gunTarget") != null:
		_label("待发目标 %s · 命中率 %.0f%%" % [str(ship.gunTarget), float(ship.get("targetChance", 0))], 18, GOLD)
		_button("取消待发炮击", func(): app.issue({"op": "gun_cancel", "ship": ship_id}), _closed())
	var tick := int(app.core.view.get("tick", 0))
	for gun in systems.get("guns", []):
		var remaining := maxi(0, int(gun.get("readyTick", tick)) - tick)
		var state := "损毁" if gun.get("destroyed", false) else "转炮" if gun.get("training", false) else "装填%d秒" % remaining if remaining > 0 else "就绪"
		_label("炮座%d  %d门  %s   %s" % [int(gun.index) + 1, int(gun.barrels), state, "%03d°" % int(round(float(gun.bearing))) if gun.get("bearing") != null else "—"], 18, MUTED)
	_section("鱼雷管")
	if not systems.get("tubes",[]).is_empty():
		var immediate:bool=str(app.core.view.get("version",""))=="cas-realtime-v10"
		_label("即时发射 · 射界未到会持续瞄准" if immediate else "旧版时序 · 沿用本航次保存版本",17,GOLD)
	if not expedition_munitions.is_empty():
		_label("鱼雷 · %s   总备雷%d枚" % [str({"standard":"标准型","fast":"高速型","heavy":"重型"}.get(str(expedition_munitions.get("torpedo","")),"—")),int(expedition_munitions.get("torpedo_reserve",0))],17,GOLD)
	var tubes: Array = systems.get("tubes", [])
	for tube in tubes:
		var mounts: Array=expedition_munitions.get("mounts",[])
		if int(tube.index)<mounts.size():
			var mount: Dictionary=mounts[int(tube.index)]
			var countdown:=int(mount.get("ready_in",0))
			_label("雷座%d  余%d/%d  备雷%d · %s" % [int(tube.index)+1,int(mount.get("loaded",0)),int(tube.tubes),int(mount.get("reserve",0)),"装填 %d秒" % countdown if countdown>0 else "就绪"],18,MUTED)
		else:
			var reload:int=maxi(0,int(tube.get("reloadingUntil",tick))-tick) if tube.get("reloadingUntil")!=null else 0
			_label("雷座%d  余%d/%d  备雷%d · %s" % [int(tube.index) + 1, int(tube.get("remaining", 0)), int(tube.tubes), int(tube.get("reserve", 0)), "装填%d秒"%reload if reload>0 else "就绪" if int(tube.get("remaining",0))>0 else "无备弹"], 18, MUTED)
	if tubes.is_empty():
		_label("本舰未装鱼雷管。", 18, MUTED)
	if app.core.view.get("torpedoDepths", false) and not tubes.is_empty():
		var settings: Dictionary = torpedo.get(ship_id, {})
		_choice("鱼雷定深", ["浅航", "深航"], ["shallow", "deep"], settings.get("depth", "shallow"), func(value): set_torpedo("depth", value), _closed())
		_choice("齐射数量", ["单座全发", "1枚", "2枚", "3枚", "4枚", "5枚", "6枚"], [0, 1, 2, 3, 4, 5, 6], settings.get("count", 0), func(value): set_torpedo("count", value), _closed())
	_section("分系统")
	_label("火控 %s  动力受损%d级\n火灾%d处  进水%d处\n可用航速上限 %.1f节 · 余雷%d枚" % ["受损" if systems.get("directorDamaged", false) else "正常", int(systems.get("engineeringLevels", 0)), int(systems.get("fires", 0)), int(systems.get("floods", 0)), float(systems.get("maxSpeed", 0)), int(ship.get("ammo", 0))], 18, MUTED)
	if systems.has("torpedoProtection"):
		var protection: Dictionary = systems.torpedoProtection
		_label("左舷水下防护 %.0f/%.0f\n右舷水下防护 %.0f/%.0f" % [float(protection.port), float(protection.capacity), float(protection.starboard), float(protection.capacity)], 18, MUTED)
	_button("设为领舰", func(): app.issue({"op": "lead", "fleet": int(ship.get("fleet", fleet_id)), "ship": ship_id}), _closed())
	_button("脱队", func(): app.issue({"op": "detach", "fleet": int(ship.get("fleet", fleet_id)), "ship": ship_id}), _closed())
	render_target_tools(ship)

func set_torpedo(key: String, value: Variant) -> void:
	var settings: Dictionary = torpedo.get(ship_id, {}).duplicate()
	if key == "count" and int(value) == 0:
		settings.erase(key)
	else:
		settings[key] = value
	torpedo[ship_id] = settings
	app.sea.torpedo_settings = torpedo

func render_target_tools(ship: Dictionary) -> void:
	_section("武器与夜战")
	var labels: Array = ["选择接触"]
	var values: Array = [""]
	for contact in app.core.view.get("contacts", []):
		labels.append(str(contact.get("name") if contact.get("name") != null else contact.id))
		values.append(str(contact.id))
	for radar in app.core.view.get("radarContacts", []):
		labels.append("雷达 " + str(radar.id))
		values.append(str(radar.id))
	_choice("本席可知目标", labels, values, target_id, func(value): target_id = str(value); app.sea.selected_contact = target_id; app.sea.queue_redraw(); rebuild())
	for weapon in ["gun", "torpedo"]:
		var aim: Dictionary = {}
		if not target_id.is_empty():
			var request := {"op": "aim", "ship": ship_id, "weapon": weapon, "target": target_id}
			if weapon == "torpedo":
				request.merge(torpedo.get(ship_id, {}), true)
			var response: Dictionary = app.core.request(request)
			aim = response.get("data", {}) if response.get("ok", false) else {"valid": false, "error": response.get("error", "不可用")}
		var command: Dictionary = {"op": "fire", "ship": ship_id, "target": target_id, "weapon": weapon}
		if weapon == "torpedo":
			command.merge(torpedo.get(ship_id, {}), true)
		var reason: Variant = aim.get("error")
		_button("持续炮击" if weapon == "gun" else "鱼雷攻击", func(): app.issue(command), _closed() or not aim.get("valid", false), "先选择有效接触。" if target_id.is_empty() else str(reason) if reason != null else "")
	if str(ship.get("kind", "")) == "dd":
		_button("停止施放" if ship.get("smoking", false) else "施放烟幕", func(): app.issue({"op": "smoke", "ship": ship_id, "on": not ship.get("smoking", false)}), _closed())
	_section("舰上雷达")
	var radars: Array = ship.get("systems", {}).get("radars", [])
	if radars.is_empty():
		_label("本舰未提供可操作雷达。", 18, MUTED)
	for radar in radars:
		var set: Dictionary = radar
		_button("%s · %s" % [str(set.name), "失能" if set.get("disabled", false) else "开启" if set.get("powered", false) else "关闭"], func(): app.issue({"op": "radar_set", "ship": ship_id, "radar": str(set.id), "powered": not set.get("powered", false)}), _closed() or set.get("disabled", false), "设备失能，不能操作。" if set.get("disabled", false) else "")
	var night: bool = app.core.view.get("environment", {}).get("light", "day") == "night"
	var light: Dictionary = {}
	if night and not target_id.is_empty():
		var response: Dictionary = app.core.request({"op": "illumination_preview", "ship": ship_id, "target": target_id})
		light = response.get("data", {}) if response.get("ok", false) else {"valid": false, "error": response.get("error", "不可用")}
	var light_reason: Variant = light.get("error")
	_button("下达照明弹", func(): app.issue({"op": "illuminate", "ship": ship_id, "target": target_id}), _closed() or not light.get("valid", false), "当前不是夜战。" if not night else str(light_reason) if light_reason != null else "先选择可照明接触。" if not light.get("valid", false) else "")
	_button("关闭探照灯" if ship.get("searchlight") is Dictionary else "开启探照灯", func(): app.issue({"op": "searchlight", "ship": ship_id, "on": not ship.get("searchlight") is Dictionary, "target": target_id}), _closed() or not night or target_id.is_empty(), "探照灯需要夜间有效目视接触。" if not night or target_id.is_empty() else "")

func render_ai() -> void:
	var fleet := _fleet()
	if fleet.is_empty():
		_label("无可指挥编队。")
		return
	_section("战术指挥官")
	var config: Dictionary = fleet.get("ai", {})
	var profiles: Array = ["coord", "gunnery", "torpedo", "evo-screen", "evo-torpedo", "evo-gunnery", "evo-brawler", "evo-kiter", "evo-denial"]
	var labels: Array = ["协同", "炮战", "雷击", "帷幄 · 屏护", "夜潮 · 雷击", "铁幕 · 炮战", "绞肉 · 近战", "拖刀 · 远距", "雷网 · 封走位"]
	var available: Array = ["coord"]
	var service = app.get("progression")
	if service != null and service.has_method("available_ai_profiles"):
		available = service.available_ai_profiles()
	var choices := _choice("AI风格", labels, profiles, config.get("profile", "coord"), func(value): change_ai("profile", value), _closed())
	for i in range(profiles.size()):
		if not available.has(profiles[i]) and str(config.get("profile", "")) != str(profiles[i]):
			choices.set_item_disabled(i, true)
			choices.set_item_text(i, str(labels[i]) + "（未拥有）")
	_choice("指挥权限", ["手动", "仅建议", "选择托管项"], ["manual", "suggest", "auto"], config.get("mode", "manual"), func(value): change_ai("mode", value), _closed())
	for i in range(3):
		var key: String = ["move", "gun", "torpedo"][i]
		var checkbox := CheckBox.new()
		checkbox.text = ["编队机动", "炮击", "雷击"][i]
		checkbox.button_pressed = bool(config.get(key, false))
		checkbox.disabled = _closed()
		checkbox.toggled.connect(func(value): change_ai(key, value))
		body.add_child(checkbox)
	_label("手动下令会接管该项；勾选可交还AI。未拥有的风格保持锁定。", 17, MUTED)
	_button("查看战术建议", ask_ai, _closed())
	if not suggestion.is_empty():
		_label(str(suggestion.get("text", "")), 18, MUTED)
		for order in suggestion.get("orders", []):
			var verb := str({"route": "调整航路", "speed": "调整航速", "fire": "雷击" if order.get("weapon") == "torpedo" else "炮击", "smoke": "施放烟幕", "resume": "脱离接触"}.get(str(order.get("op", "")), "执行战术指令"))
			_label(verb, 18, MUTED)
		_button("采纳建议", func():
			for order in suggestion.get("orders", []):
				app.issue(order)
			suggestion = {}
			rebuild(), suggestion.get("orders", []).is_empty() or _closed())

func change_ai(key: String, value: Variant) -> void:
	var config: Dictionary = _fleet().get("ai", {}).duplicate()
	config[key] = value
	config.merge({"op": "ai", "fleet": fleet_id}, true)
	app.issue(config)

func ask_ai() -> void:
	var response: Dictionary = app.core.request({"op": "suggest", "fleet": fleet_id})
	suggestion = response.get("data", {}) if response.get("ok", false) else {"text": response.get("error", "无可用建议"), "orders": []}
	rebuild()

func render_log() -> void:
	_section("战情记录 · 本席可见")
	_button("导出战报", export_report)
	_button("重演战局", begin_replay, replay_mode or int(app.core.view.get("tick", 0)) == 0, "先推进战局，再进行只读重演。" if int(app.core.view.get("tick", 0)) == 0 else "")
	var events: Array = app.core.view.get("events", [])
	for event in events.slice(maxi(0, events.size() - 180)):
		_label("%s  %s" % [_clock(int(event.get("tick", 0))), str(event.get("text", ""))], 18, MUTED)
		if event.get("rule") != null:
			_label(str(event.rule), 14, Color("79949e"))

func export_report() -> void:
	var response: Dictionary = {"ok": true, "data": {"result": app.core.view.get("result"), "events": app.core.view.get("events", []), "tick": app.core.view.get("tick", 0), "replay": true}} if replay_mode else app.core.request({"op": "report"})
	if not response.get("ok", false):
		app.notify(response)
		return
	var folder := "user://battle-reports"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var path := folder.path_join("CAS-%d.json" % Time.get_ticks_msec())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		app.notify({"ok": false, "message": "无法写入本机战报目录。"})
		return
	file.store_string(JSON.stringify(response.data, "\t"))
	file.close()
	app.notify({"message": "战报已保存：" + ProjectSettings.globalize_path(path)})

func export_save() -> void:
	if _exercise_active():app.notify({"message":"演习为独立推演，原行动保持不变。"});return
	if replay_mode:
		app.notify({"ok": false, "message": "回放不覆盖当前进度。"})
		return
	if not app.checkpoint():
		return
	var response: Dictionary = app.core.request({"op": "save", "serialized": true})
	if not response.get("ok", false):
		app.notify(response)
		return
	var file := FileAccess.open("user://battle-progress.json", FileAccess.WRITE)
	if file != null:
		file.store_string(str(response.serialized))
		file.close()
		app.notify({"message": "本机进度已保存。"})

func begin_replay() -> void:
	if replay_mode:
		return
	app.checkpoint()
	var saved: Dictionary = app.core.request({"op": "save", "serialized": true})
	if not saved.get("ok", false):
		app.notify(saved)
		return
	replay_save = str(saved.serialized)
	last_live_view = app.core.view.duplicate(true)
	replay_limit = int(app.core.view.get("tick", 0))
	replay_back_running = app.running
	app.running = false
	replay_mode = true
	seek(0)

func seek(tick: int) -> void:
	if not replay_mode:
		return
	replay_tick = clampi(tick, 0, replay_limit)
	var response: Dictionary = app.core.request({"op": "replay", "serialized": replay_save, "tick": replay_tick})
	if not response.get("ok", false):
		app.notify(response)
		return
	update()

func advance_replay(seconds: int) -> void:
	seek(replay_tick + seconds)
	if replay_tick >= replay_limit:
		app.running = false

func end_replay() -> void:
	if not replay_mode:
		return
	replay_mode = false
	if archive_replay:
		app.running = false
		app.show_page("archives")
		return
	app.core.request({"op": "observe"})
	app.running = false
	app.sea.cancel_pending()
	update()

class HullDiagram extends Control:
	var ship: Dictionary = {}
	func _draw() -> void:
		var center := size * 0.5
		var heading := deg_to_rad(float(ship.get("heading", 0)))
		var shape := PackedVector2Array()
		for point in [Vector2(0, -90), Vector2(13, -56), Vector2(17, 40), Vector2(8, 87), Vector2(-8, 87), Vector2(-17, 40), Vector2(-13, -56)]:
			shape.append(center + point.rotated(heading))
		draw_colored_polygon(shape, Color("173c48"))
		draw_polyline(shape, Color("9eb7ae"), 1.2, true)
		var guns: Array = ship.get("systems", {}).get("guns", [])
		for i in range(guns.size()):
			var gun: Dictionary = guns[i]
			var offset := Vector2(0, -60 + float(i) / maxf(1, guns.size() - 1) * 120).rotated(heading)
			var point := center + offset
			var angle: float = deg_to_rad(float(gun.get("bearing") if gun.get("bearing") != null else ship.get("heading", 0)))
			var color := Color("cf7c67") if gun.get("destroyed", false) else Color("e0ca8a")
			draw_circle(point, 6, Color("264c58"))
			draw_arc(point, 6, 0, TAU, 16, color, 1, true)
			if not gun.get("destroyed", false):
				draw_line(point, point + Vector2(sin(angle), -cos(angle)) * 18, color, 3, true)
		if int(ship.get("systems", {}).get("fires", 0)) > 0:
			draw_circle(center, 5, Color("e49b71"))
		if int(ship.get("systems", {}).get("floods", 0)) > 0:
			draw_circle(center + Vector2(0, 14), 5, Color("7bc5d5"))


func record_signal(name: String) -> void:
	var service = app.get("progression")
	if service != null and not replay_mode and not _exercise_active():
		service.record_signal(name)

func _exercise_active()->bool:
	return app.get("home_exercise_session")!=null and app.home_exercise_session.active

func render_course() -> void:
	var context: Dictionary = app.economy.state.get("active_run", {}).get("context", {})
	var course: String = str(context.get("course_id", ""))
	var service = app.get("progression")
	if course.is_empty() or service == null or replay_mode or _exercise_active():
		return
	var status: Dictionary = service.course_status(course)
	_section("实操 %d / %d" % [int(status.get("done", 0)), int(status.get("total", 0))])
	var current: Dictionary = status.get("current", {})
	_label(str(current.get("title", "本段实操已完成")), 22, GOLD)
	_label(str(current.get("instruction", "核对实操记录后可进入下一段。")), 18, MUTED)
	_button("完成本段实操", app.finish_battle, not status.get("complete", false), "请按当前提示完成真实操作。" if not status.get("complete", false) else "")

func radar_dialog() -> void:
	record_signal("radarViewed")
	var ship := _ship()
	var layer: Control = app.open_modal("舰上雷达 · " + str(ship.get("name", "")))
	var panel_body := VBoxContainer.new()
	panel_body.add_theme_constant_override("separation", 15)
	app.place(panel_body, layer, 387, 250, 822, 350)
	var previous := body
	body = panel_body
	for radar in ship.get("systems", {}).get("radars", []):
		var set: Dictionary = radar
		_label(str(set.name), 27, GOLD)
		_label("当前%s。直接雷达回波与友舰共享位置按本舰设备权限使用。" % ("已开启" if set.get("powered", false) else "已关闭"), 20, MUTED)
		_button("关闭 " + str(set.name) if set.get("powered", false) else "开启 " + str(set.name), func(): app.close_modal(); app.issue({"op": "radar_set", "ship": ship_id, "radar": str(set.id), "powered": not set.get("powered", false)}), _closed() or set.get("disabled", false))
	body = previous
