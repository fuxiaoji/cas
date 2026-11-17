extends RefCounted
## Downloaded CC0 vegetation. Grounding and filtering use the demo's own surface.
## A separate placement stream keeps decoration from changing map geometry.

const MANIFEST: String = "res://assets/vendor/nature-refine/selected.json"
const CHUNK_SIZE: float = 96.0
var _mesh_cache: Dictionary = {}
var _height: Callable
var _render_height: Callable
var _land_distance: Callable
var _rng: RandomNumberGenerator
var _root: Node3D
var _variation: FastNoiseLite

func build(parent: Node3D, height_callable: Callable, render_height_callable: Callable, seed_value: int, land_callable: Callable = Callable()) -> Node3D:
	_height = height_callable
	_render_height = render_height_callable
	_land_distance = land_callable
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value + 38273
	_variation = FastNoiseLite.new()
	_variation.seed = seed_value + 8401
	_variation.frequency = 0.021
	_root = Node3D.new()
	_root.name = "NaturalCanopyClusters"
	parent.add_child(_root)
	var manifest: Dictionary = {}
	if FileAccess.file_exists(MANIFEST):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if data is Dictionary: manifest = data
	var tree_points: Array[Vector3] = []
	var street_points: Array[Vector3] = []
	var shrub_points: Array[Vector3] = []
	var stone_points: Array[Vector3] = []
	# Whole tree footprints are tested, not only their trunk sample. This avoids
	# crowns growing through a building, a rock wall, or a cliff edge.
	for attempt: int in range(2200):
		var point: Vector2 = Vector2(_rng.randf_range(-238.0, 238.0), _rng.randf_range(-55.0, 245.0))
		if not _suitable(point, 5.0): continue
		if _variation.get_noise_2d(point.x, point.y) < -0.18: continue
		if not _spaced(point, tree_points, 7.8): continue
		tree_points.append(_ground(point))
		if tree_points.size() >= 145: break
	# Planted shade trees around the old port use the same broadleaf species.
	for point: Vector2 in [Vector2(-15,31), Vector2(14,38), Vector2(-48,73), Vector2(48,75), Vector2(-20,-9), Vector2(13,-13), Vector2(-53,29), Vector2(48,3)]:
		if _slope(point) < 0.42: street_points.append(_ground(point))
	for attempt: int in range(1400):
		var point: Vector2 = Vector2(_rng.randf_range(-240,240), _rng.randf_range(-35,245))
		if not _suitable(point, 1.5): continue
		if _variation.get_noise_2d(point.x+71.0, point.y-196.0) < -0.22: continue
		shrub_points.append(_ground(point))
		if shrub_points.size() >= 100: break
	for attempt: int in range(1000):
		var point: Vector2 = Vector2(_rng.randf_range(-248,248), _rng.randf_range(-85,240))
		var level: float = float(_height.call(point.x,point.y))
		if level < -0.8 or level > 10.0 or _building_clearance(point) < 4.5: continue
		if _road_clearance(point) < 4.5: continue
		stone_points.append(_ground(point)-Vector3.UP*.15)
		if stone_points.size() >= 140: break
	_place_group(manifest.get("trees",[]), tree_points, 10.5, "Canopy")
	_place_group(manifest.get("trees",[]), street_points, 7.1, "StreetShade")
	_place_group(manifest.get("bushes",[]), shrub_points, 1.7, "Undergrowth")
	_place_group(manifest.get("rocks",[]), stone_points, 2.1, "ShoreStone")
	_root.set_meta("tree_count",tree_points.size()+street_points.size())
	_root.set_meta("shrub_count",shrub_points.size())
	_root.set_meta("stone_count",stone_points.size())
	_root.set_meta("placement_seed",seed_value + 38273)
	return _root

func _ground(point: Vector2) -> Vector3:
	return Vector3(point.x, float(_render_height.call(point.x,point.y))-.025, point.y)

func _spaced(point: Vector2, points: Array[Vector3], distance: float) -> bool:
	for other: Vector3 in points:
		if point.distance_squared_to(Vector2(other.x,other.z)) < distance*distance: return false
	return true

