extends RefCounted
## Read-only display of the published native geography. No collision/AI authority.
## The old v4 step model is partitioned exactly, rather than smoothed into false ramps.
const NativeProjection = preload("res://scripts/home_projection_v4.gd")
const Grid = preload("res://scripts/world3d/geography_grid.gd")
const BaseArchitecture = preload("res://scripts/world3d/coastal_architecture.gd")
const HomeArchitecture = preload("res://scripts/world3d/home_architecture.gd")
const WastelandArchitecture = preload("res://scripts/world3d/wasteland_architecture.gd")
var land: Dictionary = {}
var projection = NativeProjection.new()
var native_grid=Grid.new()
var has_grid:bool=false
var origin: Vector2
var polygon: PackedVector2Array
var frame: Rect2
var levels: Array[float] = [0.0]
var root: Node3D
var details: Node3D
var water_material: ShaderMaterial
var facilities: Dictionary = {}
var _materials: Dictionary = {}
var _pieces: Array[Dictionary] = []
var _shore_depth: Texture2D
var _water:MeshInstance3D
var _water_frame:Rect2
var _low: bool = false
var _tree_meshes:Array[Dictionary]=[]
var _prop_meshes:Array[Dictionary]=[]
var _grass_mesh:Mesh
var _grass_material:ShaderMaterial
var _forest_shapes:Array[PackedVector2Array]=[]
var _forest_chunks:Dictionary={}
var _color_noise:=FastNoiseLite.new()
var _color_micro:=FastNoiseLite.new()
static var grain:ImageTexture

func bind(value: Dictionary, low_detail: bool = false) -> void:
	land = value
	_low = low_detail
	projection.bind({"land": land})
	has_grid=native_grid.bind(land.get("geography",{}))
	_color_noise.seed=int(land.get("geography",{}).get("seed",714));_color_noise.frequency=.009;_color_noise.fractal_octaves=4
	_color_micro.seed=_color_noise.seed+71;_color_micro.frequency=.026;_color_micro.fractal_octaves=3
	polygon = points(land.get("polygon", []))
	if polygon.size() < 3: return
	frame = Rect2(polygon[0], Vector2.ZERO)
	for point: Vector2 in polygon: frame = frame.expand(point)
	origin = frame.get_center()
	levels = [0.0]
	for zone: Dictionary in land.get("terrain", {}).get("elevation_zones", []):
		var elevation: float = float(zone.get("height_m", 0))
		if not levels.has(elevation): levels.append(elevation)
	levels.sort()
	if has_grid:
		levels=[native_grid.height_bounds.x,native_grid.height_bounds.y]

static func points(raw: Variant) -> PackedVector2Array:
	if raw is PackedVector2Array: return raw
	var result: PackedVector2Array = []
	if raw is Array:
		for point: Variant in raw:
			if point is Vector2: result.append(point)
			elif point is Dictionary: result.append(Vector2(float(point.get("x", 0)), float(point.get("y", 0))))
	return result

func height_at(point: Vector2) -> float:
	if has_grid:return native_grid.height_at(point)
	return projection.height(point)

func surface_at(point:Vector2)->float:
	return native_grid.surface_at(point) if has_grid else height_at(point)

func world(point: Vector2, lift: float = 0.0) -> Vector3:
	return Vector3(point.x-origin.x, surface_at(point)+lift, point.y-origin.y)

func build(parent: Node3D) -> Node3D:
	root = Node3D.new()
	root.name = "AuthorityGeography"
	parent.add_child(root)
	if polygon.size() < 3: return root
	root.set_meta("authority", "published native land; display only")
	root.set_meta("units", "metres")
	root.set_meta("core_origin", origin)
	_build_ground()
	_build_water()
	if has_grid:_build_inland_water()
	_build_features()
	details = Node3D.new(); details.name = "NearDetails"; root.add_child(details)
	_build_architecture()
	_build_forest()
	return root

func _surface_material(color: Color, stone: bool = false) -> ShaderMaterial:
	var key: String = color.to_html()+str(stone)
	if not _materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = preload("res://assets/world3d/shaders/surface.gdshader")
		material.set_shader_parameter("ground_tint", color)
		material.set_shader_parameter("rock", 1.0 if stone else 0.0)
		if grain==null:
			var noise:=FastNoiseLite.new();noise.seed=41;noise.frequency=.018;noise.fractal_octaves=5
			var grain_image:Image=noise.get_image(512,512);grain_image.generate_mipmaps()
			grain=ImageTexture.create_from_image(grain_image)
		material.set_shader_parameter("grain",grain)
		_materials[key] = material
	return _materials[key]

