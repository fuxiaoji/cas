@tool
extends Control
## Displays an already committed draw. This node never calls an economy service.
signal finished
const Design = preload("res://scripts/ui_design.gd")
const TypeToken = preload("res://scripts/tactical_type_token.gd")
@export_range(1.5, 6.0, 0.1) var reveal_seconds: float = 3.6
@export var reduced_motion: bool = false
@export_file("*.png") var preview_portrait: String = "res://assets/tactical/portraits/MCP-027.png"
@export var preview_codename: String = "赤隼"
@export var preview_role: String = "gunship"
var app
var results: Array = []
var result_index: int = 0
var phase_time: float = 0.0
var phase: String = "signal"
var _art: TextureRect
var _head: TextureRect
var _name_label: Label
var _designation: Label
var _status: Label
var _progress: Label
var _token: Control
var _confirm: Button
var _skip: Button
var _gallery: GridContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 400
	_build()
	resized.connect(_layout)
	_layout()
	set_process(not Engine.is_editor_hint())
	if Engine.is_editor_hint():
		results=[{"id":"MCP-027","portrait":preview_portrait,"codename":preview_codename,"name":preview_codename,"role":preview_role,"designation":"第27海上旋翼中队","duplicate":false}]
		_show_result(true)
		phase_time = reveal_seconds
		phase = "revealed"
		_refresh()

func bind(owner, committed_results: Array) -> void:
	app = owner
	results = committed_results.duplicate(true)
	reduced_motion = bool(app.get_meta("reduced_motion", false))
	result_index = 0
	_show_result(true)

func _label(node_name: String, font_size: int, ink: Color) -> Label:
	var node := Label.new()
	node.name = node_name
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_font_override("font", Design.font(600 if font_size > 26 else 400))
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", ink)
	add_child(node)
	return node

func _button(node_name: String, title: String, callback: Callable, primary: bool = false) -> Button:
	var node := Button.new()
	node.name = node_name
	node.text = title
	Design.apply_button(node, primary)
	node.pressed.connect(callback)
	add_child(node)
	return node

func _build() -> void:
	_art = TextureRect.new()
	_art.name = "IdentityPortrait"
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	_head = TextureRect.new()
	_head.name = "IdentityCloseup"
	_head.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_head.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_head)
	_name_label = _label("IdentityName", 52, Color("fff3d7"))
	_designation = _label("IdentityDesignation", 22, Color("9cc8c9"))
	_status = _label("ResultStatus", 24, Color("e5d5ae"))
	_progress = _label("SyncProgress", 22, Color("c2e4df"))
	_token = TypeToken.new()
	_token.name = "IdentityType"
	_token.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_token)
	_button("RevealBack", "‹ 返回", _leave)
	_button("RevealHome", "母港", func() -> void:
		if app != null: app.go_home())
	_skip = _button("SkipReveal", "跳过演出", show_all)
	_confirm = _button("ConfirmReveal", "下一份协议", _next, true)
	_gallery = GridContainer.new()
	_gallery.name = "CommittedResults"
	_gallery.columns = 5
	_gallery.add_theme_constant_override("h_separation", 14)
	_gallery.add_theme_constant_override("v_separation", 20)
	add_child(_gallery)

func _layout() -> void:
	if _art == null: return
	var scale_factor: float = minf(size.x / 1600.0, size.y / 900.0)
	var design_size := Vector2(1600, 900)
	var offset: Vector2 = (size-design_size*scale_factor)*.5
	var rects: Dictionary = {
		_art:Rect2(230,100,740,750), _head:Rect2(280,70,860,790),
		_name_label:Rect2(980,350,565,92), _designation:Rect2(985,302,550,46),
		_status:Rect2(985,460,540,65), _progress:Rect2(65,125,1000,48),
		_token:Rect2(985,232,68,46), _confirm:Rect2(985,670,450,76),
		_skip:Rect2(1260,35,275,62), get_node("RevealBack"):Rect2(45,35,180,62),
		get_node("RevealHome"):Rect2(240,35,140,62), _gallery:Rect2(90,220,1420,460)}
	if phase == "all":rects[_confirm] = Rect2(985,760,450,76)
	for node: Control in rects:
		var rect: Rect2 = rects[node]
		node.position = offset + rect.position*scale_factor
		node.size = rect.size
		node.scale = Vector2.ONE*scale_factor
	queue_redraw()

