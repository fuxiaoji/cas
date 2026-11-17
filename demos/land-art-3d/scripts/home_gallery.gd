extends Node3D
## Actual Godot model previews, not generated concept illustrations.

const OUTPUT: String = "res://../../artifacts/home-design-20261116/buildings/"
var facility_factory: Node3D
var camera: Camera3D
var caption: Label

func _ready() -> void:
	var environment: WorldEnvironment = WorldEnvironment.new()
	var settings: Environment = Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("dce8d7").srgb_to_linear()
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c5dce0")
	settings.ambient_light_energy = .35
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = settings
	add_child(environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,145,0)
	sun.light_color = Color("fff1d7")
	sun.light_energy = .68
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 100
	add_child(sun)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var ground_mesh: PlaneMesh = PlaneMesh.new()
	ground_mesh.size = Vector2(120,120)
	ground.mesh = ground_mesh
	ground.position.y = -.39
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("bfcfa5").srgb_to_linear()
	material.roughness = 1
	ground.material_override = material
	add_child(ground)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 36
	camera.position = Vector3(31,31,-40)
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0,2,0))
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	caption = Label.new()
	caption.position = Vector2(34,25)
	var font: FontVariation = FontVariation.new()
	font.base_font = load("res://assets/fonts/NotoSansSC.ttf")
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):600.0}
	caption.add_theme_font_override("font",font)
	caption.add_theme_font_size_override("font_size",25)
	caption.add_theme_color_override("font_color",Color("244e4d"))
	layer.add_child(caption)
	await get_tree().process_frame
	var directory: String = ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(directory)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/facilities"))
	var records: Array[Dictionary] = []
	var factory_script: Script = load("res://scripts/home_architecture.gd")
	facility_factory = Node3D.new()
	facility_factory.set_script(factory_script)
	add_child(facility_factory)
	var catalog: Array = factory_script.get_script_constant_map()["CATALOG"]
	for i: int in range(catalog.size()):
		var entry: Dictionary = catalog[i]
		var model: Node3D = facility_factory.call("spawn_facility",str(entry["id"]),Vector2.ZERO)
		caption.text = "%02d  %s" % [i+1,entry["name"]]
		await get_tree().create_timer(.12).timeout
		await RenderingServer.frame_post_draw
		var path: String = "%02d-%s.png" % [i+1,entry["id"]]
		get_viewport().get_texture().get_image().save_png(directory+path)
		_assign_owner(model,model)
		var packed: PackedScene = PackedScene.new()
		var error: Error = packed.pack(model)
		if error==OK: error = ResourceSaver.save(packed,"res://scenes/facilities/"+str(entry["id"])+".scn",ResourceSaver.FLAG_COMPRESS)
		records.append({"id":entry["id"],"name":entry["name"],"preview":path,"scene_save_error":error,"footprint_m":[entry["plot"].x,entry["plot"].y],"scope":"editable geometry only; economy and defense are proposed"})
		print("HOME_MODEL_CAPTURE "+path)
		facility_factory.remove_child(model)
		model.free()
	var receipt: FileAccess = FileAccess.open(directory+"../building-previews.json",FileAccess.WRITE)
	receipt.store_string(JSON.stringify(records,"\t"))
	get_tree().quit()

func _assign_owner(node: Node, scene_root: Node) -> void:
	for child: Node in node.get_children():
		child.owner = scene_root
		_assign_owner(child,scene_root)
