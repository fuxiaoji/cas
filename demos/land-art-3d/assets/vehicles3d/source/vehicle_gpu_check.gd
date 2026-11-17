extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var demo: Node3D = load("res://coast_demo.tscn").instantiate() as Node3D
	root.add_child(demo)
	while demo.get("hud") == null: await process_frame
	await create_timer(0.5).timeout
	demo.set_process(false)
	demo.get("hud").visible = false
	demo.set("target_focus", Vector3(-15,3,-25))
	demo.set("focus", Vector3(-15,3,-25))
	demo.set("target_size", 76.0)
	(demo.get("camera") as Camera3D).size = 76.0
	demo.call("_update_camera")
	var vehicles: Node = demo.find_child("ThreeDimensionalVehicles",true,false)
	vehicles.call("set_demo_time", 0.0)
	vehicles.set_process(false)
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://assets/vehicles3d/godot-vehicle-palette.png")
	print("VEHICLE_GPU_PALETTE_CAPTURED")
	quit()
