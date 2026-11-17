@tool
extends Control
const Service=preload("res://scripts/home_service.gd")
const Design=preload("res://scripts/ui_design.gd")
const Art=preload("res://scripts/character_art.gd")
const FacilityArt=preload("res://scripts/home_building_art.gd")
const TypeToken=preload("res://scripts/tactical_type_token.gd")
const HomeActor=preload("res://scripts/tactical_sprite.gd")
const ShipResident=preload("res://scripts/home_ship_resident.gd")
const DailyArt=preload("res://scripts/home_daily_art.gd")
@export var use_default_styles:bool=true
@export var preview_seed:int=1387249
var app
var service
var selected_cell:Vector2i=Vector2i(-1,-1)
var building_kind:String=""
var naval_selection:Array=[]
var unit_selection:Array=[]
var transport_preset:String="balanced"
var npc_index:int=0
var company_choices:Dictionary={}
var deployment_status:Label
var deployment_button:Button
var deployment_mode:String="raid"
var transport_list:VBoxContainer
var island_actors:Dictionary={}
var actor_layer:Control
var actor_clock:float=0
var actor_signature:String=""
var transport_art:Dictionary={}
var ship_residents:Dictionary={}
var ship_resident_layer:Control
var ship_resident_signature:String=""
@onready var canvas:Control=$Layout/Main/Island
@onready var body:VBoxContainer=$Layout/Context/Body

func _ready()->void:
	if use_default_styles:theme=Design.theme()
	if not Engine.is_editor_hint() and preload("res://scripts/coastal_map_settings.gd").enabled():
		$Layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		$Layout/Main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		$Layout/Top.anchor_top=.105;$Layout/Top.anchor_bottom=.19
		$Layout/Hint.add_theme_color_override("font_color",Color("fff4d5"))
	canvas.island_seed=preview_seed;canvas.cell_selected.connect(_cell);canvas.placement_changed.connect(_placement_changed);canvas.camera_changed.connect(_position_context)
	canvas.collection_requested.connect(func(_id:String):_collect())
	$Layout/Top/Collect.pressed.connect(func():_collect())
	$Layout/Top/ResetView.pressed.connect(func():canvas.toggle_overview())
	$Layout/Top/Training.pressed.connect(_training_lessons)
	$Layout/Top/IslandAffairs.pressed.connect(func():open_conflicts())
	$Layout/Bottom/Build.pressed.connect(_show_build_tray)
	$Layout/Bottom/Recruit.pressed.connect(func():app.show_page("home_recruit") if app!=null else null)
	$Layout/Bottom/Units.pressed.connect(_units)
	$Layout/Bottom/Garrison.pressed.connect(_garrison)
	$Layout/Bottom/Sortie.pressed.connect(_sortie)
	$Layout/Placement/Body/Cancel.pressed.connect(_cancel_placement)
	$Layout/Placement/Body/Confirm.pressed.connect(_confirm_placement)
	if use_default_styles:
		for path in ["Notice","Context","Tray","Placement"]:$Layout.get_node(path).add_theme_stylebox_override("panel",_panel())
		for name in ["Build","Recruit","Units","Garrison","Sortie"]:_dock_button($Layout/Bottom.get_node(name),str({"Build":"gear","Recruit":"recruit","Units":"crew","Garrison":"fleet","Sortie":"sortie"}[name]),name=="Sortie")
		Design.apply_button($Layout/Top/Collect,true);Design.apply_button($Layout/Top/ResetView)
		Design.apply_button($Layout/Top/Training)
		Design.apply_button($Layout/Top/IslandAffairs)
		$Layout/Top/ResetView.icon=Design.icon_texture("compass");$Layout/Top/ResetView.modulate=Color("dbeee7");$Layout/Top/ResetView.add_theme_color_override("icon_normal_color",Design.INK)
		$Layout/Top/ResetView.expand_icon=true;$Layout/Top/ResetView.add_theme_constant_override("icon_max_width",36)
		$Layout/Top/ResetView.tooltip_text="切换全岛与主基地"
		Design.apply_button($Layout/Placement/Body/Confirm,true);Design.apply_button($Layout/Placement/Body/Cancel)
	if Engine.is_editor_hint():canvas.observe({"seed":preview_seed,"buildings":[{"id":"preview","kind":"hq","cell":{"x":6,"y":4},"level":1}]})

func _panel()->StyleBoxFlat:
	var style:StyleBoxFlat=Design.box(Color("f6f8ec"),16,Color("b3c9ba"));style.content_margin_left=20;style.content_margin_right=20;style.content_margin_top=14;style.content_margin_bottom=14;style.shadow_color=Color(0,.12,.15,.15);style.shadow_size=8
	return style

func _dock_button(button:Button,icon:String,primary:bool)->void:
	Design.apply_button(button,primary);button.custom_minimum_size=Vector2(150,96);button.expand_icon=true;button.icon=Design.icon_texture(icon);button.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER;button.vertical_icon_alignment=VERTICAL_ALIGNMENT_TOP;button.add_theme_constant_override("icon_max_width",36);button.add_theme_constant_override("h_separation",4)
	if not primary:
		for state in ["normal","hover","pressed","focus"]:button.add_theme_stylebox_override(state,Design.box(Color("244a50") if state=="normal" else Color("36646a"),12))
		for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:button.add_theme_color_override(key,Color("f2f4df"))
	else:button.add_theme_color_override("icon_normal_color",Design.INK)

func bind(owner)->void:
	app=owner;service=app.home if app.get("home")!=null else Service.new(app.economy)
	if FileAccess.file_exists("res://data/transport-variants-v3.json"):
		var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/transport-variants-v3.json"))
		if raw is Dictionary:transport_art=raw
	refresh()

func _label(parent:Node,text:String,size:int=22)->Label:
	var label:=Label.new();label.text=text;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.add_theme_font_size_override("font_size",size);label.add_theme_color_override("font_color",Design.INK);parent.add_child(label);return label

func _button(parent:Node,text:String,callback:Callable,primary:bool=false)->Button:
	var button:=Button.new();button.text=text;button.custom_minimum_size.y=80;Design.apply_button(button,primary);button.pressed.connect(callback);parent.add_child(button);return button

func _empty(parent:Node)->void:
	for child in parent.get_children():parent.remove_child(child);child.queue_free()

func _cost(cost:Dictionary)->String:
	var parts:Array[String]=[]
	for key in cost:parts.append("%d%s"%[int(cost[key]),str(Service.RESOURCE_NAMES.get(key,key))])
	return " / ".join(parts)

