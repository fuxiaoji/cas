extends SceneTree

func _initialize() -> void:
	call_deferred("review")

func review() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	main.economy = load("res://scripts/economy.gd").new("user://visual_review_profile.json")
	root.add_child(main)
	await process_frame
	var output := ProjectSettings.globalize_path("res://../artifacts/godot/visual")
	DirAccess.make_dir_recursive_absolute(output)
	for page_name in ["harbor", "formation", "roster", "recruit", "shop", "settings"]:
		main.show_page(page_name)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(page_name + ".png"))
	main.queue_free()
	await process_frame
	quit()
