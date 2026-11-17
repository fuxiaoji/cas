extends SceneTree

func _initialize() -> void:
	call_deferred("_review")

func _review() -> void:
	var report: Array[Dictionary] = []
	for filename: String in ["CommonTree_1.glb","CommonTree_3.glb","CommonTree_5.glb"]:
		var packed: PackedScene = load("res://assets/vendor/nature-refine/"+filename)
		var source: Node = packed.instantiate()
		var parts: Array[Dictionary] = []
		_collect(source,Transform3D.IDENTITY,parts)
		var box:=AABB()
		var first: bool=true
		var triangles: int=0
		var normals: bool=true
		for part: Dictionary in parts:
			var mesh: Mesh=part.mesh
			var transformed: AABB=part.transform*mesh.get_aabb()
			box=transformed if first else box.merge(transformed)
			first=false
			for index: int in range(mesh.get_surface_count()):
				var arrays: Array=mesh.surface_get_arrays(index)
				triangles+=arrays[Mesh.ARRAY_INDEX].size()/3
				normals=normals and not arrays[Mesh.ARRAY_NORMAL].is_empty()
		report.append({"model":filename,"raw_bounds_m":[box.position.x,box.position.y,box.position.z,box.size.x,box.size.y,box.size.z],"triangles":triangles,"has_normals":normals,"display_height_m":10.5,"uniform_scale":10.5/box.size.y})
		source.free()
	var receipt:=FileAccess.open("res://assets/vendor/nature-refine/model-audit.json",FileAccess.WRITE)
	receipt.store_string(JSON.stringify(report,"\t"))
	print("NATURE_MODEL_AUDIT ",JSON.stringify(report))
	quit(0)

func _collect(node: Node, transform: Transform3D, parts: Array[Dictionary]) -> void:
	var local: Transform3D=transform
	if node is Node3D: local=transform*(node as Node3D).transform
	if node is MeshInstance3D: parts.append({"mesh":node.mesh,"transform":local})
	for child: Node in node.get_children(): _collect(child,local,parts)
