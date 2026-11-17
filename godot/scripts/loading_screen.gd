@tool
extends Control
## Lightweight first frame. All progress is supplied by the actual loading task.
## No catalogue, save, character art, large font, or gameplay dependency is loaded here.
signal retry_requested
signal quit_requested

@export var stage_text: String = "正在准备航线…":
	set(value):
		stage_text = value
		_refresh_labels()
@export_range(-1.0, 1.0, 0.01) var progress_value: float = -1.0:
	set(value):
		progress_value = -1.0 if value < 0.0 else clampf(value, 0.0, 1.0)
		queue_redraw()
@export var reduced_motion: bool = false:
	set(value):
		reduced_motion = value
		_sync_processing()
		queue_redraw()

var failed: bool = false
var failure_message: String = ""
var animation_clock: float = 0.0
var _content: VBoxContainer
var _title: Label
var _stage: Label
var _message: Label
var _actions: HBoxContainer
var _retry: Button
var _quit: Button
var _face: SystemFont

const INK: Color = Color("285b6b")
const MUTED: Color = Color("60858c")
const SEA: Color = Color("398f9a")
const GOLD: Color = Color("cca96c")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_face = SystemFont.new()
	_face.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	var light_theme := Theme.new()
	light_theme.default_font = _face
	light_theme.default_font_size = 19
	theme = light_theme
	_build_content()
	resized.connect(_layout_content)
	visibility_changed.connect(_sync_processing)
	_layout_content()
	_refresh_labels()
	_sync_processing()

func set_stage(text: String, progress: float = -1.0) -> void:
	stage_text = text
	progress_value = progress

func set_reduced_motion(value: bool) -> void:
	reduced_motion = value

func show_failure(message: String) -> void:
	failed = true
	failure_message = message
	show()
	_refresh_labels()
	queue_redraw()
	call_deferred("_focus_retry")

func clear_failure() -> void:
	failed = false
	failure_message = ""
	_refresh_labels()
	queue_redraw()

func _build_content() -> void:
	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_theme_constant_override("separation", 13)
	center.add_child(_content)
	var mark := _label("CAS", 18, MUTED)
	mark.name = "Mark"
	_content.add_child(mark)
	_title = _label("归 航", 45, INK)
	_title.name = "Title"
	_content.add_child(_title)
	_stage = _label(stage_text, 20, MUTED)
	_stage.name = "Stage"
	_stage.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_stage)
	_message = _label("", 17, MUTED)
	_message.name = "Message"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_message)
	_actions = HBoxContainer.new()
	_actions.name = "Actions"
	_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_actions.add_theme_constant_override("separation", 16)
	_actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_actions)
	_retry = _button("重试", true)
	_retry.name = "Retry"
	_retry.pressed.connect(func() -> void: retry_requested.emit())
	_actions.add_child(_retry)
	_quit = _button("退出游戏", false)
	_quit.name = "Quit"
	_quit.pressed.connect(func() -> void: quit_requested.emit())
	_actions.add_child(_quit)
	_retry.focus_neighbor_right = NodePath("../Quit")
	_quit.focus_neighbor_left = NodePath("../Retry")

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(148, 49)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 18)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = SEA if primary else Color(1.0, 1.0, 1.0, 0.48)
		if state == "hover": style.bg_color = style.bg_color.lightened(0.08)
		if state == "pressed": style.bg_color = style.bg_color.darkened(0.07)
		style.set_corner_radius_all(5)
		style.set_border_width_all(2 if state == "focus" else 1)
		style.border_color = GOLD if state == "focus" else Color(0.28, 0.56, 0.59, 0.22)
		style.content_margin_left = 20
		style.content_margin_right = 20
		button.add_theme_stylebox_override(state, style)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color("f5fcf9") if primary else INK)
	return button

func _layout_content() -> void:
	if not is_instance_valid(_content): return
	_content.custom_minimum_size.x = clampf(size.x * 0.64, 300.0, 650.0)
	_title.add_theme_font_size_override("font_size", int(clampf(size.y * 0.058, 34.0, 54.0)))
	_stage.add_theme_font_size_override("font_size", int(clampf(size.y * 0.026, 18.0, 23.0)))
	queue_redraw()

func _refresh_labels() -> void:
	if not is_instance_valid(_stage): return
	_stage.text = "暂时无法启航" if failed else stage_text
	_message.text = failure_message
	_message.visible = failed
	_actions.visible = failed

func _focus_retry() -> void:
	if failed and is_visible_in_tree() and is_instance_valid(_retry): _retry.grab_focus()

func _sync_processing() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if is_visible_in_tree() else Control.MOUSE_FILTER_IGNORE
	set_process(is_inside_tree() and is_visible_in_tree() and not reduced_motion)

