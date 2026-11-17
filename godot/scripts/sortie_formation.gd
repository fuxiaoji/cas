@tool
extends Control
## Unlimited saved fleets. All membership, duplicate checks and launch charging
## remain with FleetManager and Economy, shared by mouse, touch and keyboard.
const Design=preload("res://scripts/ui_design.gd")
const Art=preload("res://scripts/character_art.gd")
const ShipCard=preload("res://scripts/sortie_ship_card.gd")
@export_range(200,320,4) var fleet_panel_width:float=236
@export_range(240,360,4) var summary_panel_width:float=292
@export var ship_card_extent:Vector2=Vector2(108,136)
var app
var shell:VBoxContainer
var fleet_list:VBoxContainer
var member_grid:GridContainer
var bank_grid:GridContainer
var title:Label
var count_label:Label
var summary:Label
var status:Label
var launch:Button
var current:Dictionary={}
var roster:Dictionary={}
var bank_search:String=""
var touch_layer:Control
func _ready()->void:
	if Engine.is_editor_hint():
		theme=Design.theme();_build();launch.disabled=true;summary.text="编队和补给数据由账号实时提供。"
func initialize(owner)->void:
	app=owner;theme=Design.theme();_build();_build_touch_drag();refresh()
func _build_touch_drag()->void:
	touch_layer=load("res://scripts/littoral_drag_layer.gd").new();touch_layer.name="CompositionTouchDrag";touch_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);app.page.add_child(touch_layer)
	touch_layer.dropped.connect(func(payload:Dictionary,point:Vector2):
		var identity:String=str(payload.get("identity",""))
		if member_grid.get_parent().get_global_rect().has_point(point):_add(identity)
		elif bank_grid.get_parent().get_global_rect().has_point(point):_remove(identity))
	touch_layer.clicked.connect(func(payload:Dictionary):
		var identity:String=str(payload.get("identity",""))
		if current.get("ships",[]).has(identity):_remove(identity)
		else:_add(identity))
func _input(event:InputEvent)->void:
	if not is_instance_valid(app) or not is_visible_in_tree() or is_instance_valid(app.modal) or _locked():return
	if not event is InputEventScreenTouch or not event.pressed:return
	if touch_layer==null or not touch_layer.payload.is_empty():return
	for grid in [member_grid,bank_grid]:
		if not grid.get_parent().get_global_rect().has_point(event.position):continue
		for card in grid.get_children():
			if not card.get_global_rect().has_point(event.position) or str(card.identity).is_empty():continue
			var identity:String=str(card.identity);var row:Dictionary=roster.get(identity,{})
			touch_layer.arm({"identity":identity,"name":str(row.get("name",identity)),"texture":Art.texture(str(row.get("portrait","")))},event.position,event.index);get_viewport().set_input_as_handled();return
func _label(parent:Node,text:String,point_size:int=20)->Label:
	var result:=Label.new();result.text=text;result.add_theme_font_size_override("font_size",point_size);result.add_theme_color_override("font_color",Design.INK);parent.add_child(result);return result
func _button(parent:Node,text:String,action:Callable,primary:bool=false)->Button:
	var result:=Button.new();result.text=text;result.custom_minimum_size.y=48;Design.apply_button(result,primary);result.pressed.connect(action);parent.add_child(result);return result
func _panel(parent:Node)->PanelContainer:
	var result:=PanelContainer.new();result.add_theme_stylebox_override("panel",Design.box(Color("f4f6ed"),14,Color("c4d7cd")));parent.add_child(result);return result
func _stack(parent:Node)->VBoxContainer:
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",10);box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(box);return box
func _scroll(parent:Node)->ScrollContainer:
	var box:=ScrollContainer.new();box.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;box.size_flags_vertical=Control.SIZE_EXPAND_FILL;box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(box);return box