func _mesh_node(label: String, vertices: PackedVector3Array, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var node := MeshInstance3D.new(); node.name = label
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var raw_tint:Variant=material.get_shader_parameter("ground_tint") if material is ShaderMaterial else Color.WHITE
	var tint:Color=raw_tint if raw_tint is Color else Color.WHITE
	for vertex: Vector3 in vertices:
		surface.set_color(tint);surface.add_vertex(vertex)
	surface.generate_normals(); node.mesh = surface.commit(); node.material_override = material
	(parent if parent != null else root).add_child(node)
	return node

func _triangles(shape: PackedVector2Array, elevation: float, lift: float = 0.0) -> PackedVector3Array:
	if has_grid:return _grid_triangles(shape,lift)
	var vertices: PackedVector3Array = []
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(shape)
	if str(land.get("terrain",{}).get("height_model",""))=="inset_edge_blend_v1":
		var pending:Array[PackedVector2Array]=[]
		for offset:int in range(0,indices.size(),3):pending.append(PackedVector2Array([shape[indices[offset]],shape[indices[offset+1]],shape[indices[offset+2]]]))
		var edge_m:float=64.0 if _low else 32.0
		while not pending.is_empty():
			var triangle:PackedVector2Array=pending.pop_back();var longest:float=0.0;var edge:int=0
			for i:int in range(3):
				var length:float=triangle[i].distance_squared_to(triangle[(i+1)%3])
				if length>longest:longest=length;edge=i
			if longest>edge_m*edge_m:
				var a:int=edge;var b:int=(edge+1)%3;var c:int=(edge+2)%3;var middle:Vector2=(triangle[a]+triangle[b])*.5
				pending.append(PackedVector2Array([triangle[a],middle,triangle[c]]));pending.append(PackedVector2Array([middle,triangle[b],triangle[c]]));continue
			for corner:int in [0,1,2]:vertices.append(world(triangle[corner],lift))
		return vertices
	for offset: int in range(0, indices.size(), 3):
		for corner: int in [0, 1, 2]:
			var point: Vector2 = shape[indices[offset+corner]]
			vertices.append(Vector3(point.x-origin.x, elevation+lift, point.y-origin.y))
	return vertices

func _grid_triangles(shape:PackedVector2Array,lift:float)->PackedVector3Array:
	var result:=PackedVector3Array()
	if shape.size()<3:return result
	# Geometry2D's triangulator uses float polygon areas. Small 4-m triangles
	# around 14-km coordinates lose area to cancellation; clip in island-local
	# space, then restore the untouched native command coordinates for sampling.
	var local_shape:=PackedVector2Array()
	for point:Vector2 in shape:local_shape.append(point-origin)
	var bounds:=Rect2(shape[0],Vector2.ZERO)
	for point:Vector2 in shape:bounds=bounds.expand(point)
	var lo:Vector2=(bounds.position-native_grid.origin)/native_grid.cell_size
	var hi:Vector2=(bounds.end-native_grid.origin)/native_grid.cell_size
	for row:int in range(clampi(floori(lo.y),0,native_grid.rows-2),clampi(ceili(hi.y),0,native_grid.rows-2)+1):
		for col:int in range(clampi(floori(lo.x),0,native_grid.columns-2),clampi(ceili(hi.x),0,native_grid.columns-2)+1):
			var a:Vector2=native_grid.origin-origin+Vector2(col,row)*native_grid.cell_size
			var b:Vector2=a+Vector2(native_grid.cell_size,0);var c:Vector2=a+Vector2(0,native_grid.cell_size);var d:Vector2=a+Vector2.ONE*native_grid.cell_size
			for triangle:PackedVector2Array in [PackedVector2Array([a,b,c]),PackedVector2Array([b,d,c])]:
				for clipped:PackedVector2Array in Geometry2D.intersect_polygons(local_shape,triangle):
					var indices:PackedInt32Array=Geometry2D.triangulate_polygon(clipped)
					for index:int in indices:result.append(world(clipped[index]+origin,lift))
	return result

func _build_ground() -> void:
	if has_grid:
		_build_grid_ground();return
	_pieces = [{"shape": polygon, "height": 0.0}]
	var zones: Array = land.get("terrain", {}).get("elevation_zones", []).duplicate()
	var blended:bool=str(land.get("terrain",{}).get("height_model",""))=="inset_edge_blend_v1"
	if blended:zones=[]
	zones.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("level", 0)) < int(b.get("level", 0)))
	var by_height:Dictionary={}
	for zone:Dictionary in zones:
		var shape:PackedVector2Array=points(zone.get("polygon",[]));var h:float=float(zone.get("height_m",0))
		if shape.size()<3 or h<=0:continue
		if not by_height.has(h):by_height[h]=[]
		for clipped:PackedVector2Array in Geometry2D.intersect_polygons(shape,polygon):
			var merged:bool=false
			for index:int in range(by_height[h].size()):
				var union:Array[PackedVector2Array]=Geometry2D.merge_polygons(by_height[h][index],clipped)
				if union.size()==1:by_height[h][index]=union[0];merged=true;break
			if not merged:by_height[h].append(clipped)
	for h:float in by_height:
		for shape:PackedVector2Array in by_height[h]:_pieces.append({"shape":shape,"height":h})
	var ground: PackedVector3Array = []
	var walls: PackedVector3Array = []
	for piece: Dictionary in _pieces:
		var shape: PackedVector2Array = piece.shape
		ground.append_array(_triangles(shape, float(piece.height)))
		for index: int in range(shape.size()):
			if blended:break
			var a: Vector2 = shape[index]; var b: Vector2 = shape[(index+1)%shape.size()]
			var outward: Vector2 = (b-a).orthogonal().normalized()
			var outside_height: float = minf(height_at((a+b)*.5+outward*.03),height_at((a+b)*.5-outward*.03))
			if outside_height >= float(piece.height)-.01: continue
			var bottom: float = maxf(0.0, outside_height)
			var high_a := Vector3(a.x-origin.x, float(piece.height), a.y-origin.y)
			var high_b := Vector3(b.x-origin.x, float(piece.height), b.y-origin.y)
			walls.append_array(PackedVector3Array([high_a, high_b, Vector3(high_a.x,bottom,high_a.z), high_b,Vector3(high_b.x,bottom,high_b.z),Vector3(high_a.x,bottom,high_a.z)]))
	if not ground.is_empty():
		var ground_node:MeshInstance3D=_mesh_node("NativeGround",ground,_surface_material(Color("8eb759")))
		ground_node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not walls.is_empty(): _mesh_node("NativeCliffFaces", walls, _surface_material(Color("c4b593"), true))
	# Sand is drawn only from native beach/landing polygons below. An all-round
	# decorative beach would falsely suggest every coast is a legal unloading site.

