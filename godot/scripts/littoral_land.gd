@tool
extends Control
signal point_selected(point:Vector2,target:Variant,kind:String)
signal actor_drag_requested(row:Dictionary,point:Vector2,pointer:int)
signal actor_drag_cancelled
signal camera_changed
const Design=preload("res://scripts/ui_design.gd")
const TacticalSprite=preload("res://scenes/ui/tactical_sprite.tscn")
const BuildingArt=preload("res://scripts/home_building_art.gd")
const TransportArt=preload("res://scripts/tactical_transport_art.gd")
const Terrain=preload("res://scripts/procedural_amphibious_terrain.gd")
const TerrainBackdrop=preload("res://scripts/littoral_terrain_backdrop.gd")
const CoastMotion=preload("res://scripts/littoral_coast_motion.gd")
const World3DSettings=preload("res://scripts/world3d_settings.gd")
var world3d:Control
@export var terrain_color:Color=Color("7c9270")
var land:Dictionary={}
var selected_unit:String="":
	set(value):
		if selected_unit==value:return
		selected_unit=value
		if is_instance_valid(actor_layer):_resize_visuals()
var aim:bool=false
@export_range(30,70,1) var friendly_sprite_height:float=58
@export_range(24,60,1) var enemy_sprite_height:float=40
@export_range(1.0,2.0,.05) var vehicle_readability_scale:float=1.0
@export_range(3,5,.1) var defeat_hold_seconds:float=4
var font:Font
var actors:Dictionary={}
var previous_rows:Dictionary={}
var previous_groups:Dictionary={}
var shot_ids:Dictionary={}
var previous_tick:float=-1
var visual_tick:float=0
var playing:bool=false
var actor_layer:Node2D
var catalogue:Dictionary={}
var identity_cards:Dictionary={}
var reset_pending:bool=true
var display_offsets:Dictionary={}
var transport_keys:Dictionary={}
var environment_cache:Dictionary={}
var zoom:float=1
var camera_center:Vector2=Vector2.ZERO
var miniature:bool=false
var drag_point:Vector2=Vector2.ZERO
var drag_valid:bool=false
var show_drag_target:bool=false
var playback_rate:float=1
var projection_dirty:bool=true
var projection_queued:bool=false
var company_offsets:Dictionary={}
var transport_offsets:Dictionary={}
var iso_frame_cache:Rect2
var iso_frame_valid:bool=false
var height_cache_valid:bool=false
var height_signature:int=0
var height_zones:Array[Dictionary]=[]
var height_ramps:Array[Dictionary]=[]
var level_heights:Dictionary={0:0.0}
var height_model:String=""
var terrain_backdrop:Control
var coast_motion:Control
var terrain_draw_key:int=0
var terrain_draw_key_valid:bool=false
var camera_pointer_down:bool=false
var camera_pointer_dragged:bool=false
var camera_pointer_origin:Vector2
var camera_pointer_last:Vector2
var camera_touch_points:Dictionary={}
var camera_gesture:bool=false
var camera_pinch_distance:float=0
var camera_pinch_center:Vector2
var camera_joy:Vector2=Vector2.ZERO
var actor_commands_enabled:bool=true
var actor_pointer_armed:bool=false
var support_fx:Control
var weapon_fx:Control
var motion_strength:float=1
var ocean:ColorRect
func _notification(what:int)->void:
	if what in [NOTIFICATION_FOCUS_EXIT,NOTIFICATION_APPLICATION_FOCUS_OUT]:
		camera_joy=Vector2.ZERO;camera_pointer_down=false;camera_touch_points.clear();camera_gesture=false;actor_pointer_armed=false
func _ready()->void:
	font=Design.font(500);clip_contents=true;texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS;resized.connect(_resize_visuals);focus_mode=Control.FOCUS_ALL
	ocean=ColorRect.new();ocean.name="ProceduralOcean";ocean.mouse_filter=Control.MOUSE_FILTER_IGNORE;ocean.show_behind_parent=true;ocean.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);ocean.visible=false
	var water:=ShaderMaterial.new();water.shader=preload("res://shaders/salvage_sea.gdshader");ocean.material=water;add_child(ocean)
	terrain_backdrop=TerrainBackdrop.new();terrain_backdrop.name="NativeTerrain";terrain_backdrop.source_map=self;terrain_backdrop.visible=false;add_child(terrain_backdrop)
	coast_motion=CoastMotion.new();coast_motion.name="ShorelineMotion";coast_motion.source_map=self;coast_motion.visible=false;add_child(coast_motion)
	actor_layer=Node2D.new();actor_layer.name="Bodies";add_child(actor_layer)
	support_fx=preload("res://scripts/littoral_support_fx.gd").new();support_fx.name="AuthoritativeSupportFX";support_fx.source_map=self;support_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(support_fx)
	weapon_fx=preload("res://scripts/tactical_weapon_fx_v3.gd").new();weapon_fx.name="ActualWeaponTraces";weapon_fx.source_map=self;weapon_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(weapon_fx)
	var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/tactical-units-v1.json"))
	if raw is Dictionary:
		for row in raw.get("units",[]):catalogue[str(row.id)]=str(row.get("sprite_sheet",""));identity_cards[str(row.id)]=row
func prime_visuals()->void:reset_pending=true
func set_playing(value:bool)->void:playing=value
func set_miniature(value:bool)->void:
	miniature=value
	camera_joy=Vector2.ZERO;camera_pointer_down=false;camera_touch_points.clear();camera_gesture=false
	if actor_layer!=null:actor_layer.visible=not value
	_resize_visuals()
	queue_redraw()
func _resize_visuals()->void:
	iso_frame_valid=false
	height_cache_valid=false
	projection_dirty=true
	if not projection_queued:projection_queued=true;_sync_projection.call_deferred()
	queue_redraw()
func _sync_projection()->void:
	projection_queued=false
	if is_instance_valid(world3d):
		_sync_world3d_camera();projection_dirty=false;queue_redraw();return
	if not is_instance_valid(actor_layer):return
	if not miniature:display_offsets=_spread_positions(land.get("entities",[]).filter(_body_visible))
	transport_offsets={} if str(land.get("equipment_version","")) in ["tactical-vehicles-v3","tactical-vehicles-v4"] else TransportArt.screen_offsets(land.get("transports",[]),project)
	for row in land.get("entities",[]):
		var key:int=int(row.id)
		if actors.has(key):
			actors[key].display_height=_entity_height(row,company_key(row)==selected_unit)
			actors[key].reproject(project(pos(row))+display_offsets.get(key,Vector2.ZERO))
			actors[key].queue_redraw()
	for row in land.get("corpses",[]):
		var key:int=int(row.get("id",0))
		if actors.has(key):
			actors[key].display_height=_body_height(str(row.get("side","axis"))=="allies",false)
			actors[key].reproject(project(pos(row)))
			actors[key].queue_redraw()
	for row in land.get("transports",[]):
		var key:int=-int(row.id)-1
		if actors.has(key):
			actors[key].display_height=_transport_height(row)
			actors[key].reproject(project(pos(row))+transport_offsets.get(int(row.id),Vector2.ZERO))
	projection_dirty=false;_refresh_terrain_backdrop();_restack();queue_redraw()
func _clear_actors()->void:
	for actor in actors.values():actor_layer.remove_child(actor);actor.queue_free()
	actors.clear();previous_rows.clear();previous_groups.clear();shot_ids.clear();transport_keys.clear();display_offsets.clear();company_offsets.clear()
