@tool
extends Control
signal cell_selected(cell:Vector2i)
signal placement_changed(cell:Vector2i,valid:bool,reason:String)
signal camera_changed
signal collection_requested(building_id:String)
const FacilityArt=preload("res://scripts/home_building_art.gd")
const NativeProjection=preload("res://scripts/home_projection_v4.gd")
const NativeTerrain=preload("res://scripts/procedural_amphibious_terrain.gd")
const TerrainBackdrop=preload("res://scripts/littoral_terrain_backdrop.gd")
const World3DSettings=preload("res://scripts/world3d_settings.gd")
var world3d:Control
var world3d_center:Vector2=Vector2.ZERO
@export var island_seed:int=1387249
@export var sea_color:Color=Color("2b9db3")
@export var land_color:Color=Color("89bb82")
@export var draw_construction_grid:bool=false
@export_range(.8,2.5) var minimum_zoom:float=.85
@export_range(1.0,60.0) var maximum_zoom:float=48.0
@export var zoom:float=1.0
@export var pan:Vector2=Vector2.ZERO
@export_dir var facility_artwork_directory:String="res://assets/home/buildings"
@export_dir var environment_artwork_directory:String="res://assets/home/environment"
@export_range(.6,3.0) var facility_scale:float=2.2
@export var facility_artwork_anchor:Vector2=Vector2(.5,.72)
@export_range(0.0,.3) var ground_detail_strength:float=.09
var snapshot:Dictionary={"buildings":[],"garrison":[]}
var selected:Vector2i=Vector2i(-1,-1)
var clock:float=0.0
var redraw_time:float=0.0
var ship_textures:Array[Texture2D]=[]
var water:ColorRect
var placement_kind:String=""
var placement_cell:Vector2i=Vector2i(-1,-1)
var placement_valid:bool=false
var placement_reason:String=""
var pointer_down:bool=false
var pointer_dragged:bool=false
var pointer_origin:Vector2
var previous_pointer:Vector2
var touches:Dictionary={}
var pinch_distance:float=0
var pinch_center:Vector2
var ground_texture:Texture2D
var ground_seed:int=-1
var native_geometry:Dictionary={}
var native_projection
var native_signature:int=0
var native_walkways:Array=[]
var walkway_signature:int=0
var paving_material:Texture2D
var terrain_backdrop:Control
var terrain_draw_key:int=0
var terrain_draw_key_valid:bool=false

func _ground_texture()->Texture2D:
	if ground_texture!=null and ground_seed==island_seed:return ground_texture
	ground_seed=island_seed
	var noise:=FastNoiseLite.new();noise.seed=island_seed;noise.frequency=.036;noise.fractal_octaves=4
	var image:=Image.create(192,192,false,Image.FORMAT_RGBA8)
	for y in range(192):
		for x in range(192):
			var value:float=noise.get_noise_2d(x,y)*ground_detail_strength
			var color:Color=land_color.lightened(maxf(0,value)).darkened(maxf(0,-value))
			image.set_pixel(x,y,color)
	ground_texture=ImageTexture.create_from_image(image)
	return ground_texture

func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_STOP;clip_contents=true;texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	resized.connect(func():_clamp_pan();_refresh_native_ground();queue_redraw())
	camera_changed.connect(_refresh_native_ground)
	water=ColorRect.new();water.name="ProceduralWater";water.mouse_filter=Control.MOUSE_FILTER_IGNORE;water.show_behind_parent=true;add_child(water);water.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var material:=ShaderMaterial.new();material.shader=preload("res://shaders/home_ocean.gdshader");material.set_shader_parameter("sea_color",sea_color);water.material=material
	terrain_backdrop=TerrainBackdrop.new();terrain_backdrop.name="HomeNativeGround";terrain_backdrop.source_map=self;terrain_backdrop.visible=false;add_child(terrain_backdrop)

func _process(delta:float)->void:
	clock+=delta;redraw_time+=delta
	if redraw_time>=.1:redraw_time=0;queue_redraw()

func observe(value:Dictionary,textures:Array[Texture2D]=[])->void:
	snapshot=value;island_seed=int(value.get("seed",island_seed));ship_textures=textures
	var next:Dictionary=value.get("geometry_v4",{})
	var signature:int=hash(next)
	var first_native:bool=native_projection==null and bool(next.get("ok",false))
	if signature!=native_signature:
		native_signature=signature;native_geometry=next
		if bool(next.get("ok",false)):
			native_projection=NativeProjection.new();native_projection.bind(next)
		else:native_projection=null
	if has_native_geometry() and World3DSettings.eligible(native_projection.land):_observe_world3d()
	if first_native:focus_base()
	_refresh_native_ground();queue_redraw()
func has_native_geometry()->bool:return native_projection!=null and bool(native_geometry.get("ok",false))
func grid_cells()->Array:
	if has_native_geometry():return native_projection.cells
	var result:Array=[]
	for y in range(9):
		for x in range(12):
			if land(Vector2i(x,y)):result.append(Vector2i(x,y))
	return result
func resident_position(index:int,naval:bool,progress:float)->Vector2:
	_sync_projection()
	if is_instance_valid(world3d):
		return world3d.project(native_projection.resident_world(index,naval,progress))
	return native_projection.resident(index,naval,progress) if has_native_geometry() else Vector2.ZERO
func resident_height()->float:
	if is_instance_valid(world3d):return clampf(_world3d_scale()*6.0,12,64)
	_sync_projection();return clampf(14.0*native_projection.scale(),12,44) if has_native_geometry() else 81.0
