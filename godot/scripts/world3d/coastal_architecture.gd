extends Node3D
## Editable coastal architecture. World metres: X/Z ground, Y elevation.
## build() samples height_at.call(x, z). Front doors face -Z (the sea).
## Each named building contains MeshInstance3D batches sharing one palette.
## No gameplay collisions, navigation or simulation state are generated here.

var _height_at: Callable
var _materials: Dictionary = {}
var buildings: Array[Node3D] = []

func build(height_at: Callable) -> void:
	_height_at = height_at
	_palette()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	buildings.clear()
	spawn_house(self, Vector2(-29, 25), 0)
	spawn_warehouse(self, Vector2(29, 27))
	spawn_harbor_office(self, Vector2(-2, -1))
	spawn_house(self, Vector2(-33, 68), 1, 0.12)
	spawn_house(self, Vector2(31, 70), 2, -0.10)
	spawn_pier(self, Vector2(-2, -56))

func _palette() -> void:
	if not _materials.is_empty():
		return
	var colors: Dictionary = {
		"ivory": Color("f3e5c5"), "apricot": Color("edcda8"),
		"mint": Color("cbdcc6"), "stone": Color("b6b6a0"),
		"paving": Color("d1c8aa"), "paving_light": Color("e0d6b9"),
		"cream": Color("fff0d1"), "tile": Color("c9674d"),
		"tile_light": Color("df8060"), "tile_dark": Color("b75c4a"),
		"teal": Color("477c7a"), "blue": Color("5c8b9c"),
		"glass": Color("314f60"), "sky_glint": Color("94b6b5"),
		"wood": Color("94724f"), "wood_light": Color("b19367"),
		"dark_wood": Color("655444"), "iron": Color("4e6263"),
		"copper": Color("8b947a"), "leaf": Color("758c5b"),
		"flower": Color("d48e85"), "sign": Color("dfc88e")
	}
	for key: String in colors:
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.resource_name = "Architecture_" + key
		material.albedo_color = colors[key]
		material.roughness = 0.88
		_materials[key] = material

func _root(parent: Node3D, label: String, ground: Vector2, footprint: Vector2, yaw: float) -> Node3D:
	_palette()
	var node: Node3D = Node3D.new()
	node.name = label
	parent.add_child(node)
	var elevation: float = float(_height_at.call(ground.x, ground.y)) if _height_at.is_valid() else 0.0
	# A horizontal courtyard needs a small retaining plinth on gentle slopes.
	# Sample its real footprint rather than burying the uphill half of the slab.
	var orientation: Basis = Basis(Vector3.UP, yaw)
	if _height_at.is_valid():
		for sx: float in [-0.5, 0.5]:
			for sz: float in [-0.5, 0.5]:
				var corner: Vector3 = orientation * Vector3(footprint.x * sx, 0, footprint.y * sz)
				elevation = maxf(elevation, float(_height_at.call(ground.x + corner.x, ground.y + corner.z)))
		elevation += 0.035
	node.position = Vector3(ground.x, elevation, ground.y)
	node.rotation.y = yaw
	node.set_meta("footprint_m", footprint)
	node.set_meta("ground_xz", ground)
	node.set_meta("art_only", true)
	buildings.append(node)
	return node

