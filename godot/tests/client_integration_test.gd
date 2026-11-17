extends SceneTree
const TransitionSettle=preload("res://tests/transition_settle.gd")
## Drives the real scene through engine-injected pointer events and public UI/core methods.
## Uses a separate profile. It never edits a save or invents a battle receipt.
## Explicit v3 compatibility suite. New-player v4 packing/search is tested separately.

const MainScene = preload("res://scenes/main.tscn")
const Economy = preload("res://scripts/economy.gd")
class LegacyEconomy extends "res://scripts/economy.gd":
	# Pin only the content version at the preview boundary; all real transactions,
	# native commands, timers, snapshots and results below remain the public flow.
	func preview_sortie(seed:int,basic:bool=false,mission:Dictionary={}) -> Dictionary:
		var prepared:Dictionary=super.preview_sortie(seed,basic,mission)
		if prepared.get("ok",false):
			prepared["content"]="salvage-v3"
			prepared.erase("cargo_v4")
		return prepared
var app
var checks := 0
var failures: Array[String] = []
var shots: Array[String] = []
var input_events := 0
var path := ""
var evidence_dir := ""
var success_run := ""
var failure_run := ""
var campaign_tick := 0
var exercise_completed := false

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, title: String) -> bool:
	checks += 1
	if not value:
		failures.append(title)
		push_error(title)
	return value

func _new_client() -> void:
	app = MainScene.instantiate()
	app.boot_to_title=false
	app.economy = LegacyEconomy.new(path)
	root.add_child(app)
	app.set_process(false)
	await create_timer(0.18).timeout
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw

func _release_client() -> void:
	if is_instance_valid(app):
		app.core.close()
		app.queue_free()
		await process_frame
		await process_frame
		await create_timer(0.15).timeout

func _text(value: String) -> String:
	return " ".join(value.strip_edges().replace("　", " ").split(" ", false))

func _find_button(node: Node, title: String) -> Button:
	if node is Button and _text(node.text) == _text(title) and node.is_visible_in_tree():
		return node
	for child in node.get_children():
		var result := _find_button(child, title)
		if result != null:
			return result
	return null