func _sync_projection()->void:
	if has_native_geometry():native_projection.screen=rect()

func base_rect()->Rect2:
	if has_native_geometry():return Rect2(Vector2(70,64),Vector2(maxf(1,size.x-140),maxf(1,size.y-120)))
	var width:float=maxf(1,minf(size.x*.84,(size.y-135)/.69))
	return Rect2(Vector2((size.x-width)*.5,65),Vector2(width,width*.69))

func rect()->Rect2:
	var base:Rect2=base_rect();var center:Vector2=size*.5
	return Rect2((base.position-center)*zoom+center+pan,base.size*zoom)

func point(cell:Vector2)->Vector2:
	if is_instance_valid(world3d):return world3d.project(native_projection.world(cell))
	if has_native_geometry():_sync_projection();return native_projection.project(native_projection.world(cell))
	var field:Rect2=rect();return field.position+(cell+Vector2(.5,.5))/Vector2(12,9)*field.size

func land(cell:Vector2i)->bool:
	if has_native_geometry():return native_projection.legal.has(cell) or occupied(cell)
	if cell.x<0 or cell.x>=12 or cell.y<0 or cell.y>=9:return false
	var relative:Vector2=(Vector2(cell)-Vector2(5.5,4))/Vector2(5.3,3.8)
	var physical:bool=relative.length_squared()<.83+sin(float(cell.x*31+cell.y*17+island_seed%137)*1.71)*.12
	var area:float=float(snapshot.get("development",{}).get("buildable_radius_squared",1.0))
	return physical and (relative.length_squared()<area or occupied(cell))

func cell_at(local_position:Vector2)->Vector2i:
	if is_instance_valid(world3d):
		var origin:Dictionary=native_projection.grid.get("origin",{})
		var world:Vector2=world3d.unproject(local_position)-Vector2(float(origin.get("x",0)),float(origin.get("y",0)))
		return Vector2i((world/maxf(1,float(native_projection.grid.get("cell_size_m",120)))).floor())
	if has_native_geometry():_sync_projection();return native_projection.cell_at(local_position)
	var local:Vector2=(local_position-rect().position)/rect().size*Vector2(12,9)
	return Vector2i(int(floor(local.x)),int(floor(local.y)))

func occupied(cell:Vector2i)->bool:
	for building in snapshot.get("buildings",[]):
		if Vector2i(int(building.cell.x),int(building.cell.y))==cell:return true
	return false

func begin_placement(kind:String,cell:Vector2i)->void:
	placement_kind=kind;draw_construction_grid=true;_preview(cell)

func end_placement()->void:
	placement_kind="";placement_cell=Vector2i(-1,-1);draw_construction_grid=false;queue_redraw()

func _preview(cell:Vector2i)->void:
	placement_cell=cell;placement_valid=land(cell) and not occupied(cell)
	placement_reason="可建造" if placement_valid else "已有设施" if occupied(cell) else "升级中枢可扩区 / 岛外不可建造"
	placement_changed.emit(cell,placement_valid,placement_reason);queue_redraw()

func reset_camera()->void:
	if is_instance_valid(world3d):
		zoom=1;world3d_center=_world3d_bounds().get_center();_sync_world3d_camera();camera_changed.emit();queue_redraw();return
	zoom=1;pan=Vector2.ZERO;camera_changed.emit();queue_redraw()
func toggle_overview()->void:
	if has_native_geometry() and zoom<=1.2:focus_base()
	else:reset_camera()
func focus_base()->void:
	var headquarters:=Vector2(6,4)
	for building in snapshot.get("buildings",[]):
		if str(building.get("kind",""))=="hq":headquarters=Vector2(float(building.cell.x),float(building.cell.y));break
	var center:Vector2=Vector2.ZERO;var count:int=0
	for building in snapshot.get("buildings",[]):
		var at:=Vector2(float(building.cell.x),float(building.cell.y))
		if at.distance_to(headquarters)<=8:center+=at;count+=1
	if count==0:center=headquarters
	else:center/=count
	if is_instance_valid(world3d):
		# Start in the inhabited base, rather than shrinking its real buildings
		# to fit the entire strategic island. Overview remains a separate action.
		zoom=_world3d_zoom_for_span(120.0)
		world3d_center=native_projection.world(headquarters);_sync_world3d_camera();camera_changed.emit();queue_redraw();return
	zoom=clampf(24,minimum_zoom,maximum_zoom);pan=Vector2.ZERO;pan=size*.5-point(center);_clamp_pan();camera_changed.emit();queue_redraw()
func focus_cell(cell:Vector2i,new_zoom:float=5)->void:
	if is_instance_valid(world3d):
		zoom=_world3d_zoom_for_span(100.0);world3d_center=native_projection.world(Vector2(cell));_sync_world3d_camera();camera_changed.emit();queue_redraw();return
	zoom=clampf(new_zoom,minimum_zoom,maximum_zoom);pan=Vector2.ZERO
	pan=size*.5-point(Vector2(cell));_clamp_pan();camera_changed.emit();queue_redraw()

func _clamp_pan()->void:
	var limit:Vector2=Vector2(size.x*.26,size.y*.27)*maxf(1,zoom)
	pan=pan.clamp(-limit,limit)

