@tool
extends Control
## Preview is advisory. Only the account/native placement command commits cargo.
signal picked(id:String)
signal grabbed(id:String, offset:Vector2i, fraction:Vector2)
signal placed(x:int,y:int,turn:int)
const Service=preload("res://scripts/cargo_service.gd")
const Design=preload("res://scripts/ui_design.gd")
var data:Dictionary={"cols":8,"rows":5,"items":[]}
var selected:String=""
var turn:int=0
@export var cell:float=44.0
var hovered:=Vector2i(-1,-1)
var grab_offset:=Vector2i.ZERO
var dragging:=false
var preview_valid:=false
var preview_reason:=""
func _ready()->void:
	mouse_exited.connect(func():
		if not dragging:hovered=Vector2i(-1,-1);queue_redraw())
func refresh(value:Dictionary,id:String="",facing:int=0)->void:
	data=value;selected=id;turn=facing
	custom_minimum_size=Vector2(int(data.get("cols",8))*cell,int(data.get("rows",5))*cell)
	_evaluate();queue_redraw()
func item_at(p:Vector2i)->Dictionary:
	for item in data.get("items",[]):
		if item.get("placement")!=null and Service.item_cells(item,item.placement).has([p.x,p.y]):return item
	return {}
func current_item()->Dictionary:
	for item in data.get("items",[]):
		if str(item.id)==selected:return item
	return {}
func target()->Array:return [hovered.x-grab_offset.x,hovered.y-grab_offset.y,turn]
func valid_at(item:Dictionary,p:Array)->bool:
	if not Service.new(null).can_fit(data.get("items",[]),item,p,int(data.get("cols",8)),int(data.get("rows",5)),int(data.get("usable_cells",-1))):return false
	return item.get("placement")!=null or not data.has("max_kg") or int(data.get("kg",0))+int(item.get("kg",0))<=int(data.max_kg)
func update_pointer(local:Vector2)->void:
	hovered=Vector2i(floor(local.x/cell),floor(local.y/cell))
	_evaluate();queue_redraw()
func _evaluate()->void:
	var item:=current_item();preview_valid=false;preview_reason=""
	if item.is_empty():return
	var p:=target()
	preview_valid=valid_at(item,p)
	if preview_valid:preview_reason="松开装入" if item.get("placement")==null else "松开放置"
	elif item.get("placement")==null and data.has("max_kg") and int(data.get("kg",0))+int(item.get("kg",0))>int(data.max_kg):preview_reason="超出载重"
	else:preview_reason="此处放不下"
func _gui_input(event:InputEvent)->void:
	if event is InputEventMouseMotion and not dragging:update_pointer(event.position)
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var p:=Vector2i(floor(event.position.x/cell),floor(event.position.y/cell))
		var item:=item_at(p)
		if not item.is_empty():
			picked.emit(str(item.id))
			grabbed.emit(str(item.id),p-Vector2i(int(item.placement[0]),int(item.placement[1])),event.position/cell-Vector2(p))
		elif not selected.is_empty():placed.emit(p.x,p.y,turn)
		accept_event()
func _draw()->void:
	for y in range(int(data.get("rows",0))):
		for x in range(int(data.get("cols",0))):
			var blocked:bool=data.has("usable_cells") and y*int(data.get("cols",8))+x>=int(data.usable_cells)
			var bounds:=Rect2(x*cell+2,y*cell+2,cell-4,cell-4)
			draw_style_box(Design.box(Color("aab5bb") if blocked else Color("e2edf0"),3),bounds)
			if blocked:
				draw_line(bounds.position+Vector2(8,8),bounds.end-Vector2(8,8),Color("7b898f"),2)
				draw_line(Vector2(bounds.end.x-8,bounds.position.y+8),Vector2(bounds.position.x+8,bounds.end.y-8),Color("7b898f"),2)
	for item in data.get("items",[]):
		if item.get("placement")==null:continue
		var points:=Service.item_cells(item,item.placement)
		var first:=Vector2(INF,INF);var last:=Vector2.ZERO
		var shade:Color=Color("9bc9c6") if str(item.kind) in ["scrap","alloy"] else Color("c7bbdb")
		if dragging and str(item.id)==selected:shade.a=.27
		for p in points:
			var origin:=Vector2(float(p[0])*cell,float(p[1])*cell)
			draw_style_box(Design.box(shade,3),Rect2(origin+Vector2(2,2),Vector2.ONE*(cell-4)))
			if str(item.id)==selected:draw_rect(Rect2(origin+Vector2(2,2),Vector2.ONE*(cell-4)),Color("d49e41"),false,2)
			first=first.min(origin);last=last.max(origin+Vector2.ONE*cell)
		var texture:Texture2D=load(Service.art_path(item))
		if texture!=null:
			var bounds:=Rect2(first,last-first).grow(-6)
			var side:=minf(bounds.size.x,bounds.size.y)
			draw_texture_rect(texture,Rect2(bounds.get_center()-Vector2.ONE*side/2.0,Vector2.ONE*side),false,Color(1,1,1,.22 if dragging and str(item.id)==selected else 1.0))
	if selected.is_empty() or hovered.x<0 or hovered.y<0:return
	var item:=current_item()
	if item.is_empty():return
	var color:=Color("2b9b85") if preview_valid else Color("ce5b55")
	for p in Service.item_cells(item,target()):
		var rect:=Rect2(float(p[0])*cell+3,float(p[1])*cell+3,cell-6,cell-6)
		draw_rect(rect,Color(color,.28));draw_rect(rect,color,false,2)
		if not preview_valid:
			draw_line(rect.position+Vector2(9,9),rect.end-Vector2(9,9),color,2)
			draw_line(Vector2(rect.end.x-9,rect.position.y+9),Vector2(rect.position.x+9,rect.end.y-9),color,2)

