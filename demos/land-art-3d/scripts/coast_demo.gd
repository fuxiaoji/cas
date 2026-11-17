extends Node3D
## A standalone, editable rendering sample. It does not open an account or core process.

const EXTENT: float = 360.0
const GRID: int = 256
const SCREENSHOTS: String = "res://../../artifacts/land-art-demo-20261115/screenshots/"
var terrain_seed: int = 714
var noise: FastNoiseLite = FastNoiseLite.new()
var micro: FastNoiseLite = FastNoiseLite.new()
var camera: Camera3D
var sun: DirectionalLight3D
var world_environment: WorldEnvironment
var terrain_material: ShaderMaterial
var water_material: ShaderMaterial
var cloud_material: ShaderMaterial
var grain_texture: ImageTexture
var world_root: Node3D
var vegetation: Node3D
var hud: Control
var status: Label
var focus: Vector3 = Vector3(0.0, 3.0, 8.0)
var target_focus: Vector3 = Vector3(0.0, 3.0, 8.0)
var target_size: float = 156.0
var dragging: bool = false
var drag_distance: float = 0.0
var show_hud: bool = true
var weather: int = 0
var elapsed: float = 0.0
var rain: CPUParticles3D
var clouds: Array[Node3D] = []
var touches: Dictionary = {}
var pinch_distance: float = 0.0
var auto_capture: bool = false
var home_capture: bool = false
var selected_view: int = 0
var frame_times: Array[float] = []
var loading_label: Label
var loading_layer: CanvasLayer
var road_layer: int = 0
var nature_mesh_cache: Dictionary = {}
var geography: RefCounted
var terrain_capture: bool = false
var scale_label: Label
var scale_bar: ColorRect
var coarse_view: bool = false

