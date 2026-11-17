extends RefCounted
const Art = preload("res://scripts/character_art.gd")
## Native version of DeploymentScreen / TaskForceBuilder. All positions and prices
## come from campaign_fleet, and new_campaign still validates the complete plan.
const GOLD := Color("208b94")
const PAPER := Color("173c50")
const MUTED := Color("647f87")
var app
var entry: Dictionary
var stage := ""
var difficulty := "story"
var side := "allies"
var fleet: Dictionary = {}
var picks: Array = []
var ships_at: Dictionary = {}
var mode := "history"
var owned_practice := false
var profile := "coord"
var store: Dictionary = {"version": 1, "drafts": {}, "presets": []}
var store_path := ""
var store_writable := true
var notice := ""
var failure := ""
var slot := -1
var position := -1
var filter_kind := "all"
var term := ""
var sorting := "points"
var pending: Dictionary = {}
var candidate_list: GridContainer
var picker_layer: Control
var preset_name: LineEdit
var preset_picker: OptionButton
var candidates: Array = []

static func open(owner, row: Dictionary) -> void:
	var controller = load("res://scripts/campaign_deployment.gd").new()
	owner.set_meta("campaign_deployment", controller)
	controller.initialize(owner, row)

func initialize(owner, row: Dictionary) -> void:
	app = owner
	entry = row.duplicate(true)
	side = str(app.get_meta("campaign_side", "allies"))
	difficulty = str(app.get_meta("campaign_difficulty", "story"))
	for id in row.get("stage_ids", []):
		if str(id).begins_with("CAMP-" + side.to_upper() + "-"):
			stage = str(id)
	store_path = app.economy.save_path + ".deployment.json"
	_load_store()
	if not app.economy.state.get("active_run", {}).is_empty():
		failure = "已有海上航次，请先继续或明确结束。"
	elif not row.get("playable", false) or stage.is_empty():
		failure = "该本席想定尚未核验可玩，不能编成或出航。"
	else:
		var response: Dictionary = app.core.request({"op": "campaign_fleet", "id": stage, "difficulty": difficulty})
		if response.get("ok", false):
			fleet = response.data
		else:
			failure = str(response.get("error", "原核未开放本关编成。"))
	profile = str(app.progression.selected_profile())
	reset_history(false)
	var draft: Dictionary = store.drafts.get(_key(), {})
	if _usable(draft):
		picks = draft.picks.duplicate()
		if _profiles().has(str(draft.get("profile", "coord"))): profile = str(draft.profile)
		ships_at = draft.get("groups", {}).duplicate(true)
	_make_candidates()
	render()

func _key() -> String:
	return stage + ":" + difficulty

func _load_store() -> void:
	for suffix in ["", ".bak"]:
		if not FileAccess.file_exists(store_path + suffix): continue
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(store_path + suffix))
		if raw is Dictionary and int(raw.get("version", 0)) == 1 and raw.get("drafts") is Dictionary and raw.get("presets") is Array:
			store = raw
			return
	if FileAccess.file_exists(store_path):
		store_writable = false
		notice = "编成记录无法读取，原文件已保留；本次不会自动覆盖。"

