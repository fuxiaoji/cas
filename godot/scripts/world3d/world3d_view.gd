extends Control
## Display-only adapter. The existing Control owns drag/commands and simulation.
signal camera_changed
const Surface = preload("res://scripts/world3d/world3d_surface.gd")
const Art = preload("res://scripts/tactical_art_v2.gd")
@export var low_detail: bool = OS.has_feature("mobile")
var land: Dictionary = {}
var playing: bool = false
var zoom: float = 1.0
var center: Vector2 = Vector2.ZERO
var miniature: bool = false
var selected_unit: String = ""
var playback_rate: float = 1.0
var view_mode: String = "land"
var viewport: SubViewport
var container: SubViewportContainer
var world_root: Node3D
var camera: Camera3D
var surface = Surface.new()
var actor_root: Node3D
var actors: Dictionary = {}
var _models: Dictionary = {}
var _geometry_key: int = 0
var _has_geometry: bool = false
var _clock: float = 0.0
var _last_tick: float = -1.0
var _material_cache: Dictionary = {}
var _animation_budget: float = 0.0
var _clouds:Array[MeshInstance3D]=[]
var _cloud_material:ShaderMaterial
var weather:String="clear"
var _chart_metres_per_pixel:float=0.0
var _chart_material:ShaderMaterial
var _environment:Environment
const MODEL_PATH: String = "res://assets/world3d/vehicles/"
const BODY_HEIGHT_M:float=2.2
const SAMPLE_INTERVAL_S:float=.1
# The approved own-identity walk sheets have been inspected: +screen-X is
# their authored forward direction. World X is NOT screen X in this camera.
const AUTHORED_BODY_FACING:float=1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	container = SubViewportContainer.new();container.name = "World3DDisplay";container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container);container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);container.stretch = true
	_chart_material=ShaderMaterial.new();_chart_material.shader=preload("res://assets/world3d/shaders/chart_mirror.gdshader");container.material=_chart_material
	viewport = SubViewport.new();viewport.name = "MetreViewport";viewport.own_world_3d = true
	viewport.disable_3d = false;viewport.gui_disable_input = true;viewport.handle_input_locally = false
	viewport.msaa_3d = Viewport.MSAA_DISABLED if low_detail else Viewport.MSAA_2X
	viewport.positional_shadow_atlas_size=1024 if low_detail else 2048
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	container.add_child(viewport)
	world_root = Node3D.new();world_root.name = "NativeMetreWorld";viewport.add_child(world_root)
	var environment := WorldEnvironment.new();var env := Environment.new()
	_environment=env
	env.background_mode = Environment.BG_SKY
	var sky:=Sky.new();var sky_material:=ProceduralSkyMaterial.new()
	sky_material.sky_top_color=Color("70b2d2");sky_material.sky_horizon_color=Color("d2e5dc")
	sky_material.ground_bottom_color=Color("618b95");sky_material.ground_horizon_color=Color("d2e5dc");sky.sky_material=sky_material;env.sky=sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color = Color("b9d7db");env.ambient_light_energy = .20
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR;env.tonemap_exposure=1.0
	env.fog_enabled=not low_detail;env.fog_light_color=Color("b8d9d6");env.fog_density=.00012
	environment.environment = env;world_root.add_child(environment)
	var sun := DirectionalLight3D.new();sun.name="CoastalSun";sun.rotation_degrees=Vector3(-48,-32,0);sun.light_color=Color("fff0ca");sun.light_energy=.65;sun.shadow_enabled=not low_detail;sun.directional_shadow_max_distance=420;sun.shadow_bias=.05;world_root.add_child(sun)
	camera = Camera3D.new();camera.name="MetreCamera";camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.near=.5;camera.far=1500;camera.current=true;world_root.add_child(camera)
	actor_root=Node3D.new();actor_root.name="StableNativeEntities";world_root.add_child(actor_root)
	_cloud_material=ShaderMaterial.new();_cloud_material.shader=preload("res://assets/world3d/shaders/cloud.gdshader");_cloud_material.set_shader_parameter("coverage",.08)
	for index:int in range(2 if low_detail else 4):
		var cloud:=MeshInstance3D.new();var mesh:=PlaneMesh.new();mesh.size=Vector2(180+index*25,110+index*20);cloud.mesh=mesh;cloud.material_override=_cloud_material;cloud.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;world_root.add_child(cloud);_clouds.append(cloud)
	resized.connect(_resize_viewport)
	_resize_viewport()
	if not land.is_empty():observe(land,playing)

func _resize_viewport() -> void:
	if not is_instance_valid(viewport): return
	# Stretching container owns viewport dimensions; manually assigning warns.
	_apply_camera()

