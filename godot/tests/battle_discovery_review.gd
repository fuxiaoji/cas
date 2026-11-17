extends SceneTree
const TransitionSettle=preload("res://tests/transition_settle.gd")
## Exercises player-facing range and known-wreck controls against the real native core.
## Test profiles are isolated; no authoritative state or inventory is fabricated.
const Main = preload("res://scenes/main.tscn")
const Economy = preload("res://scripts/economy.gd")
var app
var checks := 0
var failures: Array[String] = []
var shots: Array[String] = []
var inputs := 0
var directory := ""
var profile := ""
var profiles: Array[String] = []
var radar_only := OS.get_cmdline_user_args().has("--radar-only")
func _initialize() -> void:
	call_deferred("run_review")
func check(value: bool, description: String) -> bool:
	checks += 1
	if not value:
		failures.append(description)
		push_error(description)
	return value
func find_button(node: Node, title: String) -> Button:
	if node is Button and str(node.text)==title and node.is_visible_in_tree():
		return node
	for child in node.get_children():
		var found := find_button(child,title)
		if found!=null:
			return found
	return null
func matching_buttons(node: Node, prefix: String) -> Array[Button]:
	var result: Array[Button] = []
	if node is Button and node.is_visible_in_tree() and str(node.text).begins_with(prefix):
		result.append(node)
	for child in node.get_children():
		result.append_array(matching_buttons(child,prefix))
	return result
func click(title: String) -> bool:
	await TransitionSettle.wait_for_route(self,app)
	await process_frame
	var button := find_button(app,title)
	if not check(button!=null,"visible control: "+title):
		return false
	var parent := button.get_parent()
	while parent!=null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(button)
		parent=parent.get_parent()
	await process_frame
	var p := button.get_viewport().get_screen_transform()*button.get_global_transform_with_canvas()*(button.size*.5)
	var motion := InputEventMouseMotion.new();motion.position=p;Input.parse_input_event(motion)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new();event.position=p;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		Input.parse_input_event(event);inputs+=1
		await process_frame
	await process_frame
	return true
func capture(name: String) -> void:
	await TransitionSettle.wait_for_route(self,app)
	if DisplayServer.get_name()=="headless":return
	await process_frame
	await RenderingServer.frame_post_draw
	var path := directory.path_join(name+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"saved "+name)
	shots.append(path)
func issue(command: Dictionary) -> Dictionary:
	var result: Dictionary=app.issue(command)
	check(result.get("ok",false),"native "+str(command.op)+": "+str(result.get("error","ok")))
	return result
func new_client(suffix: String) -> void:
	profile="user://tests/discovery-%d-%s.json"%[OS.get_process_id(),suffix]
	profiles.append(profile)
	app=Main.instantiate();app.economy=Economy.new(profile)
	root.add_child(app);app.set_process(false)
	await create_timer(.15).timeout
	await process_frame
func release_client() -> void:
	app.core.close();app.queue_free()
	await process_frame
	await process_frame
func range_controls() -> void:
	check(app.sea.ranges_visible,"range overlay enabled by default")
	var before := JSON.stringify(app.core.view)
	await click("射程 ✓")
	check(not app.sea.ranges_visible,"direct range control hides overlay")
	await click("射程")
	check(app.sea.ranges_visible,"direct range control restores overlay")
	await click("视图")
	await click("射程/雷达")
	check(not app.sea.ranges_visible,"view menu uses same range state")
	check(app.battle_controller.hud.range_button.text=="射程","direct range label remains synchronized after view-menu toggle")
	check(JSON.stringify(app.core.view)==before,"range display never changes core observation")
	# Return via the displayed direct control, even when the label-sync assertion fails.
	await click(str(app.battle_controller.hud.range_button.text))
	check(app.sea.ranges_visible,"range overlay restored for screenshot")
func radar_review() -> void:
	await new_client("radar")
	app.start_local_mode({"op":"new","seed":6106,"side":"allies","enemy":"gunnery","variant":"night-radar-training","realtime":true},{"mode":"exercise","id":"radar-review","title":"雷达范围验收"})
	await process_frame
	await process_frame
	if not check(app.screen=="battle","real night training opens battle HUD"):
		await release_client();return
	var ship: Dictionary=app.core.view.ships[0]
	app.select_object("ship",ship)
	await range_controls()
	var radars: Array=ship.get("systems",{}).get("radars",[])
	check(not radars.is_empty(),"selected native ship has actual radar equipment")
	if not radars.is_empty():
		app.battle_controller.show_tab("ship")
		await click("查看舰上雷达")
		await click("开启 "+str(radars[0].name))
		if is_instance_valid(app.modal):await click("关闭")
		ship=app.core.view.ships[0]
		check(bool(ship.systems.radars[0].powered),"power control activates actual radar")
		check(float(ship.get("radarRange",0))>0,"selected radar range comes from native observation")
	app.battle_controller.hud.set_drawer(false)
	app.sea.zoom=.7;app.sea.pan=Vector2.ZERO
	app.sea.pan=app.sea.size*Vector2(.20,.56)-app.sea.project(app.sea.pos(ship))
	app.sea.queue_redraw()
	check(float(ship.get("gunRange",0))>0 and float(ship.get("torpedoRange",0))>0,"selected cannon and torpedo radii come from native observation")
	await capture("01-selected-gun-torpedo-radar")
	await release_client()