func _save_store() -> bool:
	if not store_writable: return false
	var absolute := ProjectSettings.globalize_path(store_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(store_path + ".tmp", FileAccess.WRITE)
	if file == null:
		notice = "无法保存编成记录，当前草稿仍可出航。"
		return false
	file.store_string(JSON.stringify(store, "\t"))
	file.close()
	if FileAccess.file_exists(store_path):
		if FileAccess.file_exists(store_path + ".bak") and DirAccess.remove_absolute(absolute + ".bak") != OK: return false
		if DirAccess.rename_absolute(absolute, absolute + ".bak") != OK: return false
	var error := DirAccess.rename_absolute(absolute + ".tmp", absolute)
	if error != OK:
		if FileAccess.file_exists(store_path + ".bak"): DirAccess.rename_absolute(absolute + ".bak", absolute)
		notice = "编成记录写入失败，旧记录已保留。"
	return error == OK

func _profiles() -> Array:
	var rows: Array = app.progression.available_ai_profiles()
	return rows if not rows.is_empty() else ["coord"]

func _usable(row: Dictionary) -> bool:
	if not row.get("picks") is Array or row.picks.size() != fleet.get("historical", []).size(): return false
	var known := {}
	for item in fleet.get("historical", []):
		known[str(item.class)] = true
		if item.get("identity") != null: known[str(item.identity)] = true
	for item in fleet.get("options", []): known[str(item.id)] = true
	for pick in row.picks:
		if not known.has(str(pick)): return false
	return true

func _draft() -> void:
	store.drafts[_key()] = {"picks": picks.duplicate(), "groups": ships_at.duplicate(true), "profile": profile, "updatedAt": Time.get_unix_time_from_system()}
	_save_store()

func reset_history(persist := true) -> void:
	picks.clear()
	for row in fleet.get("historical", []): picks.append(str(row.identity) if row.get("identity") != null else str(row.class))
	if persist:
		_draft()
		notice = "已恢复全部历史舰位、身份与顺序。"
		render()

func _make_candidates() -> void:
	candidates.clear()
	var historical_points := {}
	for row in fleet.get("historical", []):
		if row.get("identity") != null: historical_points[str(row.identity)] = int(row.points)
		candidates.append({"key": "hist:" + str(row.slot), "pick": str(row.identity) if row.get("identity") != null else str(row.class), "class": str(row.class), "name": str(row.name), "kind": str(row.kind), "points": int(row.points), "historical": true, "identity": row.get("identity")})
	for row in fleet.get("options", []):
		candidates.append({"key": "opt:" + str(row.id), "pick": str(row.id), "class": str(row.class), "name": str(row.name), "kind": str(row.kind), "points": int(historical_points.get(str(row.id), row.points)), "historical": false, "identity": str(row.id)})

func card(pick: String) -> Dictionary:
	# Prefer the scenario period row; same-class identities remain independent.
	for row in candidates:
		if str(row.pick) == pick: return row
	for row in fleet.get("historical", []):
		if str(row.class) == pick:
			return {"pick":pick,"name":str(row.name),"kind":str(row.kind),"class":pick,"points":int(row.points),"identity":row.get("identity"),"historical":true}
	return {}

func slot_card(index: int) -> Dictionary:
	var row: Dictionary = fleet.historical[index]
	if str(picks[index]) == str(row.class) or (row.get("identity") != null and str(picks[index]) == str(row.identity)):
		return {"pick":picks[index],"name":row.name,"kind":row.kind,"class":row.class,"points":int(row.points),"identity":row.get("identity"),"historical":true}
	return card(str(picks[index]))

func total() -> int:
	var sum := 0
	if mode == "history":
		for i in range(picks.size()): sum += int(slot_card(i).get("points", 0))
	else:
		for rows in ships_at.values():
			for pick in rows: sum += int(card(str(pick)).get("points", 0))
	return sum

func groups() -> Array:
	var rows: Array = []
	for anchor in fleet.get("positions", []):
		var list: Array = ships_at.get(str(int(anchor.position)), [])
		if not list.is_empty(): rows.append({"position": int(anchor.position), "ships": list.duplicate()})
	return rows

func selected_identities() -> Array:
	if mode == "history": return picks.duplicate()
	var identities: Array = []
	for group in groups(): identities.append_array(group.ships)
	return identities

func owned_issue() -> String:
	if not owned_practice: return ""
	if difficulty != "story": return "自有舰演练仅在故事难度开放。"
	var seen: Dictionary = {}
	var missing: Array[String] = []
	var duplicate := false
	for identity in selected_identities():
		var id := str(identity)
		if seen.has(id): duplicate = true
		seen[id] = true
		if not app.economy.state.owned.has(id): missing.append(str(card(id).get("name", id)))
	if not missing.is_empty(): return "未拥有：%s%s。请更换舰娘，或用特混编成派出少量自有舰。" % [missing[0], "等%d艘" % missing.size() if missing.size() > 1 else ""]
	if duplicate: return "同一舰娘不能重复编入演练。请调整编成。"
	return ""

func _already_selected(id: String) -> bool:
	var selected := selected_identities()
	if slot >= 0 and slot < selected.size(): selected.remove_at(slot)
	return selected.has(id)

func set_owned_practice(enabled: bool) -> void:
	owned_practice = enabled and difficulty == "story"
	notice = "成长用于本次演练，历史星数独立记录。" if owned_practice else "已切回历史借用，个人成长不应用。"
	render()

func ready() -> bool:
	if not failure.is_empty() or fleet.is_empty() or total() > int(fleet.get("budget", 0)): return false
	if not owned_issue().is_empty(): return false
	if mode == "taskforce": return difficulty == "story" and fleet.get("taskForceSupported", false) and not groups().is_empty()
	return not picks.is_empty() and _usable({"picks": picks})

func _button(parent: Control, title: String, x: float, y: float, w: float, h: float, callback: Callable, disabled := false) -> Button:
	var node: Button = app.button(parent, title, x, y, w, h, callback)
	node.disabled = disabled
	node.add_theme_font_size_override("font_size", 21)
	return node

func _list(parent: Control, x: float, y: float, w: float, h: float) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	app.place(scroll, parent, x, y, w, h)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box

func _row_button(parent: Container, text: String, action: Callable, disabled := false) -> Button:
	var node := _button(app.modal, text, 0, 0, 1, 1, action, disabled)
	app.modal.remove_child(node)
	parent.add_child(node)
	node.custom_minimum_size = Vector2(0, 86)
	node.alignment = HORIZONTAL_ALIGNMENT_LEFT
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node

func render() -> void:
	app.close_modal()
	app.modal = Control.new()
	app.add_child(app.modal)
	app.modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.panel(app.modal, 0, 0, 1600, 900, Color("e6f0eb"))
	app.label(app.modal, str(entry.get("ibs_title", stage)), 50, 24, 900, 64, 38, GOLD)
	app.label(app.modal, "出击编成 · %s · %s难度" % ["同盟" if side == "allies" else "轴心", {"story":"故事","standard":"标准","challenge":"挑战"}.get(difficulty,difficulty)], 52, 84, 950, 35, 21, MUTED)
	_button(app.modal, "返回战役", 1370, 38, 180, 50, app.close_modal)
	_button(app.modal, "历史编制", 1010, 38, 160, 50, func(): mode = "history"; render())
	var taskforce := _button(app.modal, "特混编成", 1183, 38, 160, 50, func(): mode = "taskforce"; render(), difficulty != "story" or not fleet.get("taskForceSupported", false))
	taskforce.tooltip_text = "仅故事难度及已接入历史初设位置的想定可用。"
	var practice := _button(app.modal, "自有舰战役演练", 1150, 94, 410, 38, func(): set_owned_practice(not owned_practice), difficulty != "story" or fleet.is_empty())
	practice.toggle_mode = true
	practice.button_pressed = owned_practice
	practice.set_meta("owned_practice_toggle", true)
	practice.tooltip_text = "开启后只可编入已拥有舰娘，使用成长与舰装；历史阵位和敌军不变，不计历史星数。"
	app.panel(app.modal, 40, 140, 290, 711, Color("f5f6ed"))
	app.label(app.modal, "自有舰战役演练" if owned_practice else "历史阵位" if mode == "history" else "架空特混部署", 60, 162, 250, 55, 29, GOLD)
	app.label(app.modal, "原编制 %d 艘\n%d 分出航预算" % [fleet.get("historical", []).size(), int(fleet.get("budget", 0))], 62, 229, 245, 130, 23, PAPER)
	var rules := "舰艇可更换，阵位与航向保持。\n\n历史舰艇借用出航，不消耗个人物资。"
	if mode == "taskforce": rules = "选择初设位置，组建自己的编队。可留空，也可派出单舰。\n\n敌方保持历史编制。\n\n特混行动不计历史星级与首通奖励。"
	if owned_practice: rules = "使用舰娘成长与舰装。\n\n初设位置与敌军保持原样。\n\n独立演练奖励，不计历史星数。\n\n满状态演练，不扣个人物资。"
	if difficulty != "story": rules = "标准与挑战难度保持全部史实编成。逐舰替换、特混编成仅在故事难度开放。"
	app.label(app.modal, rules, 62, 378, 245, 382, 21, MUTED)
	_button(app.modal, "导入旧预设", 60, 749, 250, 43, import_dialog)
	_button(app.modal, "导出预设记录", 60, 800, 250, 38, export_presets)
	app.panel(app.modal, 350, 140, 780, 711, Color("f5f6ed"))
	app.label(app.modal, "历史舰位与顺序" if mode == "history" else "原页初设位置", 372, 156, 720, 47, 29, GOLD)
	var list := _list(app.modal, 372, 218, 735, 608)
	if not failure.is_empty():
		var error := Label.new()
		error.text = failure
		error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		error.add_theme_font_size_override("font_size", 25)
		list.add_child(error)
	elif mode == "history":
		for i in range(picks.size()):
			var index := i
			var row := slot_card(index)
			var source: Dictionary = fleet.historical[index]
			var button := _row_button(list, "%02d   %s   %s   %d分\n%s · %s" % [index + 1, str(row.get("name", picks[index])), str(row.get("kind", "")), int(row.get("points", 0)), "历史舰" if row.get("historical", false) else "替换 · 原" + str(source.name), "点击更换" if difficulty == "story" else "史实锁定"], func(): open_picker(index, -1), difficulty != "story")
			button.set_meta("deployment_slot", index)
			_portrait(button, row)
	else:
		for anchor in fleet.get("positions", []):
			var key := str(int(anchor.position))
			var header := Label.new()
			header.text = "%02d  %s  %s° / %s节\n原坐标 %s,%s · 原有%d舰" % [int(anchor.position)+1, str(anchor.name), str(anchor.course), str(anchor.speed), str(anchor.x), str(anchor.y), int(anchor.members)]
			header.add_theme_font_size_override("font_size", 21)
			list.add_child(header)
			var current: Array = ships_at.get(key, [])
			for i in range(current.size()):
				var at := i
				var position_key := key
				var item := card(str(current[i]))
				_row_button(list, "%d  %s   %d分 · 点击移除" % [at+1, str(item.get("name",current[i])), int(item.get("points",0))], func(): ships_at[position_key].remove_at(at); _draft(); render())
			var at_position := int(anchor.position)
			_row_button(list, "编入舰船 · 位置 %02d" % (at_position + 1), func(): open_picker(-1, at_position))
			if not current.is_empty(): _row_button(list, "清空位置 %02d" % (at_position + 1), func(): ships_at[str(at_position)] = []; _draft(); render())
	app.panel(app.modal, 1150, 140, 410, 711, Color("f5f6ed"))
	app.label(app.modal, "编成总分", 1174, 157, 360, 38, 23, MUTED)
	app.label(app.modal, "%d / %d" % [total(), int(fleet.get("budget", 0))], 1172, 202, 366, 66, 39, GOLD)
	app.label(app.modal, "超出预算，不能出航。" if total() > int(fleet.get("budget", 0)) else "编制可用 · 准备出航" if ready() else "请完成舰队编成", 1177, 280, 355, 45, 21, MUTED)
	var tactics := OptionButton.new()
	var profiles := _profiles()
	var profile_names:Dictionary={}
	for row in app.progression.ai_options(): profile_names[str(row.id)]=str(row.get("name","舰队战术"))
	for id in profiles: tactics.add_item(str(profile_names.get(str(id),"舰队战术")))
	tactics.selected = maxi(0, profiles.find(profile))
	app.place(tactics, app.modal, 1177, 337, 355, 43)
	tactics.item_selected.connect(func(index: int): profile = str(profiles[index]); _draft())
	app.label(app.modal, "保存常用编队", 1177, 397, 355, 35, 19, MUTED)
	preset_name = LineEdit.new()
	preset_name.placeholder_text = "预设名称"
	preset_name.add_theme_color_override("font_placeholder_color", MUTED)
	app.place(preset_name, app.modal, 1177, 441, 355, 43)
	_button(app.modal, "保存为预设", 1177, 495, 170, 45, save_preset, not ready())
	_button(app.modal, "按历史编制", 1360, 495, 170, 45, reset_history, fleet.is_empty())
	preset_picker = OptionButton.new()
	preset_picker.add_item("选择本关预设")
	preset_picker.set_item_metadata(0, "")
	for preset in store.presets:
		if str(preset.get("stageId", "")) == stage and str(preset.get("difficulty", "")) == difficulty:
			preset_picker.add_item(str(preset.name))
			preset_picker.set_item_metadata(preset_picker.item_count - 1, str(preset.id))
	app.place(preset_picker, app.modal, 1177, 554, 355, 43)
	_button(app.modal, "载入预设", 1177, 608, 112, 43, func(): load_preset(str(preset_picker.get_item_metadata(preset_picker.selected))))
	_button(app.modal, "重命名", 1300, 608, 110, 43, rename_preset)
	_button(app.modal, "删除", 1420, 608, 110, 43, delete_preset)
	app.label(app.modal, owned_issue() if not owned_issue().is_empty() else notice, 1177, 665, 355, 88, 19, MUTED)
	var sortie := _button(app.modal, "开始自有舰演练" if owned_practice else "出航作战" if mode == "history" else "特混出航", 1177, 767, 355, 60, launch, not ready())
	for state_name in ["normal", "hover", "focus", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("edcf88") if state_name == "normal" else Color("f6dfa7")
		box.set_corner_radius_all(10)
		sortie.add_theme_stylebox_override(state_name, box)

func open_picker(index: int, at_position: int) -> void:
	slot = index
	position = at_position
	filter_kind = "all"
	term = ""
	pending = {}
	picker_layer = Control.new()
	app.modal.add_child(picker_layer)
	picker_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.panel(picker_layer, 0, 0, 1600, 900, Color("edf3ec"))
	app.label(picker_layer, "更换第 %d 舰位" % (slot+1) if slot >= 0 else "编入初设位置 %d" % (position+1), 70, 33, 1100, 60, 36, GOLD)
	_button(picker_layer, "完成选舰", 1340, 40, 190, 50, close_picker)
	var search := LineEdit.new()
	search.placeholder_text = "搜索舰名或舰级"
	search.add_theme_color_override("font_placeholder_color", MUTED)
	app.place(search, picker_layer, 70, 116, 690, 47)
	search.text_changed.connect(func(value: String): term = value; render_candidates())
	var kinds := ["all", "DD", "CL", "CA", "BB"]
	for i in range(kinds.size()):
		var kind: String = kinds[i]
		_button(picker_layer, "全部" if i == 0 else kind, 780 + i*101, 116, 92, 47, func(): filter_kind = kind; render_candidates())
	var order := OptionButton.new()
	for title in ["点价降序", "舰名", "舰种"]: order.add_item(title)
	app.place(order, picker_layer, 1300, 116, 230, 47)
	order.item_selected.connect(func(i: int): sorting = ["points", "name", "kind"][i]; render_candidates())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	app.place(scroll, picker_layer, 70, 190, 1460, 585)
	candidate_list = GridContainer.new()
	candidate_list.columns = 3
	candidate_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	candidate_list.add_theme_constant_override("h_separation", 14)
	candidate_list.add_theme_constant_override("v_separation", 14)
	scroll.add_child(candidate_list)
	app.label(picker_layer, "仅显示已拥有舰娘，同一身份只能编入一次。成长生效，不计历史星数。" if owned_practice else "选择同行的舰娘。超出预算的舰艇暂不可编入。", 73, 796, 1220, 70, 21, MUTED)
	render_candidates()

func visible_candidates() -> Array:
	var rows: Array = candidates.filter(func(row: Dictionary): return (filter_kind == "all" or str(row.kind) == filter_kind) and (term.strip_edges().is_empty() or (str(row.name)+" "+str(row.class)+" "+str(row.pick)).to_lower().contains(term.strip_edges().to_lower())))
	if owned_practice: rows = rows.filter(func(row: Dictionary): return not row.historical and app.economy.state.owned.has(str(row.pick)))
	rows.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.points) > int(b.points) if sorting == "points" else str(a.name) < str(b.name) if sorting == "name" else str(a.kind) < str(b.kind))
	return rows