func observe(value:Dictionary,is_playing:bool=false)->void:
	land=value;playing=is_playing;iso_frame_valid=false
	if World3DSettings.eligible(value):
		_observe_world3d(value,is_playing);return
	if is_instance_valid(world3d):
		world3d.get_parent().remove_child(world3d);world3d.queue_free();world3d=null
		if is_instance_valid(actor_layer):actor_layer.visible=not miniature
	var elevation_signature:int=hash(value.get("terrain",{}))
	if elevation_signature!=height_signature:height_signature=elevation_signature;height_cache_valid=false
	if not is_instance_valid(actor_layer):return
	var tick:float=float(value.get("tick",0));var elapsed:float=tick-previous_tick
	var reset:bool=reset_pending or previous_tick<0 or elapsed<-.00001
	var new_time:bool=reset or elapsed>.00001
	if reset:_clear_actors()
	if is_instance_valid(support_fx):support_fx.strength=motion_strength;support_fx.observe(value,reset)
	if is_instance_valid(weapon_fx):weapon_fx.observe(value,reset)
	visual_tick=tick;previous_tick=tick;reset_pending=false
	var groups:Dictionary={}
	for group in land.get("groups",[]):groups[str(group.id)]=str(group.get("stage",""))
	if not miniature and (new_time or projection_dirty):display_offsets=_spread_positions(land.get("entities",[]).filter(_body_visible))
	var rows:Dictionary={}
	var dense_friendly:bool=land.get("entities",[]).filter(func(row):return str(row.get("side","axis"))=="allies").size()>20
	var new_art:bool=str(land.get("art_version",""))=="tactical-art-v2"
	var death_ticks:Dictionary={}
	for corpse in land.get("corpses",[]):death_ticks[int(corpse.get("id",0))]=float(corpse.get("death_tick",tick))
	for entity in land.get("entities",[]):
		if str(land.get("equipment_version","")) in ["tactical-vehicles-v3","tactical-vehicles-v4"] and not entity.has("equipment_version"):entity=entity.duplicate();entity["equipment_version"]=str(land.equipment_version)
		var key:int=int(entity.get("id",0));rows[key]=entity
		var friendly:bool=str(entity.get("side","axis"))=="allies"
		if not actors.has(key):
			var actor=TacticalSprite.instantiate();actor.name="Body_%d"%key;actor_layer.add_child(actor)
			var path:String=str(catalogue.get(str(entity.get("unit_id","")),"")) if friendly else "res://assets/tactical/sprites/enemy-security-sheet.png"
			var card:Dictionary=identity_cards.get(str(entity.get("unit_id","")),{});var portrait:Texture2D
			if path.is_empty() and friendly:portrait=load("res://scripts/story_actor_layout.gd").portrait(load("res://scripts/character_art.gd").texture(str(card.get("portrait",""))),str(entity.get("unit_id","")))
			actor.configure(entity,path,friendly_sprite_height if friendly else enemy_sprite_height,portrait,str(card.get("role",entity.get("kind","infantry"))));actor.defeat_hold_seconds=defeat_hold_seconds;actors[key]=actor
		var actor=actors[key]
		actor.art_v2=new_art
		actor.visible=_body_visible(entity)
		actor.persistent_defeat=bool(land.get("persistent_corpses",false))
		actor.playback_rate=playback_rate
		actor.motion_projector=project
		actor.selected=company_key(entity)==selected_unit
		actor.compact_mode=not new_art and friendly and dense_friendly and not actor.selected
		actor.display_height=_entity_height(entity,actor.selected)
		var is_searching:bool=false
		if str(entity.get("order",""))=="search":
			for ruin in land.get("ruins",[]):
				if float(ruin.get("progress",0))>0 and not bool(ruin.get("searched",false)) and pos(entity).distance_to(pos(ruin))<350:is_searching=true
		actor.observe(entity,project(pos(entity))+display_offsets.get(key,Vector2.ZERO),tick,elapsed,is_searching)
		if projection_dirty or not playing:actor.reproject(project(pos(entity))+display_offsets.get(key,Vector2.ZERO))
		if not reset and previous_rows.has(key) and float(entity.get("hp",0))<float(previous_rows[key].get("hp",0))-.0001:actor.hurt(tick)
		if float(entity.get("hp",0))<=0:actor.defeat(float(death_ticks.get(key,tick)))
	# v4 casualty records survive a save or camera change without replaying death.
	for corpse in land.get("corpses",[]):
		var key:int=int(corpse.get("id",0));var friendly:bool=str(corpse.get("side","axis"))=="allies"
		var row:Dictionary=corpse.duplicate(true);row["hp"]=0;row["max_hp"]=1;rows[key]=row
		if not actors.has(key):
			var actor=TacticalSprite.instantiate();actor.name="Casualty_%d"%key;actor_layer.add_child(actor)
			var id:String=str(row.get("unit_id",""));var card:Dictionary=identity_cards.get(id,{})
			var path:String=str(catalogue.get(id,"")) if friendly else "res://assets/tactical/sprites/enemy-security-sheet.png"
			var portrait:Texture2D
			if friendly and path.is_empty():portrait=load("res://scripts/story_actor_layout.gd").portrait(load("res://scripts/character_art.gd").texture(str(card.get("portrait",""))),id)
			actor.configure(row,path,friendly_sprite_height if friendly else enemy_sprite_height,portrait,str(card.get("role","infantry")));actors[key]=actor
		var actor=actors[key];actor.persistent_defeat=true;actor.selected=false;actor.compact_mode=false
		actor.art_v2=new_art
		actor.visible=_body_visible(row)
		actor.display_height=_body_height(friendly,false)
		actor.observe(row,project(pos(row)),tick,elapsed,false)
		if reset or projection_dirty or not playing:actor.reproject(project(pos(row)))
		actor.facing_left=int(corpse.get("pose_seed",key))%2==0
		actor.defeat(float(corpse.get("death_tick",tick)));actor.clock=tick;actor._refresh()
	for key in previous_rows:
		if rows.has(key) or not actors.has(key):continue
		var old:Dictionary=previous_rows[key];var id:String=company_key(old);var friendly:bool=str(old.get("side","axis"))=="allies"
		var lost:bool=not friendly or (str(previous_groups.get(id,""))=="ground" and str(groups.get(id,"")) in ["ground","lost"])
		if lost:actors[key].defeat(tick)
		else:_remove_actor(key)
	var current_transports:Dictionary={}
	transport_offsets={} if str(land.get("equipment_version","")) in ["tactical-vehicles-v3","tactical-vehicles-v4"] else TransportArt.screen_offsets(land.get("transports",[]),project)
	for transport in land.get("transports",[]):
		var key:int=-int(transport.get("id",0))-1;current_transports[key]=true
		var row:Dictionary=transport.duplicate();row["id"]=key;row["side"]=str(transport.get("side","allies")) if new_art else "allies";row["transport_kind"]=str(transport.get("kind","landing_craft"));row["kind"]="transport_helicopter" if str(transport.get("kind",""))=="helicopter" else str(transport.get("kind","landing_craft"));row["_transport_visual"]=true
		if str(land.get("equipment_version","")) in ["tactical-vehicles-v3","tactical-vehicles-v4"]:row["equipment_version"]=str(land.equipment_version)
		if not actors.has(key):
			var actor=TacticalSprite.instantiate();actor.name="Transport_%d"%int(transport.id);actor_layer.add_child(actor)
			var id:String=str(row.get("unit_id",""));var card:Dictionary=identity_cards.get(id,{})
			var portrait:Texture2D=load("res://scripts/story_actor_layout.gd").portrait(load("res://scripts/character_art.gd").texture(str(card.get("portrait",""))),id)
			actor.configure(row,str(catalogue.get(id,"")),friendly_sprite_height,portrait,str(card.get("role","infantry")));actors[key]=actor
		actors[key].selected=company_key(row)==selected_unit
		actors[key].display_height=_transport_height(row)
		actors[key].art_v2=new_art
		actors[key].motion_projector=project
		actors[key].playback_rate=playback_rate
		actors[key].observe(row,project(pos(row))+transport_offsets.get(int(transport.id),Vector2.ZERO),tick,elapsed,false)
		if projection_dirty or not playing:actors[key].reproject(project(pos(row))+transport_offsets.get(int(transport.id),Vector2.ZERO))
	for key in transport_keys:
		if not current_transports.has(key) and actors.has(key):_remove_actor(key)
	transport_keys=current_transports
	var current_shots:Dictionary={}
	for shot in land.get("shots",[]):
		var id:int=int(shot.get("id",0));current_shots[id]=true
		if shot_ids.has(id) or tick-float(shot.get("tick",-100))>.4:continue
		if reset and str(shot.get("equipment_version","")) not in ["tactical-vehicles-v3","tactical-vehicles-v4"]:continue
		var source:String=str(shot.get("source",""))
		if str(shot.get("equipment_version","")) in ["tactical-vehicles-v3","tactical-vehicles-v4"] and shot.get("operator_id")!=null:
			# Native v3 source names the company; operator_id identifies the one
			# body or independent vehicle that really emitted this shot.
			var operator:int=int(shot.operator_id)
			if actors.has(operator):actors[operator].fire(tick,project(Vector2(float(shot.get("target_x",0)),float(shot.get("target_y",0)))),shot)
		elif source.begins_with("body:") or source.begins_with("vehicle:"):
			var body:int=int(source.get_slice(":",1))
			if actors.has(body):actors[body].fire(tick,project(Vector2(float(shot.get("target_x",0)),float(shot.get("target_y",0)))),shot)
		elif str(shot.get("kind",""))=="air_support":
			# Native publishes the support helicopter's unit identity rather than its body ID.
			for row in land.get("entities",[]):
				if source in [str(row.get("unit_id","")),company_key(row)] and bool(row.get("airborne",false)) and actors.has(int(row.id)):
					actors[int(row.id)].fire(tick,project(Vector2(float(shot.get("target_x",0)),float(shot.get("target_y",0)))),shot);break
		elif str(shot.get("kind",""))=="transport_gunship":
			for transport in land.get("transports",[]):
				var key:int=-int(transport.get("id",0))-1
				if source in [str(transport.get("unit_id","")),company_key(transport),"transport:"+str(transport.get("id",0))] and actors.has(key):actors[key].fire(tick,project(Vector2(float(shot.get("target_x",0)),float(shot.get("target_y",0)))),shot)
	# Public observations are replaced, never mutated by the renderer. Keep the
	# prior rows for hit/death transitions without deep-copying every body at 10Hz.
	shot_ids=current_shots;previous_rows=rows;previous_groups=groups;projection_dirty=false
	_refresh_terrain_backdrop();_restack();queue_redraw()
