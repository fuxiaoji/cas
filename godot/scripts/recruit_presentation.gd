extends RefCounted
## A character-led banner and committed-result reveal. No economy mutation in animation.
const Design = preload("res://scripts/ui_design.gd")
const NAVY := Design.INK
const GOLD := Design.GOLD
const Cinema = preload("res://scripts/cinematic_presentation.gd")
const Arrival = preload("res://scripts/arrival_signal.gd")

static func heading(app, parent: Control, text: String, x: float, y: float, w: float, h: float, size_value: int, color := NAVY) -> Label:
	var l: Label = app.label(parent, text, x, y, w, h, mini(size_value, 40), color)
	l.add_theme_font_override("font", Design.font(600))
	return l

static func light_button(app, parent: Control, text: String, x: float, y: float, w: float, callback: Callable, primary := true) -> Button:
	var b: Button = app.button(parent, text, x, y, w, 58, callback, primary)
	Design.apply_button(b, primary)
	return b

static func pool_tab(app, parent: Control, title: String, x: float, width: float, selected: bool, dark: bool, callback: Callable) -> void:
	var tab: Button = Cinema.quiet_button(app, parent, title, x, 25, width, callback, dark)
	var ink := Cinema.WHITE if dark else NAVY
	tab.add_theme_font_override("font", Design.font(600 if selected else 400))
	for key in ["normal", "hover", "pressed", "focus"]:
		var style := Design.box(Color(1,1,1,0.10 if key == "hover" else 0.0), 0)
		style.border_color = GOLD if dark else Design.ACCENT
		style.border_width_bottom = 3 if selected else (1 if key == "focus" else 0)
		tab.add_theme_stylebox_override(key, style)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		tab.add_theme_color_override(key, ink if selected else Color(ink, 0.7))

static func featured_art(app) -> String:
	var limited:String="res://assets/story/canon-v2/missouri-limited-banner.png"
	if ResourceLoader.exists(limited):return limited
	return str(app.economy.config.get("gacha", {}).get("featured_art", "res://assets/recruit/missouri-up-v1.png"))

static func shade(app, parent: Control) -> void:
	var gradient:=Gradient.new()
	gradient.colors=PackedColorArray([Color(0.015,0.055,0.12,0.92),Color(0.015,0.055,0.12,0)])
	var texture:=GradientTexture2D.new();texture.gradient=gradient;texture.fill_from=Vector2(0,0);texture.fill_to=Vector2(1,0)
	var image:=TextureRect.new();image.texture=texture;image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.mouse_filter=Control.MOUSE_FILTER_IGNORE
	app.place(image,parent,0,0,850,900)

static func render(app) -> void:
	var scene:Control=load("res://scenes/ui/recruit_banner.tscn").instantiate()
	scene.name="RecruitBanner"
	app.page.add_child(scene)
	scene.bind(app)

static func draw(app, count: int, pool: String) -> void:
	var response: Dictionary = app.economy.recruit(count, "banner-%s-%d" % [pool, Time.get_ticks_usec()], pool)
	app.show_page("recruit")
	if not await app.wait_for_page("recruit"):return
	app.notify(response)
	if response.get("ok", false): reveal(app, response)

static func details(app) -> void:
	var up := str(app.get_meta("recruit_pool", "up")) == "up"
	var layer: Control = app.open_modal("UP征募详情" if up else "常驻征募详情")
	var text := "基础概率：UR 2% / 精锐8% / 稀有20% / 普通70%。\n常驻与UP分别累计普通次数，9次普通后下次至少稀有。\n保底时按稀有/精锐/UR = 20:8:2重新归一。\n\n"
	text += "UP池UR中50%是密苏里，基础单抽概率1%；其余UR平分另1%。\n不设隐藏的歪后必中特例或限定角色保证。\n" if up else "同稀有度的常驻角色等概率。\n"
	text += "\n重复角色转银币与舰队勋章，数额读取配置。\n扣券、角色、补偿和记录先保存，动画可跳过或中途退出。\n跳过、重开与回看不会重新抽奖或重复扣券。"
	app.label(layer, text, 390, 238, 825, 430, 24)

