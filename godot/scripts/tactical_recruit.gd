@tool
extends Control
const Service=preload("res://scripts/home_service.gd")
const Design=preload("res://scripts/ui_design.gd")
const TypeToken=preload("res://scripts/tactical_type_token.gd")
@export var use_default_styles:bool=true
@export_file("*.json") var content_path:String="res://data/tactical-art-v2.json"
var app
var service
@export var focus_id:String="MCP-088"
var results:Array=[]
var result_index:int=0
var reveal:Control
func _ready()->void:
	if use_default_styles:theme=Design.theme()
	$Layout/Actions/DrawOne.pressed.connect(func():_draw_units(1))
	$Layout/Actions/DrawTen.pressed.connect(func():_draw_units(10))
	$Layout/Actions/Archive.pressed.connect(_archive)
	$Layout/Probability.pressed.connect(_probability)
	var replay:=Button.new();replay.name="ReplayCommittedDraw";replay.text="回看上次同步";replay.custom_minimum_size.y=52;$Layout.add_child(replay);Design.apply_button(replay);replay.pressed.connect(_replay_draw)
	replay.anchor_left=.24;replay.anchor_top=.90;replay.anchor_right=.41;replay.anchor_bottom=.958
	for node in $Layout.get_children():
		if node is Label:node.add_theme_color_override("font_color",Color("f0f2f2") if str(node.name) in ["Title","Name"] else Color("b4c3cc"))
	if use_default_styles:
		for button in [$Layout/Actions/DrawOne,$Layout/Actions/DrawTen,$Layout/Actions/Archive,$Layout/Probability]:Design.apply_button(button,button==$Layout/Actions/DrawTen)
	if Engine.is_editor_hint() and FileAccess.file_exists(content_path):
		var content:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(content_path))
		for row in content.get("units",[]):
			if str(row.get("id",""))==focus_id:_show_portrait(row);break
func bind(owner)->void:
	app=owner;service=app.home if app.get("home")!=null else Service.new(app.economy)
	load("res://scripts/banner_design.gd").chrome(app,self,"战术协议")
	refresh()
func refresh()->void:
	if service==null:return
	$Layout/Title.text="群星协议"
	$Layout/Subtitle.text="回应这道信号，一起上岸。"
	$Layout/Balance.text="协议券 %d    元词 %d"%[int(service.state().tickets),int(app.economy.state.wallet.get("origins",0))]
	var pool:Array=_pool()
	$Layout/Hint.text="%d / %d 已收录 · 按连队投送"%[service.state().units.size(),pool.size()]
	$Layout/Probability.text="概率与保底 · %d个编制"%pool.size()
	for child in $Layout/FeaturedScroll/Featured.get_children():$Layout/FeaturedScroll/Featured.remove_child(child);child.queue_free()
	for row in pool:
		var id:String=str(row.id);var choice:=Button.new();choice.name="Recruit_"+id;choice.text=str(row.get("codename",row.name));choice.custom_minimum_size=Vector2(250,92);choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL;Design.apply_button(choice,id==focus_id);$Layout/FeaturedScroll/Featured.add_child(choice)
		var portrait_path:String=str(row.get("portrait",""));var picture:Texture2D=load(portrait_path) if ResourceLoader.exists(portrait_path) else null
		choice.icon=load("res://scripts/story_actor_layout.gd").portrait(picture,id);choice.expand_icon=true;choice.add_theme_constant_override("icon_max_width",72);choice.add_theme_font_size_override("font_size",21)
		choice.pressed.connect(func():focus_id=id;refresh())
	_show_portrait(service.latest_unit(focus_id))
	var disabled:bool=not app.economy.state.active_run.is_empty() or not bool(service.state().unlocked)
	$Layout/Actions/DrawOne.disabled=disabled;$Layout/Actions/DrawTen.disabled=disabled
	$Layout/ReplayCommittedDraw.visible=not service.state().get("last_draw",[]).is_empty()
