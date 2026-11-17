@tool
extends Control
## Lightweight, public-observation naval viewport for the standalone littoral mode.
signal point_selected(point:Vector2)
signal object_selected(kind:String,object:Dictionary)
signal drag_requested(payload:Dictionary,point:Vector2,pointer:int)
const Art=preload("res://scripts/character_art.gd")
const Design=preload("res://scripts/ui_design.gd")
const TransportArt=preload("res://scripts/tactical_transport_art.gd")
@export var sea_color:Color=Color("247d94")
@export var show_grid:bool=false
var view:Dictionary={}
var cards:Dictionary={}
var chibis:bool=true
var planned:Array[Vector2]=[]
var selected_ship:int=0
var selected_contact:String=""
var zoom:float=1.0
var pan:Vector2=Vector2.ZERO
var combat_offset:Vector2=Vector2.ZERO
var clock:float=0
var projectile_rate:float=0
var projectile_readonly:bool=false
var projectile_epoch:int=0
var motion_strength:float=.75
var textures:Dictionary={}
var redraw_time:float=0
var font:Font
var water:ColorRect
var miniature:bool=false
var drag_preview:Dictionary={}
var drag_point:Vector2=Vector2.ZERO
var show_drag_target:bool=false
var playback_rate:float=1
var playing:bool=false
var previous_tick:float=-1
var observed_positions:Dictionary={}
var from_positions:Dictionary={}
var visual_positions:Dictionary={}
var travel_headings:Dictionary={}
var interpolation:float=1
var interpolation_seconds:float=.1
var transport_offsets:Dictionary={}
var transport_offset_targets:Dictionary={}

func _ready()->void:
	font=Design.font(500);clip_contents=true;texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS;resized.connect(queue_redraw)
	water=ColorRect.new();water.name="ProceduralSea";water.mouse_filter=Control.MOUSE_FILTER_IGNORE;water.show_behind_parent=true;add_child(water);water.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var material:=ShaderMaterial.new();material.shader=preload("res://shaders/home_ocean.gdshader");material.set_shader_parameter("sea_color",sea_color);water.material=material
func _process(delta:float)->void:
	if playing:clock+=delta*minf(playback_rate,2.0)
	if playing and interpolation<1:
		interpolation=minf(1,interpolation+delta/interpolation_seconds)
		for key in observed_positions:visual_positions[key]=from_positions.get(key,observed_positions[key]).lerp(observed_positions[key],interpolation)
		queue_redraw()
	if playing:
		for key in transport_offset_targets:transport_offsets[key]=(transport_offsets.get(key,transport_offset_targets[key]) as Vector2).lerp(transport_offset_targets[key],minf(1,delta*9))
	redraw_time+=delta
	if redraw_time>.05:redraw_time=0;queue_redraw()
func observe(value:Dictionary)->void:
	view=value
	var tick:float=float(view.get("tick",0));var elapsed:float=tick-previous_tick
	if previous_tick<0 or elapsed<-.00001:
		observed_positions.clear();from_positions.clear();visual_positions.clear();travel_headings.clear();clock=tick
	if previous_tick<0 or elapsed>.00001 or elapsed<-.00001:
		var current:Dictionary={}
		for type in ["ships","contacts","transports"]:
			var rows:Array=view.get("littoral",{}).get("transports",[]) if type=="transports" else view.get(type,[])
			for row in rows:
				var key:String=type+":"+str(row.get("id",0));var point:Vector2=pos(row)
				var previous:Vector2=observed_positions.get(key,point);var motion:Vector2=point-previous
				if motion.length()>.01:travel_headings[key]=atan2(motion.x,motion.y)
				from_positions[key]=visual_positions.get(key,point);current[key]=point
		observed_positions=current;interpolation=0;interpolation_seconds=clampf(maxf(.1,elapsed)/maxf(1,playback_rate),.012,.25)
		for key in current:
			if not visual_positions.has(key):visual_positions[key]=current[key]
	previous_tick=tick
	transport_offset_targets=TransportArt.screen_offsets(view.get("littoral",{}).get("transports",[]),project)
	for key in transport_offset_targets:
		if not transport_offsets.has(key):transport_offsets[key]=transport_offset_targets[key]
	for ship in view.get("ships",[]):
		var identity:String=str(ship.get("characterId",""))
		textures[identity]=Art.texture(str(Art.projection(cards.get(identity,{})).get("path","")))
	queue_redraw()