func render_candidates() -> void:
	for child in candidate_list.get_children():
		candidate_list.remove_child(child)
		child.queue_free()
	for row in visible_candidates():
		var candidate: Dictionary = row
		var next_total := total() + int(row.points) - (int(slot_card(slot).points) if slot >= 0 else 0)
		var duplicate: bool = owned_practice and _already_selected(str(row.pick))
		var status := "超出预算" if next_total > int(fleet.get("budget", 0)) else "已在编成" if duplicate else "自有舰 · 成长生效" if owned_practice else "历史舰" if row.historical else "可编入"
		var button := _row_button(candidate_list, "%s\n%s    %d分\n%s" % [str(row.name), str(row.kind), int(row.points), status], func(): select_candidate(candidate), next_total > int(fleet.get("budget", 0)) or duplicate)
		button.custom_minimum_size = Vector2(300, 136)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = "%s · %s" % [str(row.pick), "历史时期舰卡" if row.historical else "注册单舰"]
		button.set_meta("candidate_key", row.key)
		button.set_meta("candidate_pick", row.pick)
		_portrait(button, row)

func _portrait(button: Button, row: Dictionary) -> void:
	var resolved:=Art.resolve(app.cards,row,false)
	var profile_card:Dictionary=resolved.card
	if resolved.representative:button.tooltip_text+=" · 舰型代表立绘 "+str(profile_card.get("name",""))
	var path := str(profile_card.get("portrait", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		var source: Texture2D = load(path)
		var portrait := AtlasTexture.new()
		portrait.atlas = source
		portrait.region = Rect2(Vector2(source.get_width() * 0.16, 0), Vector2(source.get_width() * 0.68, source.get_height() * 0.42))
		button.icon = portrait
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 96)
		button.add_theme_constant_override("h_separation", 20)
	else:
		button.icon = app.Design.icon_texture("fleet")
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 48)
		button.add_theme_constant_override("h_separation", 18)
		button.tooltip_text += " · 暂无对应立绘"

