extends "res://scripts/battle_map.gd"
## The original naval interaction map with synchronized amphibious observations.
## No naval systems, weapon solutions or ranges are synthesized here.
signal drag_requested(payload:Dictionary,point:Vector2,pointer:int)
const TransportArt=preload("res://scripts/tactical_transport_art.gd")
const Terrain=preload("res://scripts/procedural_amphibious_terrain.gd")
const AircraftArt=preload("res://scripts/littoral_aircraft_art.gd")
const World3DSettings=preload("res://scripts/world3d_settings.gd")
var world3d:Control
var playback_rate:float=1
var playing:bool=false
var motion_strength:float=1
var miniature:bool=false
var show_drag_target:bool=false
var drag_point:Vector2=Vector2.ZERO
var drag_valid:bool=false
var drag_path:Array=[]
var drag_preview:Dictionary={}
var visual_seconds:float=0
var transport_offsets:Dictionary={}
var ship_drag:Dictionary={}
var operation_fit:bool=false
var vehicle_motion=preload("res://scripts/littoral_vehicle_motion.gd").new()
var terrain_viewport:SubViewport
var terrain_canvas:Control
var terrain_source_key:int=0
var terrain_frame_key:int=0
var terrain_cache_ready:bool=false
const TERRAIN_MARGIN:int=48

func _ready()->void:
	super._ready();texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if DisplayServer.get_name()!="headless":
		terrain_viewport=SubViewport.new();terrain_viewport.name="ProceduralTerrainCache";terrain_viewport.transparent_bg=true;terrain_viewport.disable_3d=true;terrain_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED;add_child(terrain_viewport)
		terrain_canvas=preload("res://scripts/littoral_sea_terrain_cache.gd").new();terrain_canvas.source_map=self;terrain_canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE;terrain_viewport.add_child(terrain_canvas)
	resized.connect(func():
		if operation_fit:_fit_operation.call_deferred())

func focus_fleet()->void:
	# The amphibious operation includes the shoreline and the fleet. The original
	# fleet-only 2.2x framing cropped every inland artillery target on first launch.
	operation_fit=true;_fit_operation()
func _fit_operation()->void:
	if miniature or view.is_empty() or size.x<1:return
	var points:Array[Vector2]=[]
	for ship in view.get("ships",[]):points.append(pos(ship))
	for contact in view.get("contacts",[]):points.append(pos(contact))
	for island in view.get("islands",[]):
		for point in island.get("polygon",[]) if island is Dictionary else island:
			if point is Dictionary:points.append(pos(point))
	if points.is_empty():return
	var extent:Rect2=Rect2(points[0],Vector2.ONE)
	for point in points:extent=extent.expand(point)
	extent=extent.grow(450)
	var area:=Rect2(Vector2(70,115),Vector2(maxf(100,size.x-455),maxf(100,size.y-270)))
	var field:=Vector2(float(view.get("width",24000)),float(view.get("height",16000)))
	var base:float=minf(size.x/field.x,size.y/field.y)
	var maximum:float=24.0 if _new_coastal_map() else 3.0
	zoom=clampf(minf(area.size.x/extent.size.x,area.size.y/extent.size.y)/maxf(.00001,base),.7,maximum)
	pan=Vector2.ZERO;pan=area.get_center()-project(extent.get_center())+combat_offset;queue_redraw()
func project(point:Vector2)->Vector2:
	if not miniature:return super.project(point)
	var field:=Vector2(float(view.get("width",24000)),float(view.get("height",16000)))
	var scale:float=minf(maxf(1,size.x-18)/field.x,maxf(1,size.y-18)/field.y)
	return (point-field*.5)*Vector2(1,-1)*scale+size*.5
func unproject(point:Vector2)->Vector2:
	if not miniature:return super.unproject(point)
	var field:=Vector2(float(view.get("width",24000)),float(view.get("height",16000)))
	var scale:float=minf(maxf(1,size.x-18)/field.x,maxf(1,size.y-18)/field.y)
	return (point-size*.5)/maxf(.00001,scale)*Vector2(1,-1)+field*.5

