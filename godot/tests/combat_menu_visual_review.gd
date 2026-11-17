extends SceneTree
func _initialize()->void:call_deferred("run")
func shot(name:String)->void:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/godot/combat-feel/"+name+".png"))
func run()->void:
	root.size=Vector2i(1280,720)
	var app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false
	app.economy=load("res://scripts/economy.gd").new("user://tests/combat-menu-%d.json"%OS.get_process_id())
	root.add_child(app);app.set_process(false);await process_frame;app.page_motion=false
	app.show_page("settings");await shot("settings-motion-slider")
	app.core.request({"op":"new","seed":6106,"side":"allies","realtime":true})
	app.enter_battle();DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);app.fullscreen_battle=false
	app.battle_controller.hud.view_menu();await shot("battle-view-motion-slider")
	app.close_modal();app.run={"mode":"tide_event"}
	app.core.request({"op":"new_tide","seed":45,"character_id":"IBS-U-USN-FLETCHER","difficulty":"normal","intel_profile":"open-intel-v1"})
	app.enter_battle();DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);app.fullscreen_battle=false
	app.battle_controller.open_pause_menu();await shot("tide-pause-motion-slider")
	app.core.close();app.queue_free();await process_frame;quit()
