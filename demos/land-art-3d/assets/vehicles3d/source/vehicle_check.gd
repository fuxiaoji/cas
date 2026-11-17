extends SceneTree

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	var layer := Node3D.new()
	layer.set_script(load("res://scripts/coastal_vehicles.gd"))
	root.add_child(layer)
	layer.build(func(_x: float, _z: float) -> float: return 2.0)
	layer.set_process(false)
	var report: Array[Dictionary] = []
	var manifest_path: String = "res://assets/vehicles3d/vehicle-manifest.json"
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	for child: Node3D in layer.get_children():
		assert(child.get_node_or_null("EditableGLB") != null)
		var model: Node3D = child.get_node("EditableGLB") as Node3D
		var meshes: int = _count_meshes(model)
		assert(meshes > 0)
		var old: Vector3 = child.position
		layer.set_demo_time(0.1)
		var movement: Vector3 = child.position - old
		movement.y = 0.0
		var forward: Vector3 = -child.basis.z
		forward.y = 0.0
		var facing_dot: float = forward.normalized().dot(movement.normalized())
		assert(facing_dot > 0.99)
		var old_transform: Transform3D = child.transform
		child.transform = Transform3D.IDENTITY
		var articulated: Array[Node3D] = []
		var rotations: Array[Vector3] = []
		for part_name: String in ["Turret","Ramp","MainRotor","TailRotor","ChinGun"]:
			var part: Node3D = model.find_child(part_name,true,false) as Node3D
			if part == null: continue
			articulated.append(part)
			rotations.append(part.rotation)
			part.rotation = Vector3.ZERO
		var geometry: Dictionary = {"mesh_nodes":0,"surfaces":0,"triangles":0,"first":true,"bounds":AABB()}
		_measure(model, geometry)
		for index: int in range(articulated.size()): articulated[index].rotation = rotations[index]
		child.transform = old_transform
		var bounds: AABB = geometry["bounds"]
		var row: Dictionary = {"id":str(child.name), "mesh_nodes":meshes, "heading_motion_dot":facing_dot,
			"godot_minimum_m":[bounds.position.x,bounds.position.y,bounds.position.z],
			"godot_maximum_m":[bounds.end.x,bounds.end.y,bounds.end.z],
			"godot_size_m":[bounds.size.x,bounds.size.y,bounds.size.z],
			"geometry_surfaces":geometry["surfaces"],"runtime_triangles":geometry["triangles"],
			"articulation_nodes_checked":articulated.size(),"asset_bytes":FileAccess.get_file_as_bytes("res://assets/vehicles3d/"+str(child.name)+".glb").size()}
		if not bool(child.get_meta("waterline_anchor")):
			assert(absf(bounds.position.y)<0.001,"Vehicle is not grounded: "+str(child.name))
		if str(child.name).contains("helicopter"):
			var rotor: Node3D = model.find_child("MainRotor",true,false) as Node3D
			assert(rotor != null)
			var angle_before: float = rotor.rotation.y
			layer.set_demo_time(.23)
			assert(absf(rotor.rotation.y-angle_before)>1.0)
			row["rotor_motion_checked"] = true
		report.append(row)
		for entry: Dictionary in manifest["models"]:
			if str(entry["id"]) != str(child.name): continue
			entry.merge(row, true)
			entry["source_blender_triangles"] = entry["triangles"]
			entry["triangles"] = row["runtime_triangles"]
			entry.erase("blender_size_m")
			entry["measurement"] = "Godot 4.7.2 imported GLB actual MeshInstance3D global AABB at identity with every articulated pivot at rest zero; sizes [width,height,length], includes antenna/rotors. Empty anchors and presentation wake excluded."
			entry["vertex_palette_array_verified"] = true
			if str(child.name) == "cas_amphibious_apc":
				entry["body_roof_height_m"] = 2.20
				entry["weapon_station_height_m"] = 2.915
				entry["antenna_tip_height_m"] = bounds.end.y
				entry["waterline_godot_y"] = 0.81
			if str(child.name) == "cas_tank_cc0":
				entry["body_roof_height_m"] = 1.361
				entry["turret_roof_height_m"] = 2.30
				entry["antenna_tip_height_m"] = bounds.end.y
		layer.set_demo_time(0.0)
	assert(report.size() == 8)
	for id: String in manifest["original_three_preserved_sha256"]:
		assert(FileAccess.get_sha256("res://assets/vehicles3d/"+id+".glb") == manifest["original_three_preserved_sha256"][id],"Original GLB changed: "+id)
	print("VEHICLE_3D_CHECK " + JSON.stringify(report))
	var file: FileAccess = FileAccess.open(manifest_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest,"\t"))
	file.close()
	layer.queue_free()
	await process_frame
	quit()

func _count_meshes(node: Node) -> int:
	var result: int = 1 if node is MeshInstance3D else 0
	for child: Node in node.get_children(): result += _count_meshes(child)
	return result

func _measure(node: Node, result: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		var box: AABB = mesh_node.global_transform * mesh_node.get_aabb()
		result["bounds"] = box if bool(result["first"]) else (result["bounds"] as AABB).merge(box)
		result["first"] = false
		result["mesh_nodes"] = int(result["mesh_nodes"]) + 1
		for surface: int in range(mesh_node.mesh.get_surface_count()):
			result["surfaces"] = int(result["surfaces"]) + 1
			var material: StandardMaterial3D = mesh_node.get_active_material(surface) as StandardMaterial3D
			assert(material != null and material.vertex_color_use_as_albedo)
			var arrays: Array = mesh_node.mesh.surface_get_arrays(surface)
			var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			assert(not colours.is_empty())
			var coloured: bool = false
			for colour: Color in colours:
				if colour.r < 0.9 or colour.g < 0.9 or colour.b < 0.9:
					coloured = true
					break
			assert(coloured)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			result["triangles"] = int(result["triangles"]) + int((indices.size() if not indices.is_empty() else vertices.size()) / 3)
	for child: Node in node.get_children(): _measure(child, result)
