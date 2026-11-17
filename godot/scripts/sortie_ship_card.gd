@tool
extends Button
signal ship_dropped(identity:String)
signal touch_armed(identity:String,point:Vector2,pointer:int)
var identity:String=""
var drop_enabled:bool=false
var drag_enabled:bool=true
func _get_drag_data(_point:Vector2)->Variant:
	if not drag_enabled or identity.is_empty():return null
	var preview:=Label.new();preview.text=tooltip_text.get_slice("\n",0);preview.add_theme_font_size_override("font_size",22);set_drag_preview(preview)
	return {"cas_sortie_ship":identity}
func _can_drop_data(_point:Vector2,data:Variant)->bool:
	return drop_enabled and data is Dictionary and data.has("cas_sortie_ship")
func _drop_data(_point:Vector2,data:Variant)->void:ship_dropped.emit(str(data.cas_sortie_ship))
func _gui_input(event:InputEvent)->void:
	if disabled or not drag_enabled or identity.is_empty():return
	if event is InputEventScreenTouch and event.pressed:
		touch_armed.emit(identity,get_global_transform()*event.position,event.index);accept_event()