func _slope(point: Vector2) -> float:
	var dx: float = (float(_height.call(point.x+1.8,point.y))-float(_height.call(point.x-1.8,point.y)))/3.6
	var dz: float = (float(_height.call(point.x,point.y+1.8))-float(_height.call(point.x,point.y-1.8)))/3.6
	return Vector2(dx,dz).length()

func _suitable(point: Vector2, radius: float) -> bool:
	var level: float = float(_height.call(point.x,point.y))
	if level < 3.0 or level > 43.0 or _slope(point) > .50: return false
	if _land_distance.is_valid() and float(_land_distance.call(point.x,point.y)) < 22.0: return false
	if _road_clearance(point) < radius+3.0: return false
	if _building_clearance(point) < radius+2.0: return false
	return true

func _building_clearance(point: Vector2) -> float:
	var distance: float = INF
	for building: Vector2 in [Vector2(-29,25), Vector2(29,27), Vector2(-2,-1), Vector2(-33,68), Vector2(31,70)]:
		var delta: Vector2 = (point-building).abs()-Vector2(17,15)
		distance=minf(distance,Vector2(maxf(delta.x,0),maxf(delta.y,0)).length())
	# New home architecture grid explicitly shared with the integrator.
	for x: float in [-63.0,-23.0,17.0,57.0]:
		for z: float in [106.0,143.0,180.0]:
			var delta: Vector2 = (point-Vector2(x,z)).abs()-Vector2(18,17)
			distance=minf(distance,Vector2(maxf(delta.x,0),maxf(delta.y,0)).length())
	# Salvage industry, coastal relics, and the new rear defensive perimeter.
	for plot: Array in [
		[Vector2(107,39),Vector2(17,16)], [Vector2(148,39),Vector2(17,15)],
		[Vector2(107,77),Vector2(17,17)], [Vector2(148,77),Vector2(17,18)],
		[Vector2(-96,-91),Vector2(15,15)], [Vector2(-121,-82),Vector2(12,12)],
		[Vector2(28,207),Vector2(15,15)], [Vector2(-30,207),Vector2(14,13)],
		[Vector2(-64,207),Vector2(13,13)], [Vector2(0,218),Vector2(90,4)],
		[Vector2(-84,227),Vector2(4,12)], [Vector2(84,227),Vector2(4,12)]
	]:
		var delta: Vector2=(point-plot[0]).abs()-plot[1]
		distance=minf(distance,Vector2(maxf(delta.x,0),maxf(delta.y,0)).length())
	return distance

func _road_clearance(point: Vector2) -> float:
	var distance: float=INF
	var roads: Array = [
		[Vector2(-2,-43),Vector2(-2,0),Vector2(-2,43),Vector2(2,83),Vector2(21,115),Vector2(62,140)],
		[Vector2(-62,18),Vector2(-31,13),Vector2(-2,13),Vector2(28,13),Vector2(66,25)],
		[Vector2(-48,57),Vector2(-28,56),Vector2(0,56),Vector2(31,57),Vector2(70,63)],
		[Vector2(-61,18),Vector2(-80,37),Vector2(-101,71),Vector2(-114,103)]
	]
	for z: float in [88.0,126.0,163.0,200.0]: roads.append([Vector2(-88,z),Vector2(84,z)])
	roads.append([Vector2(-84,86),Vector2(-84,202)])
	roads.append([Vector2(80,86),Vector2(80,202)])
	for z: float in [20.0,58.0,96.0]: roads.append([Vector2(88,z),Vector2(170,z)])
	for x: float in [88.0,126.0,170.0]: roads.append([Vector2(x,20),Vector2(x,96)])
	roads.append([Vector2(4,200),Vector2(4,230)])
	for road: Array in roads:
		for i: int in range(road.size()-1):
			var a: Vector2=road[i]
			var b: Vector2=road[i+1]
			var t: float=clampf((point-a).dot(b-a)/maxf((b-a).length_squared(),.01),0,1)
			distance=minf(distance,point.distance_to(a+(b-a)*t))
	return distance