func _resources(parent:Node,cost:Dictionary,owned:bool=false)->void:
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",14);parent.add_child(row)
	for key in cost:
		var icon:=TextureRect.new();icon.texture=Design.icon_texture(str({"scrap":"cargo","alloy":"gear","energy":"sun","credits":"coin","protocols":"recruit"}.get(key,"cargo")));icon.custom_minimum_size=Vector2(25,25);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.modulate=Color("497867");icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;row.add_child(icon)
		var number:Label=_label(row,str(int(cost[key])),23);number.autowrap_mode=TextServer.AUTOWRAP_OFF;number.tooltip_text=str(Service.RESOURCE_NAMES.get(key,key))
		if not owned and service!=null and int(service.state().resources.get(key,0))<int(cost[key]):number.add_theme_color_override("font_color",Color("b5533c"));number.text+=" !"

func _affordable(cost:Dictionary)->bool:
	for key in cost:
		if int(service.state().resources.get(key,0))<int(cost[key]):return false
	return true

func _blocked()->String:
	if service==null:return ""
	if not bool(service.state().unlocked):return "先完成新岛登陆，接通归航信标。"
	if not app.economy.state.active_run.is_empty():return "当前行动尚未结束，返航后即可建设。"
	return ""

func refresh()->void:
	if service==null:return
	var view:Dictionary=service.overview();_empty($Layout/Top/Resources)
	for key in ["scrap","alloy","energy"]:
		var chip:=PanelContainer.new();chip.add_theme_stylebox_override("panel",_panel());$Layout/Top/Resources.add_child(chip);_resources(chip,{key:int(view.resources[key])},true)
	canvas.observe(view)
	_refresh_island_actors(view)
	_refresh_ship_residents(view)
	var amount:int=0
	for value in view.pending.values():amount+=int(value)
	$Layout/Top/Collect.text="全收 +%d"%amount if amount>0 else "收取"
	$Layout/Top/Collect.disabled=not _blocked().is_empty() or amount<=0
	$Layout/Top/Collect.tooltip_text="当前没有待收取物资" if amount<=0 else "收取所有设施已生产物资"
	var salvage:bool=str(app.get_meta("home_battle_mode",""))=="salvage" and bool(view.unlocked)
	$Layout/Bottom/Sortie.text="遗迹" if salvage else "出航"
	_restore_hint()
	if not bool(view.unlocked):_notice("归航信标未接通","先与礁刃派遣队完成新岛登陆。","开始登陆",func():app.show_page("home_story"))
	elif not _blocked().is_empty():$Layout/Hint.text="行动进行中 · 可查看岛屿，返航后建设"
	elif not bool(view.get("drag_tutorial_completed",false)):
		if is_instance_valid(canvas.world3d):_compact_drag_hint()
		else:_notice("试试拖动指挥","拖部队上岸，再拖卡移动与呼叫舰炮。","开始拖动教学",_start_drag_lesson)
	if $Layout/Context.visible:_details()

func _refresh_island_actors(view:Dictionary)->void:
	var ids:Array=view.get("tactical_garrison",[]).duplicate()
	if ids.is_empty():
		for id in view.get("units",{}):
			if ids.size()<3:ids.append(str(id))
	var signature:String=JSON.stringify(ids)
	if signature==actor_signature:return
	actor_signature=signature
	if not is_instance_valid(actor_layer):
		actor_layer=Control.new();actor_layer.name="ResidentTacticalActors";actor_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE;actor_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);canvas.add_child(actor_layer)
	_empty(actor_layer);island_actors.clear()
	for index in range(ids.size()):
		var identity:String=str(ids[index]);var row:Dictionary=service.latest_unit(identity)
		if not DailyArt.available(row):continue
		var touch=ShipResident.new();touch.name="Resident_"+identity;touch.card=row;touch.phase=float(index)*1.71;touch.size=Vector2(80,90);touch.tooltip_text=str(row.get("codename",row.get("name",identity)))+" · 点击互动";actor_layer.add_child(touch)
		island_actors[identity]={"button":touch,"sprite":touch,"index":index,"greet_until":-1.0}
		touch.pressed.connect(func():
			island_actors[identity].greet_until=actor_clock+2.2
			app.notify({"ok":true,"message":str(row.get("codename",row.get("name",identity)))+"：岛上巡查正常，等你指挥。"}))

func _process(delta:float)->void:
	if Engine.is_editor_hint() or service==null:return
	actor_clock+=delta
	_advance_ship_residents()
	for id in island_actors:
		var entry:Dictionary=island_actors[id];var index:int=int(entry.index);var phase:float=float(index)*1.71
		if canvas.has_native_geometry():
			var resident=entry.button;var routine:Dictionary=resident.routine(actor_clock);var height:float=canvas.resident_height()
			resident.body_height=height;resident.size=Vector2(maxf(44,height*.94),maxf(55,height*1.33));resident.position=canvas.resident_position(index,false,float(routine.progress))-Vector2(resident.size.x*.5,resident.size.y-6);resident.update_motion(actor_clock,bool(routine.facing_left),bool(routine.walking));continue
		# Cosmetic patrols follow a legal, horizontal island row. No simulation or ledger state is changed.
		var row:int=3+index%3;var legal:Array=[]
		for column in range(3,9):
			var cell_center:Vector2i=Vector2i(column,row)
			if canvas.land(cell_center) and canvas.land(cell_center+Vector2i.LEFT) and canvas.land(cell_center+Vector2i.RIGHT) and canvas.land(cell_center+Vector2i.UP) and canvas.land(cell_center+Vector2i.DOWN):legal.append(column)
		if legal.is_empty():continue
		var left:float=float(legal.front());var right:float=float(legal.back())
		var resident=entry.button;var routine:Dictionary=resident.routine(actor_clock)
		var cell:Vector2=Vector2(lerpf(left,right,float(routine.progress)),row+.25)
		resident.position=canvas.point(cell)-Vector2(40,84)
		resident.update_motion(actor_clock,bool(routine.facing_left),bool(routine.walking))

func _refresh_ship_residents(view:Dictionary)->void:
	var roster:Array=[];var signature_parts:Array=[]
	for identity in view.get("garrison",[]):
		# Never use class representatives. Appearance is read from the same registry
		# as the secretary, detail page and battlefield.
		var own:Dictionary=app.cards.get(str(identity),{})
		if own.is_empty():continue
		var card:Dictionary=Art.visual_card(own,app.cards).duplicate(true)
		if not DailyArt.available(card):continue
		roster.append(card);signature_parts.append([str(identity),str(card.get("appearance_id","default")),DailyArt.sd_path(card),DailyArt.entry(str(identity)).get("frames",[]).size()])
	var signature:String=JSON.stringify(signature_parts)
	if signature==ship_resident_signature:return
	ship_resident_signature=signature
	if not is_instance_valid(ship_resident_layer):
		ship_resident_layer=Control.new();ship_resident_layer.name="ResidentShipgirls";ship_resident_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE;ship_resident_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);canvas.add_child(ship_resident_layer)
	_empty(ship_resident_layer);ship_residents.clear()
	for index in range(roster.size()):
		var card:Dictionary=roster[index];var identity:String=str(card.id);var resident=ShipResident.new()
		resident.name="ShoreLeave_"+identity;resident.card=card;resident.phase=float(index)*1.37;resident.size=Vector2(76,108);resident.tooltip_text=str(card.get("name",identity))+" · 驻防休息中";resident.set_meta("character_id",identity);resident.set_meta("appearance_id",str(card.get("appearance_id","default")));ship_resident_layer.add_child(resident)
		ship_residents[identity]={"actor":resident,"index":index}
	_advance_ship_residents()

