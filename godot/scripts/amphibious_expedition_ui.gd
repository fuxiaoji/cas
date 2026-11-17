@tool
extends Control
## A second map over the unchanged naval battle controller. No combat authority.
const Design=preload("res://scripts/ui_design.gd")
const UnitCard=preload("res://scripts/littoral_drag_card.gd")
const LandMap=preload("res://scripts/amphibious_expedition_land.gd")
const DragLayer=preload("res://scripts/littoral_drag_layer.gd")
const SeaMap=preload("res://scripts/sea_map.gd")
@export var army_card_width:float=146
var app
var land
var miniature_sea
var drag
var strip:HBoxContainer
var army_scroll:ScrollContainer
var hint:Label
var swap:Button
var recover:Button
var cards:Dictionary={}
var metadata:Dictionary={}
var selected:String=""
var island:int=-1
var land_primary:bool=false
var previous_tick:int=-1
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	if Engine.is_editor_hint():return
	for row in JSON.parse_string(FileAccess.get_file_as_string("res://data/tactical-units-v1.json")).get("units",[]):metadata[str(row.id)]=row
	land=LandMap.new();land.name="LandMap";land.friendly_sprite_height=44;land.enemy_sprite_height=34;add_child(land);land.point_selected.connect(_land_click)
	miniature_sea=SeaMap.new();miniature_sea.name="SeaMiniature";miniature_sea.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(miniature_sea);miniature_sea.visible=false
	strip=HBoxContainer.new();strip.name="ArmyCards";strip.add_theme_constant_override("separation",8);add_child(strip)
	hint=Label.new();hint.add_theme_font_size_override("font_size",17);hint.add_theme_color_override("font_color",Color("f2f2de"));hint.add_theme_color_override("font_shadow_color",Color.BLACK);hint.add_theme_constant_override("shadow_offset_y",1);hint.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(hint)
	swap=Button.new();swap.text="查看陆战";Design.apply_button(swap);add_child(swap);swap.pressed.connect(func():land_primary=not land_primary;_layout();_refresh())
	recover=Button.new();recover.text="撤收部队";Design.apply_button(recover);add_child(recover);recover.pressed.connect(func():if not selected.is_empty():app.issue(_selected_command("expedition_land_recover")))
	drag=DragLayer.new();drag.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(drag);drag.dropped.connect(_drop);drag.clicked.connect(_card_click);drag.moved.connect(_drag_move);drag.cancelled.connect(func():land.show_drag_target=false)
	resized.connect(_layout);_layout();_refresh()
func _exit_tree()->void:
	if app!=null and is_instance_valid(app.sea):app.sea.visible=true
func _layout()->void:
	if land==null:return
	if army_scroll==null:
		army_scroll=ScrollContainer.new();army_scroll.name="ArmyScroll";army_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;army_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(army_scroll);remove_child(strip);army_scroll.add_child(strip)
	army_scroll.position=Vector2(size.x*.39,size.y*.824);army_scroll.size=Vector2(size.x*.59,size.y*.17)
	if drag!=null:drag.scroll_container=army_scroll
	hint.position=Vector2(size.x*.39,size.y*.79);hint.size=Vector2(size.x*.58,28);hint.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	swap.position=Vector2(size.x*.79,size.y*.16);swap.size=Vector2(size.x*.19,45)
	recover.position=Vector2(size.x*.65,size.y*.16);recover.size=Vector2(size.x*.13,45)
	if app!=null and app.battle_controller!=null and app.battle_controller.hud!=null:app.place_reposition(app.battle_controller.hud.context,624,580,552,136)
	land.position=Vector2(20,size.y*.12) if land_primary else Vector2(size.x*.76,size.y*.225)
	land.size=Vector2(size.x*.73,size.y*.67) if land_primary else Vector2(size.x*.22,size.y*.32)
	land.set_miniature(not land_primary)
	miniature_sea.position=Vector2(size.x*.76,size.y*.225);miniature_sea.size=Vector2(size.x*.22,size.y*.32);miniature_sea.visible=land_primary
	if app!=null and is_instance_valid(app.sea):app.sea.visible=not land_primary
	swap.text="返回海战" if land_primary else "查看陆战"
