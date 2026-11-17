extends SceneTree
## Read-only validation of actual demo geography, generated facilities and snapshot.
## Run: Godot --headless --path demos/land-art-3d --script res://tools/check_coast_v2.gd
## This is local visual-demo evidence, not a production-core or mobile validation.

const SEEDS: Array[int] = [714, 18031, 29143]
const REQUIRED_BIOMES: Array[String] = ["swamp", "mountain", "sea_cliff", "river", "sand"]
const VEHICLE_IDS: Array[String] = ["cas_landing_craft", "cas_heavy_landing_craft", "cas_fast_assault_boat", "cas_amphibious_apc", "cas_tank_cc0", "cas_self_propelled_artillery", "cas_transport_helicopter", "cas_attack_helicopter"]
const OUTPUT: String = "res://../../artifacts/coast-v2-20261116/geography-validation.json"
var report: Dictionary = {}
var failures: Array[String] = []
var warnings: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(name: String, passed: bool, detail: Variant = null) -> void:
	report["checks"].append({"name":name,"passed":passed,"detail":detail})
	if not passed: failures.append(name)

func _run() -> void:
	report = {"generated_utc":Time.get_datetime_string_from_system(true),"engine":Engine.get_version_info(),
		"scope":"visual_demo; no production-core, account, combat or mobile performance assertion",
		"method":"Invoke real geography and real building factories; sample actual rendered triangle surface; load actual saved editable scene. No copied height-generation formula.",
		"seeds":SEEDS,"checks":[],"geography":[],"facility_layouts":[],"source_sha256":{}}
	for source: String in ["tools/check_coast_v2.gd","scripts/coastal_geography.gd","scripts/coast_demo.gd","scripts/coastal_architecture.gd","scripts/home_architecture.gd","scripts/wasteland_architecture.gd","assets/vehicles3d/vehicle-manifest.json"]:
		report["source_sha256"][source]=FileAccess.get_sha256("res://"+source)
	for seed_value: int in SEEDS:
		_validate_geography(seed_value)
		_validate_facilities(seed_value)
	_validate_vehicles()
	await _validate_snapshot()
	var changed_sources: Array[String]=[]
	for source: String in report["source_sha256"]:
		if FileAccess.get_sha256("res://"+source)!=str(report["source_sha256"][source]): changed_sources.append(source)
	_check("validation_sources_unchanged_during_run",changed_sources.is_empty(),changed_sources)
	report["failures"]=failures
	report["warnings"]=warnings
	report["passed"]=failures.is_empty()
	report["status"]="failed" if not failures.is_empty() else "passed_with_review" if not warnings.is_empty() else "passed"
	report["not_verified"]=["GPU appearance and wave motion", "native/WASM cross-platform determinism", "authoritative landing, path, combat and construction rules", "Android performance and thermal/memory behavior"]
	var output_path: String=ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var file: FileAccess=FileAccess.open(output_path,FileAccess.WRITE)
	if file == null:
		push_error("Cannot write validation report: "+output_path)
		quit(2)
		return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("COAST_V2_VALIDATION "+JSON.stringify({"passed":report["passed"],"failures":failures,"warnings":warnings,"output":output_path}))
	quit(0 if failures.is_empty() else 1)

