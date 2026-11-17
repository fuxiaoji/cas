@tool
extends PanelContainer
const Design=preload("res://scripts/ui_design.gd")
@export var pack_id:String="demo-60":
	set(value):
		pack_id=value
		if is_node_ready():refresh_catalog()
@export var use_catalog_content:bool=true
@export var use_default_style:bool=true
func _ready() -> void:
	if theme==null:theme=Design.theme()
	if use_default_style:
		add_theme_stylebox_override("panel",Design.box(Color(1,1,1,.93),3))
		Design.apply_button($Body/Buy,true)
	refresh_catalog()
func refresh_catalog() -> void:
	if not use_catalog_content:return
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/simulated-store.json"))
	for row in data.get("packs",[]):
		if str(row.id)!=pack_id:continue
		$Body/Title.text=str(row.name)
		$Body/Amount.text="%d 元词"%int(row.origins)
		$Body/Price.text=str(row.price_label)
		var art:String=str(row.get("art",""))
		if ResourceLoader.exists(art):$Body/Art.texture=load(art)