func _process(_delta:float)->void:
	if Engine.is_editor_hint() or app==null:return
	var tick:int=int(app.core.view.get("tick",0))
	if tick!=previous_tick:previous_tick=tick;_refresh()
	queue_redraw()
func data()->Dictionary:return app.core.view.get("salvage",{}).get("amphibious",{}) if app!=null else {}
func _group_key(group:Dictionary)->String:return str(group.get("company_id",group.get("unit_id","")))
func _selected_command(op:String)->Dictionary:
	for group in data().get("groups",[]):
		if _group_key(group)==selected:
			var command:Dictionary={"op":op,"unit_id":str(group.unit_id)}
			if group.has("company_id"):command["company_id"]=str(group.company_id)
			return command
	return {"op":op,"unit_id":selected}
func _refresh()->void:
	var current:Dictionary=data();var tasks:Array=current.get("tasks",[])
	if tasks.is_empty():return
	if island<0:island=int(tasks[0].island)
	var task:Dictionary=tasks[0]
	for row in tasks:
		if int(row.island)==island:task=row
	var polygon:Array=task.get("polygon",[]);var low:=Vector2(INF,INF);var high:=Vector2(-INF,-INF)
	for p in polygon:low=low.min(Vector2(float(p.x),float(p.y)));high=high.max(Vector2(float(p.x),float(p.y)))
	var observation:Dictionary=current.duplicate(true)
	for key in ["entities","corpses","transports"]:observation[key]=current.get(key,[]).filter(func(row):return int(row.get("island",island))==island)
	observation["polygon"]=polygon;observation["bounds"]={"x":low.x-100,"y":low.y-100,"width":high.x-low.x+200,"height":high.y-low.y+200};observation["seed"]=int(app.run.get("seed",0))+island
	observation["buildings"]=[];observation["ruins"]=[{"id":task.id,"x":task.x,"y":task.y,"searched":str(task.status)=="complete","progress":float(task.progress)/maxf(1,float(task.duration))}];observation["persistent_corpses"]=true
	observation["terrain"]=task.get("terrain",{})
	land.selected_unit=selected;land.playback_rate=float(app.speed);land.observe(observation,bool(app.running))
	miniature_sea.view=app.core.view;miniature_sea.cards=app.cards;miniature_sea.queue_redraw()
	recover.visible=false
	for group in current.get("groups",[]):
		var id:String=_group_key(group);var meta:Dictionary=metadata.get(str(group.unit_id),{})
		if not cards.has(id):
			var card=UnitCard.new();card.custom_minimum_size=Vector2(army_card_width,128);strip.add_child(card);card.armed.connect(func(payload:Dictionary,at:Vector2,pointer:int):drag.arm(payload,at,pointer));cards[id]=card
		var texture:Texture2D=null
		if ResourceLoader.exists(str(meta.get("portrait",""))):texture=load(str(meta.portrait))
		var stage:String=str(group.stage);var status:String=str({"embarked":"随舰待命","approach":"载舰正在近岸","transit":"正在登陆","ground":"岸上%d人"%int(group.alive),"recovering":"正在回舰","recovered":"已回舰","lost":"失去行动能力","stranded":"失去接驳 · 岸上守备"}.get(stage,stage))
		if selected==id and stage in ["ground","approach"]:recover.visible=true
		var payload:Dictionary={"kind":"unit","unit_id":str(group.unit_id),"name":str(meta.get("name",id)),"designation":str(meta.get("designation","")),"role":str(meta.get("nato_type",meta.get("role","infantry"))),"texture":texture,"selected":selected==id,"stage":stage}
		if group.has("company_id"):payload["company_id"]=str(group.company_id);payload["company_name"]=str(group.company_name);payload["company_caption"]="%s %d/%d · %d人"%[str(group.company_name),int(group.get("company_index",1)),int(group.get("company_count",1)),int(group.get("personnel_count",0))]
		cards[id].configure(payload,status,stage!="lost")
	hint.text="拖动兵牌到岛上 · 已登陆再次拖动行军 · 点兵牌后点遗迹搜索"
	if current.get("land_done",false):hint.text="陆军已收队 · 原海军自动指挥继续打捞与撤离"
	hint.tooltip_text=str(current.get("ai_reason",""))