func _refresh_terrain_backdrop()->void:
	if is_instance_valid(world3d):
		if is_instance_valid(ocean):ocean.hide()
		if is_instance_valid(terrain_backdrop):terrain_backdrop.hide()
		if is_instance_valid(coast_motion):coast_motion.hide()
		return
	if not is_instance_valid(terrain_backdrop):return
	if is_instance_valid(ocean):
		ocean.visible=str(land.get("art_version",""))=="tactical-art-v2"
		if ocean.visible:
			var bounds:Rect2=source_bounds();var span:Vector2=bounds.size/maxf(1,zoom)*1.6
			var weather:Dictionary=land.get("weather",{})
			var origin:Vector2=unproject_base(Vector2.ZERO)
			ocean.material.set_shader_parameter("affine_world",true)
			ocean.material.set_shader_parameter("world_origin",origin);ocean.material.set_shader_parameter("world_span",span)
			ocean.material.set_shader_parameter("world_axis_x",unproject_base(Vector2(size.x,0))-origin)
			ocean.material.set_shader_parameter("world_axis_y",unproject_base(Vector2(0,size.y))-origin)
			ocean.material.set_shader_parameter("island_style",1.0)
			ocean.material.set_shader_parameter("night_amount",float(weather.get("night_amount",0)))
			ocean.material.set_shader_parameter("overcast",clampf(float(weather.get("overcast",.12)),0,1));ocean.material.set_shader_parameter("wind_speed",float(weather.get("wind_speed",8)))
			ocean.material.set_shader_parameter("adventure_theme",1)
	terrain_backdrop.visible=_isometric() and land.get("polygon",[]).size()>2
	coast_motion.visible=terrain_backdrop.visible and not miniature;coast_motion.size=size
	if not terrain_backdrop.visible:return
	terrain_backdrop.size=size
	# Tick and moving bodies do not alter static streets, slopes or vegetation.
	var next:int=hash([land.get("polygon",[]),land.get("obstacles",[]),land.get("town",{}),land.get("terrain",{}),land.get("seed",0),land.get("buildings",[]).map(func(row):return {"id":row.id,"x":row.x,"y":row.y}),land.get("ruins",[]).map(func(row):return {"id":row.id,"x":row.x,"y":row.y}),size,zoom,camera_center,miniature])
	if not terrain_draw_key_valid or next!=terrain_draw_key:terrain_draw_key=next;terrain_draw_key_valid=true;terrain_backdrop.queue_redraw();coast_motion.queue_redraw()
func paint_static_terrain(canvas:CanvasItem)->void:
	if not is_instance_valid(ocean) or not ocean.visible:canvas.draw_rect(Rect2(Vector2.ZERO,size),Color("3c7480"))
	var protected:Array=[]
	for kind in ["buildings","ruins"]:
		for row in land.get(kind,[]):protected.append(pos(row))
	Terrain.paint(canvas,land.get("polygon",[]),project,int(land.get("seed",0)),0,0 if miniature else 2,protected,land.get("town",{}),land.get("terrain",{}),project_base,false)
	var town_footprints:Dictionary={}
	for building in land.get("town",{}).get("buildings",[]):town_footprints[hash(_terrain_points(building.get("footprint",[])))]=true
	for raw in land.get("obstacles",[]):
		var points:PackedVector2Array=_terrain_points(raw.get("polygon",[]) if raw is Dictionary else raw)
		if not town_footprints.has(hash(points)):_draw_rock_field(points,canvas)
func _spread_positions(rows:Array)->Dictionary:
	# New ground rules own each body's position and collision. Moving the drawing
	# into screen-space company slots would hide avoidance and detach its feet.
	if str(land.get("art_version",""))=="tactical-art-v2":return {}
	# Persistent bounded visual slots plus spatial hashing. Fifty bodies no longer
	# scan every prior body for every one of 121 candidate offsets on every update.
	# The actual command/weapon positions remain unchanged and selected feet link back.
	var offsets:Dictionary={};var buckets:Dictionary={};var ordered:Array=rows.duplicate()
	var friendly:Array=rows.filter(func(row):return str(row.get("side","axis"))=="allies")
	if friendly.size()>20:
		offsets=_company_slots(friendly)
		for row in friendly:
			var point:Vector2=project(pos(row))+offsets.get(int(row.id),Vector2.ZERO)
			var cell:=Vector2i(floori(point.x/34),floori(point.y/34))
			if not buckets.has(cell):buckets[cell]=[]
			buckets[cell].append(point)
		ordered=rows.filter(func(row):return str(row.get("side","axis"))!="allies")
	ordered.sort_custom(func(a,b):return int(a.id)<int(b.id))
	for row in ordered:
		var id:int=int(row.get("id",0));var center:Vector2=project(pos(row));var chosen:Vector2=Vector2.ZERO
		var gap:float=clampf(_body_height(str(row.get("side","axis"))=="allies",company_key(row)==selected_unit)*.8,9,29) if _isometric() else 29
		var reach:float=clampf(gap*5,40,160)
		var candidates:Array[Vector2]=[display_offsets.get(id,Vector2.ZERO),Vector2.ZERO]
		var old:Vector2=candidates[0]
		for ring in range(1,10):
			for direction in range(20):candidates.append(Vector2.from_angle(direction*TAU/20+fposmod(id*.7,TAU))*minf(reach,ring*gap*.65))
		var best_score:float=-INF
		for offset in candidates:
			var candidate:Vector2=center+offset
			if candidate.x<30 or candidate.x>size.x-30 or candidate.y<166 or candidate.y>size.y-18:continue
			var nearest:float=999
			var cell:=Vector2i(floori(candidate.x/34),floori(candidate.y/34))
			for dx in range(-1,2):
				for dy in range(-1,2):
					for point in buckets.get(cell+Vector2i(dx,dy),[]):nearest=minf(nearest,candidate.distance_to(point))
			var score:float=minf(nearest,gap+2)-offset.length()*.018-offset.distance_to(old)*.065
			if score>best_score:best_score=score;chosen=offset
			if nearest>=gap and offset==old:break
		offsets[id]=chosen
		var slot:=Vector2i(floori((center.x+chosen.x)/34),floori((center.y+chosen.y)/34))
		if not buckets.has(slot):buckets[slot]=[]
		buckets[slot].append(center+chosen)
	return offsets
func _company_slots(rows:Array)->Dictionary:
	var grouped:Dictionary={};var offsets:Dictionary={};var reserved:Array[Rect2]=[]
	for row in rows:
		var id:String=company_key(row)
		if not grouped.has(id):grouped[id]=[]
		grouped[id].append(row)
	var identities:Array=grouped.keys();identities.sort()
	if identities.has(selected_unit):identities.erase(selected_unit);identities.push_front(selected_unit)
	for id in identities:
		var members:Array=grouped[id];members.sort_custom(func(a,b):return int(a.id)<int(b.id))
		var center:Vector2=Vector2.ZERO
		for row in members:center+=project(pos(row))
		center/=members.size()
		var spacing:float=(clampf(_body_height(true,id==selected_unit)*.85+3,10,27) if _isometric() else (38 if id==selected_unit else 23))
		var half:=Vector2(spacing*2.5,_body_height(true,id==selected_unit)+8 if _isometric() else (60 if id==selected_unit else 28))
		var candidates:Array[Vector2]=[company_offsets.get(id,Vector2.ZERO),Vector2.ZERO]
		for ring in range(1,10):
			for direction in range(16):candidates.append(Vector2.from_angle(direction*TAU/16)*ring*(maxf(12,spacing) if _isometric() else 30))
		var chosen:Vector2=Vector2.ZERO;var best:float=-INF
		for candidate in candidates:
			var point:Vector2=center+candidate
			var box:=Rect2(point-half,half*2).grow(10)
			if box.position.x<24 or box.end.x>size.x-24 or box.position.y<155 or box.end.y>size.y-22:continue
			var overlap:float=0
			for other in reserved:
				var area:Rect2=box.intersection(other)
				if area.has_area():overlap+=area.get_area()
			var score:float=-overlap*.2-candidate.length()*.1-candidate.distance_to(company_offsets.get(id,Vector2.ZERO))*.025
			if score>best:best=score;chosen=candidate
			if overlap==0 and candidate==company_offsets.get(id,Vector2.ZERO):break
		company_offsets[id]=chosen;reserved.append(Rect2(center+chosen-half,half*2).grow(10))
		for index in range(members.size()):
			var slot:=Vector2((index%5-2)*spacing,(floori(index/5.0)-.5)*spacing)
			offsets[int(members[index].id)]=center+chosen+slot-project(pos(members[index]))
	return offsets
func _body_height(friendly:bool,is_selected:bool)->float:
	if not _isometric():return friendly_sprite_height*(1.0 if is_selected else .86) if friendly else enemy_sprite_height
	# The overview reads as a crowd. Zooming into a company reveals her SD while
	# keeping feet at the same native center and leaving room for real avoidance.
	var height:float=clampf(_screen_scale()*40,9,90)
	# Keep a positive, continuous relationship to map magnification. The old
	# 42px ceiling made buildings keep growing while the same SD stopped growing.
	if str(land.get("art_version",""))=="tactical-art-v2":height=clampf(_screen_scale()*14,6 if miniature else 8,112)
	return height*(1.0 if is_selected else .88) if friendly else height*.8
