extends SceneTree
## Regression coverage for post-navigation actions against the real staged Boot.
## Every profile is created below this review's artifact directory; normal saves are read-only.
const BootScene = preload("res://scenes/boot.tscn")
const Output: String = "res://../artifacts/boot-loading-20261114/actions/"
var checks: int = 0
var failures: Array[String] = []
var route_events: Array[String] = []
var cases: Array[Dictionary] = []
var directory: String
var boot: Control
var app: Control

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
	return ok

func frames(count: int = 3) -> void:
	for index in range(count): await process_frame

func hashes() -> Dictionary:
	var result: Dictionary = {}
	for name in ["cas_port_v1.json", "cas_port_v1.json.bak"]:
		result[name] = FileAccess.get_sha256("user://" + name)
	return result

func mount(name: String) -> bool:
	var results: Array[Dictionary] = []
	boot = BootScene.instantiate()
	boot.profile_override = directory + name + ".json"
	boot.boot_completed.connect(func(result: Dictionary) -> void: results.append(result))
	root.add_child(boot)
	var began: int = Time.get_ticks_msec()
	while results.is_empty() and Time.get_ticks_msec() - began < 60000: await process_frame
	if not check(not results.is_empty() and bool(results[0].get("ok", false)), name + " real boot succeeds"): return false
	app = boot.app
	route_events.clear()
	app.page_ready.connect(func(route: String) -> void: route_events.append(route))
	check(app.startup_ready and app.staged_navigation and app.deferred_startup, name + " uses normal deferred startup and staged routing")
	return true

func unmount() -> void:
	if is_instance_valid(app): app.running = false
	if is_instance_valid(boot): boot.queue_free()
	await frames(5)

func settled(route: String, event_start: int) -> bool:
	var began: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < 30000:
		if app.screen == route and not app._route_worker and not app.page_transition.is_busy() and route_events.size() > event_start and route_events[route_events.size() - 1] == route:
			# Let actual action coroutines resume after Main has released the route worker.
			await frames(2)
			return check(true, "real staged page and readiness event: " + route)
		await process_frame
	return check(false, "staged route timeout: " + route)

func go(route: String) -> bool:
	var start: int = route_events.size()
	app.show_page(route)
	return await settled(route, start)

func find_button(text: String) -> Button:
	for node in app.page.find_children("*", "Button", true, false):
		if node.text == text: return node
	return null

func story_launch_and_save_leave() -> void:
	if not await mount("fresh-story"): return
	if not await go("home_story"): return
	var story = app.page.get_node_or_null("HomeStory")
	if not check(story != null and story.phase == "pre" and not story.lines.is_empty(), "new account mounts actual pre-island story reader"): return
	# QA selects the last authored line; actual persistence, loans, native creation,
	# async launch and routing all run through the public story action unchanged.
	story.line_index = story.lines.size() - 1
	story._line()
	var start: int = route_events.size()
	story._advance()
	check(story.committing and app.screen == "home_story" and app._route_worker, "story remains committing while real battle loading is pending")
	var active_id: String = str(app.economy.state.get("active_run", {}).get("run_id", ""))
	check(not active_id.is_empty(), "story ending commits one actual training departure")
	story._advance()
	check(story.committing and str(app.economy.state.active_run.run_id) == active_id, "second story advance cannot relaunch or release commit guard")
	if not await settled("battle", start): return
	check(is_instance_valid(app.sea) and app.battle_controller != null, "story launch finishes with real map and battle controller")
	check(str(app.core.view.get("littoral", {}).get("version", "")) == "cas-littoral-v4", "story uses current native v4 training rules")
	var active: Dictionary = app.economy.state.get("active_run", {})
	check(active.get("request", {}).get("roster", []).size() >= 2, "story receives modern multi-company loan roster")
	check(bool(active.get("home_frozen", {}).get("borrowed_tutorial", false)), "story launch uses borrowed tutorial fleet instead of player losses")
	check(float(app.core.view.get("tick", -1)) == 0 and not app.running, "story loading never advances paused training simulation")
	check(str(active.get("run_id", "")) == active_id, "one training run survives story-to-battle loading")
	cases.append({"name": "home story async launch", "run_id": active_id, "ruleset": active.get("ruleset", ""), "roster": active.get("request", {}).get("roster", [])})

	var destination: String = app.battle_return_route
	var wallet_before: Dictionary = app.economy.state.wallet.duplicate(true)
	start = route_events.size()
	app.save_leave()
	check(app.screen == "battle" and app._route_worker, "save-leave waits beneath staged cover instead of notifying an old destination")
	if not await settled(destination, start): return
	check(is_instance_valid(app.toast_label) and app.page.is_ancestor_of(app.toast_label), "save-leave notification belongs to the new destination page")
	check(app.toast_label.text == "已保存同一行动，返港期间暂停交易。" and app.toast_label.modulate.a > 0.9, "saved-run message remains visible after destination readiness")
	check(str(app.economy.state.active_run.run_id) == active_id and app.economy.state.wallet == wallet_before, "save-leave retains one actual run without another resource debit")
	cases.append({"name": "save leave post-navigation toast", "route": destination, "toast": app.toast_label.text, "run_id": active_id})