static func history(app) -> void:
	var layer: Control = app.open_modal("征募记录")
	var scroll := ScrollContainer.new()
	app.place(scroll, layer, 380, 240, 840, 445)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	scroll.add_child(rows)
	for draw in app.economy.state.get("history", []):
		var line := Label.new()
		line.text = "%d    %s    %s    %s" % [int(draw.get("sequence", 0)), str(draw.get("name", "")), rarity_name(str(draw.get("rarity", "common"))), "重复补偿" if draw.get("duplicate", false) else "新舰入列"]
		line.add_theme_font_size_override("font_size", 24)
		rows.add_child(line)

static func rarity_name(tier: String) -> String:
	return str({"common": "普通", "rare": "稀有", "elite": "精锐", "ur": "UR"}.get(tier, tier))

static func rarity_color(tier: String) -> Color:
	return {"common": Color("839caa"), "rare": Color("62b0cf"), "elite": Color("b799e2"), "ur": Color("edcc7e")}.get(tier, Color("839caa"))

static func manifest(app, response: Dictionary) -> void:
	app.close_modal()
	app.modal = Control.new()
	app.add_child(app.modal)
	app.modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var parent: Control = app.modal
	app.picture(parent, "res://assets/backgrounds/recruit-sky.png", 0, 0, 1600, 900, true)
	Cinema.gradient(app,parent,Rect2(0,0,1600,900),Color(0.96,0.98,0.94,0.2),Color(0.96,0.98,0.94,0.96))
	heading(app, parent, "到港清册", 75, 65, 800, 65, 32, NAVY)
	app.label(parent, "每一道回应，都是新的航程。", 80, 150, 900, 50, 22, Color("647f87"))
	app.button(parent, "关闭", 1380, 65, 140, 53, func(): complete(app, response))
	var draws: Array = response.get("draws", response.get("results", []))
	var count := draws.size()
	var width := 136.0 if count > 5 else 230.0
	var gap := 10.0 if count > 5 else 25.0
	var start := (1600.0 - count * width - maxi(0, count - 1) * gap) / 2.0
	for i in range(count):
		var draw: Dictionary = draws[i]
		var color := rarity_color(str(draw.get("rarity", "common")))
		var cell := Control.new()
		app.place(cell, parent, start + i * (width + gap), 242, width, 475)
		cell.clip_contents = true
		var background: Panel = app.panel(cell, 0, 0, 1600, 900, color.darkened(0.65))
		var box: StyleBoxFlat = background.get_theme_stylebox("panel").duplicate()
		box.border_color = color
		box.border_width_top = 4
		box.border_width_bottom = 3
		background.add_theme_stylebox_override("panel", box)
		face(app, cell, draw, 0, 0, 1600, 630)
		app.panel(cell, 0, 624, 1600, 276, Color(0.03, 0.08, 0.13, 0.88))
		app.label(cell, rarity_name(str(draw.get("rarity", "common"))), 115, 641, 1400, 62, 19, color)
		heading(app, cell, str(draw.get("name", "")), 112, 707, 1400, 87, 25 if count <= 5 else 22, Color("f0ebdf"))
		app.label(cell, "重复获得" if draw.get("duplicate", false) else "初次相逢", 112, 816, 1400, 56, 18, Color("b6c6cc"))
		cell.modulate.a = 0
		var tween: Tween = app.create_tween()
		tween.tween_interval(i * 0.035)
		tween.tween_property(cell, "modulate:a", 1.0, 0.22)
	app.label(parent, "本次到港  %d 艘" % count, 80, 788, 650, 60, 24, NAVY)
	light_button(app, parent, "确认入列", 1190, 790, 330, func(): complete(app, response))

static func phase(app, response: Dictionary, stage: String, index: int = 0) -> void:
	if str(app.economy.state.get("pending_recruit", {}).get("batch_id", "")) == str(response.get("batch_id", "")):
		app.economy.recruit_animation(stage, index)

static func complete(app, response: Dictionary) -> void:
	phase(app, response, "complete")
	app.close_modal()

static func face(app, parent: Control, row: Dictionary, x: float, y: float, width: float, height: float) -> void:
	var featured := str(row.get("id", "")) == "IBS-U-USN-ERMA-MISSOURI"
	var asset := featured_art(app) if featured else str(row.get("portrait", ""))
	if not ResourceLoader.exists(asset): return
	var original: Texture2D = load(asset)
	var size := original.get_size()
	var atlas := AtlasTexture.new()
	atlas.atlas = original
	atlas.region = Rect2(size.x*0.61, size.y*0.035, size.x*0.18, size.y*0.31) if featured else Rect2(size.x*0.23, size.y*0.025, size.x*0.54, size.y*0.45)
	var image := TextureRect.new()
	image.texture=atlas;image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;image.mouse_filter=Control.MOUSE_FILTER_IGNORE
	app.place(image, parent, x, y, width, height)