func _advance_ship_residents()->void:
	for identity in ship_residents:
		var entry:Dictionary=ship_residents[identity];var index:int=int(entry.index);var resident=entry.actor
		if canvas.has_native_geometry():
			var routine:Dictionary=resident.routine(actor_clock);var height:float=canvas.resident_height()
			resident.body_height=height;resident.size=Vector2(maxf(44,height*.94),maxf(55,height*1.33));resident.position=canvas.resident_position(index,true,float(routine.progress))-Vector2(resident.size.x*.5,resident.size.y-6);resident.update_motion(actor_clock,bool(routine.facing_left),bool(routine.walking));continue
		var row:int=3+(int(index/3)%2)*2;var legal:Array=[]
		for column in range(3,10):
			if canvas.land(Vector2i(column,row)):legal.append(column)
		if legal.is_empty():continue
		var phase:float=float(index)*1.37;var routine:Dictionary=resident.routine(actor_clock);var progress:float=float(routine.progress)
		var left:float=lerpf(float(legal.front()),float(legal.back()),float(index%3)/3.0)
		var right:float=lerpf(float(legal.front()),float(legal.back()),float(index%3+1)/3.0)
		var cell:Vector2=Vector2(lerpf(left,right,progress),row+.25)
		resident.position=canvas.point(cell)-Vector2(38,101);resident.update_motion(actor_clock,bool(routine.facing_left),bool(routine.walking))
		# Neighbors pause to acknowledge each other; this is visual only, not a
		# player account reward or an invented simulation action.
		for other in ship_residents.values():
			if int(other.index)<=index:continue
			if resident.position.distance_to(other.actor.position)<78 and int(actor_clock+phase)%14<2:
				resident.neighbor_until=actor_clock+.7;other.actor.neighbor_until=actor_clock+.7

func _restore_hint()->void:
	var salvage:bool=service!=null and str(app.get_meta("home_battle_mode",""))=="salvage" and bool(service.state().unlocked)
	$Layout/Hint.text="带部队搜索陆上遗迹" if salvage else "拖动海岛 · 滚轮 / 双指缩放 · 点击设施"
	if service!=null:
		var amount:int=0
		for value in service.overview().pending.values():amount+=int(value)
		if amount>0 and not salvage:$Layout/Hint.text="点击资源泡泡，收取全部设施产出"
		if bool(service.state().unlocked) and not _blocked().is_empty():$Layout/Hint.text="行动进行中 · 可查看岛屿，返航后建设"

func _notice(title:String,message:String,cta:String="",callback:Callable=Callable())->void:
	$Layout/Notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	$Layout/Notice.anchor_left=.25;$Layout/Notice.anchor_top=.14;$Layout/Notice.anchor_right=.75;$Layout/Notice.anchor_bottom=.39
	$Layout/Notice.visible=true;var holder:VBoxContainer=$Layout/Notice/Body;_empty(holder);_label(holder,title,28);_label(holder,message,23)
	if not cta.is_empty():_button(holder,cta,callback,true)

func _compact_drag_hint()->void:
	var notice:PanelContainer=$Layout/Notice
	notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	notice.anchor_left=.5;notice.anchor_right=.5;notice.offset_left=-214;notice.offset_right=214;notice.offset_top=100;notice.offset_bottom=174
	var holder:VBoxContainer=$Layout/Notice/Body;_empty(holder)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",12);holder.add_child(row)
	var label:Label=_label(row,"拖动指挥教学",21);label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;label.tooltip_text="拖部队上岸，再拖卡移动与呼叫舰炮。"
	var start:=Button.new();start.text="试一试";start.custom_minimum_size=Vector2(100,48);Design.apply_button(start,true);start.pressed.connect(_start_drag_lesson);row.add_child(start)
	var close:=Button.new();close.text="×";close.custom_minimum_size=Vector2(48,48);Design.apply_button(close);close.tooltip_text="稍后从训练入口开始";close.pressed.connect(func():notice.hide());row.add_child(close)
	notice.visible=true

func _cell(cell:Vector2i)->void:
	selected_cell=cell
	if not building_kind.is_empty():return
	$Layout/Tray.visible=false;$Layout/Notice.visible=false
	if service.building_at(cell).is_empty():$Layout/Context.visible=false
	else:_details()

func _details()->void:
	if service==null:return
	_empty(body);var building:Dictionary=service.building_at(selected_cell)
	if building.is_empty():$Layout/Context.visible=false;return
	$Layout/Context.visible=true
	var definition:Dictionary=Service.BUILDINGS[str(building.kind)]
	var header:=HBoxContainer.new();body.add_child(header)
	var art:=FacilityArt.new();art.kind=str(building.kind);art.level=int(building.level);art.custom_minimum_size=Vector2(95,95);header.add_child(art)
	var text:=VBoxContainer.new();text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(text);_label(text,str(definition.name),28);_label(text,"等级 %d"%int(building.level),21)
	var close:=Button.new();close.name="CloseBuilding";close.text="×";close.custom_minimum_size=Vector2(80,80);header.add_child(close);Design.apply_button(close);close.pressed.connect(func():$Layout/Context.visible=false)
	if not _blocked().is_empty():_label(body,_blocked(),22);_position_context();return
	var resource:String=str(definition.get("produces",""));var available:int=int(service.overview().pending.get(resource,0))
	if available>0:
		var total:int=0
		for value in service.overview().pending.values():total+=int(value)
		_button(body,"全部收取 +%d"%total,func():_collect(),true)
	elif int(building.get("hp",100))<100:_button(body,"修复 · 完好 %d%%"%int(building.get("hp",100)),func():_perform(service.repair_building(str(building.id))),true)
	elif int(building.level)<(5 if str(building.kind)=="hq" else 3):
		var cost:Dictionary=service.upgrade_cost(str(building.id));_resources(body,cost);var affordable:bool=_affordable(cost)
		var action:Button=_button(body,"升级" if affordable else "资源不足",func():_perform(service.upgrade(str(building.id))),affordable);action.name="UpgradeBuilding";action.disabled=not affordable
	else:_label(body,"设施已达当前最高等级",21)
	if not resource.is_empty():_label(body,"每小时 %d%s"%[int(definition.hourly)*int(building.level),str(Service.RESOURCE_NAMES[resource])],19)
	if str(building.kind)=="hq":_button(body,"人机海域与攻防记录",func():open_conflicts())
	if str(building.kind)=="depot":_button(body,"仓储保护详情",func():open_conflicts("storage"))
	var processing=service.processing()
	if processing.enabled():
		var order_view:Dictionary=processing.overview()
		if order_view.recipes.any(func(row):return str(row.facility_id)==str(building.id)):
			_button(body,"加工订单",func():_processing_orders(str(building.id)),true)
	_position_context.call_deferred()