func spawn_house(parent: Node3D, ground: Vector2, variant: int = 0, yaw: float = 0.0) -> Node3D:
	var cottage: bool = variant != 0
	var width: float = 8.3 if cottage else 12.2
	var depth: float = 7.2 if cottage else 9.0
	var height: float = 4.3 if cottage else 7.0
	var label: String = "Cottage_%d" % variant if cottage else "SeafrontResidence"
	var root: Node3D = _root(parent, label, ground, Vector2(width + 6, depth + 7), yaw)
	var batch: Dictionary = {}
	var wall: String = ["ivory", "apricot", "mint"][posmod(variant, 3)]
	_foundation(batch, width, depth)
	_box(batch, wall, Vector3(0, height * 0.5 + 0.45, 0), Vector3(width, height, depth))
	_box(batch, "cream", Vector3(0, height + 0.37, 0), Vector3(width + 0.32, 0.24, depth + 0.3))
	_box(batch, "stone", Vector3(0, 0.71, 0), Vector3(width + 0.13, 0.33, depth + 0.14))
	if not cottage:
		_box(batch, "cream", Vector3(0, 3.83, 0), Vector3(width + 0.14, 0.20, depth + 0.15))
	for x: float in [-width * 0.5 + 0.14, width * 0.5 - 0.14]:
		_box(batch, "cream", Vector3(x, height * 0.5 + 0.5, -depth * 0.5 - 0.07), Vector3(0.26, height, 0.16))
	_gable_roof(batch, width + 1.1, depth + 1.1, height + 0.48, 2.55 if cottage else 3.3, wall)
	_door(batch, Vector3(0, 0.45, -depth * 0.5 - 0.1), 1.55, 2.65, true)
	for level in range(1 if cottage else 2):
		var y: float = 2.25 + float(level) * 3.2
		for x: float in [-width * 0.30, width * 0.30]:
			_window(batch, Vector3(x, y, -depth * 0.5 - 0.08), 1.35, 1.75, 0.0, true, level == 0)
		for z: float in [-depth * 0.25, depth * 0.25]:
			_window(batch, Vector3(width * 0.5 + 0.08, y, z), 1.22, 1.65, -PI * 0.5, true, false)
	if not cottage:
		_balcony(batch, Vector3(0, 3.82, -depth * 0.5 - 0.76), 4.2, 1.55)
		_window(batch, Vector3(0, 5.32, -depth * 0.5 - 0.09), 1.35, 2.25, 0, false, false)
	_chimney(batch, Vector3(-width * 0.30, height + 1.25, depth * 0.23))
	_gutter(batch, width, depth, height + 0.42)
	_courtyard(batch, width + 5.5, depth + 5.5, width, depth)
	_wall_segment(batch, Vector3(-width * 0.5 - 2.1, 0.6, 0), Vector3(0.4, 1.2, depth + 3.5))
	_planter(batch, Vector3(width * 0.5 + 1.35, 0.26, -depth * 0.38), 1.4)
	_finish(root, batch)
	return root

func spawn_warehouse(parent: Node3D, ground: Vector2, yaw: float = 0.0) -> Node3D:
	var root: Node3D = _root(parent, "PortWarehouse", ground, Vector2(25, 23), yaw)
	var b: Dictionary = {}
	_foundation(b, 18, 12)
	_box(b, "ivory", Vector3(0, 3.6, 0), Vector3(18, 6.4, 12))
	for x: float in [-8.8, -5.0, 5.0, 8.8]:
		_box(b, "cream", Vector3(x, 3.7, -6.1), Vector3(0.34, 6.5, 0.22))
	_gable_roof(b, 19.3, 13.3, 6.9, 3.5, "ivory")
	_box(b, "dark_wood", Vector3(0, 2.7, -6.15), Vector3(6.2, 4.6, 0.18))
	for side: int in [-1, 1]:
		_box(b, "teal", Vector3(float(side) * 1.57, 2.65, -6.29), Vector3(2.94, 4.3, 0.15))
		for i in range(6):
			_box(b, "wood_light", Vector3(float(side) * 1.57, 0.85 + float(i) * 0.69, -6.39), Vector3(2.78, 0.065, 0.04))
		_box(b, "iron", Vector3(float(side) * 0.32, 2.4, -6.41), Vector3(0.08, 0.65, 0.07))
	_box(b, "iron", Vector3(0, 5.18, -6.42), Vector3(7.8, 0.10, 0.13))
	for x: float in [-6.6, 6.6]:
		_window(b, Vector3(x, 3.7, -6.13), 1.7, 1.75, 0, false, false)
	for z: float in [-3.6, 0.0, 3.6]:
		_window(b, Vector3(9.08, 4.5, z), 2.0, 1.25, -PI * 0.5, false, false)
	_box(b, "wood", Vector3(0, 0.55, -7.2), Vector3(12, 0.5, 2.7))
	for x: float in [-5.4, 5.4]:
		_box(b, "wood", Vector3(x, 2.6, -8.0), Vector3(0.22, 4.2, 0.22))
	_box(b, "teal", Vector3(0, 5.0, -7.15), Vector3(12.7, 0.18, 3.0), Basis(Vector3.RIGHT, -0.10))
	_box(b, "cream", Vector3(0, 4.86, -8.59), Vector3(12.8, 0.22, 0.14))
	_box(b, "sign", Vector3(0, 5.85, -6.17), Vector3(4.25, 0.65, 0.14))
	for i in range(5):
		_box(b, "dark_wood", Vector3(-1.5 + float(i) * 0.75, 5.85, -6.27), Vector3(0.32, 0.32, 0.04))
	_courtyard(b, 25, 22, 18, 12)
	for i in range(8):
		_crate(b, Vector3(6.3 + float(i % 2) * 1.35, 0.8 + float(i / 4) * 1.18, -7.0 - float((i / 2) % 2) * 1.4), 1.12)
	_gutter(b, 18, 12, 6.88)
	_finish(root, b)
	return root

