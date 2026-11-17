@tool
extends Control
## Original nautical rank insignia, independently editable from the arena screen.
@export var rank_color:Color=Color("bc9564"):
	set(value):rank_color=value;queue_redraw()
@export_range(0,7,1) var rank_index:int=0:
	set(value):rank_index=value;queue_redraw()
func _draw()->void:
	var center:=size*.5
	var unit:=minf(size.x,size.y)/180.0
	var points:=PackedVector2Array()
	for point in [Vector2(0,-72),Vector2(55,-46),Vector2(48,25),Vector2(0,69),Vector2(-48,25),Vector2(-55,-46)]:points.append(center+point*unit)
	draw_colored_polygon(points,Color(.035,.12,.20,.92))
	var outline:=points.duplicate();outline.append(points[0]);draw_polyline(outline,rank_color,2.0*unit,true)
	for side in [-1,1]:
		for leaf in range(5):
			var angle:=deg_to_rad(42+leaf*20.0)
			var at:=center+Vector2(side*sin(angle)*72,cos(angle)*61)*unit
			var tip:=at+Vector2(side*11,-12)*unit
			draw_line(at,tip,Color(rank_color,.8),3*unit,true)
	var compass:=PackedVector2Array([center+Vector2(0,-47)*unit,center+Vector2(20,13)*unit,center+Vector2(0,3)*unit,center+Vector2(-20,13)*unit])
	draw_colored_polygon(compass,rank_color)
	draw_line(center+Vector2(0,-41)*unit,center+Vector2(0,34)*unit,Color("e8f0ee"),1.3*unit,true)
	draw_arc(center,29*unit,0,TAU,48,Color(rank_color,.55),unit,true)
	var gems:=mini(rank_index+1,6)
	for i in range(gems):
		var at:=center+Vector2((float(i)-float(gems-1)*.5)*10,43)*unit
		draw_colored_polygon(PackedVector2Array([at+Vector2(0,-3)*unit,at+Vector2(3,0)*unit,at+Vector2(0,3)*unit,at+Vector2(-3,0)*unit]),rank_color)