func _ready() -> void:
	set_process(false)
	set_process_unhandled_input(false)
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--capture": auto_capture = true
		if argument == "--capture-home": home_capture = true
		if argument == "--capture-terrain": terrain_capture = true
		if argument == "--review-instance": get_window().title = "CAS · 家园三维样区复核"
		if argument.begins_with("--seed="): terrain_seed = int(argument.trim_prefix("--seed="))
	_setup_noise()
	_setup_environment()
	_show_loading()
	await get_tree().process_frame
	world_root = Node3D.new()
	world_root.name = "ProceduralCoast"
	add_child(world_root)
	_build_terrain()
	loading_label.text = "浅湾 · 正在铺展潮汐"
	await get_tree().process_frame
	_build_water()
	_build_inland_biomes()
	_build_roads()
	_build_architecture()
	_build_home_district()
	_build_wasteland()
	loading_label.text = "浅湾 · 正在唤醒港镇"
	await get_tree().process_frame
	_build_vegetation()
	_build_cast()
	_build_vehicle_showcase()
	_build_clouds()
	_build_hud()
	_set_camera_view(0, true)
	loading_layer.queue_free()
	set_process(true)
	set_process_unhandled_input(true)
	print("ART_DEMO_READY seed=%d triangles=%d draw_calls=%d" % [terrain_seed, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
	if auto_capture: call_deferred("_capture_gallery")
	if home_capture: call_deferred("_capture_home_gallery")
	if terrain_capture: call_deferred("_capture_terrain_gallery")

func _show_loading() -> void:
	loading_layer = CanvasLayer.new()
	loading_layer.layer = 10
	add_child(loading_layer)
	var background := ColorRect.new()
	background.color = Color("123f4b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_layer.add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_child(center)
	loading_label = Label.new()
	if ResourceLoader.exists("res://assets/fonts/NotoSansSC.ttf"):
		loading_label.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"))
	loading_label.text = "浅湾 · 正在生成海岸"
	loading_label.add_theme_font_size_override("font_size",26)
	loading_label.add_theme_color_override("font_color",Color("ebdfb8"))
	center.add_child(loading_label)

func _setup_noise() -> void:
	geography = load("res://scripts/coastal_geography.gd").new(terrain_seed)
	noise.seed = terrain_seed
	noise.frequency = 0.009
	noise.fractal_octaves = 4
	micro.seed = terrain_seed + 71
	micro.frequency = 0.026
	micro.fractal_octaves = 3
	var texture_noise := FastNoiseLite.new()
	texture_noise.seed = 41
	texture_noise.frequency = 0.018
	texture_noise.fractal_octaves = 5
	grain_texture = ImageTexture.create_from_image(texture_noise.get_image(512, 512))

func coast_z(x: float) -> float:
	return float(geography.call("coast_z",x))

func land_distance(x: float, z: float) -> float:
	return float(geography.call("land_distance",x,z))

func height_at(x: float, z: float) -> float:
	return float(geography.call("height_at",x,z))

func render_height_at(x: float,z: float) -> float:
	var step: float=EXTENT*2.0/GRID
	var grid: Vector2=(Vector2(x,z)+Vector2.ONE*EXTENT)/step
	var col: int=clampi(floori(grid.x),0,GRID-1)
	var row: int=clampi(floori(grid.y),0,GRID-1)
	var u: float=clampf(grid.x-col,0,1)
	var v: float=clampf(grid.y-row,0,1)
	var x0: float=-EXTENT+col*step
	var z0: float=-EXTENT+row*step
	if u+v<=1:
		var h: float=height_at(x0,z0)
		return h+(height_at(x0+step,z0)-h)*u+(height_at(x0,z0+step)-h)*v
	var h: float=height_at(x0+step,z0+step)
	return h+(height_at(x0,z0+step)-h)*(1-u)+(height_at(x0+step,z0)-h)*(1-v)

func _setup_environment() -> void:
	world_environment = WorldEnvironment.new()
	world_environment.name = "CoastalLight"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("70b2d2")
	sky_material.sky_horizon_color = Color("d2e5dc")
	sky_material.ground_bottom_color = Color("618b95")
	sky_material.ground_horizon_color = Color("d2e5dc")
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b9d7db")
	environment.ambient_light_energy = .20
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure = 1.0
	environment.fog_enabled = true
	environment.fog_light_color = Color("b8d9d6")
	environment.fog_density = .00012
	world_environment.environment = environment
	add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.name = "AfternoonSun"
	sun.rotation_degrees = Vector3(-48.0,-32.0,0.0)
	sun.light_color = Color("fff0ca")
	sun.light_energy = .65
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 420.0
	sun.shadow_bias = .05
	add_child(sun)
	camera = Camera3D.new()
	camera.name = "TacticalCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = target_size
	camera.near = .5
	camera.far = 1500.0
	add_child(camera)
	camera.current = true

func _terrain_color(x: float,z: float,h: float,surface_slope: float = -1.0) -> Color:
	var d: float = land_distance(x,z)
	var hue_noise: float = noise.get_noise_2d(x+600,z+50)*.5+.5
	if d < 0.0: return Color("8ab7a4").lerp(Color("d2c89c"),clampf((h+10.0)/10.0,0.0,1.0))
	var sand: Color = Color("ead9a5").lerp(Color("dac18f"),hue_noise*.4)
	var swamp: float = float(geography.call("swamp_weight",x,z))
	var river: float = float(geography.call("river_weight",x,z))
	if swamp>.32 or river>.35:
		return Color("7e9860").lerp(Color("746b4c"),1.0-smoothstep(1.15,2.5,h)).lerp(Color("9b9868"),hue_noise*.2)
	if d<17.0 and float(geography.call("beach_access",x,z))<.65:
		return Color("a08c70").lerp(Color("c0af8a"),hue_noise*.65)
	if d < 3.0: return Color("b6b98e").lerp(sand,d/3.0)
	var grass: Color = Color("78a54a").lerp(Color("9ab65b"),hue_noise)
	var moisture: float = micro.get_noise_2d(x,z)
	grass = grass.lerp(Color("b3b47b"),smoothstep(.15,.6,moisture)*.35)
	var color: Color = sand.lerp(grass,smoothstep(13.0,30.0,d))
	var slope: float = surface_slope if surface_slope>=0.0 else float(geography.call("slope_at",x,z))
	var rock_amount: float = smoothstep(.40,.82,slope)*smoothstep(5.0,15.0,h)
	return color.lerp(Color("a79e7a").lerp(Color("c4b58f"),hue_noise),rock_amount)

func _build_terrain() -> void:
	var stride: int = GRID+1
	var step: float = EXTENT*2.0/GRID
	var heights := PackedFloat32Array()
	heights.resize(stride*stride)
	for row: int in range(stride):
		for col: int in range(stride): heights[row*stride+col]=height_at(-EXTENT+col*step,-EXTENT+row*step)
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	normals.resize(heights.size())
	colors.resize(heights.size())
	for row: int in range(stride):
		for col: int in range(stride):
			var dx: float = (heights[row*stride+mini(GRID,col+1)]-heights[row*stride+maxi(0,col-1)])/(step*2.0)
			var dz: float = (heights[mini(GRID,row+1)*stride+col]-heights[maxi(0,row-1)*stride+col])/(step*2.0)
			normals[row*stride+col]=Vector3(-dx,1.0,-dz).normalized()
			colors[row*stride+col]=_terrain_color(-EXTENT+col*step,-EXTENT+row*step,heights[row*stride+col],Vector2(dx,dz).length())
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row: int in range(GRID):
		for col: int in range(GRID):
			var x0: float = -EXTENT+col*(EXTENT*2.0/GRID)
			var z0: float = -EXTENT+row*(EXTENT*2.0/GRID)
			for offset: Vector2 in [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
				var x: float = x0+offset.x*step
				var z: float = z0+offset.y*step
				var index: int = (row+int(offset.y))*stride+col+int(offset.x)
				var h: float = heights[index]
				st.set_normal(normals[index])
				st.set_color(colors[index])
				st.set_uv(Vector2(x,z)*.1)
				st.add_vertex(Vector3(x,h,z))
	st.index()
	var mesh: ArrayMesh = st.commit()
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = load("res://shaders/terrain.gdshader")
	terrain_material.set_shader_parameter("grain",grain_texture)
	var ground := MeshInstance3D.new()
	ground.name = "ContinuousTerrain"
	ground.mesh = mesh
	ground.material_override = terrain_material
	world_root.add_child(ground)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	ground.add_child(body)

func _build_water() -> void:
	var image := Image.create(256,256,false,Image.FORMAT_RF)
	for y: int in range(256):
		for x: int in range(256):
			var h: float = height_at((x/255.0-.5)*EXTENT*2.0,(y/255.0-.5)*EXTENT*2.0)
			image.set_pixel(x,y,Color((h+32.0)/100.0,0,0))
	water_material = ShaderMaterial.new()
	water_material.shader = load("res://shaders/water.gdshader")
	water_material.set_shader_parameter("height_map",ImageTexture.create_from_image(image))
	water_material.set_shader_parameter("grain",grain_texture)
	water_material.set_shader_parameter("map_extent",EXTENT)
	var plane := PlaneMesh.new()
	plane.size = Vector2(1100,1100)
	plane.subdivide_depth = 180
	plane.subdivide_width = 180
	var sea := MeshInstance3D.new()
	sea.name = "AnimatedSea"
	sea.mesh = plane
	sea.position.y = .09
	sea.material_override = water_material
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_root.add_child(sea)
	_build_ocean_horizon()

func _build_ocean_horizon() -> void:
	# Low-detail skirt keeps the sea edge outside the widest map camera;
	# the dense, animated near-water grid remains unchanged around the island.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for rect: Rect2 in [Rect2(-2600,-2600,2050,5200),Rect2(550,-2600,2050,5200),Rect2(-550,-2600,1100,2050),Rect2(-550,550,1100,2050)]:
		var nx: int=int(ceil(rect.size.x/48.0))
		var nz: int=int(ceil(rect.size.y/48.0))
		for row: int in range(nz):
			for col: int in range(nx):
				var a: Vector2=rect.position+rect.size*Vector2(float(col)/nx,float(row)/nz)
				var b: Vector2=rect.position+rect.size*Vector2(float(col+1)/nx,float(row+1)/nz)
				for p: Vector2 in [a,Vector2(a.x,b.y),Vector2(b.x,a.y),Vector2(b.x,a.y),Vector2(a.x,b.y),b]:
					st.set_normal(Vector3.UP)
					st.add_vertex(Vector3(p.x,.09,p.y))
	var horizon := MeshInstance3D.new()
	horizon.name="LowDetailOceanHorizon"
	st.index()
	horizon.mesh=st.commit()
	horizon.material_override=water_material
	horizon.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_root.add_child(horizon)

func _build_architecture() -> void:
	if ResourceLoader.exists("res://scripts/coastal_architecture.gd"):
		var script: Script = load("res://scripts/coastal_architecture.gd")
		var architecture: Node3D = Node3D.new()
		architecture.set_script(script)
		architecture.name = "EditableHarborVillage"
		world_root.add_child(architecture)
		architecture.call("build",Callable(self,"render_height_at"))

func _build_inland_biomes() -> void:
	var biomes: Node3D=Node3D.new()
	biomes.set_script(load("res://scripts/coastal_biomes.gd"))
	biomes.name="SharedGeographyWetlands"
	world_root.add_child(biomes)
	biomes.call("build",geography,Callable(self,"render_height_at"),grain_texture)

func _build_wasteland() -> void:
	if not ResourceLoader.exists("res://scripts/wasteland_architecture.gd"): return
	var district: Node3D=Node3D.new()
	district.name="SalvagedWastelandDistrict"
	district.set_script(load("res://scripts/wasteland_architecture.gd"))
	world_root.add_child(district)
	district.call("build",Callable(self,"render_height_at"))

func _build_cast() -> void:
	if ResourceLoader.exists("res://scripts/demo_cast.gd"):
		var cast: Node3D = Node3D.new()
		cast.set_script(load("res://scripts/demo_cast.gd"))
		cast.name = "IdentityBoundCharacters"
		world_root.add_child(cast)
		cast.set("display_height",3.8)
		cast.call("build",Callable(self,"render_height_at"))
		var home_cast: Node3D = Node3D.new()
		home_cast.set_script(load("res://scripts/demo_cast.gd"))
		home_cast.name = "HomeCharacterScaleReference"
		world_root.add_child(home_cast)
		home_cast.set("display_height",3.8)
		var layout: Array[Vector3] = [Vector3(0,0,126),Vector3(-43,0,163),Vector3(51,0,88)]
		home_cast.call("set_layout",layout)
		home_cast.call("build",Callable(self,"render_height_at"))

func _build_home_district() -> void:
	var district: Node3D = Node3D.new()
	district.set_script(load("res://scripts/home_architecture.gd"))
	district.name = "HomeFacilityArtPrototypes"
	world_root.add_child(district)
	district.call("build",Callable(self,"render_height_at"))
	for z: float in [88.0,126.0,163.0,200.0]:
		_road([Vector2(-84,z),Vector2(-40,z),Vector2(0,z),Vector2(40,z),Vector2(80,z)],4.2,Color("b8b9a1"))
	for x: float in [-84.0,80.0]:
		_road([Vector2(x,88),Vector2(x,126),Vector2(x,163),Vector2(x,200)],4.2,Color("b8b9a1"))
	_road([Vector2(0,70),Vector2(0,88)],5.0,Color("b8b9a1"))

func _build_vehicle_showcase() -> void:
	# Optional asset module is staged separately from combat rules.
	if not ResourceLoader.exists("res://scripts/coastal_vehicles.gd"): return
	var vehicles: Node3D = Node3D.new()
	vehicles.set_script(load("res://scripts/coastal_vehicles.gd"))
	vehicles.name = "ThreeDimensionalVehicles"
	world_root.add_child(vehicles)
	vehicles.call("build",Callable(self,"render_height_at"))

func _road(points: Array[Vector2], width: float, tint: Color) -> void:
	road_layer+=1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment: int in range(points.size()-1):
		var a: Vector2 = points[segment]
		var b: Vector2 = points[segment+1]
		var steps: int = maxi(1,ceili(a.distance_to(b)/1.2))
		var side: Vector2 = (b-a).normalized().orthogonal()*width*.5
		var side_end: Vector2 = side
		if segment>0:
			var previous: Vector2 = (a-points[segment-1]).normalized().orthogonal()
			var join: Vector2 = (previous+side.normalized()).normalized()
			side=join*width*.5/maxf(.4,join.dot(side.normalized()))
		if segment+2<points.size():
			var following: Vector2 = (points[segment+2]-b).normalized().orthogonal()
			var join: Vector2 = (following+side_end.normalized()).normalized()
			side_end=join*width*.5/maxf(.4,join.dot(side_end.normalized()))
		for i: int in range(steps):
			var p: Vector2 = a.lerp(b,float(i)/steps)
			var q: Vector2 = a.lerp(b,float(i+1)/steps)
			var left: Vector2 = side.lerp(side_end,float(i)/steps)
			var right: Vector2 = side.lerp(side_end,float(i+1)/steps)
			for across: int in range(5):
				var p0: Vector2=p+left*lerpf(-1.0,1.0,across/5.0)
				var p1: Vector2=p+left*lerpf(-1.0,1.0,(across+1)/5.0)
				var q0: Vector2=q+right*lerpf(-1.0,1.0,across/5.0)
				var q1: Vector2=q+right*lerpf(-1.0,1.0,(across+1)/5.0)
				for v: Vector2 in [p0,p1,q0,q0,p1,q1]:
					st.set_color(tint.srgb_to_linear())
					st.set_uv(v*.3)
					st.add_vertex(Vector3(v.x,render_height_at(v.x,v.y)+.18+road_layer*.012,v.y))
	st.generate_normals()
	var item := MeshInstance3D.new()
	item.name = "ConnectedGroundRoad"
	item.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = .95
	item.material_override = mat
	world_root.add_child(item)

func _build_roads() -> void:
	_road([Vector2(-2,-43),Vector2(-2,0),Vector2(-2,43),Vector2(2,83),Vector2(21,115),Vector2(62,140)],8.4,Color("7f8f87"))
	_road([Vector2(-62,18),Vector2(-31,13),Vector2(-2,13),Vector2(28,13),Vector2(66,25)],6.2,Color("939e8d"))
	_road([Vector2(-48,57),Vector2(-28,56),Vector2(0,56),Vector2(31,57),Vector2(70,63)],5.6,Color("939e8d"))
	_road([Vector2(-61,18),Vector2(-80,37),Vector2(-101,71),Vector2(-114,103)],3.0,Color("bcaf7d"))
	_road([Vector2(66,25),Vector2(88,20)],5.5,Color("939e8d"))
	for z: float in [20.0,58.0,96.0]:
		_road([Vector2(88,z),Vector2(126,z),Vector2(170,z)],5.5,Color("939e8d"))
	for x: float in [88.0,126.0,170.0]:
		_road([Vector2(x,20),Vector2(x,58),Vector2(x,96)],5.5,Color("939e8d"))
	_road([Vector2(0,200),Vector2(0,230)],4.0,Color("b4ac91"))
	_build_intersections()

func _mark_quad(st: SurfaceTool,a: Vector2,b: Vector2,width: float,tint: Color) -> void:
	var side: Vector2=(b-a).normalized().orthogonal()*width*.5
	for p: Vector2 in [a-side,a+side,b-side,b-side,a+side,b+side]:
		st.set_normal(Vector3.UP)
		st.set_color(tint.srgb_to_linear())
		st.add_vertex(Vector3(p.x,render_height_at(p.x,p.y)+.48,p.y))

func _build_intersections() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for center: Vector2 in [Vector2(-2,13),Vector2(-.4,56),Vector2(126,58)]:
		_road([center-Vector2(6.0,0),center+Vector2(6.0,0)],12.0,Color("75877f"))
		for side: float in [-1.0,1.0]:
			for stripe: int in range(5):
				var x: float=center.x+(stripe-2)*1.0
				_mark_quad(st,Vector2(x,center.y+side*7.0-.8),Vector2(x,center.y+side*7.0+.8),.55,Color("d9d8bd"))
	for z: float in [-31.0,-22.0,-13.0,-4.0,28.0,37.0,70.0]:
		_mark_quad(st,Vector2(-2,z),Vector2(-2,z+3.1),.17,Color("ded9b1"))
	var paint := MeshInstance3D.new()
	paint.name="WornCrosswalksAndLaneDashes"
	st.index()
	paint.mesh=st.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo=true
	material.roughness=.98
	paint.material_override=material
	paint.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_root.add_child(paint)

func _collect_meshes(node: Node, transform: Transform3D, result: Array[Dictionary]) -> void:
	var local: Transform3D = transform
	if node is Node3D: local = transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var item: MeshInstance3D = node as MeshInstance3D
		if item.mesh != null: result.append({"mesh":item.mesh,"transform":local,"material":item.material_override})
	for child: Node in node.get_children(): _collect_meshes(child,local,result)

func _instance_species(path: String, points: Array[Vector3], desired_height: float) -> void:
	if not ResourceLoader.exists(path) or points.is_empty(): return
	var packed: PackedScene = load(path) as PackedScene
	if packed == null: return
	var source: Node = packed.instantiate()
	var parts: Array[Dictionary] = []
	_collect_meshes(source,Transform3D.IDENTITY,parts)
	var bounds := AABB()
	var has_bounds: bool = false
	for part: Dictionary in parts:
		var transformed: AABB = (part["transform"] as Transform3D) * (part["mesh"] as Mesh).get_aabb()
		bounds = bounds.merge(transformed) if has_bounds else transformed
		has_bounds = true
	var scaling: float = desired_height/maxf(bounds.size.y,.1)
	for part: Dictionary in parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _nature_palette(part["mesh"])
		mm.instance_count = points.size()
		for index: int in range(points.size()):
			var p: Vector3 = points[index]
			var variation: float = .82+float(index%7)*.055
			var basis := Basis(Vector3.UP,float(index)*2.39996).scaled(Vector3.ONE*scaling*variation)
			var t := Transform3D(basis,p-Vector3.UP*bounds.position.y*scaling*variation)
			mm.set_instance_transform(index,t*(part["transform"] as Transform3D))
			mm.set_instance_color(index,Color(1.0,1.0,1.0))
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = mm
		if part["material"] != null: instance.material_override = part["material"]
		vegetation.add_child(instance)
	source.free()

func _nature_palette(original: Mesh) -> Mesh:
	var key: int=original.get_instance_id()
	if nature_mesh_cache.has(key): return nature_mesh_cache[key]
	var mesh: Mesh=original.duplicate()
	for surface: int in range(mesh.get_surface_count()):
		var source: Material=mesh.surface_get_material(surface)
		if not source is StandardMaterial3D: continue
		var material: StandardMaterial3D=source.duplicate()
		match source.resource_name:
			"Green": material.albedo_color=Color("78a847")
			"DarkGreen": material.albedo_color=Color("557d3b")
			"White": material.albedo_color=Color("d6d4b5")
			"Black": material.albedo_color=Color("4e5949")
			"Wood": material.albedo_color=Color("806648")
			"Rock": material.albedo_color=Color("a4a68d")
		material.roughness=.94
		mesh.surface_set_material(surface,material)
	nature_mesh_cache[key]=mesh
	return mesh

func _build_vegetation() -> void:
	if FileAccess.file_exists("res://assets/vendor/nature-refine/selected.json"):
		var module: RefCounted = load("res://scripts/coastal_nature.gd").new()
		vegetation=module.call("build",world_root,Callable(self,"height_at"),Callable(self,"render_height_at"),terrain_seed,Callable(self,"land_distance"))
		var grass_rng: RandomNumberGenerator = RandomNumberGenerator.new()
		grass_rng.seed=terrain_seed+300
		_build_grass(grass_rng)
		return
	vegetation = Node3D.new()
	vegetation.name = "NatureClusters"
	world_root.add_child(vegetation)
	var manifest: Dictionary = {}
	if FileAccess.file_exists("res://assets/vendor/nature_manifest.json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/vendor/nature_manifest.json"))
		if parsed is Dictionary: manifest = parsed
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed + 300
	var trees: Array[Vector3] = []
	var shrubs: Array[Vector3] = []
	var stones: Array[Vector3] = []
	for index: int in range(1100):
		var x: float = rng.randf_range(-235,235)
		var z: float = rng.randf_range(-80,245)
		var d: float = land_distance(x,z)
		if d < 18.0: continue
		var town: bool = absf(x)<70 and z<102
		var road_distance: float = absf(x-(-2.0 if z<70 else (z-70.0)*.5))
		if town or road_distance<8.0: continue
		var h: float = height_at(x,z)
		if noise.get_noise_2d(x-321,z+721) > -.23 and trees.size()<160:
			trees.append(Vector3(x,h,z))
		elif shrubs.size()<110:
			shrubs.append(Vector3(x,h+.02,z))
	for index: int in range(180):
		var x: float = rng.randf_range(-240,240)
		var z: float = coast_z(x)+rng.randf_range(-3.0,11.0)
		if absf(x)<69: continue
		if land_distance(x,z)<-5: continue
		stones.append(Vector3(x,height_at(x,z)-.15,z))
	_place_manifest_group(manifest,"trees",trees,11.0)
	var street_trees: Array[Vector3] = []
	for point: Vector2 in [Vector2(-15,31),Vector2(14,38),Vector2(-47,67),Vector2(48,74),Vector2(-19,-8),Vector2(12,-12),Vector2(-50,25),Vector2(47,11)]:
		street_trees.append(Vector3(point.x,height_at(point.x,point.y),point.y))
	_place_manifest_group(manifest,"trees",street_trees,7.0)
	for point: Vector2 in [Vector2(-16,18),Vector2(-40,23),Vector2(-42,27),Vector2(19,19),Vector2(37,18),Vector2(-11,-8),Vector2(10,-6),Vector2(-25,58),Vector2(21,58),Vector2(44,62)]:
		shrubs.append(Vector3(point.x,height_at(point.x,point.y),point.y))
	_place_manifest_group(manifest,"bushes",shrubs,2.0)
	_place_manifest_group(manifest,"rocks",stones,2.7)
	_build_grass(rng)

func _place_manifest_group(manifest: Dictionary,key: String,points: Array[Vector3],height: float) -> void:
	var entries: Array = manifest.get(key,[])
	for type_index: int in range(entries.size()):
		var group: Array[Vector3] = []
		for index: int in range(points.size()):
			if index%entries.size()==type_index: group.append(points[index])
		var entry: Variant = entries[type_index]
		var path: String = str(entry.get("path","")) if entry is Dictionary else str(entry)
		var chunks: Dictionary = {}
		for point: Vector3 in group:
			var key_chunk := Vector2i(floori(point.x/128.0),floori(point.z/128.0))
			if not chunks.has(key_chunk): chunks[key_chunk] = []
			chunks[key_chunk].append(point)
		for key_chunk: Vector2i in chunks:
			var chunk_points: Array[Vector3] = []
			chunk_points.assign(chunks[key_chunk])
			_instance_species(path,chunk_points,height)

func _build_grass(rng: RandomNumberGenerator) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade: int in range(5):
		var x: float = (blade-2)*.14
		var high: float = .30+float(blade%3)*.13
		st.set_color(Color("9cb365") if blade%2==0 else Color("748f42"))
		for vertex: Vector3 in [Vector3(x-.08,0,0),Vector3(x+.08,0,0),Vector3(x+.06,high,.03)]:
			st.set_normal(Vector3.UP)
			st.add_vertex(vertex)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = st.commit()
	var locations: Array[Vector3] = []
	for i: int in range(6000):
		var x: float = rng.randf_range(-235,235)
		var z: float = rng.randf_range(-30,240)
		if land_distance(x,z)<26: continue
		if absf(x)<72 and z<105: continue
		if x>-99 and x<96 and z>84 and z<210: continue
		if float(geography.call("slope_at",x,z))>.55: continue
		if str(geography.call("biome_at",x,z)) in ["swamp","river"]: continue
		if x>80 and x<177 and z>12 and z<104: continue
		locations.append(Vector3(x,height_at(x,z)+.02,z))
	mm.instance_count = locations.size()
	for i: int in range(locations.size()):
		mm.set_instance_transform(i,Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*rng.randf_range(.7,1.8)),locations[i]))
	var grass := MultiMeshInstance3D.new()
	grass.name = "WindInGrass"
	grass.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grass.gdshader")
	grass.material_override = mat
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vegetation.add_child(grass)

func _build_clouds() -> void:
	cloud_material = ShaderMaterial.new()
	cloud_material.shader = load("res://shaders/cloud.gdshader")
	cloud_material.set_shader_parameter("grain",grain_texture)
	cloud_material.set_shader_parameter("coverage",.08)
	for i: int in range(7):
		var cloud := MeshInstance3D.new()
		cloud.name = "DriftingCloud%d"%i
		var plane := PlaneMesh.new()
		plane.size = Vector2(100+(i%3)*19,65+(i%2)*22)
		cloud.mesh = plane
		cloud.material_override = cloud_material
		cloud.position = Vector3(-260+i*85,65+i%3*7,-30+(i%3)*110)
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cloud)
		clouds.append(cloud)
	rain = CPUParticles3D.new()
	rain.name = "WeatherRain"
	rain.amount = 700
	rain.lifetime = 1.4
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(100,12,100)
	rain.direction = Vector3(.12,-1,.07)
	rain.initial_velocity_min = 30
	rain.initial_velocity_max = 43
	rain.gravity = Vector3(0,-2,0)
	var drop := BoxMesh.new()
	drop.size = Vector3(.025,.85,.025)
	var rain_mat := StandardMaterial3D.new()
	rain_mat.albedo_color = Color(.76,.9,.95,.35)
	rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop.material = rain_mat
	rain.mesh = drop
	rain.emitting = false
	add_child(rain)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MinimalArtReviewControls"
	add_child(layer)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	var theme := Theme.new()
	if ResourceLoader.exists("res://assets/fonts/NotoSansSC.ttf"):
		var font := FontVariation.new()
		font.base_font = load("res://assets/fonts/NotoSansSC.ttf")
		font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):500.0}
		theme.default_font = font
	theme.default_font_size = 18
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("173c43f0")
	normal.corner_radius_top_left = 5
	normal.corner_radius_top_right = 5
	normal.corner_radius_bottom_left = 5
	normal.corner_radius_bottom_right = 5
	normal.content_margin_left = 19
	normal.content_margin_right = 19
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	theme.set_stylebox("normal","Button",normal)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color("38706af5")
	theme.set_stylebox("hover","Button",hover)
	theme.set_stylebox("pressed","Button",hover)
	theme.set_color("font_color","Button",Color("f7edd3"))
	hud.theme = theme
	var top := MarginContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_constant_override("margin_left",38)
	top.add_theme_constant_override("margin_right",38)
	top.add_theme_constant_override("margin_top",28)
	hud.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	top.add_child(row)
	var title := VBoxContainer.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var wordmark := Label.new()
	wordmark.text = "归 航  /  浅湾"
	wordmark.add_theme_font_size_override("font_size",29)
	wordmark.add_theme_color_override("font_color",Color("173e43"))
	title.add_child(wordmark)
	var subtitle := Label.new()
	subtitle.text = "海岸美术样区 · 3D"
	subtitle.add_theme_font_size_override("font_size",14)
	subtitle.add_theme_color_override("font_color",Color("365b59"))
	title.add_child(subtitle)
	for i: int in range(3):
		var button := Button.new()
		button.text = ["晴日","薄暮","阵雨"][i]
		button.pressed.connect(_set_weather.bind(i))
		row.add_child(button)
	var bottom := MarginContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -100
	bottom.add_theme_constant_override("margin_left",38)
	bottom.add_theme_constant_override("margin_right",38)
	bottom.add_theme_constant_override("margin_bottom",20)
	hud.add_child(bottom)
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation",10)
	bottom.add_child(bottom_row)
	for i: int in range(4):
		var button := Button.new()
		button.text = ["海湾","港镇","山林","家园样板"][i]
		button.pressed.connect(_set_camera_view.bind(i,false))
		bottom_row.add_child(button)
	var more := MenuButton.new()
	more.text="更多景观"
	more.flat=false
	for item: Dictionary in [{"name":"沼泽与河谷","id":4},{"name":"海崖与岩岸","id":5},{"name":"废土工业","id":6},{"name":"海图预览","id":7},{"name":"围墙防线","id":8}]:
		more.get_popup().add_item(str(item["name"]),int(item["id"]))
	more.get_popup().id_pressed.connect(_set_camera_view.bind(false))
	bottom_row.add_child(more)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.add_child(spacer)
	status = Label.new()
	status.text = "拖动看景 · 滚轮 / 双指缩放 · Tab 隐藏界面"
	status.add_theme_font_size_override("font_size",15)
	status.add_theme_color_override("font_color",Color("f7eed7"))
	status.add_theme_color_override("font_shadow_color",Color("143a43"))
	status.add_theme_constant_override("shadow_offset_x",1)
	status.add_theme_constant_override("shadow_offset_y",2)
	var right_column := VBoxContainer.new()
	bottom_row.add_child(right_column)
	scale_label=Label.new()
	scale_label.add_theme_font_size_override("font_size",14)
	scale_label.add_theme_color_override("font_color",Color("fff1cc"))
	scale_label.add_theme_color_override("font_shadow_color",Color("183f47"))
	scale_label.add_theme_constant_override("shadow_offset_x",1)
	scale_label.add_theme_constant_override("shadow_offset_y",1)
	right_column.add_child(scale_label)
	scale_bar=ColorRect.new()
	scale_bar.color=Color("fff1cc")
	scale_bar.custom_minimum_size=Vector2(100,3)
	scale_bar.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	right_column.add_child(scale_bar)
	right_column.add_child(status)

