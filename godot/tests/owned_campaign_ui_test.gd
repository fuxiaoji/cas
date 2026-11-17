extends SceneTree
const TransitionSettle=preload("res://tests/transition_settle.gd")
## Real planner -> account-owned snapshot -> native campaign -> independent settlement.
const Main = preload("res://scenes/main.tscn")
const Economy = preload("res://scripts/economy.gd")
const Deployment = preload("res://scripts/campaign_deployment.gd")
var app
var checks := 0
var failures: Array[String] = []
var shots: Array[String] = []
var directory := "res://../artifacts/godot/owned-campaign/"
var completed := false

func _initialize() -> void: call_deferred("run")
func check(value: bool, title: String) -> bool:
	checks += 1
	if not value: failures.append(title); push_error(title)
	return value

func button(text: String, key := "", value: Variant = null) -> Button:
	for node in app.find_children("*", "Button", true, false):
		if node.is_visible_in_tree() and (node.text == text if key.is_empty() else node.has_meta(key) and node.get_meta(key) == value): return node
	return null

func click(text: String, key := "", value: Variant = null) -> bool:
	await TransitionSettle.wait_for_route(self,app)
	await process_frame
	var node := button(text, key, value)
	if not check(node != null and not node.disabled, "clickable " + text + key): return false
	node.pressed.emit()
	await process_frame
	return true

