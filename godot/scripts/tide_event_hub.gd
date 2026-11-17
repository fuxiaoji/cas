@tool
extends Control
const Design=preload("res://scripts/ui_design.gd")
const Service=preload("res://scripts/tide_event_service.gd")
@export_file("*.json") var content_path:String="res://data/tide-event-v1.json"
@export_group("Presentation")
## Disable before editing theme overrides to keep authored fonts, colors and panels.
@export var use_default_styles:bool=true
@export var use_content_headings:bool=true
@export var use_content_artwork:bool=true
@export var responsive_shop_columns:bool=true
@export_group("Editor Preview")
@export_enum("overview","story","shop") var preview_tab:String="overview":
	set(value):
		preview_tab=value
		if Engine.is_editor_hint() and is_node_ready():_render(preview_tab)
var app
var content:Dictionary
var body:VBoxContainer:
	get:return $BriefScroll/Body
func _ready()->void:
	if theme==null:theme=Design.theme()
	content=JSON.parse_string(FileAccess.get_file_as_string(content_path))
	if use_default_styles:
		$Title.add_theme_font_override("font",Design.font(600));$Title.add_theme_color_override("font_color",Design.INK);$Subtitle.add_theme_color_override("font_color",Design.MUTED)
	if use_content_headings:$Title.text=str(content.title);$Subtitle.text=str(content.subtitle)
	if use_content_artwork and ResourceLoader.exists(str(content.hero)):$Hero.texture=load(str(content.hero))
	resized.connect(_fit_shop)
	_fit_shop()
	if Engine.is_editor_hint():_render(preview_tab)
func _fit_shop()->void:
	if not responsive_shop_columns:return
	$ShopScroll/Products.columns=3 if size.x>=1500 else 2
func bind(owner)->void:
	app=owner;Service.new(app.economy).ensure()
	$Tabs/Overview.pressed.connect(func():app.set_meta("tide_tab","overview");_render("overview"))
	$Tabs/Story.pressed.connect(func():app.set_meta("tide_tab","story");_render("story"))
	$Tabs/Shop.pressed.connect(func():app.set_meta("tide_tab","shop");_render("shop"))
	_render(str(app.get_meta("tide_tab","overview")))
func _label(parent:Node,text:String,size:int=22)->Label:
	var node:=Label.new();node.text=text;node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	if use_default_styles:node.add_theme_color_override("font_color",Design.INK);node.add_theme_font_size_override("font_size",size)
	parent.add_child(node);return node
func _action(parent:Node,text:String,callback:Callable,primary:bool=false)->Button:
	var b:=Button.new();b.text=text;b.custom_minimum_size.y=55
	if use_default_styles:Design.apply_button(b,primary)
	b.disabled=app==null;b.pressed.connect(callback);parent.add_child(b);return b
func _render(tab:String)->void:
	for node in body.get_children():body.remove_child(node);node.queue_free()
	for node in $ShopScroll/Products.get_children():$ShopScroll/Products.remove_child(node);node.queue_free()
	if use_content_headings:$Subtitle.text=str(content.subtitle)
	$BriefScroll.visible=tab!="shop";$ShopScroll.visible=tab=="shop";$Hero.visible=tab!="shop"
	if use_default_styles:
		for button in $Tabs.get_children():Design.apply_button(button,str(button.name).to_lower()==tab)
	if tab=="shop":_shop();return
	if tab=="story":
		_label(body,"一座天文台，两支归航的船队。",27)
		_label(body,"潮汐环放大了舰装的力量，也唤醒了水底的看守。你们只需要为流民船队守住三分钟。")
		_action(body,"序幕 · 不属于天空的月亮",func():app.set_meta("tide_story_ending",false);app.show_page("tide_story"),true)
		var ending:=_action(body,"尾声 · 海记得我们的名字",func():app.set_meta("tide_story_ending",true);app.show_page("tide_story"))
		ending.disabled=app==null or int(app.economy.state.get("tide_event_v1",{}).get("wins",0))<1
		return
	_label(body,"单舰启航 · 援军成阵",27)
	_label(body,"自动扫射，拾取回响强化舰装。\n呼叫伙伴，逐步集结六舰。",22)
	var selection:=HBoxContainer.new();selection.name="Deployment";selection.add_theme_constant_override("separation",12);body.add_child(selection)
	var ships:=OptionButton.new();ships.name="EventShip";ships.custom_minimum_size.y=48;ships.size_flags_horizontal=Control.SIZE_EXPAND_FILL;selection.add_child(ships)
	var owned:Array=app.economy.roster() if app!=null else [{"id":"preview","name":"弗莱彻"}]
	for row in owned:ships.add_item(str(row.name));ships.set_item_metadata(ships.item_count-1,str(row.id))
	var difficulty:=OptionButton.new();difficulty.name="EventDifficulty";difficulty.add_item("回响初醒");difficulty.add_item("深潮共鸣");difficulty.custom_minimum_size.y=48;difficulty.size_flags_horizontal=Control.SIZE_EXPAND_FILL;selection.add_child(difficulty)
	var reserves:=_action(body,"",func():_reserve_picker(str(ships.get_item_metadata(ships.selected))))
	reserves.name="ReserveFormation"
	var refresh_reserves:Callable=func():reserves.text="援军阵容 · %d名待命"%(reserve_ids(str(ships.get_item_metadata(ships.selected))).size() if ships.selected>=0 else 0)
	ships.item_selected.connect(func(_index):refresh_reserves.call())
	refresh_reserves.call()
	var launch:=_action(body,"驶入回响海域",func():app.launch_tide(str(ships.get_item_metadata(ships.selected)),"hard" if difficulty.selected==1 else "normal",reserve_ids(str(ships.get_item_metadata(ships.selected)))),true)
	launch.disabled=app==null or owned.is_empty() or not app.economy.state.get("active_run",{}).is_empty()
	reserves.disabled=app==null or owned.size()<2
	_label(body,"本局强化独立生效 · 不消耗港口油弹",17)