func observe(value: Dictionary, is_playing: bool = false) -> void:
	var was_playing:bool=playing
	land=value.duplicate();value=land;playing=is_playing
	if not is_instance_valid(world_root):return
	# Only static native geography participates in this key; tick/HP never rebuild it.
	var geography:Dictionary=value.get("geography",{})
	# Lightweight observations keep only the immutable geometry header. Retain
	# the full snapshot for this hash, never reuse a different island's grid.
	if not geography.has("heightfield") and surface.has_grid and str(geography.get("geometry_hash",""))==surface.native_grid.geometry_hash:
		value["geography"]=surface.land.get("geography",{})
		geography=value.geography
	var key:int=hash([value.get("polygon",[]),value.get("terrain",{}),value.get("town",{}),geography.get("geometry_hash",""),geography.has("heightfield"),_static_buildings(value.get("buildings",[]))])
	if not _has_geometry or key!=_geometry_key:
		var old_origin:Vector2=surface.origin
		surface.release();surface=Surface.new();surface.bind(value,low_detail);surface.build(world_root)
		_cloud_material.set_shader_parameter("grain",Surface.grain)
		_geometry_key=key;_has_geometry=true
		if center==Vector2.ZERO:center=surface.origin
		if old_origin!=surface.origin:
			for record:Dictionary in actors.values():record.node.free()
			actors.clear()
		_apply_camera()
	var tick:float=float(value.get("tick",0.0))
	if tick<_last_tick:
		for record:Dictionary in actors.values():record.node.free()
		actors.clear()
	var elapsed:float=tick-_last_tick if _last_tick>=0 else 0.0
	_sync_entities(value,elapsed,was_playing)
	_last_tick=tick
	_update_facility_health()

func _static_buildings(rows:Array)->Array:
	var result:Array=[]
	for row:Dictionary in rows:
		result.append({"id":row.get("id",0),"kind":row.get("kind",""),"x":row.get("x",0),"y":row.get("y",0),"cell":row.get("cell",{})})
	return result

func set_camera(position_m:Vector2,new_zoom:float)->void:
	var target_zoom:float=clampf(new_zoom,.5,160.0)
	if center.is_equal_approx(position_m) and is_equal_approx(zoom,target_zoom):return
	center=position_m;zoom=target_zoom;_apply_camera()

func focus_at(point:Vector2)->void:
	center=point;_apply_camera();camera_changed.emit()

func set_miniature(value:bool)->void:
	if miniature==value:return
	miniature=value;_apply_camera()
	if is_instance_valid(viewport):viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE

func set_view_mode(mode:String)->void:
	view_mode=mode;_apply_camera()

func set_chart_camera(position_m:Vector2,metres_per_pixel:float)->void:
	var scale_m:float=maxf(.0001,metres_per_pixel)
	if view_mode=="sea" and center.is_equal_approx(position_m) and is_equal_approx(scale_m,_chart_metres_per_pixel):return
	view_mode="sea";center=position_m;_chart_metres_per_pixel=scale_m;_apply_camera()

func _apply_camera()->void:
	if not is_instance_valid(camera) or surface.polygon.size()<3:return
	var span:float=maxf(surface.frame.size.x,surface.frame.size.y)/maxf(.5,zoom)
	if view_mode=="sea" and _chart_metres_per_pixel>0:span=_chart_metres_per_pixel*size.y
	camera.size=maxf(24.0,span)
	var target:Vector3=surface.world(center)
	var distance:float=maxf(80,span)*1.8 if view_mode=="sea" else maxf(433.1,span*1.8)
	# The chart camera can sit tens of kilometres above the sea. Applying the
	# 400-m scenic camera's atmospheric density there hides the entire world.
	if _environment!=null:
		_environment.fog_enabled=not low_detail and view_mode!="sea"
		_environment.fog_density=.00012*minf(1.0,433.1/distance)
	camera.far=maxf(650.0,distance+span*2.0+300.0)
	if view_mode=="sea":
		camera.position=target+Vector3(0,distance,0);camera.look_at(target,Vector3(0,0,1))
	else:
		camera.position=target+Vector3(215,245,-285).normalized()*distance;camera.look_at(target,Vector3.UP)
	if _chart_material!=null:_chart_material.set_shader_parameter("mirror_x",view_mode=="sea")
	var sun:DirectionalLight3D=world_root.get_node("CoastalSun") as DirectionalLight3D
	sun.shadow_enabled=not low_detail and not miniature and view_mode!="sea" and span<2300
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance=distance+160
	surface.set_detail(not miniature and span<2300,center,span)
	if surface.water_material!=null:surface.water_material.set_shader_parameter("chart_view",1.0 if view_mode=="sea" else 0.0)
	for index:int in range(_clouds.size()):
		_clouds[index].position=Vector3(target.x+(index-1.4)*maxf(160,span*.32),target.y+65+index*4,target.z+(index%2-.5)*maxf(180,span*.45))
	_update_readability()