func _build_grid_ground()->void:
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var colors:=PackedColorArray();var indices:=PackedInt32Array()
	var count:int=native_grid.columns*native_grid.rows
	vertices.resize(count);normals.resize(count);colors.resize(count)
	for row:int in range(native_grid.rows):
		for col:int in range(native_grid.columns):
			var index:int=row*native_grid.columns+col
			var point:Vector2=native_grid.origin+Vector2(col,row)*native_grid.cell_size
			vertices[index]=Vector3(point.x-origin.x,native_grid.heights[index],point.y-origin.y)
			normals[index]=native_grid.normal_at(col,row)
			colors[index]=_biome_color(native_grid.biome_at(col,row),native_grid.heights[index],normals[index],point)
	for row:int in range(native_grid.rows-1):
		for col:int in range(native_grid.columns-1):
			var a:int=row*native_grid.columns+col;var b:int=a+1;var c:int=a+native_grid.columns;var d:int=c+1
			indices.append_array(PackedInt32Array([a,b,c,b,d,c]))
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node:=MeshInstance3D.new();node.name="NativeContinuousGround";node.mesh=mesh;node.material_override=_surface_material(Color.WHITE);root.add_child(node)
	# Features/roads follow the same authoritative triangles, not a second sampler.
	_pieces=[{"shape":polygon,"height":0.0}]

func _biome_color(biome:String,height:float,normal:Vector3,point:Vector2)->Color:
	var local:Vector2=point-(native_grid.origin+Vector2(native_grid.columns-1,native_grid.rows-1)*native_grid.cell_size*.5)
	var hue:float=_color_noise.get_noise_2d(local.x+600,local.y+50)*.5+.5
	if height<0.0:return Color("8ab7a4").lerp(Color("d2c89c"),clampf((height+10.0)/10.0,0,1))
	var sand:Color=Color("ead9a5").lerp(Color("dac18f"),hue*.4)
	match biome:
		"beach","sand","landing_zone":return sand
		"swamp","marsh","river":return Color("7e9860").lerp(Color("746b4c"),1.0-smoothstep(1.15,2.5,height)).lerp(Color("9b9868"),hue*.2)
		"cliff","sea_cliff","rock":return Color("a08c70").lerp(Color("c0af8a"),hue*.65)
	var grass:Color=Color("78a54a").lerp(Color("9ab65b"),hue)
	grass=grass.lerp(Color("b3b47b"),smoothstep(.15,.6,_color_micro.get_noise_2d(local.x,local.y))*.35)
	var slope:float=Vector2(normal.x,normal.z).length()/maxf(.001,normal.y)
	var amount:float=smoothstep(.40,.82,slope)*smoothstep(5,15,height)
	return grass.lerp(Color("a79e7a").lerp(Color("c4b58f"),hue),amount)

