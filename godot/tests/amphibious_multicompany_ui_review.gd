extends "res://tests/amphibious_expedition_ui_review.gd"
func _initialize()->void:
	multi_review=true
	call_deferred("run")
