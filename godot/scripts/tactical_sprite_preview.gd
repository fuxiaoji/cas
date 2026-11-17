@tool
extends Control
const FRAMES:Array[String]=["待机","眨眼","行走 A","行走 B","行走 C","行走 D","瞄准","开火","受击","搜索","失衡","倒地"]
func _ready()->void:
	if not Engine.is_editor_hint():$Frame.value_changed.connect(_frame)
func _frame(value:float)->void:
	$Caption.text="姿态 · "+FRAMES[int(value)]
	for actor in $Cast.get_children():actor.preview_frame=int(value)