func _pool()->Array:return service.latest_units() if not service.latest_cards().is_empty() else service.released()
func _show_portrait(row:Dictionary)->void:
	var path:String=str(row.get("portrait",""))
	$Portrait.texture=load(path) if ResourceLoader.exists(path) else null
	$Layout/Name.text=str(row.get("codename",row.get("name","")))
	$Layout/Designation.text=str(row.get("designation",""))
	$Layout/Description.text=("档案预览 · 当前不进入招募\n" if not bool(row.get("released",false)) else "")+str(row.get("description",""))+"\n\n编制上限 %d · 按连队投送"%int(row.get("personnel_cap",1000))
	if service!=null and not service.latest_profile(str(row.get("id",""))).is_empty():$Layout/Description.text=service.latest_combat_label(str(row.id))+"\n\n本次先遣 %d连 × %d身体"%[int(row.get("company_count",0)),int(row.get("personnel_per_company",0))]
func _draw_units(count:int)->void:
	if service==null or is_instance_valid(reveal):return
	var response:Dictionary=service.draw_units(count,"home-ui-%d"%(int(service.state().draw_sequence)+1))
	if not response.get("ok",false):app.notify(response);return
	results=response.results;result_index=0;refresh();_result()
func _result()->void:
	if results.is_empty():return
	if is_instance_valid(reveal):return
	reveal=load("res://scenes/ui/protocol_reveal.tscn").instantiate();reveal.name="ProtocolReveal";add_child(reveal);reveal.bind(app,results)
	reveal.finished.connect(func():results.clear();reveal=null;refresh())
func _replay_draw()->void:
	if service==null or is_instance_valid(reveal):return
	results=service.state().get("last_draw",[]).duplicate(true);_result()
func _probability()->void:
	if service==null:return
	var layer:Control=app.open_modal("协议招募 · 公开规则")
	var pool:Array=_pool();app.label(layer,"%d个编制 · 每支等概率1/%d"%[pool.size(),pool.size()],385,225,815,55,29,Design.INK)
	app.label(layer,"每次消耗1协议券，券不足时消耗160元词。连续19次未收录新核心，下次保证一支未收录人格。全部收录后，重复转换10协议片，不增加重复兵力。",385,300,815,140,23,Design.MUTED)
	var lines:Array[String]=[]
	for row in pool:lines.append(str(row.get("codename",row.name)))
	app.label(layer,"   ·   ".join(lines),385,465,815,125,20,Design.INK)
	app.label(layer,"所有编制均等概率；稀有度标签不改变当前抽取概率。",385,610,815,60,21,Design.MUTED)
func _archive()->void:
	if service==null:return
	var layer:Control=app.open_modal("战术人格档案 · %d个编制"%_pool().size())
	var scroll:=ScrollContainer.new();app.place(scroll,layer,355,220,890,480)
	var grid:=GridContainer.new();grid.columns=4;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grid.add_theme_constant_override("h_separation",12);grid.add_theme_constant_override("v_separation",12);scroll.add_child(grid)
	for row in _pool():
		var id:String=str(row.id);var button:=Button.new();button.custom_minimum_size=Vector2(205,260);grid.add_child(button);Design.apply_button(button,service.state().units.has(id))
		var box:=VBoxContainer.new();button.add_child(box);box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);box.offset_left=8;box.offset_right=-8;box.offset_top=8;box.offset_bottom=-8;box.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var art:=TextureRect.new();art.custom_minimum_size.y=190;art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;art.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var path:String=str(row.get("portrait",""));art.texture=load(path) if ResourceLoader.exists(path) else null;box.add_child(art)
		var token:=TypeToken.new();token.role=str(row.get("role","marine"));button.add_child(token);token.position=Vector2(10,10);token.size=Vector2(50,34);token.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var name_label:=Label.new();name_label.text=str(row.name);name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;name_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;box.add_child(name_label)
		var status:=Label.new();status.text="已收录" if service.state().units.has(id) else "未收录" if bool(row.get("released",false)) else "后续整编";status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;status.mouse_filter=Control.MOUSE_FILTER_IGNORE;box.add_child(status)
		button.pressed.connect(func():focus_id=id;app.close_modal();_show_portrait(service.latest_unit(id)))