func select_candidate(row: Dictionary) -> void:
	if owned_practice and (not app.economy.state.owned.has(str(row.pick)) or _already_selected(str(row.pick))):
		notice = "演练只能编入不重复的自有舰娘。"
		return
	var next_total := total() + int(row.points) - (int(slot_card(slot).points) if slot >= 0 else 0)
	if next_total > int(fleet.get("budget", 0)):
		notice = "超过历史预算，未修改编成。"
		return
	notice = ""
	if slot >= 0:
		picks[slot] = str(row.pick)
		_draft()
		close_picker()
	else:
		var key := str(position)
		ships_at.get_or_add(key, []).append(str(row.pick))
		_draft()
		render_candidates()

func close_picker() -> void:
	slot = -1
	position = -1
	render()

func save_preset() -> void:
	if not ready(): return
	var name := preset_name.text.strip_edges()
	if name.is_empty(): name = str(entry.get("ibs_title", stage)) + " · " + ("特混" if mode == "taskforce" else "历史")
	store.presets.push_front({"id":"%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_msec()],"name":name,"stageId":stage,"difficulty":difficulty,"mode":mode,"picks":picks.duplicate(),"groups":ships_at.duplicate(true),"profile":profile,"updatedAt":Time.get_unix_time_from_system()})
	if store.presets.size() > 24: store.presets.resize(24)
	if _save_store(): notice = "已保存命名预设。"
	render()

func load_preset(id: String) -> void:
	for row in store.presets:
		if str(row.get("id", "")) != id: continue
		if str(row.get("stageId", "")) != stage or str(row.get("difficulty", "")) != difficulty or not _usable(row):
			notice = "预设与当前想定编制不符，未载入。"
			render()
			return
		picks = row.picks.duplicate()
		mode = str(row.get("mode", "history"))
		ships_at = row.get("groups", {}).duplicate(true)
		profile = str(row.profile) if _profiles().has(str(row.get("profile", ""))) else "coord"
		_draft()
		notice = "已载入预设，原核出航时仍会重新验证。"
		render()
		return

func rename_preset() -> void:
	var id := str(preset_picker.get_item_metadata(preset_picker.selected))
	var name := preset_name.text.strip_edges()
	if id.is_empty() or name.is_empty():
		notice = "选择预设并输入新名称。"
	else:
		for row in store.presets:
			if str(row.id) == id: row.name = name
		_save_store()
		notice = "预设已重命名。"
	render()

func delete_preset() -> void:
	var id := str(preset_picker.get_item_metadata(preset_picker.selected))
	if not id.is_empty():
		store.presets = store.presets.filter(func(row: Dictionary): return str(row.id) != id)
		_save_store()
		notice = "预设已删除，当前编成保持。"
	render()

func import_legacy(raw: Variant) -> Dictionary:
	# Accept original FleetPreset[] and draft books keyed stage:difficulty.
	# No browser storage is silently read, and the UI never invents a migration.
	var input: Variant = JSON.parse_string(raw) if raw is String else raw
	var rows: Array = input if input is Array else input.get("presets", []) if input is Dictionary else []
	var count := 0
	for row in rows:
		if not row is Dictionary or not row.get("picks") is Array or row.get("picks", []).is_empty(): continue
		if str(row.get("stageId", "")).is_empty() or str(row.get("difficulty", "")) not in ["story","standard","challenge"]: continue
		var usable := true
		for pick in row.picks:
			if not pick is String or str(pick).is_empty(): usable = false
		if not usable: continue
		var imported: Dictionary = row.duplicate(true)
		imported.id = str(row.get("id", "legacy-%d-%d" % [Time.get_ticks_msec(), count]))
		imported.name = str(row.get("name", row.stageId))
		imported.profile = str(row.get("profile", "coord"))
		imported.mode = str(row.get("mode", "history"))
		store.presets = store.presets.filter(func(old: Dictionary): return str(old.get("id", "")) != str(imported.id))
		store.presets.push_front(imported)
		count += 1
	if input is Dictionary:
		var book: Variant = input.get("drafts", {})
		if book is Dictionary:
			for key in book:
				var row: Variant = book[key]
				if row is Dictionary and row.get("picks") is Array and not row.picks.is_empty(): store.drafts[str(key)] = row.duplicate(true)
	if store.presets.size() > 24: store.presets.resize(24)
	var saved := _save_store()
	return {"ok": saved and count > 0, "count":count,"message":"已导入%d条旧格式预设；载入及出航时仍重新核验。" % count if saved and count > 0 else "没有可导入的旧格式预设，或文件无法保存。"}

func import_dialog() -> void:
	picker_layer = Control.new()
	app.modal.add_child(picker_layer)
	picker_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.panel(picker_layer, 0, 0, 1600, 900, Color("edf3ec"))
	app.label(picker_layer, "导入旧出击预设", 80, 40, 1000, 55, 35, GOLD)
	app.label(picker_layer, "粘贴旧 FleetPreset[] JSON 或当前导出记录。保留旧 identity/class、名称、关卡和难度。不会读取浏览器其他数据。", 83, 112, 1400, 88, 23, MUTED)
	var text := TextEdit.new()
	app.place(text, picker_layer, 83, 225, 1434, 490)
	_button(picker_layer, "读取剪贴板", 83, 763, 220, 50, func(): text.text = DisplayServer.clipboard_get())
	_button(picker_layer, "确认导入预设", 1065, 763, 225, 50, func(): var result := import_legacy(text.text); notice = str(result.message); render())
	_button(picker_layer, "取消导入", 1310, 763, 207, 50, render)

func export_presets() -> void:
	var output := store_path + ".export.json"
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		notice = "无法导出编成记录。"
	else:
		file.store_string(JSON.stringify(store, "\t"))
		file.close()
		notice = "已导出至 " + ProjectSettings.globalize_path(output)
		app.notify({"message": notice})
	render()

func launch() -> void:
	if not ready(): return
	_draft()
	var request := {"op":"new_campaign","id":stage,"difficulty":difficulty,"seed":6106,"profile":profile}
	if difficulty == "story":
		if mode == "taskforce": request.groups = groups()
		else: request.fleet = picks.duplicate()
	var context := {"mode":"campaign","id":stage,"difficulty":difficulty,"side":side,"title":str(entry.get("ibs_title",stage)),"deployment":"taskforce" if mode == "taskforce" else "pointbuy" if difficulty == "story" else "historical"}
	if owned_practice:
		var prepared: Dictionary = app.economy.campaign_growth(request)
		if not prepared.get("ok", false):
			notice = str(prepared.get("message", "自有舰成长编成未通过校验。"))
			render()
			return
		request = prepared.request
		context.deployment = "owned_practice"
		context.title = "自有舰战役演练 · " + str(entry.get("ibs_title", stage))
	app.close_modal()
	app.start_local_mode(request, context)