func _show_result(first: bool) -> void:
	if results.is_empty():
		_leave()
		return
	var row: Dictionary = results[result_index]
	var identity: Dictionary = app.home.unit(str(row.get("id", ""))) if app != null else row
	var texture: Texture2D = load(str(row.get("portrait", ""))) if ResourceLoader.exists(str(row.get("portrait", ""))) else null
	_art.texture = texture
	_head.texture = load("res://scripts/story_actor_layout.gd").portrait(texture, str(row.get("id", ""))) if texture != null else null
	_name_label.text = str(identity.get("codename", row.get("name", "")))
	_designation.text = str(identity.get("designation", row.get("id", "")))
	_status.text = str(row.get("status_text", "重复协议 · 已转换10协议片" if bool(row.get("duplicate", false)) else "初次回应 · 已收录人格核心"))
	_token.configure(str(identity.get("role", "marine")), "friendly", true)
	_confirm.text = "下一份协议" if result_index < results.size()-1 else "确认归队"
	phase_time = 0.0 if first and not reduced_motion else reveal_seconds-0.65 if not reduced_motion else reveal_seconds
	phase = "signal"
	_gallery.hide()
	_refresh()
	if app != null and app.audio != null: app.audio.ui("confirm")

func _process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	phase_time = minf(phase_time+delta, reveal_seconds)
	_refresh()

func _refresh() -> void:
	if _art == null: return
	var t: float = phase_time / maxf(.01, reveal_seconds)
	var is_all: bool = phase == "all"
	if not is_all: phase = "signal" if t < .35 else "handshake" if t < .60 else "identity" if t < .83 else "revealed"
	_progress.text = "已同步 · %d份协议均已入库"%results.size() if is_all else "%s    %02d / %02d"%[{"signal":"寻频 · 收到远方回应", "handshake":"握手 · 核心正在同步", "identity":"协议展开 · 识别人格", "revealed":"同步完成"}.get(phase, "同步完成"), result_index+1, results.size()]
	_art.visible = not is_all and t >= .60
	_art.modulate.a = clampf((t-.60)/.20, 0, 1)
	_head.visible = not is_all and not reduced_motion and t >= .39 and t < .84
	_head.modulate.a = clampf((t-.39)/.11,0,1)*clampf((.84-t)/.09,0,1)*.42
	for node: Control in [_name_label, _designation, _status, _token]:
		node.visible = not is_all and t >= .75
		node.modulate.a = clampf((t-.75)/.17,0,1)
	_confirm.visible = is_all or t >= .94
	_skip.visible = not is_all and t < 1.0
	queue_redraw()

func show_all() -> void:
	phase = "all"
	phase_time = reveal_seconds
	for node in _gallery.get_children(): node.queue_free()
	for row: Dictionary in results:
		var column := VBoxContainer.new()
		column.custom_minimum_size.x = 268
		_gallery.add_child(column)
		var portrait := TextureRect.new()
		portrait.custom_minimum_size = Vector2(column.custom_minimum_size.x, 170)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture = load("res://scripts/story_actor_layout.gd").portrait(load(str(row.portrait)), str(row.get("id", "")))
		column.add_child(portrait)
		var title := Label.new()
		var identity: Dictionary = app.home.unit(str(row.get("id", ""))) if app != null else row
		title.text = str(identity.get("codename", row.get("name", "")))
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 18)
		title.add_theme_color_override("font_color", Color("fff3d7"))
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		column.add_child(title)
		var ownership := Label.new()
		ownership.text = str(row.get("ownership_text", "+10协议片" if bool(row.get("duplicate",false)) else "初次收录"))
		ownership.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ownership.add_theme_font_size_override("font_size",16)
		ownership.add_theme_color_override("font_color",Color("a6c9c9"))
		column.add_child(ownership)
	_gallery.show()
	_confirm.text = "确认归队"
	_layout()
	_refresh()

func _next() -> void:
	if phase == "all" or result_index >= results.size()-1:
		_leave()
		return
	result_index += 1
	_show_result(false)

func _leave() -> void:
	finished.emit()
	queue_free()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("071d2a"))
	var k: float = minf(size.x/1600.0, size.y/900.0)
	var origin: Vector2 = size*.5
	var t: float = clampf(phase_time/maxf(.01, reveal_seconds),0,1)
	var radius: float = (120+260*smoothstep(0,.8,t))*k
	for index: int in 4:
		var alpha: float = .12 + index*.025
		var start: float = index*.5 + (t*1.4 if not reduced_motion else 0.0)
		draw_arc(origin, radius+index*22*k, start, start+PI*1.7, 96, Color(.4,.78,.78,alpha), 1.5*k, true)
	if phase in ["signal", "handshake"]:
		var p: float = smoothstep(0,.6,t)
		for index: int in 14:
			var y: float = size.y*(.25+.5*index/13.0)
			var spread: float = sin(index*2.3)*70*k
			draw_line(Vector2(0,y), Vector2(size.x*p,y+spread*p), Color(.64,.88,.86,.18), k, true)
		var angle: float = t*TAU
		var center: Vector2 = origin+Vector2(cos(angle),sin(angle))*radius*.65
		draw_circle(center, 7*k, Color("f2cf84"))
	var strip := PackedVector2Array([Vector2(size.x*.58,0),Vector2(size.x*.84,0),Vector2(size.x*.52,size.y),Vector2(size.x*.38,size.y)])
	draw_colored_polygon(strip, Color(.25,.52,.56,.07))
