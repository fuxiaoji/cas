@tool
extends Control
## Inspector/F6 gallery of reusable modules, not a fixed battle map.
const Town=preload("res://scripts/procedural_town.gd")
const Design=preload("res://scripts/ui_design.gd")
@export_range(3,6,1) var columns:int=6:
	set(value):columns=value;queue_redraw()
@export var show_props:bool=true:
	set(value):show_props=value;queue_redraw()
func _ready()->void:
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	resized.connect(queue_redraw);queue_redraw()
func _draw()->void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("507a75"))
	var font:Font=Design.font(500)
	draw_string(font,Vector2(28,37),"沿海城镇 · 可重组建筑与道路道具",HORIZONTAL_ALIGNMENT_LEFT,-1,24,Color("f6e8c9"))
	var groups:Array[String]=["buildings","props"] if show_props else ["buildings"]
	var rows:int=ceili(12.0/columns)
	var cell:Vector2=Vector2((size.x-48)/columns,(size.y-80)/(rows*groups.size()))
	for group in range(groups.size()):
		for index in range(12):
			var texture:Texture2D=Town._art(groups[group],index)
			if texture==null:continue
			var row:int=index/columns
			var tile_origin:Vector2=Vector2(24+(index%columns)*cell.x,65+(group*rows+row)*cell.y)
			var scale:float=minf((cell.x-20)/texture.get_width(),(cell.y-26)/texture.get_height())
			var dimensions:Vector2=texture.get_size()*scale
			draw_texture_rect(texture,Rect2(tile_origin+Vector2((cell.x-dimensions.x)*.5,cell.y-23-dimensions.y),dimensions),false)
			draw_string(font,tile_origin+Vector2(8,cell.y-5),"%s %02d"%["建筑" if group==0 else "道具",index+1],HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("f1ebd5"))
