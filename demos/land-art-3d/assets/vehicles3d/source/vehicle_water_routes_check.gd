extends SceneTree
## Art-demo navigation clearance only, not a production hull/path collision test.
const PHASE_STEPS: int = 720
const BODY_SAMPLE_SPACING_M: float = 1.5
const REQUIRED_KEEL_CLEARANCE_M: float = .75
var geography: RefCounted

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	geography = load("res://scripts/coastal_geography.gd").new(714)
	var script: Script = load("res://scripts/coastal_vehicles.gd") as Script
	var specifications: Array = script.get_script_constant_map()["SHOWCASE"]
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/vehicles3d/vehicle-manifest.json"))
	var baseline: Dictionary = {
		"cas_landing_craft":{"center":Vector2(-28,-64),"radius":Vector2(9,5)},
		"cas_heavy_landing_craft":{"center":Vector2(-62,-80),"radius":Vector2(12,6)},
		"cas_fast_assault_boat":{"center":Vector2(10,-72),"radius":Vector2(12,7)}}
	var result: Dictionary = {"date":"2026-11-16","scope":"isolated art-demo routes, seed714; not production navigation authority",
		"geography_sha256":FileAccess.get_sha256("res://scripts/coastal_geography.gd"),
		"vehicles_module_sha256":FileAccess.get_sha256("res://scripts/coastal_vehicles.gd"),
		"geography":geography.call("snapshot_header"),"phase_steps":PHASE_STEPS,"phase_step_degrees":.5,
		"method":"Full 360-degree route, complete rest model AABB footprint (four corners and <=1.5m interior grid), 0.15m horizontal allowance, both source height_at and rendered terrain triangles. Conservative keel includes all bob/roll/pitch extrema independent of phase.",
		"minimum_required_keel_clearance_m":REQUIRED_KEEL_CLEARANCE_M,"before":[],"after":[]}
	var passed: bool = true
	for specification: Dictionary in specifications:
		if not bool(specification["water"]): continue
		var id: String = str(specification["id"])
		var geometry: Dictionary = {}
		for entry: Dictionary in manifest["models"]:
			if str(entry["id"]) == id: geometry = entry
		assert(not geometry.is_empty())
		var old_specification: Dictionary = specification.duplicate()
		old_specification.merge(baseline[id],true)
		(result["before"] as Array).append(_check_route(old_specification,geometry))
		var report: Dictionary = _check_route(specification,geometry)
		(result["after"] as Array).append(report)
		passed = passed and bool(report["passed"])
	result["passed"] = passed
	var path: String = "res://assets/vehicles3d/vehicle-water-route-verification.json"
	var output: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	output.store_string(JSON.stringify(result,"\t"))
	output.close()
	print("VEHICLE_WATER_ROUTE_CHECK "+JSON.stringify(result))
	quit(0 if passed else 1)

func _check_route(specification: Dictionary, geometry: Dictionary) -> Dictionary:
	var center: Vector2 = specification["center"]
	var radius: Vector2 = specification["radius"]
	var low: Array = geometry["godot_minimum_m"]
	var high: Array = geometry["godot_maximum_m"]
	var x0: float = float(low[0])-.15
	var x1: float = float(high[0])+.15
	var z0: float = float(low[2])-.15
	var z1: float = float(high[2])+.15
	var columns: int = ceili((x1-x0)/BODY_SAMPLE_SPACING_M)
	var rows: int = ceili((z1-z0)/BODY_SAMPLE_SPACING_M)
	var result: Dictionary = {"id":str(specification["id"]),"center_m":[center.x,center.y],"radius_m":[radius.x,radius.y],
		"samples_per_phase":(columns+1)*(rows+1),"minimum_keel_clearance_m":INF,"minimum_water_depth_m":INF,
		"minimum_seaward_distance_proxy_m":INF,"invalid_samples":0,"worst_world_point":[]}
	for phase_index: int in range(PHASE_STEPS):
		var phase: float = float(phase_index)*TAU/float(PHASE_STEPS)
		var point: Vector2 = center+Vector2(cos(phase)*radius.x,sin(phase)*radius.y)
		var velocity := Vector2(-sin(phase)*radius.x,cos(phase)*radius.y)
		var yaw := Basis(Vector3.UP,atan2(-velocity.x,-velocity.y))
		for row: int in range(rows+1):
			for column: int in range(columns+1):
				var local := Vector3(lerpf(x0,x1,float(column)/float(columns)),0,lerpf(z0,z1,float(row)/float(rows)))
				var world: Vector3 = yaw*local+Vector3(point.x,0,point.y)
				var true_bed: float = float(geography.call("height_at",world.x,world.z))
				var render_bed: float = _render_height_at(world.x,world.z)
				var bed: float = maxf(true_bed,render_bed)
				var sea_distance: float = -float(geography.call("land_distance",world.x,world.z))
				# Root mean y=.12, bob amplitude .045, roll .012 and pitch .009.
				# Additional .015m covers second-order tilt and rounding terms.
				var keel: float = .12-.045+float(low[1])-absf(local.x)*sin(.012)-absf(local.z)*sin(.009)-.015
				var clearance: float = keel-bed
				if clearance < float(result["minimum_keel_clearance_m"]):
					result["minimum_keel_clearance_m"] = clearance
					result["worst_world_point"] = [world.x,world.z]
					result["worst_phase_degrees"] = float(phase_index)*.5
					result["highest_bed_under_hull_m"] = bed
				result["minimum_water_depth_m"] = minf(float(result["minimum_water_depth_m"]),.09-bed)
				result["minimum_seaward_distance_proxy_m"] = minf(float(result["minimum_seaward_distance_proxy_m"]),sea_distance)
				if sea_distance<=0 or clearance<REQUIRED_KEEL_CLEARANCE_M: result["invalid_samples"] = int(result["invalid_samples"])+1
	result["total_body_samples"] = PHASE_STEPS*(columns+1)*(rows+1)
	result["passed"] = int(result["invalid_samples"])==0
	return result

func _render_height_at(x: float,z: float) -> float:
	# Same triangle interpolation used by coast_demo render_height_at. Reading
	# geography directly also avoids loading/changing the main art scene.
	const EXTENT: float = 360.0
	const GRID: int = 256
	var step: float = EXTENT*2.0/GRID
	var grid: Vector2 = (Vector2(x,z)+Vector2.ONE*EXTENT)/step
	var col: int = clampi(floori(grid.x),0,GRID-1)
	var row: int = clampi(floori(grid.y),0,GRID-1)
	var u: float = clampf(grid.x-col,0,1)
	var v: float = clampf(grid.y-row,0,1)
	var x0: float = -EXTENT+col*step
	var z0: float = -EXTENT+row*step
	if u+v<=1:
		var h: float = float(geography.call("height_at",x0,z0))
		return h+(float(geography.call("height_at",x0+step,z0))-h)*u+(float(geography.call("height_at",x0,z0+step))-h)*v
	var h: float = float(geography.call("height_at",x0+step,z0+step))
	return h+(float(geography.call("height_at",x0,z0+step))-h)*(1-u)+(float(geography.call("height_at",x0+step,z0))-h)*(1-v)