func zoom_at(factor:float,position:Vector2)->void:
	if is_instance_valid(world3d):
		var before:Vector2=world3d.unproject(position)
		zoom=clampf(zoom*factor,minimum_zoom,160.0);_sync_world3d_camera()
		world3d_center+=before-world3d.unproject(position);_sync_world3d_camera();camera_changed.emit();queue_redraw();return
	var old:float=zoom;zoom=clampf(zoom*factor,minimum_zoom,maximum_zoom)
	pan=(pan+size*.5-position)*(zoom/old)+position-size*.5
	_clamp_pan();camera_changed.emit();queue_redraw()

func _press(position:Vector2)->void:
	pointer_down=true;pointer_dragged=false;pointer_origin=position;previous_pointer=position
	if not placement_kind.is_empty():_preview(cell_at(position))

func _drag(position:Vector2)->void:
	if not pointer_down:return
	if position.distance_to(pointer_origin)>9:pointer_dragged=true
	if not placement_kind.is_empty():_preview(cell_at(position))
	elif pointer_dragged:
		if is_instance_valid(world3d):
			world3d_center+=world3d.unproject(previous_pointer)-world3d.unproject(position);_sync_world3d_camera()
		else:pan+=position-previous_pointer;_clamp_pan()
		camera_changed.emit();queue_redraw()
	previous_pointer=position

func _release(position:Vector2)->void:
	if not pointer_down:return
	pointer_down=false
	if not placement_kind.is_empty():_preview(cell_at(position));return
	if pointer_dragged:return
	var cell:Vector2i=cell_at(position);var nearest:float=70 if not has_native_geometry() else 28
	for building in snapshot.get("buildings",[]):
		var at:Vector2=point(Vector2(int(building.cell.x),int(building.cell.y)))+Vector2(0,-10)
		var definition:Dictionary=preload("res://scripts/home_service.gd").BUILDINGS.get(str(building.get("kind","")),{})
		if definition.has("produces") and int(snapshot.get("pending",{}).get(str(definition.produces),0))>0:
			var bubble:Vector2=at+Vector2(0,10-_facility_width()*.60-sin(clock*2)*3)
			if position.distance_to(bubble)<=40:collection_requested.emit(str(building.id));return
		var distance:float=at.distance_to(position)
		if distance<nearest:nearest=distance;cell=Vector2i(int(building.cell.x),int(building.cell.y))
	var buildings:Array=snapshot.get("buildings",[]).duplicate();buildings.sort_custom(func(a:Dictionary,b:Dictionary):return int(a.cell.y)>int(b.cell.y))
	for building in buildings:
		var footprint:Vector2i=Vector2i(int(building.cell.x),int(building.cell.y))
		if FacilityArt.hit_test(position,point(Vector2(footprint)),_facility_width(),str(building.kind),facility_artwork_directory,facility_artwork_anchor):cell=footprint;break
	selected=cell;cell_selected.emit(cell);queue_redraw()

func _gui_input(event:InputEvent)->void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:zoom_at(1.12 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1/1.12,event.position);accept_event()
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:_press(event.position)
			else:_release(event.position)
			accept_event()
	elif event is InputEventMouseMotion and pointer_down:_drag(event.position);accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index]=event.position
			if touches.size()==1:_press(event.position)
			elif touches.size()==2:
				var values:Array=touches.values();pinch_distance=values[0].distance_to(values[1]);pinch_center=(values[0]+values[1])*.5;pointer_down=false
		else:
			if touches.size()==1:_release(event.position)
			touches.erase(event.index)
		accept_event()
	elif event is InputEventScreenDrag:
		touches[event.index]=event.position
		if touches.size()==1:_drag(event.position)
		elif touches.size()==2:
			var values:Array=touches.values();var distance:float=values[0].distance_to(values[1]);var center:Vector2=(values[0]+values[1])*.5
			if pinch_distance>1:zoom_at(distance/pinch_distance,center)
			if is_instance_valid(world3d):
				world3d_center+=world3d.unproject(pinch_center)-world3d.unproject(center);_sync_world3d_camera()
			else:pan+=center-pinch_center;_clamp_pan()
			pinch_distance=distance;pinch_center=center;camera_changed.emit();queue_redraw()
		accept_event()
	elif event is InputEventMagnifyGesture:zoom_at(event.factor,event.position);accept_event()

