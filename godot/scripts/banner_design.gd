extends RefCounted
## Shared image-led navigation and quiet game chrome. Pure presentation.
const Design=preload("res://scripts/ui_design.gd")
const Cinema=preload("res://scripts/cinematic_presentation.gd")
const WHITE:Color=Color("f0f2f2")
const MUTED:Color=Color("b1bcc7")
static func image_tab(app,parent:Control,title:String,asset:String,rect:Rect2,selected:bool,callback:Callable)->Button:
	var button:Button=app.button(parent,"",rect.position.x,rect.position.y,rect.size.x,rect.size.y,callback)
	button.clip_contents=true;button.tooltip_text=title
	for state in ["normal","hover","pressed","focus"]:
		var box=Design.box(Color("161f29"),2,Color("e5dfcd") if selected else Color(.7,.8,.9,.16))
		box.set_border_width_all(2 if selected or state=="focus" else 1);button.add_theme_stylebox_override(state,box)
	if ResourceLoader.exists(asset):
		var art:=TextureRect.new();art.texture=load(asset);art.mouse_filter=Control.MOUSE_FILTER_IGNORE;art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;button.add_child(art);art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);art.modulate=Color(1,1,1,.82 if selected else .4)
	var shade:=ColorRect.new();shade.color=Color(.015,.025,.04,.40);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(shade);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var caption:=Label.new();caption.text=title;caption.add_theme_font_override("font",Design.font(600));caption.add_theme_font_size_override("font_size",23);caption.add_theme_color_override("font_color",WHITE);caption.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(caption);caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);caption.offset_left=18;caption.offset_top=rect.size.y*.45
	if selected:
		var bar:=ColorRect.new();bar.color=Color("e8d19d");bar.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(bar);bar.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE);bar.offset_right=4
	return button
static func chrome(app,parent:Control,title:String)->void:
	Cinema.quiet_button(app,parent,"‹ 返回",34,24,125,app.go_back,true).name="NavigateBack"
	Cinema.quiet_button(app,parent,"母港",165,24,94,app.go_home,true).name="NavigateHome"
	var label:Label=app.label(parent,title,286,24,510,54,27,WHITE);label.add_theme_font_override("font",Design.font(600))
static func chip(app,parent:Control,icon:String,text:String,x:float,width:float)->void:
	app.panel(parent,x,25,width,51,Color(.015,.025,.04,.65))
	app.icon(parent,icon,x+13,36,28,28,Color("e6d9b9"))
	app.label(parent,text,x+49,30,width-58,43,21,WHITE)
