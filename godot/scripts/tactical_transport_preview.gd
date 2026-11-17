@tool
extends Control
## F6/Inspector preview of the original per-identity equipment, never a battle fixture.
const Art=preload("res://scripts/tactical_transport_art.gd")
const Design=preload("res://scripts/ui_design.gd")
@export var preview_deploying:bool=false:
	set(value):preview_deploying=value;queue_redraw()
@export var preview_damaged:bool=false:
	set(value):preview_damaged=value;queue_redraw()
var clock:float=0
func _ready()->void:texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS;resized.connect(queue_redraw)
func _process(delta:float)->void:
	if not Engine.is_editor_hint():clock+=delta;queue_redraw()
func _draw()->void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("244550"));Art._load()
	var index:int=0;var cell:=Vector2(size.x/5,(size.y-65)/4)
	draw_string(Design.font(600),Vector2(28,36),"原创载具 · 每连本人专属型号 / Inspector切换投送和受损预览",HORIZONTAL_ALIGNMENT_LEFT,-1,23,Color("e7ead6"))
	for id in Art.catalogue:
		var entry:Dictionary=Art.catalogue[id];var at:Vector2=Vector2((index%5+.5)*cell.x,(floori(index/5.0)+.5)*cell.y+65)
		var row:Dictionary={"unit_id":id,"kind":entry.default_kind,"stage":"deploying" if preview_deploying else "moving","hp":25 if preview_damaged else 100,"max_hp":100}
		Art.paint(self,row,at-Vector2(0,14),minf(116,cell.y*.64),0,clock,false)
		draw_string(Design.font(500),at+Vector2(-cell.x*.46,cell.y*.34),str(id)+" "+str(entry.name),HORIZONTAL_ALIGNMENT_LEFT,cell.x*.92,15,Color("f1ead4"));index+=1
