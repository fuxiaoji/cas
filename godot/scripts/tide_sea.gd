extends "res://scripts/sea_map.gd"
## Retained arcade renderer. Shared historic/expedition rendering stays untouched.
const Actor=preload("res://scripts/tide_entity.gd")
var world_seed:int=42
var actors:Dictionary={}
var drops:Dictionary={}
var warnings:Dictionary={}
var effects:Array[Dictionary]=[]
var _frames:Dictionary={}
var _seen:Dictionary={}
var _last_tick:=-1.0
var _epoch:=-1
var _sample_age:=1.0
var _sample_span:=.1
var _clock:=0.0
var _readonly:=false
var presentation_running:=false
var motion_strength:=.75
var _trauma:=0.0
var _team_hp:=-1.0
var _joins:Array=[]
var _scenery:Node2D
var _actors_layer:Node2D
var _effects_layer:Node2D
var update_usec:=0
var _visible_count:=0
class Scenery extends Node2D:
	var blocks:Array=[]
	func _draw()->void:
		for block in blocks:
			var rect:=Rect2(block.p-block.extent*.5,block.extent)
			draw_rect(rect,Color(.04,.29,.36,.40));draw_rect(rect,Color(.48,.82,.74,.25),false,12)
			for x in 2:draw_rect(Rect2(rect.position+Vector2(35+x*80,35),Vector2(35,45)),Color(.31,.66,.64,.32))
func _ready()->void:
	clip_contents=true;mouse_filter=Control.MOUSE_FILTER_STOP;font=Design.font(500)
	sea_background=ColorRect.new();sea_background.name="ProceduralTideWater";sea_background.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(sea_background);sea_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sea_material=ShaderMaterial.new();sea_material.shader=preload("res://shaders/tide_water.gdshader");sea_material.set_shader_parameter("seed",float(world_seed%10007));sea_background.material=sea_material
	_scenery=Scenery.new();_scenery.name="CachedSubmergedCity";add_child(_scenery)
	var rng:=RandomNumberGenerator.new();rng.seed=world_seed^718432
	for i in 42:_scenery.blocks.append({"p":Vector2(rng.randf_range(1000,23000),rng.randf_range(900,13100)),"extent":Vector2(rng.randf_range(110,290),rng.randf_range(180,460))})
	_actors_layer=Node2D.new();_actors_layer.name="RetainedActors";add_child(_actors_layer)
	_effects_layer=Node2D.new();_effects_layer.name="BoundedImpacts";add_child(_effects_layer)
func _draw()->void:pass
func _gui_input(event:InputEvent)->void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT and event.pressed and not event.double_click:point_selected.emit(unproject(event.position));accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:zoom=clampf(zoom*(1.12 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.12),1.0,4.0);accept_event()
func _get_tooltip(at_position:Vector2)->String:
	for row in view.get("contacts",[]):
		if project(pos(row)).distance_to(at_position)<38:return "%s · %.0f/%.0f\n%s"%[str(row.get("name","异种")),float(row.get("health",0)),float(row.get("max_health",1)),str(row.get("attack",{}).get("counter","保持移动"))]
	return ""
func _texture(row:Dictionary,kind:String)->Texture2D:
	if kind=="ship":
		var identity:String=str(row.get("characterId",""))
		textures[identity]=Art.texture(str(Art.projection(cards.get(identity,{})).path))
		return textures[identity]
	if kind!="contact":return null
	var species:String=str(row.get("visualType",row.get("species","scavenger")))
	if not _frames.has(species):_frames[species]=CasEnemyAnimation.frames_for(species,textures)
	var frames:SpriteFrames=_frames[species]
	if frames==null:return null
	var pose:String="windup" if str(row.get("attack",{}).get("state",""))=="windup" else "swim"
	if float(row.get("hurt_tick",-100))>=float(view.get("tick",0))-.15:pose="hurt"
	return frames.get_frame_texture(pose,0) if frames.has_animation(pose) else frames.get_frame_texture("idle",0)