func _build_water() -> void:
	water_material = ShaderMaterial.new(); water_material.shader = preload("res://assets/world3d/shaders/ocean.gdshader")
	water_material.set_shader_parameter("grain",grain)
	var mesh := PlaneMesh.new(); mesh.size = Vector2.ONE;mesh.subdivide_width = 96 if _low else 160;mesh.subdivide_depth = mesh.subdivide_width
	_water = MeshInstance3D.new();_water.name="ProceduralOcean";_water.mesh=mesh;_water.material_override=water_material;_water.position.y=-.16;_water.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(_water)
	_update_water(origin,maxf(frame.size.x,frame.size.y))

func _update_water(focus:Vector2,span:float)->void:
	if not is_instance_valid(_water):return
	# One bounded moving grid supplies the visible ocean. Detail is tied to the
	# camera footprint, never to a 10-km island's full extent at every zoom level.
	var extent:float=ceilf(maxf(512.0,span*3.5)/256.0)*256.0
	var quantum:float=maxf(64.0,extent*.125)
	var snapped:Vector2=(focus/quantum).floor()*quantum
	var depth_frame:=Rect2(snapped-Vector2.ONE*extent*.5,Vector2.ONE*extent)
	if depth_frame==_water_frame:return
	_water_frame=depth_frame
	(_water.mesh as PlaneMesh).size=depth_frame.size
	_water.position=Vector3(snapped.x-origin.x,-.16,snapped.y-origin.y)
	var resolution: int = 128 if _low else 256
	var image := Image.create(resolution,resolution,false,Image.FORMAT_RF)
	for y: int in range(resolution):
		for x: int in range(resolution):
			var point: Vector2 = depth_frame.position+Vector2(float(x)/(resolution-1),float(y)/(resolution-1))*depth_frame.size
			var distance: float = 0.0
			if has_grid:distance=maxf(0.0,native_grid.water_at(point)-height_at(point))/.18
			elif not Geometry2D.is_point_in_polygon(point,polygon):
				distance = INF
				for index: int in range(polygon.size()): distance = minf(distance,point.distance_to(Geometry2D.get_closest_point_to_segment(point,polygon[index],polygon[(index+1)%polygon.size()])))
			image.set_pixel(x,y,Color(clampf(distance*.18/80.0,0,1),0,0))
	_shore_depth = ImageTexture.create_from_image(image)
	water_material.set_shader_parameter("shore_depth",_shore_depth)
	water_material.set_shader_parameter("map_min",depth_frame.position-origin)
	water_material.set_shader_parameter("map_size",depth_frame.size)

func _build_inland_water()->void:
	if native_grid.water.size()!=native_grid.heights.size():return
	var vertices:=PackedVector3Array()
	for row:int in range(native_grid.rows-1):
		for col:int in range(native_grid.columns-1):
			var a:int=row*native_grid.columns+col;var b:int=a+1;var c:int=a+native_grid.columns;var d:int=c+1
			for indices:PackedInt32Array in [PackedInt32Array([a,b,c]),PackedInt32Array([b,d,c])]:
				var shape:Array[Vector3]=[];var depth:Array[float]=[]
				for index:int in indices:
					var point:Vector2=native_grid.origin+Vector2(index%native_grid.columns,floori(float(index)/native_grid.columns))*native_grid.cell_size-origin
					shape.append(Vector3(point.x,native_grid.water[index]+.025,point.y));depth.append(native_grid.water[index]-native_grid.heights[index]-.03)
				var clipped:Array[Vector3]=[]
				for index:int in range(3):
					var prior:int=(index+2)%3
					if (depth[index]>0)!=(depth[prior]>0):clipped.append(shape[prior].lerp(shape[index],depth[prior]/(depth[prior]-depth[index])))
					if depth[index]>0 and shape[index].y>0:clipped.append(shape[index])
				for i:int in range(1,clipped.size()-1):vertices.append_array(PackedVector3Array([clipped[0],clipped[i],clipped[i+1]]))
	if vertices.is_empty():return
	var material:=ShaderMaterial.new();material.shader=preload("res://assets/world3d/shaders/inland_water.gdshader");material.set_shader_parameter("grain",grain)
	var node:MeshInstance3D=_mesh_node("NativeInlandWater",vertices,material);node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _paint_polygons(shapes: Array, color: Color, lift: float, label: String) -> void:
	var mesh: PackedVector3Array = []
	for shape: PackedVector2Array in shapes:
		for piece: Dictionary in _pieces:
			for overlap: PackedVector2Array in Geometry2D.intersect_polygons(shape,piece.shape): mesh.append_array(_triangles(overlap,float(piece.height),lift))
	if not mesh.is_empty(): _mesh_node(label,mesh,_surface_material(color))