func _draw()->void:
	if is_instance_valid(world3d):_draw_world3d_overlay();return
	if water==null:draw_rect(Rect2(Vector2.ZERO,size),sea_color)
	if has_native_geometry():_draw_native();return
	if snapshot.has("geometry_v4") and not bool(native_geometry.get("ok",false)):
		draw_string(ThemeDB.fallback_font,Vector2(size.x*.5-100,size.y*.5),"正在接通岛屿地形…",HORIZONTAL_ALIGNMENT_LEFT,-1,24,Color("eff4df"));return
	for layer in range(7):
		var radius:float=float(layer+1)*size.x*.13
		draw_arc(size*Vector2(.53,.6),radius,0,TAU,90,Color(1,1,1,.018),20)
	for index in range(46):
		var origin:Vector2=Vector2(fmod(float(index*181)+clock*9,size.x+100)-50,fmod(float(index*83),size.y))
		var length:float=18+float(index%4)*7
		draw_line(origin,origin+Vector2(length,sin(clock*1.2+index)*2),Color(.84,1,1,.14),1.5,true)
	var field:Rect2=rect();var cell_size:Vector2=field.size/Vector2(12,9)
	var terrain_scale:float=minf(1.0,sqrt(float(snapshot.get("development",{}).get("area_radius_squared",.83))/.83))
	# Smooth, seeded shores enclose the exact buildable grid; no fixed map artwork.
	var coast:PackedVector2Array=[];var cliff:PackedVector2Array=[];var grass:PackedVector2Array=[]
	var center:Vector2=field.get_center()
	for index in range(96):
		var angle:float=index*TAU/96.0
		var radius:float=1.0+sin(angle*3+island_seed*.013)*.075+sin(angle*7+island_seed*.007)*.035
		var at:Vector2=center+Vector2(cos(angle)*field.size.x*.47,sin(angle)*field.size.y*.47)*radius*terrain_scale
		coast.append(at);cliff.append(at+Vector2(0,15));grass.append(at.lerp(center,.055))
	draw_polyline(coast,Color(.35,.76,.72,.28),45,true);draw_polyline(coast,Color(.66,.92,.82,.46),25,true)
	draw_colored_polygon(cliff,Color("527e77"));draw_colored_polygon(coast,Color("e2d6aa"))
	var grass_uv:PackedVector2Array=[]
	for at in grass:grass_uv.append((at-field.position)/field.size)
	draw_polygon(grass,PackedColorArray([Color.WHITE]),grass_uv,_ground_texture())
	draw_polyline(grass,Color("adca8b"),4,true)
	for index in range(24):
		var angle:float=index*2.399963+island_seed*.05;var radius:float=sqrt(float(index+1)/25.0)*.35
		var at:Vector2=center+Vector2(cos(angle)*field.size.x,sin(angle)*field.size.y)*radius*terrain_scale
		_decor("ground_patch",at,cell_size.x*(2.7+float(index%3)*.3),.55)
	for index in range(6):
		var angle:float=index*2.399963+island_seed*.012
		var at:Vector2=center+Vector2(cos(angle)*field.size.x,sin(angle)*field.size.y)*.405*terrain_scale
		_decor("beach_patch",at,cell_size.x*(1.3+float(index%3)*.17),.75)
	for entry in [{"kind":"coastal_cliff","cell":Vector2i(2,3),"scale":2.0},{"kind":"coastal_cliff","cell":Vector2i(9,5),"scale":2.3},{"kind":"ruin_cluster","cell":Vector2i(8,2),"scale":1.6},{"kind":"ruin_cluster","cell":Vector2i(3,6),"scale":1.5},{"kind":"ruin_cluster","cell":Vector2i(9,3),"scale":1.4}]:
		if land(entry.cell) and not occupied(entry.cell):_decor(str(entry.kind),point(Vector2(entry.cell)),cell_size.x*float(entry.scale))
	for index in range(105):
		var angle:float=index*2.399963+island_seed*.07;var radius:float=sqrt(float(index+1)/106.0)*.35
		var at:Vector2=center+Vector2(cos(angle)*field.size.x,sin(angle)*field.size.y)*radius*terrain_scale
		var tone:Color=Color(.29,.5,.3,.10) if index%3 else Color(.85,.9,.55,.17)
		draw_line(at-Vector2(2,1),at+Vector2(1,-3),tone,1,true);draw_line(at+Vector2(1,1),at+Vector2(4,-2),tone,1,true)
	for hill in range(5):
		var top:Vector2=center+Vector2(sin(hill*2.3+island_seed)*field.size.x*.29,cos(hill*1.7)*field.size.y*.25)*terrain_scale
		var patch:PackedVector2Array=[]
		for step in range(28):
			var angle:float=step*TAU/28;var radius:float=1+sin(step*2.1+hill)*.13
			patch.append(top+Vector2(cos(angle)*field.size.x*.1,sin(angle)*field.size.y*.13)*radius)
		for clipped in Geometry2D.intersect_polygons(patch,grass):draw_colored_polygon(clipped,Color(.2,.4,.23,.045))
		_decor("grass_patch",top,cell_size.x*1.8,.65)
	# Small rock shelves and scrub remain entirely decorative inside the island.
	for index in range(36):
		var angle:float=index*2.399963+island_seed*.01;var radius:float=.29+float(index%7)*.018
		var at:Vector2=center+Vector2(cos(angle)*field.size.x*radius,sin(angle)*field.size.y*radius)*terrain_scale
		if index%3==0:_rock(at,5+index%4)
		else:
			draw_circle(at,3.5,Color("679b6f"));draw_circle(at+Vector2(4,-2),3,Color("a3c784"))
	for y in range(9):
		for x in range(12):
			var cell:Vector2i=Vector2i(x,y)
			if not land(cell):continue
			var bounds:Rect2=Rect2(point(Vector2(cell))-cell_size*.53,cell_size*1.06)
			if (x*11+y*3)%9==0:
				var at:Vector2=point(Vector2(cell))+Vector2(5,-5)
				if not occupied(cell):_tree(at,cell_size.x*.45)
			if draw_construction_grid:draw_rect(bounds,Color(1,1,1,.22),false,1)
			if cell==selected:draw_rect(bounds.grow(-2),Color("fff0b9"),false,3)
	var buildings:Array=snapshot.get("buildings",[]).duplicate();buildings.sort_custom(func(a:Dictionary,b:Dictionary):return int(a.cell.y)<int(b.cell.y))
	for raw in buildings:
		var building:Dictionary=raw
		var at:Vector2=point(Vector2(float(building.get("cell",{}).get("x",6)),float(building.get("cell",{}).get("y",4))))
		FacilityArt.paint(self,at,cell_size.x*facility_scale,str(building.get("kind","hq")),int(building.get("level",1)),int(building.get("hp",100)),facility_artwork_directory,facility_artwork_anchor)
		var definition:Dictionary=preload("res://scripts/home_service.gd").BUILDINGS.get(str(building.get("kind","")),{})
		if definition.has("produces") and int(snapshot.get("pending",{}).get(str(definition.produces),0))>0:
			var bubble:Vector2=at+Vector2(0,-cell_size.x*facility_scale*.60-sin(clock*2)*3)
			draw_circle(bubble,28,Color("fff1c6"));draw_circle(bubble,28,Color("427e83"),false,2,true)
			draw_line(bubble+Vector2(-8,-2),bubble+Vector2(-1,5),Color("397278"),4,true);draw_line(bubble+Vector2(-1,5),bubble+Vector2(10,-8),Color("397278"),4,true)
	if not placement_kind.is_empty():
		var at:Vector2=point(Vector2(placement_cell));var bounds:Rect2=Rect2(at-cell_size*.48,cell_size*.96)
		var color:Color=Color("8de6ba") if placement_valid else Color("ffac92")
		draw_rect(bounds,color.darkened(.4));draw_rect(bounds,color,false,3)
		FacilityArt.paint(self,at,cell_size.x*facility_scale,placement_kind,1,100,facility_artwork_directory,facility_artwork_anchor)
		draw_circle(at+Vector2(cell_size.x*.42,-cell_size.y*.45),16,color)
		var symbol:Vector2=at+Vector2(cell_size.x*.42,-cell_size.y*.45)
		if placement_valid:draw_line(symbol+Vector2(-7,0),symbol+Vector2(-1,6),Color("204e48"),3,true);draw_line(symbol+Vector2(-1,6),symbol+Vector2(9,-6),Color("204e48"),3,true)
		else:draw_line(symbol-Vector2(6,6),symbol+Vector2(6,6),Color("753b30"),3,true);draw_line(symbol+Vector2(-6,6),symbol+Vector2(6,-6),Color("753b30"),3,true)
	for index in range(ship_textures.size()):
		var at:Vector2=Vector2(field.position.x+field.size.x*.2+index*64,field.end.y+40+sin(clock*1.4+index)*3)
		draw_arc(at+Vector2(0,25),32,0,TAU,32,Color(1,1,1,.22),1.5,true)
		if ship_textures[index]!=null:draw_texture_rect(ship_textures[index],Rect2(at-Vector2(40,60),Vector2(80,80)),false)
	# A few slowly drifting cloud groups keep the island view alive without photographs.
	for index in range(3):
		var at:Vector2=Vector2(fmod(index*283.0+clock*5,size.x+170)-85,size.y*(.08+float(index%2)*.73))
		_cloud(at,.75+index*.09)

