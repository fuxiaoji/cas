extends SceneTree
const TransitionSettle=preload("res://tests/transition_settle.gd")
const Main = preload("res://scenes/main.tscn")
const Economy = preload("res://scripts/economy.gd")
var app
var checks := 0
var failures: Array[String] = []
var complete := false
var profile := ""
var directory := ""
var shots: Array[String] = []
var events_sent := 0

func _initialize() -> void:
	call_deferred("run_test")

func check(condition: bool, title: String) -> bool:
	checks += 1
	if not condition:
		failures.append(title)
		push_error(title)
	return condition

func _find(node: Node, title: String) -> Button:
	if node is Button and node.text == title and node.is_visible_in_tree():
		return node
	for child in node.get_children():
		var result := _find(child, title)
		if result != null:
			return result
	return null

func click(title: String) -> bool:
	await TransitionSettle.wait_for_route(self,app)
	await process_frame
	var button := _find(app, title)
	# Traverse the new optional surfaces before exercising the unchanged commands.
	if button == null and app.screen == "battle":
		if title in ["单步", "1×", "2×", "4×", "8×", "20×"]:
			app.battle_controller.hud.tools.show()
		else:
			var tab: String = "fleet" if title in ["领舰移动", "同步移动", "预览重整纵队", "脱离接触", "下达重整"] else "ship" if title in ["设为领舰", "脱队", "查看舰上雷达", "下达照明弹", "开启探照灯", "关闭探照灯", "施放烟幕", "停止施放"] else str(app.battle_controller.tab)
			app.battle_controller.show_tab(tab)
		await process_frame
		button = _find(app, title)
	if not check(button != null, "button exists: " + title):
		return false
	var ancestor := button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(button)
		ancestor = ancestor.get_parent()
	await process_frame
	await process_frame
	var location := button.get_viewport().get_screen_transform() * button.get_global_transform_with_canvas() * (button.size * 0.5)
	await pointer(location, true)
	await pointer(location, false)
	await process_frame
	await process_frame
	return true

