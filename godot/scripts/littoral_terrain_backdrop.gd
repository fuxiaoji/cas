@tool
extends Control
## Static native terrain draw commands are cached by CanvasItem itself.
## Units, shots, weather and authoritative state remain on their live layers.
var source_map:Control
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	show_behind_parent=true
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
func _draw()->void:
	if is_instance_valid(source_map):source_map.paint_static_terrain(self)
