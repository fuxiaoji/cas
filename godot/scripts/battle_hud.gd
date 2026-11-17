extends RefCounted
## Quiet default view; precise controls live in the optional tactical drawer.
const Design = preload("res://scripts/ui_design.gd")
const Art = preload("res://scripts/character_art.gd")
const INK := Design.INK
const MUTED := Design.MUTED
const PAPER := Design.PAPER
const TEAL := Design.ACCENT
const WEATHER_NAMES := {"clear":"晴", "cloudy":"多云", "overcast":"阴", "rain":"雨", "fog":"雾"}
var _battle: WeakRef
var battle:
	get: return _battle.get_ref()
var app
var fleet_strip: HBoxContainer
var fleet_scroll:ScrollContainer
var map_controls:Array[Control]=[]
var fleet_signature := ""
var fleet_cards: Dictionary = {}
var context: Control
var context_signature := ""
var objective: Label
var warning: Label
var speed_button: Button
var tactical_button: Button
var tools: Control
var drawer_close: Button
var weather_status: Control
var weather_label: Label
var weather_image: TextureRect
var weather_icons: Dictionary = {}
var range_button: Button

func _init(controller) -> void:
	_battle = weakref(controller)
	app = battle.app

func pane(parent: Control, x: float, y: float, w: float, h: float) -> Panel:
	var node: Panel = app.panel(parent, x, y, w, h, Color(PAPER, 0.95))
	node.add_theme_stylebox_override("panel", Design.panel_style())
	return node

func action(parent: Control, text: String, x: float, y: float, w: float, h: float, callback: Callable, primary := false) -> Button:
	var button: Button = app.button(parent, text, x, y, w, h, callback, primary)
	Design.apply_button(button, primary)
	button.add_theme_font_size_override("font_size", 20)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box: StyleBoxFlat = button.get_theme_stylebox(state).duplicate()
		box.content_margin_left = 6
		box.content_margin_right = 6
		button.add_theme_stylebox_override(state, box)
	return button

func _scene_title() -> String:
	var campaign:Variant=app.core.view.get("campaign",{})
	if campaign is Dictionary and not str(campaign.get("missionLabel","")).is_empty():return str(campaign.missionLabel)
	if not str(app.run.get("title","")).is_empty():return str(app.run.title)
	var salvage:Variant=app.core.view.get("salvage",{})
	if salvage is Dictionary and salvage.has("difficulty"):
		return str({"calm":"近海巡航","standard":"交锋航路","hazard":"深渊禁区"}.get(str(salvage.difficulty),"打捞远征"))
	return str(app.core.view.get("scenario","海上行动"))