func spawn_harbor_office(parent: Node3D, ground: Vector2, yaw: float = 0.0) -> Node3D:
	var root: Node3D = _root(parent, "HarborOffice", ground, Vector2(22, 19), yaw)
	var b: Dictionary = {}
	_foundation(b, 13.8, 8.8)
	_box(b, "apricot", Vector3(0, 3.65, 0), Vector3(13.8, 6.5, 8.8))
	_box(b, "cream", Vector3(0, 3.65, 0), Vector3(14.1, 0.23, 9.1))
	_gable_roof(b, 15.0, 10.0, 7.0, 3.1, "apricot")
	_door(b, Vector3(-1.2, 0.45, -4.53), 1.8, 2.8, true)
	for x: float in [-4.6, 2.4, 5.0]:
		_window(b, Vector3(x, 2.1, -4.51), 1.25, 1.8, 0, true, false)
	for x: float in [-4.6, -1.3, 2.1, 5.0]:
		_window(b, Vector3(x, 5.2, -4.51), 1.3, 1.8, 0, false, false)
	_balcony(b, Vector3(-1.1, 3.72, -5.13), 8.5, 1.4)
	for z: float in [-2.6, 1.8]:
		_window(b, Vector3(6.98, 2.4, z), 1.5, 1.8, -PI * 0.5, false, false)
		_window(b, Vector3(6.98, 5.2, z), 1.5, 1.8, -PI * 0.5, false, false)
	# A small lantern/bell turret breaks the roof silhouette.
	_box(b, "cream", Vector3(4.35, 8.5, 1.45), Vector3(2.4, 2.4, 2.6))
	for x: float in [3.55, 5.15]:
		_box(b, "glass", Vector3(x, 8.7, 0.11), Vector3(0.48, 1.1, 0.08))
	_box(b, "glass", Vector3(5.60, 8.7, 1.45), Vector3(0.08, 1.15, 1.5))
	_gable_roof(b, 3.1, 3.2, 9.8, 1.25, "cream", Vector3(4.35, 0, 1.45))
	_cylinder(b, "iron", Vector3(-5.0, 10.4, 1.2), 0.065, 3.6, 6)
	_box(b, "teal", Vector3(-3.95, 11.25, 1.2), Vector3(1.9, 0.95, 0.06))
	_box(b, "cream", Vector3(-3.95, 11.25, 1.15), Vector3(1.7, 0.13, 0.02))
	_courtyard(b, 21, 18, 13.8, 8.8)
	for x: float in [-8.8, 8.8]:
		_wall_segment(b, Vector3(x, 0.6, 1.8), Vector3(0.45, 1.2, 12.5))
	_gutter(b, 13.8, 8.8, 6.95)
	_finish(root, b)
	return root