func _entity_height(row:Dictionary,is_selected:bool)->float:
	if str(land.get("equipment_version","")) in ["tactical-vehicles-v3","tactical-vehicles-v4"] and not str(row.get("vehicle_kind","")).is_empty():
		var equipment:Dictionary=row.duplicate();equipment["kind"]=str(row.vehicle_kind);equipment["equipment_version"]=str(land.equipment_version)
		var spec:Dictionary=TransportArt.specification(equipment)
		return _equipment_length(spec,is_selected)/2.1
	return _body_height(str(row.get("side","axis"))=="allies",is_selected)
func _equipment_length(spec:Dictionary,is_selected:bool)->float:
	var measured:float=float(spec.get("length",12))*_screen_scale()
	if miniature:return clampf(measured,5,42)
	# SD infantry is deliberately larger than a 1.7 m body at tactical zoom.
	# Equipment shares that readability convention; physics and sea scale do not.
	var ratio:float=float({"kayak":1.7,"fast_boat":2.1,"armored_boat":2.5,"landing_craft":2.8,"heavy_lander":3.5,"amphibious_vehicle":2.8,"tank":3.6,"self_propelled_gun":3.0,"attack_helicopter":3.6,"transport_helicopter":4.2,"transport_aircraft":5.0,"aa_turret":1.6}.get(str(spec.get("equipment_kind","")),2.8))
	return clampf(maxf(measured,_body_height(true,is_selected)*ratio)*vehicle_readability_scale,10,600)
func _remove_actor(key:int)->void:
	var actor=actors[key];actors.erase(key);actor_layer.remove_child(actor);actor.queue_free()
func _restack()->void:
	# Depth follows the observed feet, not body identity or a random animation order.
	actor_layer.y_sort_enabled=_isometric()
	for actor in actors.values():actor.z_index=0 if _isometric() else clampi(int(actor.target_position.y),0,3000)
func _process(delta:float)->void:
	if Engine.is_editor_hint() or not is_instance_valid(actor_layer):return
	if has_focus() and not miniature and camera_joy.length()>.25:pan_between(size*.5,size*.5-camera_joy*delta*520)
	if playing:visual_tick=minf(previous_tick+.1,visual_tick+delta*playback_rate)
	if is_instance_valid(world3d):queue_redraw();return
	if is_instance_valid(ocean) and ocean.visible:ocean.material.set_shader_parameter("visual_time",visual_tick)
	for key in actors.keys():
		var actor=actors[key];actor.advance(delta,visual_tick,playing)
		if actor.expired():_remove_actor(key)

func bounds()->Rect2:
	var source:Rect2=source_bounds()
	if zoom<=1 or miniature:return source
	var dimensions:Vector2=source.size/zoom
	return Rect2(camera_center-dimensions*.5,dimensions)
func source_bounds()->Rect2:
	var value:Dictionary=land.get("bounds",{})
	return Rect2(float(value.get("x",7000)),float(value.get("y",4000)),maxf(1,float(value.get("width",10000))),maxf(1,float(value.get("height",8000))))
func reset_camera()->void:
	zoom=1;camera_center=source_bounds().get_center();_camera_updated()
func _clamp_camera()->void:
	var source:Rect2=source_bounds();var half:Vector2=source.size/(2.0*maxf(zoom,1))
	camera_center.x=clampf(camera_center.x,source.position.x+half.x,source.end.x-half.x)
	camera_center.y=clampf(camera_center.y,source.position.y+half.y,source.end.y-half.y)
func _camera_updated()->void:
	_clamp_camera();_resize_visuals();_sync_projection();camera_changed.emit()
func zoom_at(factor:float,anchor:Vector2)->void:
	if miniature or show_drag_target:return
	var before:Vector2=unproject_base(anchor)
	if is_instance_valid(world3d):
		zoom=clampf(zoom*factor,1.0,40.0)
		_sync_world3d_camera()
		camera_center+=before-world3d.unproject(anchor)
		_camera_updated();return
	if zoom<=1:camera_center=unproject_base(_projection_area().get_center()) if _isometric() else source_bounds().get_center()
	var limit:float=40 if str(land.get("art_version",""))=="tactical-art-v2" else 12 if _isometric() else 4
	zoom=clampf(zoom*factor,1,limit);iso_frame_valid=false
	camera_center+=before-unproject_base(anchor);_camera_updated()
func pan_between(previous:Vector2,current:Vector2)->void:
	if miniature or show_drag_target or zoom<=1:return
	camera_center+=unproject_base(previous)-unproject_base(current);_camera_updated()
func focus_selected()->void:
	if zoom>1:zoom=1
	else:
		var center:Vector2=Vector2.ZERO;var count:int=0;var company_bounds:=Rect2()
		for row in land.get("entities",[]):
			if company_key(row)==selected_unit:
				company_bounds=Rect2(pos(row),Vector2.ZERO) if count==0 else company_bounds.expand(pos(row))
				center+=pos(row);count+=1
		if count==0:return
		camera_center=center/count
		if str(land.get("art_version",""))=="tactical-art-v2":
			var minimum_span:float=95.0 if str(land.get("geography",{}).get("version",""))=="cas-coastal-geography-v1" else 180.0
			var span:float=maxf(minimum_span,maxf(company_bounds.size.x,company_bounds.size.y)*2.8)
			zoom=clampf(maxf(bounds().size.x,bounds().size.y)/span,2.25,40)
		else:zoom=clampf(maxf(bounds().size.x,bounds().size.y)/700.0,2.25,12) if _isometric() else 2.25
	_resize_visuals();_sync_projection()
	camera_changed.emit()
func project(point:Vector2)->Vector2:
	if is_instance_valid(world3d):return world3d.project(point)
	var base:Vector2=project_base(point)
	return base-Vector2(0,_height_at(point)*_height_multiplier()*_screen_scale()) if _isometric() else base
func project_base(point:Vector2)->Vector2:
	if is_instance_valid(world3d):return world3d.project(point)
	if _isometric():
		var frame:Rect2=_iso_frame();var area:Rect2=_projection_area()
		var factor:float=minf(area.size.x/frame.size.x,area.size.y/frame.size.y)
		return area.get_center()+(_iso(point)-frame.get_center())*factor
	var frame:Rect2=bounds();var local:Vector2=(point-frame.position)/frame.size
	if miniature:return Vector2(local.x,1-local.y)*(size-Vector2(24,24))+Vector2(12,12)
	return Vector2(local.x,1-local.y)*(size-Vector2(32,124))+Vector2(16,100)
func unproject(point:Vector2)->Vector2:
	if is_instance_valid(world3d):return world3d.unproject(point)
	if not _isometric() or land.get("terrain",{}).is_empty():return unproject_base(point)
	if str(land.get("terrain",{}).get("height_model",""))=="inset_edge_blend_v1":
		# The actual 80 m / 120 m slopes remain monotone at a true 1:1
		# vertical scale. Solve along this screen ray instead of iterating
		# a steep gradient, which can alternate across a zone edge.
		var low:float=0;var high:float=0
		for zone in land.terrain.get("elevation_zones",[]):high=maxf(high,float(zone.get("height_m",0)))
		for iteration in range(28):
			var middle:float=(low+high)*.5
			var candidate:Vector2=unproject_base(point+Vector2(0,middle*_height_multiplier()*_screen_scale()))
			if _height_at(candidate)>middle:low=middle
			else:high=middle
		return unproject_base(point+Vector2(0,(low+high)*.5*_height_multiplier()*_screen_scale()))
	# Top surfaces are selectable in painter order. A vertical cliff face has no
	# unique world XY, so a click there falls back to the underlying ground plane.
	var heights:Array[float]=[0.0]
	for zone in land.get("terrain",{}).get("elevation_zones",[]):
		var height:float=float(zone.get("height_m",0))
		if not heights.has(height):heights.append(height)
	heights.sort();heights.reverse()
	for initial in heights:
		var candidate:Vector2=unproject_base(point+Vector2(0,initial*_height_multiplier()*_screen_scale()))
		for iteration in range(16):
			var next:Vector2=unproject_base(point+Vector2(0,_height_at(candidate)*_height_multiplier()*_screen_scale()))
			if next.distance_to(candidate)<.0001:break
			candidate=next
		if project(candidate).distance_to(point)<.02:return candidate
	return unproject_base(point)
func _height_multiplier()->float:
	return 1.0 if str(land.get("terrain",{}).get("version",""))=="tactical-terrain-v4" or str(land.get("terrain",{}).get("height_model",""))=="inset_edge_blend_v1" else 3.5
func unproject_base(point:Vector2)->Vector2:
	if is_instance_valid(world3d):return world3d.unproject(point)
	if _isometric():
		var frame:Rect2=_iso_frame();var area:Rect2=_projection_area()
		var factor:float=minf(area.size.x/frame.size.x,area.size.y/frame.size.y)
		var planar:Vector2=frame.get_center()+(point-area.get_center())/maxf(.00001,factor)
		return Vector2(planar.x/(2*.866025403784)+planar.y,planar.x/(2*.866025403784)-planar.y)
	var frame:Rect2=bounds();var local:Vector2=(point-Vector2(16,100))/(size-Vector2(32,124))
	if miniature:local=(point-Vector2(12,12))/(size-Vector2(24,24))
	return frame.position+Vector2(local.x,1-local.y)*frame.size
