extends Node3D
## Art-only 3D vehicle sample. No account, deployment, AI or combat adjudication.
## All GLB models face -Z and use metre units; all motion and headings share
## the same Node3D anchor. Infantry remain separate approved Sprite3D actors.

const MODEL_ROOT: String = "res://assets/vehicles3d/"
var _ground: Callable
var _time: float = 0.0
var _vehicles: Array[Dictionary] = []
var _palette_materials: Dictionary = {}
const SHOWCASE: Array[Dictionary] = [
	{"id":"cas_landing_craft", "center":Vector2(-24,-86), "radius":Vector2(9,5), "phase":0.0,"water":true,"speed":0.12,"seats":12},
	{"id":"cas_amphibious_apc", "center":Vector2(-16,-30), "radius":Vector2(3,6), "phase":1.7,"water":false,"speed":0.10,"seats":8},
	{"id":"cas_tank_cc0", "center":Vector2(9,-28), "radius":Vector2(3,5), "phase":3.7,"water":false,"speed":0.10,"seats":0},
	{"id":"cas_heavy_landing_craft", "center":Vector2(-56,-112), "radius":Vector2(13,8), "phase":1.0,"water":true,"speed":0.09,"seats":12},
	{"id":"cas_fast_assault_boat", "center":Vector2(10,-72), "radius":Vector2(12,7), "phase":3.0,"water":true,"speed":0.25,"seats":8},
	{"id":"cas_self_propelled_artillery", "center":Vector2(28,-18), "radius":Vector2(2.0,7), "phase":2.1,"water":false,"speed":0.08,"seats":6},
	{"id":"cas_transport_helicopter", "center":Vector2(-44,-35), "radius":Vector2(12,6), "phase":0.7,"water":false,"speed":0.17,"altitude":11.0,"seats":10},
	{"id":"cas_attack_helicopter", "center":Vector2(40,-37), "radius":Vector2(12,7), "phase":3.4,"water":false,"speed":0.20,"altitude":14.0,"seats":6},
]

func build(height_at: Callable) -> void:
	_ground = height_at
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_vehicles.clear()
	for specification: Dictionary in SHOWCASE:
		_add_vehicle(specification)
	set_process(true)
	_process(0.0)

func _add_vehicle(specification: Dictionary) -> void:
	var id: String = str(specification["id"])
	var scene: PackedScene = load(MODEL_ROOT + id + ".glb") as PackedScene
	if scene == null:
		push_warning("Vehicle model is missing: " + id)
		return
	var anchor := Node3D.new()
	anchor.name = id
	anchor.set_meta("forward", "-Z")
	anchor.set_meta("metres_per_unit", 1.0)
	anchor.set_meta("art_person_seats", int(specification["seats"]))
	anchor.set_meta("waterline_anchor", bool(specification["water"]))
	add_child(anchor)
	var model: Node3D = scene.instantiate() as Node3D
	model.name = "EditableGLB"
	anchor.add_child(model)
	_enable_vertex_palette(model)
	# Presentation scale stays separate from real model dimensions. This isolated
	# close-up is 1:1; the full engine may apply its approved SD readability scale.
	var pivot: Node3D = model.find_child("Turret", true, false) as Node3D
	var ramp: Node3D = model.find_child("Ramp", true, false) as Node3D
	var row: Dictionary = specification.duplicate()
	row.merge({"node":anchor, "turret":pivot, "ramp":ramp,
		"ramp_open":0.0,"main_rotor":model.find_child("MainRotor",true,false),
		"tail_rotor":model.find_child("TailRotor",true,false),
		"chin_gun":model.find_child("ChinGun",true,false)})
	if bool(specification["water"]): row["wake"] = _add_wake(anchor, id)
	_vehicles.append(row)