func _set_camera_view(index: int,instant: bool=false) -> void:
	selected_view = index
	match index:
		0:
			target_focus = Vector3(0,3,12)
			target_size = 190
		1:
			target_focus = Vector3(-3,4,29)
			target_size = 92
		2:
			target_focus = Vector3(196,40,139)
			target_size = 176
		3:
			target_focus = Vector3(-2,8,142)
			target_size = 172
		4:
			target_focus=Vector3(-156,5,135)
			target_size=135
		5:
			target_focus=Vector3(-190,19,-5)
			target_size=165
		6:
			target_focus=Vector3(128,12,60)
			target_size=138
		7:
			target_focus=Vector3(0,12,77)
			target_size=650
		8:
			target_focus=Vector3(0,13,216)
			target_size=152
	if instant:
		focus = target_focus
		camera.size = target_size
		_update_camera()

func _update_camera() -> void:
	# Keep even the lowest orthographic ray above the sea at wide map scales.
	# A fixed near camera cut the foreground water off at the bottom edge.
	camera.position = focus+Vector3(215,245,-285)*maxf(1.0,camera.size/500.0)
	camera.look_at(focus)

func _set_weather(index: int) -> void:
	weather = index
	var env: Environment = world_environment.environment
	match index:
		0:
			sun.rotation_degrees = Vector3(-48,-32,0)
			sun.light_color = Color("fff0ca")
			sun.light_energy = .65
			env.ambient_light_color = Color("b9d7db")
			env.ambient_light_energy = .20
			env.fog_light_color = Color("b8d9d6")
			env.fog_density = .00012
		1:
			sun.rotation_degrees = Vector3(-22,-62,0)
			sun.light_color = Color("ffd1a1")
			sun.light_energy = .90
			env.ambient_light_color = Color("acb6d1")
			env.ambient_light_energy = .30
			env.fog_light_color = Color("e0c7b7")
			env.fog_density = .00035
		2:
			sun.rotation_degrees = Vector3(-46,-32,0)
			sun.light_color = Color("dce9ed")
			sun.light_energy = .60
			env.ambient_light_color = Color("9fbec7")
			env.ambient_light_energy = .75
			env.fog_light_color = Color("b2c9cb")
			env.fog_density = .0009
	var cloud_amount: float = .08 if index==0 else (.12 if index==1 else .38)
	cloud_material.set_shader_parameter("coverage",cloud_amount)
	terrain_material.set_shader_parameter("cloud_cover",cloud_amount)
	water_material.set_shader_parameter("cloud_cover",cloud_amount)
	water_material.set_shader_parameter("sea_state",1.0 if index==0 else (1.2 if index==1 else 1.8))
	rain.emitting = index==2

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed>3 and frame_times.size()<1800: frame_times.append(delta*1000.0)
	focus = focus.lerp(target_focus,1.0-exp(-delta*9.0))
	camera.size = lerpf(camera.size,target_size,1.0-exp(-delta*9.0))
	_update_camera()
	_update_map_scale()
	var coarse: bool=camera.size>430.0
	if coarse!=coarse_view:
		coarse_view=coarse
		for name: String in ["EditableHarborVillage","HomeFacilityArtPrototypes","SalvagedWastelandDistrict","ThreeDimensionalVehicles","IdentityBoundCharacters","HomeCharacterScaleReference","NaturalCanopyClusters"]:
			var detail_node: Node3D=world_root.get_node_or_null(NodePath(name)) as Node3D
			if detail_node!=null: detail_node.visible=not coarse
	rain.position = focus+Vector3(0,45,0)
	for i: int in range(clouds.size()):
		clouds[i].position.x += delta*(.65+float(i%3)*.12)
		if clouds[i].position.x>340: clouds[i].position.x = -340