func result_modal_routes() -> void:
	if not await mount("fresh-result"): return
	for scope in ["fleet", "base"]:
		# This fixture represents an already settled result. It never exercises or
		# pretends to verify economy settlement; the real button and cargo UI are used.
		var fixture: Dictionary = {"success": true, "content": "salvage-v4", "loot": {}, "cargo_items": []}
		if scope == "fleet": fixture["cargo_transfer_v1"] = {}
		app.last_receipt = fixture
		if not await go("result"): return
		var action: Button = find_button("整理带回物资")
		if not check(action != null, scope + " actual salvage result has organize-cargo action"): return
		var start: int = route_events.size()
		action.pressed.emit()
		check(app.screen == "result" and app._route_worker, scope + " result action really begins staged warehouse navigation")
		check(not is_instance_valid(app.modal), scope + " cargo modal is not attached to outgoing result page")
		if not await settled("warehouse", start): return
		var cargo = app.modal.get_node_or_null("CargoHold") if is_instance_valid(app.modal) else null
		check(cargo != null and cargo.stash_mode and cargo.warehouse_scope == scope, scope + " cargo modal opens after the real warehouse is ready")
		if cargo == null: return
		var modal_identity: int = app.modal.get_instance_id()
		await frames(8)
		check(is_instance_valid(app.modal) and app.modal.get_instance_id() == modal_identity and is_instance_valid(cargo), scope + " cargo modal survives rendering and transition cleanup")
		check(cargo.get_node("Warehouse_" + scope).visible and not app.page_transition.is_busy(), scope + " warehouse scope controls are usable after cover removal")
		cases.append({"name": "result-to-warehouse cargo modal", "scope": scope, "modal_survives": true})
		app.close_modal()
		await frames()

func run() -> void:
	directory = Output + "headless-" + str(OS.get_process_id()) + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	root.content_scale_size = Vector2i(1600, 900)
	root.size = Vector2i(1280, 720)
	var before: Dictionary = hashes()
	await story_launch_and_save_leave()
	await unmount()
	await result_modal_routes()
	await unmount()
	var after: Dictionary = hashes()
	check(before == after, "installed full-level normal profile and backup SHA-256 remain unchanged")
	var report: Dictionary = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "display": DisplayServer.get_name(), "scope": "real staged Boot; actual v4 story training launch and save-leave; result fixture only for UI routing and modal persistence", "user_files_before": before, "user_files_after": after, "cases": cases, "routes": route_events}
	var stream := FileAccess.open(directory + "receipt.json", FileAccess.WRITE)
	if stream != null: stream.store_string(JSON.stringify(report, "\t")); stream.close()
	print("STAGED_ACTION_REVIEW " + JSON.stringify({"passed": report.passed, "checks": checks, "failures": failures, "receipt": ProjectSettings.globalize_path(directory + "receipt.json")}))
	quit(0 if failures.is_empty() else 1)
