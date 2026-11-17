@tool
extends Control
## A living tide dial. Decorative only; no input or simulation state.
@export var ink:Color=Color(0.9,0.85,0.70,0.36)
var seconds:float=0.0
func _process(delta:float)->void:
	if Engine.is_editor_hint():return
	seconds+=delta;queue_redraw()
func _draw()->void:
	var unit:=Vector2(size.x/1600.0,size.y/900.0)
	var center:=Vector2(340,356)*unit
	var radius:=215.0*minf(unit.x,unit.y)
	draw_arc(center,radius,-2.86,-0.95,72,ink,1.0,true)
	draw_arc(center,radius,0.42,1.40,48,ink,1.0,true)
	for i in range(49):
		var angle:float=-2.86+i*TAU/60.0
		if angle>-0.95 and angle<0.42:continue
		if angle>1.4:break
		var normal:=Vector2.from_angle(angle)
		draw_line(center+normal*(radius+5),center+normal*(radius+(13 if i%5==0 else 8)),ink,1.0,true)
	var line_color:=Color(ink,0.65)
	draw_line(Vector2(177,556)*unit,Vector2(454,556)*unit,line_color,1.0,true)
	var beacon:=Vector2(177,556)*unit
	draw_colored_polygon(PackedVector2Array([beacon+Vector2(0,-5),beacon+Vector2(4,0),beacon+Vector2(0,5),beacon+Vector2(-4,0)]),ink)
	for i in range(28):
		var x:=fmod(625.0+i*127.13+seconds*(2.0+i%3),1560.0)
		var y:=645.0+fmod(i*53.71,210.0)+sin(seconds*.22+i)*3.0
		var opacity:=0.08+0.07*sin(seconds*.45+i*1.7)
		draw_line(Vector2(x,y)*unit,Vector2(x+8.0+i%9,y)*unit,Color(0.88,0.95,0.89,opacity),1.0,true)