func _update_map_scale() -> void:
	if scale_label==null: return
	var metres: float=100.0 if camera.size>300.0 else 20.0
	var a: Vector2=camera.unproject_position(focus)
	var b: Vector2=camera.unproject_position(focus+camera.global_basis.x.normalized()*metres)
	scale_label.text="%d m" % int(metres)
	scale_bar.custom_minimum_size.x=clampf(a.distance_to(b),20.0,380.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event
		if mouse.button_index==MOUSE_BUTTON_LEFT:
			dragging=mouse.pressed
			if mouse.pressed: drag_distance=0
		if mouse.pressed and mouse.button_index==MOUSE_BUTTON_WHEEL_UP: target_size=clampf(target_size*.87,40,760)
		if mouse.pressed and mouse.button_index==MOUSE_BUTTON_WHEEL_DOWN: target_size=clampf(target_size*1.15,40,760)
	elif event is InputEventMouseMotion and dragging:
		var motion: InputEventMouseMotion = event
		drag_distance += motion.relative.length()
		_pan(motion.relative)
	elif event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed: touches[touch.index]=touch.position
		else: touches.erase(touch.index)
		pinch_distance=0
	elif event is InputEventScreenDrag:
		var touch_drag: InputEventScreenDrag=event
		touches[touch_drag.index]=touch_drag.position
		if touches.size()==1: _pan(touch_drag.relative)
		elif touches.size()==2:
			var positions: Array = touches.values()
			var distance: float = (positions[0] as Vector2).distance_to(positions[1])
			if pinch_distance>0: target_size=clampf(target_size*pinch_distance/maxf(distance,1.0),40,760)
			pinch_distance=distance
	elif event is InputEventMagnifyGesture:
		target_size=clampf(target_size/(event as InputEventMagnifyGesture).factor,40,760)
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		match event.keycode:
			KEY_1: _set_camera_view(0)
			KEY_2: _set_camera_view(1)
			KEY_3: _set_camera_view(2)
			KEY_4: _set_camera_view(3)
			KEY_5: _set_camera_view(4)
			KEY_6: _set_camera_view(5)
			KEY_7: _set_camera_view(6)
			KEY_8: _set_camera_view(7)
			KEY_9: _set_camera_view(8)
			KEY_F11:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
			KEY_ESCAPE: get_tree().quit()

func _input(event: InputEvent) -> void:
	if hud==null: return
	if event is InputEventKey and event.is_pressed() and not event.is_echo() and event.keycode==KEY_TAB:
		show_hud=not show_hud
		hud.visible=show_hud
		get_viewport().set_input_as_handled()

func _pan(relative: Vector2) -> void:
	var right: Vector3 = camera.global_basis.x
	var up: Vector3 = Vector3(camera.global_basis.y.x,0,camera.global_basis.y.z).normalized()
	var scale: float = camera.size/get_viewport().get_visible_rect().size.y
	target_focus -= right*relative.x*scale
	target_focus += up*relative.y*scale*1.50
	target_focus.x=clampf(target_focus.x,-260,260)
	target_focus.z=clampf(target_focus.z,-160,250)
	target_focus.y=maxf(2.0,height_at(target_focus.x,target_focus.z)*.5)

func _capture_gallery() -> void:
	var output: String = ProjectSettings.globalize_path(SCREENSHOTS)
	DirAccess.make_dir_recursive_absolute(output)
	_save_editable_scene()
	await get_tree().create_timer(4.0).timeout
	for shot: Dictionary in [{"name":"01-bay-day","view":0,"weather":0},{"name":"02-town-day","view":1,"weather":0},{"name":"03-hillside","view":2,"weather":0},{"name":"04-bay-evening","view":0,"weather":1},{"name":"05-town-rain","view":1,"weather":2}]:
		_set_camera_view(int(shot["view"]),true)
		_set_weather(int(shot["weather"]))
		await get_tree().create_timer(1.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output+str(shot["name"])+".png")
		print("ART_CAPTURE "+str(shot["name"]))
	_set_camera_view(0,true)
	_set_weather(0)
	hud.visible = false
	await get_tree().create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output+"06-clean-bay.png")
	target_focus=Vector3(-8,4,19)
	focus=target_focus
	target_size=65
	camera.size=65
	_update_camera()
	await get_tree().create_timer(.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output+"07-clean-town-detail.png")
	frame_times.sort()
	var metrics: Dictionary = {"renderer":RenderingServer.get_current_rendering_method(),"platform":OS.get_name(),"seed":terrain_seed,"frame_samples":frame_times.size(),"draw_calls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),"visible_primitives":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),"static_memory_bytes":OS.get_static_memory_usage(),"scope":"isolated art sample; not Android or combat acceptance"}
	if not frame_times.is_empty():
		metrics["p50_ms"]=frame_times[int(frame_times.size()*.50)]
		metrics["p95_ms"]=frame_times[mini(frame_times.size()-1,int(frame_times.size()*.95))]
		metrics["p99_ms"]=frame_times[mini(frame_times.size()-1,int(frame_times.size()*.99))]
	var file := FileAccess.open(output+"../desktop-sample-metrics.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(metrics,"\t"))
	get_tree().quit()

func _assign_scene_owner(node: Node,root: Node) -> void:
	for child: Node in node.get_children():
		child.owner=root
		_assign_scene_owner(child,root)

func _capture_home_gallery() -> void:
	var output: String = ProjectSettings.globalize_path("res://../../artifacts/home-design-20261116/screenshots/")
	DirAccess.make_dir_recursive_absolute(output)
	await get_tree().create_timer(2.0).timeout
	hud.visible = false
	_set_weather(0)
	for entry: Dictionary in [
		{"name":"home-district","focus":Vector3(-3,7,138),"size":165.0},
		{"name":"home-production","focus":Vector3(-14,7,109),"size":85.0},
		{"name":"home-defense","focus":Vector3(18,9,180),"size":95.0},
		{"name":"coast-new-nature","focus":Vector3(0,3,12),"size":190.0},
		{"name":"nature-detail","focus":Vector3(110,21,109),"size":100.0},
		{"name":"vehicle-shore","focus":Vector3(-15,3,-25),"size":76.0}]:
		target_focus=entry["focus"]
		focus=target_focus
		target_size=float(entry["size"])
		camera.size=target_size
		_update_camera()
		await get_tree().create_timer(.7).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output+str(entry["name"])+".png")
		print("HOME_DISTRICT_CAPTURE "+str(entry["name"]))
	_save_editable_scene()
	get_tree().quit()

func _save_editable_scene() -> void:
	var snapshot := Node3D.new()
	snapshot.name="EditableCoastalSample"
	var duplicate_world: Node = world_root.duplicate()
	snapshot.add_child(duplicate_world)
	# Static, editable objects; the interactive source keeps the live scripts.
	var pending: Array[Node] = [duplicate_world]
	while not pending.is_empty():
		var item: Node = pending.pop_back()
		if item.get_script()!=null: item.set_script(null)
		# The snapshot owns every copied descendant. Retaining an imported GLB
		# scene path would additionally instantiate its original children, then
		# replace them with the explicitly saved descendants. Flatten only this
		# copy so the static scene has one editable tree, not duplicate instances.
		item.scene_file_path=""
		for child: Node in item.get_children(): pending.append(child)
	for original: Node in [sun,world_environment,camera]:
		snapshot.add_child(original.duplicate())
	_assign_scene_owner(snapshot,snapshot)
	var packed := PackedScene.new()
	var error: Error = packed.pack(snapshot)
	if error==OK:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes"))
		error=ResourceSaver.save(packed,"res://scenes/editable_coast.scn",ResourceSaver.FLAG_COMPRESS)
	print("ART_EDITABLE_SCENE "+str(error))
	snapshot.free()

func _capture_terrain_gallery() -> void:
	var output: String=ProjectSettings.globalize_path("res://../../artifacts/coast-v2-20261116/")
	DirAccess.make_dir_recursive_absolute(output+"screenshots")
	DirAccess.make_dir_recursive_absolute(output+"waves")
	await get_tree().create_timer(1.0).timeout
	hud.visible=false
	_set_weather(0)
	for entry: Dictionary in [
		{"name":"island-overview","focus":Vector3(0,17,84),"size":420.0},
		{"name":"harbor-surf","focus":Vector3(-4,3,-48),"size":142.0},
		{"name":"coastal-cliffs","focus":Vector3(-190,21,-7),"size":166.0},
		{"name":"wetlands-river","focus":Vector3(-155,5,134),"size":124.0},
		{"name":"mountain-ridges","focus":Vector3(199,43,146),"size":178.0},
		{"name":"wasteland-industry","focus":Vector3(128,12,60),"size":125.0},
		{"name":"walls-and-defenses","focus":Vector3(-2,14,214),"size":161.0},
		{"name":"vehicle-fleet","focus":Vector3(-4,8,-35),"size":168.0},
		{"name":"sunken-ruins","focus":Vector3(-108,2,-88),"size":100.0},
		{"name":"crossroads","focus":Vector3(-2,3,13),"size":74.0},
		{"name":"strategic-scale","focus":Vector3(0,12,77),"size":650.0}]:
		target_focus=entry["focus"]
		focus=target_focus
		target_size=float(entry["size"])
		camera.size=target_size
		hud.visible=str(entry["name"])=="strategic-scale"
		_update_camera()
		await get_tree().create_timer(.55).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output+"screenshots/"+str(entry["name"])+".png")
		print("COAST_V2_CAPTURE "+str(entry["name"]))
	hud.visible=false
	target_focus=Vector3(-14,2,-76)
	focus=target_focus
	target_size=115.0
	camera.size=target_size
	_update_camera()
	for i: int in range(16):
		water_material.set_shader_parameter("sample_time",i*.25)
		await get_tree().create_timer(.08).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output+"waves/frame-%02d.png" % i)
	water_material.set_shader_parameter("sample_time",-1.0)
	var samples: Array[Dictionary]=[]
	samples.append(await _measure_render_sample("near_harbor"))
	_set_camera_view(7,true)
	await get_tree().create_timer(.5).timeout
	samples.append(await _measure_render_sample("strategic_preview"))
	var metric_file := FileAccess.open(output+"desktop-render-samples.json",FileAccess.WRITE)
	metric_file.store_string(JSON.stringify({"scope":"isolated visual demo; no combat simulation; no Android device", "renderer":RenderingServer.get_current_rendering_method(),"platform":OS.get_name(),"samples":samples},"\t"))
	var header: Dictionary=geography.call("snapshot_header")
	header["actual_grid_step_m"]=EXTENT*2.0/GRID
	header["seeded_features"]=["beach","sea_cliff","mountain","swamp","river"]
	var file := FileAccess.open(output+"geography-header.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(header,"\t"))
	# The editable close scene must restore detail hidden by the strategic
	# camera; otherwise reopening the snapshot would appear to lose buildings.
	_set_camera_view(0,true)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_editable_scene()
	get_tree().quit()

func _measure_render_sample(label: String) -> Dictionary:
	var times: Array[float]=[]
	var draw_calls: Array[int]=[]
	var primitives: Array[int]=[]
	for index: int in range(210):
		var start_usec: int=Time.get_ticks_usec()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if index<30: continue
		times.append((Time.get_ticks_usec()-start_usec)/1000.0)
		draw_calls.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	times.sort()
	draw_calls.sort()
	primitives.sort()
	return {"view":label,"frames":times.size(),"frame_wait_p50_ms":times[90],"frame_wait_p95_ms":times[171],"draw_calls_median":draw_calls[90],"rendered_primitives_median":primitives[90],"godot_static_memory_bytes":OS.get_static_memory_usage(),"camera_size_m":camera.size,"note":"wall-clock frame waits including renderer synchronization; primitive counts include render passes; static allocation is not process RSS"}