func _position_context()->void:
	if not is_instance_valid(canvas) or not $Layout/Context.visible:return
	var at:Vector2=canvas.global_position+canvas.point(Vector2(selected_cell))-$Layout.global_position
	var card:Control=$Layout/Context;var width:float=clampf($Layout.size.x*.28,400,470);card.size.x=width;card.reset_size()
	var desired:Vector2=at+Vector2(65,-card.size.y*.65)
	if desired.x+width>$Layout.size.x-15:desired.x=at.x-width-65
	card.position=Vector2(clampf(desired.x,12,$Layout.size.x-width-12),clampf(desired.y,90,maxf(90,$Layout.size.y*.78-card.size.y)))

func _show_build_tray()->void:
	if service==null:return
	consume_back()
	if not _blocked().is_empty():
		_notice("暂时不能建设",_blocked(),"继续当前行动" if bool(service.state().unlocked) else "开始登陆",func():app.resume_run() if bool(service.state().unlocked) else app.show_page("home_story"));return
	var holder:VBoxContainer=$Layout/Tray/Body;_empty(holder);$Layout/Tray.visible=true
	var top:=HBoxContainer.new();holder.add_child(top);var title:Label=_label(top,"建设",29);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var close:=Button.new();close.name="CloseConstruction";close.text="关闭";close.custom_minimum_size=Vector2(120,80);top.add_child(close);Design.apply_button(close);close.pressed.connect(func():consume_back())
	var scroll:=ScrollContainer.new();scroll.name="ConstructionScroll";scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;holder.add_child(scroll)
	var row:=HBoxContainer.new();row.name="ConstructionCards";row.add_theme_constant_override("separation",16);scroll.add_child(row)
	for kind in Service.BUILDINGS:
		if kind=="hq":continue
		var identity:String=str(kind);var definition:Dictionary=Service.BUILDINGS[kind];var count:int=0
		for building in service.state().buildings:
			if str(building.kind)==identity:count+=1
		var panel:=PanelContainer.new();panel.custom_minimum_size=Vector2(250,235);panel.add_theme_stylebox_override("panel",Design.box(Color("e7eee0"),12));row.add_child(panel)
		var card:=VBoxContainer.new();card.add_theme_constant_override("separation",7);panel.add_child(card)
		var art:=FacilityArt.new();art.kind=identity;art.custom_minimum_size=Vector2(220,130);card.add_child(art)
		_label(card,str(definition.name)+"  %d/%d"%[count,int(definition.limit)],23);_resources(card,definition.cost)
		var available:bool=count<int(definition.limit) and int(definition.get("unlock_level",1))<=int(service.island_profile().level);var affordable:bool=_affordable(definition.cost)
		var choose:Button=_button(card,"选择落位" if available and affordable else "数量已满" if not available else "资源不足",func():_choose_building(identity),available and affordable);choose.name="Build_"+identity;choose.disabled=not available or not affordable
	$Layout/Hint.text="选设施 → 在岛上择位 → 确认建造"

func _choose_building(kind:String)->void:
	building_kind=kind;$Layout/Tray.visible=false;$Layout/Context.visible=false;$Layout/Placement.visible=true
	var cell:Vector2i=Vector2i(5,4)
	var closest:float=INF
	for available_cell in canvas.grid_cells():
		var distance:float=(Vector2(available_cell)-Vector2(5.5,4)).length_squared()
		if distance<closest and service.buildable(available_cell) and service.building_at(available_cell).is_empty():cell=available_cell;closest=distance
	canvas.begin_placement(kind,cell)
	if canvas.has_native_geometry():canvas.focus_cell(cell,maxf(6,canvas.zoom))
	$Layout/Placement/Body/Status/Name.text=str(Service.BUILDINGS[kind].name)
	$Layout/Hint.text="拖动设施或点击空地 · 确认前不会消耗资源"

func _placement_changed(_cell:Vector2i,valid:bool,reason:String)->void:
	if not is_instance_valid(canvas):return
	$Layout/Placement/Body/Status/Reason.text=("✓ " if valid else "× ")+reason
	$Layout/Placement/Body/Confirm.disabled=not valid or not _blocked().is_empty()

func _confirm_placement()->void:
	if building_kind.is_empty() or not canvas.placement_valid:return
	var cell:Vector2i=canvas.placement_cell;var result:Dictionary=service.place(building_kind,cell)
	if result.get("ok",false):_cancel_placement()
	_perform(result)
	if result.get("ok",false):selected_cell=cell;canvas.selected=cell;_details()

func _cancel_placement()->void:
	building_kind="";canvas.end_placement();$Layout/Placement.visible=false;_restore_hint()

func consume_back()->bool:
	var consumed:bool=$Layout/Tray.visible or $Layout/Context.visible or $Layout/Placement.visible or $Layout/Notice.visible
	$Layout/Tray.visible=false;$Layout/Context.visible=false;$Layout/Notice.visible=false
	if not building_kind.is_empty() or $Layout/Placement.visible:_cancel_placement()
	else:_restore_hint()
	return consumed

func _collect()->void:
	if service!=null:_perform(service.collect())

func _perform(response:Dictionary)->void:
	if app!=null:app.notify(response)
	refresh()

func _home_modal(title:String,back_action:Callable=Callable())->Control:
	var layer:Control=app.open_modal(title,back_action)
	for child in layer.get_children():
		if child is Button and child.text=="关闭":app.place_reposition(child,1130,145,115,80)
	return layer

func _garrison()->void:
	if app==null:return
	var layer:Control=_home_modal("驻防舰娘 · 最多六艘")
	app.button(layer,"舰娘停泊",370,208,410,80,_garrison,true).name="GarrisonShips"
	app.button(layer,"战术驻防",800,208,410,80,_tactical_garrison).name="GarrisonTactical"
	var scroll:=ScrollContainer.new();app.place(scroll,layer,365,295,865,320)
	var grid:=GridContainer.new();grid.columns=3;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(grid)
	var selected:Array=service.state().garrison.duplicate()
	for card in app.economy.roster():
		if not bool(card.get("playable",false)):continue
		var id:String=str(card.id);var choice:=CheckButton.new();choice.name="Garrison_"+id;choice.text=str(card.name);choice.custom_minimum_size=Vector2(250,80);choice.button_pressed=selected.has(id);grid.add_child(choice)
		choice.toggled.connect(func(enabled:bool):
			if enabled and not selected.has(id):
				if selected.size()>=6:choice.set_pressed_no_signal(false);return
				selected.append(id)
			elif not enabled:selected.erase(id))
	app.button(layer,"确认停泊",825,660,400,80,func():var result:Dictionary=service.set_garrison(selected);app.notify(result);if result.get("ok",false):app.close_modal();refresh(),true)

