extends SceneTree
## Real boot + real staged menus against isolated profiles. User profiles are read-only.
const BootScene = preload("res://scenes/boot.tscn")
const Output: String = "res://../artifacts/boot-loading-20261114/"
const OldProfile: String = "res://../artifacts/mobile-home-20261113/navigation/isolated-navigation-68676.json"
var checks: int = 0
var failures: Array[String] = []
var cases: Array[Dictionary] = []
var run_directory: String
var gpu: bool = false
var screenshots: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func frames(count: int = 3) -> void:
	for index in range(count): await process_frame

func snapshot(name: String) -> void:
	if not gpu: return
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String = run_directory + name + ".png"
	check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path)) == OK, "capture " + name)
	screenshots.append(ProjectSettings.globalize_path(path))

func user_hashes() -> Dictionary:
	var result: Dictionary = {}
	for name in ["cas_port_v1.json", "cas_port_v1.json.bak"]:
		var path: String = "user://" + name
		result[name] = {"exists": FileAccess.file_exists(path), "sha256": FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""}
	return result

func write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var stream := FileAccess.open(path, FileAccess.WRITE)
	if stream == null: return false
	stream.store_buffer(bytes)
	stream.flush()
	stream.close()
	return true

func launch(profile: String, result_list: Array) -> Control:
	var boot: Control = BootScene.instantiate()
	boot.profile_override = profile
	boot.boot_completed.connect(func(result: Dictionary) -> void: result_list.append(result.duplicate(true)))
	root.add_child(boot)
	return boot

func wait_boot(boot: Control, results: Array, expected_count: int, info: Dictionary) -> bool:
	var began: int = Time.get_ticks_msec()
	var stages: Array[Dictionary] = []
	var last_stage: String = ""
	while results.size() < expected_count and Time.get_ticks_msec() - began < 60000:
		if is_instance_valid(boot.loading):
			var stage: String = str(boot.loading.stage_text)
			if stage != last_stage:
				stages.append({"stage": stage, "progress": boot.loading.progress_value, "visible": boot.loading.visible})
				last_stage = stage
		await process_frame
	info["stages_" + str(expected_count)] = stages
	info["elapsed_ms_" + str(expected_count)] = Time.get_ticks_msec() - began
	check(results.size() >= expected_count, str(info.name) + " boot_completed within timeout")
	return results.size() >= expected_count

func wait_route(app: Control, route: String, events: Array[String], event_start: int, shot_name: String = "") -> bool:
	var began: int = Time.get_ticks_msec()
	var did_shot: bool = false
	var saw_cover: bool = false
	while Time.get_ticks_msec() - began < 25000:
		if app.page_transition.is_covered():
			saw_cover = true
			if not shot_name.is_empty() and not did_shot:
				did_shot = true
				await snapshot(shot_name)
		if events.size() > event_start and events[events.size() - 1] == route and app.screen == route and not app._route_worker and not app.page_transition.is_busy():
			check(saw_cover, "staged " + route + " has opaque readiness barrier")
			return true
		await process_frame
	check(false, "staged " + route + " reaches page_ready and releases cover")
	return false

func drop_boot(boot: Control) -> void:
	boot.queue_free()
	await frames(5)

func successful_boot(boot: Control, results: Array, info: Dictionary, count: int = 1) -> bool:
	if not await wait_boot(boot, results, count, info): return false
	check(bool(results[count - 1].get("ok", false)), str(info.name) + " boot result succeeds")
	if not bool(results[count - 1].get("ok", false)): return false
	check(boot.completed and not boot.failed, str(info.name) + " completion state")
	check(not boot.loading.visible and boot.loading.mouse_filter == Control.MOUSE_FILTER_IGNORE, str(info.name) + " completed loading releases input")
	check(is_instance_valid(boot.app) and boot.app.startup_ready, str(info.name) + " Main startup_ready")
	var app: Control = boot.app
	check(app.screen == "title" and app.page.get_node_or_null("TitleScreen") != null, str(info.name) + " real title is mounted")
	check(app.fleets != null and app.progression != null and app.arena != null and app.home != null, str(info.name) + " services created after valid profile")
	info["results"] = results.duplicate(true)
	return true

func exercise_routes(app: Control, info: Dictionary) -> void:
	var events: Array[String] = []
	app.page_ready.connect(func(route: String) -> void: events.append(route))
	app.page_motion = true
	app.set_meta("reduced_motion", false)
	for route in ["harbor", "roster", "settings"]:
		var old_page: Control = app.page
		var old_screen: String = app.screen
		var start: int = events.size()
		app.show_page(route)
		check(app.screen == old_screen and app.page == old_page, "staged " + route + " does not replace uncovered page synchronously")
		if not await wait_route(app, route, events, start, "fresh-harbor-loading" if route == "harbor" else ""): return
		check(is_instance_valid(app.page) and app.page != old_page and app.page.process_mode != Node.PROCESS_MODE_DISABLED, "staged " + route + " new content is interactive")
		await snapshot("fresh-" + route)
	var back_start: int = events.size()
	app.go_back()
	if not await wait_route(app, "roster", events, back_start): return
	check(app.screen == "roster", "back restores previous menu instead of always harbor")
	var home_start: int = events.size()
	app.go_home()
	if not await wait_route(app, "harbor", events, home_start): return
	check(app.screen == "harbor", "direct home works after staged back")
	info["routes"] = events.duplicate()

