extends SceneTree
const Main = preload("res://scenes/main.tscn")
const Economy = preload("res://scripts/economy.gd")
const Modes = preload("res://scripts/modes_presentation.gd")
const Recruit = preload("res://scripts/recruit_presentation.gd")
const Film = preload("res://scripts/prologue_film.gd")
var app
var checks := 0
var failures: Array[String] = []
var screenshots: Array[String] = []
var directory := "res://../artifacts/godot/presentation-redesign/"

func _initialize() -> void: call_deferred("run")

func check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures.append(text); push_error(text)

func find_button(text: String) -> Button:
	for node in app.find_children("*", "Button", true, false):
		if node.text == text and node.is_visible_in_tree(): return node
	return null

func shot(name: String) -> void:
	await process_frame
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(directory + name + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "screenshot " + name)
	screenshots.append(path)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := "user://tests/presentation-redesign-%d.json" % OS.get_process_id()
	app = Main.instantiate()
	app.economy = Economy.new(path)
	root.add_child(app)
	await process_frame
	app.show_page("story")
	await process_frame
	var film
	for child in app.page.get_children():
		if child.get_script() == Film: film = child
	check(film != null and film.frames.size() == 52, "full-screen opening retains actual 0..204 native capture")
	check(film.size.is_equal_approx(app.page.size), "film occupies the complete scene")
	check(film.map.cinematic, "film suppresses tactical map chrome")
	check(find_button("征募") == null and find_button("商店") == null, "story contains no harbor navigation")
	await shot("01-story-opening")
	find_button("进入舰桥").pressed.emit()
	await process_frame
	check(find_button("继续对话") != null, "dialogue retains original progression action")
	await shot("02-story-dialogue")
	Modes._skip_dialogue(app)
	await process_frame
	check(int(app.progression.data().story.step) == 1 and find_button("先告诉我舰队情况") != null, "skip stops at memory choice")
	find_button("对白回顾").pressed.emit()
	await process_frame
	check(is_instance_valid(app.modal) and not app.get_meta("story_backlog", []).is_empty(), "spoken dialogue has readable backlog")
	app.close_modal()
	# Explicit visual fixtures in a disposable account; no invented completion/reward.
	app.economy.state.progression.story.step = 5
	app.economy.state.progression.story.line = 0
	app.show_page("story")
	await process_frame
	check(find_button("任命领舰") != null and find_button("帕金斯") != null, "leader selection remains separate from appointment")
	await shot("03-story-leaders")
	app.economy.state.progression.story.step = 7
	app.show_page("story")
	await process_frame
	Modes._skip_dialogue(app)
	check(int(app.progression.data().story.step) == 7, "skip cannot bypass actual command training")
	for route in ["modes", "shop", "activity", "recruit"]:
		app.show_page(route)
		await process_frame
		check(app.screen == route, "page " + route)
		await shot(route)
	app.economy.config.gacha.weights = {"ur":100,"elite":0,"rare":0,"common":0}
	app.economy.config.gacha.featured_ur_share = 1.0
	var response: Dictionary = app.economy.recruit(1, "redesign-fixture", "up")
	var sequence: int = int(app.economy.state.draw_sequence)
	Recruit.single(app, response, 0)
	await create_timer(0.65).timeout
	await shot("recruit-face")
	await create_timer(1.2).timeout
	await shot("recruit-arrival")
	check(int(app.economy.state.draw_sequence) == sequence, "cinematic reveal does not redraw")
	app.close_modal()
	app.audio.shutdown()
	app.core.close()
	app.queue_free()
	await process_frame
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	var report := {"checks":checks,"passed":checks-failures.size(),"failures":failures,"screenshots":screenshots,"scope":"native scene and progression callbacks; UI fixtures isolated from player account"}
	var file := FileAccess.open(directory+"receipt.json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"\t")); file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