func _screen_scale()->float:
	if is_instance_valid(world3d):return maxf(.00001,world3d.project(camera_center+Vector2.RIGHT).distance_to(world3d.project(camera_center)))
	var frame:Rect2=_iso_frame();var area:Rect2=_projection_area()
	return minf(area.size.x/frame.size.x,area.size.y/frame.size.y)
func _terrain_points(raw:Variant)->PackedVector2Array:
	var result:PackedVector2Array=[]
	if raw is PackedVector2Array:return raw
	if raw is Array:
		for point in raw:
			if point is Dictionary:result.append(pos(point))
			elif point is Vector2:result.append(point)
	return result
func _height_at(point:Vector2)->float:
	var terrain:Dictionary=land.get("terrain",{})
	if terrain.is_empty():return 0
	if not height_cache_valid:_cache_heights(terrain)
	if height_model=="inset_edge_blend_v1":
		var blended:float=0
		for zone in height_zones:
			if not zone.bounds.has_point(point) or not Geometry2D.is_point_in_polygon(point,zone.polygon):continue
			var edge_distance:float=INF;var polygon:PackedVector2Array=zone.polygon
			for index in range(polygon.size()):edge_distance=minf(edge_distance,point.distance_to(Geometry2D.get_closest_point_to_segment(point,polygon[index],polygon[(index+1)%polygon.size()])))
			blended=maxf(blended,float(zone.height)*clampf(edge_distance/maxf(.00001,float(zone.blend_width)),0,1))
		return blended
	var height:float=0;var level:int=-1
	for zone in height_zones:
		if int(zone.level)>=level and zone.bounds.has_point(point) and Geometry2D.is_point_in_polygon(point,zone.polygon):height=float(zone.height);level=int(zone.level)
	for ramp in height_ramps:
		if not ramp.bounds.has_point(point):continue
		var nearest:float=INF;var along:float=0
		for segment in ramp.segments:
			var delta:Vector2=(segment.b as Vector2)-(segment.a as Vector2)
			var fraction:float=(point-(segment.a as Vector2)).dot(delta)/maxf(.000001,delta.length_squared())
			# Native ramps are rectangular side bands. Their end caps must not
			# raise ground beyond the actual start/end of the published path.
			if fraction<0 or fraction>1:continue
			var closest:Vector2=(segment.a as Vector2)+delta*fraction;var distance:float=point.distance_to(closest)
			if distance<nearest:nearest=distance;along=float(segment.start)+(segment.a as Vector2).distance_to(closest)
		if nearest<=float(ramp.radius) and float(ramp.total)>0:return lerpf(float(ramp.from_height),float(ramp.to_height),clampf(along/float(ramp.total),0,1))
	return height
func _cache_heights(terrain:Dictionary)->void:
	height_zones.clear();height_ramps.clear();level_heights={0:0.0};height_model=str(terrain.get("height_model",""))
	for zone in terrain.get("elevation_zones",[]):
		var polygon:PackedVector2Array=_terrain_points(zone.get("polygon",[]))
		var level:int=int(zone.get("level",0));var height:float=float(zone.get("height_m",0));level_heights[level]=height
		if polygon.size()<3:continue
		var frame:=Rect2(polygon[0],Vector2.ZERO)
		for point in polygon:frame=frame.expand(point)
		height_zones.append({"polygon":polygon,"bounds":frame.grow(.001),"level":level,"height":height,"blend_width":float(zone.get("blend_width_m",120))})
	for ramp in terrain.get("ramps",[]):
		var points:PackedVector2Array=_terrain_points(ramp.get("points",[]))
		if points.size()<2:continue
		var frame:=Rect2(points[0],Vector2.ZERO);var segments:Array[Dictionary]=[];var total:float=0
		for point in points:frame=frame.expand(point)
		for i in range(points.size()-1):
			segments.append({"a":points[i],"b":points[i+1],"start":total});total+=points[i].distance_to(points[i+1])
		var radius:float=float(ramp.get("width",0))*.5
		height_ramps.append({"bounds":frame.grow(radius+.001),"segments":segments,"total":total,"radius":radius,"from_height":float(level_heights.get(int(ramp.get("from_level",0)),0)),"to_height":float(level_heights.get(int(ramp.get("to_level",0)),0))})
	height_cache_valid=true
func _isometric()->bool:return bool(land.get("persistent_corpses",false))
func _iso(point:Vector2)->Vector2:return Vector2(.866025403784*(point.x+point.y),.5*(point.x-point.y))
func _projection_area()->Rect2:
	return Rect2(Vector2(12,12),Vector2(maxf(1,size.x-24),maxf(1,size.y-24))) if miniature else Rect2(Vector2(24,112),Vector2(maxf(1,size.x-48),maxf(1,size.y-144)))
func _iso_frame()->Rect2:
	if iso_frame_valid:return iso_frame_cache
	var source:Rect2=source_bounds();var points:Array[Vector2]=[]
	for entry in land.get("polygon",[]):
		if entry is Dictionary:points.append(_iso(pos(entry)))
	if points.is_empty():
		for corner in [source.position,source.position+Vector2(source.size.x,0),source.end,source.position+Vector2(0,source.size.y)]:points.append(_iso(corner))
	iso_frame_cache=Rect2(points[0],Vector2.ONE)
	for point in points:iso_frame_cache=iso_frame_cache.expand(point)
	var margin:float=minf(180,maxf(12,minf(iso_frame_cache.size.x,iso_frame_cache.size.y)*.07))
	iso_frame_cache=iso_frame_cache.grow(margin)
	if zoom>1 and not miniature:iso_frame_cache=Rect2(_iso(camera_center)-iso_frame_cache.size/(2*zoom),iso_frame_cache.size/zoom)
	iso_frame_valid=true
	return iso_frame_cache
func target_at(point:Vector2)->Dictionary:
	if is_instance_valid(world3d):return _world3d_target_at(point)
	if str(land.get("equipment_version","")) in ["tactical-vehicles-v3","tactical-vehicles-v4"]:return _v3_target_at(point)
	var closest:Dictionary={};var distance:float=28
	for entity in land.get("entities",[]):
		if not _body_visible(entity):continue
		var key:int=int(entity.get("id",0));var center:Vector2=actor_hit_point(key) if actors.has(key) and not miniature else project(pos(entity))
		var next:float=center.distance_to(point)
		if next<distance:distance=next;closest={"kind":"entities","row":entity,"id":int(entity.id)}
	for type in ["buildings","ruins"]:
		for row in land.get(type,[]):
			var next:float=project(pos(row)).distance_to(point)
			if next<distance:distance=next;closest={"kind":type,"row":row,"id":row.id}
	return closest
func _v3_target_at(point:Vector2)->Dictionary:
	var closest:Dictionary={};var distance:float=INF
	# A precise touch on the vehicle centre must not select a nearby SD head
	# whose oversized artwork overlaps it in the isometric projection.
	if not miniature:
		for entity in land.get("entities",[]):
			var key:int=int(entity.get("id",0))
			if _body_visible(entity) and not str(entity.get("vehicle_kind","")).is_empty() and actors.has(key) and actor_hit_point(key).distance_to(point)<4:
				return {"kind":"entities","row":entity,"id":key}
	for entity in land.get("entities",[]):
		if not _body_visible(entity):continue
		var key:int=int(entity.get("id",0));var center:Vector2=actor_hit_point(key) if actors.has(key) and not miniature else project(pos(entity))
		var radius:float=clampf(actors[key].display_height*2.1*.44,28,100) if actors.has(key) and not str(entity.get("vehicle_kind","")).is_empty() and not miniature else 28
		var gap:float=center.distance_to(point)
		if gap<radius and gap<distance:distance=gap;closest={"kind":"entities","row":entity,"id":int(entity.id)}
	for type in ["buildings","ruins"]:
		for row in land.get(type,[]):
			var gap:float=project(pos(row)).distance_to(point)
			if gap<28 and gap<distance:distance=gap;closest={"kind":type,"row":row,"id":row.id}
	return closest
func actor_hit_point(key:int)->Vector2:
	var actor=actors[key]
	if str(land.get("equipment_version","")) in ["tactical-vehicles-v3","tactical-vehicles-v4"] and not str(actor.public_row.get("vehicle_kind","")).is_empty():return actor.position-Vector2(0,actor.visual_lift())
	return actor.position-Vector2(0,actor.visual_lift()+(minf(5,actor.display_height*.5) if actor.compact_mode else minf(18,actor.display_height*.55)))
func pos(row:Dictionary)->Vector2:return Vector2(float(row.get("x",0)),float(row.get("y",0)))
func company_key(row:Dictionary)->String:return str(row.get("company_id",row.get("unit_id","")))
func _body_visible(row:Dictionary)->bool:
	if str(land.get("equipment_version","")) in ["tactical-vehicles-v3","tactical-vehicles-v4"]:
		if bool(row.get("seated",false)) and str(row.get("vehicle_kind","")).is_empty():return false
		if not str(row.get("vehicle_kind","")).is_empty() and (str(row.get("phase","")) in ["aboard","recovered"] or row.get("carried_by")!=null):return false
	if str(land.get("art_version",""))!="tactical-art-v2" or str(row.get("side","axis"))=="allies":return true
	return bool(row.get("visible",true)) or (float(row.get("hp",1))<=0 and bool(row.get("known",false)))
