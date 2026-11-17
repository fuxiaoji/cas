extends RefCounted
## Presentation-only scene layers. They never advance the combat simulation.
const Design = preload("res://scripts/ui_design.gd")
const INK := Design.INK
const WHITE := Color("f5f8fa")

static func gradient(app, parent: Control, rect: Rect2, from: Color, to: Color, vertical := true) -> TextureRect:
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([from, to])
	var texture := GradientTexture2D.new()
	texture.gradient = ramp
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2(0, 1) if vertical else Vector2(1, 0)
	var node := TextureRect.new()
	node.texture = texture
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app.place(node, parent, rect.position.x, rect.position.y, rect.size.x, rect.size.y)
	return node

static func background(app, parent: Control, night := false) -> void:
	var asset := "res://assets/backgrounds/night-sea-v2.png" if night else "res://assets/backgrounds/harbor-day-v2.png"
	if night and not ResourceLoader.exists(asset): asset = "res://assets/backgrounds/harbor-night.png"
	if not ResourceLoader.exists(asset): asset = "res://assets/backgrounds/recruit-sky.png"
	app.picture(parent, asset, 0, 0, 1600, 900, true)
	gradient(app, parent, Rect2(0, 0, 1600, 900), Color(0.09, 0.2, 0.3, 0.16), Color(0.1, 0.22, 0.3, 0.05))

static func quiet_button(app, parent: Control, title: String, x: float, y: float, w: float, action: Callable, dark := false) -> Button:
	var button: Button = app.button(parent, title, x, y, w, 48, action)
	Design.apply_button(button, false, true)
	var ink := WHITE if dark else INK
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := Design.box(Color(0.025, 0.09, 0.16, 0.16) if dark else Color(1, 1, 1, 0.12), 3)
		if state != "normal": box.bg_color.a = 0.64 if dark else 0.75
		box.border_color = Design.GOLD
		box.set_border_width_all(1 if state == "focus" else 0)
		box.content_margin_left = 10
		box.content_margin_right = 10
		button.add_theme_stylebox_override(state, box)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, ink)
	button.add_theme_font_size_override("font_size", 20)
	return button

static func dialogue(app, speaker: String, message: String, _dark := false) -> void:
	var tint := Color(0.025,0.09,0.16,0.97)
	var font:Font=Design.font(400)
	var needed:float=maxf(78.0,font.get_multiline_string_size(message,HORIZONTAL_ALIGNMENT_LEFT,1230,26).y+8.0)
	var body_top:float=833.0-needed
	var shade:=gradient(app, app.page, Rect2(0,body_top-95.0,1600,914.0-body_top), Color(tint,0.0), tint)
	shade.set_meta("story_dialogue_shade",true)
	for rect:Rect2 in [Rect2(0,0,1600,81),Rect2(0,819,1600,81)]:
		var band:=ColorRect.new();band.color=Color.BLACK;band.mouse_filter=Control.MOUSE_FILTER_IGNORE;app.place(band,app.page,rect.position.x,rect.position.y,rect.size.x,rect.size.y)
	app.panel(app.page, 64, body_top-43.0, 4, 28, Color("cbb379"))
	var name:Label=app.label(app.page, speaker.replace(" · 状态机辅助", ""), 84, body_top-51.0, 1190, 38, 22, WHITE)
	name.add_theme_font_override("font", Design.font(600));name.set_meta("story_dialogue_speaker",true)
	var body:Label=app.label(app.page, message, 84, body_top, 1230, needed, 26, WHITE)
	body.add_theme_font_override("font", font);body.set_meta("story_dialogue_body",true)

static func remember(app, speaker: String, message: String) -> void:
	var log: Array = app.get_meta("story_backlog", [])
	var line := {"speaker":speaker, "text":message}
	if log.is_empty() or log.back() != line:
		log.append(line)
		if log.size() > 100: log.pop_front()
		app.set_meta("story_backlog", log)

static func backlog(app) -> void:
	var parent: Control = app.open_modal("对白回顾")
	var scroll := ScrollContainer.new()
	app.place(scroll, parent, 385, 230, 830, 445)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 20)
	scroll.add_child(rows)
	var log: Array = app.get_meta("story_backlog", [])
	for entry in log:
		var label := Label.new()
		label.text = str(entry.speaker) + "\n" + str(entry.text)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 700
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", INK)
		rows.add_child(label)
	if log.is_empty():
		var label := Label.new()
		label.text = "对白会在阅读后收录于此。"
		label.add_theme_color_override("font_color", INK)
		rows.add_child(label)

static func card_art(app, parent: Control, asset: String, x: float, y: float, w: float, h: float) -> void:
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app.place(clip, parent, x, y, w, h)
	app.picture(clip, asset, -200, -20, 2000, 1500)