func spawn_pier(parent: Node3D, ground: Vector2, yaw: float = 0.0) -> Node3D:
	var root: Node3D = _root(parent, "TimberPier", ground, Vector2(9, 29), yaw)
	# Flat water deck; each pile extends down from the deck, not from seabed height.
	root.position.y = maxf(1.0, root.position.y)
	var b: Dictionary = {}
	_box(b, "dark_wood", Vector3(0, 0.05, 0), Vector3(7.0, 0.48, 29.0))
	for i in range(58):
		_box(b, "wood_light" if i % 4 != 0 else "wood", Vector3(0, 0.35, -14.2 + float(i) * 0.5), Vector3(7.0, 0.16, 0.47))
	for z: float in [-13.7, -8.3, -2.8, 2.8, 8.3, 13.7]:
		for x: float in [-3.12, 3.12]:
			_cylinder(b, "wood", Vector3(x, -1.0, z), 0.27, 4.2, 8)
			_cylinder(b, "wood_light", Vector3(x, 1.15, z), 0.33, 0.18, 8)
			_cylinder(b, "iron", Vector3(x, 0.78, z), 0.29, 0.12, 8)
			if z < 10:
				_box(b, "wood", Vector3(x, 1.04, z + 2.7), Vector3(0.14, 0.16, 5.35))
	for x: float in [-2.5, 2.5]:
		_box(b, "dark_wood", Vector3(x, -0.25, 0), Vector3(0.24, 0.35, 29))
	for i in range(3):
		_crate(b, Vector3(-1.8 + float(i % 2) * 1.35, 0.45, 8.5 + float(i) * 1.45), 1.2)
	_finish(root, b)
	return root

func _foundation(b: Dictionary, width: float, depth: float) -> void:
	_box(b, "stone", Vector3(0, 0.22, 0), Vector3(width + 0.65, 0.55, depth + 0.65))
	_box(b, "cream", Vector3(0, 0.47, 0), Vector3(width + 0.82, 0.18, depth + 0.82))
	for side: int in [-1, 1]:
		for i in range(maxi(2, int(width / 1.3))):
			_box(b, "paving", Vector3(-width * 0.5 + 0.55 + float(i) * 1.3, 0.2, float(side) * (depth * 0.5 + 0.34)), Vector3(1.2, 0.29, 0.07))

