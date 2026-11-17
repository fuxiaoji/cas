@tool
extends Control
const Design=preload("res://scripts/ui_design.gd")
const Supply=preload("res://scripts/supply_presentation.gd")
const Meta=preload("res://scripts/meta_economy.gd")
@export var content:Resource=preload("res://data/expedition-design.tres")
@export_enum("calm","standard","hazard") var preview_difficulty:String="calm":
	set(value):
		preview_difficulty=value
		if is_node_ready() and Engine.is_editor_hint():selection.difficulty=value;_refresh()
var app
var selection:Dictionary={"difficulty":"calm","environment":"atoll","weather":"auto","scene":"sunken_metropolis"}
var choices:Dictionary={}
func _ready()->void:
	theme=Design.theme()
	selection.difficulty=preview_difficulty
	for i in range(3):
		var card:Control=$Cards.get_child(i)
		var data:Dictionary=content.difficulties[i]
		var body:Control=card.get_node("Margin/Body")
		for pair in [["Title","name"],["Tagline","tagline"],["Risk","risk"],["Reward","reward"]]:body.get_node(pair[0]).text=str(data.get(pair[1],""))
		var path:=str(data.art)
		if not ResourceLoader.exists(path):path=str(data.get("fallback",""))
		if ResourceLoader.exists(path):body.get_node("Art").texture=load(path)
		body.get_node("Risk").add_theme_color_override("font_color",Design.MUTED)
		body.get_node("Reward").add_theme_color_override("font_color",Design.ACCENT)
		var id:=str(data.id)
		body.get_node("Select").pressed.connect(func():_choose("difficulty",id))
		body.get_node("Select").set_meta("difficulty",id)
	_make_choices($TerrainRow,content.environments,"environment")
	_make_choices($WeatherRow,content.weather,"weather")
	_make_choices($SceneRow,content.scenes,"scene")
	$Continue.pressed.connect(_continue)
	$Amphibious.pressed.connect(_choose_army)
	_refresh()
func bind(owner)->void:
	app=owner
	var saved:Dictionary=load("res://scripts/cargo_service.gd").new(app.economy).options()
	var draft:Dictionary=app.get_meta("expedition_draft",{})
	for key in selection:selection[key]=str(draft.get(key,saved.get(key,selection[key])))
	_refresh()
	call_deferred("_focus_initial")
func _focus_initial()->void:
	if app==null:return
	if not app.economy.state.get("active_run",{}).is_empty():$Continue.grab_focus();return
	for i in range(3):
		if str(content.difficulties[i].id)==str(selection.difficulty):$Cards.get_child(i).get_node("Margin/Body/Select").grab_focus();return
func _make_choices(parent:HBoxContainer,rows:Array,key:String)->void:
	for row in rows:
		var id:=str(row.id)
		var button:=Button.new();button.text=str(row.name);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.icon=Design.icon_texture(str(row.get("icon","compass")));button.expand_icon=true
		button.add_theme_constant_override("icon_max_width",22)
		for state in ["icon_normal_color","icon_hover_color","icon_pressed_color","icon_focus_color"]:button.add_theme_color_override(state,Design.MUTED)
		button.pressed.connect(func():_choose(key,id));button.set_meta("option_key",key);button.set_meta("option_value",id)
		parent.add_child(button);choices[key+":"+id]=button
func _choose(key:String,id:String)->void:
	selection[key]=id
	if app!=null:app.set_meta("expedition_draft",selection.duplicate(true))
	_refresh()
func _refresh()->void:
	var locked:bool=app!=null and not app.economy.state.get("active_run",{}).is_empty()
	for i in range(3):
		var card:PanelContainer=$Cards.get_child(i)
		var selected:=str(content.difficulties[i].id)==str(selection.difficulty)
		var style:=Design.box(Color(1,1,1,.95),5)
		if selected:style.border_color=Design.ACCENT;style.set_border_width_all(2)
		card.add_theme_stylebox_override("panel",style)
		var button:Button=card.get_node("Margin/Body/Select")
		button.text="已选择" if selected else "选择难度";button.disabled=locked
		Design.apply_button(button,selected)
	for key in choices:
		var button:Button=choices[key]
		Supply.style_tab(button,str(selection[button.get_meta("option_key")])==str(button.get_meta("option_value")))
		button.disabled=locked
	Design.apply_button($Continue,true)
	$Continue.disabled=app==null
	$Continue.text="查看当前舰队" if locked else "编成舰队"
	$Hint.text="已有航次进行中，先继续或结束当前行动。" if locked else "搜索残骸 → 选择装载 → 及时撤离"
	if app!=null and not locked:
		var task:Dictionary=Meta.new(app.economy).mission({"kind":"salvage","id":selection.difficulty})
		$Hint.text="消耗 %d 体力 · 默认自动搜索、装货与撤离 · 随时接管"%int(task.get("cost_stamina",0))
func _continue()->void:
	if app==null:return
	if not app.economy.state.get("active_run",{}).is_empty():app.show_page("formation");return
	if not app.economy.has_method("set_salvage_options"):
		app.notify({"ok":false,"message":"远征准备接口尚未就绪"});return
	var response:Dictionary=app.economy.set_salvage_options(selection)
	if not bool(response.get("ok",false)):app.notify(response);return
	app.show_page("formation")

func _choose_army()->void:
	if app==null:return
	load("res://scripts/army_loadout.gd").open(app,func():
		var service=load("res://scripts/amphibious_expedition_service.gd").new(app.economy)
		$Amphibious.text="随舰陆军 · %d连"%service.choices().size())