func focus_fleet()->void:zoom=1;pan=Vector2.ZERO;queue_redraw()
func cancel_pending()->bool:planned.clear();return false
func pos(row:Dictionary)->Vector2:return Vector2(float(row.get("x",0)),float(row.get("y",0)))
func visual_pos(type:String,row:Dictionary)->Vector2:return visual_positions.get(type+":"+str(row.get("id",0)),pos(row))
func project(point:Vector2)->Vector2:
	var dimensions:Vector2=Vector2(float(view.get("width",24000)),float(view.get("height",16000)))
	var viewport:Rect2=Rect2(Vector2(12,12),size-Vector2(24,24)) if miniature else Rect2(Vector2(28,100),size-Vector2(56,130))
	var factor:float=minf(viewport.size.x/dimensions.x,viewport.size.y/dimensions.y)*zoom
	return (point-dimensions*.5)*Vector2(1,-1)*factor+viewport.get_center()+pan+combat_offset
func unproject(point:Vector2)->Vector2:
	var dimensions:Vector2=Vector2(float(view.get("width",24000)),float(view.get("height",16000)))
	var viewport:Rect2=Rect2(Vector2(12,12),size-Vector2(24,24)) if miniature else Rect2(Vector2(28,100),size-Vector2(56,130))
	var factor:float=maxf(.0001,minf(viewport.size.x/dimensions.x,viewport.size.y/dimensions.y)*zoom)
	return (point-viewport.get_center()-pan-combat_offset)/factor*Vector2(1,-1)+dimensions*.5
func _polygon(raw:Variant)->PackedVector2Array:
	var polygon:PackedVector2Array=[]
	if raw is Array:
		for point in raw:
			if point is Dictionary:polygon.append(project(pos(point)))
	return polygon
func _gui_input(event:InputEvent)->void:
	if event is InputEventScreenTouch and event.pressed:
		_ship_press(event.position,event.index);accept_event();return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP:zoom=minf(3,zoom*1.12);queue_redraw();accept_event();return
		if event.button_index==MOUSE_BUTTON_WHEEL_DOWN:zoom=maxf(.6,zoom/1.12);queue_redraw();accept_event();return
		if event.button_index==MOUSE_BUTTON_LEFT:
			_ship_press(event.position,-1);accept_event()
func _ship_press(point:Vector2,pointer:int)->void:
	for ship in view.get("ships",[]):
		if project(visual_pos("ships",ship)).distance_to(point)<32:
			selected_ship=int(ship.id);object_selected.emit("ship",ship);queue_redraw();drag_requested.emit({"kind":"ship","ship":int(ship.id),"name":str(ship.get("name","舰艇")),"texture":textures.get(str(ship.get("characterId","")))},get_global_transform()*point,pointer);return
	point_selected.emit(unproject(point))
