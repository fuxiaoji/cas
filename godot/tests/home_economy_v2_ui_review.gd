extends SceneTree
## Main scene, production controls, isolated ordinary account; explicit synthetic elapsed-time fixtures.
const OUTPUT: String = "res://../artifacts/home-economy-v2-ui-20261116/"
var checks: int = 0
var failures: Array[String] = []
var input_events: int = 0
var account
var home
var app
var formal_hash: String
var backup_hash: String
var finished: bool = false

func _initialize() -> void:
	call_deferred("run")
	watchdog()

func watchdog() -> void:
	await create_timer(110).timeout
	if not finished: push_error("order UI review failed to reach final receipt"); quit(2)

func check(value: bool, message: String) -> bool:
	checks += 1
	if not value: failures.append(message); push_error(message)
	return value

func frames(count: int = 5) -> void:
	for i: int in range(count): await process_frame

func emit_input(event: InputEvent) -> void:
	input_events += 1
	root.push_input(event, true)

func find_button(holder: Node, title: String) -> Button:
	if holder == null: return null
	for node: Node in holder.find_children("*", "Button", true, false):
		if node.text == title and node.is_visible_in_tree(): return node
	return null

func click(node: Control) -> void:
	if not check(node != null, "requested production control exists"): return
	var parent: Node = node.get_parent()
	while parent != null:
		if parent is ScrollContainer: parent.ensure_control_visible(node)
		parent = parent.get_parent()
	await frames(3)
	var point: Vector2 = node.get_global_transform_with_canvas() * (node.size * .5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	emit_input(motion)
	await process_frame
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = down
		emit_input(event)
		await create_timer(.03).timeout
	await frames()

func drag_slider(node: HSlider) -> void:
	var transform: Transform2D = node.get_global_transform_with_canvas()
	var start: Vector2 = transform * Vector2(node.size.x * .02, node.size.y * .5)
	var end: Vector2 = transform * Vector2(node.size.x * .10, node.size.y * .5)
	var down := InputEventMouseButton.new()
	down.position = start; down.button_index = MOUSE_BUTTON_LEFT; down.button_mask = MOUSE_BUTTON_MASK_LEFT; down.pressed = true
	emit_input(down); await process_frame
	for step: int in range(1, 5):
		var move := InputEventMouseMotion.new()
		move.position = start.lerp(end, float(step) / 4.0); move.relative = (end - start) / 4.0; move.button_mask = MOUSE_BUTTON_MASK_LEFT
		emit_input(move); await process_frame
	var up := InputEventMouseButton.new()
	up.position = end; up.button_index = MOUSE_BUTTON_LEFT; up.pressed = false
	emit_input(up); await frames()

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames(3)
	RenderingServer.force_draw()
	check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + name + ".png")) == OK, "actual GPU frame " + name)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	OS.set_environment("CAS_WORLD3D", "1")
	formal_hash = FileAccess.get_sha256("user://cas_port_v1.json")
	backup_hash = FileAccess.get_sha256("user://cas_port_v1.json.bak")
	account = load("res://scripts/economy.gd").new(OUTPUT + "ordinary-%d.json" % OS.get_process_id())
	check(account.new_profile().ok and account.load_state().ok, "isolated ordinary account is real and durable")
	account.state.progression.first_voyage_canon.active = false
	home = load("res://scripts/home_service.gd").new(account)
	home.state().unlocked = true; home.state().tutorial_complete = true; home.state().drag_tutorial_completed = true
	for key: String in home.RESOURCE_NAMES: home.state().resources[key] = 5000
	var geometry: Dictionary = home.geometry_v4()
	var placed: Dictionary = {}
	for cell: Dictionary in geometry.get("construction_grid", {}).get("buildable_cells", []):
		var target := Vector2i(int(cell.x), int(cell.y))
		if home.building_at(target).is_empty(): placed = home.place("recycler", target); break
	if not check(placed.get("ok", false), "real native-checked home construction creates processing facility"): finish(); return
	var facility: Dictionary = placed.building
	var facility_id: String = str(facility.id)
	app = load("res://scenes/main.tscn").instantiate()
	app.economy = account; app.boot_to_title = false; app.immersive_fullscreen = false; app.deferred_startup = false; app.staged_navigation = false; app.fullscreen_battle = false
	root.content_scale_size = Vector2i(1600, 900); root.size = Vector2i(1280, 720); root.add_child(app)
	await frames(10)
	app.page_motion = false; app.page_transition.cancel(); AudioServer.set_bus_mute(0, true); app.show_page("home")
	await frames(10)
	var island: Node = app.page.find_child("HomeIsland", true, false)
	if not check(island != null, "production main mounts the actual home page"): finish(); return
	island._cell(Vector2i(int(facility.cell.x), int(facility.cell.y)))
	await frames(5)
	await click(find_button(island, "加工订单"))
	if not check(app.modal != null and app.modal.find_child("OrderBatchSlider", true, false) != null, "facility action opens actual order sheet"): finish(); return
	var slider: HSlider = app.modal.find_child("OrderBatchSlider", true, false)
	await drag_slider(slider)
	check(int(slider.value) > 1 and int(slider.value) < int(slider.max_value), "real pointer drag changes batch count")
	var start_button: Button = app.modal.find_child("StartProcessingOrder", true, false)
	var quote: Dictionary = start_button.get_meta("quote", {})
	check(int(quote.get("batches", 0)) == int(slider.value) and bool(quote.get("ready", false)), "displayed quote follows selected whole batch count")
	var supplies_before: Dictionary = home.state().resources.duplicate(true)
	var wallet_before: Dictionary = account.state.wallet.duplicate(true)
	await shot("order-preview")
	await click(start_button)
	check(home.state().get("economy_v2", {}).get("jobs", {}).has(facility_id), "actual confirm creates one paid order")
	for key: String in quote.home_cost: check(int(home.state().resources[key]) == int(supplies_before[key]) - int(quote.home_cost[key]), "UI debits only quoted input " + key)
	check(home._same(wallet_before, account.state.wallet), "island order cannot silently debit silver or recruitment balances")
	check(find_button(app.modal, "取消未完成订单") != null, "running sheet shows real cancellation action")
	await shot("order-running")
	# Explicit clock fixture: two batches have elapsed; it never changes costs or output counts.
	var job: Dictionary = home.state().economy_v2.jobs[facility_id]
	job.checkpoint_at = int(Time.get_unix_time_from_system()) - int(job.seconds) * 2 - 30
	job.work_seconds = 0
	island._processing_orders(facility_id); await frames(5)
	var supply: int = int(home.state().resources.credits)
	await click(find_button(app.modal, "收取产物"))
	check(int(home.state().resources.credits) == supply + 40, "pointer claim credits exactly two matured island-supply batches")
	check(home._same(wallet_before, account.state.wallet), "claim UI keeps wallet silver and all other currencies separate")
	await shot("order-partial-claim")
	await click(find_button(app.modal, "取消未完成订单"))
	if not check(find_button(app.modal, "确认") != null, "cancel first presents actual refund confirmation"): finish(); return
	var before_cancel: Dictionary = account.state.duplicate(true)
	await click(find_button(app.modal, "取消"))
	check(home._same(before_cancel, account.state), "canceling confirmation neither refunds nor charges")
	island._processing_orders(facility_id); await frames(4)
	await click(find_button(app.modal, "取消未完成订单"))
	var shown_cancel: Dictionary = home.processing().cancel_preview(facility_id)
	# Explicit elapsed-time fixture while the real confirmation sheet is open.
	job = home.state().economy_v2.jobs[facility_id]
	job.checkpoint_at = int(job.checkpoint_at) - int(job.seconds)
	var stale_state: Dictionary = account.state.duplicate(true)
	await click(find_button(app.modal, "确认"))
	check(home._same(stale_state, account.state), "stale refund confirmation performs no cancellation, charge or smaller refund")
	var reapproval: bool = false
	for text: Node in app.modal.find_children("*", "Label", true, false):
		if "重新确认当前退款" in str(text.text): reapproval = true
	check(reapproval and find_button(app.modal, "确认") != null, "changed refund explicitly opens a new current-price confirmation")
	var cancel_quote: Dictionary = home.processing().cancel_preview(facility_id)
	check(int(cancel_quote.refund_batches) < int(shown_cancel.refund_batches), "test actually crossed a boundary that reduced refundable work")
	await shot("order-refund-reconfirmation")
	var before_refund: Dictionary = home.state().resources.duplicate(true)
	await click(find_button(app.modal, "确认"))
	for key: String in cancel_quote.home_refund: check(int(home.state().resources[key]) == int(before_refund[key]) + int(cancel_quote.home_refund[key]), "confirmed cancel returns exactly unstarted input " + key)
	check(home.state().economy_v2.jobs.has(facility_id), "newly matured unclaimed product survives guarded cancellation")
	var final_supply: int = int(home.state().resources.credits)
	await click(find_button(app.modal, "收取产物"))
	check(int(home.state().resources.credits) == final_supply + 20 and not home.state().economy_v2.jobs.has(facility_id), "claim after reapproved cancel grants remaining mature batch once and frees slot")
	app.close_modal(); await frames()
	central_commit_clocks(facility_id)
	finish()

