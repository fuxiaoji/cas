@tool
extends Control
## A shared shape silhouette for the list and the carried ghost.
const Service=preload("res://scripts/cargo_service.gd")
const Design=preload("res://scripts/ui_design.gd")
var item:Dictionary={}
var turn:=0
var unit:=12.0
var show_art:=false
var accepted:=true
func configure(value:Dictionary,facing:int=0,scale_cell:float=12.0,art:bool=false)->void:
	item=value;turn=facing;unit=scale_cell;show_art=art;mouse_filter=Control.MOUSE_FILTER_IGNORE;queue_redraw()
func _draw()->void:
	if item.is_empty():return
	var first:=Vector2(INF,INF);var last:=Vector2.ZERO
	var color:=Color("83c6ba") if accepted else Color("e38c82")
	for p in Service.item_cells(item,[0,0,turn]):
		var rect:=Rect2(Vector2(float(p[0]),float(p[1]))*unit+Vector2.ONE,Vector2.ONE*(unit-2))
		draw_style_box(Design.box(Color(color,.85 if show_art else .65),2),rect)
		draw_rect(rect,Color("ffffff") if show_art else Color("648b91"),false,1)
		first=first.min(rect.position);last=last.max(rect.end)
	if show_art:
		var texture:Texture2D=load(Service.art_path(item))
		if texture!=null:
			var bounds:=Rect2(first,last-first).grow(-4);var side:=minf(bounds.size.x,bounds.size.y)
			draw_texture_rect(texture,Rect2(bounds.get_center()-Vector2.ONE*side/2,Vector2.ONE*side),false,Color(1,1,1,.9))