func _card_click(payload:Dictionary)->void:
	var id:String=str(payload.get("company_id",payload.unit_id))
	selected=id
	for group in data().get("groups",[]):
		if _group_key(group)==id and group.get("island")!=null:island=int(group.island)
	_refresh()
func _drop(payload:Dictionary,at:Vector2)->void:
	selected=str(payload.get("company_id",payload.unit_id))
	var local:Vector2=land.get_global_transform().affine_inverse()*at
	if land.get_global_rect().has_point(at):
		var p:Vector2=land.unproject(local);_send_drop(payload,p)
	elif not land_primary and is_instance_valid(app.sea):
		var p:Vector2=app.sea.unproject(app.sea.get_global_transform().affine_inverse()*at);_send_drop(payload,p)
func _send_drop(payload:Dictionary,p:Vector2)->void:
	var stage:String=str(payload.get("stage",""));var command:Dictionary={"op":"expedition_land_order" if stage in ["ground","stranded"] else "expedition_land_deploy","unit_id":str(payload.unit_id),"x":p.x,"y":p.y,"queue":true,"action":"move"}
	if stage in ["ground","stranded"]:
		for task in data().get("tasks",[]):
			if str(task.status)!="complete" and p.distance_to(Vector2(float(task.x),float(task.y)))<150:command={"op":"expedition_land_task","unit_id":str(payload.unit_id),"task":int(task.id)};break
	if stage not in ["ground","stranded"]:command.erase("action")
	else:command.erase("queue")
	if payload.has("company_id"):command["company_id"]=str(payload.company_id)
	var response:Dictionary=app.issue(command)
	if response.get("ok",false):
		for task in data().get("tasks",[]):
			if Geometry2D.is_point_in_polygon(p,PackedVector2Array(task.polygon.map(func(q):return Vector2(q.x,q.y)))):island=int(task.island)
	_refresh()
func _drag_move(payload:Dictionary,at:Vector2)->void:
	land.show_drag_target=land.get_global_rect().has_point(at)
	if land.show_drag_target:
		land.drag_point=land.unproject(land.get_global_transform().affine_inverse()*at);land.drag_valid=true
func _land_click(point:Vector2,target:Variant,kind:String)->void:
	if selected.is_empty():land_primary=not land_primary;_layout();return
	for group in data().get("groups",[]):
		if _group_key(group)==selected and str(group.stage) in ["embarked","recovered"]:
			var payload:Dictionary={"unit_id":str(group.unit_id),"stage":group.stage}
			if group.has("company_id"):payload["company_id"]=str(group.company_id)
			_send_drop(payload,point);return
	var command:Dictionary=_selected_command("expedition_land_task" if kind in ["ruins","ruin"] else "expedition_land_order")
	if kind=="ruins" and target is int:command["task"]=int(target)
	elif kind=="ruin" and target is Dictionary:command["task"]=int(target.id)
	else:command.merge({"action":"move","x":point.x,"y":point.y})
	app.issue(command)
func _draw()->void:
	if Engine.is_editor_hint() or app==null or land_primary or not is_instance_valid(app.sea):return
	for task in data().get("tasks",[]):
		var p:Vector2=app.sea.project(Vector2(float(task.shore.x),float(task.shore.y)))+app.sea.position
		draw_circle(p,12,Color("e2ca82"));draw_arc(p,17,0,TAU,24,Color("f5ead1"),2)
		draw_string(Design.font(500),p+Vector2(18,5),str(task.title),HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("f5ead1"))