func _add_wake(anchor: Node3D, id: String) -> Node3D:
	# Thin transparent 3D triangles: separate from the asset and its real bounds.
	var length: float = 11.7 if id == "cas_heavy_landing_craft" else 6.7 if id == "cas_landing_craft" else 3.8
	var width: float = 3.4 if id == "cas_heavy_landing_craft" else 2.3 if id == "cas_landing_craft" else 1.4
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "ArtWake"
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [-1.0,1.0]:
		for segment: int in range(8):
			var distance: float = float(segment)*1.3
			var a := Vector3(side*(width*.7+distance*.17),.04,length+distance)
			var b := Vector3(side*(width*.7+(distance+1.0)*.17),.04,length+distance+1.0)
			var c: Vector3 = b+Vector3(side*.35,0,.05)
			surface.set_color(Color(.85,.98,1.0,.44-float(segment)*.045))
			surface.add_vertex(a)
			surface.add_vertex(b)
			surface.add_vertex(c)
	surface.generate_normals()
	mesh_node.mesh = surface.commit()
	var foam := StandardMaterial3D.new()
	foam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	foam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	foam.vertex_color_use_as_albedo = true
	foam.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_node.material_override = foam
	mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	anchor.add_child(mesh_node)
	return mesh_node

func _enable_vertex_palette(node: Node) -> void:
	if node is MeshInstance3D:
		var geometry: MeshInstance3D = node as MeshInstance3D
		for surface: int in range(geometry.mesh.get_surface_count()):
			var original: StandardMaterial3D = geometry.get_active_material(surface) as StandardMaterial3D
			if original == null: continue
			var key: int = original.get_instance_id()
			if not _palette_materials.has(key):
				var palette: StandardMaterial3D = original.duplicate() as StandardMaterial3D
				palette.resource_name = "CAS vehicle visible vertex palette"
				palette.albedo_color = Color.WHITE
				palette.vertex_color_use_as_albedo = true
				palette.vertex_color_is_srgb = false
				_palette_materials[key] = palette
			geometry.set_surface_override_material(surface, _palette_materials[key] as Material)
	for child: Node in node.get_children(): _enable_vertex_palette(child)

func _process(delta: float) -> void:
	_time += delta
	for row: Dictionary in _vehicles:
		var node: Node3D = row["node"] as Node3D
		var center: Vector2 = row["center"]
		var radius: Vector2 = row["radius"]
		var phase: float = _time * float(row["speed"]) + float(row["phase"])
		var point := center + Vector2(cos(phase) * radius.x, sin(phase) * radius.y)
		var velocity := Vector2(-sin(phase) * radius.x, cos(phase) * radius.y)
		var altitude: float = float(row.get("altitude",0.0))
		var height: float = 0.12 if bool(row["water"]) else float(_ground.call(point.x, point.y)) + 0.03
		if altitude > 0.0: height = maxf(height,0.12)+altitude
		node.position = Vector3(point.x, height, point.y)
		# Godot forward is -Z: never use the old +Z artwork convention.
		node.rotation.y = atan2(-velocity.x, -velocity.y)
		if bool(row["water"]):
			node.position.y += sin(_time * 1.1 + float(row["phase"])) * 0.045
			node.rotation.x = sin(_time * 0.87) * 0.009
			node.rotation.z = sin(_time * 0.73) * 0.012
			(row["wake"] as Node3D).scale.z = 1.0+sin(_time*2.2+phase)*.055
		elif altitude > 0.0:
			node.position.y += sin(_time*.9+phase)*.15
			node.rotation.z = sin(phase)*.035
			node.rotation.x = -.025
		var turret: Node3D = row["turret"] as Node3D
		if turret != null:
			turret.rotation.y = sin(_time * 0.22 + float(row["phase"])) * 0.28
		var ramp: Node3D = row["ramp"] as Node3D
		if ramp != null: ramp.rotation.x = -1.4*float(row["ramp_open"])
		var main_rotor: Node3D = row["main_rotor"] as Node3D
		if main_rotor != null: main_rotor.rotation.y = _time*21.7+float(row["phase"])
		var tail_rotor: Node3D = row["tail_rotor"] as Node3D
		if tail_rotor != null: tail_rotor.rotation.x = _time*33.1+float(row["phase"])
		var chin_gun: Node3D = row["chin_gun"] as Node3D
		if chin_gun != null: chin_gun.rotation.y = sin(_time*.3)*.18

func set_ramp_open(id: String, amount: float) -> void:
	for row: Dictionary in _vehicles:
		if str(row["id"]) == id: row["ramp_open"] = clampf(amount,0.0,1.0)
	_process(0.0)

func get_vehicle_anchor(id: String, socket_name: String) -> Node3D:
	var body: Node3D = get_node_or_null(NodePath(id)) as Node3D
	if body == null: return null
	return body.find_child(socket_name,true,false) as Node3D

func set_demo_time(seconds: float) -> void:
	_time = maxf(seconds, 0.0)
	_process(0.0)
