@tool
extends Control
## Presentation consumes the seat-visible observation only. No commands, true-state or clock writes.
const Design=preload("res://scripts/ui_design.gd")
const Impact=preload("res://scripts/combat_impact.gd")
@export_range(0,1,.05) var screen_shake_strength:float=.75
@export_range(.15,2.0,.05) var mark_duration:float=.75
@export_range(.5,6.0,.1) var notice_duration:float=3.2
@export_range(1,8) var maximum_marks:int=5
@export var editor_preview:bool=false:
	set(value):
		editor_preview=value
		if is_node_ready() and Engine.is_editor_hint():_preview()
var _map:WeakRef
var _last_tick:=-1
var _seen:Dictionary={}
var _health:Dictionary={}
var _shell_seen:Dictionary={}
var _own_ships:Dictionary={}
var _marks:Array[Dictionary]=[]
var _notice_age:=100.0
var _priority:=-1
var _last_kind:=""
var notice_history:Array[Dictionary]=[]
var impact=Impact.new()
@onready var notice:PanelContainer=$Notice
@onready var caption:Label=$Notice/Margin/Row/Caption
@onready var emblem:TextureRect=$Notice/Margin/Row/Emblem
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_override("font",Design.font(600))
	caption.add_theme_font_size_override("font_size",20)
	_preview()
func _preview()->void:
	notice.visible=Engine.is_editor_hint() and editor_preview
	if notice.visible:
		caption.text="鱼雷来袭 · 改变航向"
		_tint(Color("da805e"),"ammo")
func bind(sea:Control)->void:
	_map=weakref(sea)
	var registry:Variant=sea.get("cards")
	if registry is Dictionary and not registry.is_empty():impact.catalog=registry
func configure_motion(value:float)->void:
	screen_shake_strength=clampf(value,0,1)
	impact.strength=screen_shake_strength
	if screen_shake_strength<=0:
		impact.offset=Vector2.ZERO;_apply_camera(Vector2.ZERO);queue_redraw()
func _apply_camera(value:Vector2)->void:
	if _map==null:return
	var sea=_map.get_ref()
	if is_instance_valid(sea) and sea.combat_offset!=value:sea.combat_offset=value;sea.queue_redraw()
func _exit_tree()->void:
	_apply_camera(Vector2.ZERO)
func _tint(color:Color,icon:String)->void:
	var style:=Design.box(Color(.96,.985,1,.96),4)
	style.border_width_left=4;style.border_color=color
	notice.add_theme_stylebox_override("panel",style)
	caption.add_theme_color_override("font_color",Design.INK)
	emblem.texture=Design.icon_texture(icon);emblem.modulate=color
func _process(delta:float)->void:
	if Engine.is_editor_hint():return
	impact.strength=screen_shake_strength
	var had_impacts:bool=not impact.pulses.is_empty()
	_apply_camera(impact.advance(delta))
	if had_impacts:queue_redraw()
	_notice_age+=delta
	if _notice_age>=notice_duration:notice.hide()
	var had_marks:=not _marks.is_empty()
	for mark in _marks:mark.age=float(mark.age)+delta
	_marks=_marks.filter(func(row):return float(row.age)<mark_duration)
	if had_marks:queue_redraw()
func _reset(view:Dictionary)->void:
	_seen.clear();_health.clear();_marks.clear();notice.hide();_priority=-1;_notice_age=100
	_own_ships.clear()
	impact.reset();_apply_camera(Vector2.ZERO)
	_shell_seen.clear()
	for shell in view.get("shells",[]):_shell_seen[str(shell.get("id",""))]=true
	for event in view.get("events",[]):_seen[_event_key(event)]=true
	for ship in view.get("ships",[]):
		_health[int(ship.id)]=float(ship.get("hp",0))/maxf(1,float(ship.get("maxHp",1)))
		_own_ships[str(ship.id)]=ship.duplicate(true)
	_last_tick=int(view.get("tick",0));queue_redraw()
func _event_key(event:Dictionary)->String:
	return "%s:%s"%[str(event.get("tick",0)),str(event.get("id",str(event.get("kind",""))+str(event.get("text",""))))]
