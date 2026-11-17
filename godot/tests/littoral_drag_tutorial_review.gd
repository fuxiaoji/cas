extends SceneTree
## Isolated presentation fixtures, not claims about a live core or real-player input.
const Tutorial = preload("res://scenes/ui/littoral_drag_tutorial.tscn")
const Token = preload("res://scripts/tactical_type_token.gd")
var checks: int = 0
var failures: Array[String] = []
var completions: int = 0
var actions: Array[String] = []
var tutorial: Control
var observation: Dictionary
var event_sequence: int = 0
var input_events: int = 0

func click(point: Vector2) -> void:
	var screen: Vector2 = root.get_screen_transform()*point
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	Input.parse_input_event(motion)
	input_events += 1
	await process_frame
	for pressed: bool in [true, false]:
		var input := InputEventMouseButton.new()
		input.position = screen
		input.global_position = screen
		input.button_index = MOUSE_BUTTON_LEFT
		input.pressed = pressed
		Input.parse_input_event(input)
		input_events += 1
		await process_frame

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func event(kind: String, data: Dictionary = {}) -> void:
	event_sequence += 1
	var payload: Dictionary = {"accepted":true, "event_id":"fixture:%d" % event_sequence}
	payload.merge(data, true)
	tutorial.notify_event(kind, payload)

func observe() -> void:
	tutorial.observe_state(observation)

func step(id: String, message: String) -> void:
	check(tutorial.current_step() == id, message+" ["+tutorial.current_step()+"]")