func pointer(position: Vector2, pressed: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	Input.parse_input_event(motion)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	Input.parse_input_event(event)
	events_sent += 2
	await process_frame

func mouse_move(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	Input.parse_input_event(event)
	events_sent += 1
	await process_frame

func map_screen(world: Vector2) -> Vector2:
	return app.sea.get_viewport().get_screen_transform() * app.sea.get_global_transform_with_canvas() * app.sea.project(world)

func map_click(world: Vector2) -> void:
	var point := map_screen(world)
	await pointer(point, true)
	await pointer(point, false)
	await process_frame

func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var output := directory.path_join(name + ".png")
	check(root.get_texture().get_image().save_png(output) == OK, "screenshot: " + name)
	shots.append(output)

func call_core(command: Dictionary) -> Dictionary:
	var response: Dictionary = app.issue(command)
	check(bool(response.get("ok", false)), "real command " + str(command.op) + ": " + str(response.get("error", "ok")))
	return response

func run_test() -> void:
	profile = "user://tests/battle-ui-%d.json" % OS.get_process_id()
	directory = ProjectSettings.globalize_path("res://../artifacts/godot/immersive-battle")
	DirAccess.make_dir_recursive_absolute(directory)
	OS.set_environment("CAS_SIM_PATH", ProjectSettings.globalize_path("res://../target/release/cas-sim.exe"))
	app = Main.instantiate()
	app.economy = Economy.new(profile)
	root.add_child(app)
	app.set_process(false)
	await create_timer(0.2).timeout
	await exercise()
	check(complete, "all battle migration phases completed")
	app.core.close()
	app.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	var report := {"checks": checks, "passed": checks - failures.size(), "failures": failures, "screenshots": shots,
		"injected_events": events_sent, "input_method": "application-internal Input.parse_input_event, not OS mouse automation", "core": "native Rust cas-sim", "profile": profile}
	var file := FileAccess.open(directory.path_join("receipt.json" if failures.is_empty() else "failure-%d.json" % OS.get_process_id()), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print(JSON.stringify(report))
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(profile + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(profile + suffix))
	quit(0 if failures.is_empty() else 1)

func exercise() -> void:
	var response: Dictionary = app.core.request({"op": "new", "seed": 6106, "side": "allies", "enemy": "torpedo", "realtime": true})
	if not check(response.get("ok", false), "real native exercise initialized"):
		return
	app.campaign_mode = true
	app.run = {}
	app.enter_battle()
	await create_timer(0.2).timeout
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "actual fullscreen window")
	check(app.battle_controller.collapsed, "default tactical drawer is closed")
	check(app.sea.size == app.page.size, "map occupies full viewport and retains stable projection")
	for title in ["开始", "菜单", "战术"]:
		check(_find(app, title) != null, "quiet HUD control: " + title)
	for title in ["保存进度", "保存暂离", "结束行动"]:
		check(_find(app, title) == null, "pause-only control absent from battlefield: " + title)
	await capture("01-command-desk")
	await click("菜单")
	check(not app.running and is_instance_valid(app.modal), "pause menu stops simulation and isolates actions")
	for title in ["保存进度", "保存暂离", "结束行动", "继续行动"]:
		check(_find(app, title) != null, "pause menu owns action: " + title)
	await capture("11-pause-menu")
	await click("关闭")
	check(not app.running, "closing pause menu keeps battle paused")
	if not await click("单步"):
		return
	check(int(app.core.view.tick) == 1, "single-step advances exactly one simulated second")
	if not await click("20×"):
		return
	check(int(app.speed) == 20, "20x is a real simulation playback rate")
	app.set_process(true)
	var before_running := int(app.core.view.tick)
	if not await click("开始"):
		return
	await create_timer(0.2).timeout
	app.running = false
	app.set_process(false)
	app.update_battle()
	check(int(app.core.view.tick) > before_running + 1, "20x start actually advances the native simulation clock")
	if not await click("领舰移动"):
		return
	var ship: Dictionary = app.core.view.ships[0]
	var origin := Vector2(float(ship.x), float(ship.y))
	var destination := origin + Vector2(2600, 0)
	# The original opening sails east; this is an actual legal CAS route candidate.
	if float(ship.heading) > 180:
		destination = origin + Vector2(-2600, 0)
	var before: Dictionary = app.core.request({"op": "save"}).data
	await map_click(destination)
	check(app.sea.planned.size() == 1, "actual map click creates a waypoint draft")
	check(app.core.request({"op": "save"}).data == before, "preview never appends a command or mutates authority")
	await capture("02-route-preview")
	if not await click("取消草稿"):
		return
	check(app.sea.planned.is_empty(), "draft cancel clears local route")
	check(app.core.request({"op": "save"}).data == before, "cancelled draft leaves native save unchanged")
	if not await click("领舰移动"):
		return
	await map_click(destination)
	if app.battle_controller.preview.get("valid", false):
		if not await click("下达航线"):
			return
		check(app.core.request({"op": "save"}).data.commands.size() == before.commands.size() + 1, "commit adds exactly one real accepted route")
	else:
		check(not str(app.battle_controller.preview.get("error", "")).is_empty(), "invalid route exposes native reason")
		app.battle_controller.cancel_draft()
	app.battle_controller.show_tab("ship")
	if not await click("舰况"):
		return
	check(app.battle_controller.tab == "ship", "ship tab switches to live systems")
	await capture("03-ship-schematic")
	if not await click("战术 AI"):
		return
	check(app.battle_controller.tab == "ai", "tactical AI tab")
	await capture("04-tactical-ai")
	app.battle_controller.ask_ai()
	check(app.battle_controller.suggestion.has("orders"), "AI suggestions are real native requests")
	if not await click("战情"):
		return
	app.battle_controller.export_report()
	call_core({"op": "ai", "fleet": app.first_fleet(), "profile": "gunnery", "mode": "auto", "move": true, "gun": true, "torpedo": true})
	call_core({"op": "step", "seconds": 120})
	var live: Dictionary = app.core.view.duplicate(true)
	var wallet: Dictionary = app.economy.state.duplicate(true)
	var live_save: Dictionary = app.core.request({"op": "save", "serialized": true})
	app.battle_controller.begin_replay()
	check(app.battle_controller.replay_mode and int(app.core.view.tick) == 0, "replay reconstructs actual tick zero")
	check(not app.issue({"op": "speed", "fleet": app.first_fleet(), "speed": 20}).ok, "replay rejects mutating commands")
	app.battle_controller.seek(int(live.tick))
	check(app.core.view == live, "native replay returns exact live observation at endpoint")
	check(app.economy.state == wallet, "replay never changes economic or progression assets")
	await capture("05-native-replay")
	app.battle_controller.end_replay()
	check(app.core.view == live, "exiting replay restores same live world")
	check(str(app.core.request({"op": "save", "serialized": true}).serialized) == str(live_save.serialized), "replay does not change authoritative saved command log")
	# Select own ship and exercise drag-to-cancel against the actual map input path.
	app.battle_controller.select("ship", app.core.view.ships[0])
	app.sea.focus_fleet()
	await process_frame
	var source: Dictionary = app.core.view.ships[0]
	var center: Vector2 = app.sea.project(Vector2(source.x, source.y))
	var badge: Vector2 = app.sea.get_viewport().get_screen_transform() * app.sea.get_global_transform_with_canvas() * (center + Vector2(-24, -48))
	before = app.core.request({"op": "save"}).data
	await pointer(badge, true)
	check(not app.sea.gesture.is_empty(), "real mouse press starts gun gesture")
	var cancel_rect: Rect2 = app.sea._cancel_area()
	var cancel_at: Vector2 = app.sea.get_viewport().get_screen_transform() * app.sea.get_global_transform_with_canvas() * cancel_rect.get_center()
	await mouse_move(cancel_at)
	await pointer(cancel_at, false)
	check(app.sea.gesture.is_empty(), "drag to cancel well clears preview")
	check(app.core.request({"op": "save"}).data == before, "cancel gesture never fires or consumes ammo")
	# Exercise the remaining formation commands from the actual legacy Controls.
	if not await click("编队") or not await click("同步移动"):
		return
	ship = app.core.view.ships[0]
	origin = Vector2(ship.x, ship.y)
	destination = origin + Vector2(2600, 0)
	await map_click(destination)
	check(app.battle_controller.route_mode == "sync" and app.battle_controller.preview.get("valid", false), "synchronous route uses native multi-hull clearance preview")
	if not await click("下达航线"):
		return
	var command: Dictionary = app.core.request({"op": "save"}).data.commands[-1].request
	check(str(command.op) == "route" and str(command.mode) == "sync", "synchronous route is an accepted native command")
	before = app.core.request({"op": "save"}).data
	if not await click("预览重整纵队"):
		return
	check(app.core.request({"op": "save"}).data == before, "reform preview does not change the authority")
	if app.battle_controller.reform.get("valid", false):
		if not await click("下达重整"):
			return
		check(str(app.core.request({"op": "save"}).data.commands[-1].request.op) == "reform", "reform commits through the actual UI")
	else:
		check(not str(app.battle_controller.reform.get("error", "")).is_empty(), "unavailable reform explains actual native blocker")
	if not await click("脱离接触"):
		return
	check(str(app.core.request({"op": "save"}).data.commands[-1].request.op) == "resume", "resume command sent through actual UI")
	var successor: Dictionary = app.core.view.ships[1]
	app.battle_controller.select("ship", successor)
	if not await click("设为领舰"):
		return
	check(int(app.battle_controller._fleet().leader) == int(successor.id), "native leader actually changes")
	var fleets_before: int = app.core.view.fleets.size()
	if not await click("脱队"):
		return
	check(app.core.view.fleets.size() == fleets_before + 1, "detaching creates a real independent fleet")
	# The fixed prologue has legal close contacts from its source opening, no teleports.
	for weapon in ["gun", "torpedo"]:
		response = app.core.request({"op": "new", "seed": 6106, "side": "allies", "enemy": "gunnery", "variant": "prologue", "realtime": true})
		check(response.get("ok", false), "source prologue initialized for " + weapon)
		app.enter_battle()
		var own: Dictionary = app.core.view.ships[0]
		app.battle_controller.select("ship", own)
		app.sea.zoom = 0.9
		app.sea.pan = Vector2.ZERO
		await process_frame
		var contact: Dictionary = app.core.view.contacts[0]
		var aim: Dictionary = app.core.request({"op": "aim", "ship": int(own.id), "weapon": weapon, "target": str(contact.id)})
		check(aim.get("ok", false) and aim.data.get("valid", false), "source opening has real legal " + weapon + " target")
		var badge_local: Vector2 = app.sea.project(Vector2(own.x, own.y)) + Vector2(-24 if weapon == "gun" else 24, -48)
		var badge_point: Vector2 = app.sea.get_viewport().get_screen_transform() * app.sea.get_global_transform_with_canvas() * badge_local
		var target_point := map_screen(Vector2(contact.x, contact.y))
		var command_count: int = app.core.request({"op": "save"}).data.commands.size()
		await pointer(badge_point, true)
		await mouse_move(target_point)
		if weapon == "torpedo":
			await create_timer(0.3).timeout
			check(app.sea.gesture.has("anchor"), "torpedo gesture holds 250ms for real recommended heading")
			await mouse_move(target_point + Vector2(0, 12))
			await create_timer(0.1).timeout
			check(absf(float(app.sea.gesture.get("heading", 0)) - float(app.sea.gesture.get("base_heading", 0))) > 0.15, "torpedo heading changes through actual pointer adjustment")
			await capture("08-torpedo-aim")
		else:
			check(app.sea.gesture.get("aim", {}).has("chance"), "gun gesture shows authoritative hit probability")
			await capture("07-gun-aim")
		await pointer(target_point + (Vector2(0, 12) if weapon == "torpedo" else Vector2.ZERO), false)
		var accepted: Dictionary = app.core.request({"op": "save"}).data
		check(accepted.commands.size() == command_count + 1 and accepted.commands[-1].request.op == "fire", "mouse release commits exactly one real " + weapon + " order")
		call_core({"op": "step", "seconds": 12})
		var event_kind: String = "gun" if weapon == "gun" else "torpedo"
		check(app.core.view.events.any(func(e): return str(e.get("kind", "")) == event_kind and int(e.get("own_ship", 0)) == int(own.id)), "real " + weapon + " actually launches after gesture")
		if weapon == "gun" and app.core.view.ships[0].get("gunTarget") != null:
			call_core({"op": "gun_cancel", "ship": int(own.id)})
			check(app.core.view.ships[0].get("gunTarget") == null, "native pending continuous gun order can be cancelled")
	# Night training supplies real radar/illumination-capable equipment through the existing mode.
	response = app.core.request({"op": "new", "seed": 6106, "side": "allies", "enemy": "gunnery", "variant": "night-radar-training", "realtime": true})
	check(response.get("ok", false), "native night radar training initialized")
	app.enter_battle()
	app.battle_controller.select("ship", app.core.view.ships[0])
	await process_frame
	var radars: Array = app.core.view.ships[0].systems.get("radars", [])
	check(not radars.is_empty(), "night ship has source-bound radar equipment")
	if not radars.is_empty():
		if not await click("查看舰上雷达"):
			return
		if not await click("开启 " + str(radars[0].name)):
			return
		check(app.core.view.ships[0].systems.radars[0].powered, "actual radar dialog power command changes true observation")
	call_core({"op": "step", "seconds": 180})
	await capture("06-night-radar")
	response = app.core.request({"op": "new", "seed": 6106, "side": "allies", "enemy": "gunnery", "variant": "night-training", "realtime": true})
	check(response.get("ok", false), "native starshell training initialized")
	app.enter_battle()
	call_core({"op": "route", "fleet": 1, "mode": "follow", "speed": 15, "points": [{"x": 13000, "y": 6550}, {"x": 13000, "y": 10400}]})
	call_core({"op": "step", "seconds": 330})
	check(not app.core.view.contacts.is_empty(), "night contact acquired through real detector")
	app.battle_controller.select("ship", app.core.view.ships[0])
	app.battle_controller.select("contact", app.core.view.contacts[0])
	if not await click("下达照明弹"):
		return
	call_core({"op": "step", "seconds": 15})
	check(not app.core.view.get("illuminations", []).is_empty(), "actual starshell projectile lights a real patch of sea")
	if not await click("开启探照灯"):
		return
	check(app.core.view.ships[0].get("searchlight") is Dictionary, "searchlight command illuminates actual contact")
	if not await click("施放烟幕"):
		return
	check(bool(app.core.view.ships[0].get("smoking", false)), "smoke toggle changes authoritative hull state")
	await capture("09-night-light-smoke")
	# Borrowed training is frozen in the shared progression service, not a fake tutorial flag.
	var request := {"op": "new", "seed": 6106, "side": "allies", "enemy": "gunnery", "realtime": true}
	app.start_local_mode(request, {"mode": "training", "id": "follow", "course_id": "follow", "title": "领舰移动实操", "side": "allies"})
	check(str(app.economy.state.active_run.mode) == "training", "native training initializes a tracked borrowed run")
	app.battle_controller.show_tab("fleet")
	check(_find(app, "完成本段实操") != null, "training HUD contains its actual curriculum completion action")
	check(_find(app, "完成本段实操").disabled, "unfinished training cannot be claimed through its completion action")
	if not await click("单步"):
		return
	check(app.progression.course_status("follow").evidence.get("stepped", false), "native single-step records actual tutorial evidence")
	app.finish_battle()
	check(not app.economy.state.active_run.is_empty() and app.screen == "battle", "incomplete curriculum is rejected without settlement")
	app.battle_controller.export_save()
	check(app.economy.state.active_run.snapshot is String, "borrowed training checkpoint preserves opaque native snapshot")
	await capture("10-live-training")
	var personal: Dictionary = app.economy.state.owned.duplicate(true)
	var training_wallet: Dictionary = app.economy.wallet().duplicate(true)
	app.abandon()
	check(app.economy.state.active_run.is_empty() and app.last_receipt.get("status") == "abandoned", "explicit training abandonment records no invented victory")
	check(app.economy.state.owned == personal and app.economy.wallet() == training_wallet, "borrowed unfinished training changes no personal hull or wallet")
	var archive: Dictionary = app.progression.data().last_replay
	app.start_replay(archive)
	check(app.screen == "battle" and app.battle_controller.archive_replay and app.battle_controller.replay_mode, "archive replay opens in readonly native fullscreen without active run")
	app.battle_controller.seek(1)
	check(int(app.core.view.tick) == 1 and app.economy.wallet() == training_wallet, "archived exact snapshot reconstructs recorded tick without rewards")
	app.battle_controller.end_replay()
	check(app.screen == "archives", "archive replay returns to its archive")
	complete = true
