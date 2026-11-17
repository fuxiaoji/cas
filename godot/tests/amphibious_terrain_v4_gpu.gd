extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1280,720)
	var preview=load("res://scenes/ui/procedural_terrain_preview.tscn").instantiate();root.add_child(preview)
	for index in range(8):await process_frame
	await RenderingServer.frame_post_draw
	var first:Image=root.get_texture().get_image();first.save_png("res://../artifacts/combined-arms-v4/terrain-seed-4567.png")
	preview.terrain_seed=8632
	for index in range(8):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../artifacts/combined-arms-v4/terrain-seed-8632.png")
	preview.queue_free();await process_frame;quit()