func set_weather(value:String)->void:
	weather=value
	if surface.water_material!=null:
		surface.water_material.set_shader_parameter("sea_state",1.8 if value=="rain" else 1.2 if value=="dusk" else 1.0)
		surface.water_material.set_shader_parameter("cloud_cover",.8 if value=="rain" else .3)
	if _cloud_material!=null:_cloud_material.set_shader_parameter("coverage",.20 if value=="rain" else .08)

func project(point:Vector2)->Vector2:
	if not is_inside_tree() or not is_instance_valid(camera) or not camera.is_inside_tree() or not is_instance_valid(viewport) or surface.polygon.size()<3:return size*.5
	var p:Vector2=camera.unproject_position(surface.world(point))
	if view_mode=="sea":p.x=viewport.size.x-p.x
	return p*size/Vector2(viewport.size)

func unproject(screen_point:Vector2)->Vector2:
	if not is_inside_tree() or not is_instance_valid(camera) or not camera.is_inside_tree() or not is_instance_valid(viewport):return center
	var pixel:Vector2=screen_point*Vector2(viewport.size)/Vector2(maxf(1,size.x),maxf(1,size.y))
	if view_mode=="sea":pixel.x=viewport.size.x-pixel.x
	var from:Vector3=camera.project_ray_origin(pixel);var direction:Vector3=camera.project_ray_normal(pixel)
	if absf(direction.y)<.000001:return center
	var best_distance:float=INF;var chosen:Vector2=center
	if surface.has_grid or str(land.get("terrain",{}).get("height_model",""))=="inset_edge_blend_v1":
		# Search nearest visible intersection along this ray. No screen-height
		# iteration: steep inset edges can alternate across the zone boundary.
		var highest:float=surface.levels[-1] if not surface.levels.is_empty() else 0.0
		var start:float=maxf(0.0,(highest+1.0-from.y)/direction.y)
		var end:float=maxf(start,(-1.0-from.y)/direction.y)
		var last_t:float=start
		var prior:Vector3=from+direction*last_t
		var last_value:float=prior.y-surface.surface_at(Vector2(prior.x,prior.z)+surface.origin)
		for index:int in range(1,129):
			var at:float=lerpf(start,end,float(index)/128.0)
			var hit:Vector3=from+direction*at
			var value:float=hit.y-surface.surface_at(Vector2(hit.x,hit.z)+surface.origin)
			if last_value>=0.0 and value<=0.0:
				var lo:float=last_t;var hi:float=at
				for iteration:int in range(28):
					var middle:float=(lo+hi)*.5;var test:Vector3=from+direction*middle
					if test.y>surface.surface_at(Vector2(test.x,test.z)+surface.origin):lo=middle
					else:hi=middle
				var final:Vector3=from+direction*((lo+hi)*.5)
				return Vector2(final.x,final.z)+surface.origin
			last_value=value;last_t=at
	# Published v4 has flat native zones. Test each top plane in ray order;
	# a cliff face has no unique command XY and falls back to the ground plane.
	for level:float in surface.levels:
		var distance:float=(level-from.y)/direction.y
		if distance<0 or distance>=best_distance:continue
		var hit:Vector3=from+direction*distance;var point:Vector2=Vector2(hit.x,hit.z)+surface.origin
		if absf(surface.height_at(point)-level)<.01:best_distance=distance;chosen=point
	if best_distance<INF:return chosen
	var fallback:Vector3=from+direction*(-from.y/direction.y)
	return Vector2(fallback.x,fallback.z)+surface.origin

func height_at(point:Vector2)->float:return surface.height_at(point)

func is_point_visible(point:Vector2,tolerance_m:float=.5)->bool:
	if not is_inside_tree() or not is_instance_valid(camera) or not camera.is_inside_tree():return false
	var screen_point:Vector2=project(point)
	if not Rect2(Vector2.ZERO,size).has_point(screen_point) or camera.is_position_behind(surface.world(point)):return false
	return unproject(screen_point).distance_to(point)<=tolerance_m

func visibility_at(point:Vector2)->Dictionary:
	var screen_point:Vector2=project(point);var front:Vector2=unproject(screen_point)
	return {"visible":is_point_visible(point),"screen":screen_point,"nearest_surface":front,"difference_m":front.distance_to(point),"point_height_m":surface.surface_at(point),"front_height_m":surface.surface_at(front)}

func pick_at(point:Vector2)->Dictionary:
	var nearest:float=24.0;var result:Dictionary={}
	for record:Dictionary in actors.values():
		if not record.node.visible:continue
		var row:Dictionary=record.row
		var distance:float=actor_screen_position(row,bool(row.get("_transport",false))).distance_to(point)
		if distance<nearest:nearest=distance;result=row
	return result

func actor_position(row:Dictionary,transport:bool=false)->Vector2:
	var key:String=("transport:" if transport else "entity:")+str(row.get("id",0))
	if actors.has(key):
		var at:Vector3=actors[key].node.position
		return Vector2(at.x,at.z)+surface.origin
	return Vector2(float(row.get("x",0)),float(row.get("y",0)))