func build() -> void:
	# A full world viewport never jumps or rescales when a drawer opens.
	app.sea = battle.create_map()
	app.place(app.sea, app.page, 0, 0, 1600, 900)
	app.sea.cards = app.cards
	app.sea.chibis = app.ship_mode
	app.sea.inspect_command = func(request: Dictionary): return app.core.request(request)
	app.sea.point_selected.connect(battle.add_point)
	app.sea.object_selected.connect(app.select_object)
	app.sea.draft_changed.connect(battle.refresh_preview)
	app.sea.weapon_order.connect(app.issue)
	app.sea.interaction_hint.connect(func(text: String): app.notify({"message": text}))
	app.sea.training_signal.connect(battle.record_signal)
	app.sea.aim_state_changed.connect(func(active: bool): context.visible = not active)
	app.sea.selection_cleared.connect(battle.close_context)
	action(app.page, "", 26, 24, 340, 76, func(): battle.show_tab("fleet")).tooltip_text = "任务与行动详情"
	var scene_title:String=_scene_title()
	var scene_label:Label=app.label(app.page,scene_title,44,29,303,30,20,INK)
	scene_label.name="BattleSceneTitle"
	scene_label.max_lines_visible=1
	scene_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	scene_label.tooltip_text=scene_title
	objective = app.label(app.page, "", 44, 59, 303, 30, 20, MUTED)
	objective.max_lines_visible = 1
	objective.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	weather_status = Control.new()
	app.place(weather_status, app.page, 28, 112, 146, 42)
	weather_status.mouse_filter = Control.MOUSE_FILTER_PASS
	pane(weather_status, 0, 0, 1600, 900).mouse_filter = Control.MOUSE_FILTER_IGNORE
	weather_image = TextureRect.new()
	weather_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	weather_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	weather_image.modulate = INK
	weather_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app.place(weather_image, weather_status, 95, 145, 345, 610)
	weather_label = app.label(weather_status, "", 560, 0, 1000, 900, 20, INK)
	weather_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	weather_status.hide()
	pane(app.page, 1210, 24, 140, 56)
	battle.clock_label = app.label(app.page, "", 1228, 27, 115, 48, 25, INK)
	battle.clock_label.add_theme_font_override("font", Design.font(600))
	app.battle_status = battle.clock_label
	app.pause_button = action(app.page, "开始", 1362, 24, 80, 56, app.toggle_pause, true)
	speed_button = action(app.page, "1×", 1454, 24, 62, 56, toggle_tools)
	action(app.page, "菜单", 1528, 24, 54, 56, battle.open_pause_menu)
	battle.state_label = app.label(app.page, "", 1194, 86, 300, 26, 18, PAPER)
	battle.state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	battle.sidebar = pane(app.page, 1188, 152, 392, 592)
	battle.tabs = HBoxContainer.new()
	app.place(battle.tabs, app.page, 1201, 168, 366, 48)
	for i in range(4):
		var key: String = ["fleet", "ship", "ai", "log"][i]
		var button := action(app.page, ["编队", "舰况", "战术 AI", "战情"][i], 0, 0, 1, 1, func(): battle.show_tab(key))
		app.page.remove_child(button)
		battle.tabs.add_child(button)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 20)
	battle.scroll = ScrollContainer.new()
	battle.scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	app.place(battle.scroll, app.page, 1208, 232, 350, 490)
	battle.body = VBoxContainer.new()
	battle.body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	battle.body.add_theme_constant_override("separation", 9)
	battle.scroll.add_child(battle.body)
	app.battle_selection = battle.body
	tactical_button = action(app.page, "战术", 1490, 105, 90, 40, battle.toggle_sidebar)
	battle.sidebar_toggle = tactical_button
	tools = Control.new()
	app.place(tools, app.page, 0, 0, 1600, 900)
	tools.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane(tools, 1108, 88, 472, 58)
	action(tools, "单步", 1118, 97, 82, 40, battle.one_step)
	for i in range(5):
		var rate: int = [1, 2, 4, 8, 20][i]
		action(tools, "%d×" % rate, 1208 + i * 72, 97, 64, 40, func(): app.speed = rate; tools.hide(); battle.update())
	tools.hide()
	map_controls.append(action(app.page, "+", 28, 670, 48, 44, func(): app.sea.zoom = minf(app.sea.zoom * 1.2, 8); app.sea.queue_redraw()))
	map_controls.append(action(app.page, "−", 84, 670, 48, 44, func(): app.sea.zoom = maxf(app.sea.zoom / 1.2, 0.7); app.sea.queue_redraw()))
	map_controls.append(action(app.page, "◎", 140, 670, 48, 44, func(): app.sea.focus_fleet()))
	map_controls.back().tooltip_text = "回到舰队"
	map_controls.append(action(app.page, "视图", 200, 670, 80, 44, view_menu))
	range_button=action(app.page,"射程",290,670,86,44,toggle_ranges)
	range_button.text="射程 ✓" if app.sea.ranges_visible else "射程"
	range_button.tooltip_text="选中舰艇后显示炮击、鱼雷、目视与实际雷达范围"
	map_controls.append(range_button)
	if not app.core.view.get("salvage",{}).is_empty():
		action(app.page,"残骸搜索",388,670,124,44,salvage_search)
	fleet_scroll = ScrollContainer.new()
	fleet_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	app.place(fleet_scroll, app.page, 28, 744, 572, 138)
	fleet_strip = HBoxContainer.new()
	fleet_strip.add_theme_constant_override("separation", 8)
	fleet_scroll.add_child(fleet_strip)
	context = Control.new()
	context.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app.place(context, app.page, 624, 742, 552, 136)
	warning = app.label(app.page, "", 420, 26, 730, 54, 20, Color("fff8e8"))
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.add_theme_color_override("font_shadow_color", Color("173c50"))
	warning.add_theme_constant_override("shadow_outline_size", 6)
	battle.signal_label = warning
	app.toast_label = app.label(app.page, "", 412, 101, 730, 46, 20, Color("fff8e8"))
	app.toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	app.toast_label.add_theme_color_override("font_shadow_color", Color("173c50"))
	app.toast_label.add_theme_constant_override("shadow_outline_size", 5)
	set_drawer(false)