func observe(value:Dictionary)->void:
	view=value;weather_paused=not playing;projectile_rate=playback_rate if playing else 0
	if sea_material!=null:sea_material.set_shader_parameter("island_style",1.0)
	vehicle_motion.observe(_observed_transports(value),float(value.get("tick",0)))
	var ground:Dictionary=value.get("littoral",{}).get("land",{})
	if World3DSettings.eligible(ground):
		if not is_instance_valid(world3d):
			world3d=load("res://scripts/world3d/world3d_view.gd").new();world3d.name="SharedSeaWorld3D";world3d.show_behind_parent=true
			add_child(world3d);move_child(world3d,0);world3d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var geometry:Dictionary=ground.duplicate();geometry["transports"]=_observed_transports(value)
		world3d.observe(geometry,playing);world3d.set_miniature(miniature);_sync_world3d_camera()
	elif is_instance_valid(world3d):
		remove_child(world3d);world3d.queue_free();world3d=null
	terrain_source_key=hash([value.get("islands",[]),ground.get("town",{}),ground.get("terrain",{}),ground.get("buildings",[]).map(func(row):return [row.id,row.x,row.y]),ground.get("ruins",[]).map(func(row):return [row.id,row.x,row.y]),value.get("seed",0)])
	queue_redraw()
func reset_visuals()->void:
	gesture.clear();surface.clear();transport_offsets.clear();vehicle_motion.clear();queue_redraw()
func set_miniature(value:bool)->void:
	miniature=value;readonly=value;queue_redraw()
func focus_selected()->void:focus_fleet()
func target_at(local:Vector2)->Dictionary:
	for aircraft in view.get("littoral",{}).get("aviation",{}).get("aircraft",[]):
		if project(pos(aircraft)).distance_to(local)<24:return {"kind":"aircraft","id":int(aircraft.id),"row":aircraft}
	var contact:Dictionary=_nearest(local)
	if not contact.is_empty():return {"kind":"ship","id":str(contact.id),"row":contact}
	return {}
func _gui_input(event:InputEvent)->void:
	if miniature:return
	if _new_coastal_map() and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		operation_fit=false
		var before:Vector2=unproject(event.position)
		zoom=clampf(zoom*(1.12 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.12),.7,40)
		pan+=event.position-project(before);_sync_world3d_camera();queue_redraw();accept_event();return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN,MOUSE_BUTTON_RIGHT]:operation_fit=false
	if event is InputEventScreenTouch:
		var pointer:=InputEventMouseButton.new();pointer.position=event.position;pointer.button_index=MOUSE_BUTTON_LEFT;pointer.pressed=event.pressed
		_handle_ship_drag(pointer,event.index);return
	if event is InputEventScreenDrag:
		var pointer:=InputEventMouseMotion.new();pointer.position=event.position;pointer.relative=event.relative
		_handle_ship_drag(pointer,event.index);return
	_handle_ship_drag(event,-1)
func _handle_ship_drag(event:InputEvent,pointer:int)->void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed and not readonly and not editing:
			for ship in view.get("ships",[]):
				if project(pos(ship)).distance_to(event.position)<24:
					ship_drag={"ship":int(ship.id),"name":str(ship.get("name","舰艇")),"start":event.position,"pointer":pointer};break
		elif not event.pressed:ship_drag.clear()
	elif event is InputEventMouseMotion and not ship_drag.is_empty() and event.position.distance_to(ship_drag.start)>12:
		var payload:Dictionary={"kind":"ship","ship":ship_drag.ship,"name":ship_drag.name}
		surface.clear();ship_drag.clear();drag_requested.emit(payload,get_global_transform()*event.position,pointer);accept_event();return
	super._gui_input(event)
func _process(delta:float)->void:
	super._process(delta)
	vehicle_motion.advance(delta,playback_rate,playing)
	_refresh_terrain_cache()
	if is_instance_valid(world3d):world3d.playing=playing;world3d.playback_rate=playback_rate;_sync_world3d_camera()
	if playing:visual_seconds+=delta*minf(playback_rate,2)
	if not view.is_empty():queue_redraw()