func _process(delta: float) -> void:
	animation_clock = fmod(animation_clock + minf(delta, 0.1), 120.0)
	queue_redraw()

func _draw() -> void:
	if minf(size.x, size.y) < 1.0: return
	var corners := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	draw_polygon(corners, PackedColorArray([Color("e0f1ef"), Color("eaf5ef"), Color("c3e3e1"), Color("c9e7e6")]))
	var drift: float = 0.0 if reduced_motion else sin(animation_clock * 0.15) * size.x * 0.015
	_cloud(Vector2(size.x * 0.10 + drift, size.y * 0.17), size.y * 0.16, 0.55)
	_cloud(Vector2(size.x * 0.84 - drift * 0.7, size.y * 0.14), size.y * 0.19, 0.59)
	_cloud(Vector2(size.x * 0.99 + drift * 0.4, size.y * 0.52), size.y * 0.12, 0.28)
	for line in range(4):
		var wave := PackedVector2Array()
		for point in range(61):
			var x: float = size.x * float(point) / 60.0
			var shift: float = 0.0 if reduced_motion else animation_clock * (0.24 + float(line) * 0.035)
			var y: float = size.y * (0.74 + float(line) * 0.035) + sin(x / size.x * TAU * 1.3 + shift + float(line)) * size.y * 0.014
			wave.append(Vector2(x, y))
		draw_polyline(wave, Color(1, 1, 1, 0.27 - float(line) * 0.035), 1.3, true)
	var compass_radius: float = clampf(size.y * 0.042, 21.0, 39.0)
	var compass_y: float = size.y * 0.29
	if is_instance_valid(_content):
		# A wrapped recovery message makes the centered block taller on small screens.
		# Keep the ornament above that actual block instead of drawing through its title.
		compass_y = minf(compass_y, maxf(compass_radius * 1.4, _content.position.y - compass_radius * 1.65))
	_draw_compass(Vector2(size.x * 0.5, compass_y), compass_radius)
	if not failed: _draw_progress()

func _cloud(center: Vector2, radius: float, alpha: float) -> void:
	var color := Color(1, 1, 1, alpha)
	draw_set_transform(center, 0.0, Vector2(1.5, 0.50))
	draw_circle(Vector2(-radius * 0.72, radius * 0.12), radius * 0.67, color, true, -1.0, true)
	draw_circle(Vector2(-radius * 0.14, -radius * 0.17), radius * 0.90, color, true, -1.0, true)
	draw_circle(Vector2(radius * 0.64, radius * 0.04), radius * 0.69, color, true, -1.0, true)
	draw_set_transform(Vector2.ZERO)

func _draw_compass(center: Vector2, radius: float) -> void:
	draw_arc(center, radius, 0.0, TAU, 56, Color(0.19, 0.46, 0.49, 0.20), 1.0, true)
	for index in range(8):
		var direction := Vector2.UP.rotated(float(index) * TAU / 8.0)
		draw_line(center + direction * radius * 1.12, center + direction * radius * 1.25, Color(0.19, 0.46, 0.49, 0.32), 1.0, true)
	var angle: float = 0.0 if reduced_motion or failed else sin(animation_clock * 0.48) * 0.17
	var needle := PackedVector2Array([Vector2(0, -radius * 0.81), Vector2(radius * 0.22, radius * 0.32), Vector2(0, radius * 0.16), Vector2(-radius * 0.22, radius * 0.32)])
	draw_set_transform(center, angle)
	draw_colored_polygon(needle, SEA)
	draw_circle(Vector2.ZERO, radius * 0.055, GOLD, true, -1.0, true)
	draw_set_transform(Vector2.ZERO)

func _draw_progress() -> void:
	var width: float = clampf(size.x * 0.34, 240.0, 550.0)
	var track := Rect2(Vector2((size.x - width) * 0.5, size.y * 0.86), Vector2(width, 3.0))
	draw_rect(track, Color(0.25, 0.52, 0.55, 0.17))
	if progress_value >= 0.0:
		draw_rect(Rect2(track.position, Vector2(track.size.x * progress_value, track.size.y)), SEA)
	elif reduced_motion:
		for index in range(3):
			draw_rect(Rect2(track.position + Vector2(track.size.x * (0.44 + float(index) * 0.05), -1.0), Vector2(4.0, 5.0)), SEA)
	else:
		var span: float = width * 0.19
		var travel: float = sin(animation_clock * 1.25 - PI * 0.5) * 0.5 + 0.5
		draw_rect(Rect2(track.position + Vector2((width - span) * travel, 0), Vector2(span, track.size.y)), SEA)
