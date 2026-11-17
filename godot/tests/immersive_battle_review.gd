extends SceneTree
const TransitionSettle=preload("res://tests/transition_settle.gd")
const Main = preload("res://scenes/main.tscn")
const Economy = preload("res://scripts/economy.gd")
var app
var failures: Array[String] = []
var checks := 0
var directory := ""
func _initialize() -> void:
	call_deferred("run_review")
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures.append(title)
		push_error(title)
func shot(name: String) -> void:
	await TransitionSettle.wait_for_route(self,app)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(name + ".png"))
func run_review() -> void:
	directory = ProjectSettings.globalize_path("res://../artifacts/godot/immersive-battle")
	DirAccess.make_dir_recursive_absolute(directory)
	OS.set_environment("CAS_SIM_PATH", ProjectSettings.globalize_path("res://../target/release/cas-sim.exe"))
	var profile := "user://tests/quiet-review-%d.json" % OS.get_process_id()
	app = Main.instantiate()
	app.economy = Economy.new(profile)
	root.add_child(app)
	app.set_process(false)
	await process_frame
	var response: Dictionary = app.core.request({"op": "new", "seed": 6106, "side": "allies", "enemy": "gunnery", "variant": "prologue", "realtime": true})
	check(response.get("ok", false), "native source prologue loaded")
	app.enter_battle()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	app.fullscreen_battle = false
	var controller = app.battle_controller
	check(controller.recent_alert([{"kind": "torpedo_detected", "tick": 10, "text": "发现鱼雷"}, {"kind": "contact", "tick": 11, "text": "发现接触"}], 12) == "发现鱼雷", "torpedo danger has priority over ordinary contact")
	check(controller.recent_alert([{"kind": "contact", "tick": 0, "text": "旧接触"}], 30).is_empty(), "expired alerts leave the quiet view")
	var before: String = str(app.core.request({"op": "save", "serialized": true}).serialized)
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(1600, 720)]:
		root.size = dimensions
		await process_frame
		await process_frame
		controller.close_context()
		controller.hud.set_drawer(false)
		check(app.sea.size == app.page.size, "full map at " + str(dimensions))
		await shot("responsive-%dx%d-clean" % [dimensions.x, dimensions.y])
		controller.select("ship", app.core.view.ships[0])
		await process_frame
		check(controller.hud.context.get_global_rect().end.x <= app.page.size.x, "context stays inside viewport at " + str(dimensions))
		check(controller.hud.context.get_global_rect().end.y <= app.page.size.y, "context stays above bottom at " + str(dimensions))
		await shot("responsive-%dx%d-selected" % [dimensions.x, dimensions.y])
		controller.show_tab("ship")
		await process_frame
		check(controller.sidebar.get_global_rect().end.x <= app.page.size.x, "drawer stays inside viewport at " + str(dimensions))
		await shot("responsive-%dx%d-details" % [dimensions.x, dimensions.y])
	check(str(app.core.request({"op": "save", "serialized": true}).serialized) == before, "presentation and resize leave authoritative snapshot unchanged")
	app.core.close()
	app.queue_free()
	await process_frame
	await process_frame
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(profile + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(profile + suffix))
	var report := {"checks": checks, "failures": failures, "passed": checks - failures.size(), "sizes": ["1280x720", "960x540", "1600x720"]}
	var file := FileAccess.open(directory.path_join("responsive-receipt.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