func _validate_geography(seed_value: int) -> void:
	var script: Script=load("res://scripts/coastal_geography.gd")
	var a: RefCounted=script.new(seed_value)
	var b: RefCounted=script.new(seed_value)
	var header: Dictionary=a.call("snapshot_header")
	_check("seed_%d_metric_scope"%seed_value,header.get("units")=="metres" and header.get("authority_scope")=="visual_demo",header)
	var sequence_a: Array=[]
	var sequence_b: Array=[]
	# Off-grid probes and a different traversal order catch accidental RNG state.
	for index: int in range(193):
		var x: float=-319.37+fmod(index*71.913,638.0)
		var z: float=-299.81+fmod(index*103.127,618.0)
		sequence_a.append([a.call("height_at",x,z),a.call("biome_at",x,z),a.call("landing_at",x,z)])
	for index: int in range(192,-1,-1):
		var x: float=-319.37+fmod(index*71.913,638.0)
		var z: float=-299.81+fmod(index*103.127,618.0)
		sequence_b.push_front([b.call("height_at",x,z),b.call("biome_at",x,z),b.call("landing_at",x,z)])
	_check("seed_%d_repeat_and_order_determinism"%seed_value,sequence_a==sequence_b,{"probes":sequence_a.size(),"sha256":JSON.stringify(sequence_a).sha256_text()})
	var biomes: Dictionary={}
	var first_sample: Dictionary={}
	var total: int=0
	var land_samples: int=0
	var ordinary: int=0
	var heavy: int=0
	var amphibious: int=0
	var heavy_outside_ordinary: int=0
	var cliff_allowed: int=0
	var water_or_deep_inland_allowed: int=0
	var maximum_allowed_slope: float=0.0
	for zi: int in range(-60,61):
		for xi: int in range(-60,61):
			var x: float=xi*6.0
			var z: float=zi*6.0
			var biome: String=a.call("biome_at",x,z)
			biomes[biome]=int(biomes.get(biome,0))+1
			if not first_sample.has(biome): first_sample[biome]=[x,z,a.call("height_at",x,z)]
			var normal_allowed: bool=a.call("landing_at",x,z,"ordinary_boat").get("allowed",false)
			var heavy_allowed: bool=a.call("landing_at",x,z,"heavy_boat").get("allowed",false)
			var amphibious_allowed: bool=a.call("landing_at",x,z,"amphibious").get("allowed",false)
			ordinary+=int(normal_allowed)
			heavy+=int(heavy_allowed)
			amphibious+=int(amphibious_allowed)
			heavy_outside_ordinary+=int(heavy_allowed and not normal_allowed)
			cliff_allowed+=int(biome=="sea_cliff" and normal_allowed)
			if normal_allowed:
				var measured_slope: float=Vector2((float(a.call("height_at",x+1.0,z))-float(a.call("height_at",x-1.0,z)))*.5,(float(a.call("height_at",x,z+1.0))-float(a.call("height_at",x,z-1.0)))*.5).length()
				maximum_allowed_slope=maxf(maximum_allowed_slope,measured_slope)
				water_or_deep_inland_allowed+=int(biome=="sea" or z>230.0)
			land_samples+=int(biome!="sea")
			total+=1
	for biome: String in REQUIRED_BIOMES:
		_check("seed_%d_has_%s"%[seed_value,biome],int(biomes.get(biome,0))>0,first_sample.get(biome))
	_check("seed_%d_landing_is_local_and_nonempty"%seed_value,ordinary>0 and ordinary<float(land_samples)*.12 and water_or_deep_inland_allowed==0,{"ordinary":ordinary,"land_samples":land_samples,"whole_grid":total})
	_check("seed_%d_heavy_landing_subset"%seed_value,heavy>0 and heavy<=ordinary and heavy_outside_ordinary==0,{"heavy":heavy,"ordinary":ordinary,"outside":heavy_outside_ordinary})
	_check("seed_%d_no_ordinary_cliff_unload"%seed_value,cliff_allowed==0,{"cliff_samples":biomes.get("sea_cliff",0),"cliff_allowed":cliff_allowed})
	report["geography"].append({"seed":seed_value,"header":header,"biome_counts_6m_grid":biomes,"first_biome_samples_m":first_sample,"ordinary_landing_samples":ordinary,"heavy_landing_samples":heavy,"amphibious_landing_samples":amphibious,"ordinary_max_independent_2m_slope":maximum_allowed_slope,"sample_fingerprint":JSON.stringify(sequence_a).sha256_text()})

