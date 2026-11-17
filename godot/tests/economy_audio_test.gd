extends SceneTree

const Economy = preload("res://scripts/economy.gd")
const Audio = preload("res://scripts/audio_director.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, name: String) -> void:
	checks += 1
	if not condition:
		failures.append(name)
		push_error(name)


func _run() -> void:
	var path := "user://tests/economy-%d.json" % OS.get_process_id()
	var economy = Economy.new(path)
	check(economy.load_state().ok, "new profile persisted")
	check(economy.formation.size() == 3, "three ship formation")
	check(economy.formation_preview().ammo_required == 180, "three planned loads, no inventory deduction")
	var before: Dictionary = economy.wallet()
	var drawn: Dictionary = economy.recruit(10, "draw-one")
	check(drawn.ok and drawn.draws.size() == 10, "ten draw")
	check(economy.recruit(10, "draw-one").get("duplicate", false), "draw idempotent")
	check(not economy.recruit(1, "draw-one").ok, "same ID different operation rejected")
	check(int(economy.wallet().tickets) == int(before.tickets) - 10, "tickets deducted once")
	check(drawn.draws.any(func(row): return row.rarity != "common"), "ten draw rare guarantee")
	var bought: Dictionary = economy.buy("ammo_pack", 1, "buy-one")
	var stock_after: int = int(economy.wallet().ammo_stock)
	check(bought.ok and economy.buy("ammo_pack", 1, "buy-one").get("duplicate", false), "purchase idempotent")
	check(int(economy.wallet().ammo_stock) == stock_after, "purchase grants once")
	var ship_id: String = economy.formation[0]
	var preview_before: Dictionary = economy.formation_preview()
	check(economy.train(ship_id).ok, "training purchase")
	check(economy.formation_preview().score > preview_before.score, "growth adds real construction score")
	var sortie: Dictionary = economy.begin_sortie(777)
	check(sortie.ok, "sortie committed")
	check(int(economy.wallet().ammo_stock) == stock_after - 180, "deployment ammo deducted only at departure")
	check(not economy.buy("ammo_pack").ok and not economy.recruit().ok and not economy.sell("scrap").ok and not economy.train(ship_id).ok, "all port transactions locked")
	var snapshot := '{"tick":55,"random":18446744073709551615,"opened":["ruin-1"]}'
	check(economy.save_sortie(snapshot).ok, "snapshot atomically saved")
	var reloaded = Economy.new(path)
	var load_result: Dictionary = reloaded.load_state()
	check(load_result.ok and str(reloaded.resume_sortie().snapshot) == snapshot, "mid-sortie reload exact snapshot")
	var returned: Array = []
	for i in range(sortie.fleet.size()):
		returned.append({"id": sortie.fleet[i].id, "hp": 80 if i < 2 else 10, "ammo": 35, "protected": i == 2, "canNavigate": i < 2})
	var receipt := {"run_id": sortie.run_id, "success": true, "loot": {"scrap": 3, "alloy": 1, "equipment": 1, "command": 1}, "ships": returned, "xp": 40}
	var credits_before: int = int(reloaded.wallet().credits)
	check(reloaded.settle_sortie(receipt).ok, "successful settlement")
	check(reloaded.settle_sortie(receipt).get("duplicate", false), "settlement idempotent")
	var detailed: Dictionary = reloaded.latest_receipt()
	check(detailed.ships.size() == 3 and detailed.deployment_ammo == 180 and detailed.returned_ammo == 70, "detailed receipt freezes deployment and personal refund")
	check(detailed.ships[0].damage == 20 and detailed.ships[0].ammo_spent == 25 and detailed.ships[0].ammo_returned == 35, "per-ship damage and ammo consumption preserved")
	check(detailed.ships[2].protected and not detailed.ships[2].canNavigate and detailed.ships[2].ammo_lost == 35, "protected receipt explains positive remaining ammo loss")
	var receipt_reload = Economy.new(path)
	check(receipt_reload.load_state().ok and receipt_reload.latest_receipt().run_id == sortie.run_id and receipt_reload.latest_receipt().ships.size() == 3, "last detailed receipt survives application restart")
	check(int(reloaded.wallet().credits) == credits_before + int(detailed.rewards.get("credits",0)), "mission reward is explicit; cargo does not automatically become coins")
	credits_before=int(reloaded.wallet().credits)
	check(int(reloaded.wallet().ammo_stock) == stock_after - 180 + 70, "only surviving return ships refund ammo")
	check(int(reloaded.state.owned[sortie.fleet[2].id].hp) == 10 and reloaded.state.owned[sortie.fleet[2].id].protected, "positive HP protected ship remains damaged without ammo refund")
	check(not reloaded.begin_sortie(778).ok, "positive HP protected ship cannot depart before repair")
	check(reloaded.equip(ship_id, "equipment").ok and reloaded.equip(ship_id, "command").ok, "warehouse loadouts equipped")
	check(reloaded.formation_preview().capacity == 10, "equipment increases cargo capacity")
	check(reloaded.formation_preview().search_seconds < 12, "command and training accelerate searches")
	check(reloaded.state.item_instances.size() == 2 and reloaded.state.inventory.equipment == 0, "unique loadout ownership")
	check(reloaded.unequip(ship_id, "equipment").ok and reloaded.equip(ship_id, "equipment").ok, "unequip and re-equip same item")
	check(reloaded.state.item_instances.size() == 2, "re-equipping cannot duplicate instance")
	check(reloaded.sell_common().ok and int(reloaded.wallet().credits) == credits_before + 135, "manual sale transfers actual cargo")
	check(not reloaded.sell_common().ok, "sold cargo cannot sell twice")
	# A small nonzero wallet with every ship disabled must still have a real recovery route.
	reloaded.state.wallet.credits = 5
	reloaded.state.wallet.ammo_stock = 0
	for owned in reloaded.state.owned.values():
		owned.hp = 0
		owned.ammo = 0
	check(reloaded.save_state().ok, "bankrupt damaged fixture persisted")
	var basic: Dictionary = reloaded.begin_sortie(887, true)
	check(basic.ok and basic.mode == "basic", "borrowed recovery despite positive insufficient funds")
	check(int(reloaded.wallet().ammo_stock) == 0, "borrowed ammo does not touch personal warehouse")
	check(reloaded.settle_sortie({"run_id": basic.run_id, "success": true, "loot": {"scrap": 8, "alloy": 2, "equipment": 2}, "ships": [{"id": basic.fleet[0].id, "hp": 100, "ammo": 100}]}).ok, "real basic sortie settlement")
	check(reloaded.latest_receipt().deployment_ammo == 0 and reloaded.latest_receipt().returned_ammo == 0 and reloaded.latest_receipt().borrowed_deployment_ammo == 100, "borrowed receipt separates personal and loaned ammo")
	check(reloaded.state.inventory.scrap == 4 and reloaded.state.inventory.equipment == 0, "borrowed task limited to four scrap")
	check(int(reloaded.wallet().ammo_stock) == 0 and reloaded.state.owned[ship_id].hp == 0, "borrowed assets never enter personal account")
	check(reloaded.sell_common().ok and int(reloaded.wallet().credits) == 105, "borrowed task repairs soft-lock via cargo sale")
	check(reloaded.repair(ship_id).ok == false, "insufficient repair price does not change assets")
	var failure_path := "user://tests/economy-failure-%d.json" % OS.get_process_id()
	var failed = Economy.new(failure_path)
	failed.load_state()
	failed.set_formation([ship_id])
	var failed_run: Dictionary = failed.begin_sortie(449)
	var failed_result: Dictionary = failed.settle_sortie({"run_id": failed_run.run_id, "success": false, "loot": {"scrap": 2, "equipment": 1}, "ships": [{"id": ship_id, "hp": 70, "ammo": 42}]})
	check(failed_result.ok and failed_result.receipt.lost_loot == {"scrap": 2, "equipment": 1}, "failure receipt records unextracted cargo")
	check(failed.state.inventory.scrap == 0 and failed.state.inventory.equipment == 0, "lost cargo never granted")
	check(failed_result.receipt.deployment_ammo == 60 and failed_result.receipt.returned_ammo == 0 and failed_result.receipt.ships[0].ammo_lost == 42, "failure receipt explains all remaining deployment ammo loss")
	failed.state.last_receipt_id = ""
	failed.state.settled = {"salvage-9-777": {"run_id": "salvage-9-777"}, "basic-10-888": {"run_id": "basic-10-888"}}
	check(failed.latest_receipt().run_id == "basic-10-888", "old saves recover latest receipt by numeric sequence")
	# Failed atomic commit must roll the in-memory transaction back.
	var broken = Economy.new("res://data")
	broken.state = reloaded.state.duplicate(true)
	broken.formation.assign(reloaded.formation)
	broken.state.wallet.credits = 2000
	var old_credits: int = int(broken.wallet().credits)
	check(not broken.buy("ticket").ok and int(broken.wallet().credits) == old_credits, "failed purchase preserves assets")
	if FileAccess.file_exists("res://data.tmp"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("res://data.tmp"))
	var audio = Audio.new()
	root.add_child(audio)
	audio.set_session("audio-test", "allies")
	audio.set_scene("harbor")
	await create_timer(0.15).timeout
	check(audio.current_music_path.begins_with("res://assets/audio/original/harbor_"), "original local-time harbor music binding")
	check(audio.ledger.get("music", []).size() == 11 and audio.ledger.get("ui", []).size() == 4, "eleven original music and four CC0 UI sounds")
	audio.ingest_events([{"id": "contact-one", "tick": 10, "kind": "contact", "voiceCue": "contact", "text": "发现敌舰"}], [], [], true, 10)
	await create_timer(0.1).timeout
	check(audio.last_voice_cue == "contact" and not audio.last_voice_path.is_empty(), "contact event starts archive voice")
	check(audio._seen.size() == 1, "voice dedup ID recorded")
	audio.ingest_events([{"id": "contact-one", "tick": 10, "voiceCue": "contact"}], [], [], true, 10)
	check(audio._seen.size() == 1, "repeated observations do not replay voice")
	check(audio._voice_path("torpedo_warning", "unknown-direction").is_empty(), "unknown bearing never invents a directional warning")
	audio.ui("confirm")
	audio.set_paused(true)
	check(audio._voice.stream_paused and audio._music.stream_paused, "paused radio and music")
	audio.set_paused(false)
	audio.queue_free()
	await process_frame
	# Let the audio mixer release active Vorbis playback buffers before shutdown.
	await create_timer(0.2).timeout
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
		if FileAccess.file_exists(failure_path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(failure_path + suffix))
	var report := {"checks": checks, "passed": checks - failures.size(), "failures": failures}
	print(JSON.stringify(report))
	var report_file := FileAccess.open("res://../artifacts/godot-economy-audio.json", FileAccess.WRITE)
	if report_file:
		report_file.store_string(JSON.stringify(report, "\t"))
	quit(0 if failures.is_empty() else 1)
