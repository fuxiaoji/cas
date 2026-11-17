extends SceneTree
func _initialize()->void:call_deferred("run")
func shot(name:String)->void:
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/godot/chibi-style-root/"+name+".png"))
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../artifacts/godot/chibi-style-root"))
	root.size=Vector2i(1600,900)
	var review=load("res://scenes/demos/chibi_style_review.tscn").instantiate();root.add_child(review)
	await process_frame;await process_frame
	var count:int=review.grid.get_child_count()
	await shot("all-80-top")
	var initial_scroll:ScrollContainer=review.grid.get_parent();initial_scroll.ensure_control_visible(review.grid.get_child(count-1));await process_frame;await process_frame
	await shot("all-80-bottom")
	review.icon_height=160;review._build_review_grid();await process_frame;await process_frame
	var scroll:ScrollContainer=review.grid.get_parent()
	for page in range(4):
		scroll.scroll_vertical=page*700;await process_frame;await process_frame
		await shot("all-160-page-"+str(page+1))
	print("CHIBI_VISUAL_REVIEW ",JSON.stringify({"tiles_including_two_old_references":count,"nominal_heights":[80,160],"output":"artifacts/godot/chibi-style-root/"}))
	FileAccess.open("res://../artifacts/godot/chibi-style-root/receipt.json",FileAccess.WRITE).store_string(JSON.stringify({"expected_characters":64,"actual_characters":count-2,"old_style_references":2,"passed":count==66,"nominal_heights":[80,160],"screenshots":6},"  "))
	review.queue_free();await process_frame;quit(0 if count==66 else 1)