func _validate_facilities(seed_value: int) -> void:
	# Keep the live Demo off-tree: _ready never runs, so it cannot save/capture.
	var sampler: Node3D=load("res://scripts/coast_demo.gd").new()
	sampler.set("terrain_seed",seed_value)
	sampler.call("_setup_noise")
	var group: Node3D=Node3D.new()
	group.name="ValidationFacilities"
	root.add_child(group)
	var factory_counts: Dictionary={}
	var wasteland_ids: Dictionary={}
	for path: String in ["coastal_architecture.gd","home_architecture.gd","wasteland_architecture.gd"]:
		var factory: Node3D=load("res://scripts/"+path).new()
		group.add_child(factory)
		factory.call("build",Callable(sampler,"render_height_at"))
		var factory_buildings: Array[Node]=[]
		_collect_metadata(factory,"footprint_m",factory_buildings)
		factory_counts[path]=factory_buildings.size()
		if path=="wasteland_architecture.gd":
			for building: Node in factory_buildings:
				wasteland_ids[str(building.get_meta("facility_id","unknown"))]=true
	var buildings: Array[Node]=[]
	_collect_metadata(group,"footprint_m",buildings)
	_check("seed_%d_new_wasteland_facility_instances_33"%seed_value,int(factory_counts.get("wasteland_architecture.gd",0))==33,{"instances":factory_counts.get("wasteland_architecture.gd",0),"unique_types":wasteland_ids.size()})
	_check("seed_%d_actual_whole_sample_facility_instances_51"%seed_value,buildings.size()==51,factory_counts)
	var rows: Array=[]
	var severe: Array=[]
	var needs_review: Array=[]
	for node: Node in buildings:
		var building: Node3D=node as Node3D
		var footprint: Vector2=building.get_meta("footprint_m")
		var low: float=INF
		var high: float=-INF
		var land_points: int=0
		for zi: int in range(5):
			for xi: int in range(5):
				var local:=Vector3((xi/4.0-.5)*footprint.x,0,(zi/4.0-.5)*footprint.y)
				var world: Vector3=building.global_transform*local
				var elevation: float=sampler.call("render_height_at",world.x,world.z)
				low=minf(low,elevation)
				high=maxf(high,elevation)
				land_points+=int(elevation>=0.0)
		var id: String=str(building.get_meta("facility_id",str(building.name)))
		var water_structure: bool=id in ["submerged_tower","relic_machine_room","TimberPier"]
		var relief: float=high-low
		var maximum_clearance: float=building.global_position.y-low
		var upper_clearance: float=building.global_position.y-high
		var status: String="water_structure_separate_review" if water_structure else "ok"
		if not water_structure and (relief>1.5 or maximum_clearance>1.8 or upper_clearance<-.25):
			status="review"
			needs_review.append(id)
		if not water_structure and (relief>3.0 or maximum_clearance>3.3 or upper_clearance<-.75):
			status="severe"
			severe.append(id)
		rows.append({"id":id,"node":str(building.name),"position_m":[building.global_position.x,building.global_position.y,building.global_position.z],"footprint_m":[footprint.x,footprint.y],"terrain_min_m":low,"terrain_max_m":high,"footprint_relief_m":relief,"root_above_lowest_m":maximum_clearance,"root_above_highest_m":upper_clearance,"land_sample_count":land_points,"samples":25,"status":status})
	_check("seed_%d_no_severe_facility_grounding"%seed_value,severe.is_empty(),severe)
	if not needs_review.is_empty(): warnings.append("seed_%d_facility_grounding_review: %s"%[seed_value,", ".join(needs_review)])
	report["facility_layouts"].append({"seed":seed_value,"method":"Actual factories + 5x5 rotated footprint samples of actual render_height_at, not generator reimplementation","count":buildings.size(),"factory_instance_counts":factory_counts,"wasteland_unique_types":wasteland_ids.keys(),"review_relief_threshold_m":1.5,"severe_relief_threshold_m":3.0,"severe":severe,"review":needs_review,"facilities":rows})
	group.free()
	sampler.free()

func _collect_metadata(node: Node, key: String, matches: Array[Node]) -> void:
	if node.has_meta(key): matches.append(node)
	for child: Node in node.get_children(): _collect_metadata(child,key,matches)

func _mesh_count(node: Node) -> int:
	var count: int=int(node is MeshInstance3D and str(node.name)!="ArtWake")
	for child: Node in node.get_children(): count+=_mesh_count(child)
	return count

func _validate_vehicles() -> void:
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/vehicles3d/vehicle-manifest.json"))
	var models: Array=raw.get("models",[]) if raw is Dictionary else []
	_check("vehicle_manifest_8_types",models.size()==8,models.size())
	var measured: Array=[]
	for id: String in VEHICLE_IDS:
		var entries: Array=models.filter(func(row: Dictionary) -> bool:return str(row.get("id",""))==id)
		var path: String="res://assets/vehicles3d/"+id+".glb"
		var packed: PackedScene=load(path) as PackedScene
		var valid: bool=entries.size()==1 and packed!=null
		var model: Node=packed.instantiate() if packed!=null else null
		var actual_meshes: int=_mesh_count(model) if model!=null else 0
		var sha: String=FileAccess.get_sha256(path)
		if entries.size()==1:
			valid=valid and sha==str(entries[0].get("sha256","")) and entries[0].get("forward_godot")=="-Z" and actual_meshes==int(entries[0].get("mesh_nodes",-1))
		_check("vehicle_%s_import_manifest_hash"%id,valid,{"actual_meshes":actual_meshes,"sha256":sha})
		measured.append({"id":id,"actual_meshes":actual_meshes,"sha256":sha,"passed":valid})
		if model!=null: model.free()
	report["vehicles"]=measured