func _gable_roof(b: Dictionary, width: float, depth: float, eave: float, rise: float, wall: String, offset: Vector3 = Vector3.ZERO) -> void:
	var half: float = width * 0.5
	var front: float = -depth * 0.5 + 0.5
	var back: float = depth * 0.5 - 0.5
	for z: float in [front, back]:
		_tri(b, wall, offset + Vector3(-half + 0.5, eave - 0.03, z), offset + Vector3(0, eave + rise - 0.15, z), offset + Vector3(half - 0.5, eave - 0.03, z))
		_tri(b, wall, offset + Vector3(half - 0.5, eave - 0.03, z), offset + Vector3(0, eave + rise - 0.15, z), offset + Vector3(-half + 0.5, eave - 0.03, z))
	for side: int in [-1, 1]:
		var slope: float = atan2(rise, half)
		var length: float = sqrt(half * half + rise * rise)
		_box(b, "dark_wood", offset + Vector3(float(side) * half * 0.5, eave + rise * 0.5 - 0.1, 0), Vector3(length + 0.1, 0.18, depth), Basis(Vector3.FORWARD, float(side) * slope))
		for z: float in [-depth * 0.5, depth * 0.5]:
			_beam(b, "cream", offset + Vector3(0, eave + rise + 0.03, z), offset + Vector3(float(side) * half, eave + 0.03, z), 0.19, 0.25)
		var courses: int = maxi(2, ceili(half / 0.72))
		var columns: int = maxi(2, ceili(depth / 0.48))
		for row in range(courses):
			var x0: float = float(row) / float(courses) * half
			var x1: float = minf(half + 0.08, float(row + 1) / float(courses) * half + 0.08)
			for col in range(columns):
				var z0: float = -depth * 0.5 + float(col) / float(columns) * depth
				var z1: float = -depth * 0.5 + float(col + 1) / float(columns) * depth
				var key: String = "tile_light" if (row * 7 + col * 3) % 11 < 2 else ("tile_dark" if (row + col * 5) % 13 < 2 else "tile")
				for segment in range(3):
					var ta: float = float(segment) / 3.0
					var tb: float = float(segment + 1) / 3.0
					var za: float = lerpf(z0, z1, ta)
					var zb: float = lerpf(z0, z1, tb)
					var ya: float = sin(ta * PI) * 0.065 + 0.075
					var yb: float = sin(tb * PI) * 0.065 + 0.075
					var a: Vector3 = offset + Vector3(float(side) * x0, eave + rise * (1.0 - x0 / half) + ya, za)
					var c: Vector3 = offset + Vector3(float(side) * x1, eave + rise * (1.0 - x1 / half) + yb + 0.025, zb)
					var d: Vector3 = offset + Vector3(float(side) * x0, eave + rise * (1.0 - x0 / half) + yb, zb)
					var e: Vector3 = offset + Vector3(float(side) * x1, eave + rise * (1.0 - x1 / half) + ya + 0.025, za)
					if side == 1:
						_quad(b, key, a, d, c, e)
					else:
						_quad(b, key, a, e, c, d)
		_box(b, "cream", offset + Vector3(float(side) * half, eave - 0.02, 0), Vector3(0.17, 0.25, depth + 0.2))
	for i in range(maxi(1, ceili(depth / 0.62))):
		var z: float = -depth * 0.5 + 0.3 + float(i) * 0.62
		_cylinder(b, "tile_light", offset + Vector3(0, eave + rise + 0.05, z), 0.20, 0.66, 8, Basis(Vector3.RIGHT, PI * 0.5))

func _window(b: Dictionary, at: Vector3, width: float, height: float, yaw: float, shutters: bool, flower_box: bool) -> void:
	var t: Transform3D = Transform3D(Basis(Vector3.UP, yaw), at)
	_fbox(b, "dark_wood", t, Vector3(0, 0, 0), Vector3(width + 0.17, height + 0.15, 0.12))
	_fbox(b, "glass", t, Vector3(0, 0, -0.075), Vector3(width - 0.12, height - 0.1, 0.04))
	for x: float in [-width * 0.5, 0.0, width * 0.5]:
		_fbox(b, "cream", t, Vector3(x, 0, -0.13), Vector3(0.075, height + 0.22, 0.11))
	for y: float in [-height * 0.5, 0.0, height * 0.5]:
		_fbox(b, "cream", t, Vector3(0, y, -0.13), Vector3(width + 0.2, 0.08, 0.11))
	_fbox(b, "sky_glint", t, Vector3(-width * 0.20, height * 0.23, -0.105), Vector3(width * 0.22, height * 0.26, 0.02))
	_fbox(b, "cream", t, Vector3(0, -height * 0.5 - 0.13, -0.18), Vector3(width + 0.43, 0.16, 0.47))
	if shutters:
		for side: int in [-1, 1]:
			var x: float = float(side) * (width * 0.5 + 0.35)
			_fbox(b, "teal", t, Vector3(x, 0, -0.05), Vector3(0.52, height + 0.03, 0.13))
			for row in range(6):
				_fbox(b, "blue", t, Vector3(x, -height * 0.40 + float(row) * height * 0.16, -0.14), Vector3(0.43, 0.065, 0.05))
	if flower_box:
		_fbox(b, "tile_dark", t, Vector3(0, -height * 0.5 - 0.38, -0.37), Vector3(width + 0.1, 0.31, 0.44))
		for i in range(4):
			_fbox(b, "leaf", t, Vector3(-width * 0.35 + float(i) * width * 0.23, -height * 0.5 - 0.17, -0.39), Vector3(0.31, 0.26, 0.31))
			_fbox(b, "flower", t, Vector3(-width * 0.32 + float(i) * width * 0.23, -height * 0.5 - 0.06, -0.44), Vector3(0.15, 0.11, 0.16))