static func reveal(app, response: Dictionary) -> void:
	var draws: Array = response.get("draws", response.get("results", []))
	if draws.is_empty(): return
	if str(response.get("phase", "signal")) in ["reveal", "complete"]:
		single(app,response,clampi(int(response.get("index",0)),0,draws.size()-1));return
	app.close_modal()
	app.modal=Control.new();app.add_child(app.modal);app.modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var parent: Control = app.modal
	parent.set_meta("skipped",false)
	app.picture(parent,"res://assets/backgrounds/recruit-sky.png",0,0,1600,900,true)
	Cinema.gradient(app,parent,Rect2(0,0,1600,900),Color(0.08,0.24,0.36,0.1),Color(0.08,0.24,0.36,0.45))
	var light = Arrival.new()
	app.place(light,parent,0,0,1600,900)
	heading(app,parent,"海的另一端，有人回应了。",480,705,900,68,31,Color("f4ecdb"))
	Cinema.quiet_button(app,parent,"跳过演出",1330,35,210,func():parent.set_meta("skipped",true);phase(app,response,"reveal");manifest(app,response))
	phase(app,response,"approach")
	await app.get_tree().create_timer(1.85).timeout
	if not is_instance_valid(parent) or bool(parent.get_meta("skipped",false)):return
	single(app,response,0)

static func single(app, response: Dictionary, index: int) -> void:
	app.close_modal();app.modal=Control.new();app.add_child(app.modal);app.modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var parent: Control=app.modal
	var draws: Array=response.get("draws",response.get("results",[]))
	var row: Dictionary=draws[index]
	phase(app,response,"reveal",index)
	var featured:=str(row.get("id",""))=="IBS-U-USN-ERMA-MISSOURI"
	app.picture(parent,featured_art(app) if featured else "res://assets/backgrounds/recruit-sky.png",0,0,1600,900,true)
	if featured:
		shade(app,parent)
	else:
		Cinema.gradient(app,parent,Rect2(0,0,1000,900),Color(0.97,0.98,0.94,0.97),Color(0.97,0.98,0.94,0),false)
		app.picture(parent,str(row.get("portrait","")),660,-15,900,930)
	# The close-up is a camera beat, not a second framed portrait.
	var closeup := Control.new()
	closeup.clip_contents = true
	closeup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if featured and ResourceLoader.exists("res://assets/recruit/missouri-closeup-v2.png"):
		app.place(closeup,parent,0,0,1600,900)
		app.picture(closeup,"res://assets/recruit/missouri-closeup-v2.png",0,0,1600,900,true)
		shade(app,closeup)
	else:
		app.place(closeup,parent,695,0,905,900)
		face(app,closeup,row,0,-40,1600,1040)
	var close_camera: Tween = closeup.create_tween()
	close_camera.tween_interval(0.75)
	close_camera.tween_property(closeup,"modulate:a",0.0,0.65).set_trans(Tween.TRANS_SINE)
	var text_color := Color("f4ecdb") if featured else NAVY
	var title: Label=heading(app,parent,str(row.get("name","新舰")),95,432,620,85,40,text_color)
	app.label(parent,rarity_name(str(row.get("rarity","common"))),100,374,550,42,25,GOLD if featured else rarity_color(str(row.get("rarity","common"))).darkened(0.3))
	app.label(parent,"再次相逢" if row.get("duplicate",false) else "初次相逢",102,565,600,50,25,text_color)
	app.label(parent,"%d / %d"%[index+1,draws.size()],95,52,270,45,21,text_color)
	Cinema.quiet_button(app,parent,"查看总览",90,810,230,func():manifest(app,response),featured)
	light_button(app,parent,"下一位" if index+1<draws.size() else "查看到港清册",1120,799,390,func():single(app,response,index+1) if index+1<draws.size() else manifest(app,response))
	title.modulate.a=0
	var title_fade: Tween=title.create_tween()
	title_fade.tween_interval(0.45)
	title_fade.tween_property(title,"modulate:a",1.0,0.45)
	parent.modulate.a=0
	var fade: Tween=parent.create_tween();fade.tween_property(parent,"modulate:a",1.0,0.23)
	if app.audio!=null:app.audio.ui("confirm")
