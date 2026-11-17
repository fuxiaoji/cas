extends "res://scripts/legacy_battle.gd"
## Uses the campaign controller's complete command and detail UI against the real World.
func create_map()->Control:
	return load("res://scripts/littoral_world_sea.gd").new()
