extends SceneTree
## Actual seat-observed native fire, rendered with the production SeaMap on a real GPU.
## No synthetic combat, authority edits, damage, or rewards are used in this review.
const Core = preload("res://scripts/core_bridge.gd")
const Sea = preload("res://scripts/sea_map.gd")
const Design = preload("res://scripts/ui_design.gd")
var core = Core.new()
var sea: Control
var renderer: Node
var caption: Label
var checks := 0
var failures: Array[String] = []
var evidence: Array[Dictionary] = []
var output := "res://../artifacts/godot/projectile-visual-review/"
var native_path := ""
var old_path := ""

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func request(command: Dictionary) -> Dictionary:
	var response: Dictionary = core.request(command)
	if not response.get("ok", false):
		check(false, "native request: " + str(command.get("op", "")) + " " + str(response.get("error", "")))
	return response

func show_view() -> void:
	sea.view = core.view
	sea.projectile_epoch = core.observation_epoch
	renderer.observe(sea.view, sea.projectile_readonly, sea.projectile_epoch)
	sea.queue_redraw()

func step() -> void:
	request({"op":"step", "seconds":1})
	show_view()
	# One native second per .10 visual seconds models the normal accelerated review.
	renderer.advance(.10)

func start_case(first: String) -> void:
	var identities: Array[String] = [first]
	for id in ["IBS-U-USN-WASHINGTON", "IBS-U-USN-SAN-FRANCISCO", "IBS-U-USN-HONOLULU", "IBS-U-USN-FLETCHER", "IBS-U-USN-PERKINS"]:
		if id != first: identities.append(id)
	var response := request({"op":"new", "seed":6106, "side":"allies", "enemy":"gunnery", "profile":"gunnery", "realtime":true, "ships":identities})
	check(not response.get("data", {}).has("presentation") and not response.get("data", {}).has("presentation_epoch"), "default response observation remains unenriched")
	check(core.view.get("presentation", {}).get("version", "") == "projectile-fx-v1", "optional native presentation stream is available")
	sea.projectile_readonly = false
	sea.projectile_rate = 0.0
	show_view()

func own_main_rounds(shell_id: String) -> Array:
	return renderer.rounds().filter(func(row): return not bool(row.secondary) and str(row.shell.get("id", "")) == shell_id)

func own_shots(battery: String, tick_only: bool = true) -> Array:
	return core.view.get("presentation", {}).get("shots", []).filter(func(row): return str(row.get("battery", "")) == battery and (not tick_only or int(row.tick) == int(core.view.tick)))

func frame_path(shot: Dictionary, progress: float = .45) -> void:
	var from: Vector2 = sea.pos(shot.from)
	var to: Vector2 = sea.pos(shot.to)
	sea.zoom = 1.7
	sea.pan = Vector2.ZERO
	sea.pan = Vector2(800, 550) - sea.project(from.lerp(to, progress))

