extends SceneTree
const TransitionSettle=preload("res://tests/transition_settle.gd")
const Main = preload("res://scenes/main.tscn")
const Economy = preload("res://scripts/economy.gd")
const Deployment = preload("res://scripts/campaign_deployment.gd")
var app
var checks := 0
var failures: Array[String] = []
var shots: Array[String] = []
var inputs := 0
var profile := ""
var directory := ""
var completed := false

func _initialize() -> void: call_deferred("run_test")
func check(value: bool, title: String) -> bool:
	checks += 1
	if not value:
		failures.append(title)
		push_error(title)
	return value

func find(node: Node, title: String, meta := "", wanted: Variant = null) -> Button:
	if node is Button and node.is_visible_in_tree() and ((not meta.is_empty() and node.has_meta(meta) and node.get_meta(meta) == wanted) or (meta.is_empty() and node.text == title)): return node
	for child in node.get_children():
		var result := find(child, title, meta, wanted)
		if result != null: return result
	return null

func click(title: String, meta := "", wanted: Variant = null) -> bool:
	await TransitionSettle.wait_for_route(self,app)
	await process_frame
	var node := find(app, title, meta, wanted)
	if not check(node != null and not node.disabled, "clickable " + (title if meta.is_empty() else meta + "=" + str(wanted))): return false
	var parent := node.get_parent()
	while parent != null:
		if parent is ScrollContainer: parent.ensure_control_visible(node)
		parent = parent.get_parent()
	await process_frame
	await process_frame
	var at := node.get_viewport().get_screen_transform() * node.get_global_transform_with_canvas() * (node.size * 0.5)
	for pressed in [true, false]:
		var motion := InputEventMouseMotion.new()
		motion.position = at
		Input.parse_input_event(motion)
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		inputs += 2
		await process_frame
	await process_frame
	return true

func screenshot(name: String) -> void:
	await TransitionSettle.wait_for_route(self,app)
	await process_frame
	await RenderingServer.frame_post_draw
	var path := directory.path_join(name + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "screenshot " + name)
	shots.append(path)

func find_text(node: Node) -> TextEdit:
	if node is TextEdit: return node
	for child in node.get_children():
		var found := find_text(child)
		if found != null: return found
	return null

func run_test() -> void:
	profile = "user://tests/deployment-%d.json" % OS.get_process_id()
	directory = ProjectSettings.globalize_path("res://../artifacts/godot/deployment")
	DirAccess.make_dir_recursive_absolute(directory)
	OS.set_environment("CAS_SIM_PATH", ProjectSettings.globalize_path("res://../target/release/cas-sim.exe"))
	app = Main.instantiate()
	app.economy = Economy.new(profile)
	root.add_child(app)
	app.set_process(false)
	await create_timer(0.2).timeout
	await exercise()
	check(completed, "all deployment phases completed")
	app.core.close()
	app.remove_meta("campaign_deployment")
	app.queue_free()
	await process_frame
	var receipt := {"checks":checks,"passed":checks-failures.size(),"failures":failures,"screenshots":shots,"injected_events":inputs,"input_method":"application-internal Input.parse_input_event, not OS mouse automation","profile":profile,"core":"native Rust cas-sim"}
	var file := FileAccess.open(directory.path_join("receipt.json" if failures.is_empty() else "failure-%d.json" % OS.get_process_id()), FileAccess.WRITE)
	file.store_string(JSON.stringify(receipt,"\t"))
	file.close()
	for suffix in ["",".bak",".tmp",".deployment.json",".deployment.json.bak",".deployment.json.tmp",".deployment.json.export.json"]:
		if FileAccess.file_exists(profile+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(profile+suffix))
	print(JSON.stringify(receipt))
	quit(0 if failures.is_empty() else 1)

