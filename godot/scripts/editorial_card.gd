@tool
extends Control
## The exact runtime card is also an editable Godot component.
const Design=preload("res://scripts/ui_design.gd")
@export_file("*.png") var artwork:String="":
	set(value):artwork=value;_refresh()
@export var title:String="新的航程":
	set(value):title=value;_refresh()
@export var subtitle:String="":
	set(value):subtitle=value;_refresh()
@export var route:String="canon_catalog"
var app
func _ready()->void:
	$Title.add_theme_font_override("font",Design.font(600));_refresh()
	$Action.pressed.connect(func():if app!=null:app.show_page(route))
	for state in ["normal","hover","pressed","focus"]:
		var style=Design.box(Color(0,0,0,0),2,Color("e0cba0") if state!="normal" else Color(1,1,1,.2));style.set_border_width_all(2 if state!="normal" else 1);$Action.add_theme_stylebox_override(state,style)
func _refresh()->void:
	if not is_node_ready():return
	$Artwork.texture=load(artwork) if ResourceLoader.exists(artwork) else null
	$Title.text=title;$Subtitle.text=subtitle;$Action.tooltip_text=title
func bind(owner,path:String,headline:String,detail:String,destination:String)->void:
	app=owner;artwork=path;title=headline;subtitle=detail;route=destination