func _door(b: Dictionary, at: Vector3, width: float, height: float, arched: bool) -> void:
	_box(b, "dark_wood", at + Vector3(0, height * 0.5, -0.01), Vector3(width + 0.32, height + 0.2, 0.2))
	_box(b, "teal", at + Vector3(0, height * 0.5, -0.13), Vector3(width, height, 0.12))
	for x: float in [-width * 0.5 - 0.18, width * 0.5 + 0.18]:
		_box(b, "cream", at + Vector3(x, height * 0.5, -0.16), Vector3(0.23, height + 0.35, 0.33))
	for y: float in [height * 0.24, height * 0.60]:
		_box(b, "blue", at + Vector3(0, y, -0.22), Vector3(width * 0.76, height * 0.2, 0.04))
	_box(b, "iron", at + Vector3(width * 0.30, height * 0.46, -0.26), Vector3(0.09, 0.16, 0.09))
	if arched:
		for i in range(10):
			var angle: float = float(i) / 9.0 * PI
			var p: Vector3 = at + Vector3(cos(angle) * (width * 0.5 + 0.18), height + sin(angle) * width * 0.32, -0.13)
			_box(b, "cream", p, Vector3(0.25, 0.30, 0.32), Basis(Vector3.BACK, angle - PI * 0.5))
	else:
		_box(b, "cream", at + Vector3(0, height + 0.1, -0.14), Vector3(width + 0.6, 0.24, 0.32))
	for i in range(3):
		_box(b, "paving_light", at + Vector3(0, -0.12 - float(i) * 0.12, -0.38 - float(i) * 0.35), Vector3(width + 1.0, 0.20, 0.52))

func _balcony(b: Dictionary, at: Vector3, width: float, depth: float) -> void:
	_box(b, "cream", at, Vector3(width, 0.22, depth))
	for x: float in [-width * 0.35, width * 0.35]:
		_beam(b, "cream", at + Vector3(x, -0.8, depth * 0.45), at + Vector3(x, -0.08, -depth * 0.3), 0.19, 0.19)
	for i in range(maxi(2, ceili(width / 0.38))):
		var x: float = -width * 0.5 + 0.12 + float(i) * (width - 0.24) / float(maxi(1, ceili(width / 0.38) - 1))
		_box(b, "iron", at + Vector3(x, 0.6, -depth * 0.5 + 0.08), Vector3(0.055, 1.05, 0.055))
	for y: float in [0.18, 1.13]:
		_box(b, "iron", at + Vector3(0, y, -depth * 0.5 + 0.08), Vector3(width, 0.065, 0.07))
		for x: float in [-width * 0.5 + 0.08, width * 0.5 - 0.08]:
			_box(b, "iron", at + Vector3(x, y, 0), Vector3(0.07, 0.065, depth))

func _gutter(b: Dictionary, width: float, depth: float, height: float) -> void:
	for side: int in [-1, 1]:
		_cylinder(b, "copper", Vector3(float(side) * (width * 0.5 + 0.48), height - 0.10, 0), 0.095, depth + 1.1, 6, Basis(Vector3.RIGHT, PI * 0.5))
		_cylinder(b, "copper", Vector3(float(side) * (width * 0.5 + 0.15), height * 0.5, depth * 0.5 + 0.12), 0.075, height - 0.3, 6)
		_beam(b, "copper", Vector3(float(side) * (width * 0.5 + 0.48), height - 0.12, depth * 0.5), Vector3(float(side) * (width * 0.5 + 0.15), height - 0.6, depth * 0.5 + 0.12), 0.12, 0.12)