func run() -> void:
	root.size = Vector2i(1280, 720)
	tutorial = Tutorial.instantiate()
	tutorial.theme = preload("res://scripts/ui_design.gd").theme()
	root.add_child(tutorial)
	await process_frame
	await process_frame
	await process_frame
	tutorial.completed.connect(func() -> void: completions += 1)
	tutorial.action_complete.connect(func(id: String, _proof: Dictionary) -> void: actions.append(id))
	observation = {"tick":0.0, "littoral":{"version":"cas-littoral-v2", "frame":0, "groups":[{"id":"mcp01", "stage":"embarked", "order":"hold", "pending_deploy":null, "position":{"x":20.0,"y":30.0}}], "shots":[], "land":{"ruins":[{"id":1,"searched":false,"progress":0.0},{"id":2,"searched":false,"progress":0.0}]}}}
	tutorial.start_tutorial({"version":1,"step_id":"complete","unit_id":"mcp01","proofs":{"recover":{"source":"public_core"}}})
	observe()
	step("deploy", "forged saved UI completion is revalidated against embarked state")
	check(completions == 0, "restore alone emits no completed event")
	check(tutorial.mouse_filter == Control.MOUSE_FILTER_IGNORE, "overlay passes input to real cards and maps")
	check(tutorial.get_node("Hint/Margin/Row/Close").custom_minimum_size.y >= 48, "close-help remains a 48px touch target")
	check(tutorial.get_node("Hint").size.y <= 90, "real Noto theme initial autowrap cannot leave a giant inherited panel")
	check(tutorial.get_node("Hint/Margin/Row/Close").size.y <= 52, "close-help button never stretches to fill a tall hint")
	tutorial.set_targets({"deploy_card":Rect2(20,600,100,90),"landing_zone":Rect2(600,240,140,90),"invalid":"not a rectangle"})
	check(tutorial.target_rect("invalid") == Rect2(), "missing/invalid targets never invent a gesture location")
	check(tutorial.target_rect("deploy_card").has_area(), "real viewport target remains available")
	event("deploy_queued", {"accepted":false})
	event("drag_rejected", {"accepted":true})
	step("deploy", "rejected/misplaced drags cannot complete deploy")
	event("deploy_queued", {"unit_id":"mcp01"})
	step("approach", "accepted real deploy queue teaches approach without claiming landed")
	observation.littoral.groups[0].pending_deploy = {"status":"approaching"}
	observe()
	step("approach", "embarked plus approaching remains a waiting phase")
	observation.littoral.groups[0].stage = "transit"
	observe()
	step("land", "actual transport launch advances to landing wait")
	observation.littoral.groups[0].stage = "ground"
	observation.littoral.groups[0].pending_deploy = null
	observe()
	step("focus_land", "only actual ground stage completes landing")
	event("focus_changed", {"focus":"sea"})
	step("focus_land", "wrong map focus never completes the requested focus")
	event("focus_changed", {"focus":"land", "event_id":"same-focus"})
	step("move", "land minimap click reveals movement lesson")
	event("focus_changed", {"focus":"land", "event_id":"same-focus"})
	step("move", "duplicate events cannot skip another lesson")
	event("unit_ordered", {"unit_id":"other", "action":"move"})
	observation.littoral.groups[0].position.x += 8
	observe()
	step("move", "another group command cannot prove this group moved")
	event("unit_ordered", {"unit_id":"mcp01", "action":"move"})
	observe()
	step("move", "accepted movement order is not movement arrival")
	observation.littoral.groups[0].position.x += 8
	observation.littoral.groups[0].order = "move"
	observe()
	step("attack", "public selected group displacement confirms movement")
	event("unit_ordered", {"unit_id":"mcp01", "action":"attack", "target_id":22})
	step("attack", "stale move order cannot confirm attack")
	observation.littoral.groups[0].order = "attack"
	observe()
	step("focus_sea", "public attack order confirms attack command, not a fabricated hit")
	event("focus_changed", {"focus":"sea"})
	step("aim", "sea focus reveals naval aiming")
	event("naval_aimed", {"ship":7})
	step("focus_land_support", "real facing command leads back to land support")
	event("focus_changed", {"focus":"land"})
	step("support", "land focus reveals support card gesture")
	observation.tick = 10.0
	observation.littoral.shots = [{"id":1,"tick":10.0,"kind":"naval","source":"ship:7","target_x":100.0,"target_y":200.0}]
	observe()
	event("naval_support_queued", {"ship":7,"world":Vector2(100,200)})
	step("support", "preexisting shot at same tick cannot prove a newly queued support")
	observation.littoral.shots.append({"id":2,"tick":11.0,"kind":"naval","source":"ship:8","target_x":100.0,"target_y":200.0})
	observe()
	step("support", "another ship shot cannot confirm selected ship support")
	observation.littoral.shots.append({"id":3,"tick":11.0,"kind":"naval","source":"ship:7","target_x":800.0,"target_y":200.0})
	observe()
	step("support", "wrong target shot cannot confirm requested support")
	observation.littoral.shots.append({"id":4,"tick":11.0,"kind":"naval","source":"ship:7","target_x":100.0,"target_y":200.0})
	observe()
	step("search", "new actual matching naval shot completes support lesson")
	event("unit_ordered", {"unit_id":"mcp01","action":"search","target_id":1})
	observation.littoral.land.ruins[0].progress = .99
	observation.littoral.land.ruins[1].searched = true
	observe()
	step("search", "partial search and a different ruin do not satisfy requested search")
	observation.littoral.land.ruins[0].searched = true
	observe()
	step("withdraw", "actual searched flag reveals recovery gesture")
	event("withdraw_ordered", {"unit_id":"mcp01"})
	observation.littoral.groups[0].order = "retreat"
	observe()
	step("recover", "actual retreat order begins recovery wait")
	observation.littoral.groups[0].stage = "returning"
	observe()
	check(completions == 0, "returning is not recovered")
	observation.littoral.groups[0].stage = "lost"
	observe()
	check(completions == 0, "lost/inactive unit is never a successful recovery")
	observation.littoral.groups[0].stage = "recovered"
	observation.littoral.groups.append({"id":"mcp-other","stage":"ground","hp_percent":80,"order":"hold"})
	observe()
	step("recover", "another living group still on land blocks the fleet-return lesson")
	check(tutorial.get_node("Hint/Margin/Row/Instruction").text.contains("其余") or tutorial.get_node("Hint/Margin/Row/Instruction").text.contains("还有"), "remaining shore groups receive an explicit recovery hint")
	observation.littoral.groups.remove_at(1)
	observe()
	step("focus_sea_return", "real recovered begins fleet return rather than ending tutorial")
	check(completions == 0, "recovered at the island is not a finished sortie")
	event("focus_changed", {"focus":"sea"})
	step("return", "sea view teaches actual return route")
	event("return_ordered", {"accepted":false})
	step("return", "rejected fleet route never starts the return wait")
	event("return_ordered", {"op":"route"})
	step("sail_home", "accepted actual fleet route waits for real arrival")
	observation.littoral.exit = {"x":100.0,"y":200.0,"radius":200.0}
	observation.ships = [{"id":7,"hp":100,"x":1000.0,"y":200.0},{"id":8,"hp":100,"x":1000.0,"y":200.0}]
	observe()
	step("sail_home", "a route is not a teleport to the exit")
	observation.ships[0].x = 100.0
	observe()
	step("sail_home", "every living ship must enter the actual exit")
	observation.ships[1].hp = 0
	observe()
	step("extract", "all living ships arrived; destroyed ships do not block actual exit")
	event("extract_ordered", {"op":"littoral_extract"})
	check(completions == 0, "extract command reception is not a successful core outcome")
	observation.littoral.outcome = {"success":false,"abandoned":true}
	observe()
	check(completions == 0, "failed/abandoned outcome never completes teaching")
	observation.littoral.outcome = {"success":true,"abandoned":false}
	observe()
	check(completions == 1 and tutorial.current_step() == "complete", "actual successful extraction outcome completes once")
	observe()
	check(completions == 1, "repeated public snapshots cannot duplicate completion")
	var progress: Dictionary = tutorial.snapshot_progress()
	check(progress.version == 1 and progress.has("step_id") and progress.has("proofs"), "snapshot contains version, stable step id and diagnostic proofs")
	check(progress.proofs.recover.source == "public_core", "completion proof names core observation source")
	tutorial.replay()
	check(completions == 1, "reviewing a recovered mission does not emit a new completion/reward event")
	observe()
	check(completions == 1, "fresh recovered review observation also emits no new completion")
	tutorial.start_tutorial({"version":1,"step_id":"support","unit_id":"mcp01","proofs":{"support":true}})
	check(completions == 1 and tutorial.current_step() == "deploy", "new start cannot consume previous run's cached recovered observation")
	observation.littoral.groups[0].stage = "ground"
	observation.littoral.outcome = null
	observe()
	step("focus_land", "ground restore revalidates to a safe focus checkpoint instead of trusting saved support")
	var before: int = completions
	tutorial.close_help()
	check(not tutorial.active and completions == before, "closing help never grants completion")
	for role: String in Token.ROLES:
		check(Token.canonical_role(role) == role and Token.role_name(role) != "未识别类型", "20-profile role supported: "+role)
	check(Token.canonical_role("unregistered-person") == "unknown", "unknown role remains explicitly unknown")
	check(Token.canonical_role("anti_air") == "airdefense", "external type aliases canonicalize explicitly")
	for type: String in ["airmobile_infantry", "mechanized_infantry", "naval_infantry", "airborne_infantry", "assault_infantry", "aviation", "electronic_warfare", "medical", "anti_tank", "air_defense", "supply"]:
		check(Token.canonical_role(type) != "unknown", "core nato_type accepted: "+type)
	var token = Token.new()
	root.add_child(token)
	token.configure("air_assault", "hostile", true)
	token.set_role("medic")
	check(token.nato_type == "medic" and token.affiliation == "hostile" and token.selected, "reusable token Control exposes role/nato_type/configure/set_role API")
	observation.littoral.groups[0].stage = "ground"
	observation.littoral.groups[0].order = "hold"
	observation.littoral.land.entities = []
	observation.littoral.land.buildings = []
	observation.ships[0].gun = true
	observation.littoral.support = {"naval":[{"ship":7,"ammo":0}]}
	tutorial.start_tutorial()
	observe()
	tutorial.observe_focus("land")
	step("move", "already focused land state avoids an unnecessary double map switch")
	event("unit_ordered", {"unit_id":"mcp01","action":"move"})
	observation.littoral.groups[0].position.x += 8
	observe()
	observe()
	step("focus_sea", "publicly cleared shore never asks the player to attack a dead target")
	check(tutorial.snapshot_progress().proofs.attack.kind == "enemy_already_cleared", "cleared-shore proof is explicit rather than a fabricated attack")
	tutorial.observe_focus("sea")
	observe()
	step("focus_land_support", "no public live gun ammunition explicitly bypasses the unavailable aim lesson")
	tutorial.observe_focus("land")
	observe()
	step("withdraw", "unavailable support and actually searched ruins do not strand the player")
	check(tutorial.snapshot_progress().proofs.support.kind == "naval_unavailable", "unavailable support never claims a shot fired")
	check(tutorial.snapshot_progress().proofs.search.kind == "already_searched", "already searched ruins use explicit observed proof")
	check(completions == 1, "adaptive lesson skips alone cannot complete extraction")
	tutorial.close_help()
	observation.littoral.groups[0].stage = "embarked"
	observation.littoral.groups.append({"id":"mcp02","stage":"embarked","order":"hold","position":{"x":50,"y":60}})
	tutorial.start_tutorial()
	observe()
	event("deploy_queued", {"unit_id":"mcp02"})
	check(tutorial.unit_id == "mcp02", "tutorial follows the card actually deployed instead of always first roster entry")
	observation.littoral.groups[1].stage = "transit"
	observe()
	step("land", "second roster group real transit drives its own landing lesson")
	tutorial.close_help()
	observation.littoral.groups.remove_at(1)
	var pressed_buttons: Array[String] = []
	for index: int in 2:
		var button := Button.new()
		button.position = Vector2(100+index*180,350)
		button.size = Vector2(140,70)
		button.pressed.connect(func() -> void: pressed_buttons.append("underlay"))
		root.add_child(button)
		root.move_child(button, 0)
	observation.littoral.groups[0].stage = "embarked"
	observation.littoral.groups[0].order = "hold"
	tutorial.start_tutorial()
	observe()
	tutorial.set_targets({"deploy_card":Rect2(100,350,140,70),"landing_zone":Rect2(700,250,140,90)})
	await process_frame
	await click(Vector2(170,385))
	await click(Vector2(350,385))
	check(pressed_buttons.size() == 2, "real GUI input passes through spotlight and dim mask to underlying controls")
	check(tutorial.current_step() == "deploy", "underlay button clicks do not impersonate deployment")
	var close: Control = tutorial.get_node("Hint/Margin/Row/Close")
	await click(close.get_global_rect().get_center())
	check(not tutorial.active and completions == before, "real close-help input hides overlay without completion")
	var receipt: Dictionary = {"suite":"isolated-littoral-tutorial-components", "checks":checks, "failures":failures, "passed":failures.is_empty(), "completion_events":completions, "input_events":input_events, "actions":actions, "scope":"presentation fixtures plus overlay GUI input; live combat drag integration tested by parent suite"}
	var output: String = "C:/Users/fwj/AppData/Local/Temp/CAS-littoral-drag-tutorial-review.json"
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(receipt, "\t"))
	print(JSON.stringify(receipt))
	quit(0 if failures.is_empty() else 1)
