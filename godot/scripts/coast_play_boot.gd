extends "res://scripts/boot.gd"
## Play the real account/mode controllers with a separate local test profile.
const PROFILE:String="res://../artifacts/world3d-integration-20261116/player.json"

func _ready()->void:
	profile_override=ProjectSettings.globalize_path(PROFILE)
	immersive_fullscreen=false
	boot_completed.connect(_open_home)
	DisplayServer.window_set_title("CAS · 海岸家园")
	super._ready()

func _open_home(result:Dictionary)->void:
	if result.get("ok",false) and is_instance_valid(app):
		app.show_page("home")