func observe(view:Dictionary,readonly:bool=false)->void:
	var tick:=int(view.get("tick",0))
	if _last_tick<0 or tick<_last_tick or readonly:
		_reset(view);return
	var selected:Dictionary={}
	var pending_damage:Array[Dictionary]=[]
	for raw in view.get("events",[]):
		var event:Dictionary=raw
		var key:=_event_key(event)
		if _seen.has(key):continue
		_seen[key]=true
		if tick-int(event.get("tick",0))>12 or int(event.get("tick",0))>tick:continue
		if str(event.get("kind","")) in ["damage","creature_hit"]:pending_damage.append(event)
		if str(event.get("kind",""))=="gun" and tick-int(event.get("tick",0))<=2:
			var source:Dictionary=impact.firing_ship(event,view)
			if not source.is_empty() and _on_screen(source):
				var sea=_map.get_ref() if _map!=null else null
				var weight:float=1.0 if sea!=null and int(source.id)==int(sea.selected_ship) else .6
				impact.fire(source,event,weight)
		var cue:=_cue(event)
		if cue.is_empty():continue
		if event.has("x") and event.has("y"):_add_mark(str(cue.kind),Vector2(float(event.x),float(event.y)),cue.color)
		# A final revealed item and actual completion share a simulation tick.
		# Completion supersedes its partial-search cue without outranking damage.
		if selected.is_empty() or int(cue.priority)>int(selected.priority) or (str(cue.kind)=="search_complete" and str(selected.kind)=="search"):selected=cue
	# Tide's public observation has no gun event. Only genuinely observed new friendly
	# projectile IDs establish a shot; a timer must never manufacture fire feedback.
	if view.has("tide") and not view.get("ships",[]).is_empty():
		for shell in view.get("shells",[]):
			var id:=str(shell.get("id",""))
			if _shell_seen.has(id):continue
			_shell_seen[id]=true
			if str(shell.get("side",""))==str(view.get("side","allies")):
				var source:Dictionary=view.ships[0]
				if _on_screen(source):impact.fire(source,{"x":source.x,"y":source.y},1.0)
		if _shell_seen.size()>2048:
			_shell_seen.clear()
			for shell in view.get("shells",[]):_shell_seen[str(shell.get("id",""))]=true
	var damaged:Dictionary={}
	for raw in view.get("ships",[]):
		var ship:Dictionary=raw
		var ratio:=float(ship.get("hp",0))/maxf(1,float(ship.get("maxHp",1)))
		var old:=float(_health.get(int(ship.id),ratio))
		_health[int(ship.id)]=ratio
		var old_hp:float=float(_own_ships.get(str(ship.id),ship).get("hp",ship.get("hp",0)))
		var lost_hp:float=old_hp-float(ship.get("hp",0))
		if lost_hp>.00001:
			impact.hurt(ship,lost_hp/maxf(1,float(ship.get("maxHp",1))));damaged[str(ship.id)]=true
		if ratio<.35 and old>=.35:
			var heavy:Dictionary={"kind":"heavy","title":"严重受损 · "+str(ship.get("name","本舰")),"priority":4,"color":Color("ce775b"),"icon":"repair"}
			_add_mark("heavy",Vector2(float(ship.x),float(ship.y)),heavy.color)
			if selected.is_empty() or int(selected.priority)<4:selected=heavy
	# A fatal hit removes the ship from the live roster. Its seat-visible damage event
	# still carries the impact point; use it once when no current HP delta handled it.
	for event in pending_damage:
		if tick-int(event.get("tick",0))>2:continue
		var ship:Dictionary=impact.firing_ship(event,{"ships":view.get("ships",[])})
		if ship.is_empty():ship=impact.firing_ship(event,{"ships":_own_ships.values()})
		if ship.is_empty() and event.has("x") and event.has("y"):ship={"id":"impact-"+str(event.get("id","")),"x":event.x,"y":event.y}
		if ship.is_empty() or damaged.has(str(ship.id)):continue
		ship=ship.duplicate(true)
		if event.has("x") and event.has("y"):ship.x=event.x;ship.y=event.y
		impact.hurt(ship,.08 if not view.get("ships",[]).any(func(row):return str(row.id)==str(ship.id)) else .015)
		damaged[str(ship.id)]=true
	_own_ships.clear()
	for ship in view.get("ships",[]):_own_ships[str(ship.id)]=ship.duplicate(true)
	if not selected.is_empty():_announce(selected,tick)
	_last_tick=tick
	# The authority's visible event window is bounded; compact our local cursor too.
	if _seen.size()>2048:
		_seen.clear()
		for event in view.get("events",[]):_seen[_event_key(event)]=true