func _build_features() -> void:
	for feature: Dictionary in land.get("terrain",{}).get("features",[]):
		if has_grid:continue # Native per-vertex biomes already supply this coverage.
		var kind: String=str(feature.get("kind","")); var shape: PackedVector2Array=points(feature.get("polygon",[]))
		if shape.size()<3: continue
		var tint: Color = Color("8eb759")
		match kind:
			"beach","landing_zone": tint=Color("e7d2a0")
			"forest","bush": tint=Color("6b9b4b")
			"swamp": tint=Color("788f6b")
			"river": tint=Color("4eaaa8")
			"road","ford": tint=Color("ac9f7d")
			"cliff": tint=Color("b2aa8b")
			"highland","lowland","ramp": continue
			_: continue
		_paint_polygons([shape],tint,.025,"NativeFeature_"+str(feature.get("id",kind)))
	var roads: Array=land.get("terrain",{}).get("roads",[]).duplicate()
	roads.append_array(land.get("town",{}).get("roads",[]))
	var road_vertices:=PackedVector3Array();var marking_vertices:=PackedVector3Array()
	for road: Dictionary in roads:
		var path: PackedVector2Array=points(road.get("points",[])); var width: float=float(road.get("width",20))
		var along:float=0.0;var next_dash:float=3.0
		for index: int in range(path.size()-1):
			var normal: Vector2=(path[index+1]-path[index]).orthogonal().normalized()*width*.5
			var shape:=PackedVector2Array([path[index]-normal,path[index+1]-normal,path[index+1]+normal,path[index]+normal])
			for part:PackedVector2Array in Geometry2D.intersect_polygons(shape,polygon):
				for piece:Dictionary in _pieces:
					for clipped:PackedVector2Array in Geometry2D.intersect_polygons(part,piece.shape):road_vertices.append_array(_triangles(clipped,float(piece.height),.14))
			var length:float=path[index].distance_to(path[index+1]);var direction:Vector2=(path[index+1]-path[index]).normalized()
			while next_dash<=along+length and width>=5.5:
				var at:Vector2=path[index]+direction*(next_dash-along)
				marking_vertices.append_array(_road_mark(at-direction*.85,at+direction*.85,.13,.20))
				next_dash+=7.0
			along+=length
	if not road_vertices.is_empty():
		var node:MeshInstance3D=_mesh_node("NativeRoads",road_vertices,_surface_material(Color("6f7d7c")))
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not marking_vertices.is_empty():
		var node:MeshInstance3D=_mesh_node("RoadMarkings",marking_vertices,_surface_material(Color("ded4a0")))
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _road_mark(a:Vector2,b:Vector2,width:float,lift:float)->PackedVector3Array:
	var normal:Vector2=(b-a).orthogonal().normalized()*width*.5
	var shape:=PackedVector2Array([a-normal,b-normal,b+normal,a+normal]);var result:=PackedVector3Array()
	for piece:Dictionary in _pieces:
		for clipped:PackedVector2Array in Geometry2D.intersect_polygons(shape,piece.shape):result.append_array(_triangles(clipped,float(piece.height),lift))
	return result