func exercise() -> void:
	var rows: Array = app.core.request({"op":"campaign"}).data.scenarios
	var source: Dictionary = {}
	for row in rows:
		if row.get("stage_ids",[]).has("CAMP-ALLIES-02"): source=row
	if not check(not source.is_empty(), "real Esperance catalogue row"): return
	app.set_meta("campaign_focus_id",source.ibs_id)
	app.set_meta("campaign_side","allies")
	app.set_meta("campaign_difficulty","story")
	app.show_page("campaign")
	if not await click("出航"): return
	var editor = app.get_meta("campaign_deployment")
	check(is_instance_valid(app.modal) and editor.fleet.historical.size()==9, "actual story launch opens nine-slot native editor")
	check(editor.fleet.options.size()==107 and editor.candidates.size()==116, "107 same-side identities plus every historical hull kept independently")
	check(editor.total()==int(editor.fleet.budget), "historical period total exactly matches native budget")
	var fletchers: Array = editor.fleet.options.filter(func(row): return str(row.class).contains("fletcher"))
	check(fletchers.size()>=5, "same-class five Fletcher identities remain selectable")
	var original: Array = editor.picks.duplicate()
	for row in editor.fleet.historical:
		if row.get("identity")!=null: check(int(editor.card(str(row.identity)).points)==int(row.points), "period price wins for " + str(row.name))
	await screenshot("01-historical-slots")
	# Change one real slot to a cheap registered identity; the original anchors stay untouched.
	if not await click("", "deployment_slot", 8): return
	var expensive: Dictionary=editor.fleet.options.filter(func(row): return str(row.kind)=="BB")[0]
	check(find(app,"","candidate_key","opt:"+str(expensive.id)).disabled,"candidate exceeding the printed budget is visibly disabled")
	var too_expensive: Array=original.duplicate()
	too_expensive[8]=str(expensive.id)
	var rejection: Dictionary=app.core.request({"op":"new_campaign","id":"CAMP-ALLIES-02","difficulty":"story","seed":6106,"fleet":too_expensive})
	check(not rejection.ok and str(rejection.get("error","")).contains("超过"),"native budget gate also rejects an over-budget plan")
	editor.filter_kind="DD"
	editor.term="FLETCHER"
	editor.render_candidates()
	check(editor.visible_candidates().size()>=5, "native picker filters by hull identity without class collapse")
	await screenshot("02-identity-picker")
	if not await click("", "candidate_key", "opt:IBS-U-USN-FLETCHER"): return
	check(str(editor.picks[8])=="IBS-U-USN-FLETCHER" and editor.picks.size()==9, "actual picker changes one identity and preserves nine slots")
	editor.preset_name.text="本机九舰预设"
	if not await click("保存为预设"): return
	check(editor.store.presets.size()==1, "actual save writes named preset")
	var saved_id := str(editor.store.presets[0].id)
	if not await click("按历史编制"): return
	check(editor.picks==original, "reset restores original full historical sequence")
	editor.preset_picker.select(1)
	if not await click("载入预设"): return
	check(str(editor.picks[8])=="IBS-U-USN-FLETCHER", "named preset reloads actual identity")
	editor.preset_picker.select(1)
	editor.preset_name.text="重命名九舰"
	if not await click("重命名"): return
	check(str(editor.store.presets[0].name)=="重命名九舰", "preset rename persists")
	# Original browser FleetPreset[] uses the same picks/profile/stageId/difficulty fields.
	if not await click("导入旧预设"): return
	find_text(app.modal).text=JSON.stringify([{"id":"old-v1","name":"旧浏览器预设","stageId":"CAMP-ALLIES-02","difficulty":"story","picks":original,"profile":"coord","updatedAt":123}])
	if not await click("确认导入预设"): return
	check(editor.store.presets.size()==2 and editor.store.presets[0].picks==original, "original FleetPreset array format migrates through actual import dialog without rewriting picks")
	if not await click("导出预设记录"): return
	check(FileAccess.file_exists(editor.store_path+".export.json"),"actual export action writes reviewable deployment record")
	var snapshot: Dictionary = app.economy.state.duplicate(true)
	Deployment.open(app,source)
	editor = app.get_meta("campaign_deployment")
	check(editor.store.presets.size()==2 and str(editor.picks[8])=="IBS-U-USN-FLETCHER", "fresh controller restores persisted draft and both legacy/native presets")
	editor.preset_picker.select(1)
	if not await click("删除"): return
	check(editor.store.presets.size()==1 and str(editor.store.presets[0].id)==saved_id,"actual delete removes only selected legacy preset")
	check(app.economy.state==snapshot, "editing and preset operations do not change economic state")
	var standard: Dictionary = app.core.request({"op":"new_campaign","id":"CAMP-ALLIES-02","difficulty":"story","seed":6106,"profile":"coord"})
	var baseline: Dictionary=standard.data
	if not await click("出航作战"): return
	check(app.screen=="battle" and app.core.view.ships.size()==9, "point-buy launches a real nine-hull native campaign")
	for i in range(9):
		var actual: Dictionary=app.core.view.ships[i]
		var expected: Dictionary=baseline.ships[i]
		check(float(actual.x)==float(expected.x) and float(actual.y)==float(expected.y) and float(actual.heading)==float(expected.heading) and float(actual.speed)==float(expected.speed) and int(actual.fleet)==int(expected.fleet), "printed slot/heading/speed/fleet preserved " + str(i+1))
	check(str(app.core.view.ships[8].characterId)=="IBS-U-USN-FLETCHER", "replacement identity survives authoritative spawn")
	app.abandon()
	app.show_page("campaign")
	Deployment.open(app,source)
	editor=app.get_meta("campaign_deployment")
	if not await click("特混编成"): return
	check(editor.mode=="taskforce" and not editor.ready(), "empty taskforce cannot launch")
	if not await click("编入舰船 · 位置 01"): return
	if not await click("", "candidate_key", "opt:IBS-U-USN-FLETCHER"): return
	check(editor.groups().size()==1 and editor.groups()[0].ships.size()==1, "actual taskforce picker accepts a single hull at the printed anchor")
	if not await click("完成选舰"): return
	await screenshot("03-taskforce-anchors")
	if not await click("特混出航"): return
	check(app.screen=="battle" and app.core.view.ships.size()==1, "single-hull taskforce is a real native campaign")
	var hull: Dictionary=app.core.view.ships[0]
	var anchor: Dictionary=editor.fleet.positions[0]
	check(float(hull.x)==float(anchor.x) and float(hull.y)==float(anchor.y) and float(hull.heading)==float(anchor.course) and float(hull.speed)==float(anchor.speed), "taskforce starts at exact native printed anchor/heading/speed")
	check(str(app.economy.state.active_run.context.deployment)=="taskforce", "frozen run marks taskforce as fictional deployment")
	for fleet_row in app.core.view.fleets:
		app.issue({"op":"ai","fleet":int(fleet_row.id),"profile":"coord","mode":"auto","move":true,"gun":true,"torpedo":true})
	for i in range(5):
		if app.core.view.get("result")!=null: break
		app.issue({"op":"step","seconds":2700})
	if not check(app.core.view.get("result")!=null,"actual taskforce reaches native terminal result"): return
	var progress: Dictionary=app.progression.data().campaign.duplicate(true)
	var wallet: Dictionary=app.economy.wallet().duplicate(true)
	app.finish_battle()
	check(app.last_receipt.get("fictional_taskforce",false) and int(app.last_receipt.stars)==0, "taskforce receipt is explicit fictional with zero history stars")
	check(app.progression.data().campaign==progress, "taskforce cannot grant historical progress")
	for key in wallet: check(int(app.economy.wallet().get(key,0))==int(wallet[key]), "taskforce cannot grant historical rewards: " + str(key))
	await screenshot("04-taskforce-result")
	app.show_page("campaign")
	app.set_meta("campaign_difficulty","standard")
	Deployment.open(app,source)
	editor=app.get_meta("campaign_deployment")
	check(find(app,"特混编成").disabled and find(app,"", "deployment_slot",0).disabled,"standard difficulty explicitly locks historical slots and taskforce")
	app.close_modal()
	app.set_meta("campaign_side","axis")
	app.set_meta("campaign_difficulty","story")
	Deployment.open(app,source)
	editor=app.get_meta("campaign_deployment")
	check(editor.fleet.options.size()==95, "axis roster retains 95 independent registered identities")
	app.close_modal()
	var blocked: Dictionary={}
	for row in rows:
		if not row.get("playable",false): blocked=row; break
	if not blocked.is_empty():
		Deployment.open(app,blocked)
		editor=app.get_meta("campaign_deployment")
		check(not editor.ready() and not editor.failure.is_empty(), "source-only scenario stays blocked with an explicit reason")
	completed=true
