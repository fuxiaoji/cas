extends "res://scripts/boot.gd"
## Starts the new Demo-derived geography, never an old map with a new shader.
const PROFILE:String="res://../artifacts/coastal-rebuild-20261116/player.json"
const HOME_PATH:String="res://scenes/ui/home_island.tscn"
var _entry_scenes:Array[Resource]=[]
func _ready()->void:
	if profile_override.is_empty():profile_override=ProjectSettings.globalize_path(PROFILE)
	immersive_fullscreen=false
	boot_completed.connect(_open_coastal_home)
	DisplayServer.window_set_title("CAS · 新海岸试玩")
	super._ready()
func _begin_boot()->void:
	# Preparing these script-bearing scenes on a worker leaves 17 zero-reference
	# objects at shutdown in this Godot build. Start after the visible loading
	# frame, prepare the two scenes on the main thread, and pin them for the
	# staged home route. The shared boot still loads fonts and bitmaps in parallel.
	loading.set_stage("整理海岸图册",-1)
	await _drawn_frame()
	if not is_inside_tree():return
	_entry_scenes.clear()
	for path:String in [MAIN_PATH,HOME_PATH]:
		var scene:Resource=load(path)
		if not scene is PackedScene:
			_fail("海岸图册未能准备，请重试。",boot_attempt);return
		_entry_scenes.append(scene)
		await _drawn_frame()
		if not is_inside_tree():return
	await super._begin_boot()
func _open_coastal_home(result:Dictionary)->void:
	if result.get("ok",false) and is_instance_valid(app):app.show_page("home")