func _draw()->void:
	if water==null:draw_rect(Rect2(Vector2.ZERO,size),sea_color)
	for stripe in range(55):
		var at:Vector2=Vector2(fmod(float(stripe*163)+clock*8,size.x+80)-40,fmod(float(stripe*97),size.y))
		draw_line(at,at+Vector2(22+stripe%4*8,sin(clock+stripe)*2),Color(.8,1,1,.12),1.5,true)
	if show_grid:
		for index in range(12):
			draw_line(Vector2(index*size.x/12,0),Vector2(index*size.x/12,size.y),Color(1,1,1,.05))
	for island in view.get("islands",[]):
		var raw:Variant=island.get("polygon",island.get("points",[])) if island is Dictionary else island
		var polygon:PackedVector2Array=_polygon(raw)
		if polygon.size()>2:
			draw_polyline(polygon,Color(.45,.82,.79,.34),13,true);draw_colored_polygon(polygon,Color("d6cfaa"));draw_polyline(polygon,Color("a8dbcc"),3,true)
			var inner:PackedVector2Array=[];var center:Vector2=Vector2.ZERO
			for point in polygon:center+=point
			center/=polygon.size()
			for point in polygon:inner.append(point.lerp(center,.06))
			draw_colored_polygon(inner,Color("829b6d"))
			var extent:Vector2=Vector2.ZERO
			for point in inner:extent=extent.max((point-center).abs())
			for index in range(18):
				var at:Vector2=center+Vector2(sin(index*2.39)*extent.x*.8,cos(index*3.13)*extent.y*.8)
				if not Geometry2D.is_point_in_polygon(at,inner):continue
				if index%3==0:
					draw_colored_polygon(PackedVector2Array([at+Vector2(-5,3),at+Vector2(-3,-5),at+Vector2(4,-7),at+Vector2(7,2)]),Color("a8b198"))
				else:
					draw_line(at,at+Vector2(0,-7),Color("536d57"),2);draw_circle(at+Vector2(-3,-6),4,Color("50785a"));draw_circle(at+Vector2(2,-10),5,Color("719666"))
	var littoral:Dictionary=view.get("littoral",{})
	for beach in littoral.get("beaches",[]):
		var point:Vector2=project(pos(beach.get("sea",{})))
		draw_arc(point,5 if miniature else 18,0,TAU,24,Color("f3df9d"),2,true)
		if font!=null and not miniature:draw_string(font,point+Vector2(22,5),str(beach.get("name","登陆点")),HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("fff2cc"))
	var extraction:Variant=littoral.get("exit",{})
	if extraction is Dictionary and extraction.has("x"):
		var center:Vector2=project(pos(extraction));var radius:float=project(pos(extraction)+Vector2(float(extraction.get("radius",1600)),0)).distance_to(center)
		draw_arc(center,radius,0,TAU,40,Color("b9ead0"),2,true)
		if not miniature:draw_string(font,center+Vector2(-24,7),"返航",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("dcf3d3"))
	for ship in view.get("ships",[]):
		var point:Vector2=project(visual_pos("ships",ship));var identity:String=str(ship.get("characterId",""));var texture:Texture2D=textures.get(identity)
		if float(ship.get("hp",1))<=0:continue
		if miniature:draw_circle(point,3.2,Color("cbead1"));continue
		draw_arc(point+Vector2(0,7),18,0,TAU,24,Color(1,1,1,.35),1,true)
		if chibis and texture!=null:draw_texture_rect(texture,Rect2(point-Vector2(30,50),Vector2(60,60)),false)
		else:
			var forward:Vector2=Vector2(sin(deg_to_rad(float(ship.get("heading",0)))),-cos(deg_to_rad(float(ship.get("heading",0)))))
			draw_line(point-forward*14,point+forward*14,Color("d5eedf"),7,true)
		if int(ship.get("id",0))==selected_ship:draw_arc(point,25,0,TAU,32,Color("f6dca0"),2,true)
	for enemy in view.get("contacts",[]):
		var point:Vector2=project(visual_pos("contacts",enemy));draw_circle(point,6,Color("d79078"));draw_arc(point,10,0,TAU,16,Color("f2bca2"),1,true)
	for transport in littoral.get("transports",[]):
		var original:Vector2=project(visual_pos("transports",transport));var point:Vector2=original+(Vector2.ZERO if miniature else transport_offsets.get(int(transport.id),Vector2.ZERO));var air:bool=str(transport.get("kind","")) in ["air","helicopter"]
		var firing:bool=false
		for shot in littoral.get("shots",[]):
			if str(shot.get("kind",""))=="transport_gunship" and str(shot.get("source",""))==str(transport.get("unit_id","")) and float(view.get("tick",0))-float(shot.get("tick",-100))<.2:firing=true;break
		if not miniature and TransportArt.paint(self,transport,point,70,travel_headings.get("transports:"+str(transport.get("id",0)),0),clock,true,str(transport.get("unit_id",""))==str(littoral.get("selected_unit","")),"infantry",firing):
			if point.distance_to(original)>8:draw_line(original,point,Color(.9,.9,.73,.4),1,true);draw_circle(original,1.6,Color("f1e2ac"))
			draw_string(font,point+Vector2(-30,48),str(transport.get("unit_id","")),HORIZONTAL_ALIGNMENT_LEFT,75,13,Color("e8eed4"));continue
		draw_line(point-Vector2(9,0),point+Vector2(9,0),Color("fff1c0"),2,true);draw_circle(point,4,Color("f6efc9"))
		if air:draw_line(point-Vector2(0,7),point+Vector2(0,7),Color("fff1c0"),2,true)
	# Exit is a public field, never inferred from the opponent or the result.
	for projectile in view.get("shells",[]):
		var point:Vector2=project(pos(projectile));draw_circle(point,3,Color("ffe9a9"))
	if show_drag_target:
		var at:Vector2=project(drag_point);var valid:bool=bool(drag_preview.get("valid",false));var color:Color=Color("c4efb7") if valid else Color("ed9e89")
		draw_arc(at,24,0,TAU,32,color,3,true)
		var path:PackedVector2Array=[]
		for row in drag_preview.get("path",[]):
			if row is Dictionary:path.append(project(pos(row)))
		if path.size()>1:draw_polyline(path,color,3,true)
		var shore:Variant=drag_preview.get("land")
		if shore is Dictionary:draw_circle(project(pos(shore)),8,color)