func configure_amphibious_layout()->void:
	# Same command desk, with room for a distinct tactical/aviation tray below it.
	app.place_reposition(fleet_scroll,28,610,572,108)
	app.place_reposition(context,624,610,552,108)
	for control in map_controls:
		control.anchor_top=552.0/900;control.anchor_bottom=596.0/900
	app.place_reposition(tactical_button,1490,350,90,48)
	app.place_reposition(battle.sidebar,1188,152,392,552)
	app.place_reposition(battle.scroll,1208,232,350,450)
	for control in [battle.sidebar,battle.tabs,battle.scroll,tactical_button]:control.z_index=30
	for row in fleet_cards.values():row.button.custom_minimum_size.y=104

func set_drawer(open: bool) -> void:
	battle.collapsed = not open
	battle.sidebar.visible = open
	battle.tabs.visible = open
	battle.scroll.visible = open
	tactical_button.text = "收起" if open else "战术"

func toggle_tools() -> void:
	tools.visible = not tools.visible

func toggle_ranges() -> void:
	app.sea.ranges_visible=not app.sea.ranges_visible
	range_button.text="射程 ✓" if app.sea.ranges_visible else "射程"
	app.sea.queue_redraw()

func salvage_search() -> void:
	var layer:Control=app.open_modal("残骸搜索")
	app.label(layer,"选择已发现的残骸；靠近并减速后，点击「打捞残骸」。",380,218,835,62,22,MUTED)
	var scroll:=ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	app.place(scroll,layer,380,304,835,340)
	var list:=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",12);scroll.add_child(list)
	var known:Array=app.core.view.get("salvage",{}).get("ruins",[])
	for row in known:
		var ruin:Dictionary=row
		var button:=action(layer,"残骸 %d%s"%[int(ruin.id)," · 已打捞" if ruin.get("collected",false) else " · 定位并选择"],0,0,1,1,func():
			app.close_modal()
			app.sea.pan+=app.sea.size*.5-app.sea.project(app.sea.pos(ruin.p))+app.sea.combat_offset
			app.select_object("ruin",ruin)
			app.sea.queue_redraw())
		layer.remove_child(button);list.add_child(button);button.custom_minimum_size=Vector2(790,60);button.disabled=bool(ruin.get("collected",false))
	if known.is_empty(): app.label(layer,"当前尚未发现残骸，向海域内航行继续搜索。",390,365,800,90,25)

func view_menu() -> void:
	var layer: Control = app.open_modal("海域视图")
	app.label(layer, "按需要展开战术标记", 396, 250, 800, 50, 25, INK)
	action(layer, "射程/雷达", 400, 340, 350, 64, func(): toggle_ranges(); app.close_modal())
	action(layer, "投影切换", 800, 340, 350, 64, func(): app.ship_mode = not app.ship_mode; app.sea.chibis = app.ship_mode; app.sea.queue_redraw(); app.persist_settings(); app.close_modal())
	action(layer, "海图网格", 400, 435, 350, 64, func(): app.sea.grid_visible = not app.sea.grid_visible; app.sea.queue_redraw(); app.close_modal())
	if app.sea.is_historical_chart():
		var map_switch: Button = action(layer, "卫星底图 / 战术海图" if app.sea.has_satellite_chart() else "战术海图（当前海域）", 800, 435, 350, 64, func(): app.sea.historical_satellite_enabled = not app.sea.historical_satellite_enabled; app.sea.queue_redraw(); app.close_modal())
		map_switch.disabled = not app.sea.has_satellite_chart()
	else:
		action(layer, "战术海图 / 航海画面", 800, 435, 350, 64, func(): app.sea.stylized_environment = not app.sea.stylized_environment; app.sea.queue_redraw(); app.close_modal())
	app.label(layer,"战斗震动",400,545,180,50,23,INK)
	app.add_combat_motion_slider(layer,600,560,550)
	app.label(layer, "滚轮缩放 · 右键拖动海图", 400, 625, 700, 50, 21, MUTED)