func _place_group(entries: Array, points: Array[Vector3], height: float, label: String) -> void:
	if entries.is_empty(): return
	for species: int in range(entries.size()):
		var entry: Variant=entries[species]
		var path: String=str(entry.get("path","")) if entry is Dictionary else str(entry)
		var chunks: Dictionary={}
		for index: int in range(points.size()):
			if index%entries.size()!=species: continue
			var point: Vector3=points[index]
			var key: Vector2i=Vector2i(floori(point.x/CHUNK_SIZE),floori(point.z/CHUNK_SIZE))
			if not chunks.has(key): chunks[key]=[]
			chunks[key].append(point)
		for key: Vector2i in chunks:
			var group: Array[Vector3]=[]
			group.assign(chunks[key])
			_instance_species(path,group,height,label)

func _collect_meshes(node: Node, transform: Transform3D, result: Array[Dictionary]) -> void:
	var local: Transform3D=transform
	if node is Node3D: local=transform*(node as Node3D).transform
	if node is MeshInstance3D:
		var item: MeshInstance3D=node as MeshInstance3D
		if item.mesh != null: result.append({"mesh":item.mesh,"transform":local,"material":item.material_override})
	for child: Node in node.get_children(): _collect_meshes(child,local,result)

func _instance_species(path: String, points: Array[Vector3], desired_height: float, label: String) -> void:
	if not ResourceLoader.exists(path) or points.is_empty(): return
	var packed: PackedScene=load(path) as PackedScene
	if packed==null: return
	var source: Node=packed.instantiate()
	var parts: Array[Dictionary]=[]
	_collect_meshes(source,Transform3D.IDENTITY,parts)
	var bounds:=AABB()
	var has_bounds: bool=false
	for part: Dictionary in parts:
		var transformed: AABB=(part["transform"] as Transform3D)*(part["mesh"] as Mesh).get_aabb()
		bounds=bounds.merge(transformed) if has_bounds else transformed
		has_bounds=true
	var scaling: float=desired_height/maxf(bounds.size.y,.1)
	for part: Dictionary in parts:
		var mm:=MultiMesh.new()
		mm.transform_format=MultiMesh.TRANSFORM_3D
		mm.mesh=_palette(part["mesh"])
		mm.instance_count=points.size()
		for index: int in range(points.size()):
			var variation: float=.87+float(index%7)*.038
			var basis:=Basis(Vector3.UP,float(index)*2.39996).scaled(Vector3.ONE*scaling*variation)
			var anchor: Vector3=points[index]-basis*Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
			mm.set_instance_transform(index,Transform3D(basis,anchor)*(part["transform"] as Transform3D))
		var instance:=MultiMeshInstance3D.new()
		instance.name=label+"Batch"
		instance.multimesh=mm
		instance.visibility_range_end=580.0
		if part["material"]!=null: instance.material_override=part["material"]
		_root.add_child(instance)
	source.free()

func _palette(original: Mesh) -> Mesh:
	var key: int=original.get_instance_id()
	if _mesh_cache.has(key): return _mesh_cache[key]
	var mesh: Mesh=original.duplicate()
	for surface: int in range(mesh.get_surface_count()):
		var source: Material=mesh.surface_get_material(surface)
		if not source is StandardMaterial3D: continue
		var material: StandardMaterial3D=source.duplicate()
		# Preserve textured leaf cutouts. Only the original solid-color CC0
		# fallback shrubs and rocks need palette translation.
		if material.albedo_texture==null:
			match source.resource_name:
				"Green": material.albedo_color=Color("78a847")
				"DarkGreen": material.albedo_color=Color("557d3b")
				"White": material.albedo_color=Color("d6d4b5")
				"Black": material.albedo_color=Color("4e5949")
				"Wood": material.albedo_color=Color("806648")
				"Rock": material.albedo_color=Color("a4a68d")
		material.roughness=.94
		mesh.surface_set_material(surface,material)
	_mesh_cache[key]=mesh
	return mesh