func _tactical_garrison()->void:
	if app==null:return
	var layer:Control=_home_modal("战术驻防 · 自由选择先遣编制")
	app.button(layer,"舰娘停泊",370,208,410,80,_garrison).name="GarrisonShips"
	app.button(layer,"战术驻防",800,208,410,80,_tactical_garrison,true).name="GarrisonTactical"
	var selected:Array=service.state().tactical_garrison.duplicate()
	var scroll:=ScrollContainer.new();app.place(scroll,layer,365,295,865,325)
	var grid:=GridContainer.new();grid.columns=3;scroll.add_child(grid)
	for id in service.state().units:
		var identity:String=str(id);var row:Dictionary=service.latest_unit(identity)
		if not bool(row.get("released",false)):continue
		var choice:=CheckButton.new();choice.name="TacticalGarrison_"+identity;choice.text=str(row.get("codename",row.get("name",identity)))+"\n整备 %.0f%%"%service.condition(identity);choice.custom_minimum_size=Vector2(270,88);choice.button_pressed=selected.has(identity);choice.disabled=service.condition(identity)<10;grid.add_child(choice)
		choice.icon=load("res://scripts/story_actor_layout.gd").portrait(Art.texture(str(row.get("portrait",""))),identity);choice.expand_icon=true;choice.add_theme_constant_override("icon_max_width",45)
		choice.toggled.connect(func(enabled:bool):
			if enabled and not selected.has(identity):
				if selected.size()>=service.latest_limit("roster_per_side"):choice.set_pressed_no_signal(false);return
				selected.append(identity)
			elif not enabled:selected.erase(identity))
	app.label(layer,"防御演练直接驻岸 · 不占投送舱位 · 战损真实保存",370,625,855,35,19,Design.MUTED)
	app.button(layer,"清空驻防",370,670,250,70,func():var result:Dictionary=service.set_latest_garrison([]);app.notify(result);if result.get("ok",false):_tactical_garrison()).name="ClearTacticalGarrison"
	app.button(layer,"保存战术驻防",640,670,585,70,func():var result:Dictionary=service.set_latest_garrison(selected);app.notify(result);if result.get("ok",false):app.close_modal();refresh(),true).name="SaveTacticalGarrison"

func _units()->void:
	if app==null:return
	var layer:Control=_home_modal("战术人格 · 核心与编制")
	var scroll:=ScrollContainer.new();app.place(scroll,layer,365,220,865,405)
	var list:=GridContainer.new();list.columns=3;list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("h_separation",12);list.add_theme_constant_override("v_separation",12);scroll.add_child(list)
	for row in service.latest_units() if not service.latest_cards().is_empty() else service.catalogue:
		var id:String=str(row.id);var owned:bool=service.state().units.has(id)
		var button:=Button.new();button.name="Unit_"+id;button.custom_minimum_size=Vector2(265,240);Design.apply_button(button,owned);list.add_child(button)
		var token:=TypeToken.new();token.role=str(row.get("nato_type",row.get("role","marine")));token.echelon=str(row.get("echelon","X"));button.add_child(token);token.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);token.position=Vector2(13,13);token.size=Vector2(54,37);token.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var card:=VBoxContainer.new();button.add_child(card);card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);card.offset_top=8;card.offset_bottom=-8;card.offset_left=10;card.offset_right=-10;card.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var art:=TextureRect.new();art.custom_minimum_size.y=155;art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;art.mouse_filter=Control.MOUSE_FILTER_IGNORE;art.texture=load("res://scripts/story_actor_layout.gd").portrait(Art.texture(str(row.get("portrait",""))),id);card.add_child(art)
		var title:=Label.new();title.text=str(row.get("codename",row.name));title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.add_theme_font_size_override("font_size",23);title.mouse_filter=Control.MOUSE_FILTER_IGNORE;card.add_child(title)
		var status:=Label.new();status.text="整备 %.1f%%"%service.condition(id) if owned else "未收录" if bool(row.get("released",false)) else "整编中";status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;status.add_theme_font_size_override("font_size",17);status.mouse_filter=Control.MOUSE_FILTER_IGNORE;card.add_child(status)
		button.pressed.connect(func():_unit_detail(id))
		button.tooltip_text=str(load("res://scripts/tactical_codex_v3.gd").ROLES.get(row.get("role",""),"战术部队"))+" · "+str(row.get("description",""))
	app.label(layer,"核心不会消失 · 自然每30分钟恢复1%整备率",370,633,850,36,20,Design.MUTED)
	if str(app.economy.state.get("test_account",""))=="cas-local-qa-2026-11-12":app.button(layer,"测试：同步%d编制"%service.latest_cards().size(),805,660,420,80,func():app.notify(service.unlock_test_units_latest());app.close_modal();refresh())
	app.button(layer,"重学拖动指挥",370,660,400,80,func():app.close_modal();_start_drag_lesson())

func _start_drag_lesson()->void:
	_training_lessons()

func _training_lessons()->void:
	if app==null:return
	var layer:Control=_home_modal("海陆协同 · 指挥训练");layer.name="TrainingLessons"
	var lessons:Array=service.latest_training_lessons()
	for row:Dictionary in _coastal_scenarios():lessons.append(row)
	var scroll:=ScrollContainer.new();scroll.name="TrainingLessonScroll";scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;app.place(scroll,layer,370,245,870,335)
	var grid:=GridContainer.new();grid.columns=3;grid.add_theme_constant_override("h_separation",15);grid.add_theme_constant_override("v_separation",14);scroll.add_child(grid)
	for index in range(lessons.size()):
		var row:Dictionary=lessons[index];var key:String=str(row.id)
		var button:=Button.new();button.text="%02d · %s\n\n%s"%[index+1,str(row.title),str(row.text)];button.custom_minimum_size=Vector2(270,150);Design.apply_button(button,index==0);button.pressed.connect(func():_start_lesson_row(key,bool(row.get("sample",false))));grid.add_child(button);button.name="Lesson-"+key;button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;button.add_theme_font_size_override("font_size",21)
	app.label(layer,"借用训练编队 · 独立无损模拟，不改动账号或当前航次",370,594,855,45,20,Design.MUTED)
	app.button(layer,"旧版制海权训练",370,660,400,70,func():_start_training("sea_control")).name="LegacySeaControlLesson"
	app.button(layer,"返回海岛",795,660,430,70,app.close_modal,true).name="BackFromTrainingLessons"

func _coastal_scenarios()->Array:
	var path:String="res://data/coastal-scenarios-v1.json"
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not data is Dictionary:return []
	var rows:Array=[]
	for row:Dictionary in data.get("scenarios",[]):
		rows.append({"id":"scenario-"+str(row.get("id")),"sample":true,"title":str(row.get("title")),"text":str(row.get("text")),"scenario":row})
	return rows