func actor_screen_position(row:Dictionary,transport:bool=false)->Vector2:
	var key:String=("transport:" if transport else "entity:")+str(row.get("id",0))
	if actors.has(key):
		var pixel:Vector2=camera.unproject_position(actors[key].node.position)
		if view_mode=="sea":pixel.x=viewport.size.x-pixel.x
		return pixel*size/Vector2(viewport.size)
	return project(actor_position(row,transport))

func _visible(row:Dictionary)->bool:
	if bool(row.get("seated",false)) and str(row.get("vehicle_kind","" )).is_empty():return false
	if str(row.get("phase","")) in ["aboard","embarked","recovered"] or row.get("carried_by")!=null:return false
	return str(row.get("side","allies"))=="allies" or bool(row.get("visible",true)) or (float(row.get("hp",1))<=0 and bool(row.get("known",false)))

func _model_for(row:Dictionary,transport:bool)->String:
	var kind:String=str(row.get("vehicle_kind",""))
	if kind.is_empty() and transport:kind=str(row.get("kind","landing_craft"))
	if kind.is_empty():return ""
	return str({"tank":"cas_tank_cc0","armor":"cas_tank_cc0","amphibious_vehicle":"cas_amphibious_apc","amphibious_wheeled_ifv":"cas_amphibious_apc","amphibious_tracked_gun":"cas_amphibious_apc","ifv":"cas_amphibious_apc","self_propelled_gun":"cas_self_propelled_artillery","howitzer":"cas_self_propelled_artillery","transport_helicopter":"cas_transport_helicopter","helicopter":"cas_transport_helicopter","attack_helicopter":"cas_attack_helicopter","gunship":"cas_attack_helicopter","parachute_aircraft":"procedural_transport_aircraft","transport_aircraft":"procedural_transport_aircraft","aa_turret":"procedural_aa_turret","heavy_lander":"cas_heavy_landing_craft","heavy_landing_craft":"cas_heavy_landing_craft","fast_boat":"cas_fast_assault_boat","kayak":"cas_fast_assault_boat","armored_boat":"cas_landing_craft","landing_craft":"cas_landing_craft"}.get(kind,""))

func _sync_entities(value:Dictionary,elapsed:float=0.0,was_playing:bool=false)->void:
	var current:Dictionary={}
	var rows:Array=value.get("entities",[]).duplicate()
	for corpse:Dictionary in value.get("corpses",[]):
		var dead:Dictionary=corpse.duplicate();dead["hp"]=0;rows.append(dead)
	for transport:Dictionary in value.get("transports",[]):
		var copy:Dictionary=transport.duplicate();copy["_transport"]=true;rows.append(copy)
	for row:Dictionary in rows:
		var transport:bool=bool(row.get("_transport",false));var id:String=("transport:" if transport else "entity:")+str(row.get("id",0));current[id]=true
		var model_id:String=_model_for(row,transport)
		if not actors.has(id):_add_actor(id,row,model_id)
		var record:Dictionary=actors[id];var node:Node3D=record.node
		var position_m:=Vector2(float(row.get("x",0)),float(row.get("y",0)))
		var target:Vector3=surface.world(position_m)
		var air:bool=bool(row.get("air",false)) or model_id.contains("helicopter")
		if air or model_id.contains("aircraft"):target.y+=maxf(0.0,float(row.get("altitude_m",15.0)))
		elif model_id.contains("landing_craft") or model_id.contains("boat"):target.y=-.10
		var old:Vector3=record.get("target",target)
		var moved:bool=Vector2(target.x-old.x,target.z-old.z).length()>.003
		var old_row:Dictionary=record.row
		var lifecycle_changed:bool=str(old_row.get("phase",""))!=str(row.get("phase","")) or bool(old_row.get("seated",false))!=bool(row.get("seated",false)) or old_row.get("in_vehicle")!=row.get("in_vehicle") or (float(old_row.get("hp",1))>0)!=(float(row.get("hp",1))>0)
		var snap:bool=not bool(record.get("primed",false)) or not playing or not was_playing or elapsed<0 or elapsed>.8 or lifecycle_changed
		# Duplicate UI observations at the same native tick must not restart an
		# interpolation, clear locomotion or switch the walk frame back to idle.
		if snap or elapsed>.00001 or moved:
			record["from"]=target if snap else node.position
			record["target"]=target;record["sample_age"]=0.0
			record["sample_duration"]=maxf(.016,minf(.4,(elapsed if elapsed>.00001 else SAMPLE_INTERVAL_S)/maxf(.1,playback_rate)))
			record["moving"]=moved and not snap and float(row.get("hp",1))>0
			if moved:record["direction"]=Vector2(target.x-old.x,target.z-old.z).normalized()
			if snap:node.position=target
		record["row"]=row;record["primed"]=true
		record["heading"]=deg_to_rad(float(row.get("heading",0.0)))+PI
		if moved and not row.has("heading"):record.heading=atan2(-(target.x-old.x),-(target.z-old.z))
		node.visible=_visible(row) and str(row.get("status",""))!="recovered"
		if record.model!=null:
			if snap:node.rotation.y=float(record.heading)
			if float(row.get("hp",1))<=0:node.rotation.z=.12
		else:_animate_body(record)
		actors[id]=record
	# Only a real published shot triggers firing; ready_in is a reload timer.
	for shot:Dictionary in value.get("shots",[]):
		var operator:String="entity:"+str(shot.get("operator_id",-1))
		if not actors.has(operator) and str(shot.get("source","")).begins_with("vehicle:"):operator="entity:"+str(shot.source).get_slice(":",1)
		if not actors.has(operator) and str(shot.get("source","")).begins_with("transport:"):operator=str(shot.source)
		if not actors.has(operator):continue
		var record:Dictionary=actors[operator]
		var shot_id:int=int(shot.get("id",0))
		if int(record.get("shot_id",-1))>=shot_id:continue
		record["shot_id"]=shot_id
		if absf(float(value.get("tick",0))-float(shot.get("tick",-100)))<.25:
			record["fire_until"]=_clock+.14
			if record.model!=null:_vehicle_fired(record,shot)
	for id:String in actors.keys():
		if not current.has(id):actors[id].node.free();actors.erase(id)
	_update_readability()