func _build()->void:
	name="SortieFormation";shell=_stack(self);shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var header:=HBoxContainer.new();header.add_theme_constant_override("separation",12);shell.add_child(header)
	title=_label(header,"舰队编成",28);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_button(header,"＋ 新编队",func():_name(true))
	_button(header,"改名",func():_name(false))
	_button(header,"删除编队",_erase)
	var body:=HBoxContainer.new();body.size_flags_vertical=Control.SIZE_EXPAND_FILL;body.add_theme_constant_override("separation",16);shell.add_child(body)
	var fleet_panel:PanelContainer=_panel(body);fleet_panel.custom_minimum_size.x=fleet_panel_width
	var fleet_box:VBoxContainer=_stack(fleet_panel);_label(fleet_box,"选择随行编队",21);fleet_list=_stack(_scroll(fleet_box))
	var center:=VBoxContainer.new();center.size_flags_horizontal=Control.SIZE_EXPAND_FILL;center.add_theme_constant_override("separation",8);body.add_child(center)
	var selected_panel:PanelContainer=_panel(center);selected_panel.custom_minimum_size.y=218
	var selected_box:VBoxContainer=_stack(selected_panel);count_label=_label(selected_box,"拖舰娘到编队 · 点选也可加入 / 移出",19)
	var member_scroll:ScrollContainer=_scroll(selected_box);member_grid=GridContainer.new();member_grid.name="SelectedFleetShips";member_grid.columns=6;member_grid.add_theme_constant_override("h_separation",8);member_grid.add_theme_constant_override("v_separation",8);member_scroll.add_child(member_grid)
	var bank_panel:PanelContainer=_panel(center);bank_panel.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var bank_box:VBoxContainer=_stack(bank_panel)
	var search:=LineEdit.new();search.name="AvailableShipSearch";search.placeholder_text="搜索舰娘 / 舰种";search.custom_minimum_size.y=44;bank_box.add_child(search);search.text_changed.connect(func(value:String):bank_search=value;_refresh_bank())
	bank_grid=GridContainer.new();bank_grid.name="AvailableShips";bank_grid.columns=6;bank_grid.add_theme_constant_override("h_separation",8);bank_grid.add_theme_constant_override("v_separation",8);_scroll(bank_box).add_child(bank_grid)
	var right_panel:PanelContainer=_panel(body);right_panel.custom_minimum_size.x=summary_panel_width
	var right:VBoxContainer=_stack(right_panel);_label(right,"本次航行",25)
	summary=_label(right,"",21);summary.name="SortieCargoSummary";summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	status=_label(right,"",18);status.name="SortieValidation";status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var spacer:=Control.new();spacer.size_flags_vertical=Control.SIZE_EXPAND_FILL;right.add_child(spacer)
	_button(right,"装载与货舱",func():load("res://scripts/cargo_presentation.gd").open_loadout(app);_refresh_after_modal()).name="SortieLoadout"
	_button(right,"弹种与备雷",func():load("res://scripts/munition_setup.gd").open(app);_refresh_after_modal()).name="SortieMunitions"
	_button(right,"随舰陆军",_army).name="SortieArmy"
	launch=_button(right,"确认出航",func():app.launch(false),true);launch.name="ConfirmSortie";launch.custom_minimum_size.y=64
	_button(right,"基础打捞 · 借用舰",func():app.launch(true))
	resized.connect(_layout_columns)
func _layout_columns()->void:
	if not is_instance_valid(member_grid):return
	var columns:int=clampi(int((size.x-fleet_panel_width-summary_panel_width-70)/(ship_card_extent.x+8)),2,8);member_grid.columns=columns;bank_grid.columns=columns
func _clear(parent:Node)->void:
	for child in parent.get_children():parent.remove_child(child);child.queue_free()
func refresh()->void:
	current=app.fleets.active();roster.clear()
	for raw in app.economy.roster():
		if bool(raw.get("playable",false)):roster[str(raw.id)]=Art.visual_card(raw,app.cards)
	title.text=str(current.get("name","舰队编成"));count_label.text="%d 艘已编入 · 拖入添加，拖到舰库移出"%current.get("ships",[]).size()
	_clear(fleet_list)
	for fleet in app.fleets.rows():
		var id:String=str(fleet.id);var line:=HBoxContainer.new();fleet_list.add_child(line)
		var edit:Button=_button(line,str(fleet.name)+"\n%d 艘"%fleet.ships.size(),func():_apply(app.fleets.activate(id)),id==str(current.get("id","")));edit.name="EditFleet_"+id;edit.custom_minimum_size=Vector2(166,70);edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var take:=CheckBox.new();take.name="TakeFleet_"+id;take.tooltip_text="随行出航";take.button_pressed=app.fleets.selected(id);take.disabled=fleet.ships.is_empty() or _locked();take.custom_minimum_size=Vector2(48,48);take.toggled.connect(func(on:bool):_apply(app.fleets.select(id,on)));line.add_child(take)
	_clear(member_grid)
	for identity in current.get("ships",[]):
		if roster.has(str(identity)):
			var card:Button=_ship(roster[str(identity)],true);card.get_child(0).name="FleetSlot%d"%member_grid.get_child_count();member_grid.add_child(card)
	var add=ShipCard.new();add.name="AddFleetMember";add.text="＋\n拖到这里";add.drop_enabled=not _locked();add.drag_enabled=false;add.custom_minimum_size=ship_card_extent;Design.apply_button(add);member_grid.add_child(add);add.ship_dropped.connect(_add);add.pressed.connect(func():var search:Control=find_child("AvailableShipSearch",true,false);search.grab_focus())
	_refresh_bank();_refresh_summary();_layout_columns()
