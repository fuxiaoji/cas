@tool
extends PanelContainer
const Design=preload("res://scripts/ui_design.gd")
@export var use_default_style:bool=true
func _ready()->void:
	if not use_default_style:return
	var style:=Design.box(Color("edf2f2"),2)
	style.border_width_bottom=1;style.border_color=Color("c7d7d9")
	add_theme_stylebox_override("panel",style)
	Design.apply_button($Body/Action,false,true)
	for label in [$Body/Name,$Body/Doctrine,$Body/Status,$Body/Price]:
		label.add_theme_font_override("font",Design.font(500 if label==$Body/Name else 400))
