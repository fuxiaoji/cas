@tool
extends Control
const Design=preload("res://scripts/ui_design.gd")
const Port=preload("res://scripts/port_presentation.gd")
const LocalTimeBackdrop=preload("res://scripts/local_time_backdrop.gd")
@export var use_default_styles:bool=true
@export_range(-1,23,1) var preview_hour:int=-1
var time_backdrop:Node
func _ready() -> void:
	if theme==null:theme=Design.theme()
	time_backdrop=LocalTimeBackdrop.new();time_backdrop.name="LocalTimeBackdrop";add_child(time_backdrop);time_backdrop.bind($Background,0)
	time_backdrop.preview_hour=preview_hour;time_backdrop.refresh()
	if not use_default_styles:return
	for node in find_children("*","Button",true,false):Design.apply_button(node)
	var routes=["Crew","Fleet","Warehouse","Shop","Recruit"]
	var icons=["crew","fleet","cargo","supply","recruit"]
	for i in range(routes.size()):
		var b:Button=get_node(routes[i]);Design.apply_button(b,false,true)
		for state in ["normal","hover","pressed","focus"]:
			var style:StyleBoxFlat=b.get_theme_stylebox(state).duplicate();style.content_margin_top=43;style.content_margin_bottom=4
			if state in ["hover","pressed"]:style.bg_color=Color(1,1,1,.14)
			b.add_theme_stylebox_override(state,style)
		for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:b.add_theme_color_override(key,Color.WHITE)
		get_node(routes[i]+"Icon").texture=Design.icon_texture(icons[i])
	for name in ["Archive","Service"]:
		var b:Button=get_node(name);Design.apply_button(b,false,true)
		for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:b.add_theme_color_override(key,Color.WHITE)
	for name in ["Story","Campaign","ArenaEntry"]:
		var b:Button=get_node(name);b.alignment=HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size",28)
		for state in ["normal","hover","pressed","focus"]:
			var style:StyleBoxFlat=b.get_theme_stylebox(state).duplicate();style.content_margin_left=68;b.add_theme_stylebox_override(state,style)
	$Sail.add_theme_font_size_override("font_size",36)
	$Sail.add_theme_font_override("font",Design.font(700));$Sail.alignment=HORIZONTAL_ALIGNMENT_LEFT
	for state in ["normal","hover","pressed","focus"]:
		var fill:=Color(.05,.19,.28,.91)
		if state=="hover":fill=Color(.07,.28,.38,.97)
		if state=="pressed":fill=Color(.03,.13,.21,.97)
		var style:=Design.box(fill,3);style.border_color=Design.GOLD;style.border_width_left=4;style.content_margin_left=32
		if state=="focus":style.set_border_width_all(2)
		$Sail.add_theme_stylebox_override(state,style)
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:$Sail.add_theme_color_override(key,Color.WHITE)
	$SailIcon.texture=Design.icon_texture("sortie");$StoryIcon.texture=Design.icon_texture("story");$CampaignIcon.texture=Design.icon_texture("compass")
	$StoryIcon.modulate=Design.ACCENT;$CampaignIcon.modulate=Design.ACCENT;$SailIcon.modulate=Design.GOLD
	$ArenaIcon.texture=Design.icon_texture("trophy");$ArenaIcon.modulate=Design.ACCENT
func bind(app) -> void:
	time_backdrop.animated=bool(app.page_motion) and not bool(app.get_meta("reduced_motion",false))
	var featured:Dictionary=Port._featured(app)
	var portrait:String=str(featured.get("portrait",""))
	if ResourceLoader.exists(portrait):$SecretaryPortrait.texture=load(portrait)
	$SecretaryName.text=str(featured.get("name",""))
	var scale_value:=float(app.economy.state.harbor.get("scale",1.0))
	var offset:=Vector2(float(app.economy.state.harbor.get("x",0)),float(app.economy.state.harbor.get("y",0)))
	app.place_reposition($SecretaryPortrait,512-373*scale_value+offset.x,818-735*scale_value+offset.y,746*scale_value,735*scale_value)
	$Adjust.pressed.connect(func():Port.secretary_settings(app))
	var active:bool=not app.economy.state.get("active_run",{}).is_empty()
	$Sail.text="继续航次" if active else "出航"
	$Sail.pressed.connect(func():app.resume_run() if active else app.show_page("modes"))
	var routes={"ArenaEntry":"arena","Story":"canon_catalog","Campaign":"campaign","Crew":"roster","Fleet":"formation","Warehouse":"warehouse","Shop":"shop","Recruit":"recruit","Archive":"archives"}
	for key in routes:
		var route:String=routes[key]
		get_node(key).pressed.connect(func():app.show_page(route))
	$Service.pressed.connect(func():app.bulk_service())