func _add_actor(id:String,row:Dictionary,model_id:String)->void:
	var anchor:=Node3D.new();anchor.name=id.replace(":","_");actor_root.add_child(anchor)
	var model:Node3D=null;var sprite:Sprite3D=null
	if not model_id.is_empty():
		var path:String=MODEL_PATH+model_id+".glb"
		if model_id.begins_with("procedural_"):model=_procedural_equipment(model_id);anchor.add_child(model)
		else:
			if not _models.has(path):_models[path]=load(path) if ResourceLoader.exists(path) else null
			if _models[path]!=null:model=(_models[path] as PackedScene).instantiate() as Node3D;anchor.add_child(model);_vertex_color(model)
	if model==null:
		sprite=Sprite3D.new();sprite.name="OwnIdentityBody";sprite.billboard=BaseMaterial3D.BILLBOARD_ENABLED;sprite.shaded=false;sprite.alpha_cut=SpriteBase3D.ALPHA_CUT_DISCARD;sprite.alpha_scissor_threshold=.12;sprite.double_sided=true;sprite.no_depth_test=false;anchor.add_child(sprite)
	var record:Dictionary={"node":anchor,"model":model,"sprite":sprite,"model_id":model_id,"row":row,"target":Vector3.ZERO,"from":Vector3.ZERO,"sample_age":0.0,"sample_duration":SAMPLE_INTERVAL_S,"direction":Vector2.ZERO,"moving":false,"phase":float(posmod(int(row.get("id",0)),19))*.193,"primed":false,"reference_height":512.0,"frame_key":"","fallen":null,"fallen_key":"","rotor":model.find_child("MainRotor",true,false) if model!=null else null}
	if model!=null:
		var turret:Node3D=model.find_child("Turret",true,false) as Node3D
		record["turret"]=turret;record["turret_rest"]=turret.position if turret!=null else Vector3.ZERO
		record["weapon_age"]=100.0;record["aim_point"]=Vector3.ZERO;record["flash"]=null
	actors[id]=record

func _vehicle_fired(record:Dictionary,shot:Dictionary)->void:
	if float(record.row.get("hp",0))<=0:return
	record["weapon_age"]=0.0
	record["weapon_first_frame"]=true
	record["muzzle_frames"]=3
	record["aim_point"]=surface.world(Vector2(float(shot.get("target_x",record.row.x)),float(shot.get("target_y",record.row.y))))
	record["last_visible_shot"]=shot.duplicate()
	if not is_instance_valid(record.flash):
		var flash:=MeshInstance3D.new();flash.name="AuthoritativeMuzzleFlash";flash.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mesh:=SphereMesh.new();mesh.radius=.27;mesh.height=.54;mesh.radial_segments=8;mesh.rings=3;flash.mesh=mesh
		var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color(1,.80,.28);material.emission_enabled=true;material.emission=Color(1,.47,.12);material.emission_energy_multiplier=2;flash.material_override=material
		record.node.add_child(flash);record["flash"]=flash
	var turret:Node3D=record.turret as Node3D
	var direction:Vector3=(record.aim_point-record.node.position).normalized()
	if turret!=null:turret.rotation.y=atan2(-direction.x,-direction.z)-record.node.rotation.y
	_update_vehicle_weapon(record,0)