func _polygon(raw:Variant)->PackedVector2Array:
	var polygon:PackedVector2Array=[]
	if raw is Array:
		for entry in raw:
			if entry is Dictionary:polygon.append(project(pos(entry)))
	return polygon
func _environment(type:String,at:Vector2,width:float,canvas:CanvasItem=null)->bool:
	var path:String="res://assets/home/environment/"+type+".png"
	if not ResourceLoader.exists(path):return false
	if not environment_cache.has(path):environment_cache[path]=load(path)
	var texture:Texture2D=environment_cache[path];var dimensions:Vector2=Vector2(width,width*texture.get_height()/maxf(1,texture.get_width()))
	var target:CanvasItem=self if canvas==null else canvas
	target.draw_texture_rect(texture,Rect2(at-dimensions*Vector2(.5,.72),dimensions),false);return true
func _input(event:InputEvent)->void:
	# A pinch may start in the global unit drag layer. Its second pointer has
	# no GUI focus, so retain both contacts until their real releases arrive.
	if not miniature and camera_gesture and (event is InputEventScreenTouch or event is InputEventScreenDrag) and camera_touch_points.has(event.index):
		_gui_input(event);get_viewport().set_input_as_handled()
func _gui_input(event:InputEvent)->void:
	if miniature or (show_drag_target and not actor_pointer_armed):return
	if event is InputEventJoypadMotion:
		if event.axis==JOY_AXIS_LEFT_X:camera_joy.x=event.axis_value if absf(event.axis_value)>.25 else 0
		if event.axis==JOY_AXIS_LEFT_Y:camera_joy.y=event.axis_value if absf(event.axis_value)>.25 else 0
		accept_event();return
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index==JOY_BUTTON_Y:reset_camera()
		elif event.button_index==JOY_BUTTON_RIGHT_SHOULDER:zoom_at(1.2,size*.5)
		elif event.button_index==JOY_BUTTON_LEFT_SHOULDER:zoom_at(1.0/1.2,size*.5)
		elif event.button_index in [JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_DOWN]:
			var direction:Vector2=Vector2(-1 if event.button_index==JOY_BUTTON_DPAD_LEFT else 1 if event.button_index==JOY_BUTTON_DPAD_RIGHT else 0,-1 if event.button_index==JOY_BUTTON_DPAD_UP else 1 if event.button_index==JOY_BUTTON_DPAD_DOWN else 0)
			pan_between(size*.5,size*.5-direction*70)
		accept_event();return
	if event is InputEventMagnifyGesture:zoom_at(event.factor,event.position);accept_event();return
	if event is InputEventPanGesture:pan_between(event.position,event.position-event.delta*24);accept_event();return
	if event is InputEventKey and event.pressed:
		if event.keycode in [KEY_HOME,KEY_0]:reset_camera();accept_event()
		elif event.keycode in [KEY_PLUS,KEY_EQUAL,KEY_KP_ADD]:zoom_at(1.2,size*.5);accept_event()
		elif event.keycode in [KEY_MINUS,KEY_KP_SUBTRACT]:zoom_at(1.0/1.2,size*.5);accept_event()
		elif event.keycode in [KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN]:
			var direction:Vector2=Vector2(-1 if event.keycode==KEY_LEFT else 1 if event.keycode==KEY_RIGHT else 0,-1 if event.keycode==KEY_UP else 1 if event.keycode==KEY_DOWN else 0)
			pan_between(size*.5,size*.5-direction*70);accept_event()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			camera_touch_points[event.index]=event.position
			if camera_touch_points.size()==1:_camera_press(event.position);_arm_actor(event.position,event.index)
			else:
				if actor_pointer_armed:actor_pointer_armed=false;actor_drag_cancelled.emit()
				camera_gesture=true;camera_pointer_dragged=true
				var points:Array=camera_touch_points.values();camera_pinch_distance=points[0].distance_to(points[1]);camera_pinch_center=(points[0]+points[1])*.5
		else:
			camera_touch_points.erase(event.index)
			if camera_touch_points.is_empty():_camera_release(event.position);camera_gesture=false
		accept_event();return
	if event is InputEventScreenDrag:
		camera_touch_points[event.index]=event.position
		if camera_touch_points.size()>=2:
			var points:Array=camera_touch_points.values();var distance:float=points[0].distance_to(points[1]);var center:Vector2=(points[0]+points[1])*.5
			if camera_pinch_distance>1:zoom_at(distance/camera_pinch_distance,center);pan_between(camera_pinch_center,center)
			camera_pinch_distance=distance;camera_pinch_center=center
		elif not camera_gesture:_camera_drag(event.position)
		accept_event();return
	if event is InputEventMouseButton:
		if not camera_touch_points.is_empty() or event.device==InputEvent.DEVICE_ID_EMULATION:return
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:zoom_at(1.18 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.18,event.position);accept_event();return
		if event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_RIGHT]:
			if event.pressed:
				_camera_press(event.position);camera_pointer_dragged=event.button_index!=MOUSE_BUTTON_LEFT;grab_focus()
				if event.button_index==MOUSE_BUTTON_LEFT:_arm_actor(event.position,-1)
			else:_camera_release(event.position)
			accept_event();return
	if event is InputEventMouseMotion and camera_pointer_down:_camera_drag(event.position);accept_event()
func _camera_press(point:Vector2)->void:
	camera_pointer_down=true;camera_pointer_dragged=false;camera_pointer_origin=point;camera_pointer_last=point;actor_pointer_armed=false
func _arm_actor(point:Vector2,pointer:int)->void:
	if not actor_commands_enabled or str(land.get("equipment_version","")) not in ["tactical-vehicles-v3","tactical-vehicles-v4"]:return
	var hit:Dictionary=target_at(point);var row:Dictionary=hit.get("row",{})
	if str(hit.get("kind",""))!="entities" or str(row.get("side","axis"))!="allies" or float(row.get("hp",0))<=0:return
	actor_pointer_armed=true
	actor_drag_requested.emit(row,get_global_transform()*point,pointer)
func _camera_drag(point:Vector2)->void:
	if not camera_pointer_down or actor_pointer_armed:return
	if point.distance_to(camera_pointer_origin)>9:camera_pointer_dragged=true
	if camera_pointer_dragged:pan_between(camera_pointer_last,point)
	camera_pointer_last=point
func _camera_release(point:Vector2)->void:
	var select:bool=camera_pointer_down and not camera_pointer_dragged and not camera_gesture and not actor_pointer_armed
	camera_pointer_down=false;actor_pointer_armed=false
	if select:_select_point(point)
func _select_point(point:Vector2)->void:
		if str(land.get("equipment_version","")) in ["tactical-vehicles-v3","tactical-vehicles-v4"]:
			var hit:Dictionary=target_at(point);var selected_kind:String=str(hit.get("kind",""));var selected_id:Variant=hit.get("id",0)
			if selected_kind in ["entities","ruins"]:selected_id=int(selected_id)
			point_selected.emit(unproject(point),selected_id,selected_kind);return
		var closest:Dictionary={};var kind:String="";var distance:float=24
		for entity in land.get("entities",[]):
			if not _body_visible(entity):continue
			var key:int=int(entity.get("id",0))
			if actors.has(key):
				var next:float=actor_hit_point(key).distance_to(point)
				if next<distance:distance=next;closest=entity;kind="entities"
		for type in ["buildings","ruins"]:
			for entity in land.get(type,[]):
				var next:float=project(pos(entity)).distance_to(point)
				if next<distance:distance=next;closest=entity;kind=type
		var target:Variant=closest.get("id",0)
		if kind in ["entities","ruins"]:target=int(target)
		point_selected.emit(unproject(point),target,kind)