func _ship(row:Dictionary,member:bool)->Button:
	var identity:String=str(row.id);var choice=ShipCard.new();choice.name=("FleetMember_" if member else "Available_")+identity;choice.identity=identity;choice.drop_enabled=not _locked();choice.drag_enabled=not _locked();choice.disabled=_locked();choice.custom_minimum_size=ship_card_extent;choice.tooltip_text=str(row.name)+" · "+str(row.get("type",""))+"\n"+("点击移出" if member else "点击加入当前编队");Design.apply_button(choice,member)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",2);box.mouse_filter=Control.MOUSE_FILTER_IGNORE;choice.add_child(box);box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);box.offset_left=4;box.offset_right=-4;box.offset_top=4;box.offset_bottom=-4
	var portrait:=TextureRect.new();portrait.custom_minimum_size=Vector2(96,82);portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;portrait.texture=load("res://scripts/story_actor_layout.gd").portrait(Art.texture(str(row.get("portrait",""))),identity);portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE;box.add_child(portrait)
	var caption:Label=_label(box,str(row.get("name",identity)),16);caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;caption.mouse_filter=Control.MOUSE_FILTER_IGNORE;caption.clip_text=true
	var tag:Label=_label(box,str(row.get("type","")),13);tag.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;tag.mouse_filter=Control.MOUSE_FILTER_IGNORE
	choice.pressed.connect(func():_remove(identity) if member else _add(identity));choice.ship_dropped.connect(_add if member else _remove)
	choice.touch_armed.connect(func(id:String,point:Vector2,pointer:int):touch_layer.arm({"identity":id,"name":str(row.name),"texture":portrait.texture},point,pointer))
	return choice
func _refresh_bank()->void:
	_clear(bank_grid)
	for row in roster.values():
		if current.get("ships",[]).has(str(row.id)):continue
		if not bank_search.is_empty() and not (str(row.name)+str(row.get("type",""))).to_lower().contains(bank_search.to_lower()):continue
		bank_grid.add_child(_ship(row,false))
	# Empty banks still accept removing a member by dropping it here.
	var remove=ShipCard.new();remove.name="RemoveMemberDropZone";remove.text="移出编队\n拖到这里";remove.drop_enabled=not _locked();remove.drag_enabled=false;remove.custom_minimum_size=ship_card_extent;Design.apply_button(remove);bank_grid.add_child(remove);remove.ship_dropped.connect(_remove)
func _refresh_summary()->void:
	var groups:Array=app.fleets.groups();var preview:Dictionary=app.economy.preview_sortie(20261114,false,{"kind":"salvage","id":str(app.economy.state.get("salvage_options",{}).get("difficulty","calm"))})
	var cargo:Dictionary=app.economy.cargo_budget();var costs:Dictionary=app.economy.formation_preview();var fleet:Array=[]
	for identity in app.economy.formation:
		if roster.has(str(identity)):fleet.append(roster[str(identity)])
	var fuel:Dictionary=load("res://scripts/fuel_service.gd").new(app.economy).preview(fleet)
	summary.text="%d 个编队 · %d 艘\n\n货舱 %d 格 · %.1f 吨\n弹药 %d 份\n油料 %d 单位"%[groups.size(),app.economy.formation.size(),int(cargo.cells),float(cargo.max_kg)/1000.0,int(costs.ammo_required),int(fuel.initial)]
	if preview.get("ok",false):summary.text+="\n体力 %d"%int(preview.get("mission",{}).get("cost_stamina",0))
	status.text="已就绪 · 出航时结算" if preview.get("ok",false) else str(preview.get("message","请安排随行舰队"));status.add_theme_color_override("font_color",Design.MUTED if preview.get("ok",false) else Color("a94f3b"));launch.disabled=not preview.get("ok",false) or _locked()
func _locked()->bool:return not app.economy.state.get("active_run",{}).is_empty()
func _refresh_after_modal()->void:
	if is_instance_valid(app.modal):app.modal.tree_exited.connect(_refresh_summary,CONNECT_ONE_SHOT)
func _add(identity:String)->void:
	var members:Array=current.get("ships",[]).duplicate();if members.has(identity):return
	members.append(identity);_apply(app.fleets.set_members(members))
func _remove(identity:String)->void:
	var members:Array=current.get("ships",[]).duplicate();members.erase(identity);_apply(app.fleets.set_members(members))
func _apply(response:Dictionary)->void:
	if not response.get("ok",false):app.notify(response)
	refresh()
func _name(creating:bool)->void:
	var layer:Control=app.open_modal("新建编队" if creating else "舰队名称");var field:=LineEdit.new();field.max_length=32;field.placeholder_text="舰队名称";field.text="" if creating else str(current.get("name",""));app.place(field,layer,390,285,800,65)
	app.button(layer,"保存",840,595,350,65,func():var response:Dictionary=app.fleets.create(field.text) if creating else app.fleets.rename(str(current.id),field.text);app.close_modal();_apply(response),true);field.grab_focus()
func _erase()->void:
	app.confirm_action("删除此编队？舰娘仍留在舰库。",func():_apply(app.fleets.erase(str(current.get("id","")))))
func _army()->void:
	load("res://scripts/army_loadout.gd").open(app,_refresh_summary)