func _update_vehicle_weapon(record:Dictionary,delta:float)->void:
	if not record.has("weapon_age"):return
	if playing and delta>0:
		if bool(record.get("weapon_first_frame",false)):record["weapon_first_frame"]=false
		else:record.weapon_age=float(record.weapon_age)+delta*maxf(.1,playback_rate)
		if int(record.get("muzzle_frames",0))>0:record["muzzle_frames"]=int(record.muzzle_frames)-1
	var age:float=float(record.weapon_age)
	var turret:Node3D=record.turret as Node3D
	var live:bool=float(record.row.get("hp",0))>0
	if turret!=null:
		if age<2 and live:
			var direction:Vector3=record.aim_point-record.node.position
			turret.rotation.y=lerp_angle(turret.rotation.y,atan2(-direction.x,-direction.z)-record.node.rotation.y,minf(1,delta*12))
		# Recoil belongs to the gun assembly. The body/track anchor never shifts.
		var recoil:float=sin(clampf(age/.24,0,1)*PI)*(.28 if str(record.model_id).contains("artillery") else .16) if age<.24 and live else 0.0
		turret.position=(record.turret_rest as Vector3)+Vector3(sin(turret.rotation.y),0,cos(turret.rotation.y))*recoil
	if is_instance_valid(record.flash):
		record.flash.visible=(age<.14 or int(record.get("muzzle_frames",0))>0) and live and record.node.visible
		if record.flash.visible:
			var forward:Vector3=(record.aim_point-record.node.position);forward.y=0;forward=forward.normalized()
			var barrel_m:float=5.05 if str(record.model_id).contains("tank") else 6.5 if str(record.model_id).contains("artillery") else 4.1 if str(record.model_id).contains("apc") else 3.8
			var height_m:float=2.35 if str(record.model_id).contains("tank") else 2.95 if str(record.model_id).contains("artillery") else 3.0 if str(record.model_id).contains("apc") else .8
			var local:Vector3=record.node.global_basis.inverse()*forward*barrel_m
			local.y=height_m;record.flash.position=local;record.flash.rotation.y=atan2(-forward.x,-forward.z)-record.node.rotation.y
			var strength:float=1.2 if str(record.model_id).contains("artillery") else 1.0 if str(record.model_id).contains("tank") else .6
			record.flash.scale=Vector3(strength,strength,strength*3.2)*clampf(1-age/.18,.55,1)

func _procedural_equipment(id:String)->Node3D:
	var result:=Node3D.new();result.name=id;result.set_meta("art_status","basic_3d_pending_model_refinement")
	var material:=StandardMaterial3D.new();material.albedo_color=Color("7e978a");material.roughness=.9
	var parts:Array=[]
	if id=="procedural_transport_aircraft":
		parts=[{"size":Vector3(2.6,2.5,15.0),"at":Vector3(0,0,0)}, {"size":Vector3(20.0,.30,3.2),"at":Vector3(0,.3,1)}, {"size":Vector3(7.0,.25,1.7),"at":Vector3(0,.9,6.2)}, {"size":Vector3(.25,3.2,2.6),"at":Vector3(0,1.9,5.8)}]
	else:
		parts=[{"size":Vector3(3.0,.7,3.0),"at":Vector3(0,.35,0)}, {"size":Vector3(1.4,1.8,1.6),"at":Vector3(0,1.5,0)}, {"size":Vector3(.18,.18,3.5),"at":Vector3(-.45,2.3,-1.4)}, {"size":Vector3(.18,.18,3.5),"at":Vector3(.45,2.3,-1.4)}]
	for part:Dictionary in parts:
		var mesh:=BoxMesh.new();mesh.size=part.size;var node:=MeshInstance3D.new();node.mesh=mesh;node.position=part.at;node.material_override=material;result.add_child(node)
	return result

func _vertex_color(node:Node)->void:
	if node is MeshInstance3D:
		var mesh:MeshInstance3D=node as MeshInstance3D
		for index:int in range(mesh.mesh.get_surface_count()):
			var original:StandardMaterial3D=mesh.get_active_material(index) as StandardMaterial3D
			if original==null:continue
			var id:int=original.get_instance_id()
			if not _material_cache.has(id):
				var material:StandardMaterial3D=original.duplicate() as StandardMaterial3D;material.vertex_color_use_as_albedo=true;material.albedo_color=Color.WHITE;material.vertex_color_is_srgb=false;_material_cache[id]=material
			mesh.set_surface_override_material(index,_material_cache[id])
	for child:Node in node.get_children():_vertex_color(child)

