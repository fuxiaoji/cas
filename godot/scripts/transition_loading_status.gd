@tool
extends Control
## A real reported progress line, or an honest indeterminate activity indicator.
var determinate:bool=false
var reduced_motion:bool=false
var clock:float=0
var progress:float=0
func _ready()->void:mouse_filter=Control.MOUSE_FILTER_IGNORE
func set_reduced_motion(value:bool)->void:reduced_motion=value
func set_status(value:float,text:String,known:bool)->void:
	progress=clampf(value,0,1);determinate=known
	get_node("Label").text=text if not text.is_empty() else "正在准备页面"
	get_node("Progress").visible=known;get_node("Progress").value=progress
	queue_redraw()
func _process(delta:float)->void:
	if not visible or determinate or reduced_motion:return
	clock+=delta;queue_redraw()
func _draw()->void:
	if determinate:return
	var center:=Vector2(size.x*.5,62)
	for index in range(3):
		var alpha:float=.65 if reduced_motion else .25+.65*(.5+.5*sin(clock*5-index*1.1))
		draw_circle(center+Vector2((index-1)*18,0),4,Color(.20,.40,.49,alpha))
