extends SceneTree
const Bridge = preload("res://scripts/core_bridge.gd")
const Sea = preload("res://scripts/sea_map.gd")
const Island = preload("res://scripts/procedural_island.gd")
var failures: Array[String] = []
var checks := 0
var core = Bridge.new()
var content_version := "salvage-v2" if OS.get_cmdline_user_args().has("--salvage-v2") else "salvage-v1"
func _initialize() -> void:
	call_deferred("review")
func check(condition: bool, name: String) -> void:
	checks += 1
	if not condition:
		failures.append(name)
		push_error(name)
func generated(seed_value: int) -> Dictionary:
	var response: Dictionary = core.request({"op":"new_salvage","seed":seed_value,"start":{"content":content_version,"fleet":[{"id":"IBS-U-USN-FLETCHER","hp":100,"ammo":60,"level":1,"equipment":false,"command":false}]}})
	check(response.get("ok",false),"native generation "+str(seed_value))
	return core.view.duplicate(true)
func review() -> void:
	var output := ProjectSettings.globalize_path("res://../artifacts/godot/weather-motion")
	DirAccess.make_dir_recursive_absolute(output)
	var concave := PackedVector2Array([Vector2(0,0),Vector2(1200,0),Vector2(1200,400),Vector2(500,400),Vector2(500,1000),Vector2(0,1000)])
	var source := concave.duplicate()
	var a := Island._distance_field(concave,Rect2(0,0,1200,1000))
	var b := Island._distance_field(concave,Rect2(0,0,1200,1000))
	check(a.get_image().get_data()==b.get_image().get_data(),"same authoritative geometry yields identical generated distance field")
	check(concave==source,"distance generation leaves coastline untouched")
	check(a.resource_path.is_empty(),"distance field generated in memory, no source PNG")
	check(a.get_image().get_pixel(85,74).r==0.0,"concave inlet remains water in generated field")
	check(a.get_image().get_pixel(20,20).r>0.0,"solid coast interior has positive terrain distance")
	var first := generated(6109)
	var again := generated(6109)
	var other := generated(6110)
	check(first.islands==again.islands,"same native seed preserves exact island geometry")
	check(first.islands!=other.islands,"different native seed generates different coast geometry")
	var source_files := ["res://scripts/anime_environment.gd","res://scripts/procedural_island.gd","res://shaders/anime_cloud.gdshader","res://shaders/procedural_island.gdshader"]
	for path in source_files:
		var code := FileAccess.get_file_as_string(path)
		check(not code.contains("anime-cloud-v2.png") and not code.contains("anime-island-v2.png"),"no archived image reference: "+path)
	check(not FileAccess.get_file_as_string("res://shaders/anime_cloud.gdshader").contains("sampler2D"),"cloud density generated entirely in shader")
	var gpu := DisplayServer.get_name()!="headless"
	var image_a: Image
	if gpu:
		var map = Sea.new()
		root.add_child(map)
		map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		map.cinematic = true
		map.chibis = false
		map.environment_layer.set_process(false)
		for index in range(3):
			map.view = [first,again,other][index].duplicate(true)
			map.environment_layer.visual_time = 0
			map.environment_layer.drift = Vector2.ZERO
			map.environment_layer.weather.current.clear()
			map.environment_layer._process(0.0)
			map.queue_redraw()
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var frame := root.get_texture().get_image()
			frame.save_png(output.path_join(["seed-6109.png","seed-6109-repeat.png","seed-6110.png"][index]))
			if index==0:
				image_a = frame
			if index==1:
				check(frame.get_data()==image_a.get_data(),"same seed and visual clock render byte-identical pixels")
			if index==2:
				check(frame.get_data()!=image_a.get_data(),"different seed changes actual rendered terrain and clouds")
			for island in map.environment_layer.land_nodes:
				check(island.surface.texture.resource_path.is_empty(),"land runtime texture is generated data")
		map.queue_free()
		await process_frame
	core.close()
	var report := {"content_version":content_version,"checks":checks,"failures":failures,"gpu":gpu,"same_seed":6109,"other_seed":6110,"old_images":"archived only; no runtime references","geometry":"exact native polygon clips generated heightfield"}
	var file := FileAccess.open(output.path_join("procedural-seed-test.json" if gpu else "procedural-seed-test-headless.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