func _start_lesson_row(key:String,sample:bool)->void:
	if sample:_start_coastal_scenario(key.trim_prefix("scenario-"))
	else:_start_v3_training(key)

func _start_coastal_scenario(id:String)->void:
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/coastal-scenarios-v1.json"))
	if not data is Dictionary:app.notify({"ok":false,"message":"标准攻防样板尚未就绪"});return
	var scenario:Dictionary={}
	for row:Dictionary in data.get("scenarios",[]):
		if str(row.get("id"))==id:scenario=row;break
	if scenario.is_empty():app.notify({"ok":false,"message":"未找到该攻防样板"});return
	var geo:Dictionary=preload("res://scripts/coastal_map_settings.gd").geography()
	var garrison:Array=scenario.get("garrison",[])
	var request:Dictionary={"op":"new_island_battle","version":"cas-island-war-coastal-v1","seed":int(scenario.get("seed",18031)),"mode":"exercise",
		"company_layout":"multi-company-v1","transport_preset":"combat","ships":scenario.get("ships",[]),
		"roster":scenario.get("roster",[]),
		"island":{"npc_id":"","island_level":int(scenario.get("level",3)),"forts":scenario.get("forts",[])},
		"defender":{"ships":[{"id":str(scenario.get("garrison_ship")),"hp":100,"ammo":int(scenario.get("garrison_ship_ammo",50))}],
			"roster":garrison,
			"unit_condition":garrison.map(func(u):return {"id":str(u),"hp":100.0})},
		"geography":geo,"coastal_tuning":"coastal-combat-v2"}
	app.close_modal();app.launch_home_exercise(request)

func _start_v3_training(lesson:String)->void:
	var prepared:Dictionary=service.latest_training(lesson)
	if not prepared.get("ok",false):app.notify(prepared);return
	app.close_modal();app.launch_home_exercise(prepared.request)

func _start_training(lesson:String="landing")->void:
	if not app.economy.state.active_run.is_empty():app.close_modal();app.resume_run();return
	var prepared:Dictionary=service.prepare_littoral("tutorial",42,[],[],"balanced",Service.BATTLE_VERSION,lesson)
	if not prepared.get("ok",false):app.notify(prepared);return
	app.close_modal();app.set_meta("littoral_drag_help",true);app.launch_littoral(prepared.request)

func _unit_detail(id:String)->void:
	load("res://scripts/home_conflict_ui.gd").unit(app,id)

func _sortie()->void:
	if app==null or service==null:return
	if not bool(service.state().unlocked):app.show_page("home_story");return
	var mode:String=str(app.get_meta("home_battle_mode","raid"))
	if mode=="salvage":_legacy_sortie();return
	if not app.economy.state.active_run.is_empty() and mode!="exercise":_notice("编队尚在航行","继续当前行动，或到岛务进行独立的无损演习。","继续行动",func():app.resume_run());return
	load("res://scripts/home_sortie_v2.gd").open(app,mode)