func _build_architecture() -> void:
	var architecture = BaseArchitecture.new();details.add_child(architecture);architecture._height_at=func(x:float,z:float)->float:return height_at(Vector2(x,z)+origin)
	var home = HomeArchitecture.new();details.add_child(home);home._height_at=architecture._height_at
	var wasteland=WastelandArchitecture.new();details.add_child(wasteland);wasteland._height_at=architecture._height_at
	var town_rows: Array=land.get("town",{}).get("buildings",[])
	for index: int in range(town_rows.size()):
		var row: Dictionary=town_rows[index]; var p:=Vector2(float(row.get("x",0)),float(row.get("y",0)))-origin
		var node: Node3D=architecture.spawn_house(architecture,p,index%3)
		var footprint: PackedVector2Array=points(row.get("footprint",[]))
		if footprint.size()>=4:
			var size_x:float=footprint[0].distance_to(footprint[1]);var size_z:float=footprint[1].distance_to(footprint[2]);node.scale=Vector3(size_x/12.2,1,size_z/9.0)
		facilities["town:"+str(row.get("id",index))]=node
	for index: int in range(land.get("buildings",[]).size()):
		var row: Dictionary=land.buildings[index];var p:=Vector2(float(row.get("x",0)),float(row.get("y",0)))-origin
		var kind:String=str(row.get("kind","warehouse"));var mapped:String=str({"hq":"command","headquarters":"command","sawmill":"recycler","alloy":"workshop","forge":"workshop","solar":"power","depot":"warehouse","refinery":"power","oil":"power","battery":"coastal_gun","aa":"air_defense","radar":"research","hospital":"medical","turret":"coastal_gun","repair_tower":"medical"}.get(kind,kind))
		var node:Node3D
		match kind:
			"machine_gun":wasteland._machine_gun_bunker(p);node=wasteland.buildings[-1]
			"mortar":wasteland._mortar_position(p);node=wasteland.buildings[-1]
			"anti_ship":wasteland._armored_coastal_gun(p);node=wasteland.buildings[-1]
			"dock":node=architecture.spawn_harbor_office(architecture,p)
			_:node=home.spawn_facility(mapped,p)
		node.name="Facility_"+str(row.get("id",index));node.set_meta("native_id",row.get("id",index));node.set_meta("native_kind",kind);node.set_meta("art_family",mapped);facilities["building:"+str(row.get("id",index))]=node

func _build_forest() -> void:
	_forest_shapes.clear();_tree_meshes.clear();_prop_meshes.clear();_forest_chunks.clear()
	for feature:Dictionary in land.get("terrain",{}).get("features",[]):
		if str(feature.get("kind","")) in ["forest","bush"]:_forest_shapes.append(points(feature.get("polygon",[])))
	for variant:int in [1,3,5]:
		var scene:PackedScene=load("res://assets/world3d/nature/CommonTree_%d.glb"%variant) as PackedScene
		var temp:Node=scene.instantiate();var parts:Array[Dictionary]=[];_collect_tree_meshes(temp,Transform3D.IDENTITY,parts)
		var bounds:=AABB();var first:bool=true
		for part:Dictionary in parts:
			var transformed:AABB=(part.transform as Transform3D)*(part.mesh as Mesh).get_aabb()
			bounds=transformed if first else bounds.merge(transformed);first=false
		_tree_meshes.append({"parts":parts,"bounds":bounds});temp.free()
	for model:String in ["Bush_1","Bush_2","Rock_1","Rock_2","Rock_3"]:
		var source:PackedScene=load("res://assets/world3d/nature/"+model+".glb") as PackedScene
		if source==null:continue
		var instance:Node=source.instantiate();var parts:Array[Dictionary]=[];_collect_tree_meshes(instance,Transform3D.IDENTITY,parts)
		var bounds:=AABB();var first:bool=true
		for part:Dictionary in parts:
			var box:AABB=(part.transform as Transform3D)*(part.mesh as Mesh).get_aabb();bounds=box if first else bounds.merge(box);first=false
		_prop_meshes.append({"parts":parts,"bounds":bounds,"bush":model.begins_with("Bush")});instance.free()
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade:int in range(5):
		var x:float=(blade-2)*.14;var high:float=.30+(blade%3)*.13
		for p:Vector3 in [Vector3(x-.08,0,0),Vector3(x+.08,0,0),Vector3(x+.06,high,.03)]:
			st.set_color(Color("9cb365") if blade%2==0 else Color("748f42"));st.set_normal(Vector3.UP);st.add_vertex(p)
	_grass_mesh=st.commit();_grass_material=ShaderMaterial.new();_grass_material.shader=preload("res://assets/world3d/shaders/grass.gdshader")