func _facility_width()->float:
	if is_instance_valid(world3d):return clampf(_world3d_scale()*36,20,160)
	if has_native_geometry():_sync_projection();return clampf(native_projection.scale()*65,20,160)
	return rect().size.x/12*facility_scale
func _courtyard_dry(point:Vector2,water:Array,fords:Array,shore:PackedVector2Array)->bool:
	if not Geometry2D.is_point_in_polygon(point,shore):return false
	for polygon in fords:
		if Geometry2D.is_point_in_polygon(point,polygon):return true
	for polygon in water:
		if Geometry2D.is_point_in_polygon(point,polygon):return false
	return true
func _prepare_native_walkways()->void:
	var key:int=hash([native_signature,snapshot.get("buildings",[])])
	if key==walkway_signature:return
	walkway_signature=key;native_walkways=[]
	var positions:Array[Vector2]=[];var wet:Array=[];var fords:Array=[]
	for building in snapshot.get("buildings",[]):positions.append(native_projection.world(Vector2(float(building.cell.x),float(building.cell.y))))
	var shore:PackedVector2Array=NativeTerrain.points(native_projection.land.get("polygon",[]))
	for feature in native_projection.land.get("terrain",{}).get("features",[]):
		var kind:String=str(feature.get("kind",""))
		if kind in ["river","swamp"]:wet.append(NativeTerrain.points(feature.get("polygon",[])))
		elif kind=="ford":fords.append(NativeTerrain.points(feature.get("polygon",[])))
	if positions.size()<2:return
	var connected:Array[int]=[0];var remaining:Array[int]=[]
	for index in range(1,positions.size()):remaining.append(index)
	while not remaining.is_empty():
		var distance:float=INF;var first:int=-1;var second:int=-1
		for a in connected:
			for b in remaining:
				var separation:float=positions[a].distance_to(positions[b])
				if separation<distance:distance=separation;first=a;second=b
		if second<0:break
		connected.append(second);remaining.erase(second)
		if distance>900:continue
		var segment:PackedVector2Array=[];var steps:int=maxi(1,int(ceil(distance/8.0)))
		for step in range(steps+1):
			var at:Vector2=positions[first].lerp(positions[second],float(step)/float(steps))
			if _courtyard_dry(at,wet,fords,shore):segment.append(at)
			else:
				if segment.size()>1:native_walkways.append(segment)
				segment=PackedVector2Array()
		if segment.size()>1:native_walkways.append(segment)
