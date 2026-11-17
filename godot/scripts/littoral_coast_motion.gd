@tool
extends Control
## Only the lightweight shoreline motion redraws between native observations.
const Terrain=preload("res://scripts/procedural_amphibious_terrain.gd")
var source_map:Control
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE;show_behind_parent=true
func _process(_delta:float)->void:
	if is_instance_valid(source_map) and visible and source_map.playing:queue_redraw()
func _draw()->void:
	if is_instance_valid(source_map):Terrain.paint_coast_motion(self,source_map.land.get("polygon",[]),source_map.project,float(source_map.visual_tick))