func refresh() -> void:
	if not is_instance_valid(context): return
	app.sea.weather_paused = not app.running
	refresh_weather()
	speed_button.text = "%d×" % int(app.speed)
	var salvage: Dictionary = app.core.view.get("salvage", {})
	speed_button.tooltip_text="时间倍率。当前冒险航行已提速10倍；怪物蓄力按游戏秒计时，建议1×观察。" if salvage.has("adventure") else "调整模拟时间倍率"
	objective.text = "搜索海域 · 选择撤离点" if not salvage.is_empty() else "观察接触 · 指挥舰队"
	if not salvage.is_empty():
		objective.text = "货舱 %d / %d" % [salvage.get("cargo", []).size(), int(salvage.get("capacity", 0))]
		for key in ["collecting", "extracting"]:
			if salvage.get(key) is Dictionary:
				objective.text = "%s  %d / %d秒" % ["搜索中" if key == "collecting" else "撤离中", int(salvage[key].get("progress", 0)), int(salvage[key].get("duration", 0))]
	var course: String = str(app.economy.state.get("active_run", {}).get("context", {}).get("course_id", ""))
	if not course.is_empty() and app.progression != null:
		var status: Dictionary = app.progression.course_status(course)
		objective.text = str(status.get("current", {}).get("title", "实操完成 · 查看战术面板"))
	var chapter:Dictionary=app.core.view.get("chapter",{})
	if not chapter.is_empty():
		var kind:String=str(chapter.get("objective",{}).get("kind",""))
		var events:Array=chapter.get("events",[])
		objective.tooltip_text={"reach_and_extract":"抵达返航信标后，全队进入同一撤离区并开始撤离。","archive_and_extract":"收回指定信标档案，再带领全队集结撤离。","defeat_boss":"集中火力击败渊喉，驶离公开的攻击预警区。"}.get(kind,"")
		objective.text={"reach_and_extract":"抵达信标 → 撤离","archive_and_extract":"回收档案 → 撤离","defeat_boss":"击败渊喉 · 避开预警"}.get(kind,"第五驱逐小队 · 突围")
		if kind=="reach_and_extract" and events.has("beacon_reached"):objective.text="信标已抵达 · 集结撤离"
		if kind=="archive_and_extract" and salvage.get("cargo",[]).has("archive"):objective.text="档案已回收 · 集结撤离"
		for key in ["collecting","extracting"]:
			if salvage.get(key) is Dictionary:objective.text="%s  %d / %d秒"%["搜索中" if key=="collecting" else "撤离中",int(salvage[key].get("progress",0)),int(salvage[key].get("duration",0))]
	refresh_fleet()
	refresh_context()

func weather_texture(kind: String) -> Texture2D:
	if weather_icons.has(kind): return weather_icons[kind]
	var shape := '<circle cx="24" cy="24" r="9"/><path d="M24 3v5 M24 40v5 M3 24h5 M40 24h5 M9 9l4 4 M35 35l4 4 M9 39l4-4 M35 13l4-4"/>'
	if kind != "clear":
		shape = '<path d="M12 33h25c10-1 10-15 0-16C34 3 13 7 13 19 1 18 0 33 12 33Z"/>'
		if kind == "rain": shape += '<path d="m15 38-2 5 m12-5-2 5 m12-5-2 5"/>'
		if kind == "fog": shape += '<path d="M7 39h32 M13 45h20"/>'
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 48 48"><g fill="none" stroke="#ffffff" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round">%s</g></svg>' % shape
	var bitmap := Image.new()
	if bitmap.load_svg_from_string(svg) != OK: return null
	weather_icons[kind] = ImageTexture.create_from_image(bitmap)
	return weather_icons[kind]