func _animate_body(record:Dictionary)->void:
	var sprite:Sprite3D=record.sprite
	if sprite==null:return
	var row:Dictionary=record.row;var id:String=str(row.get("unit_id",""));var state:String="walk" if bool(record.get("moving",false)) else "idle"
	if float(row.get("hp",1))<=0:state="defeated"
	elif str(row.get("order",""))=="search":state="search"
	elif not bool(record.get("moving",false)) and _clock<float(record.get("fire_until",-1)):state="fire"
	if not playing and state=="walk":state="idle"
	record["state"]=state
	var frame:Dictionary=Art.frame(id,state,_clock+float(record.phase),int(row.get("id",0)))
	if frame.is_empty():
		if str(row.get("side","allies"))=="allies":
			# Unknown friendly identity stays explicitly unpictured; another recruit
			# or the hostile security sheet is never borrowed as her miniature.
			sprite.visible=false;return
		# Enemy security uses its own registered sheet, never another recruit's image.
		var enemy:Texture2D=load("res://assets/tactical/sprites/enemy-security-sheet.png")
		if enemy!=null:
			var column:int=3 if state=="defeated" else 2+posmod(int((_clock+float(record.phase))*9),2) if state=="walk" or state=="fire" else 1 if state=="search" else 0;var line:int=2 if state=="defeated" or state=="search" else 1 if state=="fire" else 0
			var cell:Vector2=enemy.get_size()/Vector2(4,3)
			frame={"source":"res://assets/tactical/sprites/enemy-security-sheet.png","rect":[column*cell.x,line*cell.y,cell.x,cell.y],"pivot":[cell.x*.5,cell.y*(.80 if state=="defeated" else .96)],"reference_height":cell.y*.93}
		else:return
	sprite.visible=true
	var texture:Texture2D=Art.texture(str(frame.get("source","")))
	if texture==null:return
	var rect:Array=frame.get("rect",[]);var pivot:Array=frame.get("pivot",[])
	if rect.size()!=4 or pivot.size()!=2:return
	record["active_frame"]=frame
	var key:String=str(frame.get("source",""))+str(rect)
	if key!=str(record.frame_key):
		sprite.texture=texture;sprite.region_enabled=true;sprite.region_rect=Rect2(float(rect[0]),float(rect[1]),float(rect[2]),float(rect[3]));record.frame_key=key
	# Sprite3D local Y points up, image Y points down. Keep the authored ground pivot fixed.
	record.reference_height=float(frame.get("reference_height",rect[3]))
	_update_body_facing(record)
	sprite.offset=Vector2((float(rect[2])*.5-float(pivot[0]))*(-1.0 if sprite.flip_h else 1.0),float(pivot[1])-float(rect[3])*.5)
	sprite.pixel_size=BODY_HEIGHT_M/maxf(1,float(record.reference_height))
	if state=="defeated":
		sprite.hide();_place_fallen(record,frame,texture)
	else:
		if is_instance_valid(record.fallen):record.fallen.hide()
		sprite.modulate=Color.WHITE

func _update_body_facing(record:Dictionary)->void:
	var direction:Vector2=record.get("direction",Vector2.ZERO)
	if direction.length_squared()<.0001:return
	var at:Vector3=record.node.position
	var projected:Vector2=camera.unproject_position(at+Vector3(direction.x,0,direction.y))-camera.unproject_position(at)
	# In sea view the final canvas is mirrored. The sprite is in that canvas too,
	# so using the pre-mirror projection keeps its final face and motion together.
	if absf(projected.x)>.00001:record.sprite.flip_h=projected.x*AUTHORED_BODY_FACING<0
	var frame:Dictionary=record.get("active_frame",{})
	if not frame.is_empty():
		var rect:Array=frame.rect;var pivot:Array=frame.pivot
		record.sprite.offset=Vector2((float(rect[2])*.5-float(pivot[0]))*(-1.0 if record.sprite.flip_h else 1.0),float(pivot[1])-float(rect[3])*.5)