func _on_screen(ship:Dictionary)->bool:
	if _map==null:return false
	var sea=_map.get_ref()
	return is_instance_valid(sea) and Rect2(Vector2.ZERO,sea.size).grow(40).has_point(sea.project(Vector2(float(ship.get("x",0)),float(ship.get("y",0)))))
func _cue(event:Dictionary)->Dictionary:
	var kind:=str(event.get("kind",""))
	var voice:=str(event.get("voiceCue",event.get("voice_cue","")))
	if kind=="torpedo_detected" or voice.begins_with("torpedo_warning"):return {"kind":"torpedo","title":"鱼雷来袭 · 改变航向","priority":5,"color":Color("d77b56"),"icon":"ammo"}
	match kind:
		"critical","protected":return {"kind":"critical","title":"损管告警 · 检查舰况" if kind=="critical" else "舰娘退出战斗 · 注意撤离","priority":3,"color":Color("c6815d"),"icon":"repair"}
		"creature_warning":return {"kind":"warning","title":"实体正在蓄力 · 留意海面预警","priority":3,"color":Color("ca8159"),"icon":"shield"}
		"damage","creature_hit":return {"kind":"damage","title":"舰体受损 · 保持机动","priority":2,"color":Color("cc8d72"),"icon":"shield"}
		"hit":return {"kind":"hit","title":"命中确认","priority":0,"color":Color("f2d291"),"icon":"check"}
		"salvage","cargo_stowed":return {"kind":"pickup","title":"物资已入舱","priority":1,"color":Color("4eafa1"),"icon":"cargo"}
		"cargo_revealed":return {"kind":"search","title":"发现物资 · 可选择装载","priority":1,"color":Color("559eaf"),"icon":"search"}
		"cargo_search_complete":return {"kind":"search_complete","title":"搜索完成 · 选择带走的物资","priority":1,"color":Color("559eaf"),"icon":"search"}
	return {}
func _announce(cue:Dictionary,tick:int)->void:
	if str(cue.kind)==_last_kind and _notice_age<1.0:return
	if notice.visible and _notice_age<notice_duration*.7 and int(cue.priority)<_priority:return
	caption.text=str(cue.title);_tint(cue.color,str(cue.icon))
	_notice_age=0;_priority=int(cue.priority);_last_kind=str(cue.kind)
	notice.show()
	notice_history.append({"kind":_last_kind,"title":caption.text,"tick":tick})
	if notice_history.size()>32:notice_history.pop_front()
func _add_mark(kind:String,point:Vector2,color:Color)->void:
	for mark in _marks:
		if str(mark.kind)==kind and (mark.point as Vector2).distance_to(point)<300:return
	_marks.append({"kind":kind,"point":point,"color":color,"age":0.0})
	while _marks.size()>maximum_marks:_marks.pop_front()
	queue_redraw()
func _draw()->void:
	if _map==null:return
	var sea=_map.get_ref()
	if not is_instance_valid(sea):return
	var transform:Transform2D=get_global_transform_with_canvas().affine_inverse()*sea.get_global_transform_with_canvas()
	for pulse in impact.pulses:
		var p:Vector2=transform*sea.project(pulse.point)
		var t:float=clampf(float(pulse.age)/float(pulse.duration),0,1)
		var alpha:float=pow(1-t,2)
		var radius:float=7.0+float(pulse.power)*1.6+10*t
		var color:=Color(1,.8,.43,alpha*.9) if str(pulse.kind)=="fire" else Color(1,.55,.36,alpha*.8)
		if str(pulse.kind)=="fire":
			var direction:Vector2=-pulse.direction
			for i in range(3):
				var ray:Vector2=direction.rotated((i-1)*.4)
				draw_line(p+ray*5,p+ray*radius,color,2.0,true)
		else:
			draw_arc(p,radius,0,TAU,24,color,2.0,true)
	for mark in _marks:
		var p:Vector2=get_global_transform_with_canvas().affine_inverse()*sea.get_global_transform_with_canvas()*sea.project(mark.point)
		if not Rect2(Vector2(12,12),size-Vector2(24,24)).has_point(p):continue
		var t:=clampf(float(mark.age)/mark_duration,0,1)
		var color:Color=mark.color;color.a=(1-t)*.9
		var radius:=10.0+18.0*(1-pow(1-t,2))
		draw_arc(p,radius,0,TAU,32,color,2.2,true)
		if str(mark.kind)=="hit":
			for i in range(4):
				var direction:=Vector2.from_angle(PI*.25+PI*.5*i)
				draw_line(p+direction*(radius+3),p+direction*(radius+10-5*t),color,2,true)