func _draw_native_courtyards(canvas:CanvasItem)->void:
	# Ground dressing follows existing metre coordinates. It adds no roads,
	# traversal rules, collisions or relocated facilities to the native model.
	_prepare_native_walkways()
	var scale:float=native_projection.scale()
	for path in native_walkways:
		var screen_path:PackedVector2Array=[]
		for at in path:screen_path.append(native_projection.project(at))
		canvas.draw_polyline(screen_path,Color("aba891"),maxf(.45,6.0*scale),true);canvas.draw_polyline(screen_path,Color("d9d0b5"),maxf(.35,3.8*scale),true)
	for building in snapshot.get("buildings",[]):
		var at:Vector2=native_projection.world(Vector2(float(building.cell.x),float(building.cell.y)))
		var offsets:=PackedVector2Array([Vector2(-29,-18),Vector2(-25,-22),Vector2(25,-22),Vector2(29,-18),Vector2(29,18),Vector2(25,22),Vector2(-25,22),Vector2(-29,18)])
		var corners:PackedVector2Array=[];var uv:PackedVector2Array=[]
		for offset in offsets:corners.append(at+offset);uv.append((offset+Vector2(29,22))/Vector2(58,44))
		var color:Color=Color(.96,.94,.84,.91) if str(building.kind) in ["hq","medical","depot","dock"] else Color(.86,.90,.82,.90)
		preload("res://scripts/littoral_ground_mesh.gd").paint(canvas,corners,native_projection.project,color,_paving_material(),uv)
		var outline:PackedVector2Array=[]
		for point in corners:outline.append(native_projection.project(point))
		outline.append(outline[0]);canvas.draw_polyline(outline,Color(.44,.47,.38,.37),maxf(.4,.45*scale),true)
func _paving_material()->Texture2D:
	if paving_material!=null:return paving_material
	var image:=Image.create(192,192,false,Image.FORMAT_RGBA8)
	for y in range(192):
		for x in range(192):
			var row:int=int(y/8);var shifted:int=(x+(row%2)*6)%12;var joint:bool=y%8==0 or shifted==0
			var variation:float=sin(float(int(x/12)*31+row*17))*.025
			image.set_pixel(x,y,Color(.67,.68,.61) if joint else Color(.79+variation,.80+variation,.72+variation))
	image.generate_mipmaps();paving_material=ImageTexture.create_from_image(image);return paving_material
func _refresh_native_ground()->void:
	if is_instance_valid(world3d):
		_sync_world3d_camera()
		if is_instance_valid(terrain_backdrop):terrain_backdrop.hide()
		if is_instance_valid(water):water.hide()
		return
	if not is_instance_valid(terrain_backdrop):return
	terrain_backdrop.visible=has_native_geometry()
	terrain_backdrop.size=size
	if not terrain_backdrop.visible:return
	_sync_projection()
	# CanvasItem retains the native mesh until geometry, camera or existing
	# facility dressing changes. Water, cloud and resident layers remain live.
	var next:int=hash([native_signature,island_seed,size,zoom,pan,snapshot.get("buildings",[])])
	if not terrain_draw_key_valid or next!=terrain_draw_key:
		terrain_draw_key=next;terrain_draw_key_valid=true;terrain_backdrop.queue_redraw()
func paint_static_terrain(canvas:CanvasItem)->void:
	if not has_native_geometry():return
	_sync_projection()
	var land_data:Dictionary=native_projection.land
	NativeTerrain.paint(canvas,land_data.get("polygon",[]),native_projection.project,island_seed,0,2,[],land_data.get("town",{}),land_data.get("terrain",{}),native_projection.flat,false)
	_draw_native_courtyards(canvas)
func _draw_native()->void:
	_sync_projection()
	if not is_instance_valid(terrain_backdrop) or not terrain_backdrop.visible:paint_static_terrain(self)
	NativeTerrain.paint_coast_motion(self,native_projection.land.get("polygon",[]),native_projection.project,clock)
	if draw_construction_grid:
		for cell in native_projection.cells:
			var at:Vector2=point(Vector2(cell))
			if not Rect2(Vector2.ZERO,size).grow(25).has_point(at):continue
			var tile:PackedVector2Array=native_projection.tile(cell)
			if at.distance_to(point(Vector2(cell)+Vector2.RIGHT))>8:draw_polyline(tile,Color(1,1,1,.20),1,true)
	if selected!=Vector2i(-1,-1):draw_polyline(native_projection.tile(selected),Color("fff0b9"),2.0,true)
	var ordered:Array=snapshot.get("buildings",[]).duplicate();ordered.sort_custom(func(a,b):return point(Vector2(float(a.cell.x),float(a.cell.y))).y<point(Vector2(float(b.cell.x),float(b.cell.y))).y)
	var width:float=_facility_width()
	for building in ordered:
		var at:Vector2=point(Vector2(float(building.cell.x),float(building.cell.y)))
		if not Rect2(Vector2.ZERO,size).grow(150).has_point(at):continue
		FacilityArt.paint(self,at,width,str(building.get("kind","hq")),int(building.get("level",1)),int(building.get("hp",100)),facility_artwork_directory,facility_artwork_anchor)
		var definition:Dictionary=preload("res://scripts/home_service.gd").BUILDINGS.get(str(building.kind),{})
		if definition.has("produces") and int(snapshot.get("pending",{}).get(str(definition.produces),0))>0:
			var bubble:Vector2=at+Vector2(0,-width*.60-sin(clock*2)*3);draw_circle(bubble,14,Color("fff1c6"));draw_line(bubble+Vector2(-5,0),bubble+Vector2(0,4),Color("397278"),2,true);draw_line(bubble+Vector2(0,4),bubble+Vector2(6,-5),Color("397278"),2,true)
	if not placement_kind.is_empty():
		var tile:PackedVector2Array=native_projection.tile(placement_cell);var tint:Color=Color("8de6ba") if placement_valid else Color("ffac92")
		draw_polyline(tile,tint,3,true);FacilityArt.paint(self,point(Vector2(placement_cell)),width,placement_kind,1,100,facility_artwork_directory,facility_artwork_anchor)
	# Metric scale reports the actual native map; icons have a minimum tap size.
	var metres:float=1000.0;var length:float=metres*native_projection.scale()
	while length>size.x*.2:metres*=.5;length=metres*native_projection.scale()
	var at:Vector2=Vector2(35,size.y-30);draw_line(at,at+Vector2(length,0),Color("eaf7eb"),2,true);draw_line(at-Vector2(0,5),at+Vector2(0,5),Color("eaf7eb"),2,true);draw_line(at+Vector2(length,-5),at+Vector2(length,5),Color("eaf7eb"),2,true)
	draw_string(ThemeDB.fallback_font,at+Vector2(0,-10),"%d m"%int(metres),HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("edf7ec"))
	for index in range(3):_cloud(Vector2(fmod(index*383.0+clock*5,size.x+170)-85,size.y*(.12+float(index%2)*.61)),.65+index*.11)

