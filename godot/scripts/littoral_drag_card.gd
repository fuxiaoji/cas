extends PanelContainer
const TypeToken=preload("res://scripts/tactical_type_token.gd")
const FormationMark=preload("res://scripts/tactical_formation_mark.gd")
signal armed(payload:Dictionary,point:Vector2,pointer:int)
var payload:Dictionary={}
var enabled:bool=true
var status:Label
var portrait:TextureRect
var title_label:Label
var type_badge:Control
var designation_label:Label
var company_label:Label
var panel_style:StyleBoxFlat
var compact_information:bool=false
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_STOP;focus_mode=Control.FOCUS_ALL
	var style:=StyleBoxFlat.new();style.bg_color=Color("163d49");style.border_color=Color("537d82");style.set_border_width_all(1);style.set_corner_radius_all(8);style.content_margin_left=10;style.content_margin_right=10;style.content_margin_top=5;style.content_margin_bottom=5;add_theme_stylebox_override("panel",style)
	panel_style=style
	var box:=VBoxContainer.new();box.mouse_filter=Control.MOUSE_FILTER_IGNORE;box.add_theme_constant_override("separation",1);add_child(box)
	portrait=TextureRect.new();portrait.custom_minimum_size=Vector2(95,70);portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE;portrait.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS;box.add_child(portrait)
	type_badge=TypeToken.new();type_badge.name="UnitType";portrait.add_child(type_badge)
	type_badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT);type_badge.offset_left=-44;type_badge.offset_top=-34;type_badge.offset_right=0;type_badge.offset_bottom=0;type_badge.mouse_filter=Control.MOUSE_FILTER_IGNORE;type_badge.visible=false
	title_label=Label.new();title_label.name="Title";title_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title_label.add_theme_font_size_override("font_size",19);title_label.add_theme_color_override("font_color",Color("f0efdd"));title_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;box.add_child(title_label)
	designation_label=Label.new();designation_label.name="Designation";designation_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;designation_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;designation_label.max_lines_visible=2;designation_label.custom_minimum_size.x=112;designation_label.add_theme_font_size_override("font_size",14);designation_label.add_theme_color_override("font_color",Color("c9dacf"));designation_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;designation_label.visible=false;box.add_child(designation_label)
	company_label=Label.new();company_label.name="Company";company_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;company_label.add_theme_font_size_override("font_size",14);company_label.add_theme_color_override("font_color",Color("f4dc9a"));company_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;company_label.visible=false;box.add_child(company_label)
	status=Label.new();status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;status.add_theme_font_size_override("font_size",15);status.add_theme_color_override("font_color",Color("bdccbd"));status.mouse_filter=Control.MOUSE_FILTER_IGNORE;box.add_child(status)
func configure(value:Dictionary,text:String,allowed:bool=true)->void:
	payload=value;enabled=allowed
	if portrait==null:return
	portrait.texture=payload.get("texture");title_label.text=str(payload.get("name","部队"));status.text=text;tooltip_text=str(payload.get("reason",text))
	type_badge.visible=str(payload.get("kind","")) in ["unit","vehicle"]
	designation_label.visible=type_badge.visible and not str(payload.get("designation","")).is_empty();designation_label.text=str(payload.get("designation",""))
	company_label.visible=type_badge.visible and payload.has("company_id");company_label.text=str(payload.get("company_caption",payload.get("company_name","")))
	if compact_information!=designation_label.visible:
		compact_information=designation_label.visible
		portrait.custom_minimum_size.y=36 if compact_information else 70
		title_label.add_theme_font_size_override("font_size",18 if compact_information else 19);status.add_theme_font_size_override("font_size",12 if compact_information else 15)
	panel_style.border_color=Color("ecd18b") if bool(payload.get("selected",false)) else Color("537d82")
	if type_badge.visible:
		var role:String=str(payload.get("role",payload.get("nato_type","infantry")))
		var formation:Dictionary=FormationMark.resolve(payload)
		type_badge.configure(role,"friendly",bool(payload.get("selected",false)),str(formation.echelon))
		tooltip_text=TypeToken.role_name(role)+" · "+tooltip_text
		if not str(formation.label).is_empty():tooltip_text=str(formation.label)+" · "+tooltip_text
	modulate=Color.WHITE if allowed else Color(.67,.72,.72,1)
func _gui_input(event:InputEvent)->void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:armed.emit(payload,get_global_transform()*event.position,-1);accept_event()
	elif event is InputEventScreenTouch and event.pressed:armed.emit(payload,get_global_transform()*event.position,event.index);accept_event()
