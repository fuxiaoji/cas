@tool
extends Control
const Design=preload("res://scripts/ui_design.gd")
const LocalTimeBackdrop=preload("res://scripts/local_time_backdrop.gd")
@export var background:Texture2D
@export var game_title:String="归航"
@export var use_default_styles:bool=true
@export_range(-1,23,1) var preview_hour:int=-1
var app
var time_backdrop:Node
func _ready() -> void:
	if theme==null:theme=Design.theme()
	$Title.text=game_title
	if background!=null:$Backdrop.texture=background
	elif ResourceLoader.exists("res://assets/title/horizon-v2.png"):$Backdrop.texture=load("res://assets/title/horizon-v2.png")
	elif ResourceLoader.exists("res://assets/liveops/tidebound-event-v1.png"):$Backdrop.texture=load("res://assets/liveops/tidebound-event-v1.png")
	time_backdrop=LocalTimeBackdrop.new();time_backdrop.name="LocalTimeBackdrop";add_child(time_backdrop);time_backdrop.bind($Backdrop,1)
	time_backdrop.preview_hour=preview_hour;time_backdrop.refresh()
	if use_default_styles:
		for button in [$Actions/Begin,$Actions/Harbor,$Settings,$Quit]:
			_menu_style(button)
		for node in [$Mark,$Subtitle,$Footer]:node.add_theme_font_override("font",Design.font(400))
		var title_face:=FontVariation.new()
		title_face.base_font=load("res://assets/fonts/NotoSerifSC.ttf")
		title_face.variation_opentype={TextServerManager.get_primary_interface().name_to_tag("wght"):500.0}
		title_face.spacing_glyph=10
		$Title.add_theme_font_override("font",title_face)
	$Actions/Begin.mouse_entered.connect(func():$Ornament.set_meta("menu_focus",true);$Ornament.queue_redraw())
	$Actions/Begin.mouse_exited.connect(func():$Ornament.set_meta("menu_focus",false);$Ornament.queue_redraw())
func _menu_style(button:Button)->void:
	button.add_theme_font_override("font",Design.font(400))
	button.add_theme_font_size_override("font_size",26 if button.get_parent()==$Actions else 19)
	for state in ["normal","hover","pressed","focus","disabled"]:
		var style:=StyleBoxFlat.new()
		style.bg_color=Color(1,1,1,0.0 if state in ["normal","focus","disabled"] else 0.06)
		style.border_width_bottom=1 if state in ["hover","focus"] else 0
		style.border_color=Color(0.89,0.80,0.59,0.7)
		style.content_margin_left=20;style.content_margin_right=20
		button.add_theme_stylebox_override(state,style)
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		button.add_theme_color_override(key,Color("f1eddf"))
	button.add_theme_color_override("font_hover_color",Color("f7dba6"))
func bind(owner) -> void:
	app=owner
	time_backdrop.animated=bool(app.page_motion) and not bool(app.get_meta("reduced_motion",false))
	var active:bool=not app.economy.state.get("active_run",{}).is_empty()
	$Actions/Begin.text="继续航次" if active else "开始游戏"
	$Actions/Harbor.visible=active
	if app.economy.state.is_empty():
		$Actions/Begin.disabled=true
		$Footer.text="舰队档案无法读取，请先检查存档备份。"
	$Actions/Begin.pressed.connect(func():
		if active:app.resume_run();return
		var next:Dictionary=load("res://scripts/first_voyage_onboarding.gd").prepare_route(app.economy,"harbor")
		if not next.get("ok",false):app.notify(next);return
		app.show_page(str(next.route)))
	$Actions/Harbor.pressed.connect(func():app.show_page("harbor"))
	$Settings.pressed.connect(func():app.show_page("settings"))
	$Quit.pressed.connect(func():app.core.close();app.get_tree().quit())
	$Actions/Begin.grab_focus()
	if app.audio!=null:app.audio.set_paused(false);app.audio.set_scene("title")
	if not bool(app.get_meta("reduced_motion",false)):
		var tween:=create_tween()
		tween.tween_property($Backdrop,"scale",Vector2(1.012,1.012),12.0).set_trans(Tween.TRANS_SINE)
	$Ornament.set_process(not bool(app.get_meta("reduced_motion",false)))