func _place_fallen(record:Dictionary,frame:Dictionary,texture:Texture2D)->void:
	# A fallen body keeps the authored 2D defeat frame laid down, like the map
	# view: the sprite leans back from its foot pivot instead of being draped
	# flat onto the terrain texture. Depth stays on, so buildings and the near
	# side of a hill still occlude it; the base clears the real surface 8 cm.
	var key:String=str(record.frame_key)+str(view_mode)+str(record.sprite.flip_h)+str(frame.get("reference_height",0))
	if str(record.fallen_key)==key and is_instance_valid(record.fallen):record.fallen.show();return
	if not is_instance_valid(record.fallen):
		var fallen:Sprite3D=Sprite3D.new();fallen.name="OwnIdentityFallenLying2D";fallen.billboard=BaseMaterial3D.BILLBOARD_DISABLED;fallen.shaded=false;fallen.alpha_cut=SpriteBase3D.ALPHA_CUT_DISCARD;fallen.alpha_scissor_threshold=.12;fallen.double_sided=true;fallen.no_depth_test=false;fallen.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;record.node.add_child(fallen);record["fallen"]=fallen
	var fallen:Sprite3D=record.fallen
	var rect:Array=frame.rect;var pivot:Array=frame.pivot
	fallen.texture=texture
	fallen.region_enabled=true
	fallen.region_rect=Rect2(float(rect[0]),float(rect[1]),float(rect[2]),float(rect[3]))
	var scale_m:float=BODY_HEIGHT_M/maxf(1.,float(frame.get("reference_height",rect[3])))
	fallen.pixel_size=scale_m*1.25
	fallen.flip_h=record.sprite.flip_h
	fallen.offset=Vector2((float(rect[2])*.5-float(pivot[0]))*(-1.0 if fallen.flip_h else 1.0),float(pivot[1])-float(rect[3])*.5)
	# Cross-slope roll keeps the lying 2D sprite aligned with the ground plane
	# while the -62 degree lean preserves the authored pose; any residual
	# corner penetration is cleared by lifting the base the minimum amount.
	var at:Vector3=record.node.position
	var w:float=float(rect[2])*fallen.pixel_size
	var h:float=float(rect[3])*fallen.pixel_size
	var right:Vector3=camera.global_basis.x;right.y=0;right=right.normalized()
	var roll:float=atan2(surface_height_at(at+right*w*.5)-surface_height_at(at-right*w*.5),maxf(w,.01))
	fallen.rotation_degrees=Vector3(-62,0,rad_to_deg(roll))
	var basis:Basis=Basis.from_euler(Vector3(deg_to_rad(-62),0,roll))
	var pivot_local:Vector3=Vector3(fallen.offset.x*fallen.pixel_size,fallen.offset.y*fallen.pixel_size,0)
	var lift:float=.08
	for _attempt:int in range(8):
		fallen.position=Vector3(0,lift,0)
		var worst:float=0.0
		for cx:float in [-1.0,1.0]:
			for cy:float in [-1.0,1.0]:
				var world:Vector3=at+basis*(pivot_local+Vector3(cx*w*.5,cy*h*.5,0))+Vector3(0,lift,0)
				worst=maxf(worst,surface_height_at(world)-world.y)
		if worst<=0.0:break
		lift+=worst+.02
	fallen.position=Vector3(0,lift,0)
	fallen.show();record["fallen_key"]=key

func surface_height_at(world:Vector3)->float:
	return surface.surface_at(Vector2(world.x,world.z)+surface.origin)

func _update_readability()->void:
	if not is_instance_valid(camera):return
	# A stable world height grows when zooming in. Never force sprites to shrink.
	for record:Dictionary in actors.values():
		if record.sprite!=null:
			(record.sprite as Sprite3D).pixel_size=BODY_HEIGHT_M/maxf(1,float(record.reference_height))
			_update_body_facing(record)
			if str(record.get("state",""))=="defeated":_animate_body(record)

func _update_facility_health()->void:
	for row:Dictionary in land.get("buildings",[]):
		var key:String="building:"+str(row.get("id",0))
		if surface.facilities.has(key):surface.facilities[key].visible=float(row.get("hp",1))>0 or bool(row.get("destroyed",false))

func _process(delta:float)->void:
	if playing:_clock+=delta*maxf(.1,playback_rate)
	_animation_budget+=delta
	var animate:bool=_animation_budget>=(.10 if miniature else .07)
	if animate:_animation_budget=0
	for record:Dictionary in actors.values():
		var node:Node3D=record.node
		if playing:
			record["sample_age"]=float(record.sample_age)+delta
			var blend:float=clampf(float(record.sample_age)/maxf(.001,float(record.sample_duration)),0,1)
			node.position=(record["from"] as Vector3).lerp(record.target,blend)
			# Ground follows the same authoritative triangles during interpolation,
			# instead of cutting below/through an intervening hillside.
			if not bool(record.row.get("air",false)) and not str(record.model_id).contains("helicopter") and not str(record.model_id).contains("aircraft") and not str(record.model_id).contains("craft") and not str(record.model_id).contains("boat"):
				node.position.y=surface.surface_at(Vector2(node.position.x,node.position.z)+surface.origin)
		if record.model!=null:
			if playing:node.rotation.y=lerp_angle(node.rotation.y,float(record.heading),minf(1,delta*12))
			_update_vehicle_weapon(record,delta)
			var rotor:Node3D=record.rotor as Node3D
			if rotor!=null and playing and float(record.row.get("hp",1))>0:rotor.rotation.y+=delta*37
		else:
			if animate:_animate_body(record)
			# Cosmetic bob never changes the anchor, target, collision or command XY.
			var sprite:Sprite3D=record.sprite
			if sprite!=null:sprite.position.y=absf(sin((_clock+float(record.phase))*7.0))*.025 if playing and bool(record.get("moving",false)) and float(record.row.get("hp",1))>0 else 0.0

func statistics()->Dictionary:
	return {"geometry_build_key":_geometry_key,"actor_count":actors.size(),"origin_m":surface.origin,"units":"metres","low_detail":low_detail,"scope":"display_only","camera_span_m":camera.size if is_instance_valid(camera) else 0.0}