func refresh_weather() -> void:
	# Forecasts only exist for new salvage voyages; historical environments are not randomized.
	var weather: Dictionary = app.core.view.get("weather", {})
	weather_status.visible = not weather.is_empty()
	if weather.is_empty(): return
	var kind := str(weather.get("kind", ""))
	weather_label.text = str(WEATHER_NAMES.get(kind, kind))
	weather_image.texture = weather_texture(kind)
	var remaining := maxi(0, int(weather.get("phase_ends_tick", 0)) - int(app.core.view.get("tick", 0)))
	var next := str(weather.get("next", ""))
	weather_status.tooltip_text = "当前天气：%s\n能见度：%s%%\n%d秒后：%s（能见度 %s%%）" % [weather_label.text, str(weather.get("visibility", "—")), remaining, str(WEATHER_NAMES.get(next, next)), str(weather.get("next_visibility", "—"))]

func refresh_fleet() -> void:
	var ships: Array = app.core.view.get("ships", [])
	var ids: Array = []
	for ship in ships: ids.append(ship.id)
	var signature := str(ids)
	if signature != fleet_signature:
		fleet_signature = signature
		for child in fleet_strip.get_children(): child.queue_free()
		fleet_cards.clear()
		for ship in ships:
			var id := int(ship.id)
			var card := action(app.page, "", 0, 0, 1, 1, func():
				var selected: Dictionary = {}
				for row in app.core.view.get("ships", []):
					if int(row.id) == id: selected = row
				battle.select("ship", selected))
			app.page.remove_child(card)
			fleet_strip.add_child(card)
			card.custom_minimum_size = Vector2(104, 122)
			card.tooltip_text = str(ship.name)
			var resolved:=Art.resolve(app.cards,ship,false)
			var profile: Dictionary=resolved.card
			if resolved.representative:card.tooltip_text=str(ship.name)+"\n舰型代表立绘 · "+str(profile.get("name",""))
			elif Art.projection(profile).kind=="portrait_miniature":card.tooltip_text+="\n本人立绘投影 · 独立SD待制作"
			var path := str(profile.get("portrait", ""))
			if not path.is_empty() and ResourceLoader.exists(path):
				var source: Texture2D = load(path)
				var crop := AtlasTexture.new()
				crop.atlas = source
				crop.region = Rect2(Vector2(source.get_width() * 0.12, 0), Vector2(source.get_width() * 0.76, source.get_height() * 0.47))
				var face := TextureRect.new()
				face.texture = crop
				face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
				face.mouse_filter = Control.MOUSE_FILTER_IGNORE
				card.add_child(face)
				face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				face.offset_left = 4; face.offset_right = -4; face.offset_top = 4; face.offset_bottom = -34
			else:
				var emblem:=TextureRect.new()
				emblem.texture=Design.icon_texture("fleet")
				emblem.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
				emblem.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				emblem.mouse_filter=Control.MOUSE_FILTER_IGNORE
				card.add_child(emblem);emblem.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				emblem.offset_left=20;emblem.offset_right=-20;emblem.offset_top=16;emblem.offset_bottom=-42
				card.tooltip_text+="\n暂无对应角色素材 · 保留舰体显示"
			var name_label := Label.new()
			name_label.text = str(ship.name)
			name_label.add_theme_color_override("font_color", INK)
			name_label.add_theme_font_override("font", Design.font(500))
			name_label.add_theme_font_size_override("font_size", 20)
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(name_label)
			name_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
			name_label.offset_top = -32; name_label.offset_bottom = -8
			var hp := ProgressBar.new()
			hp.show_percentage = false
			hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(hp)
			hp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
			hp.offset_left = 6; hp.offset_right = -6; hp.offset_top = -7; hp.offset_bottom = -3
			var fill := StyleBoxFlat.new(); fill.bg_color = TEAL; fill.set_corner_radius_all(2)
			hp.add_theme_stylebox_override("fill", fill)
			fleet_cards[id] = {"button": card, "hp": hp}
	for ship in ships:
		if fleet_cards.has(int(ship.id)):
			var item: Dictionary = fleet_cards[int(ship.id)]
			item.hp.max_value = maxf(1, float(ship.maxHp)); item.hp.value = float(ship.hp)
			item.button.modulate = Color.WHITE if int(ship.id) == battle.ship_id else Color(0.88, 0.94, 0.95)