func click(title: String) -> bool:
	await TransitionSettle.wait_for_route(self,app)
	await process_frame
	var target := _find_button(app, title)
	if not check(target != null, "visible button: " + title):
		print("MISSING BUTTON SCREEN=", app.screen, " wanted=", title)
		await screenshot("debug-missing-button")
		return false
	# Godot's input API accepts window coordinates, before viewport stretch.
	# Official transform chain: viewport screen transform * global canvas transform.
	var position := target.get_viewport().get_screen_transform() * target.get_global_transform_with_canvas() * (target.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = position
	Input.parse_input_event(motion)
	await process_frame
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = position
	Input.parse_input_event(down)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = position
	Input.parse_input_event(up)
	input_events += 3
	await process_frame
	await process_frame
	return true

func screenshot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await TransitionSettle.wait_for_route(self,app)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var output := evidence_dir.path_join(name + ".png")
	if check(image != null and image.save_png(output) == OK, "saved real viewport: " + name):
		shots.append(output)

func issue(command: Dictionary) -> Dictionary:
	var response: Dictionary = app.issue(command)
	check(bool(response.get("ok", false)), "core command " + str(command.get("op")) + ": " + str(response.get("error", "ok")))
	return response

func _run() -> void:
	path = "user://tests/client-integration-v3-%d.json" % OS.get_process_id()
	evidence_dir = ProjectSettings.globalize_path("res://../artifacts/godot/legacy-v3-integration")
	DirAccess.make_dir_recursive_absolute(evidence_dir)
	if not OS.has_environment("CAS_SIM_PATH"):OS.set_environment("CAS_SIM_PATH", ProjectSettings.globalize_path("res://../target/release/cas-sim.exe"))
	await _new_client()
	var final_only: bool = OS.get_cmdline_user_args().has("--final-visual")
	if final_only:
		await _final_conditions()
	else:
		await _exercise()
	check(exercise_completed, "all integration phases complete without early runtime abort")
	await _release_client()
	var report := {"checks": checks, "passed": checks - failures.size(), "failures": failures,
		"input_method": "Godot Input.parse_input_event; application-internal pointer injection, not OS mouse automation",
		"injected_pointer_events": input_events, "visible_renderer": DisplayServer.get_name(),
		"screenshots": shots, "isolated_profile": ProjectSettings.globalize_path(path),
		"successful_run_id": success_run, "failed_run_id": failure_run, "campaign_tick": campaign_tick,
		"native_process": OS.get_environment("CAS_SIM_PATH"), "content_scope":"salvage-v3 compatibility; v4 has separate complete packing/search verification", "synthetic_battle_receipts": false, "targeted_visual_supplement": final_only}
	var file := FileAccess.open(evidence_dir.path_join(("final-visual-conditions.json" if final_only else "receipt.json") if failures.is_empty() else "failed-%d.json" % OS.get_process_id()), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print(JSON.stringify(report))
	for suffix in ["", ".bak", ".tmp"]:
		var candidate := ProjectSettings.globalize_path(path + suffix)
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)
	await create_timer(0.2).timeout
	quit(0 if failures.is_empty() else 1)

func _exercise() -> void:
	if not check(app.screen == "harbor" and app.economy.formation.size() == 3, "real main scene initializes separate three-ship profile"):
		return
	await screenshot("01-harbor")
	if not await click("编队"):
		return
	check(app.screen == "formation", "pointer navigation reaches formation")
	await screenshot("02-formation")
	if not await click("‹  返回"): return
	if not await click("征募"):
		return
	if not await click("常驻征募"):
		return
	var tickets_before := int(app.economy.wallet().tickets)
	if not await click("征募十次   ◇ 10"):
		return
	check(int(app.economy.wallet().tickets) == tickets_before - 10, "real UI ten-draw consumes ten tickets once")
	check(is_instance_valid(app.modal), "real recruit results modal appears")
	await _reveal_conditions()
	await screenshot("03-recruit-results")
	if not await click("确认入列"):
		return
	if not await click("‹ 返回"):
		return
	if not await click("编队"):
		return
	var original_members:Array=app.economy.formation.duplicate()
	check(app.fleets.set_members(original_members.slice(0,2)).ok,"split first owned fleet without cloning hulls")
	check(app.fleets.create("护航编队").ok,"create second real sortie fleet")
	check(app.fleets.set_members([original_members[2]]).ok,"assign third hull to escort group")
	check(app.fleets.select(str(app.fleets.active().id),true).ok,"select two owned groups for same sortie")
	app.show_page("formation")
	var stock_before := int(app.economy.wallet().ammo_stock)
	var required := int(app.economy.formation_preview().ammo_required)
	app.set_meta("next_sortie_seed",6109)
	if not await click("确认出航"):
		return
	if not check(app.screen == "battle" and not app.run.is_empty() and not app.campaign_mode, "real UI launches committed native sortie"):
		return
	success_run = str(app.run.run_id)
	await create_timer(0.15).timeout
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "native battle window enters actual fullscreen mode")
	check(Vector2i(root.get_texture().get_image().get_size()) == DisplayServer.screen_get_size(DisplayServer.window_get_current_screen()), "battle viewport matches physical screen resolution")
	check(int(app.economy.wallet().ammo_stock) == stock_before - required, "departure deducts committed deployment exactly once")
	check(int(app.core.view.salvage.score) == int(app.run.score), "native fleet score matches frozen economy snapshot")
	check(str(app.run.get("content",""))=="salvage-v3" and str(app.core.view.salvage.get("generatorVersion",""))=="archipelago-3","explicit legacy sortie preserves versioned procedural v3 ecology")
	check(app.economy.state.active_run.get("snapshot") is String, "UI checkpoint stores exact native serialized string")
	await screenshot("04-salvage-sea")
	check(app.core.view.fleets.size()==2 and app.core.view.ships.size()==3,"two selected fleet groups spawn three distinct real hulls")
	for group in app.core.view.fleets:
		issue({"op":"ai","fleet":int(group.id),"profile":"coord","mode":"manual","move":false,"gun":false,"torpedo":false})
	var target:Dictionary=app.core.view.salvage.ruins[0].p
	var leader:Dictionary=app.core.view.ships[0]
	var distance:=Vector2(float(target.x)-float(leader.x),float(target.y)-float(leader.y)).length()
	issue({"op":"route","fleet":1,"mode":"follow","speed":6,"points":[target]})
	issue({"op":"step","seconds":int(ceil(distance/3.0867))+95})
	issue({"op": "salvage_collect", "ruin": 1})
	var duration:=int(app.core.view.salvage.searchDuration)
	var halfway:=maxi(1,duration/2)
	issue({"op":"step","seconds":halfway})
	if not check(app.core.view.salvage.collecting is Dictionary and int(app.core.view.salvage.collecting.progress)==halfway,"real current-version collection timer reaches halfway"):
		return
	var original: Dictionary = app.core.view.duplicate(true)
	var wallet_at_sea: Dictionary = app.economy.wallet()
	if not await click("菜单"): return
	if not await click("保存暂离"):
		return
	check(app.screen == "formation", "save-leave returns to the invoking formation while keeping active voyage")
	var exact_snapshot: Variant = app.economy.state.active_run.snapshot
	check(exact_snapshot is String and not str(exact_snapshot).is_empty(), "stored snapshot remains opaque source JSON")
	check(not app.economy.buy("ammo_pack").ok and not app.economy.recruit(1).ok and not app.economy.train(str(app.economy.formation[0])).ok and not app.economy.sell_common().ok, "port trade recruit train and sale lock during voyage")
	check(not app.economy.set_formation([app.economy.formation[0]]).ok, "formation changes lock during voyage")
	app.start_campaign()
	check(not app.campaign_mode and app.core.view == original, "active voyage blocks campaign without destroying core state")
	await _release_client()
	await _new_client()
	check(app.economy.state.active_run.snapshot == exact_snapshot, "complete scene and native-process restart preserves exact snapshot bytes")
	if not await click("继续航次"):
		return
	if not check(app.screen == "battle" and app.core.view == original, "real UI resumes exact native position damage timer and opened-container state"):
		return
	var restored_wallet: Dictionary = app.economy.wallet()
	var same_amounts := true
	for currency in wallet_at_sea:
		if str(currency).ends_with("_seconds"): continue
		if int(restored_wallet.get(currency, -1)) != int(wallet_at_sea[currency]):
			same_amounts = false
			print("WALLET RESTORE MISMATCH ", currency, " before=", wallet_at_sea[currency], " after=", restored_wallet.get(currency))
	check(same_amounts, "resume never deducts deployment or changes any wallet amount")
	check(str(app.run.run_id) == success_run, "resume preserves original voyage identity")
	issue({"op":"step","seconds":duration-halfway})
	check(int(app.core.view.salvage.loot.get("scrap", 0)) == 5, "resumed current-version container yields five real scrap")
	var extraction:Dictionary=app.core.view.salvage.exits[0]
	# Hold ships already recovered before moving the other real group; use the
	# authoritative ship.fleet id, not JSON-number Array.has(int) membership.
	for group in app.core.view.fleets:
		issue({"op":"speed","fleet":int(group.id),"speed":0})
	issue({"op":"step","seconds":20})
	for group in app.core.view.fleets.duplicate(true):
		var group_id:=int(group.id)
		if _group_within_exit(group_id,extraction,900): continue
		var recovery_route:Dictionary={"op":"route","fleet":group_id,"mode":"follow","speed":minf(12.0,float(group.maxSpeed)),"points":[{"x":float(extraction.x)+600,"y":float(extraction.y)+400}]}
		var preview_request:Dictionary=recovery_route.duplicate(true)
		preview_request.op="preview_route"
		var preview:Dictionary=app.core.request(preview_request)
		if not check(preview.get("ok",false) and preview.get("data",{}).get("valid",false),"returning group has a legal collision-free curved route"):
			print("RECOVERY_PREVIEW ",JSON.stringify(preview));return
		issue(recovery_route)
		var steps:=0
		while not _group_within_exit(group_id,extraction,850) and app.core.view.get("result")==null and steps<100:
			issue({"op":"step","seconds":20})
			steps+=1
		if not check(_group_within_exit(group_id,extraction,850),"every member of returning group reaches recovery area"):
			print("RETURN_TRACE ",JSON.stringify(app.core.view.ships));return
		issue({"op":"speed","fleet":group_id,"speed":0})
		issue({"op":"step","seconds":20})
	check(app.core.view.fleets.all(func(group):return _group_within_exit(int(group.id),extraction,1000)),"all navigable groups are physically inside the same extraction radius")

	issue({"op": "salvage_extract", "exit": 0})
	issue({"op": "step", "seconds": 20})
	if not check(bool(app.core.view.salvage.extracted), "all actual navigable hulls return and complete extraction"):
		return
	var credits_before_settlement := int(app.economy.wallet().credits)
	app.finish_battle()
	check(app.screen == "result" and bool(app.last_receipt.success), "real core result settles through UI economic transaction")
	check(int(app.economy.state.inventory.scrap) == 5 and int(app.economy.wallet().credits)==credits_before_settlement+int(app.last_receipt.get("rewards",{}).get("credits",0)), "actual mission rewards settle while extracted cargo remains unsold")
	check(int(app.economy.wallet().ammo_stock) == stock_before, "zero-fire successful sortie refunds all actual deployment supply")
	var credits_after_settlement:=int(app.economy.wallet().credits)
	var settled_once: Dictionary = app.economy.state.duplicate(true)
	check(app.economy.settle_sortie(app.last_receipt).get("duplicate", false), "real receipt replay is idempotent")
	check(app.economy.state == settled_once, "replayed settlement never duplicates cargo XP or ammo")
	await screenshot("05-success-result")
	if not await click("前往仓库兑换"):
		return
	await screenshot("06-warehouse-before-sale")
	if not await click("兑换全部"):
		return
	if not await click("确认"):
		return
	check(int(app.economy.state.inventory.scrap) == 0 and int(app.economy.wallet().credits) == credits_after_settlement + 125, "pointer-confirmed sale converts actual five scrap to 125 silver")
	if not await click("‹  返回"): return
	if not await click("军需"):
		return
	var stock_before_purchase := int(app.economy.wallet().ammo_stock)
	if not await click("采购"):
		return
	check(int(app.economy.wallet().ammo_stock) == stock_before_purchase + 100, "real purchase adds one ammunition pack")
	if not await click("‹  返回"): return
	if not await click("舰娘"):
		return
	var training_id: String = app.economy.formation[0]
	var old_level := int(app.economy.state.owned[training_id].level)
	var old_score := int(app.economy.formation_preview().score)
	var row: Dictionary = {}
	for ship in app.economy.roster():
		if str(ship.id) == training_id:
			row = ship
	app.ship_detail(row)
	if not await click("成长"): return
	var training_wallet:Dictionary=app.economy.wallet()
	var old_mastery:=int(app.economy.state.owned[training_id].get("mastery",0))
	# Two basic records preserve the original 80-XP / 100-silver / two-material
	# acceptance, now exercised through the tiered training interface.
	for record in range(2):
		if not await click("+40 EXP"):return
	check(int(app.economy.state.owned[training_id].level) > old_level and int(app.economy.formation_preview().score) > old_score, "paid UI training creates real growth and next-sortie score")
	check(int(app.economy.wallet().credits)==int(training_wallet.credits)-100 and int(app.economy.wallet().materials)==int(training_wallet.materials)-2,"two displayed training records debit exactly 100 silver and two materials")
	check(int(app.economy.state.owned[training_id].get("mastery",0))==old_mastery,"paid training preserves combat-only mastery")
	check(int(app.economy.growth_profile(training_id).level_cap)==10 and _find_button(app,"等级突破")!=null and _find_button(app,"等级突破").disabled,"new hull displays first breakthrough cap and cannot ascend prematurely")
	for ship in app.economy.roster():
		if str(ship.id) == training_id:
			row = ship
	app.ship_detail(row)
	if not await click("装载弹药"):
		return
	check(int(app.economy.state.owned[training_id].ammo) == 100, "UI ammo preparation changes desired deployment")
	check(int(app.economy.wallet().ammo_stock) == stock_before_purchase + 100, "preparation itself never deducts warehouse ammo")
	if not await click("‹  返回"): return
	check(app.screen=="roster","ship detail returns to its invoking roster")
	if not await click("‹  返回"):return
	if not await click("编队"):
		return
	app.set_meta("next_sortie_seed",6109)
	if not await click("确认出航"):
		return
	if not check(app.screen == "battle", "second actual voyage launches after trade and growth"):
		return
	failure_run = str(app.run.run_id)
	check(failure_run != success_run, "second voyage receives distinct identity")
	issue({"op": "ai", "fleet": 1, "profile": "gunnery", "mode": "auto", "move": false, "gun": true, "torpedo": true})
	issue({"op": "route", "fleet": 1, "mode": "follow", "speed": minf(20,float(app.core.view.fleets[0].maxSpeed)), "points": [{"x": 11500, "y": 2200}]})
	var actual_salvo:=false
	var actual_damage:=false
	var actual_hp_loss:=false
	var damage_baseline:Dictionary={}
	for hull in app.core.view.ships:damage_baseline[str(hull.id)]=float(hull.hp)
	for batch in range(23):
		if app.core.view.get("result")!=null: break
		issue({"op":"step","seconds":120})
		actual_salvo=actual_salvo or app.core.view.events.any(func(e):return str(e.get("kind",""))=="gun")
		actual_damage=actual_damage or app.core.view.events.any(func(e):return str(e.get("kind","")) in ["damage","creature_hit"])
		for hull in app.core.view.ships:
			if float(hull.hp)<float(damage_baseline.get(str(hull.id),hull.hp)):actual_hp_loss=true
	if not check(app.core.view.get("result") != null and not app.core.view.salvage.extracted, "second voyage ends through actual combat or native deadline"):
		return
	check(actual_salvo, "second voyage produces real CAS salvos")
	check(actual_damage, "second voyage resolves real damage")
	check(actual_hp_loss,"real damage events also reduce actual native hull HP")
	app.finish_battle()
	check(app.screen == "result" and not bool(app.last_receipt.success), "failure settles without fake reward")
	check(int(app.economy.state.inventory.scrap) == 0 and app.economy.state.active_run.is_empty(), "failed voyage gives no unextracted goods and unlocks port")
	await screenshot("07-failure-result")
	var economy_before_campaign: Dictionary = app.economy.state.duplicate(true)
	app.show_page("harbor")
	if not await click("战役航图"):
		return
	check(app.screen == "campaign", "historical atlas uses real catalogue")
	await screenshot("08-campaign-atlas")
	if not await click("北所罗门"):
		return
	await screenshot("08b-campaign-north")
	if not await click("战区总览"):
		return
	if not await click("作战简报"):
		return
	check(is_instance_valid(app.modal), "selected historical record opens a real briefing")
	if not await click("关闭"):
		return
	if not await click("出航"):
		return
	if not check(app.screen == "battle" and app.campaign_mode and not app.core.view.get("ships", []).is_empty(), "real historical campaign starts with borrowed fleet"):
		return
	check(app.page.find_child("BattleSceneTitle",true,false).text==str(app.core.view.campaign.missionLabel),"historical battle caption uses the actual observed campaign label")
	await screenshot("09-historical-campaign")
	for fleet in app.core.view.get("fleets", []):
		issue({"op": "ai", "fleet": int(fleet.id), "profile": "coord", "mode": "auto", "move": true, "gun": true, "torpedo": true})
	for i in range(4):
		if app.core.view.get("result") != null:
			break
		issue({"op": "step", "seconds": 2700})
	campaign_tick = int(app.core.view.get("tick", 0))
	check(app.core.view.get("result") != null, "historical campaign reaches native battle result")
	app.finish_battle()
	check(app.last_receipt.get("campaign", false) or str(app.last_receipt.get("mode", "")) == "campaign", "campaign result identified separately")
	check(app.economy.state.owned == economy_before_campaign.owned, "borrowed historical fleet never changes personal hulls or their ammunition")
	var grant: Dictionary = app.last_receipt.get("rewards", {})
	for currency in ["credits", "tickets", "up_tickets", "medals", "ammo_stock"]:
		check(int(app.economy.wallet().get(currency, 0)) == int(economy_before_campaign.wallet.get(currency, 0)) + int(grant.get(currency, 0)), "historical wallet changes only by declared real reward: " + currency)

	# Kept false on any early return or script runtime error.
	exercise_completed = true