func _legacy_sortie()->void:
	if service==null:return
	if not bool(service.state().unlocked):app.show_page("home_story");return
	if not app.economy.state.active_run.is_empty():_notice("编队尚在航行","继续当前行动，返航后再安排下一次出发。","继续行动",func():app.resume_run());return
	app.set_meta("home_battle_mode","salvage")
	var layer:Control=_home_modal("遗迹搜索 · 既有投送规则")
	var units:Array=[]
	for id in service.state().units:
		if Service.RELEASED.has(str(id)) and service.condition(str(id))>=10:units.append(str(id))
	if naval_selection.is_empty():
		naval_selection=service.state().garrison.duplicate()
		if naval_selection.is_empty() and not app.economy.formation.is_empty():naval_selection=[str(app.economy.formation[0])]
	var saved_fleet:=OptionButton.new();saved_fleet.name="SavedDeploymentFleet";saved_fleet.add_item("选择已存编队 · 本场最多六艘舰娘");app.place(saved_fleet,layer,380,193,590,44)
	for saved in app.fleets.rows():saved_fleet.add_item(str(saved.name)+" · %d艘"%saved.ships.size());saved_fleet.set_item_metadata(saved_fleet.item_count-1,saved.ships.duplicate())
	saved_fleet.item_selected.connect(func(index:int):
		if index==0:return
		var ships:Array=saved_fleet.get_item_metadata(index)
		if ships.size()>6:app.notify({"ok":false,"message":"本场海陆行动允许六舰；自由编队与搜打撤仍可多队出航。"});saved_fleet.select(0);return
		naval_selection=ships.duplicate();_sortie())
	var procure:Button=app.button(layer,"载舰采购",975,193,150,44,func():_aviation_procurement());procure.name="OpenAviationProcurement";procure.add_theme_font_size_override("font_size",18);procure.tooltip_text="航空与运输舰 · 航母 / 两栖攻击舰 / APV"
	var scroll:=ScrollContainer.new();scroll.name="DeploymentShips";app.place(scroll,layer,380,240,820,118);scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	var naval:=HBoxContainer.new();naval.add_theme_constant_override("separation",8);scroll.add_child(naval)
	for card in service.naval_roster():
		if not bool(card.get("playable",false)):continue
		var identity:String=str(card.id);var choice:=Button.new();choice.name="Sortie_"+identity;choice.toggle_mode=true;choice.button_pressed=naval_selection.has(identity);choice.custom_minimum_size=Vector2(112,111);Design.apply_button(choice,choice.button_pressed);naval.add_child(choice)
		var box:=VBoxContainer.new();box.mouse_filter=Control.MOUSE_FILTER_IGNORE;choice.add_child(box);box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);box.offset_top=5;box.offset_bottom=-5;box.offset_left=4;box.offset_right=-4
		var art:=TextureRect.new();art.custom_minimum_size=Vector2(100,68);art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;art.mouse_filter=Control.MOUSE_FILTER_IGNORE;art.texture=load("res://scripts/story_actor_layout.gd").portrait(Art.texture(str(Art.visual_card(card,app.cards).get("portrait",""))),identity);box.add_child(art)
		var title:=Label.new();title.text=str(card.name);title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.add_theme_font_size_override("font_size",17);title.mouse_filter=Control.MOUSE_FILTER_IGNORE;box.add_child(title)
		choice.tooltip_text=str(card.name)+(" · 水上机支援舰" if str(card.get("type",""))=="AV" else " · "+str(card.get("type","")))+"\n耐久 %d%% · 现有弹药 %d%%"%[int(card.get("hp",100)),int(card.get("ammo",100))]
		choice.toggled.connect(func(enabled:bool):
			if enabled and not naval_selection.has(identity):
				if naval_selection.size()>=6:choice.set_pressed_no_signal(false);app.notify({"ok":false,"message":"本次海陆行动最多六艘舰娘"});return
				naval_selection.append(identity)
			elif not enabled:naval_selection.erase(identity)
			Design.apply_button(choice,enabled);_deployment_refresh())
	var preset:=OptionButton.new();preset.name="TransportPreset";preset.add_item("火力优先 · 最多100%弹药");preset.add_item("均衡运输 · 最多70%弹药");preset.add_item("运输优先 · 最多40%弹药");app.place(preset,layer,380,354,400,74)
	var choices:Array=["combat","balanced","transport"]
	preset.selected=maxi(0,choices.find(transport_preset));preset.item_selected.connect(func(index):transport_preset=str(choices[index]);_deployment_refresh())
	var npc:=OptionButton.new();npc.name="NPCIsland";app.place(npc,layer,800,354,400,74)
	var islands:Array=service.npc_islands()
	if islands.is_empty():islands=Service.NPC_ISLANDS.duplicate(true)
	for index in range(islands.size()):
		var island:Dictionary=islands[index];npc.add_item(str(island.name));npc.set_item_tooltip(npc.item_count-1,str(island.get("description","本地人机岛屿 · Lv%d"%int(island.get("level",1)))))
		if str(island.get("id",""))==str(app.get_meta("home_npc_id","")):npc_index=index
	npc_index=clampi(npc_index,0,islands.size()-1);npc.selected=npc_index;npc.item_selected.connect(func(index):npc_index=index;app.set_meta("home_npc_id",str(islands[index].get("id",""))))
	unit_selection=unit_selection.filter(func(id):return units.has(id))
	if unit_selection.is_empty():
		var candidates:Array=service.state().tactical_garrison.duplicate()
		for id in units:
			if not candidates.has(id):candidates.append(id)
		for id in candidates:
			if unit_selection.size()>=2:break
			if not units.has(id):continue
			var trial:Array=unit_selection.duplicate();trial.append(id)
			if service.transport_summary(trial,naval_selection,transport_preset,_company_transports(trial)).get("fits",false):unit_selection.append(id)
	var unit_scroll:=ScrollContainer.new();unit_scroll.name="DeploymentUnitScroll";unit_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;app.place(unit_scroll,layer,380,434,820,84)
	var unit_grid:=HBoxContainer.new();unit_grid.name="DeploymentUnits";unit_grid.add_theme_constant_override("separation",10);unit_scroll.add_child(unit_grid)
	for id in units:
		var identity:String=str(id);var card:Dictionary=service.unit(identity);var choice:=CheckButton.new();choice.name="Deploy_"+identity;choice.text=str(card.get("codename",card.get("name",identity)));choice.button_pressed=unit_selection.has(identity);choice.custom_minimum_size=Vector2(170,80);unit_grid.add_child(choice)
		choice.icon=load("res://scripts/story_actor_layout.gd").portrait(Art.texture(str(card.get("portrait",""))),identity);choice.expand_icon=true;choice.add_theme_constant_override("icon_max_width",38);choice.add_theme_font_size_override("font_size",18)
		choice.toggled.connect(func(enabled:bool):
			if enabled and not unit_selection.has(identity):
				if unit_selection.size()>=5:choice.set_pressed_no_signal(false);app.notify({"ok":false,"message":"本次行动最多五个MCP编制，每个编制包含独立行动连"});return
				unit_selection.append(identity)
			elif not enabled:unit_selection.erase(identity)
			_deployment_transport_rows();_deployment_refresh())
	var transport_scroll:=ScrollContainer.new();transport_scroll.name="CompanyTransportScroll";transport_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;app.place(transport_scroll,layer,380,524,820,115)
	transport_list=VBoxContainer.new();transport_list.name="CompanyTransports";transport_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;transport_scroll.add_child(transport_list)
	var modes:Array=["raid","salvage","defense"];var mode:OptionButton=OptionButton.new();mode.name="LittoralMode"
	for title in ["人机岛屿突袭","遗迹搜索","本地防御模拟"]:mode.add_item(title)
	mode.selected=maxi(0,modes.find(str(app.get_meta("home_battle_mode","raid"))));app.place(mode,layer,380,645,300,74);npc.disabled=mode.selected==1;deployment_mode=str(modes[mode.selected])
	mode.item_selected.connect(func(index):
		app.set_meta("home_battle_mode",str(modes[index]))
		if index!=1:_sortie();return
		npc.disabled=true;deployment_mode="salvage";_deployment_transport_rows();_deployment_refresh())
	deployment_button=app.button(layer,"出发",705,645,495,74,func():
		var chosen:String=str(modes[mode.selected]);var selected:Array=service.state().tactical_garrison.duplicate() if chosen=="defense" else unit_selection.duplicate()
		app.set_meta("home_npc_id",str(islands[npc_index].get("id","")));_launch(chosen,selected,naval_selection,transport_preset,int(islands[npc_index].get("seed",42)) if chosen=="raid" else -1),true);deployment_button.name="LaunchLittoral";deployment_button.grab_focus()
	deployment_status=app.label(layer,"",380,716,820,28,16,Design.MUTED);deployment_status.name="DeploymentCapacity"
	_deployment_transport_rows();_deployment_refresh()

func _company_transports(ids:Array)->Array:
	var result:Array=[]
	for id in ids:
		var option:Dictionary=service.transport_option(str(id),str(company_choices.get(id,"")))
		if not option.is_empty():result.append({"id":id,"kind":str(option.kind)})
	return result

func _deployment_transport_rows()->void:
	if not is_instance_valid(transport_list):return
	_empty(transport_list)
	var ids:Array=service.state().tactical_garrison.duplicate() if deployment_mode=="defense" else unit_selection
	for node in app.modal.find_children("Deploy_*","CheckButton",true,false):node.disabled=deployment_mode=="defense"
	for id in ids:
		var identity:String=str(id);var data:Dictionary=service.profile(identity);var row:=HBoxContainer.new();row.custom_minimum_size.y=80;transport_list.add_child(row)
		var card:Dictionary=service.unit(identity);var formation:Dictionary=service.company_layout(identity)
		var name:Label=_label(row,str(card.get("codename",card.get("name",identity)))+"\n"+str(card.get("designation","")),17);name.custom_minimum_size.x=230;name.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		var token:=TypeToken.new();token.role=str(data.get("nato_type",data.get("role","marine")));token.echelon=str(load("res://scripts/tactical_formation_mark.gd").resolve(service.unit(identity)).echelon);token.custom_minimum_size=Vector2(47,44);token.size_flags_vertical=Control.SIZE_SHRINK_CENTER;row.add_child(token)
		var selector:=OptionButton.new();selector.name="CompanyTransport_"+identity;selector.custom_minimum_size=Vector2(555,80);selector.size_flags_horizontal=Control.SIZE_EXPAND_FILL;selector.add_theme_constant_override("icon_max_width",62);selector.expand_icon=true;selector.fit_to_longest_item=false;selector.clip_text=true;selector.disabled=deployment_mode=="defense";row.add_child(selector)
		var options:Array=data.get("transport_options",[]);var active:String=str(company_choices.get(identity,data.get("default_transport","landing_craft")))
		for option in options:
			var kind:String=str(option.kind);var family:String=str({"landing_craft":"舟艇","amphibious_vehicle":"两栖车","helicopter":"直升机"}.get(kind,kind))
			selector.add_item("%s · %s · %d连 × %d人"%[str(option.get("vehicle_name","")),family,int(formation.get("company_count",1)),int(formation.get("personnel_per_company",option.get("entity_count",0)))]);selector.set_item_metadata(selector.item_count-1,kind)
			var icon:Texture2D=_transport_icon(identity,kind)
			if icon!=null:selector.set_item_icon(selector.item_count-1,icon)
			if kind==active:selector.selected=selector.item_count-1
		selector.item_selected.connect(func(index):company_choices[identity]=str(selector.get_item_metadata(index));_deployment_refresh())