func reserve_ids(primary:String)->Array:
	var ids:Array=[]
	if app==null:return ids
	var chosen:Variant=app.get_meta("tide_reserves") if app.has_meta("tide_reserves") else null
	if chosen is Array:
		for id in chosen:
			if id is String and id!=primary and app.economy.state.owned.has(id) and not ids.has(id) and ids.size()<Service.MAX_RESERVES:ids.append(id)
	else:
		for row in app.economy.roster():
			if str(row.id)!=primary and ids.size()<Service.MAX_RESERVES:ids.append(str(row.id))
	return ids
func _reserve_picker(primary:String)->void:
	if app==null:return
	var selected:Array=reserve_ids(primary)
	var layer:Control=app.open_modal("援军阵容")
	var scroll:=ScrollContainer.new();scroll.name="ReserveScroll";scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;app.place(scroll,layer,370,225,860,400)
	var grid:=GridContainer.new();grid.name="Crew";grid.columns=6;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grid.add_theme_constant_override("h_separation",12);grid.add_theme_constant_override("v_separation",12);scroll.add_child(grid)
	var fit_grid:Callable=func():grid.columns=clampi(int((scroll.size.x+12.0)/139.0),2,6)
	scroll.resized.connect(fit_grid);fit_grid.call()
	var count:Label=app.label(layer,"",375,637,470,40,21,Design.MUTED)
	var refresh_count:Callable=func():count.text="已选 %d名 · 局内呼叫"%selected.size()
	refresh_count.call()
	for row in app.economy.roster():
		var id:String=str(row.id)
		if id==primary:continue
		var choice:=Button.new();choice.name="Reserve_"+id;choice.toggle_mode=true;choice.button_pressed=selected.has(id);choice.custom_minimum_size=Vector2(127,157);choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		Design.apply_button(choice,selected.has(id));grid.add_child(choice)
		var body_box:=VBoxContainer.new();body_box.mouse_filter=Control.MOUSE_FILTER_IGNORE;choice.add_child(body_box);body_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);body_box.offset_left=5;body_box.offset_right=-5;body_box.offset_top=5;body_box.offset_bottom=-5
		var art:=TextureRect.new();art.custom_minimum_size.y=112;art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;art.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var identity:Dictionary=app.cards.get(id,{})
		var projection:Dictionary=load("res://scripts/character_art.gd").projection(identity)
		art.texture=load("res://scripts/character_art.gd").texture(str(projection.get("path","")));body_box.add_child(art)
		var caption:=Label.new();caption.text=str(row.name);caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;caption.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;caption.add_theme_font_size_override("font_size",18);caption.mouse_filter=Control.MOUSE_FILTER_IGNORE;body_box.add_child(caption)
		choice.toggled.connect(func(enabled:bool):
			if enabled and not selected.has(id):
				if selected.size()>=Service.MAX_RESERVES:choice.set_pressed_no_signal(false);return
				selected.append(id)
			elif not enabled:selected.erase(id)
			Design.apply_button(choice,enabled);refresh_count.call())
	app.button(layer,"确认阵容",940,650,290,60,func():
		app.set_meta("tide_reserves",selected.duplicate());app.close_modal()
		var reserve_button:Button=body.get_node_or_null("ReserveFormation")
		if reserve_button!=null:reserve_button.text="援军阵容 · %d名待命"%reserve_ids(primary).size(),true)
	if grid.get_child_count()>0:grid.get_child(0).grab_focus()
func _shop()->void:
	var balance:int=int(app.economy.state.wallet.get("tide_tokens",0)) if app!=null else 0
	if use_content_headings:$Subtitle.text="回响徽片 %d · 战斗结束后结算，首次通关另得160元词"%balance
	for raw in content.shop:
		var product:Dictionary=raw;var card:=PanelContainer.new();card.custom_minimum_size=Vector2(390,230);card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if use_default_styles:card.add_theme_stylebox_override("panel",Design.box(Color("e7eff0"),5))
		$ShopScroll/Products.add_child(card)
		var margin:=MarginContainer.new()
		for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,18)
		card.add_child(margin);var column:=VBoxContainer.new();column.add_theme_constant_override("separation",10);margin.add_child(column)
		var icon:=TextureRect.new();icon.texture=Design.icon_texture(str(product.icon));icon.custom_minimum_size.y=45;icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;column.add_child(icon)
		_label(column,str(product.name)+" ×%d"%int(product.amount),23)
		var bought:int=int(app.economy.state.tide_event_v1.purchases.get(str(product.id),0)) if app!=null else 0
		_label(column,"剩余 %d 份"%maxi(0,int(product.limit)-bought),18)
		var buy:=_action(column,"%d 徽片 · 兑换"%int(product.cost),func():app.notify(Service.new(app.economy).purchase(str(product.id)));_render("shop"))
		buy.disabled=app==null or balance<int(product.cost) or bought>=int(product.limit) or not app.economy.state.get("active_run",{}).is_empty()