func _validate_snapshot() -> void:
	await process_frame
	var before: int=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var path: String="res://scenes/editable_coast.scn"
	var packed: PackedScene=load(path) as PackedScene
	_check("editable_snapshot_loads",packed!=null,FileAccess.get_sha256(path))
	if packed==null:return
	var instance: Node=packed.instantiate()
	root.add_child(instance)
	var pending: Array[Node]=[instance]
	var owners_missing: Array[String]=[]
	var nested_imports: Array[String]=[]
	var live_scripts: Array[String]=[]
	var hidden_critical_nodes: Array[String]=[]
	var detail_roots: Dictionary={}
	var detail_names: Array[String]=["EditableHarborVillage","HomeFacilityArtPrototypes","SalvagedWastelandDistrict","ThreeDimensionalVehicles","IdentityBoundCharacters","HomeCharacterScaleReference","NaturalCanopyClusters"]
	var anchors: Dictionary={}
	var nodes: int=0
	var mesh_nodes: int=0
	while not pending.is_empty():
		var node: Node=pending.pop_back()
		nodes+=1
		mesh_nodes+=int(node is MeshInstance3D)
		if node!=instance and node.owner!=instance: owners_missing.append(str(instance.get_path_to(node)))
		if node!=instance and not node.scene_file_path.is_empty(): nested_imports.append(str(instance.get_path_to(node)))
		if node.get_script()!=null: live_scripts.append(str(instance.get_path_to(node)))
		if node is Node3D:
			var spatial: Node3D=node as Node3D
			if str(node.name) in detail_names:detail_roots[str(node.name)]={"visible":spatial.visible,"visible_in_tree":spatial.is_visible_in_tree()}
			if (node.has_meta("footprint_m") or str(node.name) in VEHICLE_IDS or str(node.name) in detail_names or str(node.name)=="ContinuousTerrain") and not spatial.is_visible_in_tree():hidden_critical_nodes.append(str(instance.get_path_to(node)))
		if str(node.name) in VEHICLE_IDS:
			var id: String=str(node.name)
			if not anchors.has(id):anchors[id]=[]
			anchors[id].append({"path":str(instance.get_path_to(node)),"mesh_count_excluding_wake":_mesh_count(node)})
		for child: Node in node.get_children():pending.append(child)
	_check("editable_snapshot_descendants_owned",owners_missing.is_empty(),owners_missing)
	_check("editable_snapshot_flat_no_nested_glb_instance",nested_imports.is_empty(),nested_imports)
	_check("editable_snapshot_no_live_generators",live_scripts.is_empty(),live_scripts)
	_check("editable_snapshot_detail_groups_restored_visible",hidden_critical_nodes.is_empty() and detail_roots.size()==detail_names.size(),{"groups":detail_roots,"hidden_critical_nodes":hidden_critical_nodes})
	var terrain_node: MeshInstance3D=instance.find_child("ContinuousTerrain",true,false) as MeshInstance3D
	var terrain_probes: int=0
	var maximum_height_error: float=0.0
	var geography: RefCounted=load("res://scripts/coastal_geography.gd").new(714)
	if terrain_node!=null and terrain_node.mesh!=null:
		for surface: int in range(terrain_node.mesh.get_surface_count()):
			var vertices: PackedVector3Array=terrain_node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for index: int in range(0,vertices.size(),37):
				var point: Vector3=terrain_node.global_transform*vertices[index]
				maximum_height_error=maxf(maximum_height_error,absf(point.y-float(geography.call("height_at",point.x,point.z))))
				terrain_probes+=1
	_check("editable_snapshot_ground_matches_current_seed714_geography",terrain_probes>100 and maximum_height_error<.002,{"probes":terrain_probes,"max_vertex_error_m":maximum_height_error,"expected_seed":714,"tolerance_m":.002})
	var duplicate_or_missing: Array=[]
	for model: Dictionary in report["vehicles"]:
		var id: String=str(model["id"])
		var found: Array=anchors.get(id,[])
		if found.size()!=1 or (found.size()==1 and int(found[0]["mesh_count_excluding_wake"])!=int(model["actual_meshes"])): duplicate_or_missing.append({"id":id,"expected_meshes":model["actual_meshes"],"anchors":found})
	_check("editable_snapshot_one_actual_vehicle_each_no_duplicate_glb_geometry",duplicate_or_missing.is_empty(),duplicate_or_missing)
	instance.free()
	await process_frame
	await process_frame
	var after: int=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check("editable_snapshot_load_free_no_added_orphan_nodes",after<=before,{"before":before,"after":after,"delta":after-before})
	report["editable_snapshot"]={"path":path,"sha256":FileAccess.get_sha256(path),"file_modified_unix":FileAccess.get_modified_time(path),"nodes":nodes,"mesh_nodes":mesh_nodes,"vehicle_anchors":anchors,"nested_imports":nested_imports,"unowned_descendants":owners_missing,"live_scripts":live_scripts,"detail_roots":detail_roots,"hidden_critical_nodes":hidden_critical_nodes,"orphan_nodes_before":before,"orphan_nodes_after":after,"terrain_vertex_probes":terrain_probes,"terrain_max_error_to_current_seed714_m":maximum_height_error}
