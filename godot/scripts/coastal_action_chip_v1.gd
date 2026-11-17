extends PanelContainer
## Small draggable command, sharing the same pointer lifecycle as company cards.
signal armed(payload:Dictionary,point:Vector2,pointer:int)
var payload:Dictionary={}
var caption:Label
var detail:Label
var skin:StyleBoxFlat
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_STOP;focus_mode=Control.FOCUS_ALL
	custom_minimum_size=Vector2(104,54)
	skin=StyleBoxFlat.new();skin.bg_color=Color("173f49");skin.border_color=Color("577b7b");skin.set_border_width_all(1);skin.set_corner_radius_all(7)
	skin.content_margin_left=10;skin.content_margin_right=10;skin.content_margin_top=4;skin.content_margin_bottom=4;add_theme_stylebox_override("panel",skin)
	var stack:=VBoxContainer.new();stack.mouse_filter=Control.MOUSE_FILTER_IGNORE;stack.add_theme_constant_override("separation",0);add_child(stack)
	caption=Label.new();caption.mouse_filter=Control.MOUSE_FILTER_IGNORE;caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;caption.add_theme_font_size_override("font_size",18);caption.add_theme_color_override("font_color",Color("f2efd9"));stack.add_child(caption)
	detail=Label.new();detail.mouse_filter=Control.MOUSE_FILTER_IGNORE;detail.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;detail.add_theme_font_size_override("font_size",12);detail.add_theme_color_override("font_color",Color("bdd3ca"));stack.add_child(detail)
func configure(value:Dictionary,title:String,subtitle:String,available:bool=true)->void:
	payload=value;caption.text=title;detail.text=subtitle;tooltip_text=str(value.get("reason",subtitle))
	modulate=Color.WHITE if available else Color(.67,.73,.73)
	skin.border_color=Color("efd38a") if bool(value.get("selected",false)) else Color("577b7b")
func _gui_input(event:InputEvent)->void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:armed.emit(payload,get_global_transform()*event.position,-1);accept_event()
	elif event is InputEventScreenTouch and event.pressed:armed.emit(payload,get_global_transform()*event.position,event.index);accept_event()