func central_commit_clocks(facility_id: String) -> void:
	var current: int = int(Time.get_unix_time_from_system())
	check(home.processing().start(facility_id, "civilian_order", 8, "central-clock-order").ok, "central hook fixture starts a real paid order")
	var job: Dictionary = home.state().economy_v2.jobs[facility_id]
	job.work_seconds = 0; job.checkpoint_at = current - 120
	var before: Dictionary = account.state.duplicate(true)
	account.state.active_run = {"mode": "explicit-central-commit-departure-fixture"}
	check(account._commit(before, "QA departure").ok, "actual central account commit accepts departure fixture")
	check(int(job.work_seconds) >= 120 and int(job.work_seconds) <= 125, "central _commit alone checkpoints old idle interval")
	job.checkpoint_at = current - 600
	before = account.state.duplicate(true)
	var saved_work: int = int(job.work_seconds)
	account.state.active_run = {}
	check(account._commit(before, "QA return").ok, "actual central commit accepts return fixture")
	check(int(job.work_seconds) == saved_work and int(job.checkpoint_at) >= current, "central return excludes simulated battle interval without explicit module call")
	job.checkpoint_at = current - 60
	before = account.state.duplicate(true)
	for building: Dictionary in home.state().buildings:
		if str(building.id) == facility_id: building.hp = 0
	check(account._commit(before, "QA facility damaged").ok and int(job.work_seconds) >= saved_work + 60, "central facility-damage commit settles previous live work")
	job.checkpoint_at = current - 600
	saved_work = int(job.work_seconds)
	check(home.repair_building(facility_id).ok and int(job.work_seconds) == saved_work and int(job.checkpoint_at) >= current, "real existing repair transaction excludes disabled interval")
	var old_path: String = account.save_path
	var blocker: String = OUTPUT + "commit-blocker-%d" % OS.get_process_id()
	FileAccess.open(blocker, FileAccess.WRITE).store_string("intentional failed save fixture")
	account.save_path = blocker + "/account.json"
	job.checkpoint_at = current - 90
	before = account.state.duplicate(true)
	account.state.active_run = {"mode": "failed-central-departure"}
	check(not account._commit(before, "expected failure").ok and home._same(before, account.state), "actual central hook and failed durable save roll clocks and all account state back")
	account.save_path = old_path
	check(account.save_state().ok, "actual ordinary candidate account remains loadable")

func finish() -> void:
	finished = true
	if is_instance_valid(app):
		app.running = false
		if app.core != null: app.core.close()
		root.remove_child(app); app.queue_free()
	check(FileAccess.get_sha256("user://cas_port_v1.json") == formal_hash and FileAccess.get_sha256("user://cas_port_v1.json.bak") == backup_hash, "normal account and backup remain unchanged")
	var report: Dictionary = {"checks": checks, "failures": failures, "actual_input_events": input_events, "scope": "real Main scene and production controls through root viewport input; ordinary isolated account; synthetic elapsed-clock and run-transition fixtures; not OS pointer/Android", "formal_sha256": formal_hash, "backup_sha256": backup_hash}
	FileAccess.open(OUTPUT + "receipt.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("HOME_ORDERS_UI ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