func snapshot(name: String, title: String, center: Vector2 = Vector2.INF) -> void:
	caption.text = title + "\n真实原核公开观测 · 实际暂停截图 · 未改写战斗结果"
	sea.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	check(img.save_png(ProjectSettings.globalize_path(output + name + ".png")) == OK, "GPU screenshot saved: " + name)
	if center != Vector2.INF:
		var region := Rect2i(Vector2i(center) - Vector2i(220, 130), Vector2i(440, 260)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		img.get_region(region).save_png(ProjectSettings.globalize_path(output + name + "-detail.png"))

func pure_render_contract(label: String) -> void:
	var saved: String = str(request({"op":"save", "serialized":true}).get("serialized", ""))
	var published: String = JSON.stringify(core.view)
	var count: int = renderer.emitted_secondary
	var initial: Array = renderer.rounds().map(func(row): return [str(row.shell.get("id", "")), row.lane, row.progress, row.secondary])
	for i in range(60):
		renderer.observe(core.view, false, sea.projectile_epoch)
		renderer.advance(1.0 / 120.0)
	var after: Array = renderer.rounds().filter(func(row): return not bool(row.secondary)).map(func(row): return [str(row.shell.get("id", "")), row.lane, row.progress, row.secondary])
	var initial_main: Array = initial.filter(func(row): return not bool(row[3]))
	check(initial_main == after, "paused main rounds never crawl or duplicate: " + label)
	check(renderer.emitted_secondary == count, "repeated paused observation never replays secondary: " + label)
	check(JSON.stringify(core.view) == published, "renderer leaves seat observation unchanged: " + label)
	check(str(request({"op":"save", "serialized":true}).get("serialized", "")) == saved, "rendering leaves native save/time/damage unchanged: " + label)

func main_and_triple_case() -> void:
	start_case("IBS-U-USN-WASHINGTON")
	request({"op":"fire", "ship":1, "weapon":"gun", "target":"C01"})
	var first: Dictionary = {}
	for second in range(20):
		step()
		if not own_shots("main").is_empty(): first = own_shots("main")[0]; break
	check(not first.is_empty(), "actual Washington fires initial main salvo")
	if first.is_empty(): return
	check(int(first.barrels) == 6 and is_equal_approx(float(first.caliber_mm), 406), "actual two trained triple mounts report six 406mm rounds")
	var shell_id := str(first.shell_id)
	check(own_main_rounds(shell_id).size() == 6, "each actual initial main barrel has one visible round")
	var flight: Dictionary = renderer.active[shell_id]
	while float(flight.get("progress", 0)) < .35 and int(core.view.tick) < int(flight.impactTick):
		step()
		if not renderer.active.has(shell_id): break
		flight = renderer.active[shell_id]
	frame_path(first)
	var lanes: Array = own_main_rounds(shell_id)
	if lanes.size() >= 2:
		var a: Dictionary = renderer._geometry(sea, lanes[0])
		var b: Dictionary = renderer._geometry(sea, lanes[1])
		check(a.point.distance_to(b.point) > 3.0, "real grouped barrels are visibly separated in screen space")
		check(float(a.style.tail) > 20 and a.point.y < a.ground.y - 5, "406mm main shell has heavy golden ballistic arc")
	pure_render_contract("six-round actual flight")
	evidence.append({"case":"actual_two_triple_mounts", "tick":core.view.tick, "shot":first, "rounds":own_main_rounds(shell_id).size()})
	# Original validated route operations only: turn north, then west, then use the one aft mount.
	start_case("IBS-U-USN-WASHINGTON")
	request({"op":"route", "fleet":1, "mode":"follow", "speed":15, "points":[{"x":4200, "y":13000}]})
	var north := false
	for second in range(600):
		step()
		if float(core.view.ships[0].heading) < 10:
			north = true
			break
	check(north, "actual fleet completes valid first turn north")
	request({"op":"route", "fleet":1, "mode":"follow", "speed":15, "points":[{"x":1000, "y":core.view.ships[0].y}]})
	var west := false
	for second in range(600):
		step()
		var heading: float = core.view.ships[0].heading
		if heading > 260 and heading < 280:
			west = true
			break
	check(west, "actual fleet brings target into aft triple mount arc")
	request({"op":"fire", "ship":1, "weapon":"gun", "target":"C01"})
	var triple: Dictionary = {}
	for second in range(100):
		step()
		for row in own_shots("main"):
			if int(row.own_ship) == 1:
				triple = row
				break
		if not triple.is_empty(): break
	check(not triple.is_empty() and int(triple.get("barrels", 0)) == 3, "actual intact aft triple mount fires exactly three projectiles")
	if triple.is_empty(): return
	shell_id = str(triple.shell_id)
	while renderer.active.has(shell_id) and float(renderer.active[shell_id].get("progress", 0)) < .38:
		step()
	check(own_main_rounds(shell_id).size() == 3, "one actual triple mount renders exactly three simultaneous rounds")
	frame_path(triple)
	var actual_rounds := own_main_rounds(shell_id)
	var middle: Dictionary = renderer._geometry(sea, actual_rounds[1]) if actual_rounds.size() == 3 else {}
	await snapshot("01-actual-triple-flight", "406 mm 主炮 / 尾部单座三联装 / 3 发同时飞行 / tick " + str(core.view.tick), middle.get("point", Vector2.INF))
	evidence.append({"case":"actual_single_triple", "tick":core.view.tick, "own_heading":core.view.ships[0].heading, "shot":triple, "round_geometry":actual_rounds.map(func(row): return str(renderer._geometry(sea,row)))})
	var flight_saved: String = str(request({"op":"save", "serialized":true}).get("serialized", ""))
	var old_epoch: int = core.observation_epoch
	request({"op":"load", "save":JSON.parse_string(flight_saved)})
	show_view()
	check(core.observation_epoch > old_epoch, "real same-tick load advances local observation epoch")
	check(renderer.bursts.is_empty() and renderer.splashes.is_empty(), "load seeds in-flight baseline without replaying launches or impacts")
	check(own_main_rounds(shell_id).size() == 3, "restored genuine flight still contains three display rounds")
	var impact_tick: int = renderer.active.get(shell_id, {}).get("impactTick", int(core.view.tick) + 100)
	while renderer.active.has(shell_id) and int(core.view.tick) <= impact_tick + 1: step()
	var landed: Array = renderer.splashes.filter(func(row): return int(row.barrels) == 3 and is_equal_approx(float(row.caliber_mm), 406) and Vector2(row.point).distance_to(sea.pos(triple.to)) < 1)
	check(landed.size() == 1, "actual aggregate impact produces one three-column water effect")
	if not landed.is_empty():
		renderer.advance(.13)
		frame_path(triple, 1.0)
		await snapshot("03-actual-triple-impact", "406 mm / 真实弹着时刻 / 3 道落水效果 / tick " + str(core.view.tick), sea.project(sea.pos(triple.to)))
		var n: int = renderer.splashes.size()
		renderer.observe(core.view, false, sea.projectile_epoch)
		check(renderer.splashes.size() == n, "duplicate impact observation cannot replay splash")
	evidence.append({"case":"actual_impact", "tick":core.view.tick, "impact_tick":impact_tick, "splash":landed})

func secondary_case() -> void:
	start_case("IBS-U-USN-SAN-FRANCISCO")
	request({"op":"route", "fleet":1, "mode":"follow", "speed":15, "points":[{"x":4200,"y":13000}]})
	var secondary: Dictionary = {}
	for second in range(360):
		step()
		if not own_shots("secondary").is_empty(): secondary = own_shots("secondary")[0]; break
	check(not secondary.is_empty(), "actual secondary fire is published even before a hit")
	if secondary.is_empty(): return
	check(core.view.get("events", []).filter(func(row): return int(row.get("tick", -1)) == int(core.view.tick) and str(row.get("kind", "")) == "secondary").is_empty(), "first actual secondary miss has no hit event")
	check(int(secondary.barrels) == 2 and is_equal_approx(float(secondary.caliber_mm),127), "actual two eligible 127mm secondary barrels retain correct metadata")
	var native_secondary_tick: int = core.view.tick
	# Main launch is a real order in the same short exchange; no synthetic flight is inserted.
	request({"op":"fire", "ship":1, "weapon":"gun", "target":"C01"})
	show_view()
	var coexist := false
	var coexist_view: Dictionary = {}
	for second in range(26):
		step()
		var main: Array = renderer.rounds().filter(func(row): return not bool(row.secondary) and bool(row.shell.get("own", false)))
		var sub: Array = renderer.rounds().filter(func(row): return bool(row.secondary))
		if not main.is_empty() and not sub.is_empty() and float(main[0].shell.get("progress",0)) > .13: coexist = true; coexist_view = core.view.duplicate(true); break
	check(coexist, "real main and secondary fire coexist in one authorized observation")
	if coexist:
		renderer.advance(.02)
		var rows: Array = renderer.rounds()
		var main: Dictionary = rows.filter(func(row): return not bool(row.secondary) and bool(row.shell.get("own", false)))[0]
		var sub: Dictionary = rows.filter(func(row): return bool(row.secondary))[0]
		var g_main: Dictionary = renderer._geometry(sea,main)
		var g_sub: Dictionary = renderer._geometry(sea,sub)
		check(g_main.style.color != g_sub.style.color and float(g_main.style.radius) > float(g_sub.style.radius) and float(g_main.style.tail) > float(g_sub.style.tail), "actual primary and secondary fire differ in color, thickness and tail")
		frame_path(sub.shell, .36)
		await snapshot("02-actual-main-secondary", "主炮（金色抛物线）与副炮（青色平射）同框 / 真实 tick " + str(core.view.tick), renderer._geometry(sea,sub).point)
		evidence.append({"case":"actual_primary_secondary_exchange", "first_secondary_tick":native_secondary_tick, "tick":core.view.tick, "shots":core.view.presentation.shots, "rounds":rows.size(), "observed_hit_events":core.view.events.filter(func(row): return int(row.get("tick", -1)) >= native_secondary_tick and str(row.get("kind", "")) == "secondary")})
		pure_render_contract("actual primary-secondary exchange")
		var emitted: int = renderer.emitted_secondary
		sea.projectile_readonly = true
		renderer.observe(core.view, true, sea.projectile_epoch)
		check(renderer.bursts.is_empty() and renderer.splashes.is_empty(), "readonly entry clears transient secondary launches and impacts")
		renderer.advance(.3)
		renderer.observe(core.view, true, sea.projectile_epoch)
		check(renderer.emitted_secondary == emitted, "readonly repeated observation emits no secondary")
		sea.projectile_readonly = false
		renderer.observe(core.view, false, sea.projectile_epoch)
		check(renderer.emitted_secondary == emitted and renderer.bursts.is_empty(), "return from readonly seeds baseline without replay")
		var rewind: Dictionary = coexist_view.duplicate(true)
		rewind.tick = maxi(0, int(rewind.tick) - 1)
		renderer.observe(rewind, false, sea.projectile_epoch)
		check(renderer.emitted_secondary == emitted and renderer.bursts.is_empty() and renderer.splashes.is_empty(), "labeled cursor-only rewind of actual observation does not replay fire")
		show_view()

func tide_case() -> void:
	request({"op":"new_tide", "seed":45, "character_id":"IBS-U-USN-FLETCHER", "difficulty":"normal", "intel_profile":"open-intel-v1"})
	show_view()
	var sampled := false
	for second in range(20):
		step()
		if not core.view.get("shells", []).is_empty():
			sampled = true
			check(renderer.rounds().size() == core.view.shells.size(), "Tide existing single-bolt observations render exactly once each")
			check(renderer.rounds().all(func(row): return not bool(row.has_path)), "Tide uses actual public position without inventing ballistic endpoints")
			check(renderer.bursts.is_empty(), "Tide mode switch clears previous secondary effects")
			evidence.append({"case":"actual_tide_bolts", "tick":core.view.tick, "shells":core.view.shells, "round_count":renderer.rounds().size()})
			break
	check(sampled, "actual Tide visible bolts sampled")

func fallback_case() -> void:
	if old_path.is_empty(): check(false, "old core path supplied for compatibility review"); return
	OS.set_environment("CAS_SIM_PATH", old_path)
	var legacy = Core.new()
	var response: Dictionary = legacy.request({"op":"new", "seed":6106, "side":"allies", "enemy":"gunnery", "profile":"gunnery", "realtime":true})
	check(response.get("ok", false) and not legacy.presentation_supported, "old core gracefully disables unsupported optional presentation operation")
	check(legacy.error.is_empty(), "optional operation fallback leaves no user-facing core error")
	legacy.request({"op":"fire", "ship":1, "weapon":"gun", "target":"C01"})
	var own: Array = []
	for second in range(30):
		legacy.request({"op":"step", "seconds":1})
		own = legacy.view.get("shells", []).filter(func(row): return bool(row.get("own", false)))
		if not own.is_empty(): break
	check(not own.is_empty(), "old core still produces original own aggregate shell")
	sea.view = legacy.view
	sea.projectile_epoch = legacy.observation_epoch
	renderer.observe(legacy.view, false, sea.projectile_epoch)
	var expected := 0
	for shell in legacy.view.get("shells", []): expected += maxi(1, int(shell.get("barrels",1)))
	check(renderer.rounds().size() == expected and expected > 0, "old core fallback expands existing public barrel count without extra metadata")
	evidence.append({"case":"actual_old_core_fallback", "tick":legacy.view.get("tick", -1), "shells":legacy.view.get("shells", []), "round_count":renderer.rounds().size()})
	legacy.close()
	OS.set_environment("CAS_SIM_PATH", native_path)

func run() -> void:
	native_path = OS.get_environment("CAS_SIM_PATH")
	old_path = OS.get_environment("CAS_OLD_SIM_PATH")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.content_scale_size = Vector2i(1600,900)
	root.size = Vector2i(1600,900)
	sea = Sea.new()
	root.add_child(sea)
	sea.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sea.chibis = false
	sea.weather_paused = true
	renderer = sea.projectiles
	renderer.set_process(false)
	caption = Label.new()
	caption.position = Vector2(32,24)
	caption.add_theme_font_override("font", Design.font(500))
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_color", Color("fff3cf"))
	caption.add_theme_color_override("font_shadow_color", Color("082c40"))
	caption.add_theme_constant_override("shadow_offset_x", 2)
	caption.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(caption)
	await process_frame
	await main_and_triple_case()
	await secondary_case()
	tide_case()
	fallback_case()
	var report := {"checks":checks, "failures":failures, "passed":failures.is_empty(), "native_binary":native_path, "native_sha256":FileAccess.get_sha256(native_path), "old_binary":old_path, "renderer":RenderingServer.get_video_adapter_name(), "evidence":evidence, "scope":"Production GPU rendering of actual seat observations. Cursor-only rewind is labeled; no synthetic combat, hidden targets, altered fleet or damage outcomes are used."}
	FileAccess.open(output + "receipt.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("PROJECTILE_VISUAL_REVIEW ", JSON.stringify({"checks":checks, "failures":failures, "passed":failures.is_empty(), "renderer":report.renderer}))
	core.close()
	sea.queue_free()
	caption.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
