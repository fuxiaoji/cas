extends SceneTree
## Actual Godot GPU catalogue, independent of the concurrently edited coast scene.

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var lighting := Environment.new()
	lighting.background_mode = Environment.BG_COLOR
	lighting.background_color = Color("e8ece3")
	lighting.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	lighting.ambient_light_color = Color("d4e1ed")
	lighting.ambient_light_energy = .38
	lighting.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = lighting
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-35,0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	world.add_child(sun)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(43,85,105)
	camera.look_at(Vector3(0,0,0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 81.0
	camera.current = true
	var layer := Node3D.new()
	layer.set_script(load("res://scripts/coastal_vehicles.gd"))
	world.add_child(layer)
	layer.build(func(_x: float,_z: float) -> float: return 0.0)
	layer.set_process(false)
	var index: int = 0
	for vehicle: Node3D in layer.get_children():
		var x: float = (float(index%4)-1.5)*29.0
		var z: float = (float(index/4)-.5)*26.0
		vehicle.position = Vector3(x,0,z)
		vehicle.rotation = Vector3(0,PI,0)
		var wake: Node3D = vehicle.get_node_or_null("ArtWake") as Node3D
		if wake != null: wake.visible = false
		var pad := MeshInstance3D.new()
		var plane := BoxMesh.new()
		plane.size = Vector3(26,.15,23.0)
		pad.mesh = plane
		pad.position = Vector3(x,-.70 if bool(vehicle.get_meta("waterline_anchor")) else -.075,z)
		var colour := StandardMaterial3D.new()
		colour.albedo_color = Color("88c8c5") if bool(vehicle.get_meta("waterline_anchor")) else Color("d4d7bb")
		colour.roughness = .95
		pad.material_override = colour
		world.add_child(pad)
		var label := Label3D.new()
		label.text = ["01  LANDING CRAFT","02  AMPHIBIOUS APC","03  MAIN BATTLE TANK","04  HEAVY LANDING CRAFT","05  FAST ASSAULT BOAT","06  TRACKED ARTILLERY","07  TRANSPORT HELICOPTER","08  ATTACK HELICOPTER"][index]
		label.font_size = 80
		label.pixel_size = .012
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color("334741")
		label.outline_size = 0
		label.position = Vector3(x,1.0,z+12)
		world.add_child(label)
		index += 1
	var canvas := CanvasLayer.new()
	world.add_child(canvas)
	var heading := Label.new()
	heading.text = "CAS / COASTAL VEHICLE STUDY       8 true 3D assets / metre scale / one palette per vehicle"
	heading.position = Vector2(35,24)
	heading.add_theme_font_size_override("font_size",25)
	heading.add_theme_color_override("font_color",Color("2e4f49"))
	canvas.add_child(heading)
	await create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://assets/vehicles3d/godot-vehicle-catalog.png")
	# A close-up proves actual imported colours and all rotor assemblies in GPU.
	camera.position = Vector3(29,40,65)
	camera.look_at(Vector3(29,2,13))
	camera.size = 35
	heading.text = "CAS / ROTORCRAFT     Transport and armed assault / independent moving rotors"
	await create_timer(.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://assets/vehicles3d/godot-rotorcraft-close.png")
	print("VEHICLE_GPU_CATALOG_CAPTURED 8 assets")
	quit()
