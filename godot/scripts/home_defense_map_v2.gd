extends Control
## A planning chart projected entirely from the native island and its terrain.
signal picked(normalized:Vector2)
signal deployment_selected(id:String)
const COLORS:Dictionary={"beach":Color("e6cd90"),"landing_zone":Color("d8bd83"),"forest":Color("488a61"),"bush":Color("70aa63"),"cliff":Color("9b987b"),"swamp":Color("799b79"),"river":Color("61bed0"),"ford":Color("aad3be")}
var view:Dictionary={}
var existing:Array=[]
var placement:Dictionary={}
var world_rect:Rect2
var marker:Vector2=Vector2.ZERO
var marker_visible:bool=false
var marker_valid:bool=false
var draw_kind:String=""
var dragging:bool=false
func _ready()->void:
	clip_contents=true;mouse_filter=Control.MOUSE_FILTER_STOP;resized.connect(queue_redraw)
func observe(source:Dictionary,saved:Array)->void:
	view=source;existing=saved;placement=view.get("island_war",{}).get("placement",{})
	var bounds:Dictionary=view.get("littoral",{}).get("land",{}).get("bounds",{})
	world_rect=Rect2(float(bounds.get("x",0)),float(bounds.get("y",0)),maxf(1,float(bounds.get("width",1))),maxf(1,float(bounds.get("height",1))))
	queue_redraw()
func _scale()->float:return minf((size.x-36)/world_rect.size.x,(size.y-24)/world_rect.size.y)
func project(p:Vector2)->Vector2:return size*.5+(p-world_rect.get_center())*_scale()
func unproject(p:Vector2)->Vector2:return world_rect.get_center()+(p-size*.5)/maxf(.001,_scale())
func normalized(p:Vector2)->Vector2:
	var origin:Dictionary=placement.get("origin",{});return (p-Vector2(float(origin.get("x",0)),float(origin.get("y",0))))/Vector2(maxf(1,float(placement.get("width_m",1))),maxf(1,float(placement.get("height_m",1))))
func world(n:Vector2)->Vector2:
	var origin:Dictionary=placement.get("origin",{});return Vector2(float(origin.get("x",0)),float(origin.get("y",0)))+n*Vector2(float(placement.get("width_m",0)),float(placement.get("height_m",0)))
func _polygon(raw:Array)->PackedVector2Array:
	var result:PackedVector2Array=[]
	for point in raw:result.append(project(Vector2(float(point.get("x",0)),float(point.get("y",0)))))
	return result
func _gui_input(event:InputEvent)->void:
	if placement.is_empty():return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			if draw_kind.is_empty():
				for entry in existing:
					if project(world(Vector2(float(entry.x),float(entry.y)))).distance_to(event.position)<22:deployment_selected.emit(str(entry.id));accept_event();return
			else:dragging=true;marker=normalized(unproject(event.position));marker_visible=true;marker_valid=false;queue_redraw()
		elif dragging:dragging=false;marker=normalized(unproject(event.position));picked.emit(marker)
		accept_event()
	elif event is InputEventMouseMotion and dragging:marker=normalized(unproject(event.position));queue_redraw();accept_event()
func _symbol(p:Vector2,kind:String,color:Color)->void:
	if kind=="beach_position":draw_rect(Rect2(p-Vector2(10,6),Vector2(20,12)),color,false,3);draw_line(p+Vector2(-14,8),p+Vector2(14,8),color,3)
	else:
		draw_circle(p,7,color);draw_arc(p,12,0,TAU,14,color,2)
		for a in range(4):
			var arm:Vector2=Vector2.from_angle(float(a)*PI*.5+PI*.25);draw_line(p+arm*9,p+arm*15,color,2)
func _draw()->void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("246276"))
	if view.is_empty():return
	var land:Dictionary=view.get("littoral",{}).get("land",{});var polygon:PackedVector2Array=_polygon(land.get("polygon",[]))
	if polygon.size()>=3:draw_colored_polygon(polygon,Color("b9bf89"));draw_polyline(polygon+PackedVector2Array([polygon[0]]),Color("e9d7a3"),4,true)
	for feature in land.get("terrain",{}).get("features",[]):
		var shape:PackedVector2Array=_polygon(feature.get("polygon",[]))
		if shape.size()>=3:draw_colored_polygon(shape,COLORS.get(str(feature.get("kind","")),Color("a4b47e")))
	for building in land.get("buildings",[]):
		var p:Vector2=project(Vector2(float(building.get("x",0)),float(building.get("y",0))));draw_rect(Rect2(p-Vector2(5,5),Vector2(10,10)),Color("fff0c4"));draw_rect(Rect2(p-Vector2(5,5),Vector2(10,10)),Color("5b654c"),false,1)
	if not placement.is_empty():
		for entry in existing:_symbol(project(world(Vector2(float(entry.x),float(entry.y)))),str(entry.kind),Color("f6e9aa"))
		if marker_visible:
			var p:Vector2=project(world(marker));draw_circle(p,24,Color(1,1,1,.20));_symbol(p,draw_kind,Color("bcf6d0") if marker_valid else Color("ffb18c"))