func _draw()->void:
	if is_instance_valid(world3d):
		_draw_world3d_overlay();return
	var cached_terrain:bool=is_instance_valid(terrain_backdrop) and terrain_backdrop.visible
	if not cached_terrain and (not is_instance_valid(ocean) or not ocean.visible):draw_rect(Rect2(Vector2.ZERO,size),Color("3c7480"))
	var polygon:PackedVector2Array=_polygon(land.get("polygon",[]))
	var procedural:bool=bool(land.get("persistent_corpses",false))
	if procedural and polygon.size()>2 and not cached_terrain:
		var protected:Array=[]
		for kind in ["buildings","ruins","entities"]:
			for row in land.get(kind,[]):protected.append(pos(row))
		Terrain.paint(self,land.get("polygon",[]),project,int(land.get("seed",0)),float(land.get("tick",0)),0 if miniature else 2,protected,land.get("town",{}),land.get("terrain",{}),project_base)
	elif not procedural and polygon.size()>2:draw_colored_polygon(polygon,terrain_color);draw_polyline(polygon,Color("d1c7a0"),5,true)
	elif not cached_terrain and polygon.size()<=2:draw_rect(Rect2(Vector2(14,14),size-Vector2(28,28)),terrain_color)
	if polygon.size()>2 and not procedural:
		# Decorative grass and scrub are clipped to the actual native coastline.
		for index in range(38):
			var at:Vector2=Vector2(fposmod(sin(index*12.9898+2)*43758.5453,1)*(size.x-48)+24,fposmod(sin(index*78.233+9)*12741.798,1)*(size.y-58)+29)
			if not Geometry2D.is_point_in_polygon(at+Vector2(0,-18),polygon) or not Geometry2D.is_point_in_polygon(at+Vector2(16,12),polygon) or not Geometry2D.is_point_in_polygon(at-Vector2(16,-12),polygon):continue
			var environment:String="tree_cluster" if index%5==0 else "grass_patch" if index%3==0 else "ground_patch"
			if _environment(environment,at,36 if index%5==0 else 30):continue
			draw_circle(at,7+index%6,terrain_color.lightened(.025) if index%2==0 else terrain_color.darkened(.035))
			if index%4==0:
				draw_line(at,at+Vector2(0,-9),Color("4b6958"),2)
				draw_circle(at+Vector2(-3,-8),5,Color("50775d"));draw_circle(at+Vector2(3,-12),5,Color("6e9666"))
	var town_footprints:Dictionary={}
	if procedural:
		for building in land.get("town",{}).get("buildings",[]):town_footprints[hash(_polygon(building.get("footprint",[])))]=true
	for raw in land.get("obstacles",[]):
		if cached_terrain:continue
		var obstacle:PackedVector2Array=_polygon(raw.get("polygon",[]) if raw is Dictionary else raw)
		if town_footprints.has(hash(obstacle)):continue
		if procedural:
			_draw_rock_field(_terrain_points(raw.get("polygon",[]) if raw is Dictionary else raw));continue
		if obstacle.size()>2:
			draw_colored_polygon(obstacle,Color("596f63"));draw_polyline(obstacle,Color("a6ad8b"),2,true)
			var center:Vector2=Vector2.ZERO
			for point in obstacle:center+=point
			center/=obstacle.size()
			if _environment("rock_cluster",center,42):continue
			for index in range(obstacle.size()-1):
				if index%2==0:draw_colored_polygon(PackedVector2Array([center,obstacle[index],obstacle[index+1]]),Color("8b9b7b"))
	for ruin in land.get("ruins",[]):
		var at:Vector2=project(pos(ruin))
		var width:float=_world_object_width(ruin) if procedural else 44
		if procedural and (miniature or width<12):_site_marker(at,"ruin",Color("dcc38a"))
		elif not _environment("ruin_cluster",at,width):draw_rect(Rect2(at-Vector2(10,8),Vector2(20,16)),Color("c2b997"));draw_line(at-Vector2(0,8),at+Vector2(0,8),Color("5c736d"),2)
		if bool(ruin.get("searched",false)):draw_arc(at,14,0,TAU,20,Color("d0e8bf"),2,true)
		else:_bar(at+Vector2(0,14),float(ruin.get("progress",0)),1.0,Color("e9d8a0"))
	for building in land.get("buildings",[]):
		var at:Vector2=project(pos(building));var friendly:bool=str(building.get("side","axis"))=="allies"
		var color:Color=Color("bbd4bc") if friendly else Color("d3a28c")
		var width:float=_world_object_width(building) if procedural else -1
		if procedural and (miniature or width<12):_site_marker(at,str(building.get("kind","")),color)
		else:_facility(at,str(building.get("kind","")),color,float(building.get("hp",0))>0,width)
		_bar(at+Vector2(0,20),float(building.get("hp",0)),float(building.get("max_hp",1)),color)
	for entity in land.get("entities",[]):
		if not _body_visible(entity):continue
		var id:int=int(entity.get("id",0))
		if miniature:draw_circle(project(pos(entity)),2.5,Color("c9ead0") if str(entity.get("side",""))=="allies" else Color("e99779"));continue
		if company_key(entity)==selected_unit and actors.has(id):
			var center:Vector2=project(pos(entity));var drawn:Vector2=actors[id].position
			if center.distance_to(drawn)>8:draw_line(center,drawn,Color(.93,.85,.61,.4),1,true);draw_circle(center,1.7,Color("f3dda0"))
	for defense in land.get("deployables",[]):
		if not bool(defense.get("active",true)):continue
		var at:Vector2=project(pos(defense));var type:String=str(defense.get("kind",""));var color:=Color("e0dab0") if str(defense.get("side","axis"))=="allies" else Color("e6a08a")
		var scale:float=5 if miniature else 8
		if type=="aa_turret" and str(land.get("equipment_version","")) in ["tactical-vehicles-v3","tactical-vehicles-v4"]:
			if miniature:_site_marker(at,"aa",color)
			else:
				var equipment:Dictionary=defense.duplicate();equipment["equipment_version"]=str(land.equipment_version);equipment["vehicle_kind"]="aa_turret"
				if not TransportArt.paint(self,equipment,at,clampf(6*_screen_scale(),16,44),float(defense.get("heading",0)),float(land.get("tick",0)),false):BuildingArt.paint(self,at,clampf(6*_screen_scale(),16,44),"aa",1,int(defense.get("hp",0)))
				_bar(at+Vector2(0,13),float(defense.get("hp",0)),float(defense.get("max_hp",1)),color)
			continue
		elif type=="beach_position":
			draw_arc(at,scale*1.2,PI*.1,PI*.9,12,color,3,true)
			draw_arc(at+Vector2(0,2),scale*1.2,PI*.1,PI*.9,12,Color(.22,.3,.25,.8),2,true)
		else:
			draw_circle(at,scale*.5,Color(.16,.25,.28,.8));draw_arc(at,scale*.58,0,TAU,16,color,1.5,true)
			for spike in range(6):
				var axis:=Vector2.from_angle(spike*TAU/6);draw_line(at+axis*scale*.55,at+axis*scale,color,1.4,true)
			if type=="sea_mine":draw_line(at+Vector2(0,scale),at+Vector2(0,scale*1.6),color,1,true)
	if str(land.get("equipment_version","")) in ["tactical-vehicles-v3","tactical-vehicles-v4"]:
		for effect in land.get("effects",[]):
			if float(effect.get("remaining_s",0))<=0:continue
			var type:String=str(effect.get("kind",""))
			if type not in ["command_network","support_designation","supply_network"]:continue
			var center:Vector2=pos(effect);var radius:float=float(effect.get("radius_m",0))
			var ring:PackedVector2Array=[]
			# A horizontal range disk uses the centre's height plane. Sampling
			# independent cliff heights folds the outline back through itself.
			var height_shift:Vector2=project(center)-project_base(center)
			for index in range(48):ring.append(project_base(center+Vector2.from_angle(index*TAU/48)*radius)+height_shift)
			var color:=Color("a8e4bc") if type=="command_network" else Color("a9d3f0") if type=="supply_network" else Color("f4d182")
			draw_colored_polygon(ring,Color(color,.07))
			var outline:PackedVector2Array=ring.duplicate();outline.append(ring[0])
			draw_polyline(outline,Color(color,.65),1 if miniature else 2,true)
			if not miniature:
				var at:Vector2=project(center)
				draw_arc(at,10,0,TAU,24,color,1.4,true)
				if type=="support_designation":
					draw_line(at-Vector2(16,0),at+Vector2(16,0),color,1.4,true);draw_line(at-Vector2(0,16),at+Vector2(0,16),color,1.4,true)
				elif type=="supply_network":
					draw_line(at-Vector2(7,0),at+Vector2(7,0),color,2,true);draw_line(at-Vector2(0,7),at+Vector2(0,7),color,2,true)
	if not miniature and land.get("entities",[]).filter(func(row):return str(row.get("side","axis"))=="allies").size()>20:
		for id in company_offsets:
			if _isometric() and id!=selected_unit:continue
			var center:Vector2=Vector2.ZERO;var count:int=0
			for row in land.get("entities",[]):
				if company_key(row)==id:center+=project(pos(row));count+=1
			if count>0:
				var label:String=id
				for group in land.get("groups",[]):
					if str(group.id)==id:label=str(group.get("company_name",group.get("name",id)));break
				var above:float=_body_height(true,true)+12 if _isometric() else (85 if id==selected_unit else 33)
				draw_string(font,center/count+company_offsets[id]+Vector2(-20,-above),label,HORIZONTAL_ALIGNMENT_LEFT,160,14 if _isometric() else 16,Color("f4e2ae") if id==selected_unit else Color("d2e2cf"))
	for shell in land.get("shells",[]):draw_circle(project(pos(shell)),2,Color("fff0bb"))
	for impact in land.get("impacts",[]).slice(-24):
		var age:float=float(land.get("tick",0))-float(impact.get("tick",0))
		if age>=0 and age<.6:draw_arc(project(pos(impact)),4+age*18,0,TAU,16,Color(1,.86,.57,(.6-age)*.9),2,true)
	if aim:draw_rect(Rect2(Vector2(3,3),size-Vector2(6,6)),Color("ffe3a8"),false,3)
	if show_drag_target:
		var at:Vector2=project(drag_point);var color:Color=Color("c1f2b9") if drag_valid else Color("f2a58f")
		draw_arc(at,22,0,TAU,32,color,3,true);draw_line(at-Vector2(30,0),at+Vector2(30,0),color,1.5,true);draw_line(at-Vector2(0,30),at+Vector2(0,30),color,1.5,true)