func _forest_chunk(chunk:Vector2i)->Node3D:
	var result:=Node3D.new();result.name="CanopyChunk_%d_%d"%[chunk.x,chunk.y];details.add_child(result)
	var rng:=RandomNumberGenerator.new();rng.seed=int(land.get("seed",714))+9281+chunk.x*7187+chunk.y*16927
	var groups:Array=[[],[],[]]
	# Only loaded near-camera chunks are populated. The seed depends on absolute
	# chunk coordinates, so panning/LOD never moves trees or changes core terrain.
	for attempt:int in range(150 if _low else 230):
		var point:Vector2=Vector2(chunk)*256+Vector2(rng.randf(),rng.randf())*256
		var valid:bool=false
		if has_grid:
			var cell:Vector2=(point-native_grid.origin)/native_grid.cell_size
			var biome:String=native_grid.biome_at(clampi(roundi(cell.x),0,native_grid.columns-1),clampi(roundi(cell.y),0,native_grid.rows-1))
			valid=biome in ["forest","woodland","bush"] or (biome=="grassland" and rng.randf()<.22)
		for shape:PackedVector2Array in _forest_shapes:
			if Geometry2D.is_point_in_polygon(point,shape):valid=true;break
		if not valid or not Geometry2D.is_point_in_polygon(point,polygon):continue
		var steep:bool=false
		for offset:Vector2 in [Vector2(5,0),Vector2(-5,0),Vector2(0,5),Vector2(0,-5)]:
			if absf(height_at(point+offset)-height_at(point))>3.0:steep=true;break
		if steep:continue
		for obstacle:Dictionary in land.get("terrain",{}).get("features",[]):
			if str(obstacle.get("kind","")) in ["cliff","river","road","ford","landing_zone"] and Geometry2D.is_point_in_polygon(point,points(obstacle.get("polygon",[]))):steep=true;break
		if steep:continue
		for road:Dictionary in land.get("terrain",{}).get("roads",[]):
			var road_points:PackedVector2Array=points(road.get("points",[]))
			for segment:int in range(road_points.size()-1):
				if point.distance_to(Geometry2D.get_closest_point_to_segment(point,road_points[segment],road_points[segment+1]))<float(road.get("width",24))*.5+6.0:steep=true;break
		if steep:continue
		for facility:Node3D in facilities.values():
			if Vector2(facility.position.x,facility.position.z).distance_to(point-origin)<30:steep=true;break
		if steep:continue
		var species:int=rng.randi_range(0,maxi(0,_tree_meshes.size()-1))
		var bounds:AABB=_tree_meshes[species].bounds
		var base_scale:float=10.0/maxf(.01,bounds.size.y)
		var basis:=Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*base_scale*rng.randf_range(.8,1.25))
		var anchor:Vector3=world(point)-basis*Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
		groups[species].append(Transform3D(basis,anchor))
	for species:int in range(_tree_meshes.size()):
		if groups[species].is_empty():continue
		for part:Dictionary in _tree_meshes[species].parts:
			var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.mesh=part.mesh;multi.instance_count=groups[species].size()
			for index:int in range(groups[species].size()):multi.set_instance_transform(index,groups[species][index]*part.transform)
			var node:=MultiMeshInstance3D.new();node.name="Canopy_%d"%species;node.multimesh=multi;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _low else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if part.material!=null:node.material_override=part.material
			result.add_child(node)
	if has_grid:_populate_ground_props(chunk,result)
	return result

func _clear_decoration(point:Vector2,radius:float)->bool:
	if not Geometry2D.is_point_in_polygon(point,polygon):return false
	for facility:Node3D in facilities.values():
		if Vector2(facility.position.x,facility.position.z).distance_to(point-origin)<18+radius:return false
	var roads:Array=land.get("terrain",{}).get("roads",[]).duplicate();roads.append_array(land.get("town",{}).get("roads",[]))
	for road:Dictionary in roads:
		var path:PackedVector2Array=points(road.get("points",[]))
		for i:int in range(path.size()-1):
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point,path[i],path[i+1]))<float(road.get("width",6))*.5+radius:return false
	return true