func observe(next:Dictionary,readonly:bool=false,epoch:int=0,running:bool=false,rate:float=1.0)->void:
	var tick:float=float(next.get("tick",0));var reset:bool=_last_tick<0 or tick<_last_tick or epoch!=_epoch or readonly!=_readonly
	var changed:bool=reset or tick>_last_tick+.000001
	view=next;presentation_running=running;_readonly=readonly;_epoch=epoch
	if reset:
		_seen.clear();_joins.clear();_trauma=0;combat_offset=Vector2.ZERO
		for effect in effects:effect.node.queue_free()
		effects.clear();_team_hp=-1
	if changed:
		_sample_span=clampf((tick-_last_tick)/maxf(rate,.1),.016,1.0) if not reset else .1;_sample_age=0
	var present:Dictionary={}
	for kind in ["ship","contact","shell","torpedo"]:
		for row in next.get({"ship":"ships","contact":"contacts","shell":"shells","torpedo":"torpedoes"}[kind],[]):
			var key:String=kind+":"+str(row.id);present[key]=true;var fresh:bool=not actors.has(key)
			if fresh:actors[key]=Actor.new();_actors_layer.add_child(actors[key])
			var actor=actors[key]
			if changed or fresh:actor.world_from=pos(row) if reset or fresh else actor.world_now;actor.world_to=pos(row)
			var display:Dictionary=row
			if kind=="contact":
				display=row.duplicate();display["display_hurt"]=float(row.get("hurt_tick",-100))>=tick-.15
			elif kind=="shell":
				display=row.duplicate()
				for ship in next.get("ships",[]):
					if int(ship.id)==int(row.get("own_ship",-1)):display["display_caliber"]=ship.get("mainCaliberMm",100);break
			actor.configure(display,kind,_texture(row,kind),(88.0 if bool(row.get("boss",false)) else 58.0) if kind=="contact" else 67.0)
			if kind=="contact":actor.animation=_frames.get(str(row.get("visualType",row.get("species","scavenger"))))
	for key in actors.keys():
		if not present.has(key):actors[key].queue_free();actors.erase(key)
	_sync_drops();_sync_warnings()
	for member in next.get("tide",{}).get("members",[]):
		var key:String="join:"+str(member.get("joined_sequence",member.get("ship_id",0)))
		if not _seen.has(key) and not reset and not readonly:
			_joins.append(member.duplicate())
			for ship in next.get("ships",[]):
				if int(ship.id)==int(member.ship_id):_effect(pos(ship),Color("a7ffe0"),48,.6)
		_seen[key]=true
	for shot in next.get("tide",{}).get("shots",[]):
		var key:String="shot:"+str(shot.id)
		if not _seen.has(key) and not reset and not readonly:
			var heavy:bool=float(shot.get("caliber_mm",0))>=200
			_effect(pos(shot),Color("fff0b1") if heavy else Color("c8fff0"),20 if heavy else 8,.15 if heavy else .09)
			if heavy:_trauma=minf(.55,_trauma+.14)
		_seen[key]=true
	for shot in next.get("tide",{}).get("impacts",[]):
		var key:String="impact:"+str(shot.id)
		if not _seen.has(key) and not reset and not readonly:_effect(pos(shot),Color("ffe3a3") if str(shot.get("kind",""))!="torpedo" else Color("a1f4ee"),clampf(float(shot.get("radius",120))*.07,12,62),.38)
		_seen[key]=true
	var own:Array=next.get("ships",[]);var hp:float=float(next.get("tide",{}).get("team_hp",own[0].get("hp",0) if not own.is_empty() else 0))
	if not reset and not readonly and _team_hp>=0 and hp<_team_hp:_trauma=minf(1,_trauma+clampf((_team_hp-hp)/60,.12,.5))
	_team_hp=hp;_last_tick=tick
	if _seen.size()>2048:
		_seen.clear()
		for member in next.get("tide",{}).get("members",[]):_seen["join:"+str(member.get("joined_sequence",member.get("ship_id",0)))]=true
		for entry in next.get("tide",{}).get("impacts",[]):_seen["impact:"+str(entry.id)]=true
		for entry in next.get("tide",{}).get("shots",[]):_seen["shot:"+str(entry.id)]=true
func drain_joins()->Array:
	var output:Array=_joins;_joins=[];return output