func refresh_context() -> void:
	# Controls remain stable between observation ticks; rebuild only on actual selection changes.
	if app.selection_kind=="ruin":
		for ruin in app.core.view.get("salvage",{}).get("ruins",[]):
			if int(ruin.id)==int(app.selected.get("id",-1)): app.selected=ruin.duplicate(true)
	var signature := str([app.selection_kind, battle.ship_id, battle.target_id, app.selected, app.sea.planned, battle.preview, battle.replay_mode, app.sea.editing, battle._ship().get("hp", 0)])
	if signature == context_signature: return
	context_signature = signature
	for child in context.get_children(): context.remove_child(child); child.queue_free()
	if app.selection_kind.is_empty() and app.sea.planned.is_empty(): return
	pane(context, 0, 0, 1600, 900)
	var title := str(battle._ship().get("name", "舰队"))
	if not app.sea.planned.is_empty() or app.sea.editing:
		title = "%s · %d个航点" % ["领舰航路" if battle.route_mode == "follow" else "同步航路", app.sea.planned.size()]
		app.label(context, title, 55, 15, 1400, 240, 23, INK)
		var route_hint:=str(battle.preview.get("error", "航路可用" if battle.preview.get("valid", false) else "点击海面添加航点"))
		if battle.route_mode=="sync" and battle.preview.has("executionChance"):
			route_hint="同步执行 %.2f%% · 失败保持原航线"%(float(battle.preview.executionChance)*100.0)
			var ready:=int(battle.preview.get("executionReadyTick",0))-int(app.core.view.get("tick",0))
			if ready>0: route_hint+=" · %d秒后重试"%ready
		app.label(context,route_hint,55,265,1450,160,20,MUTED)
		action(context, "撤销一点", 55, 480, 430, 300, func(): app.sea.planned.pop_back(); battle.refresh_preview()).disabled = app.sea.planned.is_empty()
		action(context, "取消草稿", 535, 480, 430, 300, battle.cancel_draft)
		action(context, "下达航线", 1015, 480, 530, 300, battle.commit_route, true).disabled = not battle.preview.get("valid", false) or battle._closed()
		return
	if app.selection_kind == "ruin" or app.selection_kind == "exit":
		var ruin: bool = app.selection_kind == "ruin"
		var collected:bool=ruin and bool(app.selected.get("collected",false))
		app.label(context, "沉船残骸" if ruin else "归航水域", 55, 15, 1400, 240, 24, INK)
		app.label(context, "靠近后搜索战利品" if ruin else "集结舰队后开始撤离", 55, 270, 1400, 180, 20, MUTED)
		action(context, ("已打捞" if collected else "打捞残骸") if ruin else "开始撤离", 55, 490, 900, 300, func(): app.issue({"op": "salvage_collect", "ruin": int(app.selected.id)} if ruin else {"op": "salvage_extract", "exit": int(app.selected.index)}), true).disabled = battle._closed() or collected
		action(context, "航次货舱", 1015, 490, 530, 300, app.cargo_manifest)
		return
	app.label(context, title, 55, 15, 920, 260, 24, INK)
	var ship: Dictionary = battle._ship()
	var hp := float(ship.get("hp", 0)) / maxf(1, float(ship.get("maxHp", 1))) * 100
	app.label(context, "耐久 %.0f%%" % hp, 1040, 35, 500, 210, 20, MUTED)
	app.label(context, "拖动舰旁炮 / 雷标记瞄准", 55, 275, 1440, 170, 20, MUTED)
	for i in range(4):
		var key: String = ["follow", "sync", "ship", "ai"][i]
		action(context, ["领舰移动", "同步移动", "舰况", "战术 AI"][i], 55 + i * 380, 500, 350, 280, func(): battle.choose_route(key) if key in ["follow", "sync"] else battle.show_tab(key), i == 0)