func _populate_ground_props(chunk:Vector2i,parent:Node3D)->void:
	var rng:=RandomNumberGenerator.new();rng.seed=71817+chunk.x*37127+chunk.y*10391
	var groups:Array=[]
	for prop:Dictionary in _prop_meshes:groups.append([])
	var grass:Array[Transform3D]=[]
	for i:int in range(700 if _low else 1800):
		var p:Vector2=Vector2(chunk)*256+Vector2(rng.randf(),rng.randf())*256
		if not native_grid.contains(p):continue
		var cell:Vector2=(p-native_grid.origin)/native_grid.cell_size
		var biome:String=native_grid.biome_at(clampi(roundi(cell.x),0,native_grid.columns-1),clampi(roundi(cell.y),0,native_grid.rows-1))
		var h:float=height_at(p)
		if h<.15 or h< native_grid.water_at(p)+.08 or not _clear_decoration(p,1.8):continue
		var slope:float=Vector2(height_at(p+Vector2(2,0))-height_at(p-Vector2(2,0)),height_at(p+Vector2(0,2))-height_at(p-Vector2(0,2))).length()/4.0
		if slope>.65:continue
		var basis:=Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*rng.randf_range(.7,1.8))
		if biome in ["forest","grassland","mountain"]:grass.append(Transform3D(basis,world(p,.02)))
		if i%12!=0 or _prop_meshes.is_empty():continue
		var species:int=rng.randi_range(0,_prop_meshes.size()-1);var prop:Dictionary=_prop_meshes[species]
		if bool(prop.bush) and biome not in ["forest","grassland"]:continue
		var bounds:AABB=prop.bounds;var target:float=1.7 if bool(prop.bush) else 2.1
		var scale:float=target/maxf(.1,bounds.size.y)*rng.randf_range(.8,1.2)
		basis=Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale)
		groups[species].append(Transform3D(basis,world(p,-.03)-basis*Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)))
	for species:int in range(_prop_meshes.size()):
		if groups[species].is_empty():continue
		for part:Dictionary in _prop_meshes[species].parts:_place_detail_batch(parent,part.mesh,groups[species],part.transform,"Undergrowth",part.material)
	if not grass.is_empty():_place_detail_batch(parent,_grass_mesh,grass,Transform3D.IDENTITY,"WindInGrass",_grass_material,false)

func _place_detail_batch(parent:Node3D,mesh:Mesh,transforms:Array,local:Transform3D,label:String,material:Material=null,shadows:bool=true)->void:
	var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.mesh=mesh;multi.instance_count=transforms.size()
	for i:int in range(transforms.size()):multi.set_instance_transform(i,transforms[i]*local)
	var node:=MultiMeshInstance3D.new();node.name=label;node.multimesh=multi;node.material_override=material
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows and not _low else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(node)

func _show_forest(focus:Vector2,span:float)->void:
	if (_forest_shapes.is_empty() and not has_grid) or _tree_meshes.is_empty():return
	var radius:float=minf(650,maxf(200,span*.75))
	var low:=Vector2i(floori((focus.x-radius)/256),floori((focus.y-radius)/256))
	var high:=Vector2i(floori((focus.x+radius)/256),floori((focus.y+radius)/256))
	var active:Dictionary={}
	for y:int in range(low.y,high.y+1):
		for x:int in range(low.x,high.x+1):
			var key:=Vector2i(x,y);active[key]=true
			if not _forest_chunks.has(key):_forest_chunks[key]=_forest_chunk(key)
	for key:Vector2i in _forest_chunks.keys():
		if not active.has(key):_forest_chunks[key].free();_forest_chunks.erase(key)

func _collect_tree_meshes(node:Node, transform:Transform3D, result:Array[Dictionary])->void:
	var local:Transform3D=transform
	if node is Node3D:local=transform*(node as Node3D).transform
	if node is MeshInstance3D:
		var item:MeshInstance3D=node as MeshInstance3D
		if item.mesh!=null:
			var mesh:Mesh=item.mesh.duplicate()
			for index:int in range(mesh.get_surface_count()):
				var original:StandardMaterial3D=mesh.surface_get_material(index) as StandardMaterial3D
				if original==null:continue
				var material:StandardMaterial3D=original.duplicate() as StandardMaterial3D
				if material.albedo_texture==null:
					var palette:Dictionary={"Green":"78a847","DarkGreen":"557d3b","White":"d6d4b5","Black":"4e5949","Wood":"806648","Rock":"a4a68d"}
					if palette.has(original.resource_name):material.albedo_color=Color(str(palette[original.resource_name]))
				material.roughness=.94;mesh.surface_set_material(index,material)
			result.append({"mesh":mesh,"transform":local,"material":item.material_override})
	for child:Node in node.get_children():_collect_tree_meshes(child,local,result)

func set_detail(near:bool,focus:Vector2=Vector2.ZERO,span:float=500)->void:
	if is_instance_valid(details):details.visible=near
	_update_water(focus,span)
	if near:_show_forest(focus,span)

func release()->void:
	if is_instance_valid(root):root.free()
	facilities.clear();_materials.clear();_pieces.clear()