func _draw_minimap()->void:
	# The linked land viewport is the single secondary map in this mode.
	pass
func _draw_command_overlays()->bool:return not miniature
func _draw_additional_terrain()->void:
	if is_instance_valid(world3d):_sync_world3d_camera();return
	if terrain_cache_ready and is_instance_valid(terrain_viewport):
		draw_texture_rect(terrain_viewport.get_texture(),Rect2(Vector2(-TERRAIN_MARGIN,-TERRAIN_MARGIN)+combat_offset,Vector2(terrain_viewport.size)),false)
		for island in view.get("islands",[]):Terrain.paint_coast_motion(self,island.get("polygon",[]) if island is Dictionary else island,project,visual_seconds)
		return
	_paint_terrain(self,project,true)
func _refresh_terrain_cache()->void:
	if is_instance_valid(world3d):return
	if not is_instance_valid(terrain_viewport) or view.is_empty() or size.x<1:return
	var next:int=hash([terrain_source_key,size,pan,zoom,miniature])
	if terrain_cache_ready and terrain_frame_key==next:return
	terrain_frame_key=next;terrain_cache_ready=true
	terrain_viewport.size=Vector2i(size)+Vector2i(TERRAIN_MARGIN*2,TERRAIN_MARGIN*2);terrain_canvas.size=Vector2(terrain_viewport.size)
	terrain_canvas.queue_redraw();terrain_viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
func _cached_project(point:Vector2)->Vector2:return project(point)-combat_offset+Vector2(TERRAIN_MARGIN,TERRAIN_MARGIN)
func paint_cached_terrain(canvas:CanvasItem)->void:_paint_terrain(canvas,_cached_project,false)
func _paint_terrain(canvas:CanvasItem,projector:Callable,animated:bool)->void:
	var data:Dictionary=view.get("littoral",{});var protected:Array=[]
	for kind in ["buildings","ruins"]:
		for row in data.get("land",{}).get(kind,[]):protected.append(pos(row))
	for island in view.get("islands",[]):
		var raw:Variant=island.get("polygon",[]) if island is Dictionary else island
		Terrain.paint(canvas,raw,projector,int(data.get("seed",view.get("seed",0))),visual_seconds,0 if miniature else 1,protected,data.get("land",{}).get("town",{}),data.get("land",{}).get("terrain",{}),projector,animated)