func _chimney(b: Dictionary, at: Vector3) -> void:
	_box(b, "apricot", at, Vector3(0.85, 2.8, 0.78))
	for i in range(5):
		_box(b, "tile_dark", at + Vector3(0, float(i) * 0.32 + 0.10, -0.41), Vector3(0.9, 0.035, 0.03))
	_box(b, "cream", at + Vector3(0, 1.4, 0), Vector3(1.1, 0.20, 1.0))
	_box(b, "dark_wood", at + Vector3(0, 1.52, 0), Vector3(0.64, 0.08, 0.5))

func _courtyard(b: Dictionary, width: float, depth: float, house_width: float, house_depth: float) -> void:
	_box(b, "stone", Vector3(0, -0.43, 0), Vector3(width, 0.86, depth))
	var step: float = 1.2
	for row in range(ceili(depth / step)):
		for col in range(ceili(width / step)):
			var x: float = -width * 0.5 + (float(col) + 0.5) * step
			var z: float = -depth * 0.5 + (float(row) + 0.5) * step
			if absf(x) < house_width * 0.5 and absf(z) < house_depth * 0.5:
				continue
			_box(b, "paving_light" if (row * 13 + col * 7) % 7 < 2 else "paving", Vector3(x, 0.015, z), Vector3(step - 0.045, 0.09, step - 0.045))

func _wall_segment(b: Dictionary, at: Vector3, dimensions: Vector3) -> void:
	_box(b, "apricot", at, dimensions)
	_box(b, "cream", at + Vector3(0, dimensions.y * 0.5, 0), Vector3(dimensions.x + 0.18, 0.16, dimensions.z + 0.18))
	for end: int in [-1, 1]:
		_box(b, "cream", at + Vector3(0, 0.12, float(end) * dimensions.z * 0.5), Vector3(0.65, dimensions.y + 0.35, 0.65))
		_box(b, "tile", at + Vector3(0, dimensions.y * 0.5 + 0.32, float(end) * dimensions.z * 0.5), Vector3(0.82, 0.14, 0.82))

func _planter(b: Dictionary, at: Vector3, size: float) -> void:
	_cylinder(b, "tile", at, size * 0.42, 0.7, 10)
	_cylinder(b, "tile_light", at + Vector3(0, 0.33, 0), size * 0.48, 0.14, 10)
	for i in range(5):
		var angle: float = float(i) * TAU / 5.0
		_box(b, "leaf", at + Vector3(cos(angle) * 0.25, 0.65, sin(angle) * 0.25), Vector3(0.65, 0.45, 0.65), Basis(Vector3.UP, angle))

func _crate(b: Dictionary, at: Vector3, size: float) -> void:
	_box(b, "wood", at + Vector3(0, size * 0.5, 0), Vector3.ONE * size)
	for i in range(4):
		_box(b, "wood_light", at + Vector3(0, 0.13 + float(i) * size * 0.24, -size * 0.51), Vector3(size - 0.08, 0.06, 0.06))
	for side: int in [-1, 1]:
		_box(b, "dark_wood", at + Vector3(float(side) * size * 0.36, size * 0.5, -size * 0.54), Vector3(0.10, size, 0.05))
		_box(b, "dark_wood", at + Vector3(size * 0.54, size * 0.5, float(side) * size * 0.36), Vector3(0.05, size, 0.10))
	_beam(b, "wood_light", at + Vector3(-size * 0.4, 0.12, -size * 0.55), at + Vector3(size * 0.4, size * 0.9, -size * 0.55), 0.10, 0.055)

func _tool(b: Dictionary, key: String) -> SurfaceTool:
	if not b.has(key):
		var st: SurfaceTool = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		b[key] = st
	return b[key] as SurfaceTool

