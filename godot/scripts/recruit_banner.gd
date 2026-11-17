@tool
extends Control
## Editable banner composition; all commits and reveals remain in the existing service.
const Design=preload("res://scripts/ui_design.gd")
const Service=preload("res://scripts/recruit_presentation.gd")
@export_enum("up","standard") var preview_pool:String="up":
	set(value):preview_pool=value;if is_node_ready() and Engine.is_editor_hint():_preview()
@export_file("*.png") var featured_art:String="res://assets/story/canon-v2/missouri-limited-banner.png"
var app
func _ready()->void:
	theme=Design.theme()
	for node in get_children():
		if node is Label:
			node.add_theme_font_override("font",Design.font(600 if str(node.name) in ["PageTitle","Headline","CharacterName"] else 400))
	for button in [$DrawOne,$DrawTen]:Design.apply_button(button,button==$DrawTen)
	for button in [$Back,$Home,$Probability,$History,$Exchange,$Replay]:
		for state in ["normal","hover","pressed","focus"]:
			button.add_theme_stylebox_override(state,Design.box(Color(1,1,1,.12 if state in ["hover","focus"] else 0),0))
		for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:button.add_theme_color_override(state,Color("f0f2f2"))
	$OriginIcon.texture=Design.icon_texture("spark");$TicketIcon.texture=Design.icon_texture("ticket")
	_preview()
func _preview()->void:
	var up:bool=preview_pool=="up"
	var path:String=featured_art if up else "res://assets/backgrounds/recruit-sky.png"
	$Backdrop.texture=load(path) if ResourceLoader.exists(path) else null
	$Eyebrow.text="特别邀请" if up else "常驻信号"
	$Headline.text="枕着海风的龙" if up else "海的另一端"
	$CharacterName.text="密苏里" if up else "新的同行者"
	$Tagline.text="不远航。守着你们这盏灯就够了。" if up else "听见信号，再一起出发。"
	$Chance.text="UR中50%为密苏里" if up else "同稀有度角色等概率"
	$AppearanceHint.visible=up
	_style_tab($Pool_UP,featured_art,up)
	_style_tab($Pool_Standard,"res://assets/backgrounds/recruit-sky.png",not up)
	_style_tab($Pool_Tactical,"res://assets/tactical/portraits/MCP-001.png",false)
func _style_tab(button:Button,path:String,selected:bool)->void:
	button.get_node("Artwork").texture=load(path) if ResourceLoader.exists(path) else null
	button.get_node("Artwork").modulate=Color(1,1,1,.82 if selected else .4)
	button.get_node("Caption").add_theme_font_override("font",Design.font(600))
	button.get_node("Selection").visible=selected
	for state in ["normal","hover","pressed","focus"]:
		var box=Design.box(Color("161f29"),2,Color("e5dfcd") if selected else Color(.7,.8,.9,.16))
		box.set_border_width_all(2 if selected or state=="focus" else 1);button.add_theme_stylebox_override(state,box)
func bind(owner)->void:
	app=owner;preview_pool=str(app.get_meta("recruit_pool","up"));featured_art=Service.featured_art(app);_preview()
	var up:bool=preview_pool=="up";var wallet:Dictionary=app.economy.wallet()
	var tickets:int=int(wallet.get("up_tickets" if up else "tickets",0))
	$Origins.text="元词 %d"%int(wallet.get("origins",0));$Tickets.text="%s %d"%["UP券" if up else "常驻券",tickets]
	$Pity.text="普通累计 %d / 9 · 九普后至少稀有"%int(app.economy.state.get("pity_by_pool",{}).get(preview_pool,0))
	$Back.pressed.connect(app.go_back);$Home.pressed.connect(app.go_home)
	$Pool_UP.pressed.connect(func():app.set_meta("recruit_pool","up");app.show_page("recruit"))
	$Pool_Standard.pressed.connect(func():app.set_meta("recruit_pool","standard");app.show_page("recruit"))
	$Pool_Tactical.pressed.connect(func():app.show_page("home_recruit"))
	$Probability.pressed.connect(func():Service.details(app));$History.pressed.connect(func():Service.history(app))
	$Exchange.pressed.connect(func():app.set_meta("supply_category","exchange");app.show_page("shop"))
	var pending:Dictionary=app.economy.state.get("pending_recruit",{})
	$Replay.text="继续到港" if not pending.is_empty() else "回看"
	$Replay.visible=not pending.is_empty() or not app.economy.state.get("last_recruit",{}).is_empty()
	$Replay.pressed.connect(func():Service.reveal(app,pending if not pending.is_empty() else app.economy.state.last_recruit))
	$DrawOne.pressed.connect(func():Service.draw(app,1,preview_pool));$DrawTen.pressed.connect(func():Service.draw(app,10,preview_pool))
	var locked:bool=not app.economy.state.get("active_run",{}).is_empty()
	$DrawOne.disabled=locked or tickets<1;$DrawTen.disabled=locked or tickets<10
	$DrawOne.tooltip_text="请先结束海上行动" if locked else "需要1张对应征募券"
	$DrawTen.tooltip_text="请先结束海上行动" if locked else "需要10张对应征募券"
	$Toast.text="海上行动未结束，暂不能征募" if locked else ""
	app.toast_label=$Toast;app.first_button=$DrawOne