func _draw()->void:
	var saved_cinematic:bool=cinematic
	if miniature:cinematic=true
	super._draw();cinematic=saved_cinematic
	if view.is_empty():return
	var data:Dictionary=view.get("littoral",{})
	var equipment:Array=_observed_transports(view)
	if is_instance_valid(world3d):equipment=[]
	transport_offsets=TransportArt.screen_offsets(equipment,project,18 if not miniature else 8)
	for row in equipment:
		if str(view.get("island_war",{}).get("version","")) in ["cas-island-war-v2","cas-island-war-v3","cas-island-war-v4","cas-island-war-coastal-v1"]:
			row=row.duplicate();row["art_version"]="tactical-art-v2"
			if str(view.island_war.version) in ["cas-island-war-v3","cas-island-war-v4","cas-island-war-coastal-v1"]:row["equipment_version"]="tactical-vehicles-v4" if str(view.island_war.version) in ["cas-island-war-v4","cas-island-war-coastal-v1"] else "tactical-vehicles-v3"
		var motion:Dictionary=vehicle_motion.rows.get(int(row.id),{})
		var at:Vector2=project(motion.get("at",pos(row)))+transport_offsets.get(int(row.get("id",0)),Vector2.ZERO)
		var destination:=Vector2(float(row.get("target_x",row.get("x",0))),float(row.get("target_y",row.get("y",0))))
		var heading:float=float(row.get("heading",rad_to_deg(atan2(destination.x-pos(row).x,destination.y-pos(row).y))))
		var meters:float=16 if TransportArt.family(row)=="helicopter" else 9 if TransportArt.family(row)=="amphibious_vehicle" else 30
		var pixels:float=clampf(project(pos(row)+Vector2(meters,0)).distance_to(project(pos(row))),7 if miniature else 12,18 if miniature else 55)
		if str(row.get("kind",""))=="parachute_aircraft":
			var painted:bool=false
			if str(row.get("equipment_version","")) in ["tactical-vehicles-v3","tactical-vehicles-v4"]:painted=TransportArt.paint(self,row,at,pixels*1.4,float(motion.get("heading",deg_to_rad(heading))),visual_seconds,bool(motion.get("moving",false)),false,"transport",false)
			if not painted:
				var plane:Dictionary=row.duplicate();plane["visual_type"]="SBD";plane["heading"]=rad_to_deg(float(motion.get("heading",deg_to_rad(heading))));AircraftArt.paint(self,plane,at,pixels*1.4,visual_seconds)
		else:TransportArt.paint(self,row,at,pixels,float(motion.get("heading",deg_to_rad(heading))),visual_seconds,bool(motion.get("moving",false)),false,"transport",false)
		if str(row.get("side","allies"))=="axis":draw_line(at+Vector2(-7,10),at+Vector2(-7+14*clampf(float(row.get("hp",0))/maxf(1,float(row.get("max_hp",1))),0,1),10),Color("eb9a87"),2,true)
	for row in data.get("aviation",{}).get("aircraft",[]):
		var at:Vector2=project(pos(row));var friendly:bool=str(row.get("side","allies"))=="allies"
		var color:=Color("c2e0d8") if friendly else Color("ed9b8c")
		var heading:float=deg_to_rad(float(row.get("heading",0)))
		if not AircraftArt.paint(self,row,at,24 if miniature else 46,visual_seconds):
			var points:=PackedVector2Array()
			for p in [Vector2(0,-11),Vector2(-9,6),Vector2(0,2),Vector2(9,6)]:points.append(at+p.rotated(heading))
			draw_colored_polygon(points,color)
		if not miniature:draw_string(font,at+Vector2(12,-10),str(row.get("squadron_id","航空")),HORIZONTAL_ALIGNMENT_LEFT,-1,14,color)
	var exit:Dictionary=data.get("exit",{})
	if not exit.is_empty():
		var radius:float=project(Vector2(float(exit.get("radius",0)),0)).distance_to(project(Vector2.ZERO))
		draw_arc(project(pos(exit)),radius,0,TAU,64,Color("b9dec3"),1.5,true)
		if not miniature:draw_string(font,project(pos(exit))+Vector2(-35,0),"返航水域",HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("ebedcb"))
	if show_drag_target:
		var color:=Color("c3e7b7") if bool(drag_preview.get("valid",false)) else Color("f2a98c")
		draw_arc(project(drag_point),22,0,TAU,36,color,2,true)
		var points:=PackedVector2Array()
		for p in drag_preview.get("path",drag_path):points.append(project(pos(p)))
		if points.size()>1:draw_polyline(points,color,2,true)
func _observed_transports(source:Dictionary)->Array:
	var result:Array=source.get("littoral",{}).get("transports",[]).duplicate()
	for raw in source.get("island_war",{}).get("landing_transports",[]):
		if str(raw.get("status",""))!="sailing":continue
		var row:Dictionary=raw.duplicate();row.id=-absi(hash(str(raw.id)))-1;row["unit_id"]="";row["kind"]="landing_craft";row["side"]="axis";result.append(row)
	return result

func _has_world_background()->bool:return is_instance_valid(world3d)

func _new_coastal_map()->bool:
	return str(view.get("littoral",{}).get("land",{}).get("geography",{}).get("version",""))=="cas-coastal-geography-v1"

func _sync_world3d_camera()->void:
	if not is_instance_valid(world3d) or not is_inside_tree() or size.y<1:return
	var scale_m:float=project(Vector2.RIGHT).distance_to(project(Vector2.ZERO))
	world3d.set_chart_camera(unproject(size*.5),1.0/maxf(.000001,scale_m))