func _tri(b: Dictionary, key: String, a: Vector3, c: Vector3, d: Vector3) -> void:
	var normal: Vector3 = (c - a).cross(d - a).normalized()
	if normal.length_squared() < 0.5:
		return
	var st: SurfaceTool = _tool(b, key)
	# Godot's front faces use clockwise winding; normals remain outward.
	for point: Vector3 in [a, d, c]:
		st.set_normal(normal)
		st.set_uv(Vector2(point.x, point.z) * 0.25)
		st.add_vertex(point)

func _quad(b: Dictionary, key: String, a: Vector3, c: Vector3, d: Vector3, e: Vector3) -> void:
	_tri(b, key, a, c, d)
	_tri(b, key, a, d, e)

func _box(b: Dictionary, key: String, at: Vector3, dimensions: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var s: Vector3 = dimensions * 0.5
	var points: Array[Vector3] = []
	for p: Vector3 in [Vector3(-s.x,-s.y,-s.z), Vector3(s.x,-s.y,-s.z), Vector3(s.x,s.y,-s.z), Vector3(-s.x,s.y,-s.z), Vector3(-s.x,-s.y,s.z), Vector3(s.x,-s.y,s.z), Vector3(s.x,s.y,s.z), Vector3(-s.x,s.y,s.z)]:
		points.append(at + basis * p)
	for face: Array in [[0,3,2,1], [4,5,6,7], [0,4,7,3], [1,2,6,5], [3,7,6,2], [0,1,5,4]]:
		_quad(b, key, points[face[0]], points[face[1]], points[face[2]], points[face[3]])

func _fbox(b: Dictionary, key: String, transform: Transform3D, at: Vector3, dimensions: Vector3) -> void:
	_box(b, key, transform * at, dimensions, transform.basis)

func _beam(b: Dictionary, key: String, from: Vector3, to: Vector3, width: float, depth: float) -> void:
	var direction: Vector3 = to - from
	if direction.length() < 0.001:
		return
	var y: Vector3 = direction.normalized()
	var x: Vector3 = y.cross(Vector3.FORWARD).normalized() if absf(y.dot(Vector3.FORWARD)) < 0.98 else y.cross(Vector3.UP).normalized()
	var z: Vector3 = x.cross(y).normalized()
	_box(b, key, (from + to) * 0.5, Vector3(width, direction.length(), depth), Basis(x, y, z))

func _cylinder(b: Dictionary, key: String, at: Vector3, radius: float, height: float, segments: int, basis: Basis = Basis.IDENTITY) -> void:
	for i in range(segments):
		var a: float = float(i) * TAU / float(segments)
		var c: float = float(i + 1) * TAU / float(segments)
		var pa: Vector3 = Vector3(cos(a) * radius, -height * 0.5, sin(a) * radius)
		var pc: Vector3 = Vector3(cos(c) * radius, -height * 0.5, sin(c) * radius)
		var up: Vector3 = Vector3.UP * height
		_quad(b, key, at + basis * pa, at + basis * (pa + up), at + basis * (pc + up), at + basis * pc)
		_tri(b, key, at + basis * Vector3(0, height * 0.5, 0), at + basis * (pc + up), at + basis * (pa + up))
		_tri(b, key, at + basis * Vector3(0, -height * 0.5, 0), at + basis * pa, at + basis * pc)

func _finish(root: Node3D, b: Dictionary) -> void:
	var triangles: int = 0
	for key: String in b:
		var st: SurfaceTool = b[key] as SurfaceTool
		st.index()
		var mesh: ArrayMesh = st.commit()
		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = "Geometry_" + key
		node.mesh = mesh
		node.material_override = _materials[key]
		root.add_child(node)
		node.owner = owner if owner != null else self
		var arrays: Array = mesh.surface_get_arrays(0)
		triangles += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	root.set_meta("triangle_count", triangles)
	root.set_meta("material_batches", b.size())
	root.set_meta("front_direction", "-Z")
