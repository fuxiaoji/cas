extends Control
var source_map
func _draw()->void:
	if is_instance_valid(source_map):source_map.paint_cached_terrain(self)