func _sync_drops()->void:
	var present:Dictionary={};var rows:Array=view.get("tide",{}).get("drops",[]).duplicate()
	var own:Array=view.get("ships",[]);var center:Vector2=pos(own[0]) if not own.is_empty() else Vector2.ZERO
	rows.sort_custom(func(a,b):return pos(a).distance_squared_to(center)<pos(b).distance_squared_to(center))
	for row in rows.slice(0,96):
		var key:String=str(row.id);present[key]=true
		if not drops.has(key):
			var diamond:=Polygon2D.new();diamond.polygon=PackedVector2Array([Vector2(0,-5),Vector2(4,0),Vector2(0,5),Vector2(-4,0)]);diamond.color=Color("b4ffe7");_actors_layer.add_child(diamond);drops[key]=diamond
		drops[key].set_meta("world",pos(row))
	for key in drops.keys():
		if not present.has(key):drops[key].queue_free();drops.erase(key)
func _sync_warnings()->void:
	var present:Dictionary={}
	for row in view.get("salvage",{}).get("telegraphs",[]):
		var key:String=str(row.id);present[key]=true
		if not warnings.has(key):
			var circle:=Line2D.new();circle.width=.045;circle.default_color=Color("ffad86");circle.closed=true;var points:=PackedVector2Array()
			for i in 32:points.append(Vector2.from_angle(float(i)*TAU/32))
			circle.points=points;_effects_layer.add_child(circle);warnings[key]=circle
		warnings[key].set_meta("row",row)
	for key in warnings.keys():
		if not present.has(key):warnings[key].queue_free();warnings.erase(key)
func _effect(world:Vector2,color:Color,radius:float,duration:float)->void:
	if effects.size()>=24:return
	var circle:=Line2D.new();circle.closed=true;circle.width=.065;circle.default_color=color;var points:=PackedVector2Array()
	for i in 24:points.append(Vector2.from_angle(float(i)*TAU/24))
	circle.points=points;_effects_layer.add_child(circle);effects.append({"node":circle,"world":world,"age":0.0,"radius":radius,"duration":duration})
func _process(delta:float)->void:
	if view.is_empty():return
	var began:int=Time.get_ticks_usec();_clock+=delta;_sample_age+=delta
	var ratio:float=clampf(_sample_age/_sample_span,0,1) if presentation_running and not _readonly else 1.0
	for actor in actors.values():actor.world_now=actor.world_from.lerp(actor.world_to,ratio)
	if not view.get("ships",[]).is_empty():
		var leader=actors.get("ship:"+str(view.ships[0].id))
		if leader!=null:pan+=(size*.5-project(leader.world_now)+combat_offset)*(1-exp(-delta*5))
	_trauma=maxf(0,_trauma-delta*2.8);combat_offset=Vector2(sin(_clock*73),cos(_clock*61))*_trauma*_trauma*6*motion_strength
	var origin:Vector2=project(Vector2.ZERO);var s:float=project(Vector2(1,0)).x-origin.x
	_scenery.position=origin;_scenery.scale=Vector2(s,-s)
	sea_material.set_shader_parameter("visual_time",_clock);sea_material.set_shader_parameter("world_origin",unproject(Vector2.ZERO));sea_material.set_shader_parameter("world_span",unproject(size)-unproject(Vector2.ZERO))
	var visible_rect:=Rect2(Vector2.ZERO,size).grow(100);_visible_count=0
	for actor in actors.values():
		var at:Vector2=project(actor.world_now);actor.visible=visible_rect.has_point(at)
		if actor.visible:actor.place(at,_clock);_visible_count+=1
	for drop in drops.values():drop.position=project(drop.get_meta("world"));drop.visible=visible_rect.has_point(drop.position)
	for warning in warnings.values():
		var row:Dictionary=warning.get_meta("row");warning.position=project(pos(row));warning.scale=Vector2.ONE*float(row.get("radius",300))*s;warning.modulate.a=.65+.25*sin(_clock*8)
	for effect in effects:
		effect.age+=delta;var progress:float=clampf(float(effect.age)/float(effect.duration),0,1);effect.node.position=project(effect.world);effect.node.scale=Vector2.ONE*float(effect.radius)*(.25+.75*progress);effect.node.modulate.a=(1-progress)*(1-progress)
	for index in range(effects.size()-1,-1,-1):
		if effects[index].age>=effects[index].duration:effects[index].node.queue_free();effects.remove_at(index)
	update_usec=Time.get_ticks_usec()-began
func metrics()->Dictionary:return {"actors":actors.size(),"visible_actors":_visible_count,"drops":drops.size(),"warnings":warnings.size(),"effects":effects.size(),"update_usec":update_usec}
