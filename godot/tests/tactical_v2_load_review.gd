extends SceneTree
func _initialize()->void:
	var failed:bool=false
	for path in ["main","tactical_art_v2","tactical_sprite","littoral_land","littoral_battle","littoral_support_fx","littoral_biome_art","home_exercise_session"]:
		var script:Script=load("res://scripts/%s.gd"%path)
		if script==null or script.reload()!=OK or not script.can_instantiate():failed=true;push_error(path+" cannot instantiate")
	print(JSON.stringify({"ok":not failed,"scripts":8}));quit(1 if failed else 0)
