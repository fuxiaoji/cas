extends SceneTree
const Bridge = preload("res://scripts/core_bridge.gd")
const Sea = preload("res://scripts/sea_map.gd")
var core = Bridge.new()
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("review")

func review() -> void:
	var generated: Dictionary = core.request({"op": "new_salvage", "seed": 6106, "start": {"content": "salvage-v1", "fleet": [{"id": "IBS-U-USN-FLETCHER", "hp": 100, "ammo": 60, "level": 1, "equipment": false, "command": false}, {"id": "IBS-U-USN-PERKINS", "hp": 100, "ammo": 60, "level": 1, "equipment": false, "command": false}, {"id": "IBS-U-USN-MAURY", "hp": 100, "ammo": 60, "level": 1, "equipment": false, "command": false}]}})
	if not generated.get("ok", false):
		push_error(str(generated))
		core.close()
		quit(1)
		return
	var map = Sea.new()
	root.add_child(map)
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.view = core.view.duplicate(true)
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/ships.json"))
	for card in raw.get("ships", []):
		map.cards[str(card.id)] = card
	var before := JSON.stringify(map.view)
	var output := ProjectSettings.globalize_path("res://../artifacts/godot/sea-style")
	DirAccess.make_dir_recursive_absolute(output)
	for variant in ["painted-overview", "painted-near", "tactical-overview"]:
		map.stylized_environment = variant != "tactical-overview"
		map.zoom = 1
		map.pan = Vector2.ZERO
		if variant == "painted-near":
			map.focus_fleet()
		map.queue_redraw()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png(output.path_join(variant + ".png")) != OK:
			failures.append("screenshot " + variant)
	if JSON.stringify(map.view) != before:
		failures.append("art modified core observation")
	var report := {"screenshots": 3, "failures": failures, "seed": 6106, "islands": core.view.get("islands", []).size(), "native_observation_unchanged": JSON.stringify(map.view) == before, "scope": "presentation only; shader and shore layers do not change collision or line of sight"}
	var stream := FileAccess.open(output.path_join("receipt.json"), FileAccess.WRITE)
	stream.store_string(JSON.stringify(report, "\t"))
	stream.close()
	core.close()
	map.queue_free()
	await process_frame
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