func _rock(at:Vector2,radius:float)->void:
	var texture:Texture2D=FacilityArt.artwork("rock_cluster",environment_artwork_directory)
	if texture!=null:draw_texture_rect(texture,Rect2(at-Vector2(radius*1.6,radius*1.8),Vector2(radius*3.2,radius*3.2)),false);return
	draw_colored_polygon(PackedVector2Array([at+Vector2(-radius,radius*.25),at+Vector2(-radius*.6,-radius*.65),at+Vector2(radius*.4,-radius),at+Vector2(radius,radius*.3),at+Vector2(radius*.1,radius*.65)]),Color("7b9581"))
	draw_colored_polygon(PackedVector2Array([at+Vector2(-radius*.6,-radius*.65),at+Vector2(radius*.4,-radius),at+Vector2(radius*.6,-radius*.1),at+Vector2(-radius*.1,radius*.05)]),Color("b1b79a"))

func _decor(kind:String,at:Vector2,width:float,opacity:float=1.0)->void:
	var texture:Texture2D=FacilityArt.artwork(kind,environment_artwork_directory)
	if texture==null:return
	var dimensions:Vector2=Vector2(width,width*texture.get_height()/maxf(1,texture.get_width()))
	draw_texture_rect(texture,Rect2(at-dimensions*facility_artwork_anchor,dimensions),false,Color(1,1,1,opacity))

func _cloud(at:Vector2,scale:float)->void:
	var raw:Array[Vector2]=[Vector2(-66,15),Vector2(-65,-4),Vector2(-43,-14),Vector2(-30,-32),Vector2(-5,-35),Vector2(13,-23),Vector2(36,-29),Vector2(54,-13),Vector2(56,-2),Vector2(72,5),Vector2(66,21),Vector2(0,23)]
	var polygon:PackedVector2Array=[];var shadow:PackedVector2Array=[]
	for index in range(raw.size()):
		var a:Vector2=raw[(index+raw.size()-1)%raw.size()];var b:Vector2=raw[index];var c:Vector2=raw[(index+1)%raw.size()];var d:Vector2=raw[(index+2)%raw.size()]
		for step in range(6):
			var t:float=step/6.0;var p:Vector2=.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)*scale+at
			polygon.append(p);shadow.append(p+Vector2(7,14))
	draw_colored_polygon(shadow,Color(.1,.35,.38,.06));draw_colored_polygon(polygon,Color(.96,.98,.92,.64))

func _tree(at:Vector2,radius:float)->void:
	var texture:Texture2D=FacilityArt.artwork("tree_cluster",environment_artwork_directory)
	if texture!=null:draw_texture_rect(texture,Rect2(at-Vector2(radius*1.5,radius*2.8),Vector2(radius*3,radius*3)),false);return
	draw_line(at+Vector2(0,13),at+Vector2(0,-3),Color("667968"),3)
	draw_circle(at+Vector2(-radius*.4,0),radius,Color("528665"));draw_circle(at+Vector2(radius*.4,-radius*.3),radius*.9,Color("69a16c"));draw_circle(at+Vector2(0,-radius*.5),radius*.85,Color("82b67b"))