func _transport_height(row:Dictionary)->float:
	if str(land.get("equipment_version","")) not in ["tactical-vehicles-v3","tactical-vehicles-v4"]:return friendly_sprite_height
	var equipment:Dictionary=row.duplicate();equipment["equipment_version"]=str(land.equipment_version)
	var spec:Dictionary=TransportArt.specification(equipment)
	var air:bool=str(spec.get("family","")) in ["helicopter","aircraft"]
	return _equipment_length(spec,company_key(row)==selected_unit)/(2.2 if air else 1.8)
func _draw_rock_field(world:PackedVector2Array,canvas:CanvasItem=null)->void:
	if world.size()<3:return
	var target:CanvasItem=self if canvas==null else canvas
	var screen:PackedVector2Array=[];var frame:=Rect2(world[0],Vector2.ZERO)
	for point in world:screen.append(project(point));frame=frame.expand(point)
	target.draw_colored_polygon(screen,Color(.47,.49,.38,.22));target.draw_polyline(screen,Color(.62,.64,.49,.45),1,true)
	var random:=RandomNumberGenerator.new();random.seed=hash(world)
	var count:int=clampi(int(frame.get_area()/1700),12,150)
	for index in range(count):
		var point:Vector2=frame.position+Vector2(random.randf(),random.randf())*frame.size
		if not Geometry2D.is_point_in_polygon(point,world):continue
		var width:float=random.randf_range(20,42)*_screen_scale()
		if width>=5 and not miniature:_environment("rock_cluster",project(point),width,target)
		else:target.draw_circle(project(point),clampf(width*.25,.6,2),Color("a5a78a"))
func _world_object_width(row:Dictionary)->float:
	var points:PackedVector2Array=_terrain_points(row.get("footprint",[]))
	if points.size()>2:
		var frame:Rect2=Rect2(project(points[0]),Vector2.ZERO)
		for point in points:frame=frame.expand(project(point))
		return frame.size.x
	var meters:float=float(row.get("width_m",row.get("length_m",0)))
	return project_base(pos(row)+Vector2(meters*.5,0)).distance_to(project_base(pos(row)-Vector2(meters*.5,0)))
func _site_marker(at:Vector2,kind:String,color:Color)->void:
	var radius:float=3 if miniature else 4
	draw_circle(at,radius+1,Color("234c55"));draw_circle(at,radius,color)
	if not miniature:
		if kind in ["turret","aa"]:draw_line(at,at+Vector2(5,-5),color,1.6,true)
		elif kind=="hq":draw_line(at-Vector2(0,6),at+Vector2(0,5),color,1.2,true)
		elif kind=="ruin":draw_rect(Rect2(at-Vector2(3,3),Vector2(6,6)),Color("f7e2ab"),false,1)
func _facility(at:Vector2,kind:String,color:Color,alive:bool,width:float=-1)->void:
	if BuildingArt.artwork(kind)!=null:
		BuildingArt.paint(self,at,width if width>=0 else (69 if kind=="hq" else 55),kind,1,100 if alive else 0);return
	var shade:Color=Color("344f51")
	draw_rect(Rect2(at+Vector2(-16,3),Vector2(34,14)),Color(.1,.2,.15,.2))
	if not alive:
		for index in range(4):draw_rect(Rect2(at+Vector2(index*7-13,(index%2)*4-4),Vector2(5,7)),Color("6f7668"))
		return
	if kind in ["turret","aa"]:
		draw_colored_polygon(PackedVector2Array([at+Vector2(-15,7),at+Vector2(-12,-5),at+Vector2(10,-8),at+Vector2(16,4)]),color.darkened(.2))
		draw_circle(at+Vector2(0,-4),8,color);draw_arc(at+Vector2(0,-4),8,PI,TAU,12,color.lightened(.2),2)
		draw_line(at+Vector2(0,-5),at+Vector2(16,-16),shade,4 if kind=="turret" else 2.5,true)
		if kind=="aa":draw_line(at+Vector2(-4,-6),at+Vector2(10,-19),shade,2.5,true)
	elif kind=="depot":
		for index in range(3):
			var box:Vector2=at+Vector2(index*9-12,(index%2)*6-9)
			draw_rect(Rect2(box,Vector2(13,13)),color);draw_rect(Rect2(box+Vector2(2,2),Vector2(9,9)),shade,false,1.5);draw_line(box,box+Vector2(13,13),shade,1,true)
	else:
		draw_rect(Rect2(at+Vector2(-14,-6),Vector2(28,19)),color)
		draw_colored_polygon(PackedVector2Array([at+Vector2(-18,-7),at+Vector2(-2,-18),at+Vector2(17,-7)]),shade)
		draw_rect(Rect2(at+Vector2(-3,2),Vector2(6,11)),shade)
		draw_rect(Rect2(at+Vector2(6,-2),Vector2(6,5)),Color("e7dfae"))
		draw_line(at+Vector2(9,-9),at+Vector2(9,-29),shade,2,true);draw_line(at+Vector2(3,-25),at+Vector2(15,-25),color,2,true)
func _bar(at:Vector2,current:float,maximum:float,color:Color)->void:
	draw_line(at-Vector2(10,0),at+Vector2(10,0),Color(.1,.2,.15,.55),2)
	draw_line(at-Vector2(10,0),at+Vector2(-10+20*clampf(current/maxf(.001,maximum),0,1),0),color,2)

func _observe_world3d(value:Dictionary,is_playing:bool)->void:
	if not is_instance_valid(actor_layer):return
	if not is_instance_valid(world3d):
		_clear_actors()
		world3d=load("res://scripts/world3d/world3d_view.gd").new()
		world3d.name="SharedMetreWorld3D";world3d.show_behind_parent=true
		add_child(world3d);move_child(world3d,0)
		world3d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		world3d.camera_changed.connect(queue_redraw)
		if camera_center==Vector2.ZERO:camera_center=source_bounds().get_center()
	actor_layer.hide();_refresh_terrain_backdrop()
	var tick:float=float(value.get("tick",0))
	var reset:bool=reset_pending or previous_tick<0 or tick<previous_tick
	world3d.selected_unit=selected_unit;world3d.playback_rate=playback_rate
	world3d.observe(value,is_playing);_sync_world3d_camera()
	if is_instance_valid(support_fx):support_fx.strength=motion_strength;support_fx.observe(value,reset)
	if is_instance_valid(weapon_fx):weapon_fx.observe(value,reset)
	visual_tick=tick;previous_tick=tick;reset_pending=false;projection_dirty=false
	queue_redraw()

func _sync_world3d_camera()->void:
	if not is_instance_valid(world3d):return
	world3d.set_miniature(miniature)
	world3d.set_camera(camera_center,1.0 if miniature else zoom)

func _world3d_target_at(point:Vector2)->Dictionary:
	var nearest:Dictionary={};var gap:float=INF
	for kind in ["entities","buildings","ruins"]:
		for row in land.get(kind,[]):
			if kind=="entities" and (not _body_visible(row) or float(row.get("hp",0))<=0):continue
			var at:Vector2=world3d.actor_screen_position(row) if kind=="entities" else project(pos(row))
			var hit_radius:float=28.0
			if kind=="entities" and not str(row.get("vehicle_kind","")).is_empty():hit_radius=42.0
			var separation:float=at.distance_to(point)
			if separation<hit_radius and separation<gap:
				gap=separation;nearest={"kind":kind,"row":row,"id":row.get("id",0)}
	return nearest

func _draw_world3d_overlay()->void:
	if miniature:return
	for row in land.get("entities",[]):
		if company_key(row)!=selected_unit or not _body_visible(row) or float(row.get("hp",0))<=0:continue
		draw_arc(world3d.actor_screen_position(row),11,0,TAU,24,Color("f7d080"),1.5,true)
	if show_drag_target:
		var color:Color=Color("a5f0ce") if drag_valid else Color("f18b72")
		var at:Vector2=project(drag_point)
		draw_circle(at,18,Color(color,.16));draw_arc(at,18,0,TAU,32,color,2,true)
		draw_line(at-Vector2(25,0),at+Vector2(25,0),color,1.5,true)
		draw_line(at-Vector2(0,25),at+Vector2(0,25),color,1.5,true)
	# The distance scale follows the same camera projection used by all orders.
	var metres:float=20.0
	var pixels:float=project(camera_center+Vector2(metres,0)).distance_to(project(camera_center))
	while pixels<45:metres*=5;pixels=project(camera_center+Vector2(metres,0)).distance_to(project(camera_center))
	if pixels<size.x*.35:
		var origin:=Vector2(22,size.y-22)
		draw_line(origin,origin+Vector2(pixels,0),Color("f1edce"),2,true)
		draw_string(font,origin-Vector2(0,8),"%d m"%int(metres),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("f1edce"))