func salvage_review() -> void:
	await new_client("salvage")
	app.set_meta("next_sortie_seed",6109)
	app.launch(false)
	await process_frame
	await process_frame
	if not check(app.screen=="battle" and str(app.run.get("content",""))=="salvage-v2","real economy launches explicit v2 voyage"):
		await release_client();return
	check(float(app.speed)==4.0,"v2 voyage starts with displayed 4x speed")
	await range_controls()
	var known: Array=app.core.view.salvage.ruins.duplicate(true)
	check(not known.is_empty(),"native observation includes an initially discovered wreck")
	if known.is_empty():await release_client();return
	var wreck: Dictionary=known[0]
	await click("残骸搜索")
	var listed:=0
	for row in known:
		if find_button(app,"残骸 %d%s"%[int(row.id)," · 已打捞" if row.get("collected",false) else " · 定位并选择"])!=null:listed+=1
	check(listed==known.size() and matching_buttons(app.modal,"残骸 ").size()==known.size(),"search lists every and only seat-known wreck")
	await capture("02-known-wreck-list")
	var before:=JSON.stringify(app.core.view)
	await click("残骸 %d · 定位并选择"%int(wreck.id))
	check(app.selection_kind=="ruin" and int(app.selected.id)==int(wreck.id),"list action selects the actual wreck")
	check(app.sea.project(app.sea.pos(wreck.p)).distance_to(app.sea.size*.5)<2.0,"list action centers the actual known position")
	check(JSON.stringify(app.core.view)==before,"locating wreck does not alter world state")
	await capture("03-wreck-located")
	var close:=false
	for ship in app.core.view.ships:
		if app.sea.pos(ship).distance_to(app.sea.pos(wreck.p))<750 and float(ship.speed)<=8:close=true
	if not close:
		var fleet_id:=int(app.core.view.ships[0].fleet)
		issue({"op":"ai","fleet":fleet_id,"profile":"coord","mode":"manual","move":false,"gun":false,"torpedo":false})
		issue({"op":"route","fleet":fleet_id,"mode":"follow","speed":6,"points":[wreck.p]})
		for attempt in range(50):
			issue({"op":"step","seconds":10})
			for ship in app.core.view.ships:
				if app.sea.pos(ship).distance_to(app.sea.pos(wreck.p))<740 and float(ship.speed)<=8:close=true
			if close:break
	check(close,"actual hull satisfies collect distance and speed")
	var cargo_before: int=app.core.view.salvage.cargo.size()
	await click("打捞残骸")
	if check(app.core.view.salvage.collecting is Dictionary,"context control starts native collecting"):
		issue({"op":"step","seconds":2})
		var progress:=int(app.core.view.salvage.collecting.progress)
		await capture("04-native-collecting")
		await click("打捞残骸")
		check(int(app.core.view.salvage.collecting.progress)==progress,"duplicate collect click preserves progress")
		var seconds:=int(app.core.view.salvage.collecting.duration)-progress+1
		issue({"op":"step","seconds":seconds})
		check(app.core.view.salvage.cargo.size()>cargo_before,"completed native search adds real cargo")
		check(app.core.view.salvage.collecting==null,"native search timer completes")
		var completed := find_button(app,"已打捞")
		check(completed!=null and completed.disabled,"completed wreck context synchronizes and disables further collect")
	await click("残骸搜索")
	var collected:=find_button(app,"残骸 %d · 已打捞"%int(wreck.id))
	check(collected!=null and collected.disabled,"collected wreck is disabled in search list")
	await capture("05-collected-wreck-and-cargo")
	await release_client()
func run_review() -> void:
	directory=ProjectSettings.globalize_path("res://../artifacts/godot/battle-discovery")
	DirAccess.make_dir_recursive_absolute(directory)
	await radar_review()
	if not radar_only:await salvage_review()
	var report:={"checks":checks,"passed":checks-failures.size(),"failures":failures,"screenshots":shots,"input_events":inputs,"radar_only":radar_only,"scope":"actual native observations and player controls, isolated profiles; no world edits"}
	var file:=FileAccess.open(directory.path_join("radar-preflight.json" if radar_only else "receipt-headless.json" if DisplayServer.get_name()=="headless" else "receipt.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	for path in profiles:
		for suffix in ["",".bak",".tmp"]:
			if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)


