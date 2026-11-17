@tool
extends Control
## F6/Inspector gallery: every pose keeps its original person's identity.
const CasualtyArt=preload("res://scripts/tactical_casualty_art.gd")
const AircraftArt=preload("res://scripts/littoral_aircraft_art.gd")
const Token=preload("res://scripts/tactical_type_token.gd")
const Design=preload("res://scripts/ui_design.gd")
@export_range(35,100,1) var figure_size:float=70:
	set(value):figure_size=value;queue_redraw()
@export var show_aircraft:bool=true:
	set(value):show_aircraft=value;queue_redraw()
func _ready()->void:
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS;resized.connect(queue_redraw);queue_redraw()
func _draw()->void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("35545b"))
	var font:Font=Design.font(500);var ids:Array=["MCP-034","MCP-001","MCP-076","MCP-009","MCP-022"]
	draw_string(font,Vector2(24,32),"本人倒地姿态 / pose_seed 固定取帧",HORIZONTAL_ALIGNMENT_LEFT,-1,23,Color("f0e9cf"))
	for column in range(ids.size()):
		var x:float=(column+.5)*size.x/5
		draw_string(font,Vector2(x-42,64),str(ids[column]),HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("e0eee1"))
		for pose in range(3):
			draw_set_transform(Vector2(x,125+pose*110))
			CasualtyArt.paint(self,{"unit_id":ids[column],"side":"allies","pose_seed":pose},figure_size)
			draw_set_transform(Vector2.ZERO)
	for index in range(4):
		var kind:String=["land_rust_crab","land_cult_sentinel","land_spore_hound","land_siege_drone"][index]
		var at:=Vector2(size.x*(index+.5)/4,490)
		draw_set_transform(at);CasualtyArt.paint_land_enemy(self,{"kind":kind},3,figure_size);draw_set_transform(Vector2.ZERO)
	if show_aircraft:
		var types:Array=["F4F","SBD","TBD","A6M2","D3A2","B5N2","support_helicopter","attack_helicopter"]
		for index in range(types.size()):
			var at:=Vector2(size.x*(index+.5)/8,620)
			AircraftArt.paint(self,{"visual_type":types[index],"side":"allies","heading":0},at,figure_size)
			draw_string(font,at+Vector2(-27,55),str(types[index]).trim_suffix("_helicopter"),HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("ebecd5"))