func _group_within_exit(group_id: int, extraction: Dictionary, radius: float) -> bool:
	for ship in app.core.view.get("ships",[]):
		if int(ship.get("fleet",-1))!=group_id: continue
		if float(ship.get("systems",{}).get("maxSpeed",0))<4.0: continue
		if extraction.has("bounds"):
			var bounds:Dictionary=extraction.bounds
			if float(ship.x)<float(bounds.min_x) or float(ship.x)>float(bounds.max_x) or float(ship.y)<float(bounds.min_y) or float(ship.y)>float(bounds.max_y):return false
		elif Vector2(float(ship.x)-float(extraction.x),float(ship.y)-float(extraction.y)).length()>=radius: return false
	return true

func _reveal_conditions() -> void:
	if _find_button(app, "跳过演出") != null:
		await click("跳过演出")
	await create_timer(0.8).timeout
	var cells: Array[Control] = []
	for child in app.modal.get_children():
		if child is Control and child.clip_contents:
			cells.append(child)
	check(cells.size() == 10, "ten real reveal cells are present")
	var visible_count := 0
	for cell in cells:
		if cell.modulate.a >= 0.99:
			visible_count += 1
	check(visible_count == 10, "all ten reveal cells finish animation with alpha at least 0.99")

func _final_conditions() -> void:
	if not await click("征募"):
		return
	if not await click("常驻征募"):
		return
	if not await click("征募十次   ◇ 10"):
		return
	await _reveal_conditions()
	await screenshot("03-recruit-results")
	if not await click("确认入列"):
		return
	if not await click("‹ 返回"):
		return
	if not await click("编队"):
		return
	if not await click("确认出航"):
		return
	check(app.screen == "battle" and not app.run.is_empty(), "targeted visual check uses a real committed native voyage")
	await create_timer(0.15).timeout
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "native battle window enters actual fullscreen mode")
	check(Vector2i(root.get_texture().get_image().get_size()) == DisplayServer.screen_get_size(DisplayServer.window_get_current_screen()), "battle viewport matches physical screen resolution")
	await screenshot("04-salvage-sea")
	exercise_completed = true
