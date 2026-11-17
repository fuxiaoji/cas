extends SceneTree
## Narrow art-route check against actual built harbor meshes and platform metadata.
const PHASE_STEPS: int = 720
const TURRET_STEPS: int = 9
const MINIMUM_GAP_M: float = 1.0

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	var geography: RefCounted = load("res://scripts/coastal_geography.gd").new(714)
	var architecture := Node3D.new()
	architecture.set_script(load("res://scripts/coastal_architecture.gd"))
	root.add_child(architecture)
	architecture.call("build",Callable(geography,"height_at"))
	var buildings: Array[Dictionary] = []
	for building: Node3D in architecture.get("buildings"):
		var geometry: AABB = _bounds(building)
		var mesh_rectangle := Rect2(Vector2(geometry.position.x,geometry.position.z),Vector2(geometry.size.x,geometry.size.z))
		var footprint: Vector2 = building.get_meta("footprint_m")
		var registered: AABB = building.global_transform*AABB(Vector3(-footprint.x*.5,0,-footprint.y*.5),Vector3(footprint.x,0,footprint.y))
		var platform_rectangle := Rect2(Vector2(registered.position.x,registered.position.z),Vector2(registered.size.x,registered.size.z))
		var checked: Rect2 = mesh_rectangle.merge(platform_rectangle)
		buildings.append({"name":str(building.name),"actual_mesh_aabb_xz":_rectangle_array(mesh_rectangle),
			"registered_platform_aabb_xz":_rectangle_array(platform_rectangle),"checked_aabb_xz":_rectangle_array(checked),"rectangle":checked})
	var layer := Node3D.new()
	layer.set_script(load("res://scripts/coastal_vehicles.gd"))
	root.add_child(layer)
	layer.call("build",Callable(geography,"height_at"))
	layer.set_process(false)
	var specifications: Array = (layer.get_script() as Script).get_script_constant_map()["SHOWCASE"]
	var baseline: Dictionary = {
		"cas_amphibious_apc":{"center":Vector2(-14,-23),"radius":Vector2(2.5,9)},
		"cas_tank_cc0":{"center":Vector2(5,-9),"radius":Vector2(2.4,7)},
		"cas_self_propelled_artillery":{"center":Vector2(28,-18),"radius":Vector2(2,7)}}
	var result: Dictionary = {"date":"2026-11-16","scope":"isolated art-demo harbor footprint routes, not production navigation or collision authority",
		"vehicles_module_sha256":FileAccess.get_sha256("res://scripts/coastal_vehicles.gd"),
		"architecture_sha256":FileAccess.get_sha256("res://scripts/coastal_architecture.gd"),
		"geography_sha256":FileAccess.get_sha256("res://scripts/coastal_geography.gd"),
		"phase_steps":PHASE_STEPS,"phase_step_degrees":.5,"turret_sweep_radians":[-.28,.28],"turret_samples_per_phase":TURRET_STEPS,
		"method":"Actual imported GLB MeshInstance3D global AABB, including gun barrels; full 360-degree motion and every turret scan angle sample. Compare XZ union against actual built harbor mesh AABB plus registered platform extents. At least 1m planar clearance.",
		"minimum_required_gap_m":MINIMUM_GAP_M,"buildings":[],"before":[],"after":[]}
	for building: Dictionary in buildings:
		var row: Dictionary = building.duplicate()
		row.erase("rectangle")
		(result["buildings"] as Array).append(row)
	var passed: bool = true
	for specification: Dictionary in specifications:
		var id: String = str(specification["id"])
		if not baseline.has(id): continue
		var vehicle: Node3D = layer.get_node(NodePath(id)) as Node3D
		var before: Dictionary = specification.duplicate()
		before.merge(baseline[id],true)
		(result["before"] as Array).append(_check_route(before,vehicle,buildings))
		var report: Dictionary = _check_route(specification,vehicle,buildings)
		(result["after"] as Array).append(report)
		passed = passed and bool(report["passed"])
	result["passed"] = passed
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/vehicles3d/vehicle-manifest.json"))
	var hashes: Dictionary = {}
	for entry: Dictionary in manifest["models"]:
		var path: String = "res://assets/vehicles3d/"+str(entry["id"])+".glb"
		assert(FileAccess.get_sha256(path)==str(entry["sha256"]),"Vehicle GLB changed: "+str(entry["id"]))
		hashes[str(entry["id"])] = str(entry["sha256"])
	result["unchanged_glb_sha256"] = hashes
	var output: FileAccess = FileAccess.open("res://assets/vehicles3d/vehicle-land-route-verification.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(result,"\t"))
	output.close()
	print("VEHICLE_LAND_ROUTE_CHECK "+JSON.stringify(result))
	layer.queue_free()
	architecture.queue_free()
	await process_frame
	quit(0 if passed else 1)

func _check_route(specification: Dictionary, vehicle: Node3D, buildings: Array[Dictionary]) -> Dictionary:
	var center: Vector2 = specification["center"]
	var radius: Vector2 = specification["radius"]
	var model: Node3D = vehicle.get_node("EditableGLB") as Node3D
	var turret: Node3D = model.find_child("Turret",true,false) as Node3D
	var result: Dictionary = {"id":str(specification["id"]),"center_m":[center.x,center.y],"radius_m":[radius.x,radius.y],
		"minimum_gap_m":INF,"invalid_body_samples":0,"total_pose_samples":PHASE_STEPS*TURRET_STEPS}
	for phase_index: int in range(PHASE_STEPS):
		var phase: float = float(phase_index)*TAU/float(PHASE_STEPS)
		var point: Vector2 = center+Vector2(cos(phase)*radius.x,sin(phase)*radius.y)
		var velocity := Vector2(-sin(phase)*radius.x,cos(phase)*radius.y)
		vehicle.position = Vector3(point.x,0,point.y)
		vehicle.rotation = Vector3(0,atan2(-velocity.x,-velocity.y),0)
		for angle_index: int in range(TURRET_STEPS):
			var angle: float = lerpf(-.28,.28,float(angle_index)/float(TURRET_STEPS-1))
			if turret != null: turret.rotation.y = angle
			var geometry: AABB = _bounds(model)
			var body := Rect2(Vector2(geometry.position.x,geometry.position.z),Vector2(geometry.size.x,geometry.size.z))
			var invalid: bool = false
			for building: Dictionary in buildings:
				var obstacle: Rect2 = building["rectangle"]
				var dx: float = maxf(0,maxf(obstacle.position.x-body.end.x,body.position.x-obstacle.end.x))
				var dz: float = maxf(0,maxf(obstacle.position.y-body.end.y,body.position.y-obstacle.end.y))
				var distance: float = Vector2(dx,dz).length()
				if distance < float(result["minimum_gap_m"]):
					result["minimum_gap_m"] = distance
					result["nearest_building"] = str(building["name"])
					result["worst_phase_degrees"] = phase_index*.5
					result["worst_turret_radians"] = angle
					result["worst_actual_body_aabb_xz"] = _rectangle_array(body)
				if distance < MINIMUM_GAP_M: invalid = true
			if invalid: result["invalid_body_samples"] = int(result["invalid_body_samples"])+1
	result["passed"] = int(result["invalid_body_samples"])==0
	return result

func _bounds(node: Node3D) -> AABB:
	var result := AABB()
	var initialized: bool = false
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var item: Node = pending.pop_back()
		if item is MeshInstance3D:
			var mesh: MeshInstance3D = item as MeshInstance3D
			var box: AABB = mesh.global_transform*mesh.get_aabb()
			result = result.merge(box) if initialized else box
			initialized = true
		for child: Node in item.get_children(): pending.append(child)
	return result

func _rectangle_array(rectangle: Rect2) -> Array[float]:
	return [rectangle.position.x,rectangle.position.y,rectangle.end.x,rectangle.end.y]