func compare_old_state(app: Control, original: Dictionary, label: String) -> void:
	var owned_before: Dictionary = original.get("owned", {})
	var owned_after: Dictionary = app.economy.state.get("owned", {})
	var missing: Array[String] = []
	for identity in owned_before:
		if not owned_after.has(identity): missing.append(str(identity))
	check(missing.is_empty(), label + " preserves every owned ship identity")
	check(app.economy.state.get("active_run", {}) == original.get("active_run", {}), label + " preserves active sortie snapshot")
	check(app.economy.state.get("fleet_book", []) == original.get("fleet_book", []), label + " preserves saved player fleets")
	check(app.run.is_empty() and not app.running, label + " title never starts or charges a sortie")

func run() -> void:
	gpu = DisplayServer.get_name() != "headless"
	root.content_scale_size = Vector2i(1600, 900)
	root.size = Vector2i(1280, 720)
	run_directory = Output + ("gpu-" if gpu else "headless-") + str(OS.get_process_id()) + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(run_directory))
	var before: Dictionary = user_hashes()
	var original_bytes: PackedByteArray = FileAccess.get_file_as_bytes(OldProfile)
	var original: Variant = JSON.parse_string(original_bytes.get_string_from_utf8())
	check(original is Dictionary and not original.is_empty(), "valid original-account source is readable")
	if not original is Dictionary or original.is_empty():
		finish(before)
		return

	var fresh: Dictionary = {"name": "fresh profile"}
	var fresh_results: Array = []
	var boot: Control = launch(run_directory + "fresh.json", fresh_results)
	check(is_instance_valid(boot.loading) and boot.loading.visible and not is_instance_valid(boot.app), "lightweight loading mounts before Main exists")
	await snapshot("fresh-first-frame")
	if await successful_boot(boot, fresh_results, fresh):
		await snapshot("fresh-title")
		await exercise_routes(boot.app, fresh)
	cases.append(fresh)
	await drop_boot(boot)

	var old: Dictionary = {"name": "valid original-account clone", "source_sha256": FileAccess.get_sha256(OldProfile)}
	var old_path: String = run_directory + "original-clone.json"
	check(write_bytes(old_path, original_bytes), "write only isolated original-account clone")
	var old_results: Array = []
	boot = launch(old_path, old_results)
	if await successful_boot(boot, old_results, old):
		compare_old_state(boot.app, original, "old account boot")
	cases.append(old)
	await drop_boot(boot)

	var damaged: Dictionary = {"name": "all-NUL profile and backup"}
	var damaged_path: String = run_directory + "all-nul.json"
	var null_bytes := PackedByteArray()
	null_bytes.resize(137498)
	null_bytes.fill(0)
	check(write_bytes(damaged_path, null_bytes) and write_bytes(damaged_path + ".bak", null_bytes), "construct isolated all-NUL primary and backup")
	var damaged_hash: String = FileAccess.get_sha256(damaged_path)
	var damaged_results: Array = []
	boot = launch(damaged_path, damaged_results)
	if await wait_boot(boot, damaged_results, 1, damaged):
		check(not bool(damaged_results[0].get("ok", true)) and boot.failed and not boot.completed, "corrupt profile emits explicit failed boot")
		check(boot.loading.visible and boot.loading.failed, "corrupt profile shows readable failure instead of black screen")
		check(boot.loading.get_node("Center/Content/Actions").visible and not str(boot.loading.failure_message).is_empty(), "failure exposes explanation, retry and quit")
		check(is_instance_valid(boot.app) and not boot.app.startup_ready and boot.app.screen == "startup_error", "corrupt profile never enters playable Main")
		if is_instance_valid(boot.app):
			check(boot.app.fleets == null and boot.app.progression == null and boot.app.arena == null and boot.app.home == null, "corrupt profile cannot construct gameplay services")
			check(boot.app.economy.state.is_empty(), "corrupt profile cannot fabricate an empty account")
			boot.app.show_page("harbor")
			check(boot.app.screen == "startup_error", "routing cannot bypass corrupt-profile guard")
		check(FileAccess.get_sha256(damaged_path) == damaged_hash and FileAccess.get_sha256(damaged_path + ".bak") == damaged_hash, "failed boot preserves damaged QA primary and backup byte for byte")
		await snapshot("damaged-readable-failure")
		check(write_bytes(damaged_path, original_bytes), "replace QA primary only with valid original-account clone")
		var failed_app_id: int = boot.app.get_instance_id()
		boot.loading.retry_requested.emit()
		if await successful_boot(boot, damaged_results, damaged, 2):
			check(boot.boot_attempt == 2 and boot.app.get_instance_id() != failed_app_id, "retry starts a fresh guarded Main")
			check(not boot.loading.failed, "successful retry clears previous failure")
			compare_old_state(boot.app, original, "recovered clone")
			await snapshot("recovered-title")
	cases.append(damaged)
	await drop_boot(boot)
	finish(before)

func finish(before: Dictionary) -> void:
	var after: Dictionary = user_hashes()
	check(before == after, "normal user primary and backup SHA-256 unchanged")
	var result: Dictionary = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "display": DisplayServer.get_name(), "scope": "real boot.tscn, isolated profiles, startup guard and staged menus; no combat acceptance", "user_files_before": before, "user_files_after": after, "cases": cases, "screenshots": screenshots}
	var stream := FileAccess.open(run_directory + "receipt.json", FileAccess.WRITE)
	if stream != null: stream.store_string(JSON.stringify(result, "\t")); stream.close()
	print("BOOT_LOADING_REVIEW " + JSON.stringify({"passed": result.passed, "checks": checks, "failures": failures, "receipt": ProjectSettings.globalize_path(run_directory + "receipt.json")}))
	quit(0 if failures.is_empty() else 1)