func _building(at:Vector2,width:float,kind:String,level:int,health:int)->void:
	var body:Color=Color("eef0da") if health>0 else Color("83918c")
	var roof:Color=Color("467d8d") if kind not in ["medical","forge"] else Color("c98d6c")
	draw_ellipse_shadow(at,width)
	if kind=="solar":
		for panel in range(2):
			var tile:Rect2=Rect2(at+Vector2((panel-.9)*width*.52,-width*.32),Vector2(width*.47,width*.5))
			draw_rect(tile,Color("3c758e"));draw_rect(tile.grow(-2),Color("75bec2"),false,1)
	elif kind in ["turret","aa"]:
		draw_circle(at,width*.36,body);draw_circle(at+Vector2(0,-width*.13),width*.23,roof)
		draw_line(at+Vector2(0,-width*.13),at+Vector2(width*.45,-width*.4),roof,5 if kind=="turret" else 3,true)
		if kind=="aa":draw_line(at+Vector2(-5,-width*.13),at+Vector2(width*.3,-width*.5),roof,3,true)
	elif kind=="dock":
		for beam in range(4):draw_rect(Rect2(at+Vector2((beam-2)*width*.24,-width*.22),Vector2(width*.2,width*.65)),Color("a99070"))
		draw_line(at+Vector2(-width*.5,0),at+Vector2(width*.4,0),Color("e0d7b8"),4)
	else:
		draw_rect(Rect2(at+Vector2(-width*.4,-width*.18),Vector2(width*.8,width*.48)),body)
		var polygon:PackedVector2Array=PackedVector2Array([at+Vector2(-width*.5,-width*.15),at+Vector2(0,-width*.52),at+Vector2(width*.5,-width*.15)])
		draw_colored_polygon(polygon,roof)
		draw_rect(Rect2(at+Vector2(-width*.09,0),Vector2(width*.18,width*.28)),Color("41666c"))
		if kind=="medical":
			draw_line(at+Vector2(-width*.2,-width*.24),at+Vector2(width*.2,-width*.24),Color("fff5db"),4)
			draw_line(at+Vector2(0,-width*.43),at+Vector2(0,-width*.05),Color("fff5db"),4)
		if kind=="forge":draw_rect(Rect2(at+Vector2(width*.22,-width*.55),Vector2(width*.13,width*.4)),Color("806e64"))
		if kind in ["hq","recycler"]:
			draw_line(at+Vector2(width*.18,-width*.3),at+Vector2(width*.18,-width*.85),Color("506e73"),2)
			draw_line(at+Vector2(width*.18,-width*.8),at+Vector2(width*.5,-width*.68),Color("fff3b7"),4)
	for dot in range(level):draw_circle(at+Vector2((dot-float(level-1)*.5)*7,width*.42),2.1,Color("fff0a9"))
	if health<100:
		draw_line(at+Vector2(-width*.35,width*.55),at+Vector2(width*.35,width*.55),Color(.1,.25,.25,.4),3)
		draw_line(at+Vector2(-width*.35,width*.55),at+Vector2(-width*.35+width*.7*float(health)/100,width*.55),Color("dfb57d"),3)

func draw_ellipse_shadow(at:Vector2,width:float)->void:
	var polygon:PackedVector2Array=[]
	for index in range(20):polygon.append(at+Vector2(cos(index*TAU/20)*width*.65,sin(index*TAU/20)*width*.22+8))
	draw_colored_polygon(polygon,Color(.12,.31,.25,.17))

func _observe_world3d()->void:
	if not is_instance_valid(world3d):
		world3d=load("res://scripts/world3d/world3d_view.gd").new()
		world3d.name="SharedHomeWorld3D";world3d.show_behind_parent=true
		add_child(world3d);move_child(world3d,0)
		world3d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		world3d.camera_changed.connect(queue_redraw)
		world3d_center=_world3d_bounds().get_center()
	world3d.observe(native_projection.land,false);_sync_world3d_camera()
	if is_instance_valid(water):water.hide()
	if is_instance_valid(terrain_backdrop):terrain_backdrop.hide()

func _world3d_bounds()->Rect2:
	var bounds:Dictionary=native_projection.land.get("bounds",{})
	return Rect2(float(bounds.get("x",0)),float(bounds.get("y",0)),maxf(1,float(bounds.get("width",native_geometry.get("width_m",1)))),maxf(1,float(bounds.get("height",native_geometry.get("height_m",1)))))

func _sync_world3d_camera()->void:
	if not is_instance_valid(world3d):return
	world3d.set_camera(world3d_center,zoom)

func _world3d_scale()->float:
	return maxf(.00001,world3d.project(world3d_center+Vector2.RIGHT).distance_to(world3d.project(world3d_center)))

func _world3d_zoom_for_span(metres:float)->float:
	var extent:Vector2=world3d.surface.frame.size
	return clampf(maxf(extent.x,extent.y)/maxf(1.0,metres),minimum_zoom,160.0)

func _world3d_tile(cell:Vector2i)->PackedVector2Array:
	var center:Vector2=native_projection.world(Vector2(cell))
	var half:float=float(native_projection.grid.get("cell_size_m",120))*.48
	var corners:PackedVector2Array=[]
	for offset in [Vector2(-half,-half),Vector2(half,-half),Vector2(half,half),Vector2(-half,half)]:corners.append(world3d.project(center+offset))
	corners.append(corners[0]);return corners

func _draw_world3d_overlay()->void:
	if draw_construction_grid:
		for cell in grid_cells():
			var polygon:PackedVector2Array=_world3d_tile(cell)
			if not Rect2(Vector2.ZERO,size).intersects(Rect2(polygon[0],Vector2.ONE).expand(polygon[2])):continue
			draw_polyline(polygon,Color(.95,1,.9,.2),1,true)
	if selected.x>=0:draw_polyline(_world3d_tile(selected),Color("f8d58b"),2,true)
	if not placement_kind.is_empty() and placement_cell.x>=0:
		var color:Color=Color("9ce3bb") if placement_valid else Color("ee947c")
		var polygon:PackedVector2Array=_world3d_tile(placement_cell)
		draw_colored_polygon(polygon,Color(color,.18));draw_polyline(polygon,color,2,true)
	var metres:float=20.0;var pixels:float=_world3d_scale()*metres
	while pixels<48:metres*=5;pixels=_world3d_scale()*metres
	if pixels<size.x*.35:
		var at:=Vector2(24,size.y-28)
		draw_line(at,at+Vector2(pixels,0),Color("f3edcf"),2,true)
		draw_string(ThemeDB.fallback_font,at-Vector2(0,8),"%d m"%int(metres),HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("f3edcf"))
