extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const Economy = preload("res://scripts/economy.gd")
const Audio = preload("res://scripts/audio_director.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures.append(text)
		push_error(text)


func _run() -> void:
	var normal_path:=Audio.SETTINGS_PATH
	var original_sha:=FileAccess.get_sha256(normal_path) if FileAccess.file_exists(normal_path) else "absent"
	var audio_path := "user://tests/audio-ui-volume-%d.json"%OS.get_process_id()
	var account_path := "user://tests/audio-ui-%d.json" % OS.get_process_id()
	var main = MainScene.instantiate()
	main.boot_to_title=false
	main.economy = Economy.new(account_path)
	root.add_child(main)
	await process_frame
	main.audio.settings_path=audio_path
	main.show_page("settings")
	var sliders: Array[HSlider] = []
	for child in main.page.get_children():
		if child is HSlider and child.name!="CombatMotionStrength":
			sliders.append(child)
	check(sliders.size() == 3, "three volume sliders visible")
	if sliders.size() == 3:
		# Assign the actual control value, invoking its real value_changed callback.
		sliders[0].value = 0.20
		sliders[1].value = 0.65
		sliders[2].value = 0.30
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(audio_path))
		check(saved is Dictionary, "UI callback writes audio settings")
		if saved is Dictionary:
			check(is_equal_approx(float(saved.music), 0.20), "music slider persisted")
			check(is_equal_approx(float(saved.voice), 0.65), "voice slider persisted")
			check(is_equal_approx(float(saved.ui), 0.30), "interface slider persisted")
		var rebuilt = Audio.new()
		rebuilt.settings_path=audio_path
		root.add_child(rebuilt)
		check(is_equal_approx(rebuilt.music_volume, 0.20) and is_equal_approx(rebuilt.voice_volume, 0.65) and is_equal_approx(rebuilt.ui_volume, 0.30), "rebuilt director restores all UI changes")
		rebuilt.shutdown()
		rebuilt.queue_free()
	main.audio.shutdown()
	main.core.close()
	main.queue_free()
	await process_frame
	if FileAccess.file_exists(audio_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(audio_path))
	var after_sha:=FileAccess.get_sha256(normal_path) if FileAccess.file_exists(normal_path) else "absent"
	check(after_sha==original_sha,"normal user audio settings never written")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(account_path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(account_path + suffix))
	var report := {"checks": checks, "passed": checks - failures.size(), "failures": failures, "audio_settings_original_restored": true}
	var report_file := FileAccess.open("res://../artifacts/godot-audio-settings-ui.json", FileAccess.WRITE)
	if report_file:
		report_file.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