func _transport_icon(identity:String,kind:String)->Texture2D:
	var own:Dictionary=transport_art.get("units",{}).get(identity,{})
	if str(own.get("default_kind",""))!=kind:
		var fallback:Dictionary=transport_art.get("fallback",{});var kinds:Array=fallback.get("kinds",[]);var generic_path:String=str(fallback.get("atlas",""))
		if own.is_empty() or not kinds.has(kind) or not ResourceLoader.exists(generic_path):return null
		var atlas:Texture2D=load(generic_path);var cell:Vector2=atlas.get_size()/Vector2(maxi(1,int(fallback.get("columns",3))),maxi(1,int(fallback.get("rows",3))))
		var generic:=AtlasTexture.new();generic.atlas=atlas;generic.region=Rect2(Vector2(kinds.find(kind)*cell.x,0),cell);return generic
	var path:String=str(own.get("atlas",""));var region:Array=own.get("frames",{}).get("intact",{}).get("region",[])
	if path.is_empty() or region.size()!=4 or not ResourceLoader.exists(path):return null
	var icon:=AtlasTexture.new();icon.atlas=load(path);icon.region=Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3]));return icon

func _deployment_refresh()->void:
	if not is_instance_valid(deployment_status) or not is_instance_valid(deployment_button):return
	var ids:Array=service.state().tactical_garrison.duplicate() if deployment_mode=="defense" else unit_selection.duplicate()
	var ships:Array=service.state().garrison.duplicate() if deployment_mode=="defense" else naval_selection.duplicate()
	for node in app.modal.find_children("Sortie_*","Button",true,false):
		node.disabled=deployment_mode=="defense";node.set_pressed_no_signal(ships.has(str(node.name).trim_prefix("Sortie_")));Design.apply_button(node,node.button_pressed)
	var saved:Node=app.modal.find_child("SavedDeploymentFleet",true,false)
	if saved!=null:saved.disabled=deployment_mode=="defense"
	var cap:Dictionary=service.transport_summary(ids,ships,transport_preset,_company_transports(ids))
	var valid:bool=ids.size()>=2 and ids.size()<=5 and not ships.is_empty()
	var naval_plan:Dictionary=service._ships(ships,transport_preset)
	valid=valid and bool(naval_plan.get("ok",false))
	if deployment_mode=="defense":deployment_status.text="驻岸 %d个MCP · %d连 / %d人 · 不占投送舱"%[ids.size(),int(cap.get("companies",0)),int(cap.people)] if ids.size()>=2 else "请先到「驻防 → 战术驻防」安排二至五个编制"
	else:
		deployment_status.text="%d个MCP · %d连 / %d人 · 舱位 %d / %d"%[ids.size(),int(cap.get("companies",0)),int(cap.people),int(cap.used),int(cap.available)] if cap.fits else "缺少合格载舰或整连舱位 · 可换运输计划，或点击右上「载舰采购」";valid=valid and bool(cap.fits)
		deployment_status.tooltip_text=str(cap.get("reason",""))
	if ids.size()<2:deployment_status.text="再选择战术编制 · 本场需要2–5个MCP，并满足整连投送舱位"
	if not naval_plan.get("ok",false):deployment_status.text=str(naval_plan.get("message","请整备随行舰娘"))
	elif valid:deployment_status.text+=" · 弹药 %d（出航时结算）"%int(naval_plan.get("loaded_ammo",0))
	if deployment_mode=="defense":
		var warehouses:int=0
		for building in service.state().buildings:
			if str(building.kind)=="depot":warehouses+=1
		if warehouses==0:valid=false;deployment_status.text="先建造补给仓库，再进行本地防御模拟 · 驻防使用已保存的舰娘与编制"
	deployment_button.disabled=not valid
	deployment_status.add_theme_color_override("font_color",Design.MUTED if valid else Color("b5533c"))

func _aviation_procurement()->void:
	var layer:Control=_home_modal("航空与运输舰 · 海陆空专用",_sortie)
	app.label(layer,"历史舰体有原页依据；两栖舰为原创。舰载航空当前采用近场玩法。",380,204,820,44,19,Design.MUTED)
	for index in range(service.aviation_ships.size()):
		var card:Dictionary=service.aviation_ships[index];var id:String=str(card.id);var x:float=380+index*207
		app.picture(layer,str(card.portrait),x,259,198,300)
		app.label(layer,str(card.name)+" · "+str(card.type),x,566,198,34,25,Design.INK)
		app.label(layer,str(card.description),x,609,198,80,18,Design.MUTED)
		var owned:bool=app.economy.state.owned.has(id)
		var receive:Button=app.button(layer,"已到港" if owned else "%d 元词 · 接收"%int(card.price_origins),x,700,198,60,func():
			app.notify(service.procure_ship(id,"procure-"+id));_aviation_procurement(),not owned)
		receive.name="Procure_"+id;receive.disabled=owned;receive.add_theme_font_size_override("font_size",18)

func _launch(mode:String,units:Array,ships:Array,preset:String="balanced",seed:int=-1)->void:
	if app==null:return
	var prepared:Dictionary=service.prepare_island(mode,str(app.get_meta("home_npc_id","")),units,ships,preset,_company_transports(units)) if mode in ["raid","defense"] else service.prepare_littoral(mode,seed if seed>=0 else int(Time.get_unix_time_from_system())%4294967295,units,ships,preset,Service.BATTLE_VERSION,"landing",_company_transports(units))
	if not prepared.get("ok",false):app.notify(prepared);return
	if app.has_method("launch_littoral"):app.launch_littoral(prepared.request)
	else:app.notify({"ok":false,"message":"海陆协同行动正在接线，出航资源尚未扣除"})

func open_conflicts(section:String="islands")->void:
	load("res://scripts/home_conflict_ui.gd").open(app,section)

func _processing_orders(facility_id:String)->void:
	load("res://scripts/home_orders_ui.gd").open(self,facility_id)