func shot(name: String) -> void:
	await TransitionSettle.wait_for_route(self,app)
	await process_frame
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(directory + name + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "screenshot " + name)
	shots.append(path)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := "user://tests/owned-campaign-%d.json" % OS.get_process_id()
	OS.set_environment("CAS_SIM_PATH", ProjectSettings.globalize_path("res://../target/release/cas-sim.exe"))
	app = Main.instantiate(); app.boot_to_title=false; app.economy = Economy.new(path); root.add_child(app)
	app.set_process(false)
	await process_frame
	await exercise()
	check(completed, "all owned campaign UI phases completed")
	app.core.close()
	app.remove_meta("campaign_deployment")
	app.queue_free()
	await process_frame
	var report := {"checks":checks,"passed":checks-failures.size(),"failures":failures,"screenshots":shots,"core":"real native campaign","account":"isolated disposable profile"}
	var file := FileAccess.open(directory + "receipt.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	for suffix in ["", ".bak", ".tmp", ".deployment.json", ".deployment.json.bak", ".deployment.json.tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print(JSON.stringify(report)); quit(0 if failures.is_empty() else 1)

func exercise() -> void:
	var source: Dictionary = {}
	for row in app.core.request({"op":"campaign"}).data.scenarios:
		if row.get("stage_ids", []).has("CAMP-ALLIES-02"): source = row
	if not check(not source.is_empty(), "verified Esperance campaign exists"): return
	app.set_meta("campaign_side", "allies"); app.set_meta("campaign_difficulty", "story")
	Deployment.open(app, source)
	var editor = app.get_meta("campaign_deployment")
	check(not editor.owned_practice and editor.ready(), "default historical borrowing still available")
	var original: Array = editor.picks.duplicate()
	if not await click("", "owned_practice_toggle", true): return
	check(editor.owned_practice and not editor.ready() and editor.owned_issue().contains("未拥有"), "own practice blocks unowned historical slots explicitly")
	check(editor.picks == original and button("开始自有舰演练").disabled, "mode toggle never removes historical hulls")
	await shot("01-unowned-slots-blocked")
	if not await click("特混编成"): return
	if not await click("编入舰船 · 位置 01"): return
	var candidates: Array = editor.visible_candidates()
	check(not candidates.is_empty() and candidates.all(func(row): return app.economy.state.owned.has(str(row.pick))), "picker contains only actually owned identities")
	var unavailable: Dictionary = editor.candidates.filter(func(row): return not app.economy.state.owned.has(str(row.pick)))[0]
	editor.select_candidate(unavailable)
	check(editor.groups().is_empty(), "direct unowned selection cannot bypass UI filter")
	var identity := "IBS-U-USN-FLETCHER"
	if not check(app.economy.state.owned.has(identity), "starter Fletcher actually owned"): return
	if not await click("", "candidate_key", "opt:" + identity): return
	check(editor.groups().size() == 1 and editor.groups()[0].ships == [identity], "actual own single-hull group created")
	check(button("", "candidate_key", "opt:" + identity).disabled, "already selected identity visibly disabled")
	editor.select_candidate(editor.card(identity))
	check(editor.groups()[0].ships.size() == 1, "direct duplicate selection rejected")
	await shot("02-owned-picker")
	if not await click("完成选舰"): return
	# Explicit fixture tests the maximum progression boundary without awarding fake battle results.
	app.economy.state.owned[identity].level = 30
	app.economy.state.owned[identity].mastery = 900
	app.economy.state.owned[identity].hp = 17
	app.economy.state.owned[identity].ammo = 9
	app.economy.save_state()
	var borrowed_request := {"op":"new_campaign","id":"CAMP-ALLIES-02","difficulty":"story","seed":6106,"profile":"coord","groups":editor.groups()}
	var baseline: Dictionary = app.core.request(borrowed_request).data
	var original_world: Dictionary = app.core.request({"op":"save"}).data
	var wallet: Dictionary = app.economy.wallet().duplicate(true)
	var history: Dictionary = app.progression.data().campaign.duplicate(true)
	await shot("03-owned-ready")
	if not await click("开始自有舰演练"): return
	if not check(app.screen == "battle" and app.core.view.has("ownedGrowth"), "planner launches actual versioned native owned practice"): return
	var active: Dictionary = app.economy.state.active_run
	check(active.context.deployment == "owned_practice" and active.context.request.ownedGrowth.hulls.size() == 1, "frozen context explicitly identifies own practice")
	var payload: Dictionary = active.context.request.ownedGrowth.hulls[0]
	check(payload.id == identity and int(payload.level) == 30 and int(payload.mastery) == 900 and int(payload.hp) == 100 and int(payload.ammo) == 100, "actual growth snapshot uses full practice condition")
	var actual: Dictionary = app.core.view.ships[0]
	var expected: Dictionary = baseline.ships[0]
	check(float(actual.hp) > float(expected.hp) * 1.049 and float(actual.hp) < float(expected.hp) * 1.051, "level 30 applies five percent native hull growth")
	for field in ["x", "y", "heading", "speed", "fleet"]:
		check(actual[field] == expected[field], "original anchor preserved " + field)
	var grown_world: Dictionary = app.core.request({"op":"save"}).data
	grown_world.campaign.erase("ownedGrowth")
	check(grown_world == original_world, "native scenario seed, enemy setup, original deployment and all other saved start fields unchanged")
	check(int(app.economy.state.owned[identity].hp) == 17 and int(app.economy.state.owned[identity].ammo) == 9 and app.economy.wallet() == wallet, "practice deployment does not charge personal maintenance or resources")
	await shot("04-owned-battle")
	var snapshot: Dictionary = app.core.request({"op":"save", "serialized":true})
	check(app.core.request({"op":"load", "save":JSON.parse_string(snapshot.serialized)}).ok and app.core.view.has("ownedGrowth"), "versioned own growth survives native snapshot reload")
	for row in app.core.view.fleets:
		app.issue({"op":"ai","fleet":int(row.id),"profile":"coord","mode":"auto","move":true,"gun":true,"torpedo":true})
	for i in range(5):
		if app.core.view.get("result") != null: break
		app.issue({"op":"step","seconds":2700})
	if not check(app.core.view.get("result") != null, "real own practice reaches terminal result"): return
	app.finish_battle()
	check(app.last_receipt.get("owned_exercise", false) and int(app.last_receipt.stars) == 0, "settlement clearly has own-practice label and zero historical stars")
	check(app.progression.data().campaign == history, "own practice cannot modify historical progression")
	check(int(app.economy.state.owned[identity].mastery) > 900 and int(app.economy.state.owned[identity].mastery) <= 930, "actual participation earns capped mastery")
	check(int(app.economy.state.owned[identity].hp) == 17 and int(app.economy.state.owned[identity].ammo) == 9, "actual battle outcome preserves personal practice condition")
	await shot("05-owned-result")
	app.show_page("campaign"); app.set_meta("campaign_difficulty", "standard")
	Deployment.open(app, source); editor = app.get_meta("campaign_deployment")
	check(button("", "owned_practice_toggle", true).disabled and not editor.owned_practice, "standard historical mode does not offer growth")
	editor.set_owned_practice(true)
	check(not editor.owned_practice, "direct mode toggle cannot enable growth outside story")
	app.close_modal(); app.show_page("modes"); await shot("06-expedition-resource-ladder-entries")
	completed = true
